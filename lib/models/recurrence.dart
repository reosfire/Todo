sealed class RecurrenceRule {
  const RecurrenceRule();

  /// Check whether a given [date] matches this rule, assuming the task
  /// was first scheduled on [startDate].
  bool occursOn(DateTime date, DateTime startDate);

  String describe();

  Map<String, dynamic> toJson();

  factory RecurrenceRule.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    return switch (type) {
      'daily' => DailyRecurrence(),
      'everyNDays' => EveryNDaysRecurrence.fromJson(json),
      'weekly' => WeeklyRecurrence.fromJson(json),
      'monthly' => MonthlyRecurrence.fromJson(json),
      'yearly' => YearlyRecurrence.fromJson(json),
      _ => throw ArgumentError('Unknown recurrence type: $type'),
    };
  }
}

class DailyRecurrence extends RecurrenceRule {
  const DailyRecurrence();

  @override
  bool occursOn(DateTime date, DateTime startDate) {
    final d = DateTime(date.year, date.month, date.day);
    final s = DateTime(startDate.year, startDate.month, startDate.day);
    return !d.isBefore(s);
  }

  @override
  String describe() => 'Every day';

  @override
  Map<String, dynamic> toJson() => {'type': 'daily'};
}

class EveryNDaysRecurrence extends RecurrenceRule {
  final int interval;

  const EveryNDaysRecurrence(this.interval);

  @override
  bool occursOn(DateTime date, DateTime startDate) {
    final d = DateTime(date.year, date.month, date.day);
    final s = DateTime(startDate.year, startDate.month, startDate.day);
    if (d.isBefore(s)) return false;
    return d.difference(s).inDays % interval == 0;
  }

  @override
  String describe() => 'Every $interval days';

  @override
  Map<String, dynamic> toJson() => {'type': 'everyNDays', 'interval': interval};

  factory EveryNDaysRecurrence.fromJson(Map<String, dynamic> json) =>
      EveryNDaysRecurrence(json['interval'] as int);
}

class WeeklyRecurrence extends RecurrenceRule {
  /// Weekday numbers (1=Mon … 7=Sun).
  final Set<int> weekdays;

  const WeeklyRecurrence(this.weekdays);

  @override
  bool occursOn(DateTime date, DateTime startDate) {
    final d = DateTime(date.year, date.month, date.day);
    final s = DateTime(startDate.year, startDate.month, startDate.day);
    if (d.isBefore(s)) return false;
    return weekdays.contains(d.weekday);
  }

  @override
  String describe() {
    const names = {
      1: 'Mon',
      2: 'Tue',
      3: 'Wed',
      4: 'Thu',
      5: 'Fri',
      6: 'Sat',
      7: 'Sun',
    };
    final sorted = weekdays.toList()..sort();
    return 'Every ${sorted.map((w) => names[w]).join(', ')}';
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'weekly',
        'weekdays': weekdays.toList(),
      };

  factory WeeklyRecurrence.fromJson(Map<String, dynamic> json) =>
      WeeklyRecurrence(
        (json['weekdays'] as List).map((e) => e as int).toSet(),
      );
}

class MonthlyRecurrence extends RecurrenceRule {
  /// Day of month (1-31).
  final int dayOfMonth;

  const MonthlyRecurrence(this.dayOfMonth);

  @override
  bool occursOn(DateTime date, DateTime startDate) {
    final d = DateTime(date.year, date.month, date.day);
    final s = DateTime(startDate.year, startDate.month, startDate.day);
    if (d.isBefore(s)) return false;
    return d.day == dayOfMonth;
  }

  @override
  String describe() => 'Monthly on specific day ($dayOfMonth)';

  @override
  Map<String, dynamic> toJson() => {
        'type': 'monthly',
        'dayOfMonth': dayOfMonth,
      };

  factory MonthlyRecurrence.fromJson(Map<String, dynamic> json) =>
      MonthlyRecurrence(json['dayOfMonth'] as int);
}

class YearlyRecurrence extends RecurrenceRule {
  /// Month (1-12).
  final int month;

  /// Day of month (1-31).
  final int dayOfMonth;

  const YearlyRecurrence(this.month, this.dayOfMonth);

  @override
  bool occursOn(DateTime date, DateTime startDate) {
    final d = DateTime(date.year, date.month, date.day);
    final s = DateTime(startDate.year, startDate.month, startDate.day);
    if (d.isBefore(s)) return false;
    return d.month == month && d.day == dayOfMonth;
  }

  @override
  String describe() {
    const monthNames = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return 'Yearly on specific date (${monthNames[month]} $dayOfMonth)';
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'yearly',
        'month': month,
        'dayOfMonth': dayOfMonth,
      };

  factory YearlyRecurrence.fromJson(Map<String, dynamic> json) =>
      YearlyRecurrence(
        json['month'] as int,
        json['dayOfMonth'] as int,
      );
}
