// Server settings from environment variables. A value that is set but can't
// be used stops the server at start-up with a message saying which one,
// instead of quietly turning a limit off.

export interface ServerConfig {
  port: number;
  /** Clients must send `Authorization: Bearer <token>`. Empty = open. */
  appToken: string;
  /**
   * How many proxies (Render, Railway, nginx…) stand in front of the server;
   * the client's address is read from X-Forwarded-For that many hops back.
   * 0 = none, use the connection's address.
   */
  trustProxy: number;
  /** Requests per client in each 10-minute window. */
  rateLimit: number;
  /** Study kits + quizzes per client per day. 0 = no daily limit. */
  dailyLimit: number;
  /** Answer checks per client per day. 0 = no daily limit. */
  dailyCheckLimit: number;
  /** Estimated Claude spend per day for the whole server, in US dollars. 0 = no cap. */
  dailyBudgetUsd: number;
  /** Where "today" starts and ends for the limits above. */
  timeZone: string;
  /** /health also says which model and effort are in use. */
  healthDetails: boolean;
}

export const DEFAULTS = {
  port: 8787,
  rateLimit: 30,
  dailyLimit: 60,
  dailyCheckLimit: 300,
  dailyBudgetUsd: 5,
  timeZone: "Asia/Manila",
} as const;

export class ConfigError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ConfigError";
  }
}

type Env = Record<string, string | undefined>;

function raw(env: Env, name: string): string | undefined {
  const v = env[name]?.trim();
  return v ? v : undefined;
}

export function intFromEnv(env: Env, name: string, fallback: number, min = 0): number {
  const v = raw(env, name);
  if (v === undefined) return fallback;
  const n = Number(v);
  if (!Number.isInteger(n) || n < min) {
    throw new ConfigError(`${name} must be a whole number of at least ${min} (got "${v}").`);
  }
  return n;
}

export function numberFromEnv(env: Env, name: string, fallback: number): number {
  const v = raw(env, name);
  if (v === undefined) return fallback;
  const n = Number(v);
  if (!Number.isFinite(n) || n < 0) {
    throw new ConfigError(`${name} must be a number, 0 or more (got "${v}").`);
  }
  return n;
}

export function boolFromEnv(env: Env, name: string): boolean {
  const v = raw(env, name)?.toLowerCase();
  if (v === undefined) return false;
  if (["1", "true", "yes", "on"].includes(v)) return true;
  if (["0", "false", "no", "off"].includes(v)) return false;
  throw new ConfigError(`${name} must be 1 or 0 (got "${v}").`);
}

/** A proxy hop count: 1/true/yes = one proxy, 0/false/no = none, or a number of hops. */
export function hopsFromEnv(env: Env, name: string): number {
  const v = raw(env, name)?.toLowerCase();
  if (v === undefined) return 0;
  if (["true", "yes", "on"].includes(v)) return 1;
  if (["false", "no", "off"].includes(v)) return 0;
  const n = Number(v);
  if (!Number.isInteger(n) || n < 0 || n > 10) {
    throw new ConfigError(`${name} must be the number of proxies in front of the server, such as 1 (got "${v}").`);
  }
  return n;
}

export function isValidTimeZone(timeZone: string): boolean {
  try {
    new Intl.DateTimeFormat("en-US", { timeZone });
    return true;
  } catch {
    return false;
  }
}

export function readConfig(env: Env = process.env): ServerConfig {
  const timeZone = raw(env, "DAY_TIME_ZONE") ?? DEFAULTS.timeZone;
  if (!isValidTimeZone(timeZone)) {
    throw new ConfigError(`DAY_TIME_ZONE "${timeZone}" isn't a time zone (try Asia/Manila).`);
  }
  return {
    port: intFromEnv(env, "PORT", DEFAULTS.port, 1),
    appToken: raw(env, "APP_TOKEN") ?? "",
    trustProxy: hopsFromEnv(env, "TRUST_PROXY"),
    rateLimit: intFromEnv(env, "RATE_LIMIT", DEFAULTS.rateLimit, 1),
    dailyLimit: intFromEnv(env, "DAILY_LIMIT", DEFAULTS.dailyLimit),
    dailyCheckLimit: intFromEnv(env, "DAILY_CHECK_LIMIT", DEFAULTS.dailyCheckLimit),
    dailyBudgetUsd: numberFromEnv(env, "DAILY_BUDGET_USD", DEFAULTS.dailyBudgetUsd),
    timeZone,
    healthDetails: boolFromEnv(env, "HEALTH_DETAILS"),
  };
}
