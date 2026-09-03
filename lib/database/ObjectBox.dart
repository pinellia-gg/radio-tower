import 'dart:io';

import 'package:lib_common/log/Logger.dart';
import 'package:radio_tower/common/retryable_async_initializer.dart';

import '../objectbox.g.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class ObjectBox {
  final Store store;

  static final _initializer = RetryableAsyncInitializer<ObjectBox>();

  ObjectBox._create(this.store);

  static Future<ObjectBox> createAsync() {
    return _initializer.getOrCreate(_open);
  }

  static Future<ObjectBox> _open() async {
    Logger.wLog("ObjectBox", "createAsync");

    final docsDir = await getApplicationDocumentsDirectory();
    final dbPath = path.join(docsDir.path, "RadioTower", "database");
    final directory = Directory(dbPath);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final store =
        Store.isOpen(dbPath)
            ? Store.attach(getObjectBoxModel(), dbPath)
            : await openStore(directory: dbPath);
    return ObjectBox._create(store);
  }
}
