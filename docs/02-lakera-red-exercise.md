# Lakera Red SDK exercise

This exercise deliberately starts with no Lakera Red SDK installed or configured on the Ubuntu VM.

## 1. Connect and retrieve the lab connection values

Connect to the `sdk-vm` through Azure Bastion. The VM has no public IP. Use the Lab Token stored in Key Vault and the private Agent URL printed by `deploy.ps1`.

```bash
az login --identity
LAB_TOKEN=$(az keyvault secret show --vault-name <key-vault-name> --name lab-token --query value -o tsv)
```

## 2. Clone and install the SDK

```bash
git clone <your-github-repository-url>
cd lakera-red-hr-copilot-lab/sdk-runner
npm install
cp .env.example .env
chmod 600 .env
```

Populate `.env` with the Red Team API key from the Lakera Red portal, the private FQDN from deployment, and the Lab Token. Example:

```text
LAKERA_RED_API_KEY=<Red Team API key>
AGENT_URL=https://<internal-container-app-fqdn>/api/chat
AGENT_TOKEN=<Lab Token>
```

## 3. Validate the target contract

```bash
set -a; source .env; set +a
npm run validate
```

The validation proves the VM can reach the agent, the agent authentication works, and the target implements `{ message, sessionId }`.

## 4. Run a controlled scan

Start with the configured low concurrency and objectives. The runner uses outbound HTTPS to `red-webhooks.lakera.ai`; it does not expose a listener.

```bash
npm run scan
```

Review the dashboard link printed by the runner and `red-results.json`. The expected findings are system prompt extraction, instruction override, indirect prompt injection through RAG, PII leakage and tool enumeration.

## Customer translation

For a customer, replace only these elements:

1. `AGENT_URL`, `AGENT_TOKEN`, and proxy/corporate CA environment variables.
2. `callAgent()` in `run-sdk-scan.js` to match the customer API request, authentication and response format.
3. `app-context.yaml` with customer-approved allowed and forbidden actions. Include system prompt/tool ground truth only when explicitly authorized.
4. Objectives, strategy and concurrency according to the approved scope and the target's capacity.
