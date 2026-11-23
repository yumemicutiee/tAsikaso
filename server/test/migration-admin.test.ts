import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { after, before, test } from "node:test";

import { PGlite } from "@electric-sql/pglite";

// supabase/migrations/0003_admin.sql on a real Postgres (PGlite), after 0001
// and 0002, with stand-ins for what Supabase provides (see
// migration.test.ts). The admin functions read auth.users, so the stand-in
// has its email, created_at and is_anonymous columns.

const read = (name: string) =>
  readFileSync(new URL(`../../supabase/migrations/${name}`, import.meta.url), "utf8");
const A = "11111111-1111-4111-8111-111111111111";
const B = "22222222-2222-4222-8222-222222222222";
const ANON = "33333333-3333-4333-8333-333333333333";
const OLD = "44444444-4444-4444-8444-444444444444";
const TZ = "Asia/Manila";

let db: PGlite;

before(async () => {
  db = new PGlite();
  await db.exec(`
    create role anon nologin;
    create role authenticated nologin;
    create role service_role nologin bypassrls;
    create schema auth;
    create table auth.users (
      id uuid primary key,
      email text,
      raw_user_meta_data jsonb default '{}'::jsonb,
      is_anonymous boolean default false,
      created_at timestamptz not null default now()
    );
    create function auth.uid() returns uuid language sql stable as $$
      select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
    $$;
    grant usage on schema auth to anon, authenticated, service_role;
    grant execute on function auth.uid() to anon, authenticated, service_role;
    grant usage on schema public to anon, authenticated, service_role;
    alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
    alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
  `);
  await db.exec(read("0001_accounts.sql"));
  await db.exec(read("0002_user_data.sql"));
  await db.exec(read("0003_admin.sql"));
  await db.exec(`
    insert into auth.users (id, email, raw_user_meta_data) values
      ('${A}', 'kristine@example.com', '{"full_name": "Kristine Degamo"}'),
      ('${B}', 'budi@example.com', '{"name": "Budi"}');
    insert into auth.users (id, is_anonymous) values ('${ANON}', true);
    insert into auth.users (id, email, created_at) values ('${OLD}', 'old@example.com', now() - interval '400 days');
    update public.profiles set plan = 'semester', plan_started_at = now(),
      plan_ends_at = now() + interval '6 months', test_purchase = true where id = '${A}';
    update public.profiles set plan = 'monthly', plan_started_at = now() - interval '40 days',
      plan_ends_at = now() - interval '10 days' where id = '${B}';
  `);
});
after(() => db.close());

async function as<T>(role: string, sub: string, fn: () => Promise<T>): Promise<T> {
  await db.exec(`set role ${role}; select set_config('request.jwt.claim.sub', '${sub}', false);`);
  try {
    return await fn();
  } finally {
    await db.exec(`reset role;`);
  }
}

const call = async <T>(sql: string, params: unknown[] = []) =>
  (await db.query<{ r: T }>(sql, params)).rows[0]!.r;

type Overview = {
  total: number;
  anonymous: number;
  google: number;
  newThisWeek: number;
  newThisMonth: number;
  newThisYear: number;
  newLastYear: number;
  daily: { day: string; count: number }[];
  monthly: { month: string; count: number }[];
  plans: Record<string, number>;
};

test("the overview counts users, new users per period, and active plans", async () => {
  const o = await call<Overview>("select public.admin_overview($1) as r", [TZ]);
  assert.equal(o.total, 4);
  assert.equal(o.anonymous, 1);
  assert.equal(o.google, 3);
  assert.equal(o.newThisWeek, 3);
  assert.equal(o.newThisMonth, 3);
  assert.equal(o.newThisYear, 3);
  assert.equal(o.daily.length, 30);
  assert.equal(o.daily.at(-1)!.count, 3);
  assert.equal(o.monthly.length, 12);
  assert.equal(o.monthly.at(-1)!.count, 3);
  // B's plan ended: only A's (a test plan) is active.
  assert.deepEqual(o.plans, { free: 3, monthly: 0, semester: 1, yearly: 0, test: 1, endingIn7Days: 0 });
});

test("users: newest first, searchable by email, name or id, and paged", async () => {
  type Page = { total: number; rows: { id: string; email: string | null; plan: string | null; test: boolean; anonymous: boolean }[] };
  const all = await call<Page>("select public.admin_users('', 25, 0) as r");
  assert.equal(all.total, 4);
  assert.equal(all.rows.at(-1)!.id, OLD);
  const a = all.rows.find((r) => r.id === A)!;
  assert.equal(a.plan, "semester");
  assert.equal(a.test, true);
  // An ended plan reads as Free.
  assert.equal(all.rows.find((r) => r.id === B)!.plan, null);

  assert.deepEqual((await call<Page>("select public.admin_users('KRISTINE@', 25, 0) as r")).rows.map((r) => r.id), [A]);
  assert.deepEqual((await call<Page>("select public.admin_users('budi', 25, 0) as r")).rows.map((r) => r.id), [B]);
  assert.deepEqual((await call<Page>("select public.admin_users('3333-4333', 25, 0) as r")).rows.map((r) => r.id), [ANON]);
  // Wildcards are plain text, not patterns.
  assert.equal((await call<Page>("select public.admin_users('%', 25, 0) as r")).total, 0);

  const second = await call<Page>("select public.admin_users('', 2, 2) as r");
  assert.equal(second.total, 4);
  assert.equal(second.rows.length, 2);
});

test("payments: this month's paid total and the latest, demo ones marked", async () => {
  await db.exec(`
    insert into public.payments (user_id, provider, plan, amount_php, status, demo)
      values ('${A}', 'demo', 'semester', 199, 'paid', true),
             ('${B}', 'demo', 'monthly', 49, 'paid', true);
    insert into public.payments (user_id, provider, plan, amount_php, status, created_at)
      values ('${B}', 'gcash', 'monthly', 49, 'paid', now() - interval '70 days');
  `);
  type Pay = { monthTotalPhp: number; monthCount: number; anyDemo: boolean; recent: { email: string; demo: boolean }[] };
  const p = await call<Pay>("select public.admin_payments($1, 10) as r", [TZ]);
  assert.equal(Number(p.monthTotalPhp), 248);
  assert.equal(p.monthCount, 2);
  assert.equal(p.anyDemo, true);
  assert.equal(p.recent.length, 3);
  assert.equal(p.recent.filter((r) => r.demo).length, 2);
});

test("crash reports are grouped, and old ones pruned", async () => {
  await db.exec(`
    insert into public.crash_reports (user_id, message, stack, version, platform) values
      ('${A}', 'RangeError', 'at a', '0.8.0', 'android'),
      ('${B}', 'RangeError', 'at b', '0.8.0', 'android'),
      (null, 'Null check', null, '0.8.0', 'web');
    insert into public.crash_reports (message, version, platform, created_at)
      values ('Ancient', '0.1.0', 'android', now() - interval '100 days');
  `);
  type Crashes = { total: number; users: number; groups: { message: string; count: number; users: number }[] };
  const c = await call<Crashes>("select public.admin_crashes(7) as r");
  assert.equal(c.total, 3);
  assert.equal(c.users, 2);
  const range = c.groups.find((g) => g.message === "RangeError")!;
  assert.equal(range.count, 2);
  assert.equal(range.users, 2);
  assert.equal(await call<number>("select public.prune_crash_reports() as r"), 1);
});

test("students can't read crash reports or call the admin functions", async () => {
  for (const role of ["anon", "authenticated"]) {
    await assert.rejects(as(role, A, () => db.query("select * from public.crash_reports")), /permission denied/);
    await assert.rejects(as(role, A, () => db.query("select public.admin_overview('Asia/Manila')")), /permission denied/);
    await assert.rejects(as(role, A, () => db.query("select public.admin_users('', 25, 0)")), /permission denied/);
    await assert.rejects(as(role, A, () => db.query("select public.admin_payments('Asia/Manila', 10)")), /permission denied/);
    await assert.rejects(as(role, A, () => db.query("select public.admin_crashes(7)")), /permission denied/);
    await assert.rejects(as(role, A, () => db.query("select public.prune_crash_reports()")), /permission denied/);
  }
  // A student still sees only their own payments (0001's rule), demo or not.
  const own = await as("authenticated", A, () => db.query<{ user_id: string }>("select user_id from public.payments"));
  assert.deepEqual(own.rows.map((r) => r.user_id), [A]);
});

test("the server's role can call everything", async () => {
  await as("service_role", "", async () => {
    await db.query("select public.admin_overview('Asia/Manila')");
    await db.query("select public.admin_users('', 25, 0)");
    await db.query("select public.admin_payments('Asia/Manila', 10)");
    await db.query("select public.admin_crashes(7)");
    await db.query("insert into public.crash_reports (message, version, platform) values ('x', '1', 'web')");
  });
});
