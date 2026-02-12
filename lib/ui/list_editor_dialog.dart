import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/task_list.dart';
import '../state/app_state.dart';

class ListEditorDialog extends StatefulWidget {
  final TaskList? taskList;
  const ListEditorDialog({super.key, this.taskList});

  @override
  State<ListEditorDialog> createState() => _ListEditorDialogState();
}

class _ListEditorDialogState extends State<ListEditorDialog> {
  late final TextEditingController _nameCtrl;
  String? _folderId;
  int _colorValue = 0xFF42A5F5;

  static const _colors = [
    0xFF42A5F5, // blue
    0xFF66BB6A, // green
    0xFFEF5350, // red
    0xFFAB47BC, // purple
    0xFFFF7043, // orange
    0xFFFFA726, // amber
    0xFF26C6DA, // cyan
    0xFF78909C, // grey
  ];

  bool get _isEditing => widget.taskList != null;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.taskList?.name ?? '');
    _folderId = widget.taskList?.folderId;
    _colorValue = widget.taskList?.colorValue ?? 0xFF42A5F5;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return AlertDialog(
      title: Text(_isEditing ? 'Edit List' : 'New List'),
      content: SizedBox(
        width: 350,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              initialValue: _folderId,
              decoration: const InputDecoration(
                labelText: 'Folder',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('None')),
                ...state.folders.map(
                  (f) => DropdownMenuItem(value: f.id, child: Text(f.name)),
                ),
              ],
              onChanged: (v) => setState(() => _folderId = v),
            ),
            const SizedBox(height: 16),
            const Text('Color'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _colors.map((c) {
                return GestureDetector(
                  onTap: () => setState(() => _colorValue = c),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Color(c),
                      shape: BoxShape.circle,
                      border: _colorValue == c
                          ? Border.all(width: 3, color: Colors.black54)
                          : null,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final name = _nameCtrl.text.trim();
            if (name.isEmpty) return;
            final state = context.read<AppState>();
            if (_isEditing) {
              final list = widget.taskList!;
              list.name = name;
              list.folderId = _folderId;
              list.colorValue = _colorValue;
              state.updateList(list);
            } else {
              state.addList(
                TaskList(
                  id: state.newId(),
                  name: name,
                  folderId: _folderId,
                  colorValue: _colorValue,
                ),
              );
            }
            Navigator.pop(context);
          },
          child: Text(_isEditing ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}
