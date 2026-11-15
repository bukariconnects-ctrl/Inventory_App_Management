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

  /// هل يجري حفظ سند الآن؟
  bool get isSubmitting => _isSubmitting;

  /// رسالة خطأ عربية جاهزة للعرض، أو `null`.
  String? get errorMessage => _errorMessage;

  /// آخر سند تم حفظه بنجاح.
  TransactionModel? get lastCreatedTransaction => _lastCreatedTransaction;

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

  Future<TransactionModel?> _submit(
    Future<TransactionModel> Function() action,
  ) async {
    _isSubmitting = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final TransactionModel transaction = await action();
      _lastCreatedTransaction = transaction;
      // تحديث الأرصدة والتنبيهات في كل الشاشات فورًا.
      await _inventoryProvider?.refresh();
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
