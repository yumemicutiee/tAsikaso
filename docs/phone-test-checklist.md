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
      Note how late it is: ________ seconds.
- [ ] Android 14+: Settings → Notifications shows "Allow Exact Timing" with "Alerts may be late"; tapping it opens the
      phone's Alarms & reminders page; after allowing, the row disappears and the next alert is on time.
- [ ] Vibrate When Time Is Up ON: a real two-buzz vibration when the timer ends (app open), and the notification vibrates.
      OFF: no vibration from either.
- [ ] Refuse the notification permission on first START (fresh install): Timer Alerts switches itself off with a message.
- [ ] The alert's status-bar icon is a small clock glyph, not a white square.
- [ ] Reset during a running Pomodoro asks "Reset This Pomodoro?".
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
- [ ] Scan 3 pages; after closing the scanner a "Preparing your pages…" box shows until the review screen appears. How long? ________ s
- [ ] Save as **Scan PDF** into a folder → the note opens; share and print work. A wide (whiteboard) photo gets a
      landscape page.
- [ ] Share that PDF to Google Drive or a PDF viewer: the text on the pages can be **selected, searched and
      copied** (the hidden text layer). Does the selection sit over the right words? ________
- [ ] Android app info → Permissions: no Microphone permission is listed.
- [ ] Open the note → "View Text" shows the recognised text; Copy works; the flashcards button makes a set.
- [ ] Save as **Text PDF** (with Smart Study off): a document of the recognised text, one line per line.
- [ ] Settings → turn Smart Scanner OFF → camera button opens the app's own camera.
      Single / Multiple, flash, gallery import, rotate, four-corner crop.
- [ ] App camera: photograph a page on a darker desk → the crop corners start on the page's edges and
      "Page edges found" shows; Reset puts them back to the full frame. Try a page on a white desk: full frame.
      How often are the found corners right? ____ of ____ photos.
- [ ] Import 3 photos from the gallery at once (edges are looked for in each).
- [ ] Save as Flashcards (Smart Study off) → suggested cards appear; Add / Skip / Add All.

## Smart Study (needs the study server running, see server/README.md)
- [ ] Settings → Smart Study → Study Server: enter the address → "Connected to the study server."
      Enter the App Token too. Enter a wrong address → "no study server answered there".
- [ ] Scan 2–3 pages → Save as **Flashcards**: "Making your flashcards…" shows, then the set opens with cards,
      a summary and Key Concepts. How long did it take? ________ s. Are the cards good? ________
- [ ] Save as **Text PDF**: "Typing up your notes…", then a clean document with headings, bullets and
      Key Concepts at the end. View Text shows the typed-up notes with "Show the text as read".
- [ ] Save as **Scan PDF** with Smart Study on: the note still gets a summary and Key Concepts on View Text.
- [ ] Set screen → Take a Quiz: questions of all four types; a wrong multiple-choice shows the right one;
      a typed answer in other words is still marked right (by meaning); the score at the end;
      Try Again shuffles; New Quiz writes a new one.
- [ ] Set ⋮ menu → Make Cards with AI on a set written by hand with photos → new cards added, no duplicates.
- [ ] Switch the phone's internet off, save as Flashcards: a message says the server couldn't be reached and
      cards are suggested from the text instead. Take a Quiz still works (from the cards).
- [ ] Settings → Flashcards & Quizzes with AI OFF: saving never contacts the server.
- [ ] Watch the server's console: one line per request with the token counts; look at the usage page on
      platform.claude.com after a few scans and note the cost per scan: ________

## Library, folders, search
- [ ] New folder with a colour; open it; edit it (long-press); delete it from its ⋮ menu or from the long-press sheet's
      "Delete Folder" (deletes its notes too, with a warning).
- [ ] Rename, move and delete a note.
- [ ] Search finds a folder, a note title, text inside a scanned note, and a card.

## Flashcards
- [ ] Study a set: tap to flip, Again brings the card back, Got It moves on, summary at the end.
- [ ] Take a Quiz with Smart Study off (made from the cards): all four types appear with 5+ cards; the
      keyboard opens for typed answers; the score shows; the set's "last time" ring reflects it.
- [ ] Dashboard "Recent Flashcards": tap studies, long-press opens; score ring shows last result.
- [ ] Smart review: after a round, the set says "All caught up"; change the phone's date to tomorrow and
      it shows "N cards due" / "Review N Cards Due" plus "Study all".

## Backup & restore
- [ ] Profile → Backup & Sync → Back Up Now: the share sheet opens; choose Google Drive; the file lands in Drive
      and "Last backup" updates.
- [ ] Settings → Your Data → Delete All Data, then Backup & Restore → Restore from Backup → pick the file from
      Drive: everything comes back (folders, notes open, flashcards, tasks, analysis).
- [ ] Pick a file that isn't a backup: a clear message, nothing changed.

## Dashboard, Profile, Analysis
- [ ] Today's Focus ring, This Week bars, Continue card, Start Focus all respond.
- [ ] tAsikaso+ strip: the × hides it, and it stays hidden after reopening the app.
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

