import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { after, before, test } from "node:test";

import { PGlite } from "@electric-sql/pglite";

// supabase/migrations/0001_accounts.sql on a real Postgres (PGlite), with
// stand-ins for what Supabase provides: the auth schema, auth.uid(), the
// API roles and Supabase's default privileges (new tables and functions
// in public are open to every role, so the migration must close them).
// Note: PGlite runs one connection, so requests "at once" run in turn; the
// real guard against two racing requests is Postgres's row lock in
// consume_allowance's INSERT ... ON CONFLICT DO UPDATE.

const SQL = readFileSync(new URL("../../supabase/migrations/0001_accounts.sql", import.meta.url), "utf8");
const A = "11111111-1111-4111-8111-111111111111";
const B = "22222222-2222-4222-8222-222222222222";
const ANON = "33333333-3333-4333-8333-333333333333";

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
      raw_user_meta_data jsonb default '{}'::jsonb,
      is_anonymous boolean default false
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
  await db.exec(SQL);
  await db.exec(`
    insert into auth.users (id, raw_user_meta_data) values
      ('${A}', '{"full_name": "Kristine Degamo"}'), ('${B}', '{"name": "Budi"}');
    insert into auth.users (id, is_anonymous) values ('${ANON}', true);
  `);
});
after(() => db.close());

const take = async (user: string, kind: string, limit: number, day = "2026-11-24") =>
  (await db.query<{ n: number }>("select public.consume_allowance($1, $2, $3, $4) as n", [user, day, kind, limit])).rows[0]!.n;
const count = async (user: string, kind: string, day = "2026-11-24") =>
  (await db.query<{ count: number }>("select count from public.usage_daily where user_id=$1 and kind=$2 and day=$3", [user, kind, day])).rows[0]?.count;

/** Runs [fn] as [role] (and user [sub]), then back to the owner. */
async function as<T>(role: string, sub: string, fn: () => Promise<T>): Promise<T> {
  await db.exec(`set role ${role}; select set_config('request.jwt.claim.sub', '${sub}', false);`);
  try {
    return await fn();
  } finally {
    await db.exec(`reset role;`);
  }
}

test("every new user gets a profile on the free plan, named from Google", async () => {
  const rows = (await db.query<{ id: string; display_name: string; plan: string | null }>(
    "select id, display_name, plan from public.profiles order by id",
  )).rows;
  assert.deepEqual(
    rows.map((r) => [r.id, r.display_name, r.plan]),
    [
      [A, "Kristine Degamo", null],
      [B, "Budi", null],
      [ANON, "", null],
    ],
  );
});

test("consume_allowance counts up to the limit, refuses after, per user, kind and day", async () => {
  assert.equal(await take(A, "read", 2), 1);
  assert.equal(await take(A, "read", 2), 2);
  assert.equal(await take(A, "read", 2), -1);
  assert.equal(await count(A, "read"), 2, "a refused request isn't counted");
  assert.equal(await take(A, "study", 2), 1, "kinds are separate");
  assert.equal(await take(A, "read", 2, "2026-11-25"), 1, "a new day starts again");
  assert.equal(await take(B, "read", 2), 1, "users are separate");
  for (let i = 0; i < 4; i++) await take(B, "check", 0);
  assert.equal(await count(B, "check"), 4, "limit 0 = no limit");
  const many = await Promise.all(Array.from({ length: 20 }, () => take(ANON, "read", 7)));
  assert.equal(many.filter((n) => n > 0).length, 7);
  await assert.rejects(take(A, "photos", 5), /check constraint/);
});

test("record_cost adds to the day's row and ignores negatives", async () => {
  await db.query("select public.record_cost($1, '2026-11-24', 'read', 0.022)", [A]);
  await db.query("select public.record_cost($1, '2026-11-24', 'read', 0.021)", [A]);
  await db.query("select public.record_cost($1, '2026-11-24', 'read', -5)", [A]);
  const { cost_usd } = (await db.query<{ cost_usd: string }>(
    "select cost_usd from public.usage_daily where user_id=$1 and kind='read' and day='2026-11-24'",
    [A],
  )).rows[0]!;
  assert.equal(Number(cost_usd), 0.043);
});

test("a plan needs its dates and a known name", async () => {
  await assert.rejects(db.query("update public.profiles set plan='yearly' where id=$1", [A]), /plan_has_dates/);
  await assert.rejects(
    db.query("update public.profiles set plan='lifetime', plan_started_at=now(), plan_ends_at=now() where id=$1", [A]),
    /profiles_plan_check/,
  );
});

test("a signed-in user reads only their own rows and can write nothing", async () => {
  await db.query(
    "insert into public.payments (user_id, provider, plan, amount_php, status) values ($1, 'test', 'semester', 199, 'paid')",
    [B],
  );
  await as("authenticated", A, async () => {
    assert.deepEqual((await db.query<{ id: string }>("select id from public.profiles")).rows.map((r) => r.id), [A]);
    const users = (await db.query<{ user_id: string }>("select distinct user_id from public.usage_daily")).rows;
    assert.deepEqual(users.map((r) => r.user_id), [A]);
    assert.equal((await db.query("select * from public.payments")).rows.length, 0);
    await assert.rejects(
      db.query(`update public.profiles set plan='yearly', plan_started_at=now(), plan_ends_at=now() + interval '1 year' where id='${A}'`),
      /permission denied/,
    );
    await assert.rejects(
      db.query(`insert into public.usage_daily (user_id, day, kind) values ('${A}', '2026-12-01', 'read')`),
      /permission denied/,
    );
    await assert.rejects(db.query(`delete from public.usage_daily where user_id='${A}'`), /permission denied/);
    await assert.rejects(db.query(`select public.consume_allowance('${A}', '2026-11-24', 'read', 999)`), /permission denied/);
    await assert.rejects(db.query(`select public.record_cost('${A}', '2026-11-24', 'read', 1)`), /permission denied/);
  });
});

test("signed-out visitors can't read anything", async () => {
  await as("anon", "", async () => {
    await assert.rejects(db.query("select * from public.profiles"), /permission denied/);
    await assert.rejects(db.query("select * from public.usage_daily"), /permission denied/);
    await assert.rejects(db.query("select * from public.payments"), /permission denied/);
  });
});

test("the study server (secret key) reads everything and sets plans", async () => {
  await as("service_role", "", async () => {
    assert.equal((await db.query("select * from public.profiles")).rows.length, 3);
    await db.query(
      `update public.profiles set plan='semester', plan_started_at=now(), plan_ends_at=now() + interval '6 months', test_purchase=true where id=$1`,
      [B],
    );
    assert.equal((await db.query<{ n: number }>(`select public.consume_allowance('${B}', '2026-11-26', 'study', 3) as n`)).rows[0]!.n, 1);
  });
});

test("deleting a user removes their profile and usage, keeps payments unlinked", async () => {
  await db.query("delete from auth.users where id=$1", [B]);
  assert.equal((await db.query("select 1 from public.profiles where id=$1", [B])).rows.length, 0);
  assert.equal((await db.query("select 1 from public.usage_daily where user_id=$1", [B])).rows.length, 0);
  const pay = (await db.query<{ user_id: string | null; amount_php: string }>("select user_id, amount_php from public.payments")).rows;
  assert.deepEqual(pay.map((p) => [p.user_id, Number(p.amount_php)]), [[null, 199]]);
});

test("running the file a second time fails and changes nothing", async () => {
  const before = (await db.query<{ n: number }>("select count(*)::int as n from public.usage_daily")).rows[0]!.n;
  await assert.rejects(db.exec(SQL), /already exists/);
  await db.exec("rollback").catch(() => {});
  const after = (await db.query<{ n: number }>("select count(*)::int as n from public.usage_daily")).rows[0]!.n;
  assert.equal(after, before);
});
