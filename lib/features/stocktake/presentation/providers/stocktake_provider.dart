import 'package:flutter/foundation.dart';

import '../../../inventory/presentation/providers/inventory_provider.dart';
import '../../../transactions/data/models/transaction_model.dart';
import '../../../transactions/data/transaction_repository.dart';
import '../../data/models/stocktake_model.dart';

/// يدير جرد المخازن: حفظ التسويات وتحميل سجل الجرد السابق.
class StocktakeProvider extends ChangeNotifier {
  StocktakeProvider({
    TransactionRepository? repository,
    InventoryProvider? inventoryProvider,
  }) : _repository = repository ?? TransactionRepository(),
       _inventoryProvider = inventoryProvider;

  final TransactionRepository _repository;
  InventoryProvider? _inventoryProvider;

  List<StocktakeModel> _stocktakesHistory = <StocktakeModel>[];
  bool _isLoading = false;
  bool _isSubmitting = false;
  String? _errorMessage;
  StocktakeModel? _lastStocktake;

  /// سجل عمليات الجرد للمخزن المحدد (الأحدث أولًا).
  List<StocktakeModel> get stocktakesHistory =>
      List<StocktakeModel>.unmodifiable(_stocktakesHistory);

  bool get isLoading => _isLoading;
  bool get isSubmitting => _isSubmitting;
  String? get errorMessage => _errorMessage;

  /// آخر جرد تم اعتماده بنجاح.
  StocktakeModel? get lastStocktake => _lastStocktake;

  /// يربط مزوّد المخزون لتحديث الأرصدة تلقائيًا بعد التسوية.
  void attachInventoryProvider(InventoryProvider provider) {
    _inventoryProvider = provider;
  }

  /// يحمّل سجل الجرد السابق لمخزن محدد.
  Future<void> loadWarehouseStocktakes(int warehouseId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _stocktakesHistory = await _repository.listStocktakes(
        warehouseId: warehouseId,
      );
    } catch (error) {
      debugPrint('StocktakeProvider.loadWarehouseStocktakes: $error');
      _errorMessage = 'تعذر تحميل سجل الجرد. حاول مرة أخرى.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// يعتمد جردًا فعليًا: يسجل السجل، ينشئ حركة التسوية، ويطابق الرصيد الفعلي.
  ///
  /// يعيد `null` مع ضبط [errorMessage] عند فشل التحقق أو الحفظ.
  Future<StocktakeModel?> performStocktake({
    required int warehouseId,
    required int actualQuantity,
    String? notes,
  }) async {
    if (actualQuantity < 0) {
      _errorMessage = 'الكمية الفعلية لا يمكن أن تكون سالبة.';
      notifyListeners();
      return null;
    }

    final int? itemId = _inventoryProvider?.item?.id;
    if (itemId == null) {
      _errorMessage =
          'لم تُحمَّل بيانات الصنف بعد. حدّث البيانات وحاول مرة أخرى.';
      notifyListeners();
      return null;
    }

    final int systemQuantity =
        _inventoryProvider?.quantityFor(warehouseId) ?? 0;
    final int difference = actualQuantity - systemQuantity;
    final String? cleanNotes = (notes == null || notes.trim().isEmpty)
        ? null
        : notes.trim();

    if (difference != 0 && cleanNotes == null) {
      _errorMessage = 'يجب إدخال ملاحظات وتبرير الفارق قبل اعتماد التسوية.';
      notifyListeners();
      return null;
    }

    _isSubmitting = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final StocktakeModel stocktake = await _repository.adjustStocktake(
        warehouseId: warehouseId,
        itemId: itemId,
        actualQuantity: actualQuantity,
        notes: cleanNotes,
      );
      _lastStocktake = stocktake;
      await _inventoryProvider?.refresh();
      await loadWarehouseStocktakes(warehouseId);
      return stocktake;
    } catch (error) {
      debugPrint('StocktakeProvider.performStocktake: $error');
      _errorMessage = 'تعذر اعتماد الجرد. حاول مرة أخرى.';
      return null;
    } finally {
      _isSubmitting = false;
      notifyListeners();
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

  /// نوع الحركة الناتجة عن التسوية (للاستخدام في العروض).
  static String get adjustmentType => TransactionTypes.adjustment;
}
