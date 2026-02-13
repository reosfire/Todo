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

  void _addTask(AppState state) async {
    final title = _newTaskController.text.trim();
    if (title.isEmpty) return;

    // Find the current head of pending tasks to set nextTaskId.
    final pendingTasks = state.tasksForListOrdered(
      widget.listId,
      completedSection: false,
    );
    final currentHead = pendingTasks.isNotEmpty ? pendingTasks.first : null;

    // Create new task as the new head.
    final newTask = Task(
      id: state.newId(),
      title: title,
      createdAt: DateTime.now(),
      listId: widget.listId,
      previousTaskId: null,
      nextTaskId: currentHead?.id,
    );
    
    // Add atomically with linked list update.
    await state.addTaskAsHead(newTask);
    
    _newTaskController.clear();
    _newTaskFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final pending = state.tasksForListOrdered(
      widget.listId,
      completedSection: false,
    );
    final completed = state.tasksForListOrdered(
      widget.listId,
      completedSection: true,
    );

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
            child: pending.isEmpty && completed.isEmpty
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
                : ListView(
                    padding: const EdgeInsets.only(bottom: 16),
                    children: [
                      if (pending.isNotEmpty)
                        ReorderableListView(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          buildDefaultDragHandles: false,
                          onReorder: (oldIndex, newIndex) {
                            _reorderTasksInSection(state, pending, oldIndex, newIndex);
                          },
                          children: pending.map(
                            (task) => _TaskTile(
                              key: ValueKey(task.id),
                              task: task,
                              index: pending.indexOf(task),
                            ),
                          ).toList(),
                        ),
                      if (completed.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                          child: Text(
                            'Completed',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        ReorderableListView(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          buildDefaultDragHandles: false,
                          onReorder: (oldIndex, newIndex) {
                            _reorderTasksInSection(state, completed, oldIndex, newIndex);
                          },
                          children: completed.map(
                            (task) => _TaskTile(
                              key: ValueKey(task.id),
                              task: task,
                              index: completed.indexOf(task),
                            ),
                          ).toList(),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  void _reorderTasksInSection(
    AppState state,
    List<Task> section,
    int oldIndex,
    int newIndex,
  ) {
    // Apply standard ReorderableListView adjustment
    if (oldIndex < newIndex) newIndex--;
    
    // Simulate the reorder
    final reordered = List<Task>.from(section);
    final task = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, task);
    
    // Rebuild the linked list for this entire section from scratch.
    // This is simpler and more reliable than trying to surgically update pointers.
    state.rebuildLinkedListForTasks(reordered);
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
        previousTaskId: widget.task.previousTaskId,
        nextTaskId: widget.task.nextTaskId,
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
