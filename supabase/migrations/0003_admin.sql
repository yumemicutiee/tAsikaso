-- tAsikaso: what the owner's admin page reads (ADMIN_PAGE_PLAN.txt).
--
-- The admin page never touches the database itself. It signs in with
-- Google and asks the study server, which checks that the account is an
-- admin (ADMIN_EMAILS on Render) and then calls the admin_* functions below
-- with the secret key. Students' row-level security is unchanged: nothing
-- here is readable or callable by anon or authenticated.
--
-- Adds:
--   payments.demo   pretend payments for the demo (no real payment method
--                   is connected); written when a plan is switched on for
--                   free, so they never mix with real ones
--   crash_reports   the app's crash reports, kept 90 days (stored only when
--                   the server has STORE_CRASH_REPORTS=1)
--   admin_overview, admin_users, admin_payments, admin_crashes
--
-- Run once after 0002_user_data.sql: SQL Editor -> New query -> paste ->
-- Run. Running it twice fails at "add column" and changes nothing.

begin;

alter table public.payments add column demo boolean not null default false;

comment on column public.payments.demo is
  'tAsikaso: a pretend payment for the demo (no money moved).';

create table public.crash_reports (
  id bigint generated always as identity primary key,
  -- Signed-in users only; a deleted account keeps no link.
  user_id uuid references auth.users (id) on delete set null,
  message text not null check (length(message) between 1 and 1000),
  stack text check (stack is null or length(stack) <= 4000),
  source text check (source is null or length(source) <= 40),
  version text not null check (length(version) <= 40),
  platform text not null check (length(platform) <= 120),
  created_at timestamptz not null default now()
);

create index crash_reports_created_at on public.crash_reports (created_at);
create index crash_reports_user_id on public.crash_reports (user_id);

comment on table public.crash_reports is
  'tAsikaso: app crash reports, written only by the study server; kept 90 days.';

alter table public.crash_reports enable row level security;
revoke all on public.crash_reports from anon, authenticated;

-- Totals, new users per week/month/year (calendar periods in p_tz), new
-- users per day for 30 days and per month for 12 months, and plans.
create function public.admin_overview(p_tz text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with b as (
    select (now() at time zone p_tz)::date as d,
           date_trunc('week', now() at time zone p_tz) as w,
           date_trunc('month', now() at time zone p_tz) as m,
           date_trunc('year', now() at time zone p_tz) as y
  ),
  u as (
    select (created_at at time zone p_tz) as at, coalesce(is_anonymous, false) as anon
      from auth.users
  ),
  p as (
    select plan, test_purchase, plan_ends_at
      from public.profiles
     where plan is not null and plan_ends_at > now()
  )
  select jsonb_build_object(
    'today', (select d from b),
    'total', (select count(*) from u),
    'anonymous', (select count(*) from u where anon),
    'google', (select count(*) from u where not anon),
    'newThisWeek', (select count(*) from u, b where u.at >= b.w),
    'newLastWeek', (select count(*) from u, b where u.at >= b.w - interval '7 days' and u.at < b.w),
    'newThisMonth', (select count(*) from u, b where u.at >= b.m),
    'newLastMonth', (select count(*) from u, b where u.at >= b.m - interval '1 month' and u.at < b.m),
    'newThisYear', (select count(*) from u, b where u.at >= b.y),
    'newLastYear', (select count(*) from u, b where u.at >= b.y - interval '1 year' and u.at < b.y),
    'daily', (
      select jsonb_agg(jsonb_build_object(
               'day', g::date,
               'count', (select count(*) from u where u.at::date = g::date)) order by g)
        from b, generate_series(b.d - 29, b.d, interval '1 day') g
    ),
    'monthly', (
      select jsonb_agg(jsonb_build_object(
               'month', to_char(g, 'YYYY-MM'),
               'count', (select count(*) from u where date_trunc('month', u.at) = g)) order by g)
        from b, generate_series(b.m - interval '11 months', b.m, interval '1 month') g
    ),
    'plans', jsonb_build_object(
      'free', (select count(*) from u) - (select count(*) from p),
      'monthly', (select count(*) from p where plan = 'monthly'),
      'semester', (select count(*) from p where plan = 'semester'),
      'yearly', (select count(*) from p where plan = 'yearly'),
      'test', (select count(*) from p where test_purchase),
      'endingIn7Days', (select count(*) from p where plan_ends_at < now() + interval '7 days')
    )
  );
$$;

-- One page of users, newest first, searched by email, name or id.
create function public.admin_users(p_query text, p_limit integer, p_offset integer)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with q as (select lower(trim(coalesce(p_query, ''))) as s),
  rows as (
    select u.id, u.email, coalesce(u.is_anonymous, false) as anonymous, u.created_at,
           pr.display_name, pr.plan, pr.plan_ends_at, pr.test_purchase
      from auth.users u
      left join public.profiles pr on pr.id = u.id, q
     where q.s = ''
        or strpos(lower(coalesce(u.email, '')), q.s) > 0
        or strpos(lower(coalesce(pr.display_name, '')), q.s) > 0
        or strpos(u.id::text, q.s) > 0
  )
  select jsonb_build_object(
    'total', (select count(*) from rows),
    'rows', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', r.id,
               'email', r.email,
               'name', r.display_name,
               'anonymous', r.anonymous,
               'createdAt', r.created_at,
               'plan', case when r.plan_ends_at > now() then r.plan end,
               'planEndsAt', case when r.plan_ends_at > now() then r.plan_ends_at end,
               'test', coalesce(r.plan_ends_at > now() and r.test_purchase, false)
             ) order by r.created_at desc, r.id)
        from (select * from rows
               order by created_at desc, id
               limit least(greatest(p_limit, 1), 100)
              offset greatest(p_offset, 0)) r
    ), '[]'::jsonb)
  );
$$;

-- This month's payments (calendar month in p_tz) and the latest ones.
create function public.admin_payments(p_tz text, p_limit integer)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with m as (select date_trunc('month', now() at time zone p_tz) as start)
  select jsonb_build_object(
    'monthTotalPhp', (
      select coalesce(sum(amount_php), 0) from public.payments, m
       where status = 'paid' and (created_at at time zone p_tz) >= m.start
    ),
    'monthCount', (
      select count(*) from public.payments, m
       where status = 'paid' and (created_at at time zone p_tz) >= m.start
    ),
    'anyDemo', exists (select 1 from public.payments where demo),
    'recent', coalesce((
      select jsonb_agg(jsonb_build_object(
               'email', x.email,
               'plan', x.plan,
               'amountPhp', x.amount_php,
               'status', x.status,
               'demo', x.demo,
               'createdAt', x.created_at
             ) order by x.created_at desc)
        from (select pay.*, u.email
                from public.payments pay
                left join auth.users u on u.id = pay.user_id
               order by pay.created_at desc
               limit least(greatest(p_limit, 1), 50)) x
    ), '[]'::jsonb)
  );
$$;

-- Crash reports of the last p_days days, grouped by message, version and
-- platform, most recent first.
create function public.admin_crashes(p_days integer)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with c as (
    select * from public.crash_reports
     where created_at > now() - make_interval(days => least(greatest(p_days, 1), 90))
  )
  select jsonb_build_object(
    'total', (select count(*) from c),
    'users', (select count(distinct user_id) from c),
    'groups', coalesce((
      select jsonb_agg(g order by g ->> 'lastAt' desc)
        from (
          select jsonb_build_object(
                   'message', message,
                   'version', version,
                   'platform', platform,
                   'count', count(*),
                   'users', count(distinct user_id),
                   'lastAt', max(created_at),
                   'stack', (array_agg(stack order by created_at desc))[1]
                 ) as g
            from c
           group by message, version, platform
           order by max(created_at) desc
           limit 30
        ) s
    ), '[]'::jsonb)
  );
$$;

-- Deletes crash reports older than 90 days; the server calls it now and
-- then (no pg_cron needed).
create function public.prune_crash_reports()
returns integer
language sql
security definer
set search_path = ''
as $$
  with d as (
    delete from public.crash_reports where created_at < now() - interval '90 days' returning 1
  )
  select count(*)::integer from d;
$$;

-- Only the study server (service_role) may call these.
revoke execute on function public.admin_overview(text) from public, anon, authenticated;
revoke execute on function public.admin_users(text, integer, integer) from public, anon, authenticated;
revoke execute on function public.admin_payments(text, integer) from public, anon, authenticated;
revoke execute on function public.admin_crashes(integer) from public, anon, authenticated;
revoke execute on function public.prune_crash_reports() from public, anon, authenticated;
grant execute on function public.admin_overview(text) to service_role;
grant execute on function public.admin_users(text, integer, integer) to service_role;
grant execute on function public.admin_payments(text, integer) to service_role;
grant execute on function public.admin_crashes(integer) to service_role;
grant execute on function public.prune_crash_reports() to service_role;

-- The server inserts crash reports and demo payments with the secret key.
grant insert on public.crash_reports to service_role;

commit;
