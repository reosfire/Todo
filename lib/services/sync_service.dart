import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/app_data.dart';
import '../models/sync_index.dart';
import '../models/task.dart';
import '../models/task_list.dart';
import '../models/folder.dart';
import '../models/tag.dart';
import '../models/smart_list.dart';
import 'dropbox_service.dart';
import 'storage_service.dart';

/// Orchestrates per-entity sync with Dropbox.
///
/// Dropbox layout:
/// ```
/// /index.json              – SyncIndex (timestamps + deletions)
/// /tasks/{id}.json         – individual Task
/// /lists/{id}.json         – individual TaskList
/// /folders/{id}.json       – individual Folder
/// /tags/{id}.json          – individual Tag
/// /smart_lists/{id}.json   – individual SmartList
/// ```
///
/// On every local change the affected entity is pushed to Dropbox in the
/// background.  Rapid changes are batched (500 ms debounce) so that only one
/// remote index round-trip is needed per batch.
class SyncService {
  final DropboxService _dropbox;
  final StorageService _storage;

  /// Tracks each entity's last-modified time as known locally.
  SyncIndex _localIndex = SyncIndex();

  // ── Batching / queueing ──

  /// Buffered changes waiting for the next flush.
  /// Value is the entity JSON, or `null` for a deletion.
  final Map<String, Map<String, dynamic>?> _pendingChanges = {};
  Timer? _pushTimer;

  /// Sequential operation chain so pushes never overlap.
  Future<void>? _pendingOp;

  /// Callback invoked when remote changes have been pulled into [AppData].
  /// The caller (AppState) sets this so it can call notifyListeners / save.
  void Function(AppData)? onRemoteDataChanged;

  /// Current longpoll cursor (Dropbox list_folder cursor).
  String? _longpollCursor;

  /// Whether the remote-polling loop is active.
  bool _polling = false;

  SyncService(this._dropbox, this._storage);

  bool get isSignedIn => _dropbox.isSignedIn;

  // ───── Initialisation ─────

  /// Load the persisted local index and make sure every entity in [data]
  /// has an entry (important on first run or after adding entities offline).
  Future<void> init(AppData data) async {
    _localIndex = await _storage.loadSyncIndex();
    _ensureAllEntitiesIndexed(data);
    await _storage.saveSyncIndex(_localIndex);
  }

  void _ensureAllEntitiesIndexed(AppData data) {
    final fallback = data.lastModified;
    for (final t in data.tasks) {
      _localIndex.entities.putIfAbsent('tasks/${t.id}', () => fallback);
    }
    for (final l in data.lists) {
      _localIndex.entities.putIfAbsent('lists/${l.id}', () => fallback);
    }
    for (final f in data.folders) {
      _localIndex.entities.putIfAbsent('folders/${f.id}', () => fallback);
    }
    for (final t in data.tags) {
      _localIndex.entities.putIfAbsent('tags/${t.id}', () => fallback);
    }
    for (final s in data.smartLists) {
      _localIndex.entities.putIfAbsent('smart_lists/${s.id}', () => fallback);
    }
  }

  // ───── Auto-push (called on every local change) ─────

  /// Schedule an entity upsert to Dropbox.
  void pushEntity(String type, String id, Map<String, dynamic> json) {
    final key = '$type/$id';
    final now = DateTime.now();
    _localIndex.entities[key] = now;
    _localIndex.deletions.remove(key);
    _storage.saveSyncIndex(_localIndex); // fire-and-forget

    if (!_dropbox.isSignedIn) return;
    _pendingChanges[key] = json;
    _schedulePush();
  }

  /// Schedule an entity deletion on Dropbox.
  void pushDeletion(String type, String id) {
    final key = '$type/$id';
    final now = DateTime.now();
    _localIndex.entities.remove(key);
    _localIndex.deletions[key] = now;
    _storage.saveSyncIndex(_localIndex);

    if (!_dropbox.isSignedIn) return;
    _pendingChanges[key] = null; // null ⇒ delete
    _schedulePush();
  }

  void _schedulePush() {
    _pushTimer?.cancel();
    _pushTimer = Timer(const Duration(milliseconds: 500), _flushPendingChanges);
  }

  void _flushPendingChanges() {
    if (_pendingChanges.isEmpty) return;

    final batch = Map<String, Map<String, dynamic>?>.from(_pendingChanges);
    _pendingChanges.clear();

    _enqueue(() async {
      try {
        // 1. Upload / delete each entity file.
        for (final entry in batch.entries) {
          if (entry.value != null) {
            await _dropbox.uploadFile(
              '/${entry.key}.json',
              jsonEncode(entry.value),
            );
          } else {
            try {
              await _dropbox.deleteFile('/${entry.key}.json');
            } catch (_) {}
          }
        }

        // 2. Single remote-index round-trip for the whole batch.
        final remoteIndex = await _downloadRemoteIndex();
        for (final entry in batch.entries) {
          if (entry.value != null) {
            remoteIndex.entities[entry.key] = _localIndex.entities[entry.key]!;
            remoteIndex.deletions.remove(entry.key);
          } else {
            remoteIndex.entities.remove(entry.key);
            remoteIndex.deletions[entry.key] =
                _localIndex.deletions[entry.key]!;
          }
        }
        await _uploadRemoteIndex(remoteIndex);
      } catch (e) {
        debugPrint('Batch sync error: $e');
      }
    });
  }

  // ───── Queue helpers ─────

  void _enqueue(Future<void> Function() op) {
    _pendingOp = (_pendingOp ?? Future.value()).then(
      (_) => op().catchError(
        (Object e) => debugPrint('Enqueued sync op error: $e'),
      ),
    );
  }

  Future<void> _waitForPendingOps() async {
    _pushTimer?.cancel();
    _flushPendingChanges();
    if (_pendingOp != null) await _pendingOp;
  }

  // ───── Full sync ─────

  Future<AppData> fullSync(AppData localData) async {
    if (!_dropbox.isSignedIn) return localData;

    await _waitForPendingOps();

    final completer = Completer<AppData>();
    _enqueue(() async {
      try {
        completer.complete(await _performFullSync(localData));
      } catch (e) {
        completer.completeError(e);
      }
    });
    return completer.future;
  }

  Future<AppData> _performFullSync(AppData localData) async {
    // 1. Download remote index.
    final indexContent = await _dropbox.downloadFile('/index.json');

    if (indexContent == null) {
      // No index yet – check for legacy single-file format.
      final legacyContent = await _dropbox.downloadFile('/todo_data.json');
      if (legacyContent != null) {
        return _migrateFromLegacy(localData, legacyContent);
      }
      // Completely fresh remote – upload everything.
      await _uploadAllEntities(localData);
      return localData;
    }

    final remoteIndex = SyncIndex.fromJson(
      jsonDecode(indexContent) as Map<String, dynamic>,
    );

    bool localChanged = false;

    // 2. Process remote deletions.
    for (final entry in remoteIndex.deletions.entries) {
      final localTime = _localIndex.entities[entry.key];
      if (localTime != null && entry.value.isAfter(localTime)) {
        _removeEntityFromData(localData, entry.key);
        _localIndex.entities.remove(entry.key);
        _localIndex.deletions[entry.key] = entry.value;
        localChanged = true;
      }
    }

    // 3. Download entities that are newer remotely.
    for (final entry in remoteIndex.entities.entries) {
      if (remoteIndex.deletions.containsKey(entry.key)) continue;
      final localTime = _localIndex.entities[entry.key];
      if (localTime == null || entry.value.isAfter(localTime)) {
        try {
          final content = await _dropbox.downloadFile('/${entry.key}.json');
          if (content != null) {
            final json = jsonDecode(content) as Map<String, dynamic>;
            _applyEntityToData(localData, entry.key, json);
            _localIndex.entities[entry.key] = entry.value;
            localChanged = true;
          }
        } catch (e) {
          debugPrint('Error downloading ${entry.key}: $e');
        }
      }
    }

    // 4. Upload entities that are newer locally.
    for (final entry in _localIndex.entities.entries) {
      if (_localIndex.deletions.containsKey(entry.key)) continue;
      // Skip if remote has a newer deletion.
      final remoteDeletion = remoteIndex.deletions[entry.key];
      if (remoteDeletion != null && remoteDeletion.isAfter(entry.value)) {
        continue;
      }
      final remoteTime = remoteIndex.entities[entry.key];
      if (remoteTime == null || entry.value.isAfter(remoteTime)) {
        try {
          final json = _extractEntityFromData(localData, entry.key);
          if (json != null) {
            await _dropbox.uploadFile('/${entry.key}.json', jsonEncode(json));
            remoteIndex.entities[entry.key] = entry.value;
            remoteIndex.deletions.remove(entry.key);
          }
        } catch (e) {
          debugPrint('Error uploading ${entry.key}: $e');
        }
      }
    }

    // 5. Push local deletions to remote.
    for (final entry in _localIndex.deletions.entries) {
      final remoteTime = remoteIndex.entities[entry.key];
      if (remoteTime != null && entry.value.isAfter(remoteTime)) {
        try {
          await _dropbox.deleteFile('/${entry.key}.json');
        } catch (_) {}
        remoteIndex.entities.remove(entry.key);
        remoteIndex.deletions[entry.key] = entry.value;
      }
    }

    // 6. Persist.
    await _uploadRemoteIndex(remoteIndex);
    await _storage.saveSyncIndex(_localIndex);

    if (localChanged) {
      localData.lastModified = DateTime.now();
    }
    return localData;
  }

  // ───── Legacy migration ─────

  Future<AppData> _migrateFromLegacy(
    AppData localData,
    String legacyContent,
  ) async {
    try {
      final legacyData = AppData.fromJson(
        jsonDecode(legacyContent) as Map<String, dynamic>,
      );
      final baseData = legacyData.lastModified.isAfter(localData.lastModified)
          ? legacyData
          : localData;
      await _uploadAllEntities(baseData);
      // Try to remove the old file.
      try {
        await _dropbox.deleteFile('/todo_data.json');
      } catch (_) {}
      return baseData;
    } catch (e) {
      debugPrint('Legacy migration error: $e');
      return localData;
    }
  }

  // ───── Force upload / download ─────

  Future<void> forceUploadAll(AppData data) async {
    if (!_dropbox.isSignedIn) return;
    await _waitForPendingOps();

    final completer = Completer<void>();
    _enqueue(() async {
      try {
        await _uploadAllEntities(data);
        completer.complete();
      } catch (e) {
        completer.completeError(e);
      }
    });
    return completer.future;
  }

  Future<AppData> forceDownloadAll() async {
    if (!_dropbox.isSignedIn) return AppData();
    await _waitForPendingOps();

    final completer = Completer<AppData>();
    _enqueue(() async {
      try {
        completer.complete(await _performForceDownload());
      } catch (e) {
        completer.completeError(e);
      }
    });
    return completer.future;
  }

  Future<AppData> _performForceDownload() async {
    final remoteIndex = await _downloadRemoteIndex();
    final data = AppData();

    for (final key in remoteIndex.entities.keys) {
      if (remoteIndex.deletions.containsKey(key)) continue;
      try {
        final content = await _dropbox.downloadFile('/$key.json');
        if (content != null) {
          final json = jsonDecode(content) as Map<String, dynamic>;
          _applyEntityToData(data, key, json);
          _localIndex.entities[key] = remoteIndex.entities[key]!;
        }
      } catch (e) {
        debugPrint('Error downloading $key: $e');
      }
    }

    _localIndex.deletions = Map.from(remoteIndex.deletions);
    await _storage.saveSyncIndex(_localIndex);
    return data;
  }

  // ───── Upload all entities (used by force-upload & first sync) ─────

  Future<void> _uploadAllEntities(AppData data) async {
    final remoteIndex = SyncIndex();
    final now = DateTime.now();

    Future<void> upload(
      String type,
      String id,
      Map<String, dynamic> json,
    ) async {
      final key = '$type/$id';
      await _dropbox.uploadFile('/$key.json', jsonEncode(json));
      remoteIndex.entities[key] = now;
      _localIndex.entities[key] = now;
    }

    for (final t in data.tasks) {
      await upload('tasks', t.id, t.toJson());
    }
    for (final l in data.lists) {
      await upload('lists', l.id, l.toJson());
    }
    for (final f in data.folders) {
      await upload('folders', f.id, f.toJson());
    }
    for (final t in data.tags) {
      await upload('tags', t.id, t.toJson());
    }
    for (final s in data.smartLists) {
      await upload('smart_lists', s.id, s.toJson());
    }

    _localIndex.deletions.clear();
    await _uploadRemoteIndex(remoteIndex);
    await _storage.saveSyncIndex(_localIndex);
  }

  // ───── Remote index helpers ─────

  Future<SyncIndex> _downloadRemoteIndex() async {
    final content = await _dropbox.downloadFile('/index.json');
    if (content != null) {
      return SyncIndex.fromJson(jsonDecode(content) as Map<String, dynamic>);
    }
    return SyncIndex();
  }

  Future<void> _uploadRemoteIndex(SyncIndex index) async {
    await _dropbox.uploadFile('/index.json', jsonEncode(index.toJson()));
  }

  // ───── Data manipulation helpers ─────

  void _applyEntityToData(AppData data, String key, Map<String, dynamic> json) {
    final slash = key.indexOf('/');
    final type = key.substring(0, slash);
    switch (type) {
      case 'tasks':
        final entity = Task.fromJson(json);
        final idx = data.tasks.indexWhere((t) => t.id == entity.id);
        if (idx >= 0) {
          data.tasks[idx] = entity;
        } else {
          data.tasks.add(entity);
        }
      case 'lists':
        final entity = TaskList.fromJson(json);
        final idx = data.lists.indexWhere((l) => l.id == entity.id);
        if (idx >= 0) {
          data.lists[idx] = entity;
        } else {
          data.lists.add(entity);
        }
      case 'folders':
        final entity = Folder.fromJson(json);
        final idx = data.folders.indexWhere((f) => f.id == entity.id);
        if (idx >= 0) {
          data.folders[idx] = entity;
        } else {
          data.folders.add(entity);
        }
      case 'tags':
        final entity = Tag.fromJson(json);
        final idx = data.tags.indexWhere((t) => t.id == entity.id);
        if (idx >= 0) {
          data.tags[idx] = entity;
        } else {
          data.tags.add(entity);
        }
      case 'smart_lists':
        final entity = SmartList.fromJson(json);
        final idx = data.smartLists.indexWhere((s) => s.id == entity.id);
        if (idx >= 0) {
          data.smartLists[idx] = entity;
        } else {
          data.smartLists.add(entity);
        }
    }
  }

  void _removeEntityFromData(AppData data, String key) {
    final slash = key.indexOf('/');
    final type = key.substring(0, slash);
    final id = key.substring(slash + 1);
    switch (type) {
      case 'tasks':
        data.tasks.removeWhere((t) => t.id == id);
      case 'lists':
        data.lists.removeWhere((l) => l.id == id);
      case 'folders':
        data.folders.removeWhere((f) => f.id == id);
      case 'tags':
        data.tags.removeWhere((t) => t.id == id);
      case 'smart_lists':
        data.smartLists.removeWhere((s) => s.id == id);
    }
  }

  Map<String, dynamic>? _extractEntityFromData(AppData data, String key) {
    final slash = key.indexOf('/');
    final type = key.substring(0, slash);
    final id = key.substring(slash + 1);
    try {
      switch (type) {
        case 'tasks':
          return data.tasks.firstWhere((t) => t.id == id).toJson();
        case 'lists':
          return data.lists.firstWhere((l) => l.id == id).toJson();
        case 'folders':
          return data.folders.firstWhere((f) => f.id == id).toJson();
        case 'tags':
          return data.tags.firstWhere((t) => t.id == id).toJson();
        case 'smart_lists':
          return data.smartLists.firstWhere((s) => s.id == id).toJson();
        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }

  // ───── Pull remote changes (index-based) ─────

  /// Downloads only the entities that are newer on the server than locally.
  /// Returns `true` if any local data was changed.
  Future<bool> pullRemoteChanges(AppData localData) async {
    if (!_dropbox.isSignedIn) return false;

    try {
      final indexContent = await _dropbox.downloadFile('/index.json');
      if (indexContent == null) return false;

      final remoteIndex = SyncIndex.fromJson(
        jsonDecode(indexContent) as Map<String, dynamic>,
      );

      bool changed = false;

      // Process remote deletions.
      for (final entry in remoteIndex.deletions.entries) {
        final localTime = _localIndex.entities[entry.key];
        if (localTime != null && entry.value.isAfter(localTime)) {
          _removeEntityFromData(localData, entry.key);
          _localIndex.entities.remove(entry.key);
          _localIndex.deletions[entry.key] = entry.value;
          changed = true;
        }
      }

      // Download entities that are newer remotely.
      for (final entry in remoteIndex.entities.entries) {
        if (remoteIndex.deletions.containsKey(entry.key)) continue;
        final localTime = _localIndex.entities[entry.key];
        if (localTime == null || entry.value.isAfter(localTime)) {
          try {
            final content = await _dropbox.downloadFile('/${entry.key}.json');
            if (content != null) {
              final json = jsonDecode(content) as Map<String, dynamic>;
              _applyEntityToData(localData, entry.key, json);
              _localIndex.entities[entry.key] = entry.value;
              changed = true;
            }
          } catch (e) {
            debugPrint('Pull error for ${entry.key}: $e');
          }
        }
      }

      if (changed) {
        localData.lastModified = DateTime.now();
        await _storage.saveSyncIndex(_localIndex);
      }

      return changed;
    } catch (e) {
      debugPrint('pullRemoteChanges error: $e');
      return false;
    }
  }

  // ───── Dropbox longpoll-based remote polling ─────

  /// Start continuously polling Dropbox for remote changes.
  /// When changes are detected the remote index is checked and new entities
  /// are pulled.  This runs an infinite loop until [stopRemotePolling] is
  /// called.
  void startRemotePolling(AppData Function() currentData) {
    if (_polling) return;
    _polling = true;
    _pollLoop(currentData);
  }

  void stopRemotePolling() {
    _polling = false;
  }

  Future<void> _pollLoop(AppData Function() currentData) async {
    while (_polling && _dropbox.isSignedIn) {
      try {
        // Obtain a cursor if we don't have one yet.
        _longpollCursor ??= await _dropbox.getLatestCursor();
        if (_longpollCursor == null) {
          // Could not get cursor – wait and retry.
          await Future.delayed(const Duration(seconds: 30));
          continue;
        }

        // Block until Dropbox signals a change (or timeout).
        final hasChanges = await _dropbox.longpollForChanges(
          _longpollCursor!,
          timeout: 120,
        );

        if (!_polling) break;

        if (hasChanges == null) {
          // Error or cursor reset – get a fresh cursor.
          _longpollCursor = null;
          await Future.delayed(const Duration(seconds: 5));
          continue;
        }

        if (hasChanges) {
          // Something changed – refresh the cursor and pull updates.
          _longpollCursor = await _dropbox.getLatestCursor();

          final data = currentData();
          final changed = await pullRemoteChanges(data);
          if (changed && onRemoteDataChanged != null) {
            onRemoteDataChanged!(data);
          }
        } else {
          // Timeout with no changes – refresh cursor and loop.
          _longpollCursor = await _dropbox.getLatestCursor();
        }
      } catch (e) {
        debugPrint('Poll loop error: $e');
        _longpollCursor = null;
        if (_polling) {
          await Future.delayed(const Duration(seconds: 10));
        }
      }
    }
  }
}
