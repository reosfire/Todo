import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/smart_list.dart';
import '../state/app_state.dart';

class SmartListEditorDialog extends StatefulWidget {
  final SmartList? smartList;
  const SmartListEditorDialog({super.key, this.smartList});

  @override
  State<SmartListEditorDialog> createState() => _SmartListEditorDialogState();
}

class _SmartListEditorDialogState extends State<SmartListEditorDialog> {
  late final TextEditingController _nameCtrl;
  SmartFilterType _filterType = SmartFilterType.today;
  int _daysAhead = 7;
  final Set<String> _tagIds = {};
  DateTime? _dateFrom;
  DateTime? _dateTo;

  bool get _isEditing => widget.smartList != null;

  @override
  void initState() {
    super.initState();
    final sl = widget.smartList;
    _nameCtrl = TextEditingController(text: sl?.name ?? '');
    if (sl != null) {
      _filterType = sl.filter.type;
      _daysAhead = sl.filter.daysAhead;
      _tagIds.addAll(sl.filter.tagIds);
      _dateFrom = sl.filter.dateFrom;
      _dateTo = sl.filter.dateTo;
    }
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
      title: Text(_isEditing ? 'Edit Smart List' : 'New Smart List'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
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
                autofocus: !_isEditing,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<SmartFilterType>(
                initialValue: _filterType,
                decoration: const InputDecoration(
                  labelText: 'Filter type',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: SmartFilterType.today,
                    child: Text('Today'),
                  ),
                  DropdownMenuItem(
                    value: SmartFilterType.upcoming,
                    child: Text('Upcoming (N days)'),
                  ),
                  DropdownMenuItem(
                    value: SmartFilterType.overdue,
                    child: Text('Overdue'),
                  ),
                  DropdownMenuItem(
                    value: SmartFilterType.dateRange,
                    child: Text('Date range'),
                  ),
                  DropdownMenuItem(
                    value: SmartFilterType.tags,
                    child: Text('By tags'),
                  ),
                  DropdownMenuItem(
                    value: SmartFilterType.completed,
                    child: Text('Completed'),
                  ),
                  DropdownMenuItem(
                    value: SmartFilterType.all,
                    child: Text('All incomplete'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _filterType = v);
                },
              ),
              const SizedBox(height: 12),

              // Extra controls based on type
              if (_filterType == SmartFilterType.upcoming) ...[
                Row(
                  children: [
                    const Text('Days ahead: '),
                    SizedBox(
                      width: 60,
                      child: TextField(
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                        ),
                        controller: TextEditingController(text: '$_daysAhead'),
                        onChanged: (v) {
                          final parsed = int.tryParse(v);
                          if (parsed != null && parsed > 0) _daysAhead = parsed;
                        },
                      ),
                    ),
                  ],
                ),
              ],

              if (_filterType == SmartFilterType.tags) ...[
                const SizedBox(height: 8),
                const Text('Select tags:'),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  children: state.tags.map((tag) {
                    return FilterChip(
                      label: Text(tag.name),
                      selected: _tagIds.contains(tag.id),
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

              if (_filterType == SmartFilterType.dateRange) ...[
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    _dateFrom != null
                        ? 'From: ${_dateFrom.toString().substring(0, 10)}'
                        : 'From: (any)',
                  ),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _dateFrom ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (d != null) setState(() => _dateFrom = d);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    _dateTo != null
                        ? 'To: ${_dateTo.toString().substring(0, 10)}'
                        : 'To: (any)',
                  ),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _dateTo ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (d != null) setState(() => _dateTo = d);
                  },
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (_isEditing)
          TextButton(
            onPressed: () {
              context.read<AppState>().deleteSmartList(widget.smartList!.id);
              Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(_isEditing ? 'Save' : 'Create'),
        ),
      ],
    );
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    final state = context.read<AppState>();

    final filter = SmartFilter(
      type: _filterType,
      daysAhead: _daysAhead,
      tagIds: _tagIds,
      dateFrom: _dateFrom,
      dateTo: _dateTo,
    );

    if (_isEditing) {
      final sl = widget.smartList!;
      sl.name = name;
      sl.filter = filter;
      state.updateSmartList(sl);
    } else {
      state.addSmartList(
        SmartList(id: state.newId(), name: name, filter: filter),
      );
    }
    Navigator.pop(context);
  }
}
