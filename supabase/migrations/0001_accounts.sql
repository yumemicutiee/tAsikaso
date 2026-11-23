-- tAsikaso: accounts, plans and daily usage.
--
-- Supabase holds only what must be trusted or shared between the app and
-- the study server: who a user is (auth.users, made by Supabase Auth), their
-- tAsikaso+ plan, how much Claude they used each day, and payments. Notes,
-- photos and flashcards stay on the phone and in the student's own Google
-- Drive.
--
-- Who writes what: the study server, with the project's secret key (which
-- bypasses row-level security), writes plans, usage and payments. The app,
-- signed in as the user, may only READ its own rows. Nothing here is
-- writable from the app.
--
-- Run once in the Supabase dashboard: SQL Editor -> New query -> paste this
-- whole file -> Run. Running it twice fails at the first "create table"
-- and changes nothing.

begin;

-- One row per user, made automatically when the user signs up (Google or
-- anonymous). plan is null on the free plan.
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default '',
  plan text check (plan in ('monthly', 'semester', 'yearly')),
  plan_started_at timestamptz,
  -- When the current period ends; the plan is active until then.
  plan_ends_at timestamptz,
  -- Switched on without payment (test purchases, before real payments).
  test_purchase boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint plan_has_dates check (
    plan is null or (plan_started_at is not null and plan_ends_at is not null)
  )
);

comment on table public.profiles is
  'tAsikaso: one row per user; the plan is written only by the study server.';

-- How much Claude each user used each day ("day" is the server's day, in
-- Asia/Manila). kind: study = study kits and quizzes, check = typed answers
-- marked, read = page photos read.
create table public.usage_daily (
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null,
  kind text not null check (kind in ('study', 'check', 'read')),
  count integer not null default 0 check (count >= 0),
  cost_usd numeric(12, 6) not null default 0 check (cost_usd >= 0),
  primary key (user_id, day, kind)
);

comment on table public.usage_daily is
  'tAsikaso: requests and estimated Claude cost per user, day and kind.';

-- Payments, once real payments exist (GCash/Maya or Google Play). A deleted
-- account keeps its payment rows without the link to the user, for the
-- books.
create table public.payments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users (id) on delete set null,
  provider text not null,
  provider_ref text,
  plan text check (plan in ('monthly', 'semester', 'yearly')),
  amount_php numeric(10, 2),
  status text not null,
  created_at timestamptz not null default now(),
  raw jsonb
);

create index payments_user_id on public.payments (user_id);

comment on table public.payments is
  'tAsikaso: payments, written only by the study server (payment webhooks).';

-- Row-level security: a signed-in user reads only their own rows, and no
-- one writes through the app (there are no insert, update or delete
-- policies). The study server's secret key bypasses these rules.
alter table public.profiles enable row level security;
alter table public.usage_daily enable row level security;
alter table public.payments enable row level security;

-- And, as a second lock, the app's roles get no write privilege at all;
-- signed-out visitors (anon) can't even read.
revoke insert, update, delete, truncate on public.profiles, public.usage_daily, public.payments
  from anon, authenticated;
revoke select on public.profiles, public.usage_daily, public.payments from anon;

create policy "Users read their own profile"
  on public.profiles for select to authenticated
  using ((select auth.uid()) = id);

create policy "Users read their own usage"
  on public.usage_daily for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "Users read their own payments"
  on public.payments for select to authenticated
  using ((select auth.uid()) = user_id);

-- A profile for every new user. The name comes from Google when there is
-- one; anonymous users start with none.
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    left(coalesce(
      new.raw_user_meta_data ->> 'full_name',
      new.raw_user_meta_data ->> 'name',
      ''
    ), 200)
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Counts one request against today's limit in one step, so two requests
-- arriving together can't both slip past it. Returns the new count, or -1
-- when the limit was already reached (nothing is counted then).
-- p_limit 0 = no limit.
create function public.consume_allowance(
  p_user uuid,
  p_day date,
  p_kind text,
  p_limit integer
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  n integer;
begin
  insert into public.usage_daily as u (user_id, day, kind, count)
  values (p_user, p_day, p_kind, 1)
  on conflict (user_id, day, kind) do update
    set count = u.count + 1
    where p_limit <= 0 or u.count < p_limit
  returning u.count into n;
  return coalesce(n, -1);
end;
$$;

-- Adds what a Claude call cost to the user's row for that day and kind.
create function public.record_cost(
  p_user uuid,
  p_day date,
  p_kind text,
  p_cost numeric
)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.usage_daily
     set cost_usd = cost_usd + greatest(p_cost, 0)
   where user_id = p_user and day = p_day and kind = p_kind;
$$;

-- Only the study server (service_role, the secret key) may call these.
-- Supabase lets anon and authenticated run new functions by default.
revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.consume_allowance(uuid, date, text, integer) from public, anon, authenticated;
revoke execute on function public.record_cost(uuid, date, text, numeric) from public, anon, authenticated;
grant execute on function public.consume_allowance(uuid, date, text, integer) to service_role;
grant execute on function public.record_cost(uuid, date, text, numeric) to service_role;

commit;
