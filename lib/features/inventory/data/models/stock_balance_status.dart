import '../../../warehouses/data/models/warehouse_model.dart';
import 'item_model.dart';
import 'stock_balance_model.dart';

/// رصيد صنف في مخزن مع معلومات التنبيه من إعدادات المخزن.
class StockBalanceStatus {
  const StockBalanceStatus({
    required this.balance,
    required this.warehouse,
    required this.item,
  });

  final StockBalanceModel balance;
  final WarehouseModel warehouse;
  final ItemModel item;

  /// الكمية الحالية بالكراتين.
  int get quantity => balance.currentQuantity;

  /// حد التنبيه المعتمد لهذا المخزن.
  int get minAlertLimit => warehouse.minAlertLimit;

  /// هل الرصيد منخفض (وصل لحد التنبيه أو أقل)؟
  bool get isLowStock => quantity <= minAlertLimit;

  /// هل الرصيد صفر؟
  bool get isOutOfStock => quantity == 0;

  /// كم كرتونًا ينقص للوصول إلى حد التنبيه (صفر إن كان أعلى منه).
  int get shortageToMinimum {
    final int gap = minAlertLimit - quantity;
    return gap > 0 ? gap : 0;
  }

  @override
  String toString() =>
      'StockBalanceStatus(warehouse: ${warehouse.name}, item: ${item.name}, '
      'quantity: $quantity, isLowStock: $isLowStock)';
}
