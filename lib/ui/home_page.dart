import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../models/task_list.dart';
import '../models/folder.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = context.read<AppState>();
      if (state.lists.isNotEmpty && _selectedListId == null) {
        setState(() => _selectedListId = state.lists.first.id);
      }
    });
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
            onPressed: () => state.syncWithDrive(),
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
              onPressed: () => state.syncWithDrive(),
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
                Text('Todo',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onPrimaryContainer,
                        )),
                if (state.isSignedIn)
                  Text(state.userEmail ?? '',
                      style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                // Smart lists
                const _SectionHeader('SMART LISTS'),
                ...state.smartLists.map((sl) => ListTile(
                      leading: Icon(sl.icon, color: sl.color),
                      title: Text(sl.name),
                      selected: _selectedSmartListId == sl.id,
                      onTap: () => _selectSmartList(sl.id),
                      dense: true,
                    )),
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
                  leading: const Icon(Icons.create_new_folder_outlined, size: 20),
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
    final widgets = <Widget>[];

    // Lists not in any folder
    final orphanLists =
        state.lists.where((l) => l.folderId == null).toList();
    for (final list in orphanLists) {
      widgets.add(_buildListTile(state, list));
    }

    // Folders with their lists
    for (final folder in state.folders) {
      widgets.add(
        ExpansionTile(
          leading: const Icon(Icons.folder_outlined, size: 20),
          title: Text(folder.name),
          dense: true,
          trailing: IconButton(
            icon: const Icon(Icons.more_vert, size: 18),
            onPressed: () => _showFolderMenu(context, state, folder),
          ),
          children: state.lists
              .where((l) => l.folderId == folder.id)
              .map((l) => Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: _buildListTile(state, l),
                  ))
              .toList(),
        ),
      );
    }

    return widgets;
  }

  Widget _buildListTile(AppState state, TaskList list) {
    final count =
        state.tasks.where((t) => t.listId == list.id && !t.isCompleted).length;
    return ListTile(
      leading: Icon(list.icon, color: list.color, size: 20),
      title: Text(list.name),
      trailing: count > 0
          ? Text('$count', style: Theme.of(context).textTheme.bodySmall)
          : null,
      selected: _selectedListId == list.id,
      dense: true,
      onTap: () => _selectList(list.id),
      onLongPress: () => _showListMenu(context, state, list),
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
    showDialog(
      context: ctx,
      builder: (_) => const SmartListEditorDialog(),
    );
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
                    _selectedListId =
                        state.lists.isNotEmpty ? state.lists.first.id : null;
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
