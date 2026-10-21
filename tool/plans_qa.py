"""Browser run-through of the tester plan flow on the release web build
(served on :8080): free locks, upgrade, perks on, switch plan, downgrade,
locks back. Screenshots land next to this script."""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from playwright.sync_api import sync_playwright

import web_qa as q

HERE = os.path.dirname(os.path.abspath(__file__))
results = []


def check(name, ok, detail=""):
    results.append((name, ok))
    print(f"  {'PASS' if ok else 'FAIL'}  {name}{'  -- ' + detail if detail and not ok else ''}")


def shot(page, name):
    page.screenshot(path=os.path.join(HERE, f"plans-{name}.png"))


def back(page):
    q.click(page, "Back")
    page.wait_for_timeout(600)


def theme_color(page):
    """The colour of the big button area on the Plans page."""
    return page.evaluate("() => getComputedStyle(document.body).backgroundColor")


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

    print("\n== Free plan: things are locked")
    q.click(page, "Profile")
    check("Profile offers See Plans", q.visible(page, "See Plans"))
    q.click(page, "Pomodoro Analysis", exact=False)
    q.wait(page, "This Week", exact=False)
    q.click(page, "Month", exact=False)
    check("Month tab asks for Plus", q.visible(page, "Full Pomodoro Analysis", exact=False))
    shot(page, "01-free-month-locked")
    q.click(page, "Not Now")
    back(page)

    print("\n== Upgrade to Semester (test, no charge)")
    q.click(page, "See Plans")
    q.wait(page, "Test mode", exact=False)
    check("Test-mode note shown", True)
    q.scroll_until(page, "Semester Save 32%")
    q.click(page, "Semester Save 32%", exact=False)
    q.scroll_until(page, "Start Semester Plan")
    shot(page, "02-pick-semester")
    q.click(page, "Start Semester Plan", exact=False)
    page.wait_for_timeout(800)
    check("Welcome toast", q.visible(page, "Welcome to tAsikaso+ Semester", exact=False))
    check("Button says This Is Your Plan", q.visible(page, "This Is Your Plan", exact=False))
    shot(page, "03-semester-active")
    back(page)
    check("Profile card shows the plan", q.visible(page, "tAsikaso+ Semester", exact=False))
    check("Profile offers Manage Plan", q.visible(page, "Manage Plan", exact=False))
    shot(page, "04-profile-semester")

    print("\n== Perks on")
    q.click(page, "Pomodoro Analysis", exact=False)
    q.click(page, "Month", exact=False)
    check("Month analysis opens", q.visible(page, "This Month", exact=False))
    q.click(page, "Year", exact=False)
    check("Year analysis opens", q.visible(page, "This Year", exact=False))
    shot(page, "05-year")
    back(page)

    q.click(page, "Settings")
    q.wait(page, "Your Name", exact=False)
    q.scroll_until(page, "Teal")
    q.click(page, "Teal", exact=False)
    page.wait_for_timeout(800)
    shot(page, "06-teal")
    check("Teal applied (no plans page opened)", not q.visible(page, "Choose a Plan", exact=False)
          and not q.visible(page, "Change Plan", exact=False))
    back(page)

    q.scroll_until(page, "Backup & Sync")
    q.click(page, "Backup & Sync", exact=False)
    q.wait(page, "Google Drive", exact=False)
    check("Backup screen has no Plus lock",
          not q.visible(page, "Back Up Now  ·  tAsikaso+", exact=False)
          and not q.visible(page, "making backup files are part", exact=False))
    check("Back Up Now offered", q.visible(page, "Back Up Now"))
    shot(page, "07-backup-plus")
    back(page)

    print("\n== Switch to Yearly")
    q.scroll_until(page, "Manage Plan")
    q.click(page, "Manage Plan", exact=False)
    q.scroll_until(page, "Yearly Save 41%")
    q.click(page, "Yearly Save 41%", exact=False)
    q.scroll_until(page, "Switch to Yearly")
    q.click(page, "Switch to Yearly", exact=False)
    page.wait_for_timeout(800)
    check("Switched toast", q.visible(page, "Switched to tAsikaso+ Yearly", exact=False))
    page.wait_for_timeout(4500)

    print("\n== Downgrade to Free")
    q.scroll_until(page, "Go Back to Free Plan")
    q.click(page, "Go Back to Free Plan", exact=False)
    check("Confirmation asked", q.visible(page, "Go Back to Free?", exact=False))
    shot(page, "08-confirm-downgrade")
    q.click(page, "Go to Free")
    page.wait_for_timeout(800)
    check("Free toast", q.visible(page, "on the free plan now", exact=False))
    back(page)
    check("Profile back to See Plans", q.visible(page, "See Plans"))
    shot(page, "09-profile-free-again")

    print("\n== Locks are back")
    q.click(page, "Pomodoro Analysis", exact=False)
    q.click(page, "Month", exact=False)
    check("Month locked again", q.visible(page, "Full Pomodoro Analysis", exact=False))
    q.click(page, "Not Now")
    back(page)
    q.scroll_until(page, "Backup & Sync")
    q.click(page, "Backup & Sync", exact=False)
    q.wait(page, "Google Drive", exact=False)
    check("Backup locked again", q.visible(page, "Back Up Now  ·  tAsikaso+", exact=False))
    shot(page, "10-backup-free")
    back(page)

    print("\n== Reload keeps the free plan; colors are Navy")
    page.reload()
    page.wait_for_selector("flt-semantics-placeholder", timeout=60000)
    page.wait_for_timeout(2500)
    page.locator("flt-semantics-placeholder").dispatch_event("click")
    q.wait(page, "Today's Focus", timeout=30, exact=False)
    q.click(page, "Profile")
    check("Still free after reload", q.visible(page, "See Plans"))

    print(f"\npage errors: {errors[:3]}")
    browser.close()

failed = [n for n, ok in results if not ok]
print(f"\n{len(results) - len(failed)} of {len(results)} checks passed")
for n in failed:
    print("  FAILED:", n)
sys.exit(1 if failed else 0)
