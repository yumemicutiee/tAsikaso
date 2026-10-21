"""Drives the release web build (served on :8080) through the new Smart
Study, quiz and save-sheet flows with headless Chrome, and reports what it
saw. Screenshots land next to this script.

Flutter web puts text into aria-labels of merged semantics nodes and text
fields into <input>/<textarea> elements, so elements are found by label or
text and clicked by their screen position."""

import os
import sys
import time

from playwright.sync_api import sync_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
APP = "http://127.0.0.1:8080/"
SERVER = "http://127.0.0.1:8787"
console = []
findings = []

FIND_JS = """([text, exact]) => {
  const norm = s => (s || '').replace(/\\s+/g, ' ').trim();
  const want = norm(text);
  let best = null;
  const els = document.querySelectorAll('flt-semantics, flt-semantics input, flt-semantics textarea');
  for (const e of els) {
    const label = norm(e.getAttribute('aria-label') || e.getAttribute('placeholder'));
    const all = norm(e.textContent);
    const own = norm([...e.childNodes].filter(n => n.nodeType === 3).map(n => n.textContent).join(' '));
    const hit = exact ? (label === want || own === want || all === want)
                      : (label.includes(want) || all.includes(want));
    if (!hit) continue;
    const r = e.getBoundingClientRect();
    if (r.width < 1 || r.height < 1) continue;
    if (r.bottom < 0 || r.top > innerHeight || r.right < 0 || r.left > innerWidth) continue;
    // Page-sized containers hold every label on screen: never a target.
    if (r.width * r.height > innerWidth * innerHeight * 0.5) continue;
    const area = r.width * r.height;
    if (!best || area < best.area) best = {x: r.left + r.width / 2, y: r.top + r.height / 2, area};
  }
  return best;
}"""

LABELS_JS = """() => [...document.querySelectorAll('flt-semantics, flt-semantics input, flt-semantics textarea')]
    .map(e => (e.getAttribute('aria-label') || e.getAttribute('placeholder') || e.textContent).replace(/\\s+/g, ' ').trim())
    .filter(Boolean)"""


def note(text):
    print(f"  - {text}")
    findings.append(text)


def shot(page, name):
    page.screenshot(path=os.path.join(HERE, f"{name}.png"))


def labels(page):
    return page.evaluate(LABELS_JS)


def find(page, text, exact=True):
    return page.evaluate(FIND_JS, [text, exact])


def wait(page, text, timeout=15, exact=True):
    end = time.time() + timeout
    while time.time() < end:
        box = find(page, text, exact)
        if box:
            return box
        page.wait_for_timeout(250)
    raise TimeoutError(f"'{text}' not on screen after {timeout}s; screen shows: {labels(page)[-25:]}")


def click(page, text, exact=True, timeout=15):
    box = wait(page, text, timeout, exact)
    page.mouse.click(box["x"], box["y"])
    page.wait_for_timeout(500)


def visible(page, text, exact=True):
    return find(page, text, exact) is not None


def wait_gone(page, text, timeout=12, exact=False):
    """Waits for a toast to leave (it floats over the buttons at the bottom)."""
    end = time.time() + timeout
    while time.time() < end and visible(page, text, exact):
        page.wait_for_timeout(300)
    return not visible(page, text, exact)


def type_into(page, label, text):
    click(page, label, exact=False)
    page.keyboard.type(text, delay=15)
    page.wait_for_timeout(200)


def scroll_until(page, text, steps=12):
    for _ in range(steps):
        if visible(page, text, exact=False):
            return True
        page.mouse.move(200, 500)
        page.mouse.wheel(0, 500)
        page.wait_for_timeout(900)
    return visible(page, text, exact=False)


def step(title):
    print(f"\n== {title}")


def run():
    with sync_playwright() as p:
        browser = p.chromium.launch(channel="chrome", headless=True)
        # Scale factor 1: Flutter counter-scales the semantics host, which
        # puts leaf rects outside the viewport check at 2x.
        ctx = browser.new_context(viewport={"width": 412, "height": 915})
        page = ctx.new_page()
        page.on("console", lambda m: console.append(f"{m.type}: {m.text}") if m.type in ("error", "warning") else None)
        page.on("pageerror", lambda e: console.append(f"pageerror: {e}"))

        step("Load the app and switch semantics on")
        page.goto(APP)
        page.wait_for_selector("flt-semantics-placeholder", timeout=60000)
        page.wait_for_timeout(2500)
        page.locator("flt-semantics-placeholder").dispatch_event("click")
        wait(page, "Today's Focus", timeout=30, exact=False)
        shot(page, "01-dashboard")
        print("  dashboard loaded")

        step("Settings -> Smart Study: server address and token")
        click(page, "Profile")
        click(page, "Settings")
        wait(page, "Your Name", exact=False)
        if not scroll_until(page, "Smart Study"):
            note("Settings: could not scroll to the Smart Study section")
        # The heading is at the bottom edge; bring its rows on screen too,
        # and let the scroll settle before tapping.
        page.mouse.move(200, 500)
        page.mouse.wheel(0, 320)
        page.wait_for_timeout(1500)
        shot(page, "02-settings-smart-study")
        click(page, "Study Server", exact=False)
        wait(page, "Save")
        page.keyboard.type(SERVER, delay=10)
        click(page, "Save")
        try:
            wait(page, "Connected to the study server.", timeout=15)
            print("  server ping: Connected")
        except TimeoutError as e:
            note(f"Settings: no 'Connected to the study server.' after saving the address ({e})")
        shot(page, "03-server-saved")
        page.wait_for_timeout(4500)  # let the snackbar go
        click(page, "App Token", exact=False)
        wait(page, "Save")
        page.keyboard.type("qa-token", delay=10)
        click(page, "Save")
        page.wait_for_timeout(500)
        if not visible(page, "••••", exact=False):
            note("Settings: the App Token row doesn't show the masked value after saving")

        step("Make a set with three cards")
        if visible(page, "Back"):
            click(page, "Back")  # Settings is a sub-page without the bottom bar
        else:
            page.go_back()
            page.wait_for_timeout(800)
        click(page, "Dashboard", exact=False)
        wait(page, "Today's Focus", exact=False)
        click(page, "Add")
        click(page, "New Flashcard Set")
        wait(page, "Next")
        page.keyboard.type("QA Set", delay=10)
        click(page, "Next")
        wait(page, "Save in Folder")
        shot(page, "04-folder-picker")
        click(page, "Biology")
        wait(page, "Add cards to start studying")
        cards = [
            ("What makes ATP?", "The mitochondria"),
            ("Ribosome", "Makes proteins"),
            ("Nucleus", "Holds the DNA"),
        ]
        click(page, "Add Card")
        for i, (front, back) in enumerate(cards):
            wait(page, "Front (question or term)", exact=False)
            type_into(page, "Front (question or term)", front)
            type_into(page, "Back (answer)", back)
            click(page, "Save & Add Another" if i < len(cards) - 1 else "Save Card")
        wait(page, "3 cards", exact=False)
        wait(page, "Take a Quiz", exact=False)
        shot(page, "05-set-with-cards")
        print("  set has 3 cards and a Take a Quiz button")

        step("Take a Quiz (server has a fake key -> falls back to the cards)")
        click(page, "Take a Quiz", exact=False)
        try:
            wait(page, "key is missing or wrong", timeout=20, exact=False)
            print("  toast: server key error shown, quiz made from the cards")
            if visible(page, "Check") and find(page, "Check")["y"] > 800:
                note("Quiz: the toast floats over the Check button at the bottom for a few seconds")
            wait_gone(page, "key is missing or wrong")
        except TimeoutError:
            note("Quiz: no toast about the server's key problem (fallback message missing?)")
        wait(page, "Question 1 of", exact=False, timeout=20)
        shot(page, "06-quiz-q1")
        for q in range(1, 8):
            page.wait_for_timeout(300)
            if visible(page, "True") and visible(page, "False"):
                click(page, "True")
            elif visible(page, "Your answer", exact=False) or visible(page, "The missing word or phrase", exact=False):
                field = "Your answer" if visible(page, "Your answer", exact=False) else "The missing word or phrase"
                type_into(page, field, "the mitochondria")
            else:
                picked = False
                for cand in ("The mitochondria", "Makes proteins", "Holds the DNA"):
                    if visible(page, cand):
                        click(page, cand)
                        picked = True
                        break
                if not picked:
                    note(f"Quiz: question {q} had nothing I could pick: {labels(page)[-15:]}")
                    break
            click(page, "Check")
            page.wait_for_timeout(700)
            shot(page, f"07-quiz-q{q}-checked")
            if visible(page, "See Results"):
                click(page, "See Results")
                break
            click(page, "Next")
        try:
            wait(page, "questions right", exact=False, timeout=10)
            shot(page, "08-quiz-results")
            print("  quiz finished with a score:", [t for t in labels(page) if "%" in t][:1])
        except TimeoutError as e:
            note(f"Quiz: results screen not reached ({e})")
        if visible(page, "Done"):
            click(page, "Done")

        step("Reload: does the web build keep the set and the settings?")
        page.reload()
        page.wait_for_selector("flt-semantics-placeholder", timeout=60000)
        page.wait_for_timeout(2500)
        page.locator("flt-semantics-placeholder").dispatch_event("click")
        wait(page, "Today's Focus", timeout=30, exact=False)
        click(page, "Library", exact=False)
        if visible(page, "QA Set", exact=False):
            print("  the set survived a reload (IndexedDB)")
        else:
            note("Web: the flashcard set did not survive a page reload")
        shot(page, "08b-library-after-reload")

        step("Scan flow on the web: import a photo, save as Scan PDF")
        click(page, "Dashboard", exact=False)
        wait(page, "Today's Focus", exact=False)
        shot(page, "09-before-scan")
        photo = os.path.join(HERE, "09-before-scan.png")
        click(page, "Capture Notes")
        wait(page, "Import Photos", timeout=20, exact=False)
        with page.expect_file_chooser(timeout=10000) as fc:
            click(page, "Import Photos", exact=False)
        fc.value.set_files(photo)
        wait(page, "Crop Page", timeout=30, exact=False)
        shot(page, "10-review")
        print(f"  auto-crop hint shown: {visible(page, 'Page edges found', exact=False)}")
        click(page, "Next")
        wait(page, "Save Notes As", exact=False)
        shot(page, "11-save-sheet")
        for t in ("Scan PDF", "Text PDF", "Flashcards", "Needs text recognition (Android or iOS)"):
            if not visible(page, t, exact=False):
                note(f"Save sheet: '{t}' not shown")
        click(page, "Save as PDF")
        try:
            wait(page, "Saved to", exact=False, timeout=30)
            print("  scan PDF saved")
        except TimeoutError as e:
            note(f"Save: no 'Saved to' message after Save as PDF ({e})")
        shot(page, "12-saved")
        click(page, "Open")
        try:
            wait(page, "View Text", timeout=10)
            note("Note viewer: 'View Text' shows for a web scan that has no text")
        except TimeoutError:
            print("  note viewer: no View Text button for a note without text (as designed)")
        shot(page, "13-note-viewer")

        step("Browser console")
        errors = [c for c in console if not c.startswith("warning")]
        print(f"  {len(console)} console warnings/errors, {len(errors)} errors")
        for c in console[:20]:
            print("   ", c[:200])
        browser.close()


if __name__ == "__main__":
    try:
        run()
    except Exception as e:  # noqa: BLE001
        print(f"\n!! stopped: {type(e).__name__}: {e}")
        findings.append(f"script stopped: {e}")
        sys.exit(1)
    finally:
        print("\nFindings:" if findings else "\nNo findings from the script.")
        for f in findings:
            print(" *", f)
