# Lakera Red HR Copilot Lab for Azure

A reproducible Azure lab for training Check Point Security Engineers to assess an intentionally vulnerable HR agent. The infrastructure is provisioned with Bicep; the assessment implementation exercise is delivered separately from this repository.

## Architecture

```text
SE ── Azure Bastion ── Ubuntu assessment VM ── private HTTPS ── HR Copilot
                                                               │
                                                               └── OpenAI API
```

The Ubuntu VM has no public IP. Azure Bastion provides RDP access. It has Internet access and private HTTPS access to the agent. The Container Apps Environment has an internal load balancer; the HR Copilot's ingress is reachable only from the VNet. The deployment creates and links the required private DNS zone automatically.

## Deploy

This script is run **once by the lab owner/administrator**, not by each SE. Follow the complete [lab owner deployment guide](docs/00-lab-owner-deployment.md), including the corporate PowerShell signing-policy note. From VS Code PowerShell, after authenticating with `az login`:

```powershell
./scripts/deploy.ps1 `
  -ResourceGroup 'rg-lakera-red-lab' `
  -Location 'eastus' `
  -Prefix 'lkrhrlab'
```

The script uses the active subscription selected by `az login` / `az account set`. It prompts separately for the Ubuntu password and OpenAI API key, then generates a Lab Token. None is committed to the repository. Each SE only needs the Bastion access details and the separately delivered assessment exercise.

After deployment, grant Bastion access to the SEs. They follow [the Security Engineer access guide](docs/01-security-engineer-access.md) and then the separately delivered assessment exercise. They do not run `deploy.ps1`.

## Intentional vulnerabilities

This lab is unsafe by design and must never be converted into a production HR application. It includes overly permissive tool behavior, confidential employee records, a retrievable indirect-prompt-injection document, weak authorization assumptions and prompt/tool disclosure paths.

## Clean up

```powershell
./scripts/destroy.ps1 -ResourceGroup 'rg-lakera-red-lab' -Confirm
```
