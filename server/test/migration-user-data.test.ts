import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { after, before, test } from "node:test";

import { PGlite } from "@electric-sql/pglite";

// supabase/migrations/0002_user_data.sql on a real Postgres (PGlite), after
// 0001, with stand-ins for what Supabase provides (see migration.test.ts).

const read = (name: string) =>
  readFileSync(new URL(`../../supabase/migrations/${name}`, import.meta.url), "utf8");
const A = "11111111-1111-4111-8111-111111111111";
const B = "22222222-2222-4222-8222-222222222222";

let db: PGlite;

before(async () => {
  db = new PGlite();
  await db.exec(`
    create role anon nologin;
    create role authenticated nologin;
    create role service_role nologin bypassrls;
    create schema auth;
    create table auth.users (id uuid primary key, raw_user_meta_data jsonb default '{}'::jsonb, is_anonymous boolean default false);
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
  await db.exec(`insert into auth.users (id) values ('${A}'), ('${B}');`);
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

const DATA = JSON.stringify({ v: 1, prefs: { name: "Kristine" }, sessions: [{ end: "2026-11-21T09:00:00", min: 25 }] });

test("a user adds, reads and changes their own row (the app's upsert)", async () => {
  await as("authenticated", A, async () => {
    await db.query(
      `insert into public.user_data (user_id, data, photo, app_version) values ($1, $2::jsonb, 'abc', '0.8.0')
       on conflict (user_id) do update set data = excluded.data, app_version = excluded.app_version`,
      [A, DATA],
    );
    const rows = (await db.query<{ data: { prefs: { name: string } }; photo: string }>("select data, photo from public.user_data")).rows;
    assert.equal(rows.length, 1);
    assert.equal(rows[0]!.data.prefs.name, "Kristine");
    // Upsert again without the photo: the photo stays.
    await db.query(
      `insert into public.user_data (user_id, data) values ($1, $2::jsonb)
       on conflict (user_id) do update set data = excluded.data`,
      [A, JSON.stringify({ v: 1, prefs: { name: "Kris" } })],
    );
    const again = (await db.query<{ data: { prefs: { name: string } }; photo: string }>("select data, photo from public.user_data")).rows[0]!;
    assert.equal(again.data.prefs.name, "Kris");
    assert.equal(again.photo, "abc");
  });
});

test("the server's clock sets updated_at, whatever the app sends", async () => {
  await as("authenticated", A, async () => {
    await db.query(`update public.user_data set updated_at = '2000-01-01' where user_id = $1`, [A]);
  });
  const { updated_at } = (await db.query<{ updated_at: Date }>("select updated_at from public.user_data where user_id = $1", [A])).rows[0]!;
  assert.ok(new Date(updated_at).getFullYear() >= 2026);
});

test("a user can't read, add or change anyone else's row, or delete their own", async () => {
  await as("authenticated", B, async () => {
    assert.equal((await db.query("select * from public.user_data")).rows.length, 0, "A's row is invisible to B");
    await assert.rejects(
      db.query(`insert into public.user_data (user_id, data) values ('${A}', '{}')`),
      /row-level security/,
    );
    const changed = await db.query(`update public.user_data set data = '{"hacked": true}' where user_id = '${A}'`);
    assert.equal(changed.affectedRows ?? 0, 0);
  });
  await as("authenticated", A, async () => {
    await assert.rejects(db.query(`delete from public.user_data where user_id = '${A}'`), /permission denied/);
  });
  const still = (await db.query<{ data: Record<string, unknown> }>("select data from public.user_data where user_id = $1", [A])).rows[0]!;
  assert.equal(still.data.hacked, undefined);
});

test("signed-out visitors can't read it", async () => {
  await as("anon", "", async () => {
    await assert.rejects(db.query("select * from public.user_data"), /permission denied/);
  });
});

test("size caps: a huge photo or non-object data is refused", async () => {
  await as("authenticated", B, async () => {
    await assert.rejects(
      db.query(`insert into public.user_data (user_id, data, photo) values ('${B}', '{}', repeat('x', 800000))`),
      /user_data_photo_size/,
    );
    await assert.rejects(
      db.query(`insert into public.user_data (user_id, data) values ('${B}', '[1,2,3]')`),
      /user_data_is_object/,
    );
  });
});

test("the study server (secret key) can read every row, for the admin page", async () => {
  await as("service_role", "", async () => {
    assert.equal((await db.query("select * from public.user_data")).rows.length, 1);
  });
});

test("deleting the account deletes its data", async () => {
  await db.query("delete from auth.users where id = $1", [A]);
  assert.equal((await db.query("select 1 from public.user_data where user_id = $1", [A])).rows.length, 0);
});
