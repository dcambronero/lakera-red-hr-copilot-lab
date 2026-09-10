[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory = $true)] [string] $ResourceGroup)

if ($PSCmdlet.ShouldProcess($ResourceGroup, 'Delete Azure resource group and all lab resources')) {
  az group delete --name $ResourceGroup --yes --no-wait
  Write-Host "Deletion started for resource group $ResourceGroup."
}
