import 'package:flutter/material.dart';
import 'task.dart';

enum SmartFilterType {
  today,
  upcoming,     // next 7 days
  overdue,
  dateRange,
  tags,
  completed,
  all,
}

class SmartFilter {
  final SmartFilterType type;

  /// For [dateRange]: start.
  final DateTime? dateFrom;

  /// For [dateRange]: end.
  final DateTime? dateTo;

  /// For [tags]: required tag ids (any match).
  final Set<String> tagIds;

  /// For [upcoming]: number of days ahead.
  final int daysAhead;

  const SmartFilter({
    required this.type,
    this.dateFrom,
    this.dateTo,
    this.tagIds = const {},
    this.daysAhead = 7,
  });

  factory SmartFilter.today() =>
      const SmartFilter(type: SmartFilterType.today);

  factory SmartFilter.upcoming([int days = 7]) =>
      SmartFilter(type: SmartFilterType.upcoming, daysAhead: days);

  factory SmartFilter.overdue() =>
      const SmartFilter(type: SmartFilterType.overdue);

  factory SmartFilter.completed() =>
      const SmartFilter(type: SmartFilterType.completed);

  factory SmartFilter.all() =>
      const SmartFilter(type: SmartFilterType.all);

  factory SmartFilter.byTags(Set<String> tagIds) =>
      SmartFilter(type: SmartFilterType.tags, tagIds: tagIds);

  factory SmartFilter.byDateRange(DateTime from, DateTime to) =>
      SmartFilter(type: SmartFilterType.dateRange, dateFrom: from, dateTo: to);

  bool matches(Task task) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    switch (type) {
      case SmartFilterType.today:
        return task.occursOn(today);
      case SmartFilterType.upcoming:
        for (int i = 0; i <= daysAhead; i++) {
          if (task.occursOn(today.add(Duration(days: i)))) return true;
        }
        return false;
      case SmartFilterType.overdue:
        if (task.isCompleted) return false;
        if (task.scheduledDate == null) return false;
        if (task.recurrence != null) return false;
        final sd = DateTime(
          task.scheduledDate!.year,
          task.scheduledDate!.month,
          task.scheduledDate!.day,
        );
        return sd.isBefore(today);
      case SmartFilterType.dateRange:
        if (task.scheduledDate == null) return false;
        final sd = DateTime(
          task.scheduledDate!.year,
          task.scheduledDate!.month,
          task.scheduledDate!.day,
        );
        final from = dateFrom != null
            ? DateTime(dateFrom!.year, dateFrom!.month, dateFrom!.day)
            : DateTime(1970);
        final to = dateTo != null
            ? DateTime(dateTo!.year, dateTo!.month, dateTo!.day)
            : DateTime(2100);
        return !sd.isBefore(from) && !sd.isAfter(to);
      case SmartFilterType.tags:
        return task.tagIds.any((t) => tagIds.contains(t));
      case SmartFilterType.completed:
        return task.isCompleted;
      case SmartFilterType.all:
        return !task.isCompleted;
    }
  }

  Map<String, dynamic> toJson() => {
        'type': type.index,
        'dateFrom': dateFrom?.toIso8601String(),
        'dateTo': dateTo?.toIso8601String(),
        'tagIds': tagIds.toList(),
        'daysAhead': daysAhead,
      };

  factory SmartFilter.fromJson(Map<String, dynamic> json) => SmartFilter(
        type: SmartFilterType.values[json['type'] as int],
        dateFrom: json['dateFrom'] != null
            ? DateTime.parse(json['dateFrom'] as String)
            : null,
        dateTo: json['dateTo'] != null
            ? DateTime.parse(json['dateTo'] as String)
            : null,
        tagIds:
            (json['tagIds'] as List?)?.map((e) => e as String).toSet() ?? {},
        daysAhead: json['daysAhead'] as int? ?? 7,
      );
}

class SmartList {
  String id;
  String name;
  int iconCodePoint;
  int colorValue;
  SmartFilter filter;

  SmartList({
    required this.id,
    required this.name,
    this.iconCodePoint = 0xe0c8, // Icons.auto_awesome
    this.colorValue = 0xFFAB47BC,
    required this.filter,
  });

  IconData get icon => IconData(iconCodePoint, fontFamily: 'MaterialIcons');
  Color get color => Color(colorValue);

  List<Task> apply(List<Task> allTasks) =>
      allTasks.where((t) => filter.matches(t)).toList();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'iconCodePoint': iconCodePoint,
        'colorValue': colorValue,
        'filter': filter.toJson(),
      };

  factory SmartList.fromJson(Map<String, dynamic> json) => SmartList(
        id: json['id'] as String,
        name: json['name'] as String,
        iconCodePoint: json['iconCodePoint'] as int? ?? 0xe0c8,
        colorValue: json['colorValue'] as int? ?? 0xFFAB47BC,
        filter: SmartFilter.fromJson(json['filter'] as Map<String, dynamic>),
      );
}
