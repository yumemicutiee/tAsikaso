// Today's requests and estimated spend, kept in memory: right for one server
// process. It starts again from zero when the process restarts (a deploy, or
// a free host waking up), and several instances don't share it; that would
// need a shared store such as Redis or a database.

/**
 * Study kits and quizzes count as "study"; marking a typed answer is a
 * "check"; reading one page photo is a "read".
 */
export type RequestKind = "study" | "check" | "read";

export interface LedgerOptions {
  timeZone: string;
  /** Study requests per client per day; 0 = unlimited. */
  dailyLimit: number;
  /** Answer checks per client per day; 0 = unlimited. */
  dailyCheckLimit: number;
  /** Page photos read per client per day; 0 = unlimited. */
  dailyReadLimit?: number;
  /** Estimated dollars per day for the whole server; 0 = no cap. */
  budgetUsd: number;
  /** For tests. */
  now?: () => number;
}

/**
 * Who a request is counted for. With an install id (a random id the app
 * makes once and sends as X-Install-Id), the daily limits apply per install,
 * so students on one school Wi-Fi (one address) each get their own; their
 * address together gets SHARED_ADDRESS_FACTOR times the limit, so inventing
 * ids doesn't buy more than that. Without one (older apps), the address alone.
 */
export interface Client {
  address: string;
  install?: string;
}

/** How many installs' worth of requests one address may make in a day. */
export const SHARED_ADDRESS_FACTOR = 10;

export type Admission =
  | { ok: true }
  | { ok: false; reason: "daily_limit"; kind: RequestKind; limit: number }
  | { ok: false; reason: "budget" };

interface ClientDay {
  study: number;
  check: number;
  read: number;
}

const emptyDay = (): ClientDay => ({ study: 0, check: 0, read: 0 });

export interface UsageReport {
  day: string;
  timeZone: string;
  resetsInSeconds: number;
  /** Requests that went to Claude today, by route. */
  requests: number;
  byRoute: Record<string, number>;
  refused: { daily_limit: number; budget: number };
  tokens: { input: number; output: number };
  spentUsd: number;
  budgetUsd: number | null;
  remainingUsd: number | null;
  you: {
    study: number;
    studyLimit: number | null;
    checks: number;
    checkLimit: number | null;
    pagesRead: number;
    readLimit: number | null;
  };
}

export class DailyLedger {
  private readonly now: () => number;
  private readonly dayFormat: Intl.DateTimeFormat;
  private readonly clockFormat: Intl.DateTimeFormat;
  private day = "";
  private clients = new Map<string, ClientDay>();
  private byRoute: Record<string, number> = {};
  private refused = { daily_limit: 0, budget: 0 };
  private tokens = { input: 0, output: 0 };
  private spent = 0;

  constructor(private readonly opts: LedgerOptions) {
    this.now = opts.now ?? Date.now;
    this.dayFormat = new Intl.DateTimeFormat("en-CA", {
      timeZone: opts.timeZone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    });
    this.clockFormat = new Intl.DateTimeFormat("en-GB", {
      timeZone: opts.timeZone,
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
      hourCycle: "h23",
    });
    this.rollOver();
  }

  /** Today's date (YYYY-MM-DD) in the ledger's time zone. */
  today(): string {
    this.rollOver();
    return this.day;
  }

  /**
   * Checks the server-wide budget and [client]'s allowance for [kind]; when
   * both allow it, counts the request against them.
   */
  admit(client: string | Client, kind: RequestKind, route: string): Admission {
    this.rollOver();
    const { budgetUsd } = this.opts;
    if (budgetUsd > 0 && this.spent >= budgetUsd) {
      this.refused.budget++;
      return { ok: false, reason: "budget" };
    }
    const limit = this.limitFor(kind);
    // Each counter that must allow the request, with its limit.
    const counters: [string, number][] = [];
    for (const [key, max] of keysFor(client, limit)) {
      counters.push([key, max]);
      const day = this.clients.get(key) ?? emptyDay();
      if (limit > 0 && day[kind] >= max) {
        this.refused.daily_limit++;
        return { ok: false, reason: "daily_limit", kind, limit: max };
      }
    }
    for (const [key] of counters) {
      const day = this.clients.get(key) ?? emptyDay();
      day[kind]++;
      this.clients.set(key, day);
    }
    this.byRoute[route] = (this.byRoute[route] ?? 0) + 1;
    return { ok: true };
  }

  /**
   * For a signed-in user, whose own limits are counted in Supabase: only
   * the server-wide budget is checked here. Then [countAdmitted] or
   * [countRefusedLimit], once Supabase has answered.
   */
  checkBudget(): Admission {
    this.rollOver();
    const { budgetUsd } = this.opts;
    if (budgetUsd > 0 && this.spent >= budgetUsd) {
      this.refused.budget++;
      return { ok: false, reason: "budget" };
    }
    return { ok: true };
  }

  /** A signed-in user's request that goes on to Claude, for /v1/usage. */
  countAdmitted(route: string): void {
    this.rollOver();
    this.byRoute[route] = (this.byRoute[route] ?? 0) + 1;
  }

  /** A request refused by a signed-in user's own daily limit, for /v1/usage. */
  countRefusedLimit(): void {
    this.rollOver();
    this.refused.daily_limit++;
  }

  private limitFor(kind: RequestKind): number {
    switch (kind) {
      case "study":
        return this.opts.dailyLimit;
      case "check":
        return this.opts.dailyCheckLimit;
      case "read":
        return this.opts.dailyReadLimit ?? 0;
    }
  }

  /** Adds what one Claude call cost to today's total. */
  record(cost: { inputTokens: number; outputTokens: number; costUsd: number }): void {
    this.rollOver();
    this.tokens.input += cost.inputTokens;
    this.tokens.output += cost.outputTokens;
    this.spent += cost.costUsd;
  }

  /** Seconds until midnight in the ledger's time zone. */
  secondsToMidnight(): number {
    const parts = this.clockFormat.formatToParts(new Date(this.now()));
    const get = (type: string) => Number(parts.find((p) => p.type === type)?.value ?? 0);
    const elapsed = get("hour") * 3600 + get("minute") * 60 + get("second");
    return Math.max(1, 86_400 - elapsed);
  }

  report(client?: string | Client): UsageReport {
    this.rollOver();
    const { budgetUsd, dailyLimit, dailyCheckLimit, timeZone } = this.opts;
    const dailyReadLimit = this.opts.dailyReadLimit ?? 0;
    // The counter that is the client's own: its install, else its address.
    const own = client === undefined ? undefined : keysFor(client, 1)[0]?.[0];
    const mine = (own && this.clients.get(own)) || emptyDay();
    const requests = Object.values(this.byRoute).reduce((a, b) => a + b, 0);
    return {
      day: this.day,
      timeZone,
      resetsInSeconds: this.secondsToMidnight(),
      requests,
      byRoute: { ...this.byRoute },
      refused: { ...this.refused },
      tokens: { ...this.tokens },
      spentUsd: round(this.spent),
      budgetUsd: budgetUsd > 0 ? budgetUsd : null,
      remainingUsd: budgetUsd > 0 ? round(Math.max(0, budgetUsd - this.spent)) : null,
      you: {
        study: mine.study,
        studyLimit: dailyLimit > 0 ? dailyLimit : null,
        checks: mine.check,
        checkLimit: dailyCheckLimit > 0 ? dailyCheckLimit : null,
        pagesRead: mine.read,
        readLimit: dailyReadLimit > 0 ? dailyReadLimit : null,
      },
    };
  }

  private rollOver(): void {
    const day = this.dayFormat.format(new Date(this.now()));
    if (day === this.day) return;
    this.day = day;
    this.clients = new Map();
    this.byRoute = {};
    this.refused = { daily_limit: 0, budget: 0 };
    this.tokens = { input: 0, output: 0 };
    this.spent = 0;
  }
}

const round = (usd: number) => Math.round(usd * 10_000) / 10_000;

/**
 * The counters a request from [client] goes on, each with its limit: the
 * install's own and its address's shared one, or (no install id, or a plain
 * address string) the address alone, as before install ids.
 */
function keysFor(client: string | Client, limit: number): [string, number][] {
  if (typeof client === "string") return [[client, limit]];
  if (!client.install) return [[client.address, limit]];
  return [
    [`install:${client.install}`, limit],
    [`shared:${client.address}`, limit * SHARED_ADDRESS_FACTOR],
  ];
}
