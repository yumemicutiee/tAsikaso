import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Runs integration_test/ through `flutter drive` and saves the screenshots
/// the tests take to emulator-results/screenshots/.
Future<void> main() => integrationDriver(
      onScreenshot: (name, bytes, [args]) async {
        final file = File('emulator-results/screenshots/$name.png');
        await file.create(recursive: true);
        await file.writeAsBytes(bytes);
        return true;
      },
    );
