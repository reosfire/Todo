import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../models/task_list.dart';
import '../models/folder.dart';
import '../services/storage_service.dart';
import 'task_list_view.dart';
import 'smart_list_view.dart';
import 'list_editor_dialog.dart';
import 'folder_editor_dialog.dart';
import 'smart_list_editor_dialog.dart';
import 'tag_manager_dialog.dart';
import 'sync_settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _selectedListId;
  String? _selectedSmartListId;
  Set<String> _expandedFolderIds = {};
  final _storageService = StorageService();

  @override
  void initState() {
    super.initState();
    _loadExpandedFolders();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = context.read<AppState>();
      if (state.lists.isNotEmpty && _selectedListId == null) {
        setState(() => _selectedListId = state.lists.first.id);
      }
    });
  }

  Future<void> _loadExpandedFolders() async {
    final ids = await _storageService.loadExpandedFolderIds();
    setState(() => _expandedFolderIds = ids);
  }

  Future<void> _saveExpandedFolders() async {
    await _storageService.saveExpandedFolderIds(_expandedFolderIds);
  }

  void _selectList(String id) {
    setState(() {
      _selectedListId = id;
      _selectedSmartListId = null;
    });
    if (_isNarrow) Navigator.pop(context);
  }

  void _selectSmartList(String id) {
    setState(() {
      _selectedSmartListId = id;
      _selectedListId = null;
    });
    if (_isNarrow) Navigator.pop(context);
  }

  bool get _isNarrow => MediaQuery.of(context).size.width < 600;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (state.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Auto‑select first list.
    if (_selectedListId == null &&
        _selectedSmartListId == null &&
        state.lists.isNotEmpty) {
      _selectedListId = state.lists.first.id;
    }

    final drawer = _buildDrawer(state);
    final body = _buildBody(state);

    if (_isNarrow) {
      return Scaffold(
        appBar: _buildAppBar(state),
        drawer: Drawer(child: drawer),
        body: body,
      );
    }

    return Scaffold(
      body: Row(
        children: [
          SizedBox(width: 280, child: drawer),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                _buildWideAppBar(state),
                Expanded(child: body),
              ],
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(AppState state) {
    String title = 'Todo';
    if (_selectedSmartListId != null) {
      title = state.smartListById(_selectedSmartListId!)?.name ?? 'Todo';
    } else if (_selectedListId != null) {
      title = state.listById(_selectedListId!)?.name ?? 'Todo';
    }
    return AppBar(
      title: Text(title),
      actions: [
        if (state.syncing)
          const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (state.isSignedIn)
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: () => state.sync(),
            tooltip: 'Sync',
          ),
      ],
    );
  }

  Widget _buildWideAppBar(AppState state) {
    String title = 'Todo';
    if (_selectedSmartListId != null) {
      title = state.smartListById(_selectedSmartListId!)?.name ?? 'Todo';
    } else if (_selectedListId != null) {
      title = state.listById(_selectedListId!)?.name ?? 'Todo';
    }
    return Container(
      height: 56,
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          if (state.syncing)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (state.isSignedIn)
            IconButton(
              icon: const Icon(Icons.sync),
              onPressed: () => state.sync(),
              tooltip: 'Sync',
            ),
        ],
      ),
    );
  }

  Widget _buildDrawer(AppState state) {
    return SafeArea(
      child: Column(
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Todo',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                if (state.isSignedIn)
                  Text(
                    'Syncing with Dropbox',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                // Smart lists
                const _SectionHeader('SMART LISTS'),
                ...state.smartLists.map(
                  (sl) => ListTile(
                    leading: Icon(sl.icon, color: sl.color),
                    title: Text(sl.name),
                    selected: _selectedSmartListId == sl.id,
                    onTap: () => _selectSmartList(sl.id),
                    dense: true,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.add, size: 20),
                  title: const Text('Add Smart List'),
                  dense: true,
                  onTap: () => _showSmartListEditor(context, state),
                ),
                const Divider(),

                // Folders and lists
                const _SectionHeader('LISTS'),
                ..._buildFolderAndListItems(state),
                ListTile(
                  leading: const Icon(Icons.add, size: 20),
                  title: const Text('Add List'),
                  dense: true,
                  onTap: () => _showListEditor(context, state, null),
                ),
                ListTile(
                  leading: const Icon(
                    Icons.create_new_folder_outlined,
                    size: 20,
                  ),
                  title: const Text('Add Folder'),
                  dense: true,
                  onTap: () => _showFolderEditor(context, state, null),
                ),
                const Divider(),

                // Bottom actions
                ListTile(
                  leading: const Icon(Icons.label_outline, size: 20),
                  title: const Text('Manage Tags'),
                  dense: true,
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (_) => const TagManagerDialog(),
                    );
                  },
                ),
                ListTile(
                  leading: Icon(
                    state.isSignedIn ? Icons.cloud_done : Icons.cloud_off,
                    size: 20,
                  ),
                  title: Text(state.isSignedIn ? 'Sync Settings' : 'Sign In'),
                  dense: true,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SyncSettingsPage(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildFolderAndListItems(AppState state) {
    // Lists not in any folder, sorted by order
    final orphanLists = state.lists.where((l) => l.folderId == null).toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    // Folders sorted by order
    final sortedFolders = state.folders.toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    // Build orphan list widgets with keys for reordering
    final orphanWidgets = orphanLists
        .map(
          (list) =>
              _buildListTile(state, list, key: ValueKey('list_${list.id}')),
        )
        .toList();

    // Build folder widgets with keys
    final folderWidgets = sortedFolders.map((folder) {
      final folderLists =
          state.lists.where((l) => l.folderId == folder.id).toList()
            ..sort((a, b) => a.order.compareTo(b.order));

      final folderListCount = state.tasks
          .where(
            (t) => folderLists.any((l) => l.id == t.listId) && !t.isCompleted,
          )
          .length;

      return _HoverTrailingTile(
        key: ValueKey('folder_${folder.id}'),
        child: (isHovered) => ExpansionTile(
          initiallyExpanded: _expandedFolderIds.contains(folder.id),
          onExpansionChanged: (expanded) {
            setState(() {
              if (expanded) {
                _expandedFolderIds.add(folder.id);
              } else {
                _expandedFolderIds.remove(folder.id);
              }
            });
            _saveExpandedFolders();
          },
          leading: const Icon(Icons.folder_outlined, size: 20),
          title: Text(folder.name),
          dense: true,
          shape: const Border(),
          collapsedShape: const Border(),
          trailing: SizedBox(
            width: 32,
            child: isHovered
                ? IconButton(
                    icon: const Icon(Icons.more_horiz, size: 18),
                    onPressed: () => _showFolderMenu(context, state, folder),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    visualDensity: VisualDensity.compact,
                  )
                : folderListCount > 0
                ? Text(
                    '$folderListCount',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  )
                : const SizedBox.shrink(),
          ),
          children: [
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorder: (oldIndex, newIndex) {
                _reorderListsInFolder(
                  state,
                  folder.id,
                  folderLists,
                  oldIndex,
                  newIndex,
                );
              },
              children: folderLists.asMap().entries.map((e) {
                return ReorderableDragStartListener(
                  key: ValueKey('list_${e.value.id}_in_folder'),
                  index: e.key,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: _buildListTile(state, e.value),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      );
    }).toList();

    // Combine into ReorderableListView
    return [
      ReorderableListView(
        key: const ValueKey('reorderable_folders_lists'),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        onReorder: (oldIndex, newIndex) {
          _reorderFoldersAndLists(
            state,
            orphanLists,
            sortedFolders,
            oldIndex,
            newIndex,
          );
        },
        children: [
          ...orphanWidgets.asMap().entries.map(
            (e) => ReorderableDragStartListener(
              key: e.value.key!,
              index: e.key,
              child: e.value,
            ),
          ),
          ...folderWidgets.asMap().entries.map(
            (e) => ReorderableDragStartListener(
              key: e.value.key!,
              index: orphanWidgets.length + e.key,
              child: e.value,
            ),
          ),
        ],
      ),
    ];
  }

  void _reorderFoldersAndLists(
    AppState state,
    List<TaskList> orphanLists,
    List<Folder> folders,
    int oldIndex,
    int newIndex,
  ) {
    // Create combined list of items
    final items = <dynamic>[...orphanLists, ...folders];

    // Perform reorder
    if (oldIndex < newIndex) newIndex--;
    final item = items.removeAt(oldIndex);
    items.insert(newIndex, item);

    // Split back into lists and folders
    final reorderedOrphanLists = <TaskList>[];
    final reorderedFolders = <Folder>[];

    for (final item in items) {
      if (item is TaskList) {
        reorderedOrphanLists.add(item);
      } else if (item is Folder) {
        reorderedFolders.add(item);
      }
    }

    // Update state
    state.reorderLists(reorderedOrphanLists);
    state.reorderFolders(reorderedFolders);
  }

  void _reorderListsInFolder(
    AppState state,
    String folderId,
    List<TaskList> folderLists,
    int oldIndex,
    int newIndex,
  ) {
    // Perform reorder
    if (oldIndex < newIndex) newIndex--;
    final item = folderLists.removeAt(oldIndex);
    folderLists.insert(newIndex, item);

    // Update state with reordered lists in this folder
    state.reorderLists(folderLists);
  }

  Widget _buildListTile(AppState state, TaskList list, {Key? key}) {
    final count = state.tasks
        .where((t) => t.listId == list.id && !t.isCompleted)
        .length;
    return _HoverTrailingTile(
      key: key,
      child: (isHovered) => ListTile(
        leading: Icon(Icons.list, color: list.color, size: 20),
        title: Text(list.name),
        trailing: SizedBox(
          width: 32,
          child: isHovered
              ? IconButton(
                  icon: const Icon(Icons.more_horiz, size: 18),
                  onPressed: () => _showListMenu(context, state, list),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                )
              : count > 0
              ? Text(
                  '$count',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                )
              : const SizedBox.shrink(),
        ),
        selected: _selectedListId == list.id,
        dense: true,
        onTap: () => _selectList(list.id),
        onLongPress: () => _showListMenu(context, state, list),
      ),
    );
  }

  Widget _buildBody(AppState state) {
    if (_selectedSmartListId != null) {
      final sl = state.smartListById(_selectedSmartListId!);
      if (sl != null) return SmartListView(smartList: sl);
    }
    if (_selectedListId != null) {
      return TaskListView(listId: _selectedListId!);
    }
    return const Center(child: Text('Select a list'));
  }

  // ───── Dialogs ─────

  void _showListEditor(BuildContext ctx, AppState state, TaskList? list) {
    showDialog(
      context: ctx,
      builder: (_) => ListEditorDialog(taskList: list),
    );
  }

  void _showFolderEditor(BuildContext ctx, AppState state, Folder? folder) {
    showDialog(
      context: ctx,
      builder: (_) => FolderEditorDialog(folder: folder),
    );
  }

  void _showSmartListEditor(BuildContext ctx, AppState state) {
    showDialog(context: ctx, builder: (_) => const SmartListEditorDialog());
  }

  void _showListMenu(BuildContext ctx, AppState state, TaskList list) {
    showModalBottomSheet(
      context: ctx,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Edit'),
              onTap: () {
                Navigator.pop(ctx);
                _showListEditor(ctx, state, list);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                state.deleteList(list.id);
                if (_selectedListId == list.id) {
                  setState(() {
                    _selectedListId = state.lists.isNotEmpty
                        ? state.lists.first.id
                        : null;
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showFolderMenu(BuildContext ctx, AppState state, Folder folder) {
    showModalBottomSheet(
      context: ctx,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Rename'),
              onTap: () {
                Navigator.pop(ctx);
                _showFolderEditor(ctx, state, folder);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                state.deleteFolder(folder.id);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _HoverTrailingTile extends StatefulWidget {
  final Widget Function(bool isHovered) child;
  const _HoverTrailingTile({super.key, required this.child});

  @override
  State<_HoverTrailingTile> createState() => _HoverTrailingTileState();
}

class _HoverTrailingTileState extends State<_HoverTrailingTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: widget.child(_isHovered),
    );
  }
}
