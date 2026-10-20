// Adds the Android settings that notifications need, after
// `flutter create . --platforms=android,web` has made the android/ folder.
//
//   dart run tool/setup_android.dart
//
// Safe to run more than once: anything already there is left alone.
import 'dart:io';

void main() {
  final gradleKts = File('android/app/build.gradle.kts');
  final gradle = File('android/app/build.gradle');
  final manifest = File('android/app/src/main/AndroidManifest.xml');

  if (!manifest.existsSync() || (!gradleKts.existsSync() && !gradle.existsSync())) {
    stderr.writeln('No android/ folder yet. Run this first:\n'
        '  flutter create . --platforms=android,web');
    exit(1);
  }

  if (gradleKts.existsSync()) {
    _patchGradle(
      gradleKts,
      desugarFlag: 'isCoreLibraryDesugaringEnabled = true',
      dependency: 'coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")',
    );
  } else {
    _patchGradle(
      gradle,
      desugarFlag: 'coreLibraryDesugaringEnabled true',
      dependency: "coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'",
    );
  }
  _patchManifest(manifest);
  _writeProguardRules(File('android/app/proguard-rules.pro'));
  _writeNotificationIcon(
      File('android/app/src/main/res/drawable/ic_stat_notify.xml'));
  stdout.writeln('Done. Now run: flutter pub get && flutter run');
}

/// The status-bar icon for timer alerts (white on transparent, as Android
/// requires; the launcher icon would show as a white blob).
void _writeNotificationIcon(File file) {
  if (file.existsSync()) {
    stdout.writeln('${file.path} already set up');
    return;
  }
  file.parent.createSync(recursive: true);
  file.writeAsStringSync('''
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
    <path
        android:fillColor="#FFFFFFFF"
        android:fillType="evenOdd"
        android:pathData="M12,3a9,9 0 1,0 0.01,0z M12,5.5a6.5,6.5 0 1,1 -0.01,0z M11,7.5h2v4.3l3.2,1.9 -1,1.7 -4.2,-2.5z"/>
</vector>
''');
  stdout.writeln('Wrote ${file.path}');
}

/// ML Kit's text recognition plugin refers to optional Chinese, Devanagari,
/// Japanese and Korean recognisers that the app doesn't include. Release
/// builds shrink the code (R8) and stop on those missing classes unless told
/// to ignore them. Flutter adds this file to release builds automatically.
void _writeProguardRules(File file) {
  const rules = '''
# Optional ML Kit text recognisers the app doesn't use.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
''';
  final text = file.existsSync() ? file.readAsStringSync() : '';
  if (text.contains('mlkit.vision.text.chinese')) {
    stdout.writeln('${file.path} already set up');
    return;
  }
  file.writeAsStringSync('$text$rules');
  stdout.writeln('Updated ${file.path}');
}

/// Java 8+ library desugaring, required by flutter_local_notifications.
void _patchGradle(File file,
    {required String desugarFlag, required String dependency}) {
  var text = file.readAsStringSync();
  var changed = false;

  if (!text.contains('oreLibraryDesugaringEnabled')) {
    final i = text.indexOf('compileOptions {');
    if (i < 0) {
      stderr.writeln('Could not find "compileOptions {" in ${file.path}. '
          'Add "$desugarFlag" inside android { compileOptions { ... } } by hand.');
    } else {
      final at = i + 'compileOptions {'.length;
      text = '${text.substring(0, at)}\n        $desugarFlag${text.substring(at)}';
      changed = true;
    }
  }

  if (!text.contains('desugar_jdk_libs')) {
    text = '${text.trimRight()}\n\ndependencies {\n    $dependency\n}\n';
    changed = true;
  }

  if (changed) {
    file.writeAsStringSync(text);
    stdout.writeln('Updated ${file.path}');
  } else {
    stdout.writeln('${file.path} already set up');
  }
}

/// Permissions and receivers for scheduled notifications.
void _patchManifest(File file) {
  var text = file.readAsStringSync();
  var changed = false;

  const permissions = [
    'android.permission.POST_NOTIFICATIONS',
    'android.permission.RECEIVE_BOOT_COMPLETED',
    'android.permission.SCHEDULE_EXACT_ALARM',
    'android.permission.VIBRATE',
  ];
  final missing = [
    for (final p in permissions)
      if (!text.contains('"$p"')) '    <uses-permission android:name="$p"/>',
  ];
  if (missing.isNotEmpty) {
    final i = text.indexOf('<application');
    text = '${text.substring(0, i)}${missing.join('\n')}\n    ${text.substring(i)}';
    changed = true;
  }

  // The camera plugin asks for the microphone and makes a camera required;
  // the app records no sound and can import photos instead. Both need the
  // "tools" namespace.
  if (!text.contains('xmlns:tools=')) {
    text = text.replaceFirst('<manifest ',
        '<manifest xmlns:tools="http://schemas.android.com/tools" ');
    changed = true;
  }
  const extras = [
    '    <uses-permission android:name="android.permission.RECORD_AUDIO" tools:node="remove"/>',
    '    <uses-feature android:name="android.hardware.camera.any" android:required="false" tools:replace="android:required"/>',
    '    <uses-feature android:name="android.hardware.camera" android:required="false"/>',
  ];
  final neededExtras = [
    for (final e in extras)
      if (!text.contains(e.trim().split(' ')[1])) e, // by android:name
  ];
  if (neededExtras.isNotEmpty) {
    final i = text.indexOf('<application');
    text = '${text.substring(0, i)}${neededExtras.join('\n')}\n    ${text.substring(i)}';
    changed = true;
  }

  if (!text.contains('ScheduledNotificationReceiver')) {
    const receivers = '''
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
''';
    final i = text.lastIndexOf('</application>');
    text = '${text.substring(0, i)}$receivers    ${text.substring(i)}';
    changed = true;
  }

  // The name under the icon on the home screen.
  const label = 'android:label="tAsikaso"';
  if (!text.contains(label)) {
    final named = RegExp(r'android:label="[^"]*"');
    if (named.hasMatch(text)) {
      text = text.replaceFirst(named, label);
      changed = true;
    }
  }

  if (changed) {
    file.writeAsStringSync(text);
    stdout.writeln('Updated ${file.path}');
  } else {
    stdout.writeln('${file.path} already set up');
  }
}
