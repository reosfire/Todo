import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_data.dart';
import '../models/sync_index.dart';

class StorageService {
  static const _fileName = 'todo_data.json';
  static const _webKey = 'todo_app_data';
  static const _syncIndexFile = 'sync_index.json';
  static const _syncIndexWebKey = 'todo_sync_index';

  Future<File> get _file async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<AppData> load() async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        final jsonString = prefs.getString(_webKey);
        if (jsonString != null) {
          final json = jsonDecode(jsonString) as Map<String, dynamic>;
          return AppData.fromJson(json);
        }
      } else {
        final file = await _file;
        if (await file.exists()) {
          final contents = await file.readAsString();
          final json = jsonDecode(contents) as Map<String, dynamic>;
          return AppData.fromJson(json);
        }
      }
    } catch (e) {
      // ignore corrupt data, return defaults
    }
    return AppData();
  }

  Future<void> save(AppData data) async {
    data.lastModified = DateTime.now();
    final json = jsonEncode(data.toJson());

    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_webKey, json);
    } else {
      final file = await _file;
      await file.writeAsString(json);
    }
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

  // ───── Sync index ─────

  Future<SyncIndex> loadSyncIndex() async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        final jsonString = prefs.getString(_syncIndexWebKey);
        if (jsonString != null) {
          return SyncIndex.fromJson(
            jsonDecode(jsonString) as Map<String, dynamic>,
          );
        }
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/$_syncIndexFile');
        if (await file.exists()) {
          final contents = await file.readAsString();
          return SyncIndex.fromJson(
            jsonDecode(contents) as Map<String, dynamic>,
          );
        }
      }
    } catch (_) {}
    return SyncIndex();
  }

  Future<void> saveSyncIndex(SyncIndex index) async {
    final json = jsonEncode(index.toJson());
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_syncIndexWebKey, json);
    } else {
      final dir = await getApplicationDocumentsDirectory();
      await File('${dir.path}/$_syncIndexFile').writeAsString(json);
    }
  }

  // ───── UI state (local only) ─────

  static const _expandedFoldersKey = 'expanded_folder_ids';

  Future<Set<String>> loadExpandedFolderIds() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_expandedFoldersKey);
    return ids?.toSet() ?? {};
  }

  Future<void> saveExpandedFolderIds(Set<String> folderIds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_expandedFoldersKey, folderIds.toList());
  }
}
