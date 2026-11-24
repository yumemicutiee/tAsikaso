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
  _copyLauncherIcons(Directory('tool/android_icon/res'),
      Directory('android/app/src/main/res'));
  _writeLaunchScreen(Directory('android/app/src/main/res'));
  stdout.writeln('Done. Now run: flutter pub get && flutter run');
}

/// tAsikaso's launcher icon (tool/android_icon/res, in the default Navy &
/// Sky colors): the classic icons, the adaptive icon of Android 8+ and the
/// one-color icon for Android 13's themed icons. Always copied, replacing
/// the Flutter logo that `flutter create` puts there.
void _copyLauncherIcons(Directory from, Directory to) {
  if (!from.existsSync()) {
    stderr.writeln('${from.path} is missing; the launcher icon stays Flutter\'s.');
    return;
  }
  var copied = 0;
  for (final entity in from.listSync(recursive: true)) {
    if (entity is! File) continue;
    final relative = entity.path.substring(from.path.length + 1);
    final target = File('${to.path}/$relative');
    target.parent.createSync(recursive: true);
    entity.copySync(target.path);
    copied++;
  }
  stdout.writeln('Copied the launcher icon ($copied files)');
}

/// What shows while the app starts, before its own loading screen: the
/// logo on the loading screen's background (pale sky, or dark blue in dark
/// mode; lib/widgets/brand_mark.dart), so the hand-over is seamless. Android 12+
/// draws its own splash from the launcher icon; it gets the same background.
/// Always written, replacing `flutter create`'s plain white screen.
void _writeLaunchScreen(Directory res) {
  void write(String path, String text) {
    final file = File('${res.path}/$path');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(text);
  }

  const layers = '''
<?xml version="1.0" encoding="utf-8"?>
<!-- tAsikaso's launch screen (tool/setup_android.dart). -->
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="@color/splash_background" />
    <item>
        <bitmap android:gravity="center" android:src="@mipmap/ic_launcher_foreground" />
    </item>
</layer-list>
''';
  write('drawable/launch_background.xml', layers);
  write('drawable-v21/launch_background.xml', layers);
  String color(String hex) => '''
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="splash_background">$hex</color>
</resources>
''';
  write('values/splash_colors.xml', color('#F4F8FD'));
  write('values-night/splash_colors.xml', color('#0F1320'));
  String v31(String parent) => '''
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="LaunchTheme" parent="$parent">
        <item name="android:windowBackground">@drawable/launch_background</item>
        <item name="android:windowSplashScreenBackground">@color/splash_background</item>
    </style>
</resources>
''';
  write('values-v31/styles.xml', v31('@android:style/Theme.Light.NoTitleBar'));
  write('values-night-v31/styles.xml', v31('@android:style/Theme.Black.NoTitleBar'));
  stdout.writeln('Wrote the launch screen');
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
  // ML Kit finds its parts (the text recogniser, its model loader) by name
  // at run time. R8 renamed or removed them in release builds, so reading
  // text failed on phones ("Object.getClass() on a null object reference")
  // while debug builds worked. Checked by .github/workflows/release-check.yml.
  const mlkit = '''

# ML Kit looks its components up by name: keep them whole in release builds.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-keep class com.google_mlkit_text_recognition.** { *; }
-keep class com.google_mlkit_document_scanner.** { *; }
-keep class com.google_mlkit_commons.** { *; }
''';
  // ONNX Runtime (auto-crop's page model) is called from native code by name.
  const onnx = '''

# ONNX Runtime (auto-crop's page model) is called from native code by name.
-keep class ai.onnxruntime.** { *; }
''';
  var text = file.existsSync() ? file.readAsStringSync() : '';
  var changed = false;
  if (!text.contains('mlkit.vision.text.chinese')) {
    text = '$text$rules';
    changed = true;
  }
  if (!text.contains('-keep class com.google.mlkit.')) {
    text = '$text$mlkit';
    changed = true;
  }
  if (!text.contains('ai.onnxruntime')) {
    text = '$text$onnx';
    changed = true;
  }
  if (!changed) {
    stdout.writeln('${file.path} already set up');
    return;
  }
  file.writeAsStringSync(text);
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
    // Smart Study talks to the study server; Flutter's template grants
    // INTERNET in debug and profile builds only.
    'android.permission.INTERNET',
    'android.permission.POST_NOTIFICATIONS',
    'android.permission.RECEIVE_BOOT_COMPLETED',
    'android.permission.SCHEDULE_EXACT_ALARM',
    // A timer app's alarm, granted at install on Android 13+.
    'android.permission.USE_EXACT_ALARM',
    'android.permission.VIBRATE',
    // The timer's alarm, rung by the app itself (TimerAlarm.kt).
    'android.permission.FOREGROUND_SERVICE',
    'android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK',
    'android.permission.WAKE_LOCK',
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
    // androidx.biometric (a dependency's) asks for these; nothing uses them.
    '    <uses-permission android:name="android.permission.USE_BIOMETRIC" tools:node="remove"/>',
    '    <uses-permission android:name="android.permission.USE_FINGERPRINT" tools:node="remove"/>',
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

  // The timer alert's Stop button (it silences the alarm without opening
  // the app) is handled by this receiver of the notifications plugin.
  if (!text.contains('ActionBroadcastReceiver')) {
    const receiver = '''
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver" />
''';
    final i = text.lastIndexOf('</application>');
    text = '${text.substring(0, i)}$receiver    ${text.substring(i)}';
    changed = true;
  }

  // The timer's alarm: rung by the app itself until Stop (TimerAlarm.kt).
  if (!text.contains('.TimerAlarmService')) {
    const alarm = '''
        <receiver android:exported="false" android:name=".TimerAlarmReceiver" />
        <service android:exported="false" android:name=".TimerAlarmService"
            android:foregroundServiceType="mediaPlayback" />
''';
    final i = text.lastIndexOf('</application>');
    text = '${text.substring(0, i)}$alarm    ${text.substring(i)}';
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
