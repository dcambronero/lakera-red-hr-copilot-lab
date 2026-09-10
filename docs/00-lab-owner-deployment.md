# Deployment guide — Lab owner only

This guide is for the person who owns the Azure subscription and deploys the shared training environment. **Security Engineers do not run `deploy.ps1`.** Their workflow starts after the environment exists, by connecting to the Ubuntu VM through Azure Bastion and following the separately delivered assessment exercise.

## 1. Download and open the project

Extract the project and open the inner `lakera-red-hr-copilot-lab` folder in VS Code. It must contain `scripts`, `infra`, `src` and `README.md`.

## 2. Sign-in to Azure

```powershell
az login
```

The deployment uses the active subscription selected by `az login`. If multiple subscriptions are available, select the intended one before deployment:

```powershell
az account list -o table
az account set --subscription '<subscription-id>'
```

## 3. Corporate PowerShell execution policies

Windows may mark downloaded scripts as unsigned. If organizational policy allows it, enable execution only for the current PowerShell process and remove the downloaded-file mark:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Unblock-File .\scripts\deploy.ps1
```

This does not change the machine-wide policy; it ends when the PowerShell window closes. If a Group Policy still blocks execution, do not try to bypass it. Ask the corporate endpoint/security administrator to approve or code-sign the deployment script.

## 4. Deploy

```powershell
.\scripts\deploy.ps1 `
  -ResourceGroup 'rg-lakera-red-lab' `
  -Location 'eastus' `
  -Prefix 'lkrhrlab'
```

The script securely prompts for the Ubuntu password and OpenAI API key. It creates the Azure infrastructure once, generates a Lab Token and stores it in Key Vault.

## 5. Hand off to SEs

Provide each SE only:

- Bastion access to the Ubuntu VM.
- The GitHub repository URL.
- The Key Vault name and permission to read the Lab Token through the VM managed identity.
- The separately delivered assessment exercise.

Do not give SEs the Azure subscription deployment role, the OpenAI API key, or the Ubuntu administrator password.
