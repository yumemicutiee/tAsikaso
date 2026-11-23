-- tAsikaso: each user's own account data, so it comes back after Log Out
-- or on a new phone (lib/services/account_data.dart).
--
-- One row per user: their preferences, Pomodoro settings, tasks and
-- statistics as JSON (the app's AppStore.accountDataToJson), and their
-- profile photo (a small base64 JPEG). Study materials (notes, flashcards,
-- their pages) are NOT stored here; they stay on the phone and in the
-- student's own Google Drive.
--
-- Unlike plans and usage (0001), this is the user's own data: the app,
-- signed in as the user, reads and writes its own row directly. It can't
-- touch anyone else's row, can't delete rows, and each row has a size cap.
-- Deleting the account (auth.users) deletes the row.
--
-- Run once after 0001_accounts.sql: SQL Editor -> New query -> paste ->
-- Run. Running it twice fails at "create table" and changes nothing.

begin;

create table public.user_data (
  user_id uuid primary key references auth.users (id) on delete cascade,
  data jsonb not null default '{}'::jsonb,
  photo text,
  app_version text,
  updated_at timestamptz not null default now(),
  -- About a year of heavy daily use is ~150 kB; 2 MB leaves room, and
  -- stops a row from being used as free storage.
  constraint user_data_size check (pg_column_size(data) <= 2000000),
  constraint user_data_photo_size check (photo is null or length(photo) <= 700000),
  constraint user_data_is_object check (jsonb_typeof(data) = 'object')
);

comment on table public.user_data is
  'tAsikaso: each user''s preferences, Pomodoro settings, tasks and statistics, and photo; written by the app as that user.';

-- The server's clock decides updated_at, whatever the app sends.
create function public.touch_user_data()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger user_data_touch
  before insert or update on public.user_data
  for each row execute function public.touch_user_data();

revoke execute on function public.touch_user_data() from public, anon, authenticated;

alter table public.user_data enable row level security;

-- Signed-out visitors get nothing; signed-in users may read, add and
-- change (never delete) their own row.
revoke all on public.user_data from anon;
revoke delete, truncate, references, trigger on public.user_data from authenticated;
grant select, insert, update on public.user_data to authenticated;

create policy "Users read their own data"
  on public.user_data for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "Users add their own data"
  on public.user_data for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy "Users change their own data"
  on public.user_data for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

commit;
