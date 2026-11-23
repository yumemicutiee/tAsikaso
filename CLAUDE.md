# tAsikaso: notes for whoever works on this project next

tAsikaso is a study app (Flutter: Android + web) with a Pomodoro timer,
note scanning, flashcards and quizzes, and Smart Study with Claude. A Node
study server (`server/`, on Render) calls Claude; Supabase holds accounts,
plans, daily usage and each user's settings and Pomodoro statistics.

## Before you start

- **Admin page:** if asked for an admin page, dashboard or anything for the
  owner to see users, usage or costs, read **`ADMIN_PAGE_PLAN.txt`** first and
  follow it. It says what is recorded, where each piece of data lives, how the
  page connects, the server routes and SQL to write, the steps, and the
  owner's open decisions.
- **Keys:** Supabase and Render access is in **`KEYS.local.txt`** (owner's PC
  only, in `.gitignore`). Never commit it, print its tokens in chat, or copy
  them into code. The repository on GitHub is public.
- **Where things stand:** `PROGRESS.txt` (milestones, versions),
  `Incomplete_Features.md` (open items, roadmap in section 10),
  `server/README.md` (server settings and routes).

## How things fit

- App code: `lib/`. Accounts: `lib/services/accounts.dart` (Supabase Auth),
  `account_data.dart` (settings + statistics to the `user_data` table),
  `plan_sync.dart`, `study_ai.dart` (study server).
- Server: `server/src/app.ts` (routes), `accounts.ts` (token check,
  Supabase REST), `claude.ts`, `ledger.ts`.
- Database: `supabase/migrations/*.sql`, applied in order with the Supabase
  Management API (see KEYS.local.txt). Each is tested on PGlite in
  `server/test/migration*.test.ts` before it is run for real.

## Checks before pushing

- App: `flutter analyze` and `flutter test` (Flutter at `C:\src\flutter`).
- Server: in `server/`, `npm run typecheck` and `npm test` (Node at `C:\src\node`).
- GitHub runs the APK build, the Android emulator tests, a release-build
  text-recognition check and the web deploy on every push to `main`.
- Releases: `tool/publish_release.ps1 -Version X.Y.Z` after all checks pass.
