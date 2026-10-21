"""End-to-end run-through of the sweep's new features on the web build
(:8080) against the real study server (:8787, talking to a fake Claude on
:8797) and a never-answering server (:8799) for Cancel."""

import os
import sys
import time
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from playwright.sync_api import sync_playwright

import web_qa as q

HERE = os.path.dirname(os.path.abspath(__file__))
TASKS = os.path.join(os.path.dirname(os.path.dirname(HERE)), "tasks")
results = []


def check(name, ok, detail=""):
    results.append((name, ok))
    print(f"  {'PASS' if ok else 'FAIL'}  {name}{'  -- ' + str(detail)[:300] if detail and not ok else ''}")


def shot(page, name):
    page.screenshot(path=os.path.join(HERE, f"sweep-{name}.png"))


def back(page):
    q.click(page, "Back")
    page.wait_for_timeout(700)


def set_server(page, url, token=None):
    q.click(page, "Profile")
    q.click(page, "Settings")
    q.wait(page, "Your Name", exact=False)
    q.scroll_until(page, "Smart Study")
    page.mouse.move(200, 500)
    page.mouse.wheel(0, 320)
    page.wait_for_timeout(1500)
    q.click(page, "Study Server", exact=False)
    q.wait(page, "Save")
    page.keyboard.press("Control+A")
    page.keyboard.type(url, delay=5)
    q.click(page, "Save")
    page.wait_for_timeout(1500)
    if token is not None:
        page.wait_for_timeout(4000)
        q.click(page, "App Token", exact=False)
        q.wait(page, "Save")
        page.keyboard.press("Control+A")
        page.keyboard.type(token, delay=5)
        q.click(page, "Save")
        page.wait_for_timeout(600)
    back(page)


def open_menu_item(page, item):
    # The set screen's ⋮ menu is the last "More"-like button on the app bar.
    boxes = page.evaluate("""() => [...document.querySelectorAll('flt-semantics')]
        .filter(e => (e.getAttribute('aria-label') || '') === '' && e.getAttribute('role') === 'button')
        .map(e => e.getBoundingClientRect().toJSON())
        .filter(r => r.top < 70 && r.left > 300)""")
    if not boxes:
        raise RuntimeError("menu button not found")
    b = boxes[-1]
    page.mouse.click(b["x"] + b["width"] / 2, b["y"] + b["height"] / 2)
    page.wait_for_timeout(600)
    q.click(page, item)


with sync_playwright() as p:
    browser = p.chromium.launch(channel="chrome", headless=True)
    page = browser.new_context(viewport={"width": 412, "height": 915}).new_page()
    errors = []
    page.on("pageerror", lambda e: errors.append(str(e)))
    page.goto(q.APP)
    page.wait_for_selector("flt-semantics-placeholder", timeout=60000)
    page.wait_for_timeout(2500)
    page.locator("flt-semantics-placeholder").dispatch_event("click")
    q.wait(page, "Today's Focus", timeout=30, exact=False)

    print("\n== Accessibility: bottom bar labels read once")
    labels = q.labels(page)
    check("No 'Dashboard Dashboard' label", not any("Dashboard Dashboard" in l for l in labels), labels[-8:])

    print("\n== Connect the app to the real server (fake Claude behind it)")
    set_server(page, "http://127.0.0.1:8787", "e2e-token")

    print("\n== A set with 3 cards")
    q.click(page, "Dashboard", exact=False)
    q.click(page, "Add")
    q.click(page, "New Flashcard Set")
    q.wait(page, "Next")
    page.keyboard.type("E2E Set", delay=10)
    q.click(page, "Next")
    q.wait(page, "Save in Folder")
    q.click(page, "Biology")
    q.wait(page, "Add cards to start studying")
    cards = [("What makes ATP?", "The mitochondria"), ("Ribosome", "Makes proteins"), ("Nucleus", "Holds the DNA")]
    q.click(page, "Add Card")
    for i, (front, back_) in enumerate(cards):
        q.wait(page, "Front (question or term)", exact=False)
        q.type_into(page, "Front (question or term)", front)
        q.type_into(page, "Back (answer)", back_)
        q.click(page, "Save & Add Another" if i < len(cards) - 1 else "Save Card")
    q.wait(page, "3 cards", exact=False)
    check("Thin-quiz hint hidden while Smart Study is on",
          not q.visible(page, "Add a few more cards for a better quiz.", exact=False))

    print("\n== New Quiz with options -> server -> Claude")
    open_menu_item(page, "New Quiz")
    q.wait(page, "Question Types", exact=False)
    shot(page, "01-options")
    check("Options sheet shows counts and types", q.visible(page, "Multiple Choice", exact=False)
          and q.visible(page, "Type the Answer", exact=False))
    q.click(page, "True or False", exact=False)       # turn off
    q.click(page, "Fill in the Blank", exact=False)   # turn off
    page.wait_for_timeout(300)
    q.click(page, "Make Quiz")
    q.wait(page, "Question 1 of", exact=False, timeout=30)
    shot(page, "02-quiz")
    check("Quiz came from Claude (via the server)", q.visible(page, "E2E question", exact=False))
    with open(os.path.join(TASKS, sys.argv[1]), encoding="utf-8", errors="replace") as f:
        claude_log = f.read()
    check("Server asked Claude for only the chosen types",
          "schema=[questions]" in claude_log)

    q.click(page, "Mitochondria")
    q.click(page, "Check")
    check("Multiple choice marked correct", q.visible(page, "Correct!", exact=False))
    q.click(page, "Next")
    q.type_into(page, "Your answer", "the powerhouse thing")
    q.click(page, "Check")
    q.wait(page, "Partly right", exact=False, timeout=30)
    shot(page, "03-partly")
    check("Typed answer judged by Claude (partly, with feedback)",
          q.visible(page, "E2E feedback", exact=False))
    q.click(page, "See Results")
    q.wait(page, "partly right of", exact=False)
    shot(page, "04-results")
    check("Partly right counts half (75%)", q.visible(page, "75%", exact=False))
    q.click(page, "Done")

    print("\n== Quiz list: delete a question")
    q.scroll_until(page, "Quiz Questions (2)")
    page.mouse.move(200, 500)
    page.mouse.wheel(0, 250)
    page.wait_for_timeout(800)
    # "Show" shares one node with the section title: tap the row's right end.
    row = q.wait(page, "Quiz Questions (2) Show", exact=False)
    rect = page.evaluate("""() => { for (const e of document.querySelectorAll('flt-semantics')) {
        const l = (e.getAttribute('aria-label') || e.textContent || '').replace(/\\s+/g, ' ').trim();
        if (l === 'Quiz Questions (2) Show') return e.getBoundingClientRect().toJSON(); } return null; }""")
    page.mouse.click(rect["right"] - 18, rect["y"] + rect["height"] / 2)
    page.wait_for_timeout(700)
    q.scroll_until(page, "Delete Question")
    q.click(page, "Delete Question")
    q.click(page, "Delete")
    page.wait_for_timeout(600)
    q.scroll_until(page, "Quiz Questions")
    check("Quiz list shows one question left", q.visible(page, "Quiz Questions (1)", exact=False))
    shot(page, "05-quiz-list")
    back(page)

    print("\n== Cancel really drops the request")
    set_server(page, "http://127.0.0.1:8799")
    q.click(page, "Library", exact=False)
    q.click(page, "E2E Set", exact=False)
    q.wait(page, "3 cards", exact=False)
    open_menu_item(page, "New Quiz")
    q.wait(page, "Question Types", exact=False)
    q.click(page, "Make Quiz")
    q.wait(page, "Cancel", timeout=15)
    page.wait_for_timeout(1500)
    shot(page, "06-progress-cancel")
    check("Progress dialog offers Cancel", q.visible(page, "Cancel"))
    q.click(page, "Cancel")
    page.wait_for_timeout(1200)
    shot(page, "07-after-cancel")
    check("Dialog closed at once, no quiz opened, no error toast",
          not q.visible(page, "Cancel")
          and not q.visible(page, "Question 1 of", exact=False)
          and not q.visible(page, "slow test server", exact=False)
          and q.visible(page, "3 cards", exact=False))
    time.sleep(1.5)
    with open(os.path.join(TASKS, sys.argv[2]), encoding="utf-8", errors="replace") as f:
        slow_log = f.read()
    check("Slow server saw the connection closed", "CLIENT CLOSED /v1/quiz" in slow_log, slow_log[-300:])
    back(page)

    print("\n== Help & FAQ")
    q.click(page, "Profile")
    q.scroll_until(page, "Help & FAQ")
    q.click(page, "Help & FAQ", exact=False)
    q.wait(page, "Help & FAQ", exact=False)
    q.scroll_until(page, "What is Smart Study?")
    check("FAQ explains Smart Study", q.visible(page, "What is Smart Study?", exact=False))
    check("FAQ explains quizzes", q.scroll_until(page, "How do quizzes work?"))

    print(f"\npage errors: {errors[:3]}")
    browser.close()

failed = [n for n, ok in results if not ok]
print(f"\n{len(results) - len(failed)} of {len(results)} checks passed")
for n in failed:
    print("  FAILED:", n)
sys.exit(1 if failed else 0)
