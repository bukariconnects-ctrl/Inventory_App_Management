import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../transactions/data/models/transaction_model.dart';
import '../../../transactions/data/transaction_repository.dart';
import '../../../transactions/presentation/providers/transaction_provider.dart';
import '../../data/models/report_models.dart';

/// يدير سجل الحركات المفلتر، مقاييس الفترة، ومسحوبات المناديب.
class ReportsProvider extends ChangeNotifier {
  ReportsProvider({TransactionRepository? repository})
    : _repository = repository ?? TransactionRepository();

  /// أقصى عدد حركات محمّل في الأرشيف دفعة واحدة.
  static const int archivePageSize = 300;

  final TransactionRepository _repository;

  TransactionProvider? _transactionProvider;
  int? _lastSeenTransactionId;

  List<TransactionModel> _transactions = <TransactionModel>[];
  List<RepresentativeSummary> _representatives = <RepresentativeSummary>[];
  PeriodSummaryMetrics _metrics = PeriodSummaryMetrics.empty;

  int? _warehouseId;
  String? _transactionType;
  DateRange? _dateRange;
  String _searchQuery = '';

  bool _isLoading = false;
  String? _errorMessage;
  int _requestId = 0;

  // ---------------------------------------------------------------------------
  // الحالة المقروءة
  // ---------------------------------------------------------------------------

  /// الحركات المطابقة للفلاتر (الأحدث أولًا).
  List<TransactionModel> get transactions =>
      List<TransactionModel>.unmodifiable(_transactions);

  /// المناديب الأكثر سحبًا خلال نفس الفترة.
  List<RepresentativeSummary> get representatives =>
      List<RepresentativeSummary>.unmodifiable(_representatives);

  /// مقاييس الفترة الحالية.
  PeriodSummaryMetrics get metrics => _metrics;

  int? get warehouseId => _warehouseId;
  String? get transactionType => _transactionType;
  DateRange? get dateRange => _dateRange;
  String get searchQuery => _searchQuery;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// هل هناك أي فلتر مطبّق غير «الكل»؟
  bool get hasActiveFilters =>
      _warehouseId != null ||
      _transactionType != null ||
      _dateRange != null ||
      _searchQuery.trim().isNotEmpty;

  /// عدد الفلاتر المطبقة (لشارة زر التصفية المتقدمة).
  int get activeFiltersCount {
    int count = 0;
    if (_warehouseId != null) {
      count++;
    }
    if (_transactionType != null) {
      count++;
    }
    if (_dateRange != null) {
      count++;
    }
    if (_searchQuery.trim().isNotEmpty) {
      count++;
    }
    return count;
  }

  // ---------------------------------------------------------------------------
  // الربط بالحركات
  // ---------------------------------------------------------------------------

  /// يعيد تحميل التقارير تلقائيًا فور حفظ أي سند جديد.
  ///
  /// يُستدعى من `ChangeNotifierProxyProvider` في `main.dart`.
  void attachTransactionProvider(TransactionProvider provider) {
    if (identical(_transactionProvider, provider)) {
      return;
    }
    _transactionProvider?.removeListener(_handleTransactionsChanged);
    _transactionProvider = provider..addListener(_handleTransactionsChanged);
    _lastSeenTransactionId = provider.lastCreatedTransaction?.id;
  }

  void _handleTransactionsChanged() {
    final TransactionModel? latest =
        _transactionProvider?.lastCreatedTransaction;
    if (latest == null || latest.id == _lastSeenTransactionId) {
      return;
    }
    _lastSeenTransactionId = latest.id;
    unawaited(loadReportsData(showLoader: false));
  }

  @override
  void dispose() {
    _transactionProvider?.removeListener(_handleTransactionsChanged);
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // الفلاتر
  // ---------------------------------------------------------------------------

  /// يطبّق مجموعة فلاتر كاملة (أي قيمة `null` تعني إلغاء ذلك الفلتر).
  Future<void> applyFilters({
    int? warehouseId,
    String? transactionType,
    DateRange? dateRange,
    String? searchQuery,
  }) {
    _warehouseId = warehouseId;
    _transactionType = transactionType;
    _dateRange = dateRange;
    _searchQuery = searchQuery?.trim() ?? '';
    return loadReportsData(showLoader: false);
  }

  Future<void> setWarehouseFilter(int? warehouseId) {
    if (_warehouseId == warehouseId) {
      return Future<void>.value();
    }
    _warehouseId = warehouseId;
    return loadReportsData(showLoader: false);
  }

  Future<void> setTypeFilter(String? transactionType) {
    if (_transactionType == transactionType) {
      return Future<void>.value();
    }
    _transactionType = transactionType;
    return loadReportsData(showLoader: false);
  }

  Future<void> setDateRange(DateRange? dateRange) {
    _dateRange = dateRange;
    return loadReportsData(showLoader: false);
  }

  Future<void> setSearchQuery(String query) {
    _searchQuery = query.trim();
    return loadReportsData(showLoader: false);
  }

  Future<void> clearFilters() {
    _warehouseId = null;
    _transactionType = null;
    _dateRange = null;
    _searchQuery = '';
    return loadReportsData(showLoader: false);
  }

  // ---------------------------------------------------------------------------
  // التحميل
  // ---------------------------------------------------------------------------

  /// يحمّل الحركات والمقاييس والمناديب وفق الفلاتر الحالية.
  Future<void> loadReportsData({bool showLoader = true}) async {
    final int requestId = ++_requestId;
    if (showLoader) {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
    }

    try {
      final DateTime? start = _dateRange?.start;
      final DateTime? end = _dateRange?.endOfDay;

      final List<Object?> results =
          await Future.wait<Object?>(<Future<Object?>>[
            _repository.filterTransactions(
              warehouseId: _warehouseId,
              transactionType: _transactionType,
              startDate: start,
              endDate: end,
              searchQuery: _searchQuery,
              limit: archivePageSize,
            ),
            _repository.getPeriodSummaryMetrics(
              warehouseId: _warehouseId,
              startDate: start,
              endDate: end,
            ),
            _repository.getTopRepresentatives(
              warehouseId: _warehouseId,
              startDate: start,
              endDate: end,
            ),
          ]);

      if (requestId != _requestId) {
        return;
      }

      _transactions = results[0]! as List<TransactionModel>;
      _metrics = results[1]! as PeriodSummaryMetrics;
      _representatives = results[2]! as List<RepresentativeSummary>;
      _errorMessage = null;
    } catch (error) {
      if (requestId != _requestId) {
        return;
      }
      debugPrint('ReportsProvider.loadReportsData: $error');
      _errorMessage = 'تعذر تحميل السجل والتقارير. حاول مرة أخرى.';
    } finally {
      if (requestId == _requestId) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// تحديث سريع دون شاشة تحميل كاملة.
  Future<void> refresh() => loadReportsData(showLoader: false);
}
