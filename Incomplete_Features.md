# Incomplete features and QA findings

QA pass of the app (Flutter) and the study server (`server/`), 21 October 2026.
This is the list to continue from. Items are grouped by area; each says what
is missing or wrong, where it lives, why it matters, and what to do.

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
| 1.1 | **Payments (Google Play Billing) for tAsikaso+** | 🔴 | `plans_screen.dart` "Start Free Trial" only shows "coming soon"; debug builds have "Turn On Plus for Testing". No `in_app_purchase`, no receipt check, no restore. |
| 1.2 | **Plus limits are not enforced** | 🟠 | Month/Year analysis, "unlimited suggested cards", backup are all free today. Only app colours check `isPlus`. Decide the rules, then gate in `AppStore`/screens. |
| 1.3 | **Smart Study is not part of any plan** | 🟠 | Anyone with the server address + token gets Claude at the owner's cost. Needs a plan rule (Plus only / N scans a day) and, really, user accounts on the server (see 3.1). |
| 1.4 | **Automatic sync between devices (Google Drive)** | 🟠 built 21 Oct, not yet usable | `lib/services/drive_sync.dart`: sign in with Google, incremental upload to Drive's app folder, restore on a new phone, auto-sync after changes and on backgrounding. **Blocked on setup only:** the OAuth client in Google Cloud (Android: package + SHA‑1 of the upload key; Web: client id as the `GOOGLE_CLIENT_ID` repo variable) and the two signing secrets in GitHub. Until then "Sign in with Google" shows the "OAuth client is missing" message. Also untested on a device/with a real Google account; conflicts are last-upload-wins (no merge). |
| 1.5 | **iOS build** | 🔴 | No `ios/` project generated or tested. Google's document scanner is Android-only (the app's own camera + auto-crop would be used); OCR exists on iOS but is untested; `AppDelegate.swift` needs the notification delegate (README). |
| 1.6 | **Accounts / sign-in** | 🟡 | None. Everything is per device. Needed for billing, sync and server quotas. |
| 1.7 | **Other languages for the UI** | 🟡 | UI strings are English only; notes themselves can be Filipino/Taglish (Claude keeps the language). |

## 2. Smart Study (AI) — works, with gaps

| # | Gap | Status | Where / what to do |
|---|---|---|---|
| 2.1 | **Never run against the real Claude API** | 🔴 | `server/src/claude.ts` is written from the current SDK typings and type-checks, but no live call was possible here. First thing: `cd server`, put a real key in `.env`, `npm run try`. Check the JSON comes back, the quiz types are sensible, and how long Opus 5.5 at `high` takes on 2–3 pages. |
| 2.2 | **No way to add AI to a note saved offline** | 🟠 | A note saved while the server was unreachable has no typed-up text/concepts and nothing re-asks later. Sets have "Make Cards with AI"; add a "Type up with AI" action on `NoteTextScreen` (`actions.dart`) that calls `StudyAi.makeStudyKit(maxCards: 0, quizCount: 0)` and `updateNote`. |
| 2.3 | **No Cancel while waiting** | 🟠 | The progress dialog during save (`review_screen.dart` `_ProgressDialog`) and `runWithProgress` can't be cancelled; `StudyAi.timeout` is 3 minutes. Add a Cancel that abandons the request (and on the server, abort the Anthropic call when the client disconnects, see 3.6). |
| 2.4 | **On the web, Smart Study can't start from a scan** | 🟠 | There is no OCR on web, so scans have no text and the server is never called. Only "Make Cards with AI" on a set that already has `sourceText` works. Either accept (document) or add a web OCR (Tesseract.js) or let the server OCR the photos (it could send images to Claude directly — costlier). |
| 2.5 | **Quiz questions can't be viewed, edited or deleted** | 🟡 | `FlashcardSet.quiz` is only reachable through "Take a Quiz". A list with delete/edit, like the cards list in `set_screen.dart`, would help when Claude writes a bad question. |
| 2.6 | **No choice of quiz size or types** | 🟡 | Always 12 questions mixing all four types (`StudyAi.makeQuiz` / `buildLocalQuiz`). Add a small sheet before the quiz: count + which types. |
| 2.7 | **Summary and key concepts are not searchable** | 🟡 | `AppStore.searchNotes` matches `title`, `text` and folder; `searchSets` matches title and cards. Add `cleanText`, `summary`, `concepts` (terms). |
| 2.8 | **A "partly right" answer counts as wrong in the score** | 🟡 | `quiz_screen.dart` shows "Partly right" but `_correct` counts only `correct`. Decide: half a point, or count it, and say so on the result card. |
| 2.9 | **The app token lives in prefs and in backups** | 🟠 | `AppPrefs.aiToken` is saved in `data.json` and therefore inside every backup ZIP (`backup.dart`). Sharing a backup shares the token. Leave it out of backups (`_toJson` for backup) or keep it in a separate file. In web builds a `--dart-define` token is visible in the JS. |
| 2.10 | **Costs are per scan at Opus 5.5 `high`** | 🟡 | ≈ ₱9–26 per study kit (see `server/README.md`). `CLAUDE_EFFORT=medium` or Sonnet 5.5 roughly halve it. Decide before many students use it; see 1.3. |
| 2.11 | **Toast covers the quiz's Check button** | 🟡 | Seen on web: the "server key is missing… quiz was made from your cards" snackbar floats over the Check button for ~4 s. Show it before navigating, or give the quiz screen a bottom inset while a snackbar is up. |
| 2.12 | **Text sent to the server = text sent to Anthropic** | 🟡 | Privacy note for the user: OCR text leaves the phone (photos don't). Anthropic keeps API data 30 days by default. Worth a line in Help & FAQ and the Smart Study note. |

## 3. Backend (`server/`) — gaps

| # | Gap | Status | What to do |
|---|---|---|---|
| 3.1 | **One shared token, no users, no quotas** | 🟠 | `APP_TOKEN` is the same for every install and extractable from an APK. The in-memory limiter is per IP per process (resets on restart; several instances don't share it). For real use: per-user tokens (accounts), a store (Redis/DB) for limits, a daily spend cap. |
| 3.2 | **Hosts with short request limits will cut off study kits** | 🔴 | A study kit at `high` effort can take 30–120 s. Vercel/Netlify serverless functions (10–60 s) will time out; the README mentions Vercel. Use a long-running Node host (Render, Railway, a VPS) or add a job queue + polling endpoint. |
| 3.3 | **No live/integration test** | 🟠 | `test/` covers validation, auth, limits and normalisation only. Add a test behind an env flag that calls Claude once (`scripts/try.ts` is the manual version). |
| 3.4 | **Only console logging** | 🟡 | One line per request with token counts; no request ids, no persisted logs, no cost dashboard. Fine for a start; add a logger + request id when deploying. |
| 3.5 | **No prompt caching** | 🟡 | System prompts are short (below the cacheable minimum), so nothing is cached. If prompts grow (examples, rubrics), add `cache_control` on the system block. |
| 3.6 | **The Claude call keeps running after the client gives up** | 🟡 | If the app times out (3 min) or the user leaves, the server still finishes and pays. Pass an `AbortSignal` tied to `req.on('close')` into the SDK call. |
| 3.7 | **Very long notes fail rather than split** | 🟡 | Input is capped at 120k characters; output at 32k tokens (`TooLongError` → 413). Long notebooks should be chunked server-side. |
| 3.8 | **`/health` exposes model and effort** | 🟡 | Harmless, but remove if you don't want it public. |
| 3.9 | **No HTTPS of its own** | 🟡 | Expected: the host terminates TLS. Release Android builds need `https://` (cleartext is only allowed in debug builds, see 6.2). |

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
| 6.3 | Snackbar covers the quiz's Check button | 🟡 open | See 2.11. |
| 6.4 | Bottom bar items read "Dashboard Dashboard" to screen readers | 🟡 open | Tooltip + label duplicated (`widgets/bottom_nav.dart`); same for other tooltips noted in `docs/web-run-through-2026-10-20.md`. |
| 6.5 | `PdfFonts` cached a Future across zones | ✅ fixed | Would have hung the second PDF in tests; now caches the loaded fonts. |

Nothing crashed, no console errors on the web other than the expected 500s from the fake-key server, and all three fallbacks behaved (toast + cards from text / quiz from cards / phone-side answer check).

## 7. Untested on a real device — must do before a release

Run `docs/phone-test-checklist.md` on an Android phone with the study server running. Specifically unverified:

- Google's document scanner (ML Kit), the app camera, gallery import, **auto-crop on real photos**.
- OCR: text quality, line boxes → **selectable text in the Scan PDF** in a real viewer (Drive, Adobe).
- Timer-end notifications and their lateness on Android 14+, daily reminder, vibration, keep-screen-on, restore after the process is killed.
- Smart Study end to end: time per scan, card/quiz quality, error toasts when offline, the Settings ping.
- Backup to Google Drive via the share sheet, and restore.
- Memory/time with 10+ pages at 2000 px (page render + OCR + PDF build run one after another).

## 8. Documentation and UI text out of date

- **Help & FAQ** (`help_screen.dart`): no entry for Smart Study, quizzes, Text PDF, auto-crop, or where the text goes; "save them as a PDF or as flashcards" is now three choices; "flashcards get suggested cards" is only the offline case.
- **tAsikaso+ copy**: Profile card and Dashboard strip say "Suggested cards, full analysis history and backup" — suggested cards and backup are free now, Smart Study isn't mentioned. `plans_screen.dart` and README's price paragraph need the real plan rules (see 1.2).
- `docs/web-run-through-2026-10-20.md` predates Smart Study; this file is the newer status. (`server/README.md` now says the local `http://` tip is for debug builds and release needs `https://`.)

## 9. Tests and CI gaps

- **CI never fails on test or analyze errors**: `.github/workflows/build-apk.yml` runs them with `continue-on-error: true`. Make them required, and add a job for `server/` (`npm ci && npm test && npm run typecheck`).
- No widget tests for: `makeCardsForSet`, `makeFlashcardsFromNote`, the `NoteTextScreen` typed-up/as-read toggle, the Settings ping flow, Quiz "Try Again"/"New Quiz", the auto-crop hint on the review screen.
- No test for the save flow's "no text → Text PDF refused" path.
- Server: no test of `claude.ts` (see 3.3); `normalize.ts` and routes are covered.
- The browser run-through is `tool/web_qa.py` (Python + Playwright, uses the installed Chrome): serve `build/web` on :8080, run the study server on :8787, then `python tool/web_qa.py`. It isn't wired into CI.

## 9b. Google Drive sync — what's left (added 21 Oct, evening)

- Create the Google Cloud OAuth clients (README → "Google Drive sync") and add the GitHub secrets/variables; then test sign-in on a phone and on the Pages site.
- Sync is last-upload-wins per file: two phones editing at the same time overwrite each other's `data.json` (notes/photos are never lost, only the small data). A merge would need per-record timestamps.
- Large libraries upload each file once, but a restore downloads everything in one go with no progress bar.
- Web sessions: after the access token expires (~1 h) the next sync says "sign in again"; a silent refresh on the web isn't wired.
- iOS needs the reversed client id in `Info.plist` once an iOS build exists.
- `Delete All Data` forgets the Google account on purpose (so the Drive copy survives); the Settings dialog says so.

## 10. Suggested order of work

1. **Live Claude check** (`npm run try`), then deploy the server to a long-running host and point a **rebuilt** debug APK at it (6.1).
2. **Phone run-through** (section 7) — this is where the biggest unknowns are.
3. Plan rules for Smart Study and Plus (1.2, 1.3), then billing (1.1) and server accounts/quotas (3.1).
4. "Type up with AI" for notes, Cancel on long requests, quiz list/edit (2.2, 2.3, 2.5).
5. Docs/FAQ/Plus copy (section 8) and CI (section 9).
6. Sync (1.4) and iOS (1.5).
