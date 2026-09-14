[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)] [string] $ResourceGroup,
  [Parameter(Mandatory = $true)] [string] $Location,
  [Parameter(Mandatory = $true)] [ValidatePattern('^[a-z0-9]{3,12}$')] [string] $Prefix,
  [string] $AdminUsername = 'labadmin'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$infraPath = Join-Path $repoRoot 'infra'

function Format-AzArgumentsForError {
  param([Parameter(Mandatory = $true)] [string[]] $AzArguments)

  $redactNext = $false

  $safeArguments = foreach ($argument in $AzArguments) {
    if ($redactNext) {
      $redactNext = $false
      '***REDACTED***'
      continue
    }

    if ($argument -in @('--value', '--password', '--client-secret')) {
      $redactNext = $true
      $argument
      continue
    }

    if ($argument -match '^(adminPassword|openAiApiKey|labToken)=') {
      (($argument -split '=', 2)[0] + '=***REDACTED***')
      continue
    }

    $argument
  }

  return ($safeArguments -join ' ')
}

function Invoke-Az {
  param([Parameter(Mandatory = $true)] [string[]] $AzArguments)

  $result = & az @AzArguments

  if ($LASTEXITCODE -ne 0) {
    throw "Azure CLI command failed: az $(Format-AzArgumentsForError -AzArguments $AzArguments)"
  }

  return $result
}

Invoke-Az -AzArguments @(
  'bicep',
  'build',
  '--file',
  (Join-Path $infraPath 'main.bicep')
) | Out-Null

Invoke-Az -AzArguments @(
  'bicep',
  'build',
  '--file',
  (Join-Path $infraPath 'workload.bicep')
) | Out-Null

$account = Invoke-Az -AzArguments @(
  'account',
  'show',
  '--query',
  '{subscription:id,name:name,user:user.name}',
  '-o',
  'json'
) | ConvertFrom-Json

if (-not $account.subscription) {
  throw 'No active Azure session. Run az login first.'
}

Write-Host "Using active Azure subscription: $($account.name) ($($account.subscription))"

Invoke-Az -AzArguments @(
  'group',
  'create',
  '--name',
  $ResourceGroup,
  '--location',
  $Location
) | Out-Null

$labInstanceIdResult = Invoke-Az -AzArguments @(
  'group',
  'show',
  '--name',
  $ResourceGroup,
  '--query',
  'tags.lakeraRedLabId',
  '-o',
  'tsv'
)

if ($null -eq $labInstanceIdResult) {
  $labInstanceId = ''
} else {
  $labInstanceId = ([string]$labInstanceIdResult).Trim()
}

if ([string]::IsNullOrWhiteSpace($labInstanceId) -or $labInstanceId -eq 'null') {
  $labInstanceId = [guid]::NewGuid().ToString('N')

  Invoke-Az -AzArguments @(
    'group',
    'update',
    '--name',
    $ResourceGroup,
    '--set',
    "tags.lakeraRedLabId=$labInstanceId"
  ) | Out-Null
}

Write-Host "Using stable lab instance ID: $labInstanceId"

$adminPassword = Read-Host 'Ubuntu password (will not be saved)' -AsSecureString
$adminPasswordText = [System.Net.NetworkCredential]::new('', $adminPassword).Password

$openAiApiKey = Read-Host 'OpenAI API key (will not be saved)' -AsSecureString
$openAiApiKeyText = [System.Net.NetworkCredential]::new('', $openAiApiKey).Password

$labToken = [guid]::NewGuid().ToString('N')

Write-Host 'Deploying network, Bastion, Ubuntu VM, ACR, Key Vault and Container Apps environment...'

$coreArguments = @(
  'deployment',
  'group',
  'create',
  '--name',
  "${Prefix}-core",
  '--resource-group',
  $ResourceGroup,
  '--template-file',
  (Join-Path $infraPath 'main.bicep'),
  '--parameters',
  "prefix=${Prefix}",
  "adminUsername=${AdminUsername}",
  "adminPassword=${adminPasswordText}",
  "labInstanceId=${labInstanceId}",
  '--query',
  'properties.outputs',
  '-o',
  'json'
)

$core = Invoke-Az -AzArguments $coreArguments | ConvertFrom-Json

$registryName = $core.registryName.value
$environmentId = $core.acaEnvironmentId.value
$appName = "$Prefix-hr-copilot"

Write-Host 'Building the HR Copilot image in Azure Container Registry...'

Push-Location $repoRoot

try {
  Invoke-Az -AzArguments @(
    'acr',
    'build',
    '--registry',
    $registryName,
    '--image',
    'hr-copilot:latest',
    '--file',
    'Dockerfile',
    '.'
  )
} finally {
  Pop-Location
}

Write-Host 'Deploying the private HR Copilot...'

$workloadArguments = @(
  'deployment',
  'group',
  'create',
  '--name',
  "${Prefix}-workload",
  '--resource-group',
  $ResourceGroup,
  '--template-file',
  (Join-Path $infraPath 'workload.bicep'),
  '--parameters',
  "appName=${appName}",
  "environmentId=${environmentId}",
  "registryName=${registryName}",
  "openAiApiKey=${openAiApiKeyText}",
  "labToken=${labToken}",
  '--query',
  'properties.outputs',
  '-o',
  'json'
)

$workload = Invoke-Az -AzArguments $workloadArguments | ConvertFrom-Json

$keyVaultName = $core.keyVaultName.value

$keyVaultId = Invoke-Az -AzArguments @(
  'keyvault',
  'show',
  '--name',
  $keyVaultName,
  '--query',
  'id',
  '-o',
  'tsv'
)

$deployerObjectId = Invoke-Az -AzArguments @(
  'ad',
  'signed-in-user',
  'show',
  '--query',
  'id',
  '-o',
  'tsv'
)

Invoke-Az -AzArguments @(
  'role',
  'assignment',
  'create',
  '--assignee-object-id',
  $deployerObjectId,
  '--assignee-principal-type',
  'User',
  '--role',
  'Key Vault Secrets Officer',
  '--scope',
  $keyVaultId
) | Out-Null

Invoke-Az -AzArguments @(
  'keyvault',
  'secret',
  'set',
  '--vault-name',
  $keyVaultName,
  '--name',
  'lab-token',
  '--value',
  $labToken
) | Out-Null

Write-Host ''
Write-Host 'Deployment complete.' -ForegroundColor Green
Write-Host "Bastion: $($core.bastionName.value)"
Write-Host "VM:      $($core.vmName.value)"
Write-Host "Agent:   https://$($workload.agentFqdn.value)/api/chat (private; reachable only from the VNet)"
Write-Host "Token:   saved as Key Vault secret '$keyVaultName/lab-token'"
Write-Host 'Next: connect to the VM through Azure Bastion and follow docs/02-lakera-red-sdk-training.md.'