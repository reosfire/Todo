import 'recurrence.dart';

class Task {
  String id;
  String title;
  String notes;
  bool isCompleted;
  DateTime createdAt;
  DateTime? scheduledDate;
  RecurrenceRule? recurrence;
  Set<String> tagIds;
  String listId;
  
  /// Doubly-linked list pointers for task ordering within a list.
  /// The first task in a list has previousTaskId = null.
  /// The last task in a list has nextTaskId = null.
  String? previousTaskId;
  String? nextTaskId;

  /// For recurring tasks: dates on which the task was explicitly completed.
  Set<DateTime> completedDates;

  Task({
    required this.id,
    required this.title,
    this.notes = '',
    this.isCompleted = false,
    required this.createdAt,
    this.scheduledDate,
    this.recurrence,
    Set<String>? tagIds,
    required this.listId,
    this.previousTaskId,
    this.nextTaskId,
    Set<DateTime>? completedDates,
  }) : tagIds = tagIds ?? {},
       completedDates = completedDates ?? {};

  bool isCompletedOn(DateTime date) {
    if (recurrence == null) return isCompleted;
    final d = DateTime(date.year, date.month, date.day);
    return completedDates.any(
      (c) => c.year == d.year && c.month == d.month && c.day == d.day,
    );
  }

  bool occursOn(DateTime date) {
    if (recurrence != null && scheduledDate != null) {
      return recurrence!.occursOn(date, scheduledDate!);
    }
    if (scheduledDate != null) {
      final d = DateTime(date.year, date.month, date.day);
      final s = DateTime(
        scheduledDate!.year,
        scheduledDate!.month,
        scheduledDate!.day,
      );
      return d == s;
    }
    return false;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'notes': notes,
    'isCompleted': isCompleted,
    'createdAt': createdAt.toIso8601String(),
    'scheduledDate': scheduledDate?.toIso8601String(),
    'recurrence': recurrence?.toJson(),
    'tagIds': tagIds.toList(),
    'listId': listId,
    'previousTaskId': previousTaskId,
    'nextTaskId': nextTaskId,
    'completedDates': completedDates.map((d) => d.toIso8601String()).toList(),
  };

  factory Task.fromJson(Map<String, dynamic> json) => Task(
    id: json['id'] as String,
    title: json['title'] as String,
    notes: json['notes'] as String? ?? '',
    isCompleted: json['isCompleted'] as bool? ?? false,
    createdAt: DateTime.parse(json['createdAt'] as String),
    scheduledDate: json['scheduledDate'] != null
        ? DateTime.parse(json['scheduledDate'] as String)
        : null,
    recurrence: json['recurrence'] != null
        ? RecurrenceRule.fromJson(json['recurrence'] as Map<String, dynamic>)
        : null,
    tagIds: (json['tagIds'] as List?)?.map((e) => e as String).toSet() ?? {},
    listId: json['listId'] as String,
    previousTaskId: json['previousTaskId'] as String?,
    nextTaskId: json['nextTaskId'] as String?,
    completedDates:
        (json['completedDates'] as List?)
            ?.map((e) => DateTime.parse(e as String))
            .toSet() ??
        {},
  );
}
