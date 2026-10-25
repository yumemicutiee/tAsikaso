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

flutter drive --no-pub \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/phone_test.dart \
  -d emulator-5554 2>&1 | tee "$OUT/test.txt"
STATUS=${PIPESTATUS[0]}

adb shell dumpsys notification --noredact > "$OUT/notifications.txt" 2>&1 || true
kill "$LOGCAT" 2>/dev/null || true
exit "$STATUS"
