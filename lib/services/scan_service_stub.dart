import 'package:flutter/foundation.dart';

// Web and other platforms without ML Kit.

bool get canScanDocuments => false;

bool get canReadText => false;

Future<List<Uint8List>?> scanDocuments(int pageLimit) async => null;

Future<String> readText(List<Uint8List> jpegs) async => '';
