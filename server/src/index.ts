import { existsSync } from "node:fs";

// Local runs read .env (Node's own loader, no extra package); hosts set
// real environment variables instead.
if (existsSync(".env")) process.loadEnvFile(".env");

const { createApp } = await import("./app.js");
const { EFFORT, MODEL } = await import("./claude.js");

if (!process.env.ANTHROPIC_API_KEY) {
  console.error("ANTHROPIC_API_KEY is not set. Copy .env.example to .env and add your key.");
  process.exit(1);
}
if (!process.env.APP_TOKEN) {
  console.warn("APP_TOKEN is not set: anyone who finds this server can use it.");
}

const port = Number(process.env.PORT ?? 8787);
const app = createApp({
  appToken: process.env.APP_TOKEN,
  rateLimit: process.env.RATE_LIMIT ? Number(process.env.RATE_LIMIT) : undefined,
  trustProxy: Boolean(process.env.TRUST_PROXY),
});

app.listen(port, () => {
  console.log(`tAsikaso study server on http://localhost:${port} (${MODEL}, effort ${EFFORT})`);
});
