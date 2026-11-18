#!/usr/bin/env bash
# Runs integration_test/phone_test.dart on the emulator that
# .github/workflows/android-emulator.yml started. The results, screenshots
# and the phone's log go to emulator-results/.
set -uo pipefail
PKG=com.tasikaso.study_app
OUT=emulator-results
mkdir -p "$OUT/screenshots"

adb shell getprop ro.build.version.release > "$OUT/android-version.txt"
adb logcat -c || true
adb logcat -v time > "$OUT/logcat.txt" 2>&1 &
LOGCAT=$!

# Installed with every permission granted (camera, notifications), so no
# system dialog stops the tests; flutter drive reinstalls over it and the
# permissions stay. Exact alarms are allowed, as a user would in Settings.
adb install -r -g build/app/outputs/flutter-apk/app-debug.apk
adb shell appops set "$PKG" SCHEDULE_EXACT_ALARM allow || true

# The real study server (server/, built by the workflow) on this machine,
# with tool/fake_claude.mjs standing in for Anthropic's API: the app on the
# emulator reaches it at 10.0.2.2, so Smart Study is tested end to end
# without a key and without cost.
node tool/fake_claude.mjs > "$OUT/fake-claude.log" 2>&1 &
FAKE=$!
(cd server && ANTHROPIC_API_KEY=sk-ant-fake ANTHROPIC_BASE_URL=http://127.0.0.1:8797 \
  APP_TOKEN=emulator-token PORT=8787 node dist/index.js) > "$OUT/study-server.log" 2>&1 &
SERVER=$!
STUDY_SERVER=""
for _ in $(seq 1 30); do
  if curl -fs http://127.0.0.1:8787/health > /dev/null; then
    STUDY_SERVER=http://10.0.2.2:8787
    break
  fi
  sleep 1
done
echo "study server for the tests: ${STUDY_SERVER:-none}"

# A run normally takes several minutes; 30 is the most it may wait.
timeout 30m flutter drive --no-pub \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/phone_test.dart \
  --dart-define=E2E_STUDY_SERVER="$STUDY_SERVER" \
  -d emulator-5554 2>&1 | tee "$OUT/test.txt"
STATUS=${PIPESTATUS[0]}
kill "$SERVER" "$FAKE" 2>/dev/null || true

# The permission states a real student is likely to have, one run each
# (integration_test/restricted_test.dart). flutter drive may install the app
# afresh, wiping permission states set beforehand, and revoking a permission
# from a running app restarts it. So the state is set while the test runs:
# the test logs "TASIKASO_SETUP <step>" when it is ready, this script makes a
# change that doesn't restart the app (a grant, or a flag), and the test
# waits until it sees the change.
when_logged() { # <marker> <adb shell command...>
  # Snapshots of the log (logcat -d prints what's there and exits), once a
  # second: a live `logcat | grep -m1` would wait for the app's *next* log
  # line before going on, while the test waits silently for this change.
  local marker=$1; shift
  (
    for _ in $(seq 1 1200); do
      # grep reads all of it (no -q): stopping early would cut adb off,
      # and with pipefail the pipe would count as failed despite a match.
      if adb logcat -d -s flutter:I 2>/dev/null | grep -F "$marker" > /dev/null; then
        adb shell "$@"
        echo "set up: $*" >> "$OUT/restricted-setup.txt"
        exit 0
      fi
      sleep 1
    done
    echo "never saw: $marker" >> "$OUT/restricted-setup.txt"
  ) &
}

#  1. Exact alarms not allowed (Android 14's default for new installs), with
#     notifications allowed.
adb shell appops set "$PKG" SCHEDULE_EXACT_ALARM deny || true
when_logged "TASIKASO_SETUP grant-notifications" \
  pm grant "$PKG" android.permission.POST_NOTIFICATIONS
timeout 16m flutter drive --no-pub \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/restricted_test.dart \
  --dart-define=RESTRICTED=exact \
  -d emulator-5554 2>&1 | tee "$OUT/restricted-exact.txt"
EXACT=${PIPESTATUS[0]}
adb shell appops set "$PKG" SCHEDULE_EXACT_ALARM allow || true

#  2. Notifications refused, and fixed so (as after "Don't allow"): Android
#     answers no straight away, with no dialog. A fresh install hasn't been
#     granted them; the flag is set once the app runs.
adb shell pm revoke "$PKG" android.permission.POST_NOTIFICATIONS || true
when_logged "TASIKASO_SETUP fix-notifications-refused" \
  pm set-permission-flags "$PKG" android.permission.POST_NOTIFICATIONS user-fixed
timeout 10m flutter drive --no-pub \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/restricted_test.dart \
  --dart-define=RESTRICTED=notifications \
  -d emulator-5554 2>&1 | tee "$OUT/restricted-notifications.txt"
REFUSED=${PIPESTATUS[0]}

for s in "$EXACT" "$REFUSED"; do
  if [ "$STATUS" -eq 0 ] && [ "$s" -ne 0 ]; then STATUS=$s; fi
done

adb shell dumpsys notification --noredact > "$OUT/notifications.txt" 2>&1 || true
kill "$LOGCAT" 2>/dev/null || true
# Any setup watcher still waiting (its test failed before it was ready).
kill $(jobs -p) 2>/dev/null || true
exit "$STATUS"
