# Run-through on the web build — 20 Oct 2026

How: the app was run with `flutter run -d web-server` (debug) and driven in
Chrome through Playwright, screen by screen, with screenshots and the
accessibility tree checked at every step. The dev-server log showed **no
exceptions** during the whole run. An Android emulator was not possible on
this PC (virtualization is off in the BIOS and enabling it needs admin), so
camera, Smart Scanner, text recognition, notifications and vibration still
need a real phone (see `phone-test-checklist.md`).

## Verified working

**Pomodoro & Focus Mode** — START opens Focus Mode with the circle reveal
and bubbles; pause holds the time; ✕ pauses and RESUME continues from the same
second; Skip to Break asks first with the minutes left; mode switch works; a
1-minute Pomodoro finished on time → "Pomodoro done! Time for a Short Break",
Focus Mode switched to the break ("Time for a breather, Kristine!"), the Study
strip showed "1 Pomodoro · 1m", the task went 4/8 → 5/8; the 1-minute break
finished → "Break over. Ready for the next Pomodoro?". New lengths from Settings
apply at once while the timer is at the start.

**Tasks** — add (becomes current, listed first, "Add Task" disabled until a
title is typed), edit, Mark as Done → Completed (1), Delete → "Undo" restores
it to the same position, Clear Completed asks first. The "this Pomodoro still
counts for X" notice appears when a new task becomes current mid-Pomodoro.

**Analysis** — Week / Month / Year all render; History bars, Productive Hours
(5 PM: 1m), Focus/Break 50/50 with the tip, Focus by Task, Heatmap with
"1 day streak · Best 1 day", Previous/Next week, Timeline with both the
Pomodoro and the break and their times.

**Dashboard** — greeting → name dialog; streak; Today's Focus ring (1 of
150 min, cards reviewed); This Week; Continue card; folder tiles reorder by
recent use; Recent Flashcards row with the "2 of 3 · 67%" ring, tap = study,
long-press = open set; search overlay; the "+" sheet (Scan Notes / New
Flashcard Set / New Folder / New Task).

**Library & folders** — new folder with colour; open; rename via ⋮ → Edit
Folder; New Flashcard Set from the folder menu; Delete Folder warns "Its 1 note
and 0 flashcard sets will also be deleted" and does so; search finds folders,
notes and sets.

**Flashcards** — set created, three cards added via "Save & Add Another",
Study: Show Answer, Again (card returns later), Got It, summary "You knew 2 of
3 cards on the first try", score ring on the Dashboard.

**Notes (gallery path)** — import two photos → review screen with four-corner
crop, Rotate, thumbnails, Add More, Delete → Save Notes As (PDF / Flashcards,
title, folder, New) → "Saved to Organic Chemistry · Open" → viewer shows the
pages with print/share; ⋮ Rename / Move to Folder / Delete all work.

**Settings & Profile** — name, daily goal, presets, typed lengths, Reset to
Default + Undo (restored 30–5–15), Appearance Dark switches every screen,
locked colours open the plans page, "Turn On Plus for Testing" unlocks them
(Teal applied everywhere), Help & FAQ (7 questions), Delete All Data clears
everything and keeps theme + Plus as designed; the web-only notes under
Notifications / Scanning / Your Data are honest.

## Bugs confirmed by running

**Status (later the same day):** 1, 2, 3, 6, 7 and 8 below are fixed in the
"Phase 1" commit, together with the data-safety bugs from the code audit
(Delete All Data and PDFs while saving is paused, the task editor, scan and
gallery-import errors, file-delete errors) and the name-clearing and
accessibility-label gaps. 4 and 5 wait for Phase 3 (billing, web storage).

| # | Bug | Seen |
|---|---|---|
| 1 | **Typing a length overwrites the saved Custom rhythm.** | Typed 40 then 25 into Focus → the Custom card reads "Custom 2 – 5 – 15". |
| 2 | **The tAsikaso+ strip can't be dismissed and shows even with Plus on.** | No close control; still "Try tAsikaso+ free" after Turn On Plus. |
| 3 | **Start Focus during a paused break resumes the break.** | Dashboard → Start Focus opened Focus Mode on "Short Break 04:56". |
| 4 | **Trial button is a stub**; **Backup & Sync** just opens the plans page. | Snackbar only; plans page even with Plus on. |
| 5 | **Web keeps nothing across a reload.** | Documented in Settings; confirmed. |
| 6 | Plural: "1 sets" / "1 notes" in search results. | Library search for "chem". |
| 7 | "Notifications & Reminders" on Profile opens Settings at the top, not at the notifications section. | |
| 8 | Continue card estimate uses the *current* focus length: after setting Focus = 1 it read "101 / 8 min". | Cosmetic but confusing. |

Downgraded: "task editor overwrites progress if a Pomodoro finishes while it is
open" is almost unreachable from the UI, because the timer only runs inside
Focus Mode, where the editor isn't available. Still worth the one-line fix.

## Accessibility gaps noticed (screen readers)

- The floating "+" button has no label.
- Print and Share in the note viewer have no labels.
- The Rename Note dialog's field has no label; the New Flashcard Set field has
  only its placeholder.
- All ten folder colour swatches read "Folder color" with no selected state.
- Tooltip text is duplicated into labels ("Pause Pause", "Resume Resume Resume").

## Not testable here (needs a phone)

Smart Scanner (ML Kit), app camera, text recognition and suggested cards from
photos, timer-end notifications and their lateness on Android 14+, daily
reminder, vibration, keep-screen-on, restore after the app process is killed,
saving to the phone's storage.
