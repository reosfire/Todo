import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/smart_list.dart';
import '../models/task.dart';
import '../state/app_state.dart';
import 'sectioned_task_list.dart';

class SmartListView extends StatelessWidget {
  final SmartList smartList;
  const SmartListView({super.key, required this.smartList});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final filter = smartList.filter;
    final sections = filter.organize(state.tasks);

    return SectionedTaskList(
      sections: sections,
      reorderable: false,
      showListName: true,
      inputHint: filter.hasInput ? 'Add a task...' : null,
      onAddTask: filter.hasInput
          ? (title) => _addTask(state, title, filter)
          : null,
      toggleDate: _getToggleDate(filter),
    );
  }

  DateTime? _getToggleDate(SmartListFilter filter) {
    final now = DateTime.now();
    return switch (filter) {
      TodayFilter() => DateTime(now.year, now.month, now.day),
      TomorrowFilter() =>
        DateTime(now.year, now.month, now.day).add(const Duration(days: 1)),
      _ => null,
    };
  }

  Future<void> _addTask(
    AppState state,
    String title,
    SmartListFilter filter,
  ) async {
    // Find first orphan list (not in a folder), sorted by order.
    final orphanLists = state.lists
        .where((l) => l.folderId == null)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    if (orphanLists.isEmpty) return;

    final targetListId = orphanLists.first.id;
    final scheduledDate = filter.newTaskScheduledDate;

    final pendingTasks = state.tasksForListOrdered(
      targetListId,
      completedSection: false,
    );
    final currentHead = pendingTasks.isNotEmpty ? pendingTasks.first : null;

    final newTask = Task(
      id: state.newId(),
      title: title,
      createdAt: DateTime.now(),
      listId: targetListId,
      scheduledDate: scheduledDate,
      previousTaskId: null,
      nextTaskId: currentHead?.id,
    );

    await state.addTaskAsHead(newTask);
  }
}
