import 'package:flutter/foundation.dart';

import '../../../../core/database/database_exceptions.dart';
import '../../../inventory/presentation/providers/inventory_provider.dart';
import '../../data/models/transaction_model.dart';
import '../../data/transaction_repository.dart';

/// يدير حفظ سندات الاستلام والصرف ويحدّث الأرصدة بعد كل عملية.
class TransactionProvider extends ChangeNotifier {
  TransactionProvider({
    TransactionRepository? repository,
    InventoryProvider? inventoryProvider,
  }) : _repository = repository ?? TransactionRepository(),
       _inventoryProvider = inventoryProvider;

  final TransactionRepository _repository;
  InventoryProvider? _inventoryProvider;

  bool _isSubmitting = false;
  String? _errorMessage;
  TransactionModel? _lastCreatedTransaction;

  List<TransactionModel> _pendingTransactions = <TransactionModel>[];
  bool _isLoadingPending = false;
  bool _hasLoadedPending = false;
  int? _processingTransactionId;

  /// هل يجري حفظ سند الآن؟
  bool get isSubmitting => _isSubmitting;

  /// رسالة خطأ عربية جاهزة للعرض، أو `null`.
  String? get errorMessage => _errorMessage;

  /// آخر سند تم حفظه بنجاح.
  TransactionModel? get lastCreatedTransaction => _lastCreatedTransaction;

  /// السندات المعلقة بانتظار الاعتماد (الأحدث أولًا).
  List<TransactionModel> get pendingTransactions =>
      List<TransactionModel>.unmodifiable(_pendingTransactions);

  /// عدد الطلبات المعلقة بانتظار الاعتماد.
  int get pendingCount => _pendingTransactions.length;

  bool get isLoadingPending => _isLoadingPending;

  /// هل جرى تحميل قائمة الطلبات المعلقة مرة واحدة على الأقل؟
  bool get hasLoadedPending => _hasLoadedPending;

  /// معرّف السند الجاري اعتماده أو رفضه (لتعطيل الأزرار).
  int? get processingTransactionId => _processingTransactionId;

  bool isProcessing(int? transactionId) =>
      transactionId != null && _processingTransactionId == transactionId;

  /// يربط مزوّد المخزون لتحديث الأرصدة تلقائيًا بعد كل سند.
  ///
  /// يُستدعى من `ChangeNotifierProxyProvider` في `main.dart`.
  void attachInventoryProvider(InventoryProvider provider) {
    _inventoryProvider = provider;
  }

  /// يسجّل سند استلام (توريد) من المصنع ويحدّث الأرصدة.
  Future<TransactionModel?> createInboundReceipt({
    required int warehouseId,
    required int quantity,
    String? partyName,
    String? notes,
  }) {
    return _submit(() async {
      final int itemId = _requireItemId();
      return _repository.createInbound(
        warehouseId: warehouseId,
        itemId: itemId,
        quantity: quantity,
        partyName: _clean(partyName),
        notes: _clean(notes),
      );
    });
  }

  /// يسجّل سند صرف لمندوب/موزع ويخصم الكمية من المخزن.
  ///
  /// عند تجاوز الرصيد تُعاد `null` وتُضبط [errorMessage] برسالة عربية
  /// توضح الكمية المتاحة والنقص المطلوب.
  Future<TransactionModel?> createOutboundIssue({
    required int warehouseId,
    required int quantity,
    required String orderReference,
    required String partyName,
    String? vehicleNumber,
    String? notes,
  }) {
    return _submit(() async {
      if (orderReference.trim().isEmpty) {
        throw ArgumentError('رقم أمر الصرف الإداري مطلوب.');
      }
      if (partyName.trim().isEmpty) {
        throw ArgumentError('اسم المندوب أو جهة الصرف مطلوب.');
      }
      final int itemId = _requireItemId();
      return _repository.createOutbound(
        warehouseId: warehouseId,
        itemId: itemId,
        quantity: quantity,
        partyName: partyName.trim(),
        orderReference: orderReference.trim(),
        vehicleNumber: _clean(vehicleNumber),
        notes: _clean(notes),
      );
    });
  }

  /// يسجّل سند إتلاف/هدر ويخصم الكمية التالفة من المخزن.
  ///
  /// السبب واسم المسؤول إلزاميان، ويُعالج نقص الرصيد بنفس أسلوب الصرف.
  Future<TransactionModel?> createDamageVoucher({
    required int warehouseId,
    required int quantity,
    required String reason,
    required String responsibleName,
    String? notes,
  }) {
    return _submit(() async {
      if (reason.trim().isEmpty) {
        throw ArgumentError('سبب الإتلاف مطلوب.');
      }
      if (responsibleName.trim().isEmpty) {
        throw ArgumentError('اسم المسؤول عن الإتلاف مطلوب.');
      }
      final int itemId = _requireItemId();
      return _repository.createDamage(
        warehouseId: warehouseId,
        itemId: itemId,
        quantity: quantity,
        reason: reason.trim(),
        partyName: responsibleName.trim(),
        notes: _clean(notes),
      );
    });
  }

  // ---------------------------------------------------------------------------
  // الطلبات المعلقة ودورة الاعتماد
  // ---------------------------------------------------------------------------

  /// يرفع طلب صرف بدل تالف لمندوب بحالة معلقة (دون خصم الرصيد).
  Future<TransactionModel?> createMarketReplacementRequest({
    required int warehouseId,
    required int quantity,
    required String partyName,
    required String orderReference,
    required String reason,
    String? vehicleNumber,
    String? notes,
  }) {
    return _submit(() async {
      if (orderReference.trim().isEmpty) {
        throw ArgumentError('رقم أمر الصرف الإداري مطلوب.');
      }
      if (partyName.trim().isEmpty) {
        throw ArgumentError('اختر المندوب المستفيد من بدل التالف.');
      }
      if (reason.trim().isEmpty) {
        throw ArgumentError('مبرر بدل التالف مطلوب.');
      }
      final int itemId = _requireItemId();
      return _repository.createPendingMarketReplacement(
        warehouseId: warehouseId,
        itemId: itemId,
        quantity: quantity,
        partyName: partyName.trim(),
        orderReference: orderReference.trim(),
        reason: reason.trim(),
        vehicleNumber: _clean(vehicleNumber),
        notes: _clean(notes),
      );
    }, refreshPending: true);
  }

  /// يرفع محضر إتلاف مخزني داخلي بحالة معلقة (دون خصم الرصيد).
  Future<TransactionModel?> createInternalDamageRequest({
    required int warehouseId,
    required int quantity,
    required String reason,
    required String responsibleName,
    String? notes,
  }) {
    return _submit(() async {
      if (reason.trim().isEmpty) {
        throw ArgumentError('سبب الإتلاف مطلوب.');
      }
      if (responsibleName.trim().isEmpty) {
        throw ArgumentError('اسم أمين المخزن المسؤول مطلوب.');
      }
      final int itemId = _requireItemId();
      return _repository.createPendingInternalDamage(
        warehouseId: warehouseId,
        itemId: itemId,
        quantity: quantity,
        reason: reason.trim(),
        responsibleName: responsibleName.trim(),
        notes: _clean(notes),
      );
    }, refreshPending: true);
  }

  /// يحمّل قائمة الطلبات المعلقة من قاعدة البيانات.
  Future<void> loadPendingApprovals({bool showLoader = true}) async {
    if (showLoader) {
      _isLoadingPending = true;
      notifyListeners();
    }
    try {
      _pendingTransactions = await _repository.getPendingTransactions();
      _hasLoadedPending = true;
    } catch (error) {
      debugPrint('TransactionProvider.loadPendingApprovals: $error');
      _errorMessage = 'تعذر تحميل الطلبات المعلقة. حاول مرة أخرى.';
    } finally {
      _isLoadingPending = false;
      notifyListeners();
    }
  }

  /// يعتمد طلبًا معلقًا فيخصم الكمية من الرصيد ذرّيًا.
  Future<bool> approvePending(TransactionModel transaction) async {
    final int? id = transaction.id;
    if (id == null) {
      _errorMessage = 'لا يمكن اعتماد سند غير محفوظ.';
      notifyListeners();
      return false;
    }
    return _process(id, () async {
      await _repository.approvePendingTransaction(id);
      return true;
    });
  }

  /// يرفض طلبًا معلقًا مع تسجيل سبب الرفض، دون أي مساس بالرصيد.
  Future<bool> rejectPending(
    TransactionModel transaction,
    String reason,
  ) async {
    final int? id = transaction.id;
    if (id == null) {
      _errorMessage = 'لا يمكن رفض سند غير محفوظ.';
      notifyListeners();
      return false;
    }
    if (reason.trim().isEmpty) {
      _errorMessage = 'سبب الرفض مطلوب.';
      notifyListeners();
      return false;
    }
    return _process(id, () async {
      await _repository.rejectPendingTransaction(id, reason.trim());
      return true;
    });
  }

  /// يعاين رقم السند القادم (دون حفظ) لعرضه في رأس الشاشة.
  Future<String> previewVoucherNumber(String transactionType) async {
    try {
      return await _repository.nextVoucherNumber(
        transactionType: transactionType,
      );
    } catch (error) {
      debugPrint('TransactionProvider.previewVoucherNumber: $error');
      return '';
    }
  }

  /// يمسح رسالة الخطأ الحالية.
  void clearError() {
    if (_errorMessage == null) {
      return;
    }
    _errorMessage = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // أدوات داخلية
  // ---------------------------------------------------------------------------

  int _requireItemId() {
    final int? itemId = _inventoryProvider?.item?.id;
    if (itemId == null) {
      throw ArgumentError(
        'لم تُحمَّل بيانات الصنف بعد. حدّث البيانات وحاول مرة أخرى.',
      );
    }
    return itemId;
  }

  String? _clean(String? value) {
    final String? trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  /// ينفّذ اعتمادًا أو رفضًا مع تعطيل أزرار السند الجاري ومعالجة الأخطاء.
  Future<bool> _process(
    int transactionId,
    Future<bool> Function() action,
  ) async {
    _processingTransactionId = transactionId;
    _errorMessage = null;
    notifyListeners();

    try {
      final bool succeeded = await action();
      return succeeded;
    } on InsufficientStockException catch (error) {
      _errorMessage =
          'الرصيد غير كافٍ للاعتماد: المطلوب ${error.requestedQuantity} '
          'كرتون والمتاح ${error.availableQuantity} كرتون '
          '(النقص ${error.shortage} كرتون).';
      return false;
    } on ArgumentError catch (error) {
      _errorMessage = error.message?.toString() ?? 'تعذر تنفيذ العملية.';
      return false;
    } catch (error) {
      debugPrint('TransactionProvider.process: $error');
      _errorMessage = 'تعذر تنفيذ العملية. حاول مرة أخرى.';
      return false;
    } finally {
      _processingTransactionId = null;
      // تحديث الأرصدة وقائمة الطلبات بعد أي تغيير في الحالة.
      await _inventoryProvider?.refresh();
      try {
        _pendingTransactions = await _repository.getPendingTransactions();
        _hasLoadedPending = true;
      } catch (error) {
        debugPrint('TransactionProvider.process pending reload: $error');
      }
      notifyListeners();
    }
  }

  Future<TransactionModel?> _submit(
    Future<TransactionModel> Function() action, {
    bool refreshPending = false,
  }) async {
    _isSubmitting = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final TransactionModel transaction = await action();
      _lastCreatedTransaction = transaction;
      // تحديث الأرصدة والتنبيهات في كل الشاشات فورًا.
      await _inventoryProvider?.refresh();
      if (refreshPending) {
        try {
          _pendingTransactions = await _repository.getPendingTransactions();
          _hasLoadedPending = true;
        } catch (error) {
          debugPrint('TransactionProvider.submit pending reload: $error');
        }
      }
      return transaction;
    } on InsufficientStockException catch (error) {
      _errorMessage =
          'الكمية المطلوبة تتجاوز الرصيد المتوفر في المخزن بمقدار '
          '${error.shortage} كرتون. المتاح حاليًا: '
          '${error.availableQuantity} كرتون.';
      return null;
    } on ArgumentError catch (error) {
      _errorMessage = error.message?.toString() ?? 'بيانات السند غير صحيحة.';
      return null;
    } catch (error) {
      debugPrint('TransactionProvider.submit: $error');
      _errorMessage = 'تعذر حفظ السند. حاول مرة أخرى.';
      return null;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }
}
