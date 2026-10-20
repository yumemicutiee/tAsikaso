# Phone test checklist

Run through this once on a real Android phone before fixing anything, so we
know where we're starting from. Install `tAsikaso-release.apk` (or the debug
one, which has "Turn On Plus for Testing" on the plans page).

Write down: phone model ________  Android version ________  APK: debug / release

Mark each line ✅ works · ⚠️ partly · ❌ broken, and note what you saw.

## First launch
- [ ] App opens; five sample folders and five sample tasks are there.
- [ ] Greeting asks for your name; the name shows in "Hello, …!".

## Pomodoro & Focus Mode
- [ ] START asks "Allow notifications?" the first time.
- [ ] Focus Mode opens with the circle animation; timer counts down; bubbles move.
- [ ] ✕ or back pauses; RESUME carries on from the same second.
- [ ] Put the app in the background for 2 minutes, come back: the countdown is still right.
- [ ] Close the app completely (swipe away) while running, reopen: the timer carries on.
- [ ] Set Focus to 1 minute in Settings, start, lock the phone: a notification with sound arrives when it ends.
      Note how late it is: ________ seconds. (Android 14+ phones are expected to be late — known bug.)
- [ ] Vibrate When Time Is Up: can you feel anything when the timer ends? (Expected: barely — known bug.)
- [ ] Skip during a Pomodoro asks first; skip during a break goes to the next Pomodoro.
- [ ] Long break after 4 Pomodoros (set Focus/breaks to 1 min to test quickly).
- [ ] Auto-start breaks / Pomodoros works when switched on.
- [ ] Keep Screen On: the screen doesn't dim in Focus Mode.

## Tasks
- [ ] Add a task from + on the Study tab; it becomes the current task and is listed first.
- [ ] Edit a task's title and estimate; delete it; Undo brings it back.
- [ ] Mark done, then Clear Completed.
- [ ] After a Pomodoro finishes, the task's count goes up (e.g. 1 / 4).

## Scanning notes (needs a real phone)
- [ ] Camera button → Smart Scanner opens (Google's scanner UI). It finds page edges.
- [ ] Scan 3 pages; after closing the scanner, how long until the review screen shows? ________ s (no progress indicator — known bug).
- [ ] Save as PDF into a folder → the note opens; share and print work.
- [ ] Open the note → "View Text" shows the recognised text; Copy works.
- [ ] Settings → turn Smart Scanner OFF → camera button opens the app's own camera.
      Single / Multiple, flash, gallery import, rotate, four-corner crop.
- [ ] Import 3 photos from the gallery at once.
- [ ] Save as Flashcards → suggested cards appear; Add / Skip / Add All.

## Library, folders, search
- [ ] New folder with a colour; open it; edit it (long-press); delete it from its ⋮ menu (deletes its notes too, with a warning).
- [ ] Rename, move and delete a note.
- [ ] Search finds a folder, a note title, text inside a scanned note, and a card.

## Flashcards
- [ ] Study a set: tap to flip, Again brings the card back, Got It moves on, summary at the end.
- [ ] Dashboard "Recent Flashcards": tap studies, long-press opens; score ring shows last result.

## Dashboard, Profile, Analysis
- [ ] Today's Focus ring, This Week bars, Continue card, Start Focus all respond.
- [ ] tAsikaso+ strip: is there any way to dismiss it? (Expected: no — known bug.)
- [ ] Profile: edit name, stats, streak.
- [ ] Analysis: Week / Month / Year, step back, all six sections draw without errors.

## Settings
- [ ] Presets Classic / Short / Deep Work; type a custom length; Reset to Default + Undo.
- [ ] Daily reminder at a time 2 minutes from now → notification arrives.
- [ ] Appearance System / Light / Dark switches instantly everywhere.
- [ ] App Color: locked colours open the plans page; with Plus on (debug) they apply.
- [ ] Delete All Data → everything gone, sample data NOT re-added, reopen app → still empty.
- [ ] Help & FAQ opens.

## Anything that crashed, froze, or looked wrong
(write it here with the steps to repeat it)

