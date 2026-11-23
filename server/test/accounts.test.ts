import assert from "node:assert/strict";
import { createServer, type IncomingMessage, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import { after, before, test } from "node:test";

import { exportJWK, generateKeyPair, type JWK, SignJWT } from "jose";

import {
  AccountsUnavailableError,
  addMonths,
  BadTokenError,
  FREE_PLAN,
  looksLikeJwt,
  planActive,
  SupabaseStore,
  supabaseVerifier,
  tierOf,
} from "../src/accounts.js";
import { ConfigError, readConfig } from "../src/config.js";

// Sign-in tokens checked the way Supabase signs them (ES256, published
// keys), and the Supabase REST calls, against local stand-ins.

const USER = "28e37b9c-2a2e-43fb-bfd1-08ab8cc363ad";

let jwksServer: Server;
let base: string;
let privateKey: CryptoKey;
let otherKey: CryptoKey;
let jwks: { keys: JWK[] } = { keys: [] };
let jwksDown = false;

before(async () => {
  const pair = await generateKeyPair("ES256");
  privateKey = pair.privateKey;
  otherKey = (await generateKeyPair("ES256")).privateKey;
  const jwk = await exportJWK(pair.publicKey);
  jwks = { keys: [{ ...jwk, kid: "key-1", alg: "ES256", use: "sig" }] };
  jwksServer = createServer((req, res) => {
    if (jwksDown) {
      res.writeHead(503).end("down");
      return;
    }
    if (req.url === "/auth/v1/.well-known/jwks.json") {
      res.writeHead(200, { "content-type": "application/json" }).end(JSON.stringify(jwks));
      return;
    }
    res.writeHead(404).end();
  });
  await new Promise<void>((r) => jwksServer.listen(0, "127.0.0.1", r));
  base = `http://127.0.0.1:${(jwksServer.address() as AddressInfo).port}`;
});
after(() => jwksServer.close());

async function token(
  claims: Record<string, unknown> = {},
  opts: { key?: CryptoKey; issuer?: string; audience?: string; expires?: string } = {},
) {
  return new SignJWT({ role: "authenticated", is_anonymous: false, ...claims })
    .setProtectedHeader({ alg: "ES256", kid: "key-1" })
    .setSubject((claims.sub as string | undefined) ?? USER)
    .setIssuer(opts.issuer ?? `${base}/auth/v1`)
    .setAudience(opts.audience ?? "authenticated")
    .setIssuedAt()
    .setExpirationTime(opts.expires ?? "1h")
    .sign(opts.key ?? privateKey);
}

test("a Supabase token signed with the project's key names the user, anonymous or not", async () => {
  const verifier = supabaseVerifier(base);
  assert.deepEqual(await verifier.verify(await token()), { id: USER, anonymous: false });
  assert.deepEqual(await verifier.verify(await token({ is_anonymous: true })), {
    id: USER,
    anonymous: true,
  });
  // The signed email (Google accounts), lower case, for the admin check.
  assert.deepEqual(await verifier.verify(await token({ email: " Owner@Example.com " })), {
    id: USER,
    anonymous: false,
    email: "owner@example.com",
  });
  assert.deepEqual(await verifier.verify(await token({ email: "" })), { id: USER, anonymous: false });
});

test("expired, foreign, forged or odd tokens are refused as bad tokens", async () => {
  const verifier = supabaseVerifier(base);
  const bad = [
    await token({}, { expires: "-1m" }),
    await token({}, { issuer: "https://someone-else.supabase.co/auth/v1" }),
    await token({}, { audience: "anon" }),
    await token({}, { key: otherKey }),
    await token({ role: "anon" }),
    await token({ sub: "not-a-uuid" }),
    "a.b.c",
  ];
  for (const t of bad) {
    await assert.rejects(verifier.verify(t), BadTokenError, t.slice(0, 40));
  }
});

test("when the signing keys can't be fetched, it's Supabase's problem, not the user's", async () => {
  jwksDown = true;
  try {
    await assert.rejects(supabaseVerifier(base).verify(await token()), AccountsUnavailableError);
    await assert.rejects(
      supabaseVerifier("http://127.0.0.1:9").verify(await token({}, { issuer: "http://127.0.0.1:9/auth/v1" })),
      AccountsUnavailableError,
    );
  } finally {
    jwksDown = false;
  }
});

test("looksLikeJwt tells a Supabase token from the shared app token", async () => {
  assert.equal(looksLikeJwt(await token()), true);
  assert.equal(looksLikeJwt("3f9c2a7b1e0d4c6a8b5e2f1a0c9d8e7f"), false);
  assert.equal(looksLikeJwt("has.dots but spaces.x"), false);
});

test("plans: active until they end; tiers follow plan, then account", () => {
  const now = Date.parse("2026-11-24T00:00:00Z");
  const plus = {
    name: "semester" as const,
    startedAt: "2026-11-01T00:00:00.000Z",
    endsAt: "2027-05-01T00:00:00.000Z",
    test: true,
  };
  const ended = { ...plus, endsAt: "2026-11-23T00:00:00.000Z" };
  assert.equal(planActive(plus, now), true);
  assert.equal(planActive(ended, now), false);
  assert.equal(planActive(FREE_PLAN, now), false);
  assert.equal(tierOf({ id: USER, anonymous: true }, FREE_PLAN, now), "anonymous");
  assert.equal(tierOf({ id: USER, anonymous: false }, FREE_PLAN, now), "free");
  assert.equal(tierOf({ id: USER, anonymous: false }, ended, now), "free");
  assert.equal(tierOf({ id: USER, anonymous: true }, plus, now), "plus");
  assert.equal(
    addMonths(new Date("2026-11-24T10:30:00Z"), 6).toISOString(),
    "2027-05-24T10:30:00.000Z",
  );
});

// --- SupabaseStore against a stand-in REST API ------------------------------

interface Seen {
  method: string;
  url: string;
  headers: IncomingMessage["headers"];
  body: unknown;
}

async function fakeRest(reply: (seen: Seen) => { status?: number; body?: unknown }) {
  const seen: Seen[] = [];
  const server = createServer((req, res) => {
    let raw = "";
    req.on("data", (c) => (raw += c));
    req.on("end", () => {
      const s = {
        method: req.method ?? "",
        url: req.url ?? "",
        headers: req.headers,
        body: raw ? JSON.parse(raw) : undefined,
      };
      seen.push(s);
      const r = reply(s);
      res.writeHead(r.status ?? 200, { "content-type": "application/json" });
      res.end(r.body === undefined ? "" : JSON.stringify(r.body));
    });
  });
  await new Promise<void>((r) => server.listen(0, "127.0.0.1", r));
  const url = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  return { url, seen, close: () => server.close() };
}

test("the store calls Supabase's REST API with the secret key in apikey only", async () => {
  const rest = await fakeRest((s) => {
    if (s.url.startsWith("/rest/v1/profiles?")) {
      return s.method === "GET"
        ? { body: [{ plan: "yearly", plan_started_at: "2026-11-24T00:00:00+00:00", plan_ends_at: "2027-11-24T00:00:00+00:00", test_purchase: true }] }
        : { body: [{ plan: null, plan_started_at: null, plan_ends_at: null, test_purchase: false }] };
    }
    if (s.url === "/rest/v1/rpc/consume_allowance") return { body: 3 };
    if (s.url === "/rest/v1/rpc/record_cost") return { status: 204 };
    if (s.url.startsWith("/rest/v1/usage_daily?")) return { body: [{ kind: "read", count: 4 }, { kind: "check", count: 1 }] };
    if (s.url.startsWith("/auth/v1/admin/users/")) return { body: {} };
    return { status: 404 };
  });
  try {
    const store = new SupabaseStore(rest.url + "/", "sb_secret_test");
    assert.deepEqual(await store.plan(USER), {
      name: "yearly",
      startedAt: "2026-11-24T00:00:00.000Z",
      endsAt: "2027-11-24T00:00:00.000Z",
      test: true,
    });
    assert.equal(await store.consume(USER, "2026-11-24", "read", 50), 3);
    await store.recordCost(USER, "2026-11-24", "read", 0.0223456789);
    assert.deepEqual(await store.usage(USER, "2026-11-24"), { read: 4, check: 1, study: 0 });
    assert.deepEqual(await store.setPlan(USER, FREE_PLAN), FREE_PLAN);
    await store.deleteUser(USER);

    for (const s of rest.seen) {
      assert.equal(s.headers.apikey, "sb_secret_test", s.url);
      assert.equal(s.headers.authorization, undefined, "a new-style key isn't sent as a bearer");
    }
    const [getPlan, consume, cost, usage, patch, del] = rest.seen;
    assert.equal(getPlan!.url, `/rest/v1/profiles?id=eq.${USER}&select=plan,plan_started_at,plan_ends_at,test_purchase`);
    assert.deepEqual(consume!.body, { p_user: USER, p_day: "2026-11-24", p_kind: "read", p_limit: 50 });
    assert.deepEqual(cost!.body, { p_user: USER, p_day: "2026-11-24", p_kind: "read", p_cost: 0.022346 });
    assert.equal(usage!.url, `/rest/v1/usage_daily?user_id=eq.${USER}&day=eq.2026-11-24&select=kind,count`);
    assert.equal(patch!.method, "PATCH");
    assert.equal(patch!.headers.prefer, "return=representation");
    assert.equal((patch!.body as Record<string, unknown>).plan, null);
    assert.equal(del!.method, "DELETE");
    assert.equal(del!.url, `/auth/v1/admin/users/${USER}`);
  } finally {
    rest.close();
  }
});

test("a legacy service_role key (a JWT) is also sent as the bearer", async () => {
  const rest = await fakeRest(() => ({ body: [] }));
  try {
    await new SupabaseStore(rest.url, "eyJhbGciOiJIUzI1NiJ9.e30.sig").plan(USER);
    assert.equal(rest.seen[0]!.headers.authorization, "Bearer eyJhbGciOiJIUzI1NiJ9.e30.sig");
  } finally {
    rest.close();
  }
});

test("a profile that isn't there yet reads as the free plan", async () => {
  const rest = await fakeRest(() => ({ body: [] }));
  try {
    assert.deepEqual(await new SupabaseStore(rest.url, "sb_secret_test").plan(USER), FREE_PLAN);
  } finally {
    rest.close();
  }
});

test("Supabase errors and an unreachable Supabase are AccountsUnavailableError", async () => {
  const rest = await fakeRest(() => ({ status: 500, body: { message: "boom" } }));
  try {
    await assert.rejects(new SupabaseStore(rest.url, "sb_secret_test").consume(USER, "2026-11-24", "read", 5), AccountsUnavailableError);
  } finally {
    rest.close();
  }
  await assert.rejects(new SupabaseStore("http://127.0.0.1:9", "sb_secret_test").plan(USER), AccountsUnavailableError);
});

// --- Settings ----------------------------------------------------------------------

test("Supabase settings: both or neither, the right key, limits per tier", () => {
  const ok = readConfig({
    SUPABASE_URL: "https://zwresopjspwugugikrqt.supabase.co/",
    SUPABASE_SECRET_KEY: "sb_secret_x",
    READ_LIMITS: "5, 10, 0",
  });
  assert.equal(ok.supabaseUrl, "https://zwresopjspwugugikrqt.supabase.co");
  assert.deepEqual(ok.tierLimits.read, { anonymous: 5, free: 10, plus: 0 });
  assert.deepEqual(ok.tierLimits.study, { anonymous: 10, free: 30, plus: 100 });
  assert.equal(ok.allowAppToken, true);
  assert.equal(ok.testPurchases, true);

  const off = readConfig({});
  assert.equal(off.supabaseUrl, "");
  assert.equal(readConfig({ ALLOW_APP_TOKEN: "0", TEST_PURCHASES: "0" }).allowAppToken, false);

  assert.throws(() => readConfig({ SUPABASE_URL: "https://x.supabase.co" }), ConfigError);
  assert.throws(() => readConfig({ SUPABASE_SECRET_KEY: "sb_secret_x" }), ConfigError);
  assert.throws(
    () => readConfig({ SUPABASE_URL: "https://x.supabase.co", SUPABASE_SECRET_KEY: "sb_publishable_x" }),
    /publishable/,
  );
  assert.throws(
    () => readConfig({ SUPABASE_URL: "https://evil.example.com", SUPABASE_SECRET_KEY: "sb_secret_x" }),
    ConfigError,
  );
  assert.throws(() => readConfig({ READ_LIMITS: "20,50" }), /three whole numbers/);
  assert.throws(() => readConfig({ CHECK_LIMITS: "1,-2,3" }), ConfigError);
});
