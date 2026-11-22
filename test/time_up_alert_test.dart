import 'package:flutter_test/flutter_test.dart';

import 'package:study_app/models/models.dart';

void main() {
  test('the default is the alarm sound with vibration', () {
    expect(const AppPrefs().timeUpAlert, TimeUpAlert.alarmAndVibration);
  });

  test('each choice is the right mix of sound and vibration', () {
    expect((TimeUpAlert.alarmAndVibration.sound, TimeUpAlert.alarmAndVibration.vibrate),
        (true, true));
    expect((TimeUpAlert.alarm.sound, TimeUpAlert.alarm.vibrate), (true, false));
    expect((TimeUpAlert.vibration.sound, TimeUpAlert.vibration.vibrate), (false, true));
    expect((TimeUpAlert.off.sound, TimeUpAlert.off.vibrate), (false, false));
    expect(TimeUpAlert.values.map((a) => a.label), [
      'Alarm Clock and Vibration',
      'Alarm Clock',
      'Vibration Only',
      'Off',
    ]);
  });

  test('every choice can be picked, saved and read back', () {
    for (final a in TimeUpAlert.values) {
      final p = const AppPrefs().withTimeUpAlert(a);
      expect(p.timeUpAlert, a);
      expect(AppPrefs.fromJson(p.toJson()).timeUpAlert, a);
    }
  });

  test("Off keeps the sound and vibration choices, so turning back on restores "
      "them", () {
    final alarmOnly = const AppPrefs().withTimeUpAlert(TimeUpAlert.alarm);
    final off = alarmOnly.withTimeUpAlert(TimeUpAlert.off);
    expect(off.timeUpAlert, TimeUpAlert.off);
    expect(off.timerAlerts, isFalse);
    expect(off.copyWith(timerAlerts: true).timeUpAlert, TimeUpAlert.alarm);
  });

  test('settings saved before this choice existed mean the same as before', () {
    // Timer Alerts on, Vibrate on (the old defaults) → alarm and vibration.
    expect(AppPrefs.fromJson(const {'alerts': true, 'vibrate': true}).timeUpAlert,
        TimeUpAlert.alarmAndVibration);
    expect(AppPrefs.fromJson(const {'alerts': true, 'vibrate': false}).timeUpAlert,
        TimeUpAlert.alarm);
    expect(AppPrefs.fromJson(const {'alerts': false, 'vibrate': true}).timeUpAlert,
        TimeUpAlert.off);
  });

  test('updating from before the alarm choice says once that alerts now ring '
      'like an alarm', () {
    expect(AppPrefs.fromJson(const {'alerts': true, 'vibrate': true}).alarmNotice,
        isTrue);
    expect(AppPrefs.fromJson(const {'alerts': false}).alarmNotice, isFalse);
    // Saved by 0.5.1 or later: nothing changed for them.
    expect(AppPrefs.fromJson(const {'alerts': true, 'alarm': true}).alarmNotice,
        isFalse);
    expect(const AppPrefs().alarmNotice, isFalse);
    // Seen: the next save drops it, and it stays gone.
    final seen = AppPrefs.fromJson(const {'alerts': true})
        .copyWith(alarmNotice: false);
    expect(AppPrefs.fromJson(seen.toJson()).alarmNotice, isFalse);
  });
}
