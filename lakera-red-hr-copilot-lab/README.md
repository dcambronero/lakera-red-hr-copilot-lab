# Lakera Red HR Copilot Lab for Azure

A reproducible Azure lab for training Check Point Security Engineers to run **Lakera Red SDK** assessments against an intentionally vulnerable HR agent. The infrastructure is provisioned with Bicep; the SDK is intentionally not installed or configured on the Ubuntu runner VM.

## Architecture

```text
SE ── Azure Bastion ── Ubuntu SDK runner ── private HTTPS ── HR Copilot
                              │                                │
                              └── outbound HTTPS ── Lakera Red  └── OpenAI API
```

The Ubuntu VM has no public IP. Azure Bastion provides RDP access. The SDK runner only needs outbound TCP/443 to `red-webhooks.lakera.ai` and private HTTPS access to the agent.

## Deploy

This script is run **once by the lab owner/administrator**, not by each SE. From VS Code PowerShell, after authenticating with `az login`:

```powershell
./scripts/deploy.ps1 `
  -ResourceGroup 'rg-lakera-red-lab' `
  -Location 'eastus' `
  -Prefix 'lkrhrlab'
```

The script uses the active subscription selected by `az login` / `az account set`. It prompts separately for the Ubuntu password and OpenAI API key, then generates a Lab Token. None is committed to the repository. Each SE only needs the Bastion access details and the instructions in the SDK exercise.

After deployment, connect to the VM in Azure Portal through Bastion, clone this repository and follow [the SDK exercise](docs/02-lakera-red-exercise.md).

## Intentional vulnerabilities

This lab is unsafe by design and must never be converted into a production HR application. It includes overly permissive tool behavior, confidential employee records, a retrievable indirect-prompt-injection document, weak authorization assumptions and prompt/tool disclosure paths.

## Clean up

```powershell
./scripts/destroy.ps1 -ResourceGroup 'rg-lakera-red-lab' -Confirm
```
