#!/usr/bin/env bash
# Runs integration_test/qa_walkthrough_test.dart on the emulator started by
# .github/workflows/qa-walkthrough.yml. Screenshots, the test output and the
# problems found go to emulator-results/.
set -uo pipefail
PKG=com.tasikaso.study_app
OUT=emulator-results
mkdir -p "$OUT/screenshots"
adb logcat -c || true
adb logcat -v time > "$OUT/logcat.txt" 2>&1 &
LOGCAT=$!
unzip -l build/app/outputs/flutter-apk/app-debug.apk | grep -i "ic_launcher" > "$OUT/apk-icons.txt" || true
adb install -r -g build/app/outputs/flutter-apk/app-debug.apk
adb shell appops set "$PKG" SCHEDULE_EXACT_ALARM allow || true
timeout 60m flutter drive --no-pub \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/qa_walkthrough_test.dart \
  -d emulator-5554 2>&1 | tee "$OUT/test.txt"
STATUS=${PIPESTATUS[0]}
# The launcher icon on the home screen's app list.
adb shell am start -a android.intent.action.MAIN -c android.intent.category.HOME >/dev/null 2>&1 || true
sleep 2
adb shell input swipe 540 1900 540 400 300 || true
sleep 2
adb exec-out screencap -p > "$OUT/screenshots/zz-app-list.png" || true
grep -E "QA_(PROBLEM|MISSING|SUMMARY|STEP)" -A3 "$OUT/test.txt" > "$OUT/qa.txt" || true
kill "$LOGCAT" 2>/dev/null || true
exit "$STATUS"
