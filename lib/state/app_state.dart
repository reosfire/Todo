import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/app_data.dart';
import '../models/task.dart';
import '../models/task_list.dart';
import '../models/folder.dart';
import '../models/tag.dart';
import '../models/smart_list.dart';
import '../services/storage_service.dart';
import '../services/dropbox_service.dart';

const _uuid = Uuid();

class AppState extends ChangeNotifier {
  final StorageService _storage = StorageService();
  final DropboxService dropboxService = DropboxService();

  AppData _data = AppData();
  bool _loading = true;
  bool _syncing = false;

  bool get loading => _loading;
  bool get syncing => _syncing;
  bool get isSignedIn => dropboxService.isSignedIn;

  List<Task> get tasks => _data.tasks;
  List<TaskList> get lists => _data.lists;
  List<Folder> get folders => _data.folders;
  List<Tag> get tags => _data.tags;
  List<SmartList> get smartLists => _data.smartLists;

  // ───── Initialization ─────

  Future<void> init() async {
    _data = await _storage.load();
    _ensureDefaults();
    _loading = false;
    notifyListeners();

    // Initialise Dropbox (loads saved tokens and handles web OAuth redirect).
    await dropboxService.init();
    notifyListeners();
  }

  void _ensureDefaults() {
    if (_data.lists.isEmpty) {
      _data.lists.add(TaskList(id: _uuid.v4(), name: 'My Tasks'));
    }
    if (_data.smartLists.isEmpty) {
      _data.smartLists.addAll([
        SmartList(
          id: 'smart_today',
          name: 'Today',
          iconCodePoint: Icons.today.codePoint,
          colorValue: 0xFF66BB6A,
          filter: SmartFilter.today(),
        ),
        SmartList(
          id: 'smart_upcoming',
          name: 'Upcoming',
          iconCodePoint: Icons.upcoming.codePoint,
          colorValue: 0xFF42A5F5,
          filter: SmartFilter.upcoming(),
        ),
        SmartList(
          id: 'smart_all',
          name: 'All Tasks',
          iconCodePoint: Icons.list_alt.codePoint,
          colorValue: 0xFF78909C,
          filter: SmartFilter.all(),
        ),
      ]);
    }
  }

  Future<void> _save() async {
    _data.lastModified = DateTime.now();
    notifyListeners();
    await _storage.save(_data);
  }

  // ───── Tasks ─────

  List<Task> tasksForList(String listId) =>
      _data.tasks.where((t) => t.listId == listId).toList();

  Task? taskById(String id) {
    try {
      return _data.tasks.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> addTask(Task task) async {
    _data.tasks.add(task);
    await _save();
  }

  Future<void> updateTask(Task task) async {
    final i = _data.tasks.indexWhere((t) => t.id == task.id);
    if (i >= 0) _data.tasks[i] = task;
    await _save();
  }

  Future<void> updateTasks(List<Task> tasks) async {
    for (final task in tasks) {
      final i = _data.tasks.indexWhere((t) => t.id == task.id);
      if (i >= 0) _data.tasks[i] = task;
    }
    await _save();
  }

  Future<void> deleteTask(String id) async {
    _data.tasks.removeWhere((t) => t.id == id);
    await _save();
  }

  Future<void> toggleTask(Task task, {DateTime? onDate}) async {
    if (task.recurrence != null && onDate != null) {
      final d = DateTime(onDate.year, onDate.month, onDate.day);
      if (task.isCompletedOn(d)) {
        task.completedDates.removeWhere(
          (c) => c.year == d.year && c.month == d.month && c.day == d.day,
        );
      } else {
        task.completedDates.add(d);
      }
    } else {
      task.isCompleted = !task.isCompleted;
    }
    await _save();
  }

  // ───── Lists ─────

  TaskList? listById(String id) {
    try {
      return _data.lists.firstWhere((l) => l.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> addList(TaskList list) async {
    _data.lists.add(list);
    await _save();
  }

  Future<void> updateList(TaskList list) async {
    final i = _data.lists.indexWhere((l) => l.id == list.id);
    if (i >= 0) _data.lists[i] = list;
    await _save();
  }

  Future<void> deleteList(String id) async {
    _data.lists.removeWhere((l) => l.id == id);
    _data.tasks.removeWhere((t) => t.listId == id);
    await _save();
  }

  // ───── Folders ─────

  Folder? folderById(String id) {
    try {
      return _data.folders.firstWhere((f) => f.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> addFolder(Folder folder) async {
    _data.folders.add(folder);
    await _save();
  }

  Future<void> updateFolder(Folder folder) async {
    final i = _data.folders.indexWhere((f) => f.id == folder.id);
    if (i >= 0) _data.folders[i] = folder;
    await _save();
  }

  Future<void> deleteFolder(String id) async {
    for (final list in _data.lists) {
      if (list.folderId == id) list.folderId = null;
    }
    _data.folders.removeWhere((f) => f.id == id);
    await _save();
  }

  // ───── Tags ─────

  Tag? tagById(String id) {
    try {
      return _data.tags.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> addTag(Tag tag) async {
    _data.tags.add(tag);
    await _save();
  }

  Future<void> updateTag(Tag tag) async {
    final i = _data.tags.indexWhere((t) => t.id == tag.id);
    if (i >= 0) _data.tags[i] = tag;
    await _save();
  }

  Future<void> deleteTag(String id) async {
    for (final task in _data.tasks) {
      task.tagIds.remove(id);
    }
    _data.tags.removeWhere((t) => t.id == id);
    await _save();
  }

  // ───── Smart Lists ─────

  SmartList? smartListById(String id) {
    try {
      return _data.smartLists.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> addSmartList(SmartList smartList) async {
    _data.smartLists.add(smartList);
    await _save();
  }

  Future<void> updateSmartList(SmartList smartList) async {
    final i = _data.smartLists.indexWhere((s) => s.id == smartList.id);
    if (i >= 0) _data.smartLists[i] = smartList;
    await _save();
  }

  Future<void> deleteSmartList(String id) async {
    _data.smartLists.removeWhere((s) => s.id == id);
    await _save();
  }

  // ───── Sync ─────

  Future<void> signIn() async {
    await dropboxService.signIn();
  }

  Future<void> signOut() async {
    await dropboxService.signOut();
    notifyListeners();
  }

  Future<void> sync() async {
    if (!dropboxService.isSignedIn) return;
    _syncing = true;
    notifyListeners();

    try {
      final remote = await dropboxService.download();
      if (remote != null && remote.lastModified.isAfter(_data.lastModified)) {
        // Remote is newer – use it.
        _data = remote;
        _ensureDefaults();
        await _storage.save(_data);
      } else {
        // Local is newer (or no remote) – upload.
        await dropboxService.upload(_data);
      }
    } catch (e) {
      debugPrint('Sync error: $e');
    }

    _syncing = false;
    notifyListeners();
  }

  Future<void> forceUpload() async {
    if (!dropboxService.isSignedIn) return;
    _syncing = true;
    notifyListeners();
    try {
      await dropboxService.upload(_data);
    } catch (e) {
      debugPrint('Upload error: $e');
    }
    _syncing = false;
    notifyListeners();
  }

  Future<void> forceDownload() async {
    if (!dropboxService.isSignedIn) return;
    _syncing = true;
    notifyListeners();
    try {
      final remote = await dropboxService.download();
      if (remote != null) {
        _data = remote;
        _ensureDefaults();
        await _storage.save(_data);
      }
    } catch (e) {
      debugPrint('Download error: $e');
    }
    _syncing = false;
    notifyListeners();
  }

  String newId() => _uuid.v4();
}
