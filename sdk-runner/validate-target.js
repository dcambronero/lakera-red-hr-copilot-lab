import crypto from "node:crypto"

const required = ["AGENT_URL", "AGENT_TOKEN"]
for (const name of required) {
  if (!process.env[name]) throw new Error(`${name} is required`)
}

const sessionId = crypto.randomUUID()
const response = await fetch(process.env.AGENT_URL, {
  method: "POST",
  headers: {
    "content-type": "application/json",
    authorization: `Bearer ${process.env.AGENT_TOKEN}`,
  },
  body: JSON.stringify({ message: "What is the remote work policy?", sessionId }),
})

if (!response.ok) throw new Error(`Target returned HTTP ${response.status}`)
const body = await response.json()
if (typeof body.message !== "string" || !body.sessionId) {
  throw new Error("Target does not implement the expected { message, sessionId } response contract")
}
console.log(`Target connection validated. Session: ${body.sessionId}`)
