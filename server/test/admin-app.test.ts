import assert from "node:assert/strict";
import type { Server } from "node:http";
import type { AddressInfo } from "node:net";
import { after, test } from "node:test";

import {
  type Account,
  type AdminStore,
  BadTokenError,
  MemoryStore,
  type PlanName,
  type StoredCrash,
  type TokenVerifier,
} from "../src/accounts.js";
import { type AppOptions, createApp } from "../src/app.js";
import { ConfigError, emailsFromEnv, readConfig } from "../src/config.js";
import type { LogFields } from "../src/log.js";

// The admin page's routes (/v1/admin/*), crash reports kept for it, and
// demo payments, with a stand-in verifier and a recording admin store.

const OWNER = "aaaaaaaa-0000-4000-8000-000000000001";
const STUDENT = "bbbbbbbb-0000-4000-8000-000000000002";
const ANON = "cccccccc-0000-4000-8000-000000000003";
const TOKENS: Record<string, Account> = {
  "owner.tok.en": { id: OWNER, anonymous: false, email: "owner@example.com" },
  "student.tok.en": { id: STUDENT, anonymous: false, email: "student@example.com" },
  "anon.tok.en": { id: ANON, anonymous: true },
  // An anonymous token can't become an admin, even with an admin's email.
  "anon-owner.tok.en": { id: ANON, anonymous: true, email: "owner@example.com" },
};
const verifier: TokenVerifier = {
  async verify(token) {
    const account = TOKENS[token];
    if (!account) throw new BadTokenError("unknown token");
    return account;
  },
};

class FakeAdminStore implements AdminStore {
  readonly calls: string[] = [];
  readonly crashes_: { userId: string | null; crash: StoredCrash }[] = [];
  readonly demo: { userId: string; plan: PlanName }[] = [];
  pruned = 0;
  async overview(tz: string) {
    this.calls.push(`overview ${tz}`);
    return { total: 3 };
  }
  async users(q: string, limit: number, offset: number) {
    this.calls.push(`users "${q}" ${limit} ${offset}`);
    return { total: 1, rows: [{ id: STUDENT }] };
  }
  async payments(tz: string, limit: number) {
    this.calls.push(`payments ${tz} ${limit}`);
    return { monthTotalPhp: 0 };
  }
  async crashes(days: number) {
    this.calls.push(`crashes ${days}`);
    return { total: 0 };
  }
  async saveCrash(userId: string | null, crash: StoredCrash) {
    this.crashes_.push({ userId, crash });
  }
  async pruneCrashes() {
    this.pruned++;
    return 0;
  }
  async recordDemoPayment(userId: string, plan: PlanName) {
    this.demo.push({ userId, plan });
  }
}

const servers: Server[] = [];
after(() => {
  for (const s of servers) {
    s.closeAllConnections();
    s.close();
  }
});

async function start(options: Partial<AppOptions> = {}) {
  const admin = new FakeAdminStore();
  const logs: (LogFields & { msg: string })[] = [];
  const app = createApp({
    appToken: "shared-secret",
    accounts: { verifier, store: new MemoryStore() },
    admin: { emails: ["Owner@Example.com"], store: admin },
    log: (_level, msg, fields = {}) => logs.push({ msg, ...fields }),
    now: () => Date.parse("2026-11-24T04:00:00Z"),
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
  return { call, admin, logs };
}

const codeOf = async (r: Response) => ((await r.json()) as { error: { code: string } }).error.code;
const settle = () => new Promise((r) => setTimeout(r, 20));

test("only a Google account named in ADMIN_EMAILS gets the dashboard", async () => {
  const { call, admin } = await start();
  const ok = await call("GET", "/v1/admin/dashboard", "owner.tok.en");
  assert.equal(ok.status, 200);
  assert.equal(ok.headers.get("cache-control"), "no-store");
  const body = (await ok.json()) as Record<string, unknown>;
  assert.deepEqual(body.admin, { email: "owner@example.com" });
  assert.equal(body.timeZone, "Asia/Manila");
  assert.equal(body.crashReportsSaved, false);
  assert.deepEqual(body.overview, { total: 3 });
  assert.deepEqual(admin.calls.sort(), ["crashes 7", "overview Asia/Manila", "payments Asia/Manila 6"]);

  for (const token of ["student.tok.en", "anon.tok.en", "anon-owner.tok.en"]) {
    const r = await call("GET", "/v1/admin/dashboard", token);
    assert.equal(r.status, 403, token);
    assert.equal(await codeOf(r), "not_admin");
  }
  // The shared app token is never an admin.
  const app = await call("GET", "/v1/admin/dashboard", "shared-secret");
  assert.equal(app.status, 401);
  assert.equal((await call("GET", "/v1/admin/dashboard", null)).status, 401);
  assert.equal((await call("GET", "/v1/admin/dashboard", "forged.tok.en")).status, 401);
  assert.equal(admin.calls.length, 3, "refused requests read nothing");
});

test("the user list is searched and paged on the server", async () => {
  const { call, admin } = await start();
  const r = await call("GET", "/v1/admin/users?q=%20budi%20&page=3", "owner.tok.en");
  assert.equal(r.status, 200);
  assert.deepEqual(await r.json(), { total: 1, rows: [{ id: STUDENT }], page: 3, pageSize: 25 });
  assert.deepEqual(admin.calls, ['users "budi" 25 50']);
  await call("GET", "/v1/admin/users?page=-4", "owner.tok.en");
  assert.equal(admin.calls[1], 'users "" 25 0');
  assert.equal((await call("GET", "/v1/admin/users", "student.tok.en")).status, 403);
});

test("without ADMIN_EMAILS the admin routes don't exist", async () => {
  const { call } = await start({ admin: { emails: [], store: new FakeAdminStore() } });
  const r = await call("GET", "/v1/admin/dashboard", "owner.tok.en");
  assert.equal(r.status, 404);
});

test("crash reports are kept only with storeCrashReports, with the user's id", async () => {
  const crash = { message: "RangeError", version: "0.8.0", platform: "android" };
  const off = await start();
  assert.equal((await off.call("POST", "/v1/crash", "student.tok.en", crash)).status, 204);
  await settle();
  assert.equal(off.admin.crashes_.length, 0);

  const on = await start({ storeCrashReports: true });
  await on.call("POST", "/v1/crash", "student.tok.en", crash);
  await on.call("POST", "/v1/crash", "shared-secret", crash);
  await settle();
  assert.deepEqual(on.admin.crashes_.map((c) => c.userId), [STUDENT, null]);
  assert.equal(on.admin.pruned, 1, "old reports are pruned once a day");
  assert.ok(on.logs.some((l) => l.msg === "app crash"), "still logged");
  const dash = (await (await on.call("GET", "/v1/admin/dashboard", "owner.tok.en")).json()) as Record<string, unknown>;
  assert.equal(dash.crashReportsSaved, true);
});

test("switching a plan on for free writes a demo payment (unless turned off)", async () => {
  const on = await start();
  assert.equal((await on.call("POST", "/v1/plan/test", "student.tok.en", { plan: "semester" })).status, 200);
  await on.call("POST", "/v1/plan/test", "student.tok.en", { plan: null });
  await settle();
  assert.deepEqual(on.admin.demo, [{ userId: STUDENT, plan: "semester" }], "back to Free pays nothing");

  const off = await start({ demoPayments: false });
  await off.call("POST", "/v1/plan/test", "student.tok.en", { plan: "monthly" });
  await settle();
  assert.equal(off.admin.demo.length, 0);
});

test("ADMIN_EMAILS, STORE_CRASH_REPORTS and DEMO_PAYMENTS settings", () => {
  assert.deepEqual(emailsFromEnv({ ADMIN_EMAILS: " A@x.com, b@y.org ,a@x.com" }, "ADMIN_EMAILS"), ["a@x.com", "b@y.org"]);
  assert.deepEqual(emailsFromEnv({}, "ADMIN_EMAILS"), []);
  assert.throws(() => emailsFromEnv({ ADMIN_EMAILS: "owner" }, "ADMIN_EMAILS"), ConfigError);
  const c = readConfig({});
  assert.deepEqual(c.adminEmails, []);
  assert.equal(c.storeCrashReports, false);
  assert.equal(c.demoPayments, true);
  const d = readConfig({ STORE_CRASH_REPORTS: "1", DEMO_PAYMENTS: "0" });
  assert.equal(d.storeCrashReports, true);
  assert.equal(d.demoPayments, false);
});
