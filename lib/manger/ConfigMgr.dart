import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:lib_common/log/Logger.dart';

class ConfigMgr {
  final String _tag = "ConfigMgr";

  static final ConfigMgr _instance = ConfigMgr._create();

  late final String _configFolder;
  late final String _path;
  final String _fileName = "config";

  Map<String, dynamic> _dataMap = HashMap();

  ConfigMgr._create();

  factory ConfigMgr() {
    return _instance;
  }

  Future<void> init() async {
    String docDir = await getApplicationDocumentsDirectory().then(
      (dir) => dir.path,
    );
    _configFolder = path.join(docDir, "RadioTower", "config");
    _path = path.join(_configFolder, _fileName);
    File file = File(_path);

    if (!file.existsSync()) {
      file.create(recursive: true, exclusive: true);
      saveSync();
    } else {
      try {
        String content = file.readAsStringSync();
        _dataMap = jsonDecode(content);
      } on Exception catch (e, stacktrace) {
        Logger.eLog(_tag, "解析配置文件错误", error: e, stackTrace: stacktrace);
      }
    }
  }

  int getIntVal(String key, int defValue) {
    int value = defValue;
    try {
      value = _dataMap[key];
    } catch (e) {
      // print(e);
    }
    return value;
  }

  ConfigMgr put(String key, dynamic value) {
    _dataMap[key] = value;

    return this;
  }

  bool getBoolVal(String key, bool defValue) {
    bool? value = defValue;

    try {
      value = _dataMap[key];
    } on Exception {
      // print(e);
    }

    return value ?? defValue;
  }

  String getStringVal(String key, String defValue) {
    String value = defValue;
    try {
      value = _dataMap[key];
    } catch (e) {
      // print(e);
    }
    return value;
  }

  double getDoubleVal(String key, double defValue) {
    final value = _dataMap[key];
    if (value is num) {
      return value.toDouble();
    }
    return defValue;
  }

  List<String> getStringListVal(String key, List<String> defValue) {
    List<String> value = defValue;
    try {
      value = _dataMap[key];
    } catch (e) {
      value = defValue;
    }
    return value;
  }

  List<int> getIntListVal(String key, List<int> defValue) {
    List<int> value = defValue;
    try {
      value = _dataMap[key];
    } catch (e) {
      value = defValue;
    }
    return value;
  }

  List<double> getDoubleListVal(String key, List<double> defValue) {
    List<double> value = defValue;
    try {
      value = _dataMap[key];
    } catch (e) {}

    value = defValue;

    return value;
  }

  Map<String, dynamic> getMapVal(String key, Map<String, dynamic> defValue) {
    Map<String, dynamic> value = defValue;
    try {
      value = _dataMap[key];
    } catch (e) {}

    return value;
  }

  void saveSync() {
    try {
      File file = File(_path);

      String content = jsonEncode(_dataMap);
      file.writeAsStringSync(content, flush: true);
    } catch (e) {
      // print(e);
    }
  }

  Future<void> save() async {
    try {
      File file = File(_path);

      String content = jsonEncode(_dataMap);
      await file.writeAsString(content, flush: true);
    } catch (e) {
      // print(e);
    }
  }
}
