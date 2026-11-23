import assert from "node:assert/strict";
import type { Server } from "node:http";
import type { AddressInfo } from "node:net";
import { after, test } from "node:test";

import {
  type Account,
  BadTokenError,
  MemoryStore,
  type TierLimits,
  type TokenVerifier,
} from "../src/accounts.js";
import { type AppOptions, createApp, type Generators } from "../src/app.js";
import type { CallUsage } from "../src/claude.js";
import type { LogFields } from "../src/log.js";

// The server with Supabase accounts on: a stand-in verifier (token string
// -> account) and the in-memory store with the SQL functions' rules.

const ANON = "aaaaaaaa-0000-4000-8000-000000000001";
const FREE = "bbbbbbbb-0000-4000-8000-000000000002";
const PLUS = "cccccccc-0000-4000-8000-000000000003";
const TOKENS: Record<string, Account> = {
  "anon.tok.en": { id: ANON, anonymous: true },
  "free.tok.en": { id: FREE, anonymous: false },
  "plus.tok.en": { id: PLUS, anonymous: false },
};
const verifier: TokenVerifier = {
  async verify(token) {
    const account = TOKENS[token];
    if (!account) throw new BadTokenError("unknown token");
    return account;
  },
};

const LIMITS: TierLimits = {
  read: { anonymous: 2, free: 3, plus: 5 },
  study: { anonymous: 1, free: 2, plus: 0 },
  check: { anonymous: 1, free: 1, plus: 1 },
};

const servers: Server[] = [];
after(() => {
  for (const s of servers) {
    s.closeAllConnections();
    s.close();
  }
});

const usage = (costUsd: number): CallUsage => ({
  model: "claude-opus-5-5",
  inputTokens: 4700,
  outputTokens: 170,
  costUsd,
  fallback: false,
  estimated: false,
});

const PAGE = { image: Buffer.alloc(3000, 7).toString("base64") };
const NOTES = { text: "x".repeat(40) };

interface LogLine extends LogFields {
  level: string;
  msg: string;
}

async function start(options: Partial<AppOptions> = {}, store = new MemoryStore()) {
  let claudeCalls = 0;
  const generators: Partial<Generators> = {
    readPage: async () => {
      claudeCalls++;
      return { ...usage(0.022), data: { text: "Page" }, ms: 1 };
    },
    studyKit: async () => {
      claudeCalls++;
      return {
        ...usage(0.11),
        data: { title: "T", summary: "S", notes: "# T", concepts: [], cards: [], quiz: [] },
        ms: 1,
      };
    },
  };
  const logs: LogLine[] = [];
  const now = Date.parse("2026-11-24T04:00:00Z"); // noon in Manila
  const app = createApp({
    appToken: "shared-secret",
    generators,
    accounts: { verifier, store, limits: LIMITS },
    log: (level, msg, fields = {}) => logs.push({ level, msg, ...fields }),
    now: () => now,
    ...options,
  });
  const server = await new Promise<Server>((r) => {
    const s = app.listen(0, "127.0.0.1", () => r(s));
  });
  servers.push(server);
  const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  const call = (method: string, path: string, token: string | null, body?: unknown) =>
    fetch(base + path, {
      method,
      headers: {
        "content-type": "application/json",
        ...(token ? { authorization: `Bearer ${token}` } : {}),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
  return { call, store, logs, claudeCalls: () => claudeCalls, now };
}

type ErrorBody = { error: { code: string; message: string; tier?: string } };

test("each tier gets its own daily limit, counted in the store per user", async () => {
  const { call, store, claudeCalls } = await start();
  store.plans.set(PLUS, {
    name: "yearly",
    startedAt: "2026-01-01T00:00:00.000Z",
    endsAt: "2027-01-01T00:00:00.000Z",
    test: true,
  });
  const statuses = async (token: string, n: number) => {
    const out: number[] = [];
    for (let i = 0; i < n; i++) out.push((await call("POST", "/v1/read-page", token, PAGE)).status);
    return out;
  };
  assert.deepEqual(await statuses("anon.tok.en", 3), [200, 200, 429], "no account: 2 pages");
  assert.deepEqual(await statuses("free.tok.en", 4), [200, 200, 200, 429], "signed in: 3 pages");
  assert.deepEqual(await statuses("plus.tok.en", 6), [200, 200, 200, 200, 200, 429], "tAsikaso+: 5 pages");
  assert.equal(claudeCalls(), 10, "a refused request never reaches Claude");
  assert.equal(store.counts.get(`${ANON}|2026-11-24|read`), 2, "counted on the Manila day");
  assert.equal(store.counts.get(`${FREE}|2026-11-24|read`), 3);
});

test("the limit message tells each tier what it can do next", async () => {
  const { call } = await start();
  for (let i = 0; i < 2; i++) await call("POST", "/v1/read-page", "anon.tok.en", PAGE);
  const anon = await call("POST", "/v1/read-page", "anon.tok.en", PAGE);
  const body = (await anon.json()) as ErrorBody;
  assert.equal(body.error.code, "daily_limit");
  assert.equal(body.error.tier, "anonymous");
  assert.equal(
    body.error.message,
    "You've reached today's limit of 2 pages read by Claude. Continue with Google in tAsikaso for more, or try again tomorrow.",
  );
  assert.ok(Number(anon.headers.get("retry-after")) > 0);

  await call("POST", "/v1/study-kit", "free.tok.en", NOTES);
  await call("POST", "/v1/study-kit", "free.tok.en", NOTES);
  const free = (await (await call("POST", "/v1/study-kit", "free.tok.en", NOTES)).json()) as ErrorBody;
  assert.equal(
    free.error.message,
    "You've reached today's limit of 2 Smart Study requests. Try again tomorrow, or get tAsikaso+ for more.",
  );
});

test("a plan that has ended counts as the free plan", async () => {
  const { call, store } = await start();
  store.plans.set(FREE, {
    name: "monthly",
    startedAt: "2026-10-01T00:00:00.000Z",
    endsAt: "2026-11-01T00:00:00.000Z",
    test: true,
  });
  const statuses: number[] = [];
  for (let i = 0; i < 4; i++) statuses.push((await call("POST", "/v1/read-page", "free.tok.en", PAGE)).status);
  assert.deepEqual(statuses, [200, 200, 200, 429]);
});

test("what each call cost goes on the user's row for that day and kind", async () => {
  const { call, store } = await start();
  await call("POST", "/v1/read-page", "free.tok.en", PAGE);
  await call("POST", "/v1/read-page", "free.tok.en", PAGE);
  await new Promise((r) => setTimeout(r, 20)); // recorded after the reply
  assert.ok(Math.abs((store.costs.get(`${FREE}|2026-11-24|read`) ?? 0) - 0.044) < 1e-9);
});

test("apps with the shared token keep working, with the old per-device limits", async () => {
  const { call, store } = await start({ dailyReadLimit: 1 });
  assert.equal((await call("POST", "/v1/read-page", "shared-secret", PAGE)).status, 200);
  assert.equal((await call("POST", "/v1/read-page", "shared-secret", PAGE)).status, 429);
  assert.equal(store.counts.size, 0, "nothing is written to Supabase for them");
});

test("once ALLOW_APP_TOKEN is off, old apps are told to update", async () => {
  const { call } = await start({ allowAppToken: false });
  const res = await call("POST", "/v1/read-page", "shared-secret", PAGE);
  assert.equal(res.status, 401);
  assert.equal(((await res.json()) as ErrorBody).error.code, "update_required");
  assert.equal((await call("POST", "/v1/read-page", "free.tok.en", PAGE)).status, 200);
});

test("a bad or expired sign-in is 401 session_expired; a wrong app token stays unauthorized", async () => {
  const { call } = await start();
  const expired = await call("POST", "/v1/read-page", "old.tok.en", PAGE);
  assert.equal(expired.status, 401);
  assert.equal(((await expired.json()) as ErrorBody).error.code, "session_expired");
  const wrong = await call("POST", "/v1/read-page", "nope", PAGE);
  assert.equal(((await wrong.json()) as ErrorBody).error.code, "unauthorized");
  assert.equal((await call("POST", "/v1/read-page", null, PAGE)).status, 401);
});

test("when Supabase is down, nothing reaches Claude and the app is told to retry", async () => {
  const { call, store, claudeCalls } = await start();
  store.down = true;
  const res = await call("POST", "/v1/read-page", "free.tok.en", PAGE);
  assert.equal(res.status, 503);
  assert.equal(((await res.json()) as ErrorBody).error.code, "accounts_unavailable");
  assert.equal(res.headers.get("retry-after"), "30");
  assert.equal(claudeCalls(), 0);
});

test("the server-wide spend cap still stops signed-in users", async () => {
  const { call } = await start({ dailyBudgetUsd: 0.03 });
  assert.equal((await call("POST", "/v1/read-page", "free.tok.en", PAGE)).status, 200);
  assert.equal((await call("POST", "/v1/read-page", "free.tok.en", PAGE)).status, 200);
  const third = await call("POST", "/v1/read-page", "free.tok.en", PAGE);
  assert.equal(third.status, 503);
  assert.equal(((await third.json()) as ErrorBody).error.code, "budget");
});

test("/v1/me: the plan, the tier and today's usage against its limits", async () => {
  const { call } = await start();
  await call("POST", "/v1/read-page", "anon.tok.en", PAGE);
  const res = await call("GET", "/v1/me", "anon.tok.en");
  assert.equal(res.status, 200);
  const me = (await res.json()) as Record<string, unknown>;
  assert.deepEqual(me.user, { id: ANON, anonymous: true });
  assert.equal(me.tier, "anonymous");
  assert.deepEqual(me.plan, { name: null, startedAt: null, endsAt: null, test: false });
  assert.equal(me.day, "2026-11-24");
  assert.deepEqual(me.today, {
    read: { used: 1, limit: 2 },
    study: { used: 0, limit: 1 },
    check: { used: 0, limit: 1 },
  });
  const legacy = await call("GET", "/v1/me", "shared-secret");
  assert.equal(legacy.status, 401);
  assert.equal(((await legacy.json()) as ErrorBody).error.code, "sign_in_required");
});

test("test purchases: a plan switched on for its months, then back to Free", async () => {
  const { call, store } = await start();
  const on = await call("POST", "/v1/plan/test", "free.tok.en", { plan: "semester" });
  assert.equal(on.status, 200);
  const me = (await on.json()) as { tier: string; plan: Record<string, unknown>; today: Record<string, { limit: number | null }> };
  assert.equal(me.tier, "plus");
  assert.deepEqual(me.plan, {
    name: "semester",
    startedAt: "2026-11-24T04:00:00.000Z",
    endsAt: "2027-05-24T04:00:00.000Z",
    test: true,
  });
  assert.equal(me.today.study!.limit, null, "0 = no limit, sent as null");
  assert.equal(store.plans.get(FREE)?.name, "semester");

  const off = (await (await call("POST", "/v1/plan/test", "free.tok.en", { plan: null })).json()) as { tier: string };
  assert.equal(off.tier, "free");
  assert.equal((await call("POST", "/v1/plan/test", "free.tok.en", { plan: "lifetime" })).status, 400);
  assert.equal((await call("POST", "/v1/plan/test", "shared-secret", { plan: "monthly" })).status, 401);
});

test("test purchases can be switched off", async () => {
  const { call } = await start({ testPurchases: false });
  const res = await call("POST", "/v1/plan/test", "free.tok.en", { plan: "monthly" });
  assert.equal(res.status, 403);
  assert.equal(((await res.json()) as ErrorBody).error.code, "test_purchases_off");
});

test("DELETE /v1/me deletes the account and its usage", async () => {
  const { call, store, logs } = await start();
  await call("POST", "/v1/read-page", "free.tok.en", PAGE);
  const res = await call("DELETE", "/v1/me", "free.tok.en");
  assert.equal(res.status, 204);
  assert.deepEqual(store.deleted, [FREE]);
  assert.equal(store.counts.get(`${FREE}|2026-11-24|read`), undefined);
  assert.ok(logs.some((l) => l.msg === "account deleted"));
  assert.equal((await call("DELETE", "/v1/me", "shared-secret")).status, 401);
});

test("the log line names the user only by a one-way code, with their tier", async () => {
  const { call, logs } = await start();
  const res = await call("POST", "/v1/read-page", "free.tok.en", PAGE);
  const id = res.headers.get("x-request-id");
  await new Promise((r) => setTimeout(r, 20));
  const line = logs.find((l) => l.requestId === id && l.msg === "request");
  assert.ok(line, "a log line");
  assert.match(String(line.user), /^[0-9a-f]{12}$/);
  assert.equal(line.tier, "free");
  assert.ok(!JSON.stringify(logs).includes(FREE), "the user id itself is never logged");
});

test("with accounts off, the account routes don't exist and JWTs aren't accepted", async () => {
  const { call } = await start({ accounts: undefined });
  assert.equal((await call("GET", "/v1/me", "shared-secret")).status, 404);
  assert.equal((await call("POST", "/v1/read-page", "free.tok.en", PAGE)).status, 401);
  assert.equal((await call("POST", "/v1/read-page", "shared-secret", PAGE)).status, 200);
});

test("browsers may call DELETE (CORS)", async () => {
  const { call } = await start();
  const res = await call("OPTIONS", "/v1/me", null);
  assert.match(res.headers.get("access-control-allow-methods") ?? "", /DELETE/);
});
