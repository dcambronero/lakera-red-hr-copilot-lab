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

function Invoke-Az {
  param([Parameter(ValueFromRemainingArguments = $true)] [string[]] $Arguments)
  $result = & az @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "Azure CLI command failed: az $($Arguments -join ' ')"
  }
  return $result
}

Invoke-Az bicep build --file (Join-Path $infraPath 'main.bicep') | Out-Null
Invoke-Az bicep build --file (Join-Path $infraPath 'workload.bicep') | Out-Null

$account = Invoke-Az account show --query '{subscription:id,name:name,user:user.name}' -o json | ConvertFrom-Json
if (-not $account.subscription) {
  throw 'No active Azure session. Run az login first.'
}
Write-Host "Using active Azure subscription: $($account.name) ($($account.subscription))"
Invoke-Az group create --name $ResourceGroup --location $Location | Out-Null

$adminPassword = Read-Host 'Ubuntu password (will not be saved)' -AsSecureString
$adminPasswordText = [System.Net.NetworkCredential]::new('', $adminPassword).Password
$openAiApiKey = Read-Host 'OpenAI API key (will not be saved)' -AsSecureString
$openAiApiKeyText = [System.Net.NetworkCredential]::new('', $openAiApiKey).Password
$labToken = [guid]::NewGuid().ToString('N')

Write-Host 'Deploying network, Bastion, Ubuntu VM, ACR, Key Vault and Container Apps environment...'
$core = Invoke-Az deployment group create `
  --name '${Prefix}-core' `
  --resource-group $ResourceGroup `
  --template-file (Join-Path $infraPath 'main.bicep') `
  --parameters prefix=$Prefix adminUsername=$AdminUsername adminPassword=$adminPasswordText `
  --query properties.outputs -o json | ConvertFrom-Json

$registryName = $core.registryName.value
$environmentId = $core.acaEnvironmentId.value
$appName = "$Prefix-hr-copilot"

Write-Host 'Building the HR Copilot image in Azure Container Registry...'
Push-Location $repoRoot
try {
  Invoke-Az acr build --registry $registryName --image hr-copilot:latest --file Dockerfile .
} finally {
  Pop-Location
}

Write-Host 'Deploying the private HR Copilot...'
$workload = Invoke-Az deployment group create `
  --name '${Prefix}-workload' `
  --resource-group $ResourceGroup `
  --template-file (Join-Path $infraPath 'workload.bicep') `
  --parameters appName=$appName environmentId=$environmentId registryName=$registryName openAiApiKey=$openAiApiKeyText labToken=$labToken `
  --query properties.outputs -o json | ConvertFrom-Json

$keyVaultName = $core.keyVaultName.value
$keyVaultId = Invoke-Az keyvault show --name $keyVaultName --query id -o tsv
$deployerObjectId = Invoke-Az ad signed-in-user show --query id -o tsv
Invoke-Az role assignment create --assignee-object-id $deployerObjectId --assignee-principal-type User --role 'Key Vault Secrets Officer' --scope $keyVaultId | Out-Null
Invoke-Az keyvault secret set --vault-name $keyVaultName --name lab-token --value $labToken | Out-Null

Write-Host ''
Write-Host 'Deployment complete.' -ForegroundColor Green
Write-Host "Bastion: $($core.bastionName.value)"
Write-Host "VM:      $($core.vmName.value)"
Write-Host "Agent:   https://$($workload.agentFqdn.value)/api/chat (private; reachable only from the VNet)"
Write-Host "Token:   saved as Key Vault secret '$keyVaultName/lab-token'"
Write-Host 'Next: connect to the VM through Azure Bastion and follow docs/02-lakera-red-exercise.md.'
