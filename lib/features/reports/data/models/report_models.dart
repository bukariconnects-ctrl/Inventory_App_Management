/// نماذج مشتركة بين مستودع الحركات وشاشات السجل والتقارير.
library;

/// نطاق زمني مغلق (يشمل يوم النهاية كاملًا عند الاستعلام).
class DateRange {
  const DateRange({required this.start, required this.end});

  /// يوم واحد.
  factory DateRange.day(DateTime day) {
    final DateTime date = DateTime(day.year, day.month, day.day);
    return DateRange(start: date, end: date);
  }

  /// آخر [days] أيام بما فيها اليوم.
  factory DateRange.lastDays(int days, {DateTime? now}) {
    final DateTime today = DateTime(
      (now ?? DateTime.now()).year,
      (now ?? DateTime.now()).month,
      (now ?? DateTime.now()).day,
    );
    return DateRange(
      start: today.subtract(Duration(days: days - 1)),
      end: today,
    );
  }

  /// الشهر الحالي كاملًا.
  factory DateRange.thisMonth({DateTime? now}) {
    final DateTime date = now ?? DateTime.now();
    return DateRange(
      start: DateTime(date.year, date.month),
      end: DateTime(date.year, date.month + 1, 0),
    );
  }

  /// أول يوم في النطاق (00:00).
  final DateTime start;

  /// آخر يوم في النطاق (يُستخدم مع [endOfDay] في الاستعلام).
  final DateTime end;

  /// نهاية يوم النهاية بالمللي ثانية، ليشمل كل حركات ذلك اليوم.
  DateTime get endOfDay =>
      DateTime(end.year, end.month, end.day, 23, 59, 59, 999);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is DateRange && other.start == start && other.end == end;
  }

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'DateRange($start → $end)';
}

/// مقاييس حركة المخزون خلال فترة ومخزن محددين.
class PeriodSummaryMetrics {
  const PeriodSummaryMetrics({
    required this.totalInbound,
    required this.totalOutbound,
    required this.totalDamaged,
    required this.voucherCount,
  });

  static const PeriodSummaryMetrics empty = PeriodSummaryMetrics(
    totalInbound: 0,
    totalOutbound: 0,
    totalDamaged: 0,
    voucherCount: 0,
  );

  /// إجمالي الكراتين الواردة (استلام).
  final int totalInbound;

  /// إجمالي الكراتين المصروفة (صرف).
  final int totalOutbound;

  /// إجمالي الكراتين التالفة (إتلاف).
  final int totalDamaged;

  /// عدد السندات المشمولة في الفترة.
  final int voucherCount;

  /// صافي التغير = الوارد − المنصرف − التالف.
  int get netChange => totalInbound - totalOutbound - totalDamaged;

  /// هل الفترة بلا حركات؟
  bool get isEmpty => voucherCount == 0;

  @override
  String toString() =>
      'PeriodSummaryMetrics(inbound: $totalInbound, outbound: $totalOutbound, '
      'damaged: $totalDamaged, vouchers: $voucherCount)';
}

/// إجمالي مسحوبات مندوب/موزّع خلال الفترة.
class RepresentativeSummary {
  const RepresentativeSummary({
    required this.name,
    required this.totalQuantity,
    required this.voucherCount,
  });

  final String name;

  /// مجموع الكراتين المصروفة له.
  final int totalQuantity;

  /// عدد سندات الصرف الخاصة به.
  final int voucherCount;

  /// نسبة مسحوباته من إجمالي الصرف في الفترة (0.0 – 1.0).
  double shareOf(int totalOutbound) {
    if (totalOutbound <= 0) {
      return 0;
    }
    return totalQuantity / totalOutbound;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is RepresentativeSummary &&
        other.name == name &&
        other.totalQuantity == totalQuantity &&
        other.voucherCount == voucherCount;
  }

  @override
  int get hashCode => Object.hash(name, totalQuantity, voucherCount);

  @override
  String toString() =>
      'RepresentativeSummary($name, totalQuantity: $totalQuantity, '
      'voucherCount: $voucherCount)';
}
