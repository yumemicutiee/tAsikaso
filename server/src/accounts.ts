// Accounts, plans and daily usage in Supabase (see
// supabase/migrations/0001_accounts.sql). The app signs in with Supabase
// Auth (Google, or anonymously) and sends its access token; the server
// checks the token against the project's public signing keys, then reads
// the user's plan and counts the request in Postgres, so limits survive
// restarts and are counted per person.

import { createRemoteJWKSet, errors as joseErrors, jwtVerify } from "jose";

import type { RequestKind } from "./ledger.js";

/** A signed-in user, as their token says. */
export interface Account {
  id: string;
  /** Signed in without an account ("Continue without an account"). */
  anonymous: boolean;
  /** The account's email, as the token says (Google accounts); used for the admin check. */
  email?: string;
}

/** Which limits apply. */
export type Tier = "anonymous" | "free" | "plus";

export type PlanName = "monthly" | "semester" | "yearly";
export const PLAN_NAMES: readonly PlanName[] = ["monthly", "semester", "yearly"];

/** What one period of each plan costs, in pesos, as in the app (lib/data/plans.dart). */
export const PLAN_PRICE_PHP: Record<PlanName, number> = { monthly: 49, semester: 199, yearly: 349 };

/** How long one period of each plan lasts, as in the app (lib/data/plans.dart). */
export const PLAN_MONTHS: Record<PlanName, number> = { monthly: 1, semester: 6, yearly: 12 };

/** A user's plan: null name = the free plan. */
export interface Plan {
  name: PlanName | null;
  startedAt: string | null;
  endsAt: string | null;
  test: boolean;
}

export const FREE_PLAN: Plan = { name: null, startedAt: null, endsAt: null, test: false };

/** The plan is tAsikaso+ and still running at [now]. */
export function planActive(plan: Plan, now: number): boolean {
  return plan.name !== null && plan.endsAt !== null && Date.parse(plan.endsAt) > now;
}

export function tierOf(account: Account, plan: Plan, now: number): Tier {
  if (planActive(plan, now)) return "plus";
  return account.anonymous ? "anonymous" : "free";
}

/** When a period of [months] starting at [start] ends: same day and time, months later (UTC). */
export function addMonths(start: Date, months: number): Date {
  const d = new Date(start.getTime());
  d.setUTCMonth(d.getUTCMonth() + months);
  return d;
}

/** Daily limits per tier and kind; 0 = no limit. */
export type TierLimits = Record<RequestKind, Record<Tier, number>>;

export const DEFAULT_TIER_LIMITS: TierLimits = {
  read: { anonymous: 20, free: 50, plus: 200 },
  study: { anonymous: 10, free: 30, plus: 100 },
  check: { anonymous: 50, free: 150, plus: 500 },
};

/** The sign-in token was missing, malformed, expired or not from this project. */
export class BadTokenError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "BadTokenError";
  }
}

/** Supabase couldn't be reached or answered with an error. */
export class AccountsUnavailableError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AccountsUnavailableError";
  }
}

export interface TokenVerifier {
  /** The account [token] belongs to; throws BadTokenError if it isn't valid. */
  verify(token: string): Promise<Account>;
}

/** Three base64url parts: the shape of a JWT (an app token has no dots). */
export function looksLikeJwt(token: string): boolean {
  return /^[\w-]+\.[\w-]+\.[\w-]+$/.test(token);
}

/**
 * Checks Supabase access tokens with the project's published signing keys
 * (asymmetric: no secret needed). The keys are fetched once and cached;
 * a token signed with a new key makes jose fetch them again.
 */
export function supabaseVerifier(
  projectUrl: string,
  options: { jwksUrl?: string; fetchTimeoutMs?: number } = {},
): TokenVerifier {
  const base = projectUrl.replace(/\/+$/, "");
  const issuer = `${base}/auth/v1`;
  const jwks = createRemoteJWKSet(new URL(options.jwksUrl ?? `${issuer}/.well-known/jwks.json`), {
    timeoutDuration: options.fetchTimeoutMs ?? 5000,
  });
  return {
    async verify(token: string): Promise<Account> {
      let payload;
      try {
        ({ payload } = await jwtVerify(token, jwks, {
          issuer,
          audience: "authenticated",
          algorithms: ["ES256", "RS256", "EdDSA"],
        }));
      } catch (e) {
        const message = e instanceof Error ? e.message : String(e);
        // Fetching the keys failed (Supabase down or slow): not the user's
        // fault, so "try again", not "sign in again". Errors that aren't
        // jose's own come from the network.
        if (
          e instanceof joseErrors.JWKSTimeout ||
          !(e instanceof joseErrors.JOSEError) ||
          /JSON Web Key Set HTTP response/.test(message)
        ) {
          throw new AccountsUnavailableError(`couldn't fetch the signing keys: ${message}`);
        }
        throw new BadTokenError(message);
      }
      const id = payload.sub;
      if (typeof id !== "string" || !/^[0-9a-f-]{36}$/i.test(id)) {
        throw new BadTokenError("the token names no user");
      }
      if (payload.role !== "authenticated") throw new BadTokenError("not a user's token");
      const email = typeof payload.email === "string" && payload.email.includes("@")
        ? payload.email.trim().toLowerCase()
        : undefined;
      return { id, anonymous: payload.is_anonymous === true, ...(email ? { email } : {}) };
    },
  };
}

/** Where plans and usage are kept (Supabase in production, memory in tests). */
export interface AccountStore {
  plan(userId: string): Promise<Plan>;
  /** Counts one request; the new count, or -1 when [limit] (0 = none) is reached. */
  consume(userId: string, day: string, kind: RequestKind, limit: number): Promise<number>;
  recordCost(userId: string, day: string, kind: RequestKind, usd: number): Promise<void>;
  usage(userId: string, day: string): Promise<Record<RequestKind, number>>;
  setPlan(userId: string, plan: Plan): Promise<Plan>;
  deleteUser(userId: string): Promise<void>;
}

/** A crash report from the app, as stored (see 0003_admin.sql). */
export interface StoredCrash {
  message: string;
  stack?: string;
  source?: string;
  version: string;
  platform: string;
}

/**
 * The admin page's user filters (0004_admin_history_filters.sql). Left out
 * (or all "all", 0 and "newest"), the list is unfiltered, newest first.
 */
export interface UserFilters {
  account?: "all" | "google" | "anonymous";
  plan?: "all" | "free" | "plus" | "monthly" | "semester" | "yearly" | "ending";
  days?: number;
  sort?: "newest" | "oldest" | "ending";
}

/**
 * What the admin page reads, and the rows behind it (0003_admin.sql). Each
 * read returns the admin_* function's JSON as it is.
 */
export interface AdminStore {
  overview(timeZone: string): Promise<unknown>;
  users(query: string, limit: number, offset: number, filters?: UserFilters): Promise<unknown>;
  payments(timeZone: string, limit: number): Promise<unknown>;
  crashes(days: number): Promise<unknown>;
  saveCrash(userId: string | null, crash: StoredCrash): Promise<void>;
  pruneCrashes(): Promise<number>;
  /** A pretend payment for the demo (no money moved), when a plan is switched on for free. */
  recordDemoPayment(userId: string, plan: PlanName): Promise<void>;
}

type Fetch = typeof fetch;

/**
 * Supabase's REST API (PostgREST and the Auth admin API) with the
 * project's secret key, which bypasses row-level security. Never sent to
 * the app.
 */
export class SupabaseStore implements AccountStore, AdminStore {
  private readonly base: string;
  private readonly headers: Record<string, string>;

  constructor(
    projectUrl: string,
    secretKey: string,
    private readonly fetchImpl: Fetch = fetch,
    private readonly timeoutMs = 8000,
  ) {
    this.base = projectUrl.replace(/\/+$/, "");
    // New-style keys (sb_secret_…) go in `apikey` alone; a legacy
    // service_role key is a JWT and is also sent as the bearer.
    this.headers = {
      apikey: secretKey,
      ...(secretKey.startsWith("eyJ") ? { Authorization: `Bearer ${secretKey}` } : {}),
    };
  }

  private async call(method: string, path: string, body?: unknown, extra: Record<string, string> = {}) {
    let res: Response;
    try {
      res = await this.fetchImpl(this.base + path, {
        method,
        headers: {
          ...this.headers,
          ...(body === undefined ? {} : { "Content-Type": "application/json" }),
          ...extra,
        },
        body: body === undefined ? undefined : JSON.stringify(body),
        signal: AbortSignal.timeout(this.timeoutMs),
      });
    } catch (e) {
      throw new AccountsUnavailableError(`${method} ${path}: ${e instanceof Error ? e.message : e}`);
    }
    const text = await res.text();
    if (!res.ok) {
      throw new AccountsUnavailableError(`${method} ${path}: HTTP ${res.status} ${text.slice(0, 300)}`);
    }
    return text ? (JSON.parse(text) as unknown) : null;
  }

  async plan(userId: string): Promise<Plan> {
    const rows = (await this.call(
      "GET",
      `/rest/v1/profiles?id=eq.${encodeURIComponent(userId)}&select=plan,plan_started_at,plan_ends_at,test_purchase`,
    )) as Array<Record<string, unknown>> | null;
    const row = rows?.[0];
    if (!row) return FREE_PLAN;
    return planFromRow(row);
  }

  async consume(userId: string, day: string, kind: RequestKind, limit: number): Promise<number> {
    const n = await this.call("POST", "/rest/v1/rpc/consume_allowance", {
      p_user: userId,
      p_day: day,
      p_kind: kind,
      p_limit: limit,
    });
    if (typeof n !== "number") throw new AccountsUnavailableError(`consume_allowance returned ${JSON.stringify(n)}`);
    return n;
  }

  async recordCost(userId: string, day: string, kind: RequestKind, usd: number): Promise<void> {
    await this.call("POST", "/rest/v1/rpc/record_cost", {
      p_user: userId,
      p_day: day,
      p_kind: kind,
      p_cost: Math.round(usd * 1_000_000) / 1_000_000,
    });
  }

  async usage(userId: string, day: string): Promise<Record<RequestKind, number>> {
    const rows = (await this.call(
      "GET",
      `/rest/v1/usage_daily?user_id=eq.${encodeURIComponent(userId)}&day=eq.${encodeURIComponent(day)}&select=kind,count`,
    )) as Array<{ kind: RequestKind; count: number }> | null;
    const out: Record<RequestKind, number> = { study: 0, check: 0, read: 0 };
    for (const r of rows ?? []) if (r.kind in out) out[r.kind] = r.count;
    return out;
  }

  async setPlan(userId: string, plan: Plan): Promise<Plan> {
    const rows = (await this.call(
      "PATCH",
      `/rest/v1/profiles?id=eq.${encodeURIComponent(userId)}`,
      {
        plan: plan.name,
        plan_started_at: plan.startedAt,
        plan_ends_at: plan.endsAt,
        test_purchase: plan.test,
        updated_at: new Date().toISOString(),
      },
      { Prefer: "return=representation" },
    )) as Array<Record<string, unknown>> | null;
    const row = rows?.[0];
    if (!row) throw new AccountsUnavailableError("no profile for this user");
    return planFromRow(row);
  }

  async deleteUser(userId: string): Promise<void> {
    await this.call("DELETE", `/auth/v1/admin/users/${encodeURIComponent(userId)}`);
  }

  overview(timeZone: string) {
    return this.call("POST", "/rest/v1/rpc/admin_overview", { p_tz: timeZone });
  }

  users(query: string, limit: number, offset: number, filters: UserFilters = {}) {
    // Filters go only when set, so the call also works before
    // 0004_admin_history_filters.sql has been run.
    const extra: Record<string, unknown> = {};
    if (filters.account && filters.account !== "all") extra.p_account = filters.account;
    if (filters.plan && filters.plan !== "all") extra.p_plan = filters.plan;
    if (filters.days && filters.days > 0) extra.p_days = filters.days;
    if (filters.sort && filters.sort !== "newest") extra.p_sort = filters.sort;
    return this.call("POST", "/rest/v1/rpc/admin_users", { p_query: query, p_limit: limit, p_offset: offset, ...extra });
  }

  payments(timeZone: string, limit: number) {
    return this.call("POST", "/rest/v1/rpc/admin_payments", { p_tz: timeZone, p_limit: limit });
  }

  crashes(days: number) {
    return this.call("POST", "/rest/v1/rpc/admin_crashes", { p_days: days });
  }

  async saveCrash(userId: string | null, crash: StoredCrash): Promise<void> {
    await this.call(
      "POST",
      "/rest/v1/crash_reports",
      {
        user_id: userId,
        message: crash.message,
        stack: crash.stack ?? null,
        source: crash.source ?? null,
        version: crash.version,
        platform: crash.platform,
      },
      { Prefer: "return=minimal" },
    );
  }

  async pruneCrashes(): Promise<number> {
    const n = await this.call("POST", "/rest/v1/rpc/prune_crash_reports", {});
    return typeof n === "number" ? n : 0;
  }

  async recordDemoPayment(userId: string, plan: PlanName): Promise<void> {
    await this.call(
      "POST",
      "/rest/v1/payments",
      {
        user_id: userId,
        provider: "demo",
        plan,
        amount_php: PLAN_PRICE_PHP[plan],
        status: "paid",
        demo: true,
      },
      { Prefer: "return=minimal" },
    );
  }
}

function planFromRow(row: Record<string, unknown>): Plan {
  const name = PLAN_NAMES.includes(row.plan as PlanName) ? (row.plan as PlanName) : null;
  const iso = (v: unknown) => (typeof v === "string" ? new Date(v).toISOString() : null);
  return {
    name,
    startedAt: name ? iso(row.plan_started_at) : null,
    endsAt: name ? iso(row.plan_ends_at) : null,
    test: name ? row.test_purchase === true : false,
  };
}

/** The same rules in memory: for tests, and a model of the SQL functions. */
export class MemoryStore implements AccountStore {
  readonly plans = new Map<string, Plan>();
  readonly counts = new Map<string, number>();
  readonly costs = new Map<string, number>();
  readonly deleted: string[] = [];
  /** Make every call fail, as if Supabase were down. */
  down = false;

  private check() {
    if (this.down) throw new AccountsUnavailableError("Supabase is down (test)");
  }

  async plan(userId: string) {
    this.check();
    return this.plans.get(userId) ?? FREE_PLAN;
  }
  async consume(userId: string, day: string, kind: RequestKind, limit: number) {
    this.check();
    const key = `${userId}|${day}|${kind}`;
    const n = this.counts.get(key) ?? 0;
    if (limit > 0 && n >= limit) return -1;
    this.counts.set(key, n + 1);
    return n + 1;
  }
  async recordCost(userId: string, day: string, kind: RequestKind, usd: number) {
    this.check();
    const key = `${userId}|${day}|${kind}`;
    this.costs.set(key, (this.costs.get(key) ?? 0) + Math.max(usd, 0));
  }
  async usage(userId: string, day: string) {
    this.check();
    const get = (kind: RequestKind) => this.counts.get(`${userId}|${day}|${kind}`) ?? 0;
    return { study: get("study"), check: get("check"), read: get("read") };
  }
  async setPlan(userId: string, plan: Plan) {
    this.check();
    this.plans.set(userId, plan);
    return plan;
  }
  async deleteUser(userId: string) {
    this.check();
    this.deleted.push(userId);
    this.plans.delete(userId);
    for (const k of [...this.counts.keys()]) if (k.startsWith(`${userId}|`)) this.counts.delete(k);
  }
}
