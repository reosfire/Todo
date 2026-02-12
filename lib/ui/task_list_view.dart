import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/task.dart';
import '../state/app_state.dart';
import 'task_editor_dialog.dart';

class TaskListView extends StatelessWidget {
  final String listId;
  const TaskListView({super.key, required this.listId});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final tasks = state.tasksForList(listId);
    final pending = tasks.where((t) => !t.isCompleted).toList()
      ..sort(_compareTasksByDate);
    final completed = tasks.where((t) => t.isCompleted).toList();

    return Scaffold(
      body: tasks.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 64,
                      color: Theme.of(context).colorScheme.outlineVariant),
                  const SizedBox(height: 12),
                  Text('No tasks yet',
                      style: Theme.of(context).textTheme.bodyLarge),
                ],
              ),
            )
          : ReorderableListView(
              padding: const EdgeInsets.only(bottom: 80),
              buildDefaultDragHandles: false,
              onReorder: (oldIndex, newIndex) {
                _reorderTasks(state, pending, completed, oldIndex, newIndex);
              },
              children: [
                ...pending.map((t) => _TaskTile(key: ValueKey(t.id), task: t)),
                if (completed.isNotEmpty) ...[
                  Padding(
                    key: const ValueKey('completed_header'),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: const Text('Completed',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  ...completed.map((t) => _TaskTile(key: ValueKey(t.id), task: t)),
                ],
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addTask(context, state),
        child: const Icon(Icons.add),
      ),
    );
  }

  int _compareTasksByDate(Task a, Task b) {
    if (a.scheduledDate == null && b.scheduledDate == null) return 0;
    if (a.scheduledDate == null) return 1;
    if (b.scheduledDate == null) return -1;
    return a.scheduledDate!.compareTo(b.scheduledDate!);
  }

  void _reorderTasks(AppState state, List<Task> pending, List<Task> completed,
      int oldIndex, int newIndex) {
    final allTasks = [...pending, ...completed];
    if (oldIndex < newIndex) newIndex--;
    final task = allTasks.removeAt(oldIndex);
    allTasks.insert(newIndex, task);
    // Note: Actual reordering persistence would require adding an 'order' field to Task model
  }

  void _addTask(BuildContext context, AppState state) {
    showDialog(
      context: context,
      builder: (_) => TaskEditorDialog(listId: listId),
    );
  }
}

class _TaskTile extends StatefulWidget {
  final Task task;
  const _TaskTile({required super.key, required this.task});

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
        completedDates: widget.task.completedDates,
      );
      state.updateTask(updated);
    }
    setState(() => _isEditing = false);
  }

  void _showEditDialog(BuildContext context, Offset position) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        overlay.size.width - position.dx,
        overlay.size.height - position.dy,
      ),
      items: [],
    ).then((_) {
      // Close the empty menu immediately and show the dialog
    });
    
    showDialog(
      context: context,
      builder: (_) => TaskEditorDialog(
        listId: widget.task.listId,
        existingTask: widget.task,
        initialPosition: position,
      ),
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
          if (event.buttons == kSecondaryMouseButton) {
            _showEditDialog(context, event.position);
          }
        },
        child: ListTile(
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ReorderableDragStartListener(
                index: 0,
                child: Icon(
                  Icons.drag_indicator,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
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
              if (isRecurring)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(Icons.repeat,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              IconButton(
                icon: const Icon(Icons.more_vert, size: 20),
                onPressed: () {
                  final box = context.findRenderObject() as RenderBox;
                  final position = box.localToGlobal(Offset.zero);
                  _showEditDialog(
                    context,
                    Offset(position.dx + box.size.width - 50, position.dy),
                  );
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          onTap: () {
            if (!_isEditing) _startEditing();
          },
        ),
      ),
    );
  }

  Widget? _buildSubtitle(BuildContext context) {
    final state = context.read<AppState>();
    final parts = <Widget>[];

    if (widget.task.scheduledDate != null) {
      parts.add(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.calendar_today,
              size: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            DateFormat.MMMd().format(widget.task.scheduledDate!),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ));
    }

    final tagWidgets = widget.task.tagIds
        .map((id) => state.tagById(id))
        .where((t) => t != null)
        .map((t) => Container(
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: t!.color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(t.name,
                  style: TextStyle(fontSize: 11, color: t.color)),
            ))
        .toList();

    if (tagWidgets.isNotEmpty) {
      parts.add(Row(mainAxisSize: MainAxisSize.min, children: tagWidgets));
    }

    if (parts.isEmpty) return null;
    return Wrap(spacing: 8, children: parts);
  }
}
