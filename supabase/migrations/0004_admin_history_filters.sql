-- tAsikaso: the admin page's chart history and user filters.
--
-- 1. admin_overview (same arguments, same result) gains one key:
--      byDay  {"2026-11-23": 4, ...}: new users per day in p_tz, every day
--             that had any, since the first; the New users chart can then
--             be dragged back to earlier weeks, months and years.
-- 2. admin_users gains filters, each with a default, so the study server's
--    three-argument call still works:
--      p_account  all | google | anonymous
--      p_plan     all | free | plus (any plan) | monthly | semester |
--                 yearly | ending (a plan ending in the next 7 days)
--      p_days     joined in the last n days (0 = any time)
--      p_sort     newest | oldest | ending (plan ending soonest first)
-- Without this file the page still works: the last 30 days and 12 months
-- on the chart, and search without filters.
--
-- Run once after 0003_admin.sql: SQL Editor -> New query -> paste -> Run.
-- Running it again changes nothing.

begin;

create or replace function public.admin_overview(p_tz text)
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
    -- Every day with sign-ups since the first one, {"2026-11-23": 4, ...}
    -- (days with none are left out), so the page can page back through
    -- earlier weeks, months and years.
    'byDay', coalesce((
      select jsonb_object_agg(day, n)
        from (select at::date as day, count(*) as n from u group by 1) c
    ), '{}'::jsonb),
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

-- One page of users, searched by email, name or id and filtered.
drop function if exists public.admin_users(text, integer, integer);
create or replace function public.admin_users(
  p_query text,
  p_limit integer,
  p_offset integer,
  p_account text default 'all',
  p_plan text default 'all',
  p_days integer default 0,
  p_sort text default 'newest'
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with q as (select lower(trim(coalesce(p_query, ''))) as s),
  base as (
    select u.id, u.email, coalesce(u.is_anonymous, false) as anonymous, u.created_at,
           pr.display_name,
           case when pr.plan_ends_at > now() then pr.plan end as plan,
           case when pr.plan_ends_at > now() then pr.plan_ends_at end as plan_ends_at,
           coalesce(pr.plan_ends_at > now() and pr.test_purchase, false) as test
      from auth.users u
      left join public.profiles pr on pr.id = u.id
  ),
  rows as (
    select b.* from base b, q
     where (q.s = ''
            or strpos(lower(coalesce(b.email, '')), q.s) > 0
            or strpos(lower(coalesce(b.display_name, '')), q.s) > 0
            or strpos(b.id::text, q.s) > 0)
       and case coalesce(p_account, 'all')
             when 'google' then not b.anonymous
             when 'anonymous' then b.anonymous
             else true end
       and case coalesce(p_plan, 'all')
             when 'free' then b.plan is null
             when 'plus' then b.plan is not null
             when 'ending' then b.plan_ends_at < now() + interval '7 days'
             when 'monthly' then b.plan = 'monthly'
             when 'semester' then b.plan = 'semester'
             when 'yearly' then b.plan = 'yearly'
             else true end
       and (coalesce(p_days, 0) <= 0 or b.created_at > now() - make_interval(days => least(p_days, 36500)))
  ),
  ranked as (
    select rows.*, row_number() over (order by
             case when p_sort = 'ending' then plan_ends_at end asc nulls last,
             case when p_sort = 'oldest' then created_at end asc,
             created_at desc, id) as n
      from rows
  ),
  page as (
    select * from ranked
     where n > greatest(p_offset, 0)
     order by n
     limit least(greatest(p_limit, 1), 100)
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
               'plan', r.plan,
               'planEndsAt', r.plan_ends_at,
               'test', r.test
             ) order by r.n)
        from page r
    ), '[]'::jsonb)
  );
$$;

-- Replacing a function keeps its grants; set them again to be sure.
revoke execute on function public.admin_overview(text) from public, anon, authenticated;
grant execute on function public.admin_overview(text) to service_role;
revoke execute on function public.admin_users(text, integer, integer, text, text, integer, text) from public, anon, authenticated;
grant execute on function public.admin_users(text, integer, integer, text, text, integer, text) to service_role;

commit;
