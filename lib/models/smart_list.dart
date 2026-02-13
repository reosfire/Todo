import 'package:flutter/material.dart';
import 'task.dart';

/// A section of tasks to display in a grouped list view.
class TaskSection {
  final String? header;
  final List<Task> tasks;
  const TaskSection({this.header, required this.tasks});
}

// ───── Sealed hierarchy for smart list filter types ─────

sealed class SmartListFilter {
  const SmartListFilter();

  /// Whether this filter provides an input field for creating tasks.
  bool get hasInput;

  /// The scheduled date to assign to newly created tasks (if [hasInput]).
  DateTime? get newTaskScheduledDate => null;

  /// Organize matching tasks into display sections.
  List<TaskSection> organize(List<Task> allTasks);

  /// Count matching pending tasks (for drawer badge).
  int countTasks(List<Task> allTasks);

  Map<String, dynamic> toJson();

  static SmartListFilter fromJson(Map<String, dynamic> json) {
    final rawType = json['type'];
    // Handle legacy integer type index and new string type.
    final typeStr =
        rawType is int ? _legacyTypeMap(rawType) : rawType as String;

    return switch (typeStr) {
      'today' => const TodayFilter(),
      'tomorrow' => const TomorrowFilter(),
      'upcoming' => const UpcomingFilter(),
      'overdue' => const OverdueFilter(),
      'dateRange' => DateRangeFilter(
          dateFrom: json['dateFrom'] != null
              ? DateTime.parse(json['dateFrom'] as String)
              : null,
          dateTo: json['dateTo'] != null
              ? DateTime.parse(json['dateTo'] as String)
              : null,
        ),
      'tags' => TagsFilter(
          tagIds: (json['tagIds'] as List?)
                  ?.map((e) => e as String)
                  .toSet() ??
              {},
        ),
      'completed' => const CompletedFilter(),
      'all' => const AllTasksFilter(),
      _ => const AllTasksFilter(),
    };
  }

  /// Map legacy enum index to string type name.
  static String _legacyTypeMap(int index) {
    const map = [
      'today',
      'upcoming',
      'overdue',
      'dateRange',
      'tags',
      'completed',
      'all',
    ];
    return index < map.length ? map[index] : 'all';
  }
}

// ───── Built-in filter types ─────

class TodayFilter extends SmartListFilter {
  const TodayFilter();

  @override
  bool get hasInput => true;

  @override
  DateTime? get newTaskScheduledDate {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  List<TaskSection> organize(List<Task> allTasks) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayTasks = allTasks.where((t) => t.occursOn(today)).toList();

    final pending = todayTasks
        .where((t) =>
            t.recurrence != null ? !t.isCompletedOn(today) : !t.isCompleted)
        .toList()
      ..sort(_byScheduledDate);

    final completed = todayTasks
        .where((t) =>
            t.recurrence != null ? t.isCompletedOn(today) : t.isCompleted)
        .toList()
      ..sort(_byScheduledDate);

    return [
      TaskSection(tasks: pending),
      if (completed.isNotEmpty)
        TaskSection(header: 'Completed', tasks: completed),
    ];
  }

  @override
  int countTasks(List<Task> allTasks) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return allTasks
        .where((t) =>
            t.occursOn(today) &&
            (t.recurrence != null
                ? !t.isCompletedOn(today)
                : !t.isCompleted))
        .length;
  }

  @override
  Map<String, dynamic> toJson() => {'type': 'today'};
}

class TomorrowFilter extends SmartListFilter {
  const TomorrowFilter();

  @override
  bool get hasInput => true;

  @override
  DateTime? get newTaskScheduledDate {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
  }

  @override
  List<TaskSection> organize(List<Task> allTasks) {
    final now = DateTime.now();
    final tomorrow =
        DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    final tomorrowTasks =
        allTasks.where((t) => t.occursOn(tomorrow)).toList();

    final pending = tomorrowTasks
        .where((t) => t.recurrence != null
            ? !t.isCompletedOn(tomorrow)
            : !t.isCompleted)
        .toList()
      ..sort(_byScheduledDate);

    final completed = tomorrowTasks
        .where((t) => t.recurrence != null
            ? t.isCompletedOn(tomorrow)
            : t.isCompleted)
        .toList()
      ..sort(_byScheduledDate);

    return [
      TaskSection(tasks: pending),
      if (completed.isNotEmpty)
        TaskSection(header: 'Completed', tasks: completed),
    ];
  }

  @override
  int countTasks(List<Task> allTasks) {
    final now = DateTime.now();
    final tomorrow =
        DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    return allTasks
        .where((t) =>
            t.occursOn(tomorrow) &&
            (t.recurrence != null
                ? !t.isCompletedOn(tomorrow)
                : !t.isCompleted))
        .length;
  }

  @override
  Map<String, dynamic> toJson() => {'type': 'tomorrow'};
}

class UpcomingFilter extends SmartListFilter {
  const UpcomingFilter();

  @override
  bool get hasInput => false;

  @override
  List<TaskSection> organize(List<Task> allTasks) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final dayAfterTomorrow = today.add(const Duration(days: 2));
    // End of week: next Sunday.
    final daysUntilSunday = DateTime.sunday - today.weekday;
    final endOfWeek = today.add(
      Duration(days: daysUntilSunday <= 0 ? 7 : daysUntilSunday),
    );

    final overdue = <Task>[];
    final todayTasks = <Task>[];
    final tomorrowTasks = <Task>[];
    final restOfWeek = <Task>[];
    final later = <Task>[];

    for (final task in allTasks) {
      if (task.isCompleted) continue;

      if (task.recurrence != null && task.scheduledDate != null) {
        if (task.occursOn(today) && !task.isCompletedOn(today)) {
          todayTasks.add(task);
        }
        if (task.occursOn(tomorrow) && !task.isCompletedOn(tomorrow)) {
          tomorrowTasks.add(task);
        }
        for (var d = dayAfterTomorrow;
            d.isBefore(endOfWeek) || d.isAtSameMomentAs(endOfWeek);
            d = d.add(const Duration(days: 1))) {
          if (task.occursOn(d) && !task.isCompletedOn(d)) {
            restOfWeek.add(task);
            break;
          }
        }
        continue;
      }

      if (task.scheduledDate == null) continue;

      final sd = DateTime(
        task.scheduledDate!.year,
        task.scheduledDate!.month,
        task.scheduledDate!.day,
      );
      if (sd.isBefore(today)) {
        overdue.add(task);
      } else if (sd.isAtSameMomentAs(today)) {
        todayTasks.add(task);
      } else if (sd.isAtSameMomentAs(tomorrow)) {
        tomorrowTasks.add(task);
      } else if (sd.isBefore(endOfWeek) || sd.isAtSameMomentAs(endOfWeek)) {
        restOfWeek.add(task);
      } else {
        later.add(task);
      }
    }

    return [
      if (overdue.isNotEmpty)
        TaskSection(
          header: 'Overdue',
          tasks: overdue..sort(_byScheduledDate),
        ),
      if (todayTasks.isNotEmpty)
        TaskSection(
          header: 'Today',
          tasks: todayTasks..sort(_byScheduledDate),
        ),
      if (tomorrowTasks.isNotEmpty)
        TaskSection(
          header: 'Tomorrow',
          tasks: tomorrowTasks..sort(_byScheduledDate),
        ),
      if (restOfWeek.isNotEmpty)
        TaskSection(
          header: 'Rest of Week',
          tasks: restOfWeek..sort(_byScheduledDate),
        ),
      if (later.isNotEmpty)
        TaskSection(
          header: 'Later',
          tasks: later..sort(_byScheduledDate),
        ),
    ];
  }

  @override
  int countTasks(List<Task> allTasks) {
    return allTasks
        .where((t) => !t.isCompleted && t.scheduledDate != null)
        .length;
  }

  @override
  Map<String, dynamic> toJson() => {'type': 'upcoming'};
}

// ───── User-created filter types ─────

class OverdueFilter extends SmartListFilter {
  const OverdueFilter();

  @override
  bool get hasInput => false;

  @override
  List<TaskSection> organize(List<Task> allTasks) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tasks = allTasks.where((t) {
      if (t.isCompleted) return false;
      if (t.scheduledDate == null) return false;
      if (t.recurrence != null) return false;
      final sd = DateTime(
        t.scheduledDate!.year,
        t.scheduledDate!.month,
        t.scheduledDate!.day,
      );
      return sd.isBefore(today);
    }).toList()
      ..sort(_byScheduledDate);

    return [TaskSection(tasks: tasks)];
  }

  @override
  int countTasks(List<Task> allTasks) =>
      organize(allTasks).fold(0, (s, sec) => s + sec.tasks.length);

  @override
  Map<String, dynamic> toJson() => {'type': 'overdue'};
}

class DateRangeFilter extends SmartListFilter {
  final DateTime? dateFrom;
  final DateTime? dateTo;

  const DateRangeFilter({this.dateFrom, this.dateTo});

  @override
  bool get hasInput => false;

  @override
  List<TaskSection> organize(List<Task> allTasks) {
    final from = dateFrom != null
        ? DateTime(dateFrom!.year, dateFrom!.month, dateFrom!.day)
        : DateTime(1970);
    final to = dateTo != null
        ? DateTime(dateTo!.year, dateTo!.month, dateTo!.day)
        : DateTime(2100);

    final tasks = allTasks.where((t) {
      if (t.scheduledDate == null) return false;
      final sd = DateTime(
        t.scheduledDate!.year,
        t.scheduledDate!.month,
        t.scheduledDate!.day,
      );
      return !sd.isBefore(from) && !sd.isAfter(to);
    }).toList()
      ..sort(_byScheduledDate);

    return [TaskSection(tasks: tasks)];
  }

  @override
  int countTasks(List<Task> allTasks) =>
      organize(allTasks).fold(0, (s, sec) => s + sec.tasks.length);

  @override
  Map<String, dynamic> toJson() => {
        'type': 'dateRange',
        'dateFrom': dateFrom?.toIso8601String(),
        'dateTo': dateTo?.toIso8601String(),
      };
}

class TagsFilter extends SmartListFilter {
  final Set<String> tagIds;

  const TagsFilter({required this.tagIds});

  @override
  bool get hasInput => false;

  @override
  List<TaskSection> organize(List<Task> allTasks) {
    final matching =
        allTasks.where((t) => t.tagIds.any((id) => tagIds.contains(id)));

    final pending = matching.where((t) => !t.isCompleted).toList()
      ..sort(_byScheduledDate);
    final completed = matching.where((t) => t.isCompleted).toList()
      ..sort(_byScheduledDate);

    return [
      TaskSection(tasks: pending),
      if (completed.isNotEmpty)
        TaskSection(header: 'Completed', tasks: completed),
    ];
  }

  @override
  int countTasks(List<Task> allTasks) {
    return allTasks
        .where(
            (t) => !t.isCompleted && t.tagIds.any((id) => tagIds.contains(id)))
        .length;
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'tags',
        'tagIds': tagIds.toList(),
      };
}

class CompletedFilter extends SmartListFilter {
  const CompletedFilter();

  @override
  bool get hasInput => false;

  @override
  List<TaskSection> organize(List<Task> allTasks) {
    final tasks = allTasks.where((t) => t.isCompleted).toList()
      ..sort(_byScheduledDate);
    return [TaskSection(tasks: tasks)];
  }

  @override
  int countTasks(List<Task> allTasks) =>
      allTasks.where((t) => t.isCompleted).length;

  @override
  Map<String, dynamic> toJson() => {'type': 'completed'};
}

class AllTasksFilter extends SmartListFilter {
  const AllTasksFilter();

  @override
  bool get hasInput => false;

  @override
  List<TaskSection> organize(List<Task> allTasks) {
    final pending = allTasks.where((t) => !t.isCompleted).toList()
      ..sort(_byScheduledDate);
    final completed = allTasks.where((t) => t.isCompleted).toList()
      ..sort(_byScheduledDate);

    return [
      TaskSection(tasks: pending),
      if (completed.isNotEmpty)
        TaskSection(header: 'Completed', tasks: completed),
    ];
  }

  @override
  int countTasks(List<Task> allTasks) =>
      allTasks.where((t) => !t.isCompleted).length;

  @override
  Map<String, dynamic> toJson() => {'type': 'all'};
}

// ───── Helper ─────

int _byScheduledDate(Task a, Task b) {
  if (a.scheduledDate == null && b.scheduledDate == null) return 0;
  if (a.scheduledDate == null) return 1;
  if (b.scheduledDate == null) return -1;
  return a.scheduledDate!.compareTo(b.scheduledDate!);
}

// ───── SmartList wrapper ─────

class SmartList {
  String id;
  String name;
  int iconCodePoint;
  int colorValue;
  SmartListFilter filter;

  SmartList({
    required this.id,
    required this.name,
    this.iconCodePoint = 0xe0c8, // Icons.auto_awesome
    this.colorValue = 0xFFAB47BC,
    required this.filter,
  });

  IconData get icon => IconData(iconCodePoint, fontFamily: 'MaterialIcons');
  Color get color => Color(colorValue);

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
        filter:
            SmartListFilter.fromJson(json['filter'] as Map<String, dynamic>),
      );
}

// ───── Hardcoded built-in smart lists ─────

final builtInSmartLists = [
  SmartList(
    id: 'builtin_today',
    name: 'Today',
    iconCodePoint: 0xf06bb, // Icons.today
    colorValue: 0xFF66BB6A,
    filter: const TodayFilter(),
  ),
  SmartList(
    id: 'builtin_tomorrow',
    name: 'Tomorrow',
    iconCodePoint: 0xf0504, // Icons.wb_sunny_outlined
    colorValue: 0xFFFFA726,
    filter: const TomorrowFilter(),
  ),
  SmartList(
    id: 'builtin_upcoming',
    name: 'Upcoming',
    iconCodePoint: 0xf07dc, // Icons.upcoming
    colorValue: 0xFF42A5F5,
    filter: const UpcomingFilter(),
  ),
];

/// IDs of legacy default smart lists to remove on migration.
const _legacySmartListIds = {'smart_today', 'smart_upcoming', 'smart_all'};

/// Remove legacy default smart lists from data (they are now built-in).
void removeLegacySmartLists(List<SmartList> smartLists) {
  smartLists.removeWhere((sl) => _legacySmartListIds.contains(sl.id));
}
