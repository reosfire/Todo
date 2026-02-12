import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/task.dart';
import '../models/recurrence.dart';
import '../state/app_state.dart';

class TaskEditorDialog extends StatefulWidget {
  static const double dialogWidth = 400.0;

  final String listId;
  final Task? existingTask;
  final Offset clickPosition;

  const TaskEditorDialog({
    super.key,
    required this.listId,
    this.existingTask,
    required this.clickPosition,
  });

  @override
  State<TaskEditorDialog> createState() => _TaskEditorDialogState();
}

class _TaskEditorDialogState extends State<TaskEditorDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _notesCtrl;
  DateTime? _scheduledDate;
  RecurrenceRule? _recurrence;
  late Set<String> _tagIds;
  late String _listId;
  bool get _isEditing => widget.existingTask != null;
  final GlobalKey _dialogKey = GlobalKey();
  Offset? _calculatedPosition;

  @override
  void initState() {
    super.initState();
    final t = widget.existingTask;
    _titleCtrl = TextEditingController(text: t?.title ?? '');
    _notesCtrl = TextEditingController(text: t?.notes ?? '');
    _scheduledDate = t?.scheduledDate;
    _recurrence = t?.recurrence;
    _tagIds = Set.from(t?.tagIds ?? {});
    _listId = t?.listId ?? widget.listId;

    // Measure and position after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureAndPosition();
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _measureAndPosition() {
    final renderBox = _dialogKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final dialogSize = renderBox.size;
    final screenSize = MediaQuery.of(context).size;
    final clickPosition = widget.clickPosition;

    // Try 4 corner positions
    final candidates = [
      Offset(clickPosition.dx, clickPosition.dy),
      Offset(clickPosition.dx, clickPosition.dy - dialogSize.height),
      Offset(clickPosition.dx - dialogSize.width, clickPosition.dy),
      Offset(clickPosition.dx - dialogSize.width, clickPosition.dy - dialogSize.height),
    ];

    // Find first position that fits
    Offset? bestPos;
    for (final pos in candidates) {
      if (pos.dx >= 0 &&
          pos.dy >= 0 &&
          pos.dx + dialogSize.width <= screenSize.width &&
          pos.dy + dialogSize.height <= screenSize.height) {
        bestPos = pos;
        break;
      }
    }

    // If none fit, adjust the first candidate
    if (bestPos == null) {
      var x = candidates[0].dx;
      var y = candidates[0].dy;

      if (x < 0) x = 0;
      if (x + dialogSize.width > screenSize.width) {
        x = screenSize.width - dialogSize.width;
      }

      if (y < 0) y = 0;
      if (y + dialogSize.height > screenSize.height) {
        y = screenSize.height - dialogSize.height;
      }

      bestPos = Offset(x, y);
    }

    if (_calculatedPosition != bestPos) {
      setState(() => _calculatedPosition = bestPos);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    
    final dialog = AlertDialog(
      insetPadding: EdgeInsets.zero,
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      title: Text(_isEditing ? 'Edit Task' : 'New Task'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
                autofocus: !_isEditing,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),

              // List picker
              DropdownButtonFormField<String>(
                initialValue: _listId,
                decoration: const InputDecoration(
                  labelText: 'List',
                  border: OutlineInputBorder(),
                ),
                items: state.lists
                    .map((l) => DropdownMenuItem(
                          value: l.id,
                          child: Text(l.name),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _listId = v);
                },
              ),
              const SizedBox(height: 16),

              // Scheduled date
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today),
                title: Text(_scheduledDate != null
                    ? DateFormat.yMMMd().format(_scheduledDate!)
                    : 'No date'),
                trailing: _scheduledDate != null
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () =>
                            setState(() => _scheduledDate = null),
                      )
                    : null,
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _scheduledDate ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    setState(() => _scheduledDate = picked);
                  }
                },
              ),

              // Recurrence
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.repeat),
                title: Text(_recurrence?.describe() ?? 'No repeat'),
                trailing: _recurrence != null
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () =>
                            setState(() => _recurrence = null),
                      )
                    : null,
                onTap: () => _showRecurrencePicker(),
              ),

              // Tags
              const SizedBox(height: 8),
              const Text('Tags',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                children: state.tags.map((tag) {
                  final selected = _tagIds.contains(tag.id);
                  return FilterChip(
                    label: Text(tag.name),
                    selected: selected,
                    selectedColor: tag.color.withValues(alpha: 0.3),
                    onSelected: (v) {
                      setState(() {
                        if (v) {
                          _tagIds.add(tag.id);
                        } else {
                          _tagIds.remove(tag.id);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (_isEditing)
          TextButton(
            onPressed: () {
              state.deleteTask(widget.existingTask!.id);
              Navigator.pop(context);
            },
            child:
                const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(_isEditing ? 'Save' : 'Add'),
        ),
      ],
    );

    // Wrap dialog in positioned widget with measured position
    final position = _calculatedPosition ?? widget.clickPosition;
    return Stack(
      children: [
        Positioned(
          left: position.dx,
          top: position.dy,
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              key: _dialogKey,
              child: dialog,
            ),
          ),
        ),
      ],
    );
  }

  void _save() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    final state = context.read<AppState>();

    if (_isEditing) {
      final task = widget.existingTask!;
      task.title = title;
      task.notes = _notesCtrl.text.trim();
      task.scheduledDate = _scheduledDate;
      task.recurrence = _recurrence;
      task.tagIds = _tagIds;
      task.listId = _listId;
      state.updateTask(task);
    } else {
      state.addTask(Task(
        id: state.newId(),
        title: title,
        notes: _notesCtrl.text.trim(),
        createdAt: DateTime.now(),
        scheduledDate: _scheduledDate,
        recurrence: _recurrence,
        tagIds: _tagIds,
        listId: _listId,
      ));
    }
    Navigator.pop(context);
  }

  void _showRecurrencePicker() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Repeat',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              title: const Text('Every day'),
              onTap: () {
                setState(() => _recurrence = RecurrenceRule.daily());
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              title: const Text('Every N days…'),
              onTap: () {
                Navigator.pop(ctx);
                _showEveryNDaysPicker();
              },
            ),
            ListTile(
              title: const Text('Weekly on specific days…'),
              onTap: () {
                Navigator.pop(ctx);
                _showWeekdayPicker();
              },
            ),
            ListTile(
              title: const Text('Monthly on this day'),
              onTap: () {
                final day = _scheduledDate?.day ?? DateTime.now().day;
                setState(() => _recurrence = RecurrenceRule.monthly(day));
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              title: const Text('Yearly on this date'),
              onTap: () {
                final d = _scheduledDate ?? DateTime.now();
                setState(() =>
                    _recurrence = RecurrenceRule.yearly(d.month, d.day));
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showEveryNDaysPicker() {
    int n = 2;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Every N days'),
          content: Row(
            children: [
              const Text('Every '),
              SizedBox(
                width: 60,
                child: TextField(
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(border: OutlineInputBorder()),
                  onChanged: (v) {
                    final parsed = int.tryParse(v);
                    if (parsed != null && parsed > 0) n = parsed;
                  },
                  controller: TextEditingController(text: '$n'),
                ),
              ),
              const Text(' days'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                setState(
                    () => _recurrence = RecurrenceRule.everyNDays(n));
                Navigator.pop(ctx);
              },
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
  }

  void _showWeekdayPicker() {
    final selected = <int>{};
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Select days'),
          content: Wrap(
            spacing: 6,
            children: List.generate(7, (i) {
              final day = i + 1;
              return FilterChip(
                label: Text(names[i]),
                selected: selected.contains(day),
                onSelected: (v) {
                  setDialogState(() {
                    if (v) {
                      selected.add(day);
                    } else {
                      selected.remove(day);
                    }
                  });
                },
              );
            }),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (selected.isNotEmpty) {
                  setState(() =>
                      _recurrence = RecurrenceRule.weekly(selected));
                }
                Navigator.pop(ctx);
              },
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
  }
}
