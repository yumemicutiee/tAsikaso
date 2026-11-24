-- tAsikaso: the admin page's Payments card shows what is paid for the plans
-- active right now.
--
-- A student who switches plans (Yearly, then Monthly, then Semester) has a
-- payment for each, but only the last plan is active; the others were
-- replaced. The card now adds up, for each Google account whose plan is
-- active (profiles.plan_ends_at in the future), the latest paid payment for
-- that plan: the one that started it. So it matches the tAsikaso+ plans
-- card ("Active right now"). New keys:
--   activeTotalPhp  what the active plans were paid
--   activePayers    Google accounts with an active, paid plan
-- 0006's keys stay (this month's payments, googleUsers, recent).
--
-- Run once after 0006_admin_payments_google.sql: SQL Editor -> New query ->
-- paste -> Run. Running it again changes nothing.

begin;

create or replace function public.admin_payments(p_tz text, p_limit integer)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with m as (select date_trunc('month', now() at time zone p_tz) as start),
  google as (
    select id, email from auth.users where not coalesce(is_anonymous, false)
  ),
  paid as (
    select pay.* from public.payments pay
      join google g on g.id = pay.user_id, m
     where pay.status = 'paid' and (pay.created_at at time zone p_tz) >= m.start
  ),
  -- Each active plan's own payment: the latest paid one for that plan.
  active as (
    select distinct on (pr.id) pr.id, pay.amount_php
      from public.profiles pr
      join google g on g.id = pr.id
      join public.payments pay
        on pay.user_id = pr.id and pay.plan = pr.plan and pay.status = 'paid'
     where pr.plan_ends_at > now()
     order by pr.id, pay.created_at desc
  )
  select jsonb_build_object(
    'activeTotalPhp', (select coalesce(sum(amount_php), 0) from active),
    'activePayers', (select count(*) from active),
    'monthTotalPhp', (select coalesce(sum(amount_php), 0) from paid),
    'monthCount', (select count(*) from paid),
    'payers', (select count(distinct user_id) from paid),
    'googleUsers', (select count(*) from google),
    'anyDemo', exists (select 1 from public.payments pay join google g on g.id = pay.user_id where pay.demo),
    'recent', coalesce((
      select jsonb_agg(jsonb_build_object(
               'email', x.email,
               'plan', x.plan,
               'amountPhp', x.amount_php,
               'status', x.status,
               'demo', x.demo,
               'createdAt', x.created_at
             ) order by x.created_at desc)
        from (select pay.*, g.email
                from public.payments pay
                join google g on g.id = pay.user_id
               order by pay.created_at desc
               limit least(greatest(p_limit, 1), 50)) x
    ), '[]'::jsonb)
  );
$$;

-- Replacing a function keeps its grants; set them again to be sure.
revoke execute on function public.admin_payments(text, integer) from public, anon, authenticated;
grant execute on function public.admin_payments(text, integer) to service_role;

commit;
