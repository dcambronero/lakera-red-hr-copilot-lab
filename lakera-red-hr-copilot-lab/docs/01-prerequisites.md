# Prerequisites

Install on the workstation running VS Code:

- Azure CLI and an authenticated Azure subscription
- PowerShell 7+
- Git
- The VS Code extensions **Azure Resources**, **Bicep**, **Docker** and **PowerShell**

The deployment creates billable Azure resources: Azure Bastion, NAT Gateway, Standard public IPs, Container Apps Environment, Container Registry, Log Analytics, Key Vault and a B2s Ubuntu VM. Destroy the resource group when the training is complete.

Do not place OpenAI, Lakera Red, Azure or agent API credentials in source files, `app-context.yaml`, issue trackers, screenshots or Git commits.
