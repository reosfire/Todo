import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/task.dart';
import '../models/smart_list.dart';
import '../state/app_state.dart';
import 'task_editor_dialog.dart';

/// A common task list component that displays tasks organized in sections.
///
/// Supports both reorderable (regular lists) and non-reorderable (smart lists)
/// modes via the [reorderable] flag.
class SectionedTaskList extends StatefulWidget {
  /// The sections of tasks to display.
  final List<TaskSection> sections;

  /// Whether tasks can be reordered via drag-and-drop.
  final bool reorderable;

  /// Whether to show the list name in each task tile's subtitle.
  final bool showListName;

  /// Hint text for the input field. If null, no input field is shown.
  final String? inputHint;

  /// Callback when a new task is created via the input field.
  final void Function(String title)? onAddTask;

  /// Callback when tasks in a section are reordered.
  final void Function(int sectionIndex, int oldIndex, int newIndex)? onReorder;

  /// The date to use for recurring task completion toggle.
  final DateTime? toggleDate;

  const SectionedTaskList({
    super.key,
    required this.sections,
    this.reorderable = false,
    this.showListName = false,
    this.inputHint,
    this.onAddTask,
    this.onReorder,
    this.toggleDate,
  });

  @override
  State<SectionedTaskList> createState() => _SectionedTaskListState();
}

class _SectionedTaskListState extends State<SectionedTaskList> {
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocus = FocusNode();

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _handleAddTask() {
    final title = _inputController.text.trim();
    if (title.isEmpty) return;
    widget.onAddTask?.call(title);
    _inputController.clear();
    _inputFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final allEmpty = widget.sections.every((s) => s.tasks.isEmpty);

    return Column(
      children: [
        // Input field
        if (widget.inputHint != null)
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
                    controller: _inputController,
                    focusNode: _inputFocus,
                    decoration: InputDecoration(
                      hintText: widget.inputHint,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) => _handleAddTask(),
                    textInputAction: TextInputAction.done,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: _handleAddTask,
                    child: const Text('Add'),
                  ),
                ),
              ],
            ),
          ),
        // Task sections
        Expanded(
          child: allEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        widget.reorderable
                            ? Icons.check_circle_outline
                            : Icons.inbox_outlined,
                        size: 64,
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.reorderable
                            ? 'No tasks yet'
                            : 'No matching tasks',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 16),
                  children: _buildSectionWidgets(),
                ),
        ),
      ],
    );
  }

  List<Widget> _buildSectionWidgets() {
    final widgets = <Widget>[];
    for (var i = 0; i < widget.sections.length; i++) {
      final section = widget.sections[i];
      if (section.tasks.isEmpty) continue;

      if (section.header != null) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              section.header!,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        );
      }

      if (widget.reorderable) {
        final sectionIndex = i;
        widgets.add(
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorder: (oldIndex, newIndex) {
              widget.onReorder?.call(sectionIndex, oldIndex, newIndex);
            },
            children: [
              for (var j = 0; j < section.tasks.length; j++)
                TaskTile(
                  key: ValueKey(section.tasks[j].id),
                  task: section.tasks[j],
                  index: j,
                  reorderable: true,
                  showListName: widget.showListName,
                  toggleDate: widget.toggleDate,
                ),
            ],
          ),
        );
      } else {
        for (final task in section.tasks) {
          widgets.add(
            TaskTile(
              key: ValueKey('s${i}_${task.id}'),
              task: task,
              index: 0,
              reorderable: false,
              showListName: widget.showListName,
              toggleDate: widget.toggleDate,
            ),
          );
        }
      }
    }
    return widgets;
  }
}

// ───── Common task tile ─────

class TaskTile extends StatefulWidget {
  final Task task;
  final int index;
  final bool reorderable;
  final bool showListName;
  final DateTime? toggleDate;

  const TaskTile({
    required super.key,
    required this.task,
    required this.index,
    this.reorderable = false,
    this.showListName = false,
    this.toggleDate,
  });

  @override
  State<TaskTile> createState() => _TaskTileState();
}

class _TaskTileState extends State<TaskTile> {
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
    if (!widget.reorderable) return;
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
      final updated = state.copyTask(
        widget.task,
        previousTaskId: widget.task.previousTaskId,
        nextTaskId: widget.task.nextTaskId,
      );
      updated.title = newTitle;
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
    final task = widget.task;
    final isRecurring = task.recurrence != null;
    final completed = isRecurring && widget.toggleDate != null
        ? task.isCompletedOn(widget.toggleDate!)
        : task.isCompleted;

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
      child: Listener(
        onPointerDown: (event) {
          if (event.buttons == 2) {
            _showEditDialog(context, event.position);
          }
        },
        child: GestureDetector(
          onSecondaryTapDown: (details) {},
          onSecondaryTap: () {},
          behavior: HitTestBehavior.opaque,
          child: ListTile(
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.reorderable) ...[
                  ReorderableDragStartListener(
                    index: widget.index,
                    child: Icon(
                      Icons.drag_handle_rounded,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                Checkbox(
                  value: completed,
                  onChanged: (_) =>
                      state.toggleTask(task, onDate: widget.toggleDate),
                  shape: widget.reorderable
                      ? RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        )
                      : const CircleBorder(),
                ),
              ],
            ),
            title: _isEditing && widget.reorderable
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
                    task.title,
                    style: TextStyle(
                      decoration:
                          completed ? TextDecoration.lineThrough : null,
                      color: completed
                          ? Theme.of(context).colorScheme.onSurfaceVariant
                          : null,
                    ),
                  ),
            subtitle: _buildSubtitle(context, state),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (task.scheduledDate != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      DateFormat.MMMd().format(task.scheduledDate!),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                if (isRecurring)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      Icons.repeat,
                      size: widget.reorderable ? 20 : 16,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.7),
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
                    final Offset buttonPosition =
                        button.localToGlobal(Offset.zero);
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
              if (widget.reorderable && !_isEditing) {
                _startEditing();
              } else if (!widget.reorderable) {
                final RenderBox box =
                    context.findRenderObject() as RenderBox;
                final pos = box.localToGlobal(Offset.zero);
                _showEditDialog(
                  context,
                  Offset(
                    pos.dx + box.size.width / 2,
                    pos.dy + box.size.height / 2,
                  ),
                );
              }
            },
          ),
        ),
      ),
    );
  }

  Widget? _buildSubtitle(BuildContext context, AppState state) {
    final parts = <Widget>[];

    if (widget.showListName) {
      final listName = state.listById(widget.task.listId)?.name ?? '';
      if (listName.isNotEmpty) {
        parts.add(
          Text(
            listName,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(fontStyle: FontStyle.italic),
          ),
        );
      }
    }

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
            child:
                Text(t.name, style: TextStyle(fontSize: 11, color: t.color)),
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
