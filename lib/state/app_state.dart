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
    // Remove legacy default smart lists (now replaced by built-in ones).
    removeLegacySmartLists(_data.smartLists);
  }

  Future<void> _save() async {
    _data.lastModified = DateTime.now();
    notifyListeners();
    await _storage.save(_data);
  }

  // ───── Tasks ─────

  List<Task> tasksForList(String listId) =>
      _data.tasks.where((t) => t.listId == listId).toList();

  /// Get tasks for a list in their linked-list order.
  /// [completedSection] determines whether to return completed or pending tasks.
  List<Task> tasksForListOrdered(String listId, {required bool completedSection}) {
    final allTasks = tasksForList(listId)
        .where((t) => t.isCompleted == completedSection)
        .toList();
    
    if (allTasks.isEmpty) return [];
    
    // Build a map for quick lookup.
    final taskMap = {for (var t in allTasks) t.id: t};
    
    // Find the head (first task with no previous).
    Task? head;
    for (var task in allTasks) {
      if (task.previousTaskId == null || 
          !taskMap.containsKey(task.previousTaskId)) {
        head = task;
        break;
      }
    }
    
    // If no clear head found (e.g., cycle or orphaned tasks), fall back to creation time.
    if (head == null) {
      return allTasks..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    
    // Traverse the linked list from head.
    final ordered = <Task>[];
    Task? current = head;
    final visited = <String>{};
    
    while (current != null && !visited.contains(current.id)) {
      ordered.add(current);
      visited.add(current.id);
      
      final nextId = current.nextTaskId;
      if (nextId == null || !taskMap.containsKey(nextId)) break;
      current = taskMap[nextId]!;
    }
    
    // Include any orphaned tasks at the end (tasks not in the chain).
    for (var task in allTasks) {
      if (!visited.contains(task.id)) {
        ordered.add(task);
      }
    }
    
    return ordered;
  }

  /// Rebuild the linked list for a set of tasks based on their order in the list.
  /// This is simpler than trying to surgically update pointers during reorder.
  Future<void> rebuildLinkedListForTasks(List<Task> orderedTasks) async {
    if (orderedTasks.isEmpty) return;
    
    final updates = <Task>[];
    
    for (var i = 0; i < orderedTasks.length; i++) {
      final task = orderedTasks[i];
      final prevId = i > 0 ? orderedTasks[i - 1].id : null;
      final nextId = i < orderedTasks.length - 1 ? orderedTasks[i + 1].id : null;
      
      // Only update if the pointers actually changed
      if (task.previousTaskId != prevId || task.nextTaskId != nextId) {
        updates.add(copyTask(
          task,
          previousTaskId: prevId,
          nextTaskId: nextId,
        ));
      }
    }
    
    if (updates.isNotEmpty) {
      await updateTasks(updates);
    }
  }

  /// Reorder a task by updating its position in the linked list.
  /// [task] is the task to move.
  /// [newPrevious] is the task that should come before it (null = move to head).
  /// [newNext] is the task that should come after it (null = move to tail).
  Future<void> reorderTask(Task task, Task? newPrevious, Task? newNext) async {
    // Track which tasks need updates and what their new links should be.
    final taskUpdates = <String, ({String? prev, String? next})>{};
    
    // 1. Remove task from its current position.
    final oldPrev = task.previousTaskId != null 
        ? taskById(task.previousTaskId!) 
        : null;
    final oldNext = task.nextTaskId != null 
        ? taskById(task.nextTaskId!) 
        : null;
    
    // Unlink old neighbors from the moved task.
    if (oldPrev != null) {
      taskUpdates[oldPrev.id] = (
        prev: oldPrev.previousTaskId,
        next: oldNext?.id,
      );
    }
    if (oldNext != null) {
      taskUpdates[oldNext.id] = (
        prev: oldPrev?.id,
        next: oldNext.nextTaskId,
      );
    }
    
    // 2. Insert task at new position.
    taskUpdates[task.id] = (
      prev: newPrevious?.id,
      next: newNext?.id,
    );
    
    // Link new neighbors to the moved task.
    if (newPrevious != null) {
      // If newPrevious was already updated (e.g., it was oldNext), merge the updates.
      final existing = taskUpdates[newPrevious.id];
      taskUpdates[newPrevious.id] = (
        prev: existing?.prev ?? newPrevious.previousTaskId,
        next: task.id,
      );
    }
    if (newNext != null) {
      final existing = taskUpdates[newNext.id];
      taskUpdates[newNext.id] = (
        prev: task.id,
        next: existing?.next ?? newNext.nextTaskId,
      );
    }
    
    // Build final task updates from the map.
    final updates = <Task>[];
    for (final entry in taskUpdates.entries) {
      final originalTask = taskById(entry.key);
      if (originalTask == null) continue;
      
      updates.add(copyTask(
        originalTask,
        previousTaskId: entry.value.prev,
        nextTaskId: entry.value.next,
      ));
    }
    
    await updateTasks(updates);
  }

  /// Helper to create a copy of a task with updated link pointers.
  Task copyTask(
    Task task, {
    required String? previousTaskId,
    required String? nextTaskId,
  }) {
    return Task(
      id: task.id,
      title: task.title,
      notes: task.notes,
      isCompleted: task.isCompleted,
      createdAt: task.createdAt,
      scheduledDate: task.scheduledDate,
      recurrence: task.recurrence,
      tagIds: task.tagIds,
      listId: task.listId,
      previousTaskId: previousTaskId,
      nextTaskId: nextTaskId,
      completedDates: task.completedDates,
    );
  }

  /// Add a new task to the head of its list's linked list chain.
  /// This atomically adds the task and updates the old head if there is one.
  Future<void> addTaskAsHead(Task newTask) async {
    final updates = <Task>[newTask];
    
    // Find current head and update it to point back to new task.
    final pendingTasks = tasksForListOrdered(
      newTask.listId,
      completedSection: newTask.isCompleted,
    );
    
    if (pendingTasks.isNotEmpty) {
      final oldHead = pendingTasks.first;
      updates.add(copyTask(
        oldHead,
        previousTaskId: newTask.id,
        nextTaskId: oldHead.nextTaskId, // Preserve the old next link
      ));
    }
    
    // Add to internal list and batch save/sync.
    _data.tasks.add(newTask);
    for (final task in updates.skip(1)) {
      final i = _data.tasks.indexWhere((t) => t.id == task.id);
      if (i >= 0) _data.tasks[i] = task;
    }
    
    await _save();
    
    for (final task in updates) {
      _syncService.pushEntity('tasks', task.id, task.toJson());
    }
  }

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
      await _save();
      _syncService.pushEntity('tasks', task.id, task.toJson());
    } else {
      // For non-recurring tasks, toggle moves the task between sections.
      // We need to properly move it in the linked list.
      await _toggleTaskWithReorder(task);
    }
  }

  /// Toggle a task's completion status and move it to the head of the new section.
  Future<void> _toggleTaskWithReorder(Task task) async {
    final updates = <Task>[];
    
    // 1. Remove task from its current section's linked list.
    final oldPrev = task.previousTaskId != null ? taskById(task.previousTaskId!) : null;
    final oldNext = task.nextTaskId != null ? taskById(task.nextTaskId!) : null;
    
    if (oldPrev != null) {
      updates.add(copyTask(
        oldPrev,
        previousTaskId: oldPrev.previousTaskId,
        nextTaskId: oldNext?.id,
      ));
    }
    if (oldNext != null) {
      updates.add(copyTask(
        oldNext,
        previousTaskId: oldPrev?.id,
        nextTaskId: oldNext.nextTaskId,
      ));
    }
    
    // 2. Toggle completion status.
    final newCompletedStatus = !task.isCompleted;
    
    // 3. Find the head of the new section.
    final newSectionTasks = tasksForListOrdered(
      task.listId,
      completedSection: newCompletedStatus,
    );
    final newSectionHead = newSectionTasks.isNotEmpty ? newSectionTasks.first : null;
    
    // 4. Insert task at the head of the new section.
    final updatedTask = copyTask(
      task,
      previousTaskId: null,
      nextTaskId: newSectionHead?.id,
    );
    updatedTask.isCompleted = newCompletedStatus;
    updates.add(updatedTask);
    
    // 5. Update the old head of the new section to point back.
    if (newSectionHead != null) {
      updates.add(copyTask(
        newSectionHead,
        previousTaskId: task.id,
        nextTaskId: newSectionHead.nextTaskId,
      ));
    }
    
    // Apply all updates atomically.
    for (final update in updates) {
      final i = _data.tasks.indexWhere((t) => t.id == update.id);
      if (i >= 0) _data.tasks[i] = update;
    }
    
    await _save();
    
    for (final update in updates) {
      _syncService.pushEntity('tasks', update.id, update.toJson());
    }
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
    // Check built-in smart lists first.
    for (final sl in builtInSmartLists) {
      if (sl.id == id) return sl;
    }
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
