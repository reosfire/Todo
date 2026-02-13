import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/smart_list.dart';
import '../state/app_state.dart';

/// The filter types available for user-created smart lists.
enum _EditorFilterType {
  overdue,
  dateRange,
  tags,
  completed,
  all,
}

class SmartListEditorDialog extends StatefulWidget {
  final SmartList? smartList;
  const SmartListEditorDialog({super.key, this.smartList});

  @override
  State<SmartListEditorDialog> createState() => _SmartListEditorDialogState();
}

class _SmartListEditorDialogState extends State<SmartListEditorDialog> {
  late final TextEditingController _nameCtrl;
  _EditorFilterType _filterType = _EditorFilterType.all;
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
      _filterType = _filterTypeFromFilter(sl.filter);
      if (sl.filter case TagsFilter(:final tagIds)) {
        _tagIds.addAll(tagIds);
      }
      if (sl.filter case DateRangeFilter(:final dateFrom, :final dateTo)) {
        _dateFrom = dateFrom;
        _dateTo = dateTo;
      }
    }
  }

  static _EditorFilterType _filterTypeFromFilter(SmartListFilter filter) {
    return switch (filter) {
      OverdueFilter() => _EditorFilterType.overdue,
      DateRangeFilter() => _EditorFilterType.dateRange,
      TagsFilter() => _EditorFilterType.tags,
      CompletedFilter() => _EditorFilterType.completed,
      AllTasksFilter() => _EditorFilterType.all,
      // Built-in types should not appear in the editor, but handle gracefully.
      TodayFilter() => _EditorFilterType.all,
      TomorrowFilter() => _EditorFilterType.all,
      UpcomingFilter() => _EditorFilterType.all,
    };
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
              DropdownButtonFormField<_EditorFilterType>(
                initialValue: _filterType,
                decoration: const InputDecoration(
                  labelText: 'Filter type',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: _EditorFilterType.all,
                    child: Text('All incomplete'),
                  ),
                  DropdownMenuItem(
                    value: _EditorFilterType.overdue,
                    child: Text('Overdue'),
                  ),
                  DropdownMenuItem(
                    value: _EditorFilterType.dateRange,
                    child: Text('Date range'),
                  ),
                  DropdownMenuItem(
                    value: _EditorFilterType.tags,
                    child: Text('By tags'),
                  ),
                  DropdownMenuItem(
                    value: _EditorFilterType.completed,
                    child: Text('Completed'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _filterType = v);
                },
              ),
              const SizedBox(height: 12),

              // Extra controls based on type
              if (_filterType == _EditorFilterType.tags) ...[
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

              if (_filterType == _EditorFilterType.dateRange) ...[
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

    final SmartListFilter filter = switch (_filterType) {
      _EditorFilterType.overdue => const OverdueFilter(),
      _EditorFilterType.dateRange =>
        DateRangeFilter(dateFrom: _dateFrom, dateTo: _dateTo),
      _EditorFilterType.tags => TagsFilter(tagIds: _tagIds),
      _EditorFilterType.completed => const CompletedFilter(),
      _EditorFilterType.all => const AllTasksFilter(),
    };

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
