"""Checks a built APK for what a phone test can't see: its permissions and
whether it runs on Android 15+ phones with 16 KB memory pages.

usage: python3 tool/check_apk.py <app.apk> <aapt2> <zipalign>
Fails (exit 1) when:
  - a permission outside ALLOWED appears (a new dependency added one: either
    remove it in android/app/src/main/AndroidManifest.xml with
    tools:node="remove", or add it here on purpose and say why);
  - a 64-bit native library has a LOAD segment aligned below 16 KB;
  - the APK's uncompressed native libraries aren't 16 KB-aligned in the zip.
"""
import struct
import subprocess
import sys
import zipfile

# Every permission the app may hold, and why.
ALLOWED = {
    "android.permission.INTERNET": "Smart Study and Google Drive sync",
    "android.permission.ACCESS_NETWORK_STATE": "added by Google libraries",
    "android.permission.POST_NOTIFICATIONS": "timer alerts, daily reminder",
    "android.permission.RECEIVE_BOOT_COMPLETED": "reschedule alerts after a restart",
    "android.permission.SCHEDULE_EXACT_ALARM": "timer alerts on time",
    "android.permission.VIBRATE": "vibrate when time is up",
    "android.permission.FOREGROUND_SERVICE": "the timer's alarm rings until Stop (TimerAlarm.kt)",
    "android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK": "the alarm's service plays the alarm sound",
    "android.permission.WAKE_LOCK": "keeps the phone awake while the alarm rings",
    "android.permission.CAMERA": "the app's own camera",
    "android.permission.READ_EXTERNAL_STORAGE": "gallery import on old Androids (ignored on 13+)",
    "android.permission.WRITE_EXTERNAL_STORAGE": "old Androids only (maxSdkVersion 28)",
    "com.tasikaso.study_app.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION": "AndroidX internal",
}

apk, aapt2, zipalign = sys.argv[1:4]
problems = []

badging = subprocess.run([aapt2, "dump", "badging", apk], capture_output=True, text=True, check=True).stdout
perms = sorted({line.split("name='")[1].split("'")[0]
                for line in badging.splitlines() if line.startswith("uses-permission:")})
for p in perms:
    print(f"permission {'ok ' if p in ALLOWED else 'NEW'} {p}")
    if p not in ALLOWED:
        problems.append(f"unexpected permission {p}")

with zipfile.ZipFile(apk) as z:
    for name in sorted(n for n in z.namelist() if n.endswith(".so") and ("arm64" in n or "x86_64" in n)):
        data = z.read(name)
        if data[:4] != b"\x7fELF" or data[4] != 2:
            continue
        endian = "<" if data[5] == 1 else ">"
        phoff = struct.unpack_from(endian + "Q", data, 0x20)[0]
        phentsize, phnum = struct.unpack_from(endian + "HH", data, 0x36)
        aligns = [struct.unpack_from(endian + "Q", data, phoff + i * phentsize + 0x30)[0]
                  for i in range(phnum)
                  if struct.unpack_from(endian + "I", data, phoff + i * phentsize)[0] == 1]
        worst = min(aligns) if aligns else 0
        print(f"16 KB pages {'ok ' if worst >= 16384 else 'BAD'} {worst:>6} {name}")
        if worst < 16384:
            problems.append(f"{name} is aligned to {worst} bytes, not 16 KB")

zip_check = subprocess.run([zipalign, "-c", "-P", "16", "4", apk], capture_output=True, text=True)
print(f"zip 16 KB alignment {'ok' if zip_check.returncode == 0 else 'BAD'}")
if zip_check.returncode != 0:
    problems.append("native libraries are not 16 KB-aligned in the APK")

if problems:
    print("\nAPK check failed:\n  " + "\n  ".join(problems))
    sys.exit(1)
print("\nAPK check passed.")
