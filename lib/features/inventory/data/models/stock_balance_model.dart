/// رصيد صنف داخل مخزن محدد (صف واحد لكل مخزن وصنف).
class StockBalanceModel {
  const StockBalanceModel({
    this.id,
    required this.warehouseId,
    required this.itemId,
    required this.currentQuantity,
    required this.lastUpdated,
  });

  /// يقرأ الرصيد من صف قاعدة البيانات.
  factory StockBalanceModel.fromMap(Map<String, Object?> map) {
    return StockBalanceModel(
      id: map['id'] as int?,
      warehouseId: map['warehouse_id'] as int? ?? 0,
      itemId: map['item_id'] as int? ?? 0,
      currentQuantity: map['current_quantity'] as int? ?? 0,
      lastUpdated:
          DateTime.tryParse(map['last_updated'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  final int? id;
  final int warehouseId;
  final int itemId;

  /// الكمية الحالية بالكراتين.
  final int currentQuantity;
  final DateTime lastUpdated;

  /// يحوّل الرصيد إلى صف قاعدة بيانات.
  Map<String, Object?> toMap({bool includeId = false}) {
    return <String, Object?>{
      if (includeId && id != null) 'id': id,
      'warehouse_id': warehouseId,
      'item_id': itemId,
      'current_quantity': currentQuantity,
      'last_updated': lastUpdated.toIso8601String(),
    };
  }

  StockBalanceModel copyWith({
    int? id,
    int? warehouseId,
    int? itemId,
    int? currentQuantity,
    DateTime? lastUpdated,
  }) {
    return StockBalanceModel(
      id: id ?? this.id,
      warehouseId: warehouseId ?? this.warehouseId,
      itemId: itemId ?? this.itemId,
      currentQuantity: currentQuantity ?? this.currentQuantity,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is StockBalanceModel &&
        other.id == id &&
        other.warehouseId == warehouseId &&
        other.itemId == itemId &&
        other.currentQuantity == currentQuantity &&
        other.lastUpdated == lastUpdated;
  }

  @override
  int get hashCode =>
      Object.hash(id, warehouseId, itemId, currentQuantity, lastUpdated);

  @override
  String toString() =>
      'StockBalanceModel(warehouseId: $warehouseId, itemId: $itemId, '
      'currentQuantity: $currentQuantity)';
}
