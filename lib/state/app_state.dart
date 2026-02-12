import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:app_links/app_links.dart';
import '../models/app_data.dart';
import '../models/task.dart';
import '../models/task_list.dart';
import '../models/folder.dart';
import '../models/tag.dart';
import '../models/smart_list.dart';
import '../services/storage_service.dart';
import '../services/dropbox_service.dart';
import '../services/sync_service.dart';

const _uuid = Uuid();

class AppState extends ChangeNotifier with WidgetsBindingObserver {
  final StorageService _storage = StorageService();
  final DropboxService dropboxService = DropboxService();
  late final SyncService _syncService = SyncService(dropboxService, _storage);
  final _appLinks = AppLinks();

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
    await _syncService.init(_data);

    // Initialize deep link handling for Android/iOS OAuth redirect
    _initDeepLinks();

    // Set up callback for when remote changes arrive via longpoll.
    _syncService.onRemoteDataChanged = _onRemoteDataPulled;

    // Register lifecycle observer so we pause/resume polling.
    WidgetsBinding.instance.addObserver(this);

    // Pull latest changes from server on startup and start polling.
    if (dropboxService.isSignedIn) {
      _pullAndStartPolling();
    }

    notifyListeners();
  }

  @override
  void dispose() {
    _syncService.stopRemotePolling();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App came back to foreground – pull changes and restart polling.
      if (dropboxService.isSignedIn) {
        _pullAndStartPolling();
      }
    } else if (state == AppLifecycleState.paused) {
      // App went to background – stop the longpoll loop.
      _syncService.stopRemotePolling();
    }
  }

  /// Pull remote changes and (re)start the longpoll loop.
  Future<void> _pullAndStartPolling() async {
    // Quick pull on open.
    final changed = await _syncService.pullRemoteChanges(_data);
    if (changed) {
      _ensureDefaults();
      await _storage.save(_data);
      notifyListeners();
    }
    // Start continuous polling.
    _syncService.startRemotePolling(() => _data);
  }

  /// Called by SyncService when the longpoll loop detected and pulled changes.
  void _onRemoteDataPulled(AppData data) async {
    _ensureDefaults();
    await _storage.save(_data);
    notifyListeners();
  }

  void _initDeepLinks() async {
    // Handle initial link (when app was closed and opened via deep link)
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleIncomingLink(initialUri);
      }
    } catch (e) {
      // Handle error silently
    }

    // Listen for new links while app is running
    _appLinks.uriLinkStream.listen((uri) {
      _handleIncomingLink(uri);
    });
  }

  void _handleIncomingLink(Uri uri) async {
    if (uri.scheme == 'todoapp' && uri.host == 'auth') {
      final code = uri.queryParameters['code'];
      if (code != null) {
        final success = await dropboxService.handleRedirectCode(code);
        if (success) {
          notifyListeners();
          // Trigger initial sync after successful OAuth
          await sync();
          // Start polling for remote changes.
          _syncService.startRemotePolling(() => _data);
        }
      }
    }
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
    _syncService.pushEntity('tasks', task.id, task.toJson());
  }

  Future<void> updateTask(Task task) async {
    final i = _data.tasks.indexWhere((t) => t.id == task.id);
    if (i >= 0) _data.tasks[i] = task;
    await _save();
    _syncService.pushEntity('tasks', task.id, task.toJson());
  }

  Future<void> updateTasks(List<Task> tasks) async {
    for (final task in tasks) {
      final i = _data.tasks.indexWhere((t) => t.id == task.id);
      if (i >= 0) _data.tasks[i] = task;
    }
    await _save();
    for (final task in tasks) {
      _syncService.pushEntity('tasks', task.id, task.toJson());
    }
  }

  Future<void> deleteTask(String id) async {
    _data.tasks.removeWhere((t) => t.id == id);
    await _save();
    _syncService.pushDeletion('tasks', id);
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
    _syncService.pushEntity('tasks', task.id, task.toJson());
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
    _syncService.pushEntity('lists', list.id, list.toJson());
  }

  Future<void> updateList(TaskList list) async {
    final i = _data.lists.indexWhere((l) => l.id == list.id);
    if (i >= 0) _data.lists[i] = list;
    await _save();
    _syncService.pushEntity('lists', list.id, list.toJson());
  }

  Future<void> deleteList(String id) async {
    final taskIds = _data.tasks
        .where((t) => t.listId == id)
        .map((t) => t.id)
        .toList();
    _data.lists.removeWhere((l) => l.id == id);
    _data.tasks.removeWhere((t) => t.listId == id);
    await _save();
    _syncService.pushDeletion('lists', id);
    for (final tid in taskIds) {
      _syncService.pushDeletion('tasks', tid);
    }
  }

  Future<void> reorderLists(List<TaskList> reorderedLists) async {
    for (var i = 0; i < reorderedLists.length; i++) {
      reorderedLists[i].order = i;
      final idx = _data.lists.indexWhere((l) => l.id == reorderedLists[i].id);
      if (idx >= 0) _data.lists[idx] = reorderedLists[i];
    }
    await _save();
    for (final list in reorderedLists) {
      _syncService.pushEntity('lists', list.id, list.toJson());
    }
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
    _syncService.pushEntity('folders', folder.id, folder.toJson());
  }

  Future<void> updateFolder(Folder folder) async {
    final i = _data.folders.indexWhere((f) => f.id == folder.id);
    if (i >= 0) _data.folders[i] = folder;
    await _save();
    _syncService.pushEntity('folders', folder.id, folder.toJson());
  }

  Future<void> deleteFolder(String id) async {
    final affectedLists = _data.lists.where((l) => l.folderId == id).toList();
    for (final list in affectedLists) {
      list.folderId = null;
    }
    _data.folders.removeWhere((f) => f.id == id);
    await _save();
    _syncService.pushDeletion('folders', id);
    for (final list in affectedLists) {
      _syncService.pushEntity('lists', list.id, list.toJson());
    }
  }

  Future<void> reorderFolders(List<Folder> reorderedFolders) async {
    for (var i = 0; i < reorderedFolders.length; i++) {
      reorderedFolders[i].order = i;
      final idx = _data.folders.indexWhere(
        (f) => f.id == reorderedFolders[i].id,
      );
      if (idx >= 0) _data.folders[idx] = reorderedFolders[i];
    }
    await _save();
    for (final folder in reorderedFolders) {
      _syncService.pushEntity('folders', folder.id, folder.toJson());
    }
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
    _syncService.pushEntity('tags', tag.id, tag.toJson());
  }

  Future<void> updateTag(Tag tag) async {
    final i = _data.tags.indexWhere((t) => t.id == tag.id);
    if (i >= 0) _data.tags[i] = tag;
    await _save();
    _syncService.pushEntity('tags', tag.id, tag.toJson());
  }

  Future<void> deleteTag(String id) async {
    final affectedTasks = _data.tasks
        .where((t) => t.tagIds.contains(id))
        .toList();
    for (final task in affectedTasks) {
      task.tagIds.remove(id);
    }
    _data.tags.removeWhere((t) => t.id == id);
    await _save();
    _syncService.pushDeletion('tags', id);
    for (final task in affectedTasks) {
      _syncService.pushEntity('tasks', task.id, task.toJson());
    }
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
    _syncService.pushEntity('smart_lists', smartList.id, smartList.toJson());
  }

  Future<void> updateSmartList(SmartList smartList) async {
    final i = _data.smartLists.indexWhere((s) => s.id == smartList.id);
    if (i >= 0) _data.smartLists[i] = smartList;
    await _save();
    _syncService.pushEntity('smart_lists', smartList.id, smartList.toJson());
  }

  Future<void> deleteSmartList(String id) async {
    _data.smartLists.removeWhere((s) => s.id == id);
    await _save();
    _syncService.pushDeletion('smart_lists', id);
  }

  // ───── Sync ─────

  Future<void> signIn() async {
    await dropboxService.signIn();
  }

  Future<void> signOut() async {
    _syncService.stopRemotePolling();
    await dropboxService.signOut();
    notifyListeners();
  }

  Future<void> sync() async {
    if (!dropboxService.isSignedIn) return;
    _syncing = true;
    notifyListeners();

    try {
      _syncService.stopRemotePolling();
      _data = await _syncService.fullSync(_data);
      _ensureDefaults();
      await _storage.save(_data);
    } catch (e) {
      debugPrint('Sync error: $e');
    }

    _syncing = false;
    notifyListeners();
    // Restart polling after manual sync.
    _syncService.startRemotePolling(() => _data);
  }

  Future<void> forceUpload() async {
    if (!dropboxService.isSignedIn) return;
    _syncing = true;
    notifyListeners();
    try {
      await _syncService.forceUploadAll(_data);
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
      _data = await _syncService.forceDownloadAll();
      _ensureDefaults();
      await _storage.save(_data);
    } catch (e) {
      debugPrint('Download error: $e');
    }
    _syncing = false;
    notifyListeners();
  }

  String newId() => _uuid.v4();
}
