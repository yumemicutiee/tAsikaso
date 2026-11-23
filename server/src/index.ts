import { existsSync } from "node:fs";

// Local runs read .env (Node's own loader, no extra package); hosts set
// real environment variables instead.
if (existsSync(".env")) process.loadEnvFile(".env");

const { ConfigError, readConfig } = await import("./config.js");
const { createApp } = await import("./app.js");
const { CHECK_EFFORT, EFFORT, MODEL, READ_EFFORT } = await import("./claude.js");
const { jsonLogger: log } = await import("./log.js");
const { SupabaseStore, supabaseVerifier } = await import("./accounts.js");

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

const store = config.supabaseUrl ? new SupabaseStore(config.supabaseUrl, config.supabaseSecretKey) : undefined;

const app = createApp({
  appToken: config.appToken,
  rateLimit: config.rateLimit,
  trustProxy: config.trustProxy,
  dailyLimit: config.dailyLimit,
  dailyCheckLimit: config.dailyCheckLimit,
  dailyReadLimit: config.dailyReadLimit,
  dailyBudgetUsd: config.dailyBudgetUsd,
  timeZone: config.timeZone,
  healthDetails: config.healthDetails,
  allowAppToken: config.allowAppToken,
  testPurchases: config.testPurchases,
  accounts: store
    ? {
        verifier: supabaseVerifier(config.supabaseUrl),
        store,
        limits: config.tierLimits,
      }
    : undefined,
  admin: store ? { emails: config.adminEmails, store } : undefined,
  storeCrashReports: config.storeCrashReports,
  demoPayments: config.demoPayments,
});

const server = app.listen(config.port, () => {
  log("info", "started", {
    url: `http://localhost:${config.port}`,
    model: MODEL,
    effort: EFFORT,
    checkEffort: CHECK_EFFORT,
    readEffort: READ_EFFORT,
    dailyLimit: config.dailyLimit,
    dailyCheckLimit: config.dailyCheckLimit,
    dailyReadLimit: config.dailyReadLimit,
    accounts: config.supabaseUrl ? `on (${config.supabaseUrl})` : "off",
    allowAppToken: config.allowAppToken,
    testPurchases: config.testPurchases,
    tierLimits: config.tierLimits,
    adminPage: config.adminEmails.length > 0 ? `on (${config.adminEmails.length} admin)` : "off",
    storeCrashReports: config.storeCrashReports,
    demoPayments: config.demoPayments,
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
