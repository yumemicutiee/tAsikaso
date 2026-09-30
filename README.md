# tAsikaso

tAsikaso is a Flutter app for Android (and web) with a Pomodoro timer + task list, and
lecture-note capture → PDF or flashcards.

**What works**
- **Saved on the phone:** folders, notes (PDFs), flashcards, tasks, settings
  and stats are stored in the app's documents folder and survive restarts.
  (On web, data is kept only while the page is open for now.)
- **Smart Scanner (Android):** the camera button opens Google's document
  scanner (ML Kit), the same kind CamScanner uses. It finds the page edges, crops and
  straightens each page, offers filters, scans many pages, and can import from
  the gallery. You can still check each page before saving. If it's turned off in Settings, or the phone
  can't run it, or you're on the web, the app's own camera opens instead
  (Single / Multiple, flash, gallery, rotate, four-corner crop).
- **Text recognition (OCR):** when you save, the text on the pages is read
  on the phone (no internet). For PDFs it makes notes searchable and adds a
  **View Text** screen with Copy. For Flashcards it suggests cards from
  lines like `Term – definition`, `Term: definition`, `Q: … / A: …`, or a
  question followed by its answer. You pick **Add**, **Skip** or **Add All**.
- **Save Notes As:** choose PDF or Flashcards, a title and a folder, or tap
  **New** to create a folder right there.
- **Library & folders:** create folders with a colour, open a folder to see
  its notes and sets, edit or delete folders (long-press a folder too).
  Notes can be opened, shared, renamed, moved or deleted.
- **Search:** Dashboard and Library search folders, notes, set titles and
  card text.
- **Flashcards:** create sets (from the + button or from scanned photos),
  write cards while looking at your photos, then study: tap to flip, "Again"
  brings a card back later, "Got It" moves on; a summary at the end.
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
  goal; Pomodoro presets (Classic 25·5·15, Short 15·3·10, Deep Work
  50·10·30, or Custom, which remembers your own lengths), lengths you can type
  or step, auto-start and **Reset to Default** (with Undo); Focus Mode (keep screen on, vibrate);
  notifications (timer alerts that sound even when the app is closed, a daily
  study reminder at a time you pick); Smart Scanner; Delete All Data; Help &
  FAQ.
- **Dark mode:** Settings → Appearance: System (follows the phone), Light or
  Dark. It switches instantly, on every screen.
- **App colours (tAsikaso+):** Settings → App Color: Navy (free), Teal, Plum,
  Forest, Wine, Cocoa, Graphite, or **Custom** (slide to any hue; matching
  light and dark shades are made from it). Buttons, rings, charts, the tAsikaso+
  cards and Focus Mode follow it, in light and dark. Locked colours open the
  plans page. Payments aren't connected yet, so debug builds show "Turn On
  Plus for Testing" on the plans page.
- **Start Focus** on the Dashboard (and the play button on Continue) starts a
  Pomodoro and opens Focus Mode straight away.
- **Stats:** Today's Progress shows real focus minutes and cards reviewed;
  the streak counts days in a row with a finished Pomodoro or reviewed cards.

**Not yet:** payments for tAsikaso+ (Google Play Billing), and backup/sync. The plan limits
shown on the plans page aren't enforced yet.

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
`pubspec.yaml` let `flutter pub get` pick older ones on older Flutter. The first time
you tap the scan button, Android asks for camera permission; the permission is
added to the app automatically by the `camera` package.

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
| Review & crop | `lib/screens/capture/review_screen.dart` | Rotate, drag the 4 corners to crop, then save as **PDF** into a folder |
| Note viewer | `lib/screens/note_viewer_screen.dart` | View, share or print a saved PDF; rename, move, delete |
| Folder | `lib/screens/folder_screen.dart` | A folder's notes and flashcard sets |
| Flashcard set | `lib/screens/flashcards/set_screen.dart` | Photos, cards, add/edit cards, Study button |
| Study cards | `lib/screens/flashcards/study_cards_screen.dart` | Flip, Again / Got It, summary |
| Settings | `lib/screens/settings_screen.dart` | Name, goal, typed Pomodoro lengths, Focus Mode, notifications, scanning, data |

## Where things live

```
lib/
  main.dart, app.dart          app entry (loads saved data first) + theme
  theme/                       colours, text styles, icons, brand name (brand.dart)
  models/                      folders, notes, tasks, flashcards, settings (JSON)
  data/app_store.dart          all app data + saving; screens listen to it
  data/pomodoro_controller.dart  the one timer, shared by Study and Focus Mode
  services/scan_service*.dart  ML Kit scanner + OCR (phones), stub on web
  utils/card_suggestions.dart  finds flashcards in recognised text
  data/storage/                files on the phone, memory on web/tests
  widgets/                     header, bottom bar, folder card, list rows, dialogs
  screens/                     Dashboard, Library, Folder, Study, Profile,
                               Settings, capture/, flashcards/, actions.dart
assets/fonts/                  Plus Jakarta Sans (headings, numbers), Inter (text), Phosphor icons
```

## Next (functionality)

- Google Play Billing for Plus (e.g. `in_app_purchase`), then enforce limits
- Saving on web (IndexedDB), backup & sync
- Spaced repetition (show hard cards more often across days)

Fonts: Plus Jakarta Sans (Tokotype) and Inter (Rasmus Andersson), SIL Open Font License 1.1.
Icons: Phosphor Icons, MIT License (assets/fonts/PHOSPHOR_LICENSE.txt).
