import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/smart_list.dart';
import '../models/task.dart';
import '../state/app_state.dart';
import 'task_editor_dialog.dart';

class SmartListView extends StatelessWidget {
  final SmartList smartList;
  const SmartListView({super.key, required this.smartList});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final tasks = smartList.apply(state.tasks);
    tasks.sort(_compareTasksByDate);

    if (tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'No matching tasks',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        final task = tasks[index];
        return _SmartTaskTile(task: task);
      },
    );
  }

  int _compareTasksByDate(Task a, Task b) {
    if (a.scheduledDate == null && b.scheduledDate == null) return 0;
    if (a.scheduledDate == null) return 1;
    if (b.scheduledDate == null) return -1;
    return a.scheduledDate!.compareTo(b.scheduledDate!);
  }
}

class _SmartTaskTile extends StatelessWidget {
  final Task task;
  const _SmartTaskTile({required this.task});

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final listName = state.listById(task.listId)?.name ?? '';
    final tags = task.tagIds
        .map((id) => state.tagById(id))
        .where((t) => t != null)
        .toList();

    return ListTile(
      leading: Checkbox(
        value: task.isCompleted,
        onChanged: (_) => state.toggleTask(task),
        shape: const CircleBorder(),
      ),
      title: Text(
        task.title,
        style: TextStyle(
          decoration: task.isCompleted ? TextDecoration.lineThrough : null,
          color: task.isCompleted
              ? Theme.of(context).colorScheme.onSurfaceVariant
              : null,
        ),
      ),
      subtitle: _buildSubtitle(context, listName, tags),
      trailing: task.recurrence != null
          ? Icon(
              Icons.repeat,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            )
          : null,
      onTap: () {
        showGeneralDialog(
          context: context,
          barrierDismissible: true,
          barrierLabel: '',
          barrierColor: Colors.transparent,
          pageBuilder: (context, animation, secondaryAnimation) {
            return TaskEditorDialog(
              listId: task.listId,
              existingTask: task,
              clickPosition: Offset(
                MediaQuery.of(context).size.width / 2,
                MediaQuery.of(context).size.height / 2,
              ),
            );
          },
        );
      },
    );
  }

  Widget? _buildSubtitle(BuildContext context, String listName, List tags) {
    final parts = <Widget>[];

    parts.add(
      Text(
        listName,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
      ),
    );

    if (task.scheduledDate != null) {
      parts.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_today,
              size: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              DateFormat.MMMd().format(task.scheduledDate!),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    }

    final tagWidgets = tags
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

    return Wrap(spacing: 8, children: parts);
  }
}
