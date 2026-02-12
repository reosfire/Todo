enum RecurrenceType {
  everyNDays,
  weekday, // specific day(s) of the week
  monthDay, // specific day of the month
  yearDay, // specific month+day of the year
}

class RecurrenceRule {
  final RecurrenceType type;

  /// For [everyNDays]: interval in days (1 = every day).
  final int interval;

  /// For [weekday]: set of weekday numbers (1=Mon … 7=Sun).
  final Set<int> weekdays;

  /// For [monthDay]: day of month (1-31).
  final int? monthDay;

  /// For [yearDay]: month (1-12).
  final int? yearMonth;

  /// For [yearDay]: day of month (1-31).
  final int? yearDayOfMonth;

  const RecurrenceRule({
    required this.type,
    this.interval = 1,
    this.weekdays = const {},
    this.monthDay,
    this.yearMonth,
    this.yearDayOfMonth,
  });

  /// Every day shortcut.
  factory RecurrenceRule.daily() =>
      const RecurrenceRule(type: RecurrenceType.everyNDays, interval: 1);

  /// Every N days.
  factory RecurrenceRule.everyNDays(int n) =>
      RecurrenceRule(type: RecurrenceType.everyNDays, interval: n);

  /// Specific weekdays (e.g. Mon, Wed, Fri).
  factory RecurrenceRule.weekly(Set<int> weekdays) =>
      RecurrenceRule(type: RecurrenceType.weekday, weekdays: weekdays);

  /// Same day each month.
  factory RecurrenceRule.monthly(int day) =>
      RecurrenceRule(type: RecurrenceType.monthDay, monthDay: day);

  /// Same date each year.
  factory RecurrenceRule.yearly(int month, int day) => RecurrenceRule(
    type: RecurrenceType.yearDay,
    yearMonth: month,
    yearDayOfMonth: day,
  );

  /// Check whether a given [date] matches this rule, assuming the task
  /// was first scheduled on [startDate].
  bool occursOn(DateTime date, DateTime startDate) {
    final d = DateTime(date.year, date.month, date.day);
    final s = DateTime(startDate.year, startDate.month, startDate.day);
    if (d.isBefore(s)) return false;

    switch (type) {
      case RecurrenceType.everyNDays:
        return d.difference(s).inDays % interval == 0;
      case RecurrenceType.weekday:
        return weekdays.contains(d.weekday);
      case RecurrenceType.monthDay:
        return d.day == monthDay;
      case RecurrenceType.yearDay:
        return d.month == yearMonth && d.day == yearDayOfMonth;
    }
  }

  Map<String, dynamic> toJson() => {
    'type': type.index,
    'interval': interval,
    'weekdays': weekdays.toList(),
    'monthDay': monthDay,
    'yearMonth': yearMonth,
    'yearDayOfMonth': yearDayOfMonth,
  };

  factory RecurrenceRule.fromJson(Map<String, dynamic> json) => RecurrenceRule(
    type: RecurrenceType.values[json['type'] as int],
    interval: json['interval'] as int? ?? 1,
    weekdays:
        (json['weekdays'] as List?)?.map((e) => e as int).toSet() ?? const {},
    monthDay: json['monthDay'] as int?,
    yearMonth: json['yearMonth'] as int?,
    yearDayOfMonth: json['yearDayOfMonth'] as int?,
  );

  String describe() {
    switch (type) {
      case RecurrenceType.everyNDays:
        if (interval == 1) return 'Every day';
        return 'Every $interval days';
      case RecurrenceType.weekday:
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
      case RecurrenceType.monthDay:
        return 'Monthly on day $monthDay';
      case RecurrenceType.yearDay:
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
        return 'Yearly on ${monthNames[yearMonth!]} $yearDayOfMonth';
    }
  }
}
