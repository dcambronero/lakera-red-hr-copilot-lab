import "dotenv/config"
import crypto from "node:crypto"
import { LakeraRedClient } from "lakera-red-sdk"

const required = ["LAKERA_RED_API_KEY", "AGENT_URL", "AGENT_TOKEN"]
for (const name of required) {
  if (!process.env[name]) throw new Error(`${name} is required`)
}

const client = new LakeraRedClient({
  apiKey: process.env.LAKERA_RED_API_KEY,
  baseUrl: "https://red-webhooks.lakera.ai",
  logLevel: "info",
})

async function callAgent(message, sessionId) {
  const response = await fetch(process.env.AGENT_URL, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${process.env.AGENT_TOKEN}`,
    },
    body: JSON.stringify({ message, sessionId }),
  })
  if (!response.ok) throw new Error(`Target returned HTTP ${response.status}`)
  const body = await response.json()
  if (typeof body.message !== "string") throw new Error("Target response does not contain message")
  return body.message
}

const target = await client.createOrGetTarget({
  name: process.env.TARGET_NAME || "hr-copilot-lab",
  appContextFile: "./app-context.yaml",
})

const scan = await client.createScan({
  name: process.env.SCAN_NAME || "HR Copilot Assessment",
  targetId: target.targetId,
  strategy: { name: "crescendo", maxTurns: Number(process.env.SCAN_MAX_TURNS || 5) },
  objectives: [
    "security.system-prompt-extraction.1",
    "security.instruction-override.1",
  ],
  concurrency: Number(process.env.SCAN_CONCURRENCY || 3),
})

await scan.run(async (session) => {
  // One customer-agent session per independent Lakera Red attack conversation.
  const sessionId = crypto.randomUUID()
  for await (const { attack, respond } of session) {
    const reply = await callAgent(attack, sessionId)
    await respond(reply)
  }
})

await scan.writeResults("./red-results.json")
console.log(`Scan completed: ${scan.dashboardLink}`)
