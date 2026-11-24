-- tAsikaso: names for students without an account on the admin page.
--
-- A student who taps "No account" gets an anonymous account on the first
-- run, before typing a name, so profiles.display_name stays empty and the
-- admin page could only show "No account" and an id. The name they type is
-- saved with their settings in user_data (data.prefs.name), so admin_users
-- now falls back to it (and search finds it). Same arguments and result
-- as 0004's admin_users; only 'name' is filled in more often.
--
-- Run once after 0004_admin_history_filters.sql: SQL Editor -> New query ->
-- paste -> Run. Running it again changes nothing.

begin;

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
           left(coalesce(nullif(trim(pr.display_name), ''),
                         nullif(trim(ud.data #>> '{prefs,name}'), '')), 200) as display_name,
           case when pr.plan_ends_at > now() then pr.plan end as plan,
           case when pr.plan_ends_at > now() then pr.plan_ends_at end as plan_ends_at,
           coalesce(pr.plan_ends_at > now() and pr.test_purchase, false) as test
      from auth.users u
      left join public.profiles pr on pr.id = u.id
      left join public.user_data ud on ud.user_id = u.id
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
revoke execute on function public.admin_users(text, integer, integer, text, text, integer, text) from public, anon, authenticated;
grant execute on function public.admin_users(text, integer, integer, text, text, integer, text) to service_role;

commit;
