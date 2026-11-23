/// نماذج مشتركة بين مستودع الحركات وشاشات السجل والتقارير.
library;

import '../../../transactions/data/models/transaction_model.dart';

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

/// كشف مسحوبات مندوب/موزّع خلال فترة: كل سندات الصرف وبدل التالف المعتمدة.
class RepresentativeLedger {
  const RepresentativeLedger({
    required this.representativeName,
    required this.startDate,
    required this.endDate,
    required this.transactions,
    this.warehouseId,
  });

  /// اسم المندوب كما هو محفوظ في السندات (`party_name`).
  final String representativeName;

  /// أول يوم في الكشف (00:00).
  final DateTime startDate;

  /// آخر يوم في الكشف (يُستعلم عنه بنهاية اليوم).
  final DateTime endDate;

  /// السندات المعتمدة مرتبة زمنيًا من الأقدم إلى الأحدث.
  final List<TransactionModel> transactions;

  /// المخزن المحدد في الكشف، أو `null` عند شمول كل المخازن.
  final int? warehouseId;

  /// إجمالي الكراتين المنصرفة (صرف عادي + بدل تالف).
  int get totalCartons => transactions.fold<int>(
    0,
    (int sum, TransactionModel t) => sum + t.quantity.abs(),
  );

  /// عدد السندات المشمولة في الكشف.
  int get voucherCount => transactions.length;

  /// عدد سندات الصرف العادي.
  int get outboundCount => transactions
      .where(
        (TransactionModel t) => t.transactionType == TransactionTypes.outbound,
      )
      .length;

  /// عدد سندات بدل التالف.
  int get replacementCount => transactions
      .where(
        (TransactionModel t) =>
            t.transactionType == TransactionTypes.marketReplacement,
      )
      .length;

  /// هل الكشف بلا حركات؟
  bool get isEmpty => transactions.isEmpty;

  @override
  String toString() =>
      'RepresentativeLedger($representativeName, cartons: $totalCartons, '
      'vouchers: $voucherCount)';
}

/// اليومية المخزنية الشاملة ليوم واحد: الحركات وأرصدة بداية ونهاية اليوم.
class DailyJournalReport {
  const DailyJournalReport({
    required this.date,
    required this.transactions,
    required this.openingBalance,
    required this.closingBalance,
    this.warehouseId,
  });

  /// اليوم المخزني (00:00).
  final DateTime date;

  /// كل الحركات المعتمدة في اليوم مرتبة زمنيًا.
  final List<TransactionModel> transactions;

  /// رصيد بداية اليوم (كراتين).
  final int openingBalance;

  /// رصيد نهاية اليوم الصافي (كراتين).
  final int closingBalance;

  /// المخزن المحدد، أو `null` عند شمول كل المخازن.
  final int? warehouseId;

  /// حركات الاستلام من المصنع.
  List<TransactionModel> get inboundTransactions =>
      _ofType(TransactionTypes.inbound);

  /// حركات الصرف للمناديب.
  List<TransactionModel> get outboundTransactions =>
      _ofType(TransactionTypes.outbound);

  /// حركات بدل التالف المعتمدة.
  List<TransactionModel> get replacementTransactions =>
      _ofType(TransactionTypes.marketReplacement);

  /// محاضر الإتلاف المخزني المعتمدة.
  List<TransactionModel> get damageTransactions =>
      _ofType(TransactionTypes.damage);

  /// حركات تسوية الجرد.
  List<TransactionModel> get adjustmentTransactions =>
      _ofType(TransactionTypes.adjustment);

  /// إجمالي الكراتين الواردة.
  int get inboundCartons => _absoluteTotal(TransactionTypes.inbound);

  /// إجمالي الكراتين المنصرفة.
  int get outboundCartons => _absoluteTotal(TransactionTypes.outbound);

  /// إجمالي كراتين بدل التالف.
  int get replacementCartons =>
      _absoluteTotal(TransactionTypes.marketReplacement);

  /// إجمالي الكراتين المتلفة.
  int get damagedCartons => _absoluteTotal(TransactionTypes.damage);

  /// صافي أثر تسويات الجرد (موجب للفائض وسالب للعجز).
  int get adjustmentCartons => adjustmentTransactions.fold<int>(
    0,
    (int sum, TransactionModel t) => sum + t.quantity,
  );

  /// إجمالي التالف والبدل (كراتين).
  int get damagedAndReplacementCartons => damagedCartons + replacementCartons;

  /// صافي حركة اليوم = الوارد − المنصرف − التالف والبدل + صافي التسويات.
  int get netChange =>
      inboundCartons -
      outboundCartons -
      damagedAndReplacementCartons +
      adjustmentCartons;

  /// عدد السندات المنفذة خلال اليوم.
  int get voucherCount => transactions.length;

  /// هل اليوم بلا حركات؟
  bool get isEmpty => transactions.isEmpty;

  List<TransactionModel> _ofType(String type) => transactions
      .where((TransactionModel t) => t.transactionType == type)
      .toList(growable: false);

  int _absoluteTotal(String type) => _ofType(
    type,
  ).fold<int>(0, (int sum, TransactionModel t) => sum + t.quantity.abs());

  @override
  String toString() =>
      'DailyJournalReport($date, vouchers: $voucherCount, '
      'opening: $openingBalance, closing: $closingBalance)';
}
