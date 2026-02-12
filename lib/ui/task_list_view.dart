import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/task.dart';
import '../state/app_state.dart';
import 'task_editor_dialog.dart';

class TaskListView extends StatefulWidget {
  final String listId;
  const TaskListView({super.key, required this.listId});

  @override
  State<TaskListView> createState() => _TaskListViewState();
}

class _TaskListViewState extends State<TaskListView> {
  final TextEditingController _newTaskController = TextEditingController();
  final FocusNode _newTaskFocus = FocusNode();

  @override
  void dispose() {
    _newTaskController.dispose();
    _newTaskFocus.dispose();
    super.dispose();
  }

  void _addTask(AppState state) {
    final title = _newTaskController.text.trim();
    if (title.isEmpty) return;

    final existingTasks = state.tasksForList(widget.listId);
    final maxOrder = existingTasks.isEmpty
        ? 0
        : existingTasks.map((t) => t.order).reduce((a, b) => a > b ? a : b);

    final task = Task(
      id: state.newId(),
      title: title,
      createdAt: DateTime.now(),
      listId: widget.listId,
      order: maxOrder + 1,
    );
    state.addTask(task);
    _newTaskController.clear();
    _newTaskFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final tasks = state.tasksForList(widget.listId);
    final pending = tasks.where((t) => !t.isCompleted).toList()
      ..sort((a, b) => b.order.compareTo(a.order));
    final completed = tasks.where((t) => t.isCompleted).toList()
      ..sort((a, b) => b.order.compareTo(a.order));

    return Scaffold(
      body: Column(
        children: [
          // Add task input at the top
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newTaskController,
                    focusNode: _newTaskFocus,
                    decoration: InputDecoration(
                      hintText: 'Add a task...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) => _addTask(state),
                    textInputAction: TextInputAction.done,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: () => _addTask(state),
                    child: const Text('Add'),
                  ),
                ),
              ],
            ),
          ),
          // Task list
          Expanded(
            child: tasks.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 64,
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No tasks yet',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  )
                : ReorderableListView(
                    padding: const EdgeInsets.only(bottom: 16),
                    buildDefaultDragHandles: false,
                    onReorder: (oldIndex, newIndex) {
                      _reorderTasks(
                        state,
                        pending,
                        completed,
                        oldIndex,
                        newIndex,
                      );
                    },
                    children: [
                      ...pending.asMap().entries.map(
                        (e) => _TaskTile(
                          key: ValueKey(e.value.id),
                          task: e.value,
                          index: e.key,
                        ),
                      ),
                      if (completed.isNotEmpty) ...[
                        Padding(
                          key: const ValueKey('completed_header'),
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                          child: const Text(
                            'Completed',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        ...completed.asMap().entries.map(
                          (e) => _TaskTile(
                            key: ValueKey(e.value.id),
                            task: e.value,
                            index: pending.length + e.key,
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  void _reorderTasks(
    AppState state,
    List<Task> pending,
    List<Task> completed,
    int oldIndex,
    int newIndex,
  ) {
    // Don't allow reordering between pending and completed sections
    if (oldIndex >= pending.length && newIndex < pending.length) return;
    if (oldIndex < pending.length && newIndex >= pending.length) return;

    final allTasks = [...pending, ...completed];
    if (oldIndex < newIndex) newIndex--;
    final task = allTasks.removeAt(oldIndex);
    allTasks.insert(newIndex, task);

    // Update order field for all affected tasks by creating new Task instances
    final updatedTasks = <Task>[];
    for (var i = 0; i < allTasks.length; i++) {
      final t = allTasks[i];
      updatedTasks.add(
        Task(
          id: t.id,
          title: t.title,
          notes: t.notes,
          isCompleted: t.isCompleted,
          createdAt: t.createdAt,
          scheduledDate: t.scheduledDate,
          recurrence: t.recurrence,
          tagIds: t.tagIds,
          listId: t.listId,
          order: i,
          completedDates: t.completedDates,
        ),
      );
    }
    state.updateTasks(updatedTasks);
  }
}

class _TaskTile extends StatefulWidget {
  final Task task;
  final int index;
  const _TaskTile({
    required super.key,
    required this.task,
    required this.index,
  });

  @override
  State<_TaskTile> createState() => _TaskTileState();
}

class _TaskTileState extends State<_TaskTile> {
  bool _isEditing = false;
  late TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.task.title);
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && _isEditing) {
        _saveTitle();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _startEditing() {
    setState(() => _isEditing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  void _saveTitle() {
    if (!mounted) return;

    _focusNode.unfocus();

    final state = context.read<AppState>();
    final newTitle = _controller.text.trim();
    if (newTitle.isNotEmpty && newTitle != widget.task.title) {
      final updated = Task(
        id: widget.task.id,
        title: newTitle,
        notes: widget.task.notes,
        isCompleted: widget.task.isCompleted,
        createdAt: widget.task.createdAt,
        scheduledDate: widget.task.scheduledDate,
        recurrence: widget.task.recurrence,
        tagIds: widget.task.tagIds,
        listId: widget.task.listId,
        order: widget.task.order,
        completedDates: widget.task.completedDates,
      );
      state.updateTask(updated);
    }
    if (mounted) {
      setState(() => _isEditing = false);
    }
  }

  void _showEditDialog(BuildContext context, Offset position) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.transparent,
      pageBuilder: (context, animation, secondaryAnimation) {
        return TaskEditorDialog(
          listId: widget.task.listId,
          existingTask: widget.task,
          clickPosition: position,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final isRecurring = widget.task.recurrence != null;
    final completed = widget.task.isCompleted;

    return Dismissible(
      key: ValueKey(widget.task.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => state.deleteTask(widget.task.id),
      child: Listener(
        onPointerDown: (event) {
          if (event.buttons == 2) {
            // Right mouse button - show dialog
            _showEditDialog(context, event.position);
          }
        },
        child: GestureDetector(
          onSecondaryTapDown: (details) {
            // Prevents default context menu
          },
          onSecondaryTap: () {},
          behavior: HitTestBehavior.opaque,
          child: ListTile(
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ReorderableDragStartListener(
                  index: widget.index,
                  child: Icon(
                    Icons.drag_handle_rounded,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(width: 4),
                Checkbox(
                  value: completed,
                  onChanged: (_) => state.toggleTask(widget.task),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
            title: _isEditing
                ? TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    style: Theme.of(context).textTheme.bodyLarge,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onSubmitted: (_) => _saveTitle(),
                    onTapOutside: (_) => _saveTitle(),
                  )
                : Text(
                    widget.task.title,
                    style: TextStyle(
                      decoration: completed ? TextDecoration.lineThrough : null,
                      color: completed
                          ? Theme.of(context).colorScheme.onSurfaceVariant
                          : null,
                    ),
                  ),
            subtitle: _buildSubtitle(context),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.task.scheduledDate != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      DateFormat.MMMd().format(widget.task.scheduledDate!),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                if (isRecurring)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      Icons.repeat,
                      size: 20,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                IconButton(
                  icon: Icon(
                    Icons.more_horiz,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  onPressed: () {
                    final RenderBox button =
                        context.findRenderObject() as RenderBox;
                    final Offset buttonPosition = button.localToGlobal(
                      Offset.zero,
                    );
                    _showEditDialog(
                      context,
                      Offset(
                        buttonPosition.dx,
                        buttonPosition.dy + button.size.height,
                      ),
                    );
                  },
                ),
              ],
            ),
            onTap: () {
              if (!_isEditing) _startEditing();
            },
          ),
        ),
      ),
    );
  }

  Widget? _buildSubtitle(BuildContext context) {
    final state = context.read<AppState>();
    final parts = <Widget>[];

    final tagWidgets = widget.task.tagIds
        .map((id) => state.tagById(id))
        .where((t) => t != null)
        .map(
          (t) => Container(
            margin: const EdgeInsets.only(right: 4),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: t!.color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(t.name, style: TextStyle(fontSize: 11, color: t.color)),
          ),
        )
        .toList();

    if (tagWidgets.isNotEmpty) {
      parts.add(Row(mainAxisSize: MainAxisSize.min, children: tagWidgets));
    }

    if (parts.isEmpty) return null;
    return Wrap(spacing: 8, children: parts);
  }
}
