import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:study_app/theme/brand.dart';

void main() {
  test("the app's version matches pubspec.yaml", () {
    final line = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('version:'));
    final name = line.substring('version:'.length).trim().split('+').first;
    expect(kAppVersion, name,
        reason: 'raise kAppVersion (lib/theme/brand.dart) with the version');
  });
}
