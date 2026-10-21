import { existsSync } from "node:fs";

// Local runs read .env (Node's own loader, no extra package); hosts set
// real environment variables instead.
if (existsSync(".env")) process.loadEnvFile(".env");

const { ConfigError, readConfig } = await import("./config.js");
const { createApp } = await import("./app.js");
const { CHECK_EFFORT, EFFORT, MODEL } = await import("./claude.js");
const { jsonLogger: log } = await import("./log.js");

if (!process.env.ANTHROPIC_API_KEY) {
  console.error("ANTHROPIC_API_KEY is not set. Copy .env.example to .env and add your key.");
  process.exit(1);
}

let config;
try {
  config = readConfig();
} catch (e) {
  if (e instanceof ConfigError) {
    console.error(`Bad setting: ${e.message}`);
    process.exit(1);
  }
  throw e;
}

if (!config.appToken) {
  console.warn("APP_TOKEN is not set: anyone who finds this server can use it.");
}

const app = createApp({
  appToken: config.appToken,
  rateLimit: config.rateLimit,
  trustProxy: config.trustProxy,
  dailyLimit: config.dailyLimit,
  dailyCheckLimit: config.dailyCheckLimit,
  dailyBudgetUsd: config.dailyBudgetUsd,
  timeZone: config.timeZone,
  healthDetails: config.healthDetails,
});

const server = app.listen(config.port, () => {
  log("info", "started", {
    url: `http://localhost:${config.port}`,
    model: MODEL,
    effort: EFFORT,
    checkEffort: CHECK_EFFORT,
    dailyLimit: config.dailyLimit,
    dailyCheckLimit: config.dailyCheckLimit,
    dailyBudgetUsd: config.dailyBudgetUsd,
    timeZone: config.timeZone,
  });
});

// Hosts send SIGTERM before replacing the server: stop taking new requests
// and let the ones in progress finish.
for (const signal of ["SIGTERM", "SIGINT"] as const) {
  process.once(signal, () => {
    log("info", "stopping", { signal });
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(0), 25_000).unref();
  });
}
