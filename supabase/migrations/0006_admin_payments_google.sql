-- tAsikaso: the admin page's Payments card counts Google accounts only.
--
-- Paying for tAsikaso+ belongs to a Google account (it follows the student
-- to a new phone). So this month's total, the payment count and the recent
-- list now leave out payments of students without an account (anonymous)
-- and of deleted accounts (no account left to say which kind it was).
-- Two new keys give the card's percentage the right base:
--   payers       Google accounts that paid this month (each counted once)
--   googleUsers  all Google accounts
-- Same arguments as 0003's admin_payments; the old keys stay.
--
-- Run once after 0005_admin_user_names.sql: SQL Editor -> New query ->
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
  )
  select jsonb_build_object(
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
