-- tAsikaso: sign-ups per day for the whole history, so the admin page's
-- New users chart can be dragged back to earlier weeks, months and years.
--
-- Replaces admin_overview (same arguments, same result) and adds one key:
--   byDay  {"2026-11-23": 4, ...}: new users per day in p_tz, every day
--          that had any, since the first.
-- The page still works without it (only the latest 30 days and 12 months).
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

-- Replacing a function keeps its grants; set them again to be sure.
revoke execute on function public.admin_overview(text) from public, anon, authenticated;
grant execute on function public.admin_overview(text) to service_role;

commit;
