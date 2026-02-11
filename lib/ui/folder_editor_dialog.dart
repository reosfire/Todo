import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/folder.dart';
import '../state/app_state.dart';

class FolderEditorDialog extends StatefulWidget {
  final Folder? folder;
  const FolderEditorDialog({super.key, this.folder});

  @override
  State<FolderEditorDialog> createState() => _FolderEditorDialogState();
}

class _FolderEditorDialogState extends State<FolderEditorDialog> {
  late final TextEditingController _nameCtrl;
  bool get _isEditing => widget.folder != null;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.folder?.name ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? 'Rename Folder' : 'New Folder'),
      content: TextField(
        controller: _nameCtrl,
        decoration: const InputDecoration(
          labelText: 'Folder name',
          border: OutlineInputBorder(),
        ),
        autofocus: true,
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
              widget.folder!.name = name;
              state.updateFolder(widget.folder!);
            } else {
              state.addFolder(Folder(id: state.newId(), name: name));
            }
            Navigator.pop(context);
          },
          child: Text(_isEditing ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}
