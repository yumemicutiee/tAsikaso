import 'package:idb_shim/idb_browser.dart';

import 'local_storage.dart';
import 'local_storage_idb.dart';

/// The browser's IndexedDB, so data survives a reload.
LocalStorage createStorage() => IdbStorage(idbFactoryBrowser);
