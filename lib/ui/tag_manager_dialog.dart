import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/tag.dart';
import '../state/app_state.dart';

class TagManagerDialog extends StatelessWidget {
  const TagManagerDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return AlertDialog(
      title: const Text('Tags'),
      content: SizedBox(
        width: 350,
        height: 350,
        child: Column(
          children: [
            Expanded(
              child: state.tags.isEmpty
                  ? const Center(child: Text('No tags yet'))
                  : ListView(
                      children: state.tags
                          .map((tag) => ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: tag.color,
                                  radius: 12,
                                ),
                                title: Text(tag.name),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete, size: 18),
                                  onPressed: () => state.deleteTag(tag.id),
                                ),
                                onTap: () => _editTag(context, state, tag),
                              ))
                          .toList(),
                    ),
            ),
            const Divider(),
            TextButton.icon(
              onPressed: () => _addTag(context, state),
              icon: const Icon(Icons.add),
              label: const Text('Add Tag'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }

  void _addTag(BuildContext context, AppState state) {
    _showTagEditor(context, state, null);
  }

  void _editTag(BuildContext context, AppState state, Tag tag) {
    _showTagEditor(context, state, tag);
  }

  void _showTagEditor(BuildContext context, AppState state, Tag? tag) {
    final ctrl = TextEditingController(text: tag?.name ?? '');
    int colorValue = tag?.colorValue ?? 0xFF42A5F5;

    const colors = [
      0xFF42A5F5,
      0xFF66BB6A,
      0xFFEF5350,
      0xFFAB47BC,
      0xFFFF7043,
      0xFFFFA726,
      0xFF26C6DA,
      0xFFEC407A,
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(tag != null ? 'Edit Tag' : 'New Tag'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                decoration: const InputDecoration(
                  labelText: 'Tag name',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: colors.map((c) {
                  return GestureDetector(
                    onTap: () => setDialogState(() => colorValue = c),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: colorValue == c
                            ? Border.all(width: 3, color: Colors.black54)
                            : null,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final name = ctrl.text.trim();
                if (name.isEmpty) return;
                if (tag != null) {
                  tag.name = name;
                  tag.colorValue = colorValue;
                  state.updateTag(tag);
                } else {
                  state.addTag(Tag(
                    id: state.newId(),
                    name: name,
                    colorValue: colorValue,
                  ));
                }
                Navigator.pop(ctx);
              },
              child: Text(tag != null ? 'Save' : 'Create'),
            ),
          ],
        ),
      ),
    );
  }
}
