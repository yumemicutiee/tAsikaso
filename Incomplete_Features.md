# Incomplete features and QA findings

QA pass of the app (Flutter) and the study server (`server/`), 21 October 2026.
This is the list to continue from. Items are grouped by area; each says what
is missing or wrong, where it lives, why it matters, and what to do.

**Update — v0.4.0 sweep (21 Oct, late):** a frontend and a backend sweep
closed most of sections 2, 3, 6, 8 and 9 (marked ✅ below). Checked with
`flutter analyze` (clean), `flutter test` (165 pass), the server's
`npm run typecheck` / `npm test` (57 pass, 1 live test skipped without a
key) / `npm run build`, and a 14-step browser run where the web app talked
to the real study server, which talked to a fake Anthropic API (same
streaming protocol): quizzes with chosen types, a typed answer judged by
"Claude", partly-right scoring, the quiz list, and Cancel cutting the
connection. **What's left before and after adding the Opus 5.5 key is in
section 0.**

**Update — bug pass (25 Oct):** 23 bugs fixed in the app, plus a flaky
server test; what was fixed and what was found but left is in
**section 11**. `flutter analyze` clean, `flutter test` 190 pass, server
57 pass (1 live test skipped).

## 0. Next step: connecting Claude Opus 5.5 for real

The server is already written for Opus 5.5 (`claude-opus-5-5`, adaptive
thinking, effort `high`, structured JSON, refusal fallbacks); only a real key
and a host are missing. In order:

1. Get an API key at platform.claude.com, put it in `server/.env`, run
   `npm run try` and `LIVE_CLAUDE=1 npm test` (PowerShell:
   `$env:LIVE_CLAUDE=1; npm test`). Look at the cards and quiz it makes and
   how long it takes. (2.1)
2. Set a **monthly spend limit in the Claude Console** — the server's own
   daily cap (`DAILY_BUDGET_USD`, $5 default) restarts from zero whenever the
   server restarts or a free instance wakes up.
3. Deploy with `server/render.yaml` (README → Deploy), with a random
   `APP_TOKEN`. Check `https://<service>.onrender.com/health`.
4. Point the app at it: Settings → Smart Study, or set the GitHub variable
   `STUDY_AI_URL` and secret `STUDY_AI_TOKEN` so CI builds carry them.
5. From two phones on different networks, call `/v1/usage`; if both show the
   same `you.address`, set `TRUST_PROXY=2`.
6. Phone run-through of Smart Study (section 7), then tune `CLAUDE_EFFORT`
   and `DAILY_BUDGET_USD` from real costs (2.10).

**How this was checked**
- Code review of `lib/` and `server/src/` against the README's claims.
- `flutter analyze` clean; `flutter test` 107/107; `server`: `npm test` 13/13, `npm run typecheck`, `npm run build`.
- The study server run locally with a *fake* Anthropic key and probed over HTTP (health, CORS preflight, token check, validation, 404, key failure, rate limit).
- The release **web** build driven in headless Chrome (Playwright) through: Settings → Smart Study (address saved, "Connected" ping, token masked), a new set with three cards, a full quiz with the server failing (fallback to cards), reload (IndexedDB kept the data), gallery import → Save Notes As → Scan PDF.
- **Not checked:** anything on a real phone, and any *live* call to Claude (no API key on this PC). See section 7.

Status key: 🔴 blocks a feature · 🟠 feature works but is incomplete · 🟡 polish / later · ✅ fixed during this QA

---

## 1. Product features not built

| # | Feature | Status | Notes |
|---|---|---|---|
| 1.1 | **Payments (Google Play Billing) for tAsikaso+** | 🔴 | No `in_app_purchase`, no receipt check, no restore of purchases. Until then plans are **test purchases** (`kTestPurchases` in `lib/data/plans.dart`, on by default): Profile → See Plans starts Monthly / Semester / Yearly free, switches, or goes back to Free. When billing lands: start the plan from the purchase, build with `--dart-define=TEST_PURCHASES=false`, and re-check the plan with Google Play on start-up. |
| 1.2 | **Plus limits** | ✅ 21 Oct (v0.3.0) | Enforced: analysis beyond this week + heatmap + full timeline, 20 suggested cards a month (AI or text), smart review, app colours, Drive sync and backup files. Signing in and restoring stay free. Plans end on their own with a notice. Tested in `test/plans_test.dart` and a 19-step browser run-through. |
| 1.3 | **Smart Study and the plans** | 🟠 partly | Free accounts are capped by the 20 suggested cards a month (the server isn't called once they're used up). Not capped: typing up notes for a Text PDF, quizzes for existing cards, answer checks. Plans live on the device, so the server can't tell Free from Plus; real limits need user accounts on the server (see 3.1). |
| 1.4 | **Automatic sync between devices (Google Drive)** | ✅ working on a phone (21 Oct) | `lib/services/drive_sync.dart`: sign in with Google, incremental upload to Drive's app folder, restore on a new phone, auto-sync after changes and on backgrounding; name and photo taken from the account. Syncing is tAsikaso+ since v0.3.0. Still open: a second-device restore test, the two signing secrets in GitHub so CI builds carry the upload key, and conflicts are last-upload-wins (no merge). |
| 1.5 | **iOS build** | 🔴 | No `ios/` project generated or tested. Google's document scanner is Android-only (the app's own camera + auto-crop would be used); OCR exists on iOS but is untested; `AppDelegate.swift` needs the notification delegate (README). |
| 1.6 | **Accounts / sign-in** | 🟡 | None. Everything is per device. Needed for billing, sync and server quotas. |
| 1.7 | **Other languages for the UI** | 🟡 | UI strings are English only; notes themselves can be Filipino/Taglish (Claude keeps the language). |

## 2. Smart Study (AI) — works, with gaps

| # | Gap | Status | Where / what to do |
|---|---|---|---|
| 2.1 | **Never run against the real Claude API** | 🔴 | `server/src/claude.ts` is written from the current SDK typings and type-checks, but no live call was possible here. First thing: `cd server`, put a real key in `.env`, `npm run try`. Check the JSON comes back, the quiz types are sensible, and how long Opus 5.5 at `high` takes on 2–3 pages. |
| 2.2 | **Type up a note with AI** | ✅ v0.4.0 | "Type Up with AI" / "Type Up Again" on the note's text screen (`typeUpNote` in `actions.dart`); doesn't use suggested-card allowance. |
| 2.3 | **Cancel while waiting** | ✅ v0.4.0 | `CancelToken` in `study_ai.dart`; every AI wait has Cancel. Cancel drops the connection, and the server then aborts the Claude call (3.6) — seen end to end. In the save flow Cancel saves without AI. |
| 2.4 | **On the web, Smart Study can't start from a scan** | 🟠 | There is no OCR on web, so scans have no text and the server is never called. Only "Make Cards with AI" on a set that already has `sourceText` works. Either accept (document) or add a web OCR (Tesseract.js) or let the server OCR the photos (it could send images to Claude directly — costlier). |
| 2.5 | **Quiz questions list** | ✅ v0.4.0 (delete only) | "Quiz Questions (N)" on the set screen, with delete. Editing a question's text isn't built. |
| 2.6 | **Quiz size and types** | ✅ v0.4.0 | "New Quiz" opens a sheet (count + the four types); the server enforces the types. |
| 2.7 | **Search summary and key concepts** | ✅ v0.4.0 | Notes and sets match typed-up text, summary and concepts. |
| 2.8 | **Partly right** | ✅ v0.4.0 | Counts as half a point; the result says so. Smart review still treats it as not known. |
| 2.9 | **App token in backups** | ✅ v0.4.0 (web caveat stays) | Left out of backup ZIPs and the Drive copy; a restore keeps this device's server settings (a new phone takes the backup's address, not a token). A token built into a **web** build with `--dart-define` is still visible in its JavaScript — per-user tokens (3.1) are the real fix. |
| 2.10 | **Costs are per scan at Opus 5.5 `high`** | 🟡 | ≈ ₱9–26 per study kit (see `server/README.md`). `CLAUDE_EFFORT=medium` or Sonnet 5.5 roughly halve it. Decide before many students use it; see 1.3. |
| 2.11 | **Toast covers the quiz's Check button** | ✅ v0.4.0 | The quiz now shows such messages as a banner at the top; three similar toasts on the camera and review screens became on-screen text. |
| 2.12 | **Text sent to the server = text sent to Anthropic** | ✅ v0.4.0 (retention not mentioned) | Help & FAQ and the Smart Study note say only text leaves the phone (never photos) and goes to the study server and Anthropic. Anthropic's 30-day retention isn't mentioned; add it to a privacy policy before launch. |
| 2.13 | **Web: no OCR, so Smart Study can't start from a web scan** | 🟠 | Same as 2.4; still open. |

## 3. Backend (`server/`) — gaps

| # | Gap | Status | What to do |
|---|---|---|---|
| 3.1 | **Shared token; limits per IP, in memory** | 🟠 partly | ✅ v0.4.0: daily per-device quota (`DAILY_LIMIT` 60, `DAILY_CHECK_LIMIT` 300), server-wide daily spend cap (`DAILY_BUDGET_USD` $5, priced from real usage), constant-time token check, `/v1/usage`. Still open: one `APP_TOKEN` for every install; limits are per IP (school Wi-Fi shares one) and in memory (reset on restart/wake-up). Real fix: per-user tokens/accounts and a shared store (Redis/DB). Set a Console spend limit meanwhile. |
| 3.2 | **Host for long requests** | ✅ v0.4.0 | `server/render.yaml` Blueprint, `Dockerfile`, README Deploy steps; serverless hosts warned against. Graceful shutdown on SIGTERM. |
| 3.3 | **Live test** | ✅ v0.4.0 | `test/live.test.ts`, skipped unless `LIVE_CLAUDE=1` and a key are set. All other Claude-call tests run the real SDK against a local fake API. |
| 3.4 | **Logging** | ✅ v0.4.0 | One JSON line per request: id, route, status, model that answered, tokens, cost, fallback, duration. `X-Request-Id` header and `error.requestId`; the app shows a short "Ref" in error messages. |
| 3.5 | **No prompt caching** | 🟡 | Unchanged: prompts are below the cacheable minimum. Revisit if prompts grow. |
| 3.6 | **Abort when the app gives up** | ✅ v0.4.0 | The Claude stream is aborted when the client disconnects; logged as 499 with an estimated cost. |
| 3.7 | **Very long notes** | 🟡 partly | Output ceiling raised to 64k tokens; input stays 120k characters. Splitting whole notebooks is described in `server/README.md` as future work. |
| 3.8 | **`/health`** | ✅ v0.4.0 | `{ok:true}` only, unless `HEALTH_DETAILS=1`. |
| 3.9 | **No HTTPS of its own** | 🟡 | Expected: the host terminates TLS. Release Android builds need `https://`. |
| 3.10 | **Bugs fixed in the sweep** | ✅ v0.4.0 | A cut-off or refused answer came back as a 500 (the SDK parsed before the stop reason was checked); mid-answer fallback text was mixed into the JSON; multiple-choice answer index shifted when options were de-duplicated; quiz `cardIndex` pointed at the wrong card after cards were dropped; `maxCards: 0` was rejected; quiz types not enforced; unbounded quiz input; bad settings silently disabled limits; `TRUST_PROXY` could be spoofed; tag injection in student text; missing error mappings (overloaded, timeout, billing). All with tests. |

## 4. Scanning and PDFs — gaps

| # | Gap | Status | Where / what to do |
|---|---|---|---|
| 4.1 | **Auto-crop (app camera) is unproven on real photos** | 🟠 | `lib/utils/page_detector.dart` finds a *bright page on a darker background* (Otsu threshold + largest blob + hull corners). It gives up on white desks, low contrast (< 40 levels) and strong shadows, and does no line fitting, so corners can be a few pixels off. Test on 20 real photos; if it's weak, fit lines on the edge map (Hough) or use OpenCV (`opencv_dart`) on phones. |
| 4.2 | **Google's scanner, OCR and the text layer never ran on a phone** | 🔴 | Everything in `scan_service_mlkit.dart` (scanner, `readPages` with line boxes) is untested on a device. The Scan PDF's hidden text uses axis-aligned line boxes, so selection on slanted lines will sit slightly off. Check with `docs/phone-test-checklist.md`. |
| 4.3 | **OCR is Latin script only** | 🟡 | `TextRecognitionScript.latin`. Fine for English/Filipino; Chinese/Japanese/Korean notes won't be read. |
| 4.4 | **Text PDF thumbnail is the first photo** | 🟡 | `review_screen.dart` uses `CapturedPage.thumbnail(jpegs.first)`; a rendered first page of the document would look right in lists. |
| 4.5 | **Text PDF page count is counted with a regex** | 🟡 | `pdfPageCount` scans the PDF bytes for `/Type /Page`; works with this `pdf` package version. If the package starts compressing object dictionaries it will return 1. |
| 4.6 | **Scan PDF has no page numbers / title page** | 🟡 | By design so far; easy to add in `buildNotesPdf`. |
| 4.7 | **Web: Text PDF is unavailable** | 🟠 | Needs OCR (see 2.4). The sheet says so. |
| 4.8 | **Web camera on phones: frames can arrive sideways** | 🟠 fixed by a rule of thumb | Seen on the Pages site (21 Oct): a landscape 1920×1080 stream on a portrait page, content rotated. `capture_screen.dart` now turns the preview and each photo a quarter turn clockwise when the page is portrait and the stream landscape (and the reverse). Phones whose frames need the other direction get an upside-down photo and must use Rotate on the review screen; browsers don't report the sensor's orientation. |

## 5. Flashcards and quizzes — gaps

| # | Gap | Status | Notes |
|---|---|---|---|
| 5.1 | **Quiz results don't reach Analysis** | 🟡 | A quiz counts "cards reviewed" and updates the set's last score ring, nothing else. No history of quiz scores per set. |
| 5.2 | **The quiz score replaces the study ring** | 🟡 | `markSetStudied` is called by both Study and Quiz; the Dashboard ring shows whichever was last. Acceptable, but say "quiz" or "study" next to it. |
| 5.3 | **Offline quiz with few cards is thin** | 🟡 | With 2–3 cards: multiple choice has 2–3 options, true/false swaps between the same answers. Needs ≥ 5 cards for a good quiz; the button appears from 2. |
| 5.4 | **Suggested cards only appear offline** | 🟡 | With the server on, AI cards go straight into the set (no Add/Skip step). Some users may want to review first — a setting could switch this. |
| 5.5 | **`sourceText` grows the save file** | 🟡 | Every scanned set keeps its OCR text in `data.json` (and backups). Fine for hundreds of sets; for thousands move it to a file per set. |

## 6. Bugs found in this QA pass

| # | Bug | Status | Detail |
|---|---|---|---|
| 6.1 | **Release APK had no INTERNET permission** | ✅ fixed | Flutter's template grants it only in debug/profile manifests, so the release APK could not reach the study server at all. Added to `android/app/src/main/AndroidManifest.xml` and to `tool/setup_android.dart` (CI regenerates the project). **Rebuild the APK** — the one built before this fix is affected. |
| 6.2 | **Plain `http://` to a LAN server is blocked on Android 9+** | ✅ fixed (debug only) | The README's local-testing tip (`http://<PC IP>:8787`) needs cleartext traffic. Added `android:usesCleartextTraffic="true"` to the **debug** manifest only; release builds must use `https://`. |
| 6.3 | Snackbar covers the quiz's Check button | ✅ v0.4.0 | See 2.11. |
| 6.4 | Screen readers read some labels twice | ✅ v0.4.0 | Bottom bar, folder tiles, New Folder, colour swatches, recent sets and the save sheet's New button now read once. Section headers still merge the title with their action ("Quiz Questions (2) Show"). |
| 6.5 | `PdfFonts` cached a Future across zones | ✅ fixed | Would have hung the second PDF in tests; now caches the loaded fonts. |

Nothing crashed, no console errors on the web other than the expected 500s from the fake-key server, and all three fallbacks behaved (toast + cards from text / quiz from cards / phone-side answer check).

## 7. Untested on a real device — must do before a release

**Now checked on an emulator (25 Oct):** every push runs
`integration_test/phone_test.dart` on an Android 14 emulator on GitHub
(`.github/workflows/android-emulator.yml`; results, screenshots and logcat on
the `emulator-results` branch). Passing there: saving to the device and
reading it back after a restart; ML Kit text recognition (read a printed
test page exactly) and the hidden text layer in the Scan PDF; a timer alert
delivered by Android 5 s after it was scheduled (exact alarms allowed); the
daily reminder scheduled; Google's scanner failing → the app's own camera
opening with its notice → photo → Crop Page → saved as a Scan PDF.

Still for a real phone — run `docs/phone-test-checklist.md` with the study server running:

- Google's document scanner (ML Kit; not available on the emulator), gallery import, **auto-crop on real photos of paper** (on the emulator's test picture, which has no page, it still reported "Page edges found" with a lopsided shape — see 11.35).
- OCR on real handwriting and photos; **selectable text in the Scan PDF** in a real viewer (Drive, Adobe).
- Timer-alert lateness when exact alarms are *not* allowed (Android 14's default), vibration, keep-screen-on, restore after the process is killed.
- Smart Study end to end: time per scan, card/quiz quality, error toasts when offline, the Settings ping.
- Backup to Google Drive via the share sheet, and restore.
- Memory/time with 10+ pages at 2000 px (page render + OCR + PDF build run one after another).

## 8. Documentation and UI text

- ✅ v0.4.0: Help & FAQ covers the three save choices, auto-crop, Smart Study (and what leaves the phone), quizzes and tAsikaso+; Plus copy matches the enforced rules (v0.3.0).
- `docs/web-run-through-2026-10-20.md` predates Smart Study; this file is the newer status.

## 9. Tests and CI

- ✅ v0.4.0: the APK and web workflows stop when `flutter analyze` or `flutter test` fails (they used to ignore failures); `server-ci.yml` runs typecheck, tests and build on every change under `server/`.
- ✅ v0.4.0: tests for making cards (AI and offline), cards from a note, Type Up, the typed-up/as-read toggle, quiz Try Again / New Quiz with options, the Text PDF refusal, Cancel, quiz list delete, search, partly-right scoring, token out of backups (`test/study_tools_test.dart`); the server's Claude calls through the real SDK against a fake API.
- Still not covered: the Settings ping flow, the auto-crop hint on the review screen.
- Browser run-throughs (Python + Playwright, installed Chrome): `tool/web_qa.py` (helpers), `tool/plans_qa.py` (plans), `tool/sweep_qa.py` with `tool/fake_claude.mjs` and `tool/slow_server.mjs` (app → server → fake Claude, and Cancel). Not wired into CI.

## 9b. Google Drive sync — what's left (added 21 Oct, evening)

- Create the Google Cloud OAuth clients (README → "Google Drive sync") and add the GitHub secrets/variables; then test sign-in on a phone and on the Pages site.
- Sync is last-upload-wins per file: two phones editing at the same time overwrite each other's `data.json`. A sync also removes Drive files this phone doesn't have, so another phone's new PDFs and photos can go too (not only the small data). A merge would need per-record timestamps.
- Large libraries upload each file once, but a restore downloads everything in one go with no progress bar.
- Web sessions: after the access token expires (~1 h) the next sync says "sign in again"; a silent refresh on the web isn't wired.
- iOS needs the reversed client id in `Info.plist` once an iOS build exists.
- `Delete All Data` forgets the Google account on purpose (so the Drive copy survives); the Settings dialog says so.

## 10. Roadmap to 1.0 (updated 25 Oct)

**Done:** Phases 0–4 (20 Oct: bugs, alerts, web saving, smart review,
backup, polish) · Smart Study app + server (21 Oct) · Google Drive sync,
working on a phone (v0.2.x) · tAsikaso+ plans with every perk enforced, as
test purchases (v0.3.0) · sweep (v0.4.0) · bug pass, 23 fixes (v0.4.1) ·
Android emulator tests on every push.

Milestones, in order. **Who** says what each one needs from the owner.

| Milestone | What | Who | Status |
|---|---|---|---|
| **A. Robustness** | 11.35 auto-crop rejects non-page shapes · 11.27 Drive uploads over 5 MB (resumable) · 11.24 double-tap guards · 11.36 small screens · 11.30 Cancel on answer checks · 11.31 reminder after restore · more emulator tests (gallery import, Focus Mode + alert, backup ZIP round trip) | Claude alone | ⏳ next |
| **B. Smart Study live** | Section 0: API key → `npm run try` + live test → Console spend limit → deploy (Render) → app settings / `STUDY_AI_URL`. Then pick the model/effort from real costs (2.10). | Owner: API key, Render account. Claude: the rest | ⏸ waiting for the key |
| **C. Real-phone run-through** | `docs/phone-test-checklist.md` with the live server: Google's scanner, auto-crop on paper, handwriting OCR, alert lateness without exact alarms, vibration, share-sheet backup, 10+ page scans. Can be driven from the PC over Wireless debugging. | Owner: phone. Claude: drives the tests | after B |
| **D. Ready for strangers** | Google sign-in out of **Testing** (today only listed test users can sign in, and their sign-in lapses after 7 days); privacy policy (Anthropic's retention, Drive data); CI signing secrets (1.4); crash reports from phones; publish v0.4.1. | Owner: Google Cloud console, decisions. Claude: policy draft, code | — |
| **E. Paid plans for real** | Real payments (1.1) instead of test purchases; per-user accounts on the server (Google sign-in as the account) and shared limits (3.1, 1.3), so Free vs Plus is enforced by the server too. | Owner: decisions below. Claude: build | — |
| **F. Launch 1.0** | Distribution (Play Store listing, or APK + website with a download page), version 1.0, release notes. | Owner + Claude | — |
| Later | Web OCR (2.4) · sync merge (1.4) · iOS (1.5) · other UI languages (1.7) · quiz history in Analysis (5.1) | — | after 1.0 |

**Decisions the owner needs to make** (they shape D–F):
1. **Where students get the app:** Google Play, or the APK from GitHub/the website.
2. **How Plus is paid:** Google Play Billing (required on Play for digital perks), GCash/Maya through a payment provider (outside Play), or free for now.
3. **Smart Study for Free accounts:** keep 20 suggested cards a month, or Plus only (each kit costs ≈ ₱9–26 at Opus 5.5 `high`).
4. **Model and effort** after seeing real costs in B.

## 11. Bug pass (25 Oct)

Two reviewers, one on the data layer, services and server, one on the
screens. Every fix has a regression test that fails on the old code (except
11.5, which only fails in a time zone with daylight saving).

**Fixed — data and sync**

| # | What a user would have seen | Where |
|---|---|---|
| 11.1 | A restore that ran out of space had already deleted this phone's PDFs and photos, while saying "Nothing was changed". The backup's files now go in first. | `app_store.dart` `restoreFrom` |
| 11.2 | A save during a restore (e.g. a Pomodoro ending) could land on top of the restored data. Saving is paused for the restore. | same |
| 11.3 | "Your tAsikaso+ Plan Ended" after restoring an old backup, even with an active plan. | `app_store.dart` `_init(checkPlan:)` |
| 11.4 | Delete All Data during a running sync could delete the copy on Drive. The account is now forgotten first. | `eraseEverything` |
| 11.5 | Smart-review due dates a day off across a daylight-saving change. | `scheduleCard` |
| 11.6 | While saving was paused (unreadable save file), notes and photos made that session wouldn't open. | `_readFile` |
| 11.7 | Changes made during an upload were marked as synced and never reached Drive. | `drive_sync.dart` `_changes` |
| 11.8 | "Restored from Google Drive" when a restore was tapped during an upload, but nothing was restored. | `_runOne(wait:)` |
| 11.9 | A new phone's automatic sync could overwrite Drive's data before the user chose Restore or Keep Mine. | `_upload` |
| 11.10 | An upload that stopped halfway left Drive's data.json naming files that weren't uploaded. New files go first now. | `_upload` |
| 11.11 | Signing in while Drive couldn't be checked (weak connection) uploaded this phone's data over Drive's. Now it says what went wrong and uploads nothing. | `backup_screen.dart` `_signIn` |
| 11.12 | Short text sent to Smart Study showed the server's developer message; now refused in plain words. | `study_ai.dart` |
| 11.13 | Sets over 200 cards never got AI quizzes (server 400). 200 random cards are sent. | `makeQuiz` |
| 11.14 | An answer check the app couldn't read left the quiz's Check button spinning. | `checkAnswer` |

**Fixed — screens**

| # | What a user would have seen | Where |
|---|---|---|
| 11.15 | A progress spinner stuck on screen for good when another dialog (e.g. "Couldn't Save") had opened above it. Dialogs now close their own route. | `dialogs.dart` `closeDialog`, `review_screen.dart`, `scan_flow.dart` |
| 11.16 | No keyboard for the next typed quiz question. | `quiz_screen.dart` `_next` |
| 11.17 | A card asked about twice in one quiz moved two smart-review steps. | `quiz_screen.dart` `_check` |
| 11.18 | Deleting a card left its quiz questions counted and listed. | `set_screen.dart` |
| 11.19 | "Make Cards with AI" a second time wiped most of the set's quiz. | `actions.dart` `makeCardsForSet` |
| 11.20 | "Backup restored." lost (and an exception) after leaving the Backup screen. | `backup_screen.dart` `_restore` |
| 11.21 | Offline quiz with two right choices, or a "False" that was true ("Mitochondria" vs "The mitochondria."). | `quiz_builder.dart` |
| 11.22 | Productive Hours lost a minute for every Pomodoro across an hour. | `analysis_screen.dart` `_byHour` |
| 11.23 | Auto-crop never found a page in a 16-bit photo. | `page_detector.dart` |
| — | Server test: the two abort tests now wait for `message_start` instead of a fixed timer (one failed under load). | `server/test/claude.test.ts` |

**Found, not fixed**

| # | Problem | Status | Notes |
|---|---|---|---|
| 11.24 | Double-tap during a page transition: START can pause again, two camera screens, two offline sets. | 🟡 | Flutter lets taps through one frame after a push; needs guards in several places. |
| 11.25 | Drive status compares Drive's clock with the phone's (+5 s): a phone with a slow clock says "Google Drive has newer data" after its own sync. | 🟡 | Save Drive's own timestamp in the sync state. |
| 11.26 | `_uploadedJson` isn't saved, so the first sync after a restart uploads data.json again. | 🟡 | Harmless, one extra upload. |
| 11.27 | Drive uploads use multipart, which Google documents for files ≤ 5 MB. A big Scan PDF may make every sync fail. | 🟠 unverified | Check on a phone with a 10+ page scan; switch to resumable upload if it fails. |
| 11.28 | Requests that never reached Claude (overloaded, bad key, connection) still use up the student's daily allowance; an error mid-stream isn't added to the daily spend. | 🟡 | Policy call. |
| 11.29 | Text over 120,000 characters returns 400 with the validator's wording; the README documents `too_long` (413). | 🟡 | Pick one; a test asserts 400 today. |
| 11.30 | Answer checks wait the full 3 minutes with no Cancel. | 🟡 | |
| 11.31 | The daily reminder isn't rescheduled when a restore changes it (fixed at next start). | 🟡 | |
| 11.32 | Switching the camera to Single, or closing it, drops Multiple-mode pages without asking. | 🟡 | Design question. |
| 11.33 | The quiz ring counts partly right as 0; the quiz result counts it as half. | 🟡 | Needs a model field. |
| 11.34 | Dashboard and Study don't roll over at midnight until something changes; Dashboard says "No tasks yet" when all are done; profile photo errors are silent. | 🟡 | |
| 11.35 | Auto-crop accepts any bright shape: on a photo with no page (the emulator's test picture) it says "Page edges found" and draws a lopsided quadrilateral. | 🟠 | `page_detector.dart`: reject quads that are far from a rectangle (very unequal opposite sides, or a small share of their bounding box) and leave the full frame instead. |
| 11.36 | On a 320 dp-wide screen (small budget phones), the Study screen's "Today · 0 Pomodoros · … Analysis" strip is cut off and the + button covers content. | 🟡 | Seen in the emulator's first run; fine at 411 dp (Pixel 6). |
