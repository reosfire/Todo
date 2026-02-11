import 'package:flutter/material.dart';
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
          : ListView(
              padding: const EdgeInsets.only(bottom: 80),
              children: [
                ...pending.map((t) => _TaskTile(task: t)),
                if (completed.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text('Completed',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  ...completed.map((t) => _TaskTile(task: t)),
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

  void _addTask(BuildContext context, AppState state) {
    showDialog(
      context: context,
      builder: (_) => TaskEditorDialog(listId: listId),
    );
  }
}

class _TaskTile extends StatelessWidget {
  final Task task;
  const _TaskTile({required this.task});

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();

    final isRecurring = task.recurrence != null;
    final completed = task.isCompleted;

    return Dismissible(
      key: ValueKey(task.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => state.deleteTask(task.id),
      child: ListTile(
        leading: Checkbox(
          value: completed,
          onChanged: (_) => state.toggleTask(task),
          shape: const CircleBorder(),
        ),
        title: Text(
          task.title,
          style: TextStyle(
            decoration: completed ? TextDecoration.lineThrough : null,
            color: completed
                ? Theme.of(context).colorScheme.onSurfaceVariant
                : null,
          ),
        ),
        subtitle: _buildSubtitle(context),
        trailing: isRecurring
            ? Icon(Icons.repeat,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant)
            : null,
        onTap: () {
          showDialog(
            context: context,
            builder: (_) => TaskEditorDialog(
              listId: task.listId,
              existingTask: task,
            ),
          );
        },
      ),
    );
  }

  Widget? _buildSubtitle(BuildContext context) {
    final state = context.read<AppState>();
    final parts = <Widget>[];

    if (task.scheduledDate != null) {
      parts.add(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.calendar_today,
              size: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            DateFormat.MMMd().format(task.scheduledDate!),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ));
    }

    final tagWidgets = task.tagIds
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
