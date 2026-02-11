import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/app_data.dart';

class StorageService {
  static const _fileName = 'todo_data.json';

  Future<File> get _file async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<AppData> load() async {
    try {
      final file = await _file;
      if (await file.exists()) {
        final contents = await file.readAsString();
        final json = jsonDecode(contents) as Map<String, dynamic>;
        return AppData.fromJson(json);
      }
    } catch (e) {
      // ignore corrupt data, return defaults
    }
    return AppData();
  }

  Future<void> save(AppData data) async {
    final file = await _file;
    data.lastModified = DateTime.now();
    final json = jsonEncode(data.toJson());
    await file.writeAsString(json);
  }

  /// Returns raw JSON string for uploading.
  Future<String> exportJson(AppData data) async {
    data.lastModified = DateTime.now();
    return jsonEncode(data.toJson());
  }

  /// Parses downloaded JSON string.
  AppData importJson(String jsonString) {
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return AppData.fromJson(json);
  }
}
