import 'package:flutter/foundation.dart';

import '../../data/inventory_repository.dart';
import '../../data/models/item_model.dart';
import '../../data/models/stock_balance_status.dart';

/// يدير أرصدة الصنف في كل المخازن ويوفّر الإجماليات والتنبيهات للواجهات.
class InventoryProvider extends ChangeNotifier {
  InventoryProvider({InventoryRepository? repository})
    : _repository = repository ?? InventoryRepository();

  final InventoryRepository _repository;

  List<StockBalanceStatus> _statuses = <StockBalanceStatus>[];
  ItemModel? _item;
  bool _isLoading = false;
  String? _errorMessage;

  /// أرصدة الصنف في كل المخازن.
  List<StockBalanceStatus> get statuses =>
      List<StockBalanceStatus>.unmodifiable(_statuses);

  /// بيانات الصنف الأساسي (كرتون ماء رواء).
  ItemModel? get item => _item;

  bool get isLoading => _isLoading;

  String? get errorMessage => _errorMessage;

  /// إجمالي الكراتين في جميع المخازن.
  int get totalCartons => _statuses.fold<int>(
    0,
    (int sum, StockBalanceStatus s) => sum + s.quantity,
  );

  /// عدد المخازن النشطة التي لها رصيد مسجّل.
  int get activeWarehousesCount =>
      _statuses.where((StockBalanceStatus s) => s.warehouse.isActive).length;

  /// المخازن النشطة التي وصل رصيدها إلى حد التنبيه أو أقل.
  List<StockBalanceStatus> get lowStockWarehouses => _statuses
      .where((StockBalanceStatus s) => s.warehouse.isActive && s.isLowStock)
      .toList(growable: false);

  /// هل يوجد أي مخزن برصيد منخفض؟
  bool get hasLowStockAlert => lowStockWarehouses.isNotEmpty;

  /// عدد المخازن المنخفضة (للعرض في الشريط التحذيري والبطاقات).
  int get lowStockCount => lowStockWarehouses.length;

  /// عدد المخازن النشطة النافدة تمامًا (رصيد صفر).
  int get outOfStockCount => _statuses
      .where((StockBalanceStatus s) => s.warehouse.isActive && s.isOutOfStock)
      .length;

  /// رصيد مخزن محدد من البيانات المحمّلة.
  StockBalanceStatus? statusFor(int warehouseId) {
    for (final StockBalanceStatus status in _statuses) {
      if (status.balance.warehouseId == warehouseId) {
        return status;
      }
    }
    return null;
  }

  /// كمية مخزن محدد بالكرتون من البيانات المحمّلة (صفر إن لم يوجد).
  int quantityFor(int warehouseId) => statusFor(warehouseId)?.quantity ?? 0;

  /// يحمّل أرصدة كل المخازن وبيانات الصنف.
  Future<void> loadInventoryStatus({bool showLoader = true}) async {
    if (showLoader) {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
    }
    try {
      final List<StockBalanceStatus> statuses = await _repository
          .listBalances();
      _statuses = statuses;
      _item = statuses.isNotEmpty
          ? statuses.first.item
          : await _repository.getPrimaryItem();
      _errorMessage = null;
    } catch (error) {
      debugPrint('InventoryProvider.loadInventoryStatus: $error');
      _errorMessage = 'تعذر تحميل أرصدة المخزون. حاول مرة أخرى.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// تحديث سريع دون إظهار مؤشر تحميل كامل.
  Future<void> refresh() => loadInventoryStatus(showLoader: false);

  /// يقرأ رصيد مخزن مباشرة من قاعدة البيانات (بالكرتون).
  Future<int> fetchWarehouseQuantity(int warehouseId, {int? itemId}) async {
    final int? resolvedItemId = itemId ?? _item?.id;
    if (resolvedItemId == null) {
      return 0;
    }
    try {
      return await _repository.currentQuantity(
        warehouseId: warehouseId,
        itemId: resolvedItemId,
      );
    } catch (error) {
      debugPrint('InventoryProvider.fetchWarehouseQuantity: $error');
      return 0;
    }
  }
}
