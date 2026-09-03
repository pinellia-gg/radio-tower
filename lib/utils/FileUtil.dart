import 'dart:io' show File;

class FileUtil {
  Future<String> _readFileAsync(String filename) {
    final file = File(filename);

    // .readAsString() returns a Future.
    // .then() registers a callback to be executed when `readAsString` resolves.
    return file.readAsString().then((contents) {
      return contents.trim();
    });
  }

  String readFile(String filename) {
    final file = File(filename);
    final contents = file.readAsStringSync();
    return contents.trim();
  }

  Future<String> readFileAsync(String filename) async {

    final file = File(filename);
    final contents = await file.readAsString();
    return contents.trim();
  }
}
