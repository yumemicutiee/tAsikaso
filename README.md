# tAsikaso

tAsikaso is a Flutter app for Android (and web) with a Pomodoro timer + task list, and
lecture-note capture → PDF or flashcards.

**What works**
- **Saved on the phone:** folders, notes (PDFs), flashcards, tasks, settings
  and stats are stored in the app's documents folder and survive restarts.
  On the web they are saved in the browser (IndexedDB).
- **Profile photo and name from Google:** signing in fills in the name (if
  none is set) and takes the account photo (kept at 256 px, following a
  changed Google photo until the user picks their own). Tap the photo on
  Profile to choose one from the gallery or camera, go back to the Google
  photo, or remove it; tap the name to change it. The photo is backed up
  and synced with everything else.
- **Google Drive sync:** Profile → Backup & Sync → **Sign in with Google**.
  Everything (folders, notes, flashcards, tasks, statistics, settings) is
  kept in a private folder of the user's own Google Drive that only this
  app can see, uploaded a little after each change and when the app goes to
  the background; only new files are sent. On a new phone, signing in
  offers to restore it all. Sign Out and Delete All Data leave the copy on
  Drive alone. Needs the app's Google OAuth client (see "Google Drive sync"
  under Run it).
- **Backup file:** the same screen also makes one `.zip` with everything in
  it and opens the share sheet (downloads on the web), and Restore from
  Backup picks such a file and replaces everything on the device.
- **Smart review (spaced repetition):** each card comes back after a growing
  gap when you know it (1, 3, 7, 14, 30… days) and tomorrow when you miss it.
  A set shows how many cards are due and offers to review just those, or all.
- **Smart Scanner (Android):** the camera button opens Google's document
  scanner (ML Kit), the same kind CamScanner uses. It finds the page edges, crops and
  straightens each page, offers filters, scans many pages, and can import from
  the gallery. You can still check each page before saving. If it's turned off in Settings, or the phone
  can't run it, or you're on the web, the app's own camera opens instead
  (Single / Multiple, flash, gallery, rotate, four-corner crop). The app's
  camera and gallery import **find the page edges too** (`lib/utils/page_detector.dart`,
  pure Dart): the crop corners start on the page, and you drag them if they're off.
- **Text recognition (OCR):** when you save, the text on the pages is read
  on the phone (no internet). It goes into the Scan PDF as a hidden text
  layer, so the text can be selected, searched and copied in any PDF viewer;
  it makes notes searchable in the app and adds a **View Text** screen with
  Copy and **Make Flashcards**. Without the study server, flashcards are
  suggested from lines like `Term – definition`, `Term: definition`,
  `Q: … / A: …`, or a question followed by its answer, and you pick **Add**,
  **Skip** or **Add All**.
- **Smart Study (Claude):** with the study server set up (see
  `server/README.md`; Settings → Smart Study holds its address and token),
  saving a scan sends the recognised text there and Claude Opus 5.5 sends
  back the notes **typed up cleanly**, a summary, the **key concepts**, a set
  of **flashcards** and a **quiz**. Key concepts show on the note's text
  screen and on the set; "Make Cards with AI" and "New Quiz" work on
  existing sets, and any note's text can become a set. Needs internet; when
  the server can't be reached the app falls back to the offline behaviour
  and says so. The photos themselves never leave the phone.
- **Save Notes As:** choose **Scan PDF** (the pages as photos, text
  selectable), **Text PDF** (the notes typed up, with the key concepts at
  the end; needs text recognition) or **Flashcards**, a title and a folder,
  or tap **New** to create a folder right there.
- **Library & folders:** create folders with a colour, open a folder to see
  its notes and sets, edit or delete folders (long-press a folder too).
  Notes can be opened, shared, renamed, moved or deleted.
- **Search:** Dashboard and Library search folders, notes, set titles and
  card text.
- **Flashcards:** create sets (from the + button or from scanned photos),
  write cards while looking at your photos, then study: tap to flip, "Again"
  brings a card back later, "Got It" moves on; a summary at the end.
- **Quizzes:** any set with two or more cards has **Take a Quiz**: multiple
  choice, true or false, fill in the blank and typed answers, one at a
  time, with the right answer and an explanation after each and the score
  at the end. Questions come from the study server when it's on, otherwise
  they're made from the cards themselves. Typed answers are judged on the
  phone (spelling slips and word order forgiven) or, with the server, by
  meaning. Right answers count like "Got It" and wrong ones like "Again"
  for smart review.
- **Pomodoro:** START opens **Focus Mode**: a circle grows out of the
  button into a full-screen view with the task, "Focus on the process, *name*!",
  a big timer and a tick-mark dial. The controls are pause, reset and skip.
  Closing Focus Mode (✕ or the back gesture) pauses the timer; RESUME carries on.
  Soft bubbles drift up behind the timer (Settings → Focus Mode → Moving
  Bubbles; they hold still if the phone is set to reduce motion). It also has
  automatic breaks and a long break every N Pomodoros. Each finished Pomodoro is added to the current
  task and to today's focus minutes. The countdown stays correct after the
  app has been in the background.
- **Tasks:** add, edit (type or step the estimated Pomodoros), pick the current
  task (tap it, or "Work on This"). The current task is always listed first.
  Mark done, delete with **Undo**, and **Clear Completed**.
- **Pomodoro Analysis:**
  - **Overview:** pick Week, Month or Year and step back through earlier ones.
    - A navy summary shows focus time, the change from the same point last
      period, Pomodoros, daily average and best day (or month).
    - **History** bars have a daily-goal line.
    - **Productive Hours** has 24 hour cells.
    - **Focus / Break** is the split with a tip.
    - **Focus by Task.**
    - **Heatmap** covers the last months, with the darkest cells meaning the
      goal was met, plus the streak.
  - **Timeline:** every Pomodoro and break, newest first, grouped by day.
  - Breaks are now recorded: finished ones, and skipped ones for the time taken.
- **Dashboard:** the "Hello, *name*!" greeting, week strip, Today's Focus ring,
  This Week card and Continue card. **Recent Flashcards** are calm rows: tap to
  study, long-press to open, with a small ring for last time's score. It also
  has three folder tiles that fit the width and a dismissible **tAsikaso+**
  strip that leads to the plans page. Payments aren't connected yet.
- **Settings** (Profile, or the gear on Study): your name and daily focus
  goal; Pomodoro presets (Classic 25–5–15, Short 15–3–10, Deep Work
  50–10–30, or Custom, which remembers your own lengths), lengths you can type
  or step, auto-start and **Reset to Default** (with Undo); Focus Mode (keep screen on, vibrate);
  notifications (timer alerts that sound even when the app is closed, a daily
  study reminder at a time you pick, and on Android 14+ an **Allow Exact
  Timing** row while the phone would deliver alerts late); Smart Scanner;
  Smart Study (the AI switch, the study server's address — checked when you
  save it — and the app token); Delete All Data; Help & FAQ.
- **Dark mode:** Settings → Appearance: System (follows the phone), Light or
  Dark. It switches instantly, on every screen.
- **App colours (tAsikaso+):** Settings → App Color: Navy (free), Teal, Plum,
  Forest, Wine, Cocoa, Graphite, or **Custom** (slide to any hue; matching
  light and dark shades are made from it). Buttons, rings, charts, the tAsikaso+
  cards and Focus Mode follow it, in light and dark. Locked colours open the
  plans page.
- **Start Focus** on the Dashboard (and the play button on Continue) starts a
  Pomodoro and opens Focus Mode straight away.
- **Stats:** Today's Progress shows real focus minutes and cards reviewed;
  the streak counts days in a row with a finished Pomodoro or reviewed cards.

**tAsikaso+ plans (Philippine pesos, for students):** ₱49 / month,
₱199 / semester (6 months) or ₱349 / year. Free keeps everything needed to
study (timer, tasks, scanning to PDF, your own cards, quizzes, search and
copy, this week's analysis, restoring a backup you have). Plus adds, and the
app enforces (`lib/data/plans.dart` lists them as `PlusFeature`):

| Perk | Free | tAsikaso+ |
|---|---|---|
| Pomodoro Analysis | this week only | every week, month and year, the heatmap, the full timeline |
| Suggested cards from notes (AI or from the text) | 20 a month (the study server isn't called once they're used up) | unlimited |
| Smart review | every card each round (answers are still recorded) | due-only reviews, due counts |
| App colours | Navy | all colours and Custom |
| Google Drive sync & backup files | sign in (name, photo) and restore only | sync and backup files |

Plans have a start and end date (Monthly 1, Semester 6, Yearly 12 months)
and end on their own, with a notice; nothing is deleted when a plan ends.
Delete All Data and restoring a backup keep the plan and this month's
suggested-card count.

**Test purchases (now):** payments aren't connected, so Profile → See Plans
starts any plan free ("Test mode, no payment is taken"), switches between
Monthly, Semester and Yearly, and **Go Back to Free Plan** ends it. This is
the build flag `TEST_PURCHASES` (`lib/data/plans.dart`), on by default; when
Google Play Billing is added, build with `--dart-define=TEST_PURCHASES=false`
and the plans page stops handing out plans.

**Not yet:** payments for tAsikaso+ (Google Play Billing), and plans tied to
a user account on a server: today the plan is kept on the device, so anyone
can start a test plan. Smart Study needs your own study server and Anthropic
API key; on the free plan it is capped by the 20 suggested cards a month,
but typing up notes (Text PDF) isn't limited.

A first launch starts with five sample folders and five sample tasks so the
app isn't empty. They can be edited or deleted.

## Design system

Navy + Sky, each colour with one job:

| Role | Colour | Used for |
|---|---|---|
| Navy | `#1E3A6E` (→ `#132647`) | Links, numbers, selected tab; Focus Mode, tAsikaso+ and Analysis summary backgrounds |
| Sky | `#9FCBF5` (tint `#E7F2FD`) | Buttons, rings, bars, the + and camera buttons; name and dial in Focus Mode |
| Butter | `#F7DC8C` | Camera and crop screens |
| Gold | `#FFD76A` (tint `#FDEBB8`) | The tAsikaso+ crown and "Plus" badges |
| Chart scale | `#EEF1F6` → `#CFE4FA` → `#9FCBF5` → `#5E8FCB` → `#1E3A6E` | Productive Hours and the Heatmap (none → a lot) |
| Flame | `#FF8A3D` → `#E5484D` | Streak only |
| Folders | user-chosen | Folder tiles and the flashcard score bars |

Pastel fills always carry dark ink (`#23263A`, `AppColors.onFill`) text and
icons, in both modes.

Background: white, with thin `#E6EAF1` borders on cards and a light grey `#F1F3F6` search bar.

**Dark mode** keeps Navy + Sky:

| Role | Light | Dark |
|---|---|---|
| Page / cards / sheets | `#FFFFFF` | `#0F1320` / `#181D2C` / `#1F2536` |
| Text / secondary / muted | `#23263A` / `#6B7085` / `#A0A5B8` | `#EEF0F7` / `#A3A9BD` / `#6B7288` |
| Borders, search bar | `#E6EAF1`, `#F1F3F6` | `#2A3143`, `#222838` |
| Accent text ("navy") | `#1E3A6E` | pale sky `#A9D2F7` |
| Sky tint | `#E7F2FD` | `#1C2A45` |
| Chart bars (picked / other) | `#1E3A6E` / `#9FCBF5` | `#A9D2F7` / `#3F6BA3` |
| Heat scale (none → a lot) | light to dark navy | `#232838` → … → `#A9D2F7` (brighter = more) |

Buttons stay sky with dark text; Focus Mode, the tAsikaso+ cards and the
camera screens look the same in both modes. In code, colours that change are
getters on `AppColors` (and every `AppText` style), so they can't go in
`const` widgets; `StudyApp` rebuilds every screen when the mode changes.

Type: **Plus Jakarta Sans** for screen titles, the greeting, big numbers,
the timer and buttons (ExtraBold for the biggest text); **Inter** for everything
else (task and note names, labels, body text).

## Run it

Requires Flutter **3.35 or newer** (`flutter --version`).

```bash
cd study_app
flutter create . --platforms=android,web   # generates the android/ and web/ folders (keeps lib/ as is)
dart run tool/setup_android.dart           # app name, notification permissions + Gradle setting (see below)
flutter pub get
flutter run                                # Android phone or emulator
flutter run -d chrome                      # web
flutter test                               # widget smoke tests
```

**Smart Study.** The AI features talk to the small Node.js server in
`server/`, which holds your Anthropic API key (never put the key in the
app). `server/README.md` has the setup and deployment steps. Point the app
at it in Settings → Smart Study, or bake the address and token in:

```bash
flutter build apk --dart-define=STUDY_AI_URL=https://your-site.com --dart-define=STUDY_AI_TOKEN=the-APP_TOKEN
```

**Google Drive sync.** Sign-in needs an OAuth client in *your* Google Cloud
project (free), once:

1. [console.cloud.google.com](https://console.cloud.google.com) → New
   project (e.g. "tAsikaso") → APIs & Services → **Enable** "Google Drive API".
2. **OAuth consent screen**: External, app name tAsikaso, your email; add the
   scope `.../auth/drive.appdata`; while the app is in *Testing*, add each
   tester's Gmail under Test users (up to 100).
3. **Credentials → Create credentials → OAuth client ID**:
   - **Android**: package name `com.tasikaso.study_app`, SHA‑1 of the signing
     key (`keytool -list -v -keystore android/upload-keystore.jks -alias upload`;
     the key made on 21 Oct 2026 is `34:1D:FC:8F:E5:57:29:C3:A1:AC:C9:9C:C5:B5:11:E2:5A:02:66:3C`).
     Nothing to paste into the app.
   - **Web application**: Authorized JavaScript origins
     `https://yumemicutiee.github.io` and `http://localhost:8080`. Its client
     id is built into the app (`DriveSync.clientId`, currently
     `308120396420-…hbqda.apps.googleusercontent.com`) and is also the
     "server client id" the Android sign-in library needs. Its client
     *secret* is never used or stored: the app only asks Google for access
     tokens. Another project's id can be used with
     `--dart-define=GOOGLE_CLIENT_ID=…` (GitHub: repo variable
     `GOOGLE_CLIENT_ID`).

   Both clients must be in the same Google Cloud project. Without the
   Android one, the Android app's sign-in fails with a configuration error.

Release builds must all carry the **same signing key**, or Google rejects
the sign-in: `android/key.properties` + `android/upload-keystore.jks` (kept
out of git) sign local builds; GitHub Actions signs with the secrets
`ANDROID_KEYSTORE_BASE64` (contents of `android/upload-keystore.base64.txt`)
and `ANDROID_KEYSTORE_PASSWORD` (from `key.properties`). Keep the keystore
and its password safe: without them the app can't be updated later.

**Android setup for notifications.** Timer alerts and the daily reminder use
`flutter_local_notifications`, which needs two things in the generated
`android/` folder: Java "desugaring" in `android/app/build.gradle.kts`, and
notification permissions plus two receivers in `AndroidManifest.xml`.
`tool/setup_android.dart` adds both; it's safe to run again. If Gradle
complains about `compileSdk`, set `compileSdk = 36` in
`android/app/build.gradle.kts`. The app asks "Allow notifications?" the first
time you press START.

On iOS, alerts only show while the app is open if `ios/Runner/AppDelegate.swift`
sets the notification delegate (see the flutter_local_notifications README,
"iOS setup"). While the app is closed they work without it.

The camera and Smart Scanner need a real phone. Smart Scanner uses Google Play
services, which downloads the scanner the first time it's used.
The newest ML Kit plugins need Flutter 3.44+. The version ranges in
`pubspec.yaml` let `flutter pub get` pick older ones on older Flutter. With Smart
Scanner on, Google's scanner handles the camera itself, so there is no permission
prompt; the app's own camera asks for camera permission the first time it opens
(the `camera` package declares the permission; `tool/setup_android.dart` drops
the microphone permission it also asks for, since nothing is recorded).

## Screens

| Screen | File | Notes |
|---|---|---|
| Dashboard | `lib/screens/dashboard_screen.dart` | Greeting, week strip, Today's Focus ring (daily goal), This Week bars, Continue, folders row, Plus strip, recent notes; search behind the search button |
| Library | `lib/screens/library_screen.dart` | Folder grid + all notes |
| Study | `lib/screens/study_screen.dart` | Mode switch, ring timer, Reset / START / Skip, today strip, task list (current task on top) |
| Focus Mode | `lib/screens/focus_screen.dart` | Full-screen timer, circular reveal from START |
| Pomodoro Analysis | `lib/screens/analysis_screen.dart` | Overview (Week / Month / Year) and Timeline |
| tAsikaso+ | `lib/screens/plans_screen.dart` | Free vs Plus, prices, trial button |
| Profile | `lib/screens/profile_screen.dart` | Name (tap to edit), stats, Plus card, Analysis and Settings |
| Scan flow | `lib/screens/capture/scan_flow.dart` | Smart Scanner first, the app's camera as fallback |
| Capture | `lib/screens/capture/capture_screen.dart` | App camera: Single / Multiple, flash, gallery import |
| Review & crop | `lib/screens/capture/review_screen.dart` | Rotate, drag the 4 corners (pre-set on the page edges when found), then save as **Scan PDF**, **Text PDF** or **Flashcards** |
| Note viewer | `lib/screens/note_viewer_screen.dart` | View, share or print a saved PDF; rename, move, delete; View Text (typed-up notes, summary, key concepts, Make Flashcards) |
| Folder | `lib/screens/folder_screen.dart` | A folder's notes and flashcard sets |
| Flashcard set | `lib/screens/flashcards/set_screen.dart` | Photos, key concepts, cards, add/edit cards, Study and Take a Quiz buttons |
| Study cards | `lib/screens/flashcards/study_cards_screen.dart` | Flip, Again / Got It, summary |
| Quiz | `lib/screens/flashcards/quiz_screen.dart` | One question at a time, four types, result after each, score and review at the end |
| Settings | `lib/screens/settings_screen.dart` | Name, goal, typed Pomodoro lengths, Focus Mode, notifications, scanning, Smart Study, data |

## Where things live

```
lib/
  main.dart, app.dart          app entry (loads saved data first) + theme
  theme/                       colours, text styles, icons, brand name (brand.dart)
  models/                      folders, notes, tasks, flashcards, settings (JSON)
  data/app_store.dart          all app data + saving; screens listen to it
  data/pomodoro_controller.dart  the one timer, shared by Study and Focus Mode
  services/scan_service*.dart  ML Kit scanner + OCR with line positions (phones), stub on web
  services/study_ai.dart       talks to the study server (server/) for Smart Study
  utils/card_suggestions.dart  finds flashcards in recognised text (offline)
  utils/page_detector.dart     finds the page edges in a photo (the app's own auto-crop)
  utils/quiz_builder.dart      makes quiz questions from a set's cards (offline)
  utils/answer_match.dart      judges a typed answer on the phone
  data/storage/                files on the phone, memory on web/tests
  widgets/                     header, bottom bar, folder card, list rows, dialogs
  screens/                     Dashboard, Library, Folder, Study, Profile,
                               Settings, capture/, flashcards/, actions.dart
  screens/capture/notes_pdf.dart  Scan PDF (hidden text layer) and Text PDF builders
assets/fonts/                  Plus Jakarta Sans (headings, numbers), Inter (text), Phosphor icons
server/                        the study server: Node.js + Claude (its own README)
```

## Next (functionality)

- Google Play Billing for Plus (e.g. `in_app_purchase`), then enforce limits
  and decide how Smart Study fits the plans
- Automatic sync (Google Drive app folder) on top of the backup file
- Run the phone checklist in `docs/phone-test-checklist.md` with the study
  server on: Smart Study and the auto-crop have only been checked in tests
  and on the web build so far

Fonts: Plus Jakarta Sans (Tokotype) and Inter (Rasmus Andersson), SIL Open Font License 1.1.
Icons: Phosphor Icons, MIT License (assets/fonts/PHOSPHOR_LICENSE.txt).
