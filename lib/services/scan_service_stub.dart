import 'package:flutter/foundation.dart';

import 'recognized_text.dart';

// Web and other platforms without ML Kit.

bool get canScanDocuments => false;

bool get canReadText => false;

Future<List<Uint8List>?> scanDocuments(int pageLimit) async => null;

Future<List<RecognizedPage>> readPages(List<Uint8List> jpegs) async =>
    [for (final _ in jpegs) const RecognizedPage()];
