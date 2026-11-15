/// سجل جرد واحد: يوثّق الرصيد الدفتري والفعلي والفرق بينهما.
class StocktakeModel {
  const StocktakeModel({
    this.id,
    required this.warehouseId,
    required this.itemId,
    required this.systemQuantity,
    required this.actualQuantity,
    required this.difference,
    this.notes,
    required this.createdAt,
  });

  /// يقرأ سجل الجرد من صف قاعدة البيانات.
  factory StocktakeModel.fromMap(Map<String, Object?> map) {
    return StocktakeModel(
      id: map['id'] as int?,
      warehouseId: map['warehouse_id'] as int? ?? 0,
      itemId: map['item_id'] as int? ?? 0,
      systemQuantity: map['system_quantity'] as int? ?? 0,
      actualQuantity: map['actual_quantity'] as int? ?? 0,
      difference: map['difference'] as int? ?? 0,
      notes: map['notes'] as String?,
      createdAt:
          DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  final int? id;
  final int warehouseId;
  final int itemId;

  /// الرصيد الدفتري في النظام قبل الجرد.
  final int systemQuantity;

  /// الرصيد الفعلي المعدود على أرض الواقع.
  final int actualQuantity;

  /// الفرق = الرصيد الفعلي - الرصيد الدفتري (سالب يعني عجزًا).
  final int difference;
  final String? notes;
  final DateTime createdAt;

  /// هل يوجد فرق يستوجب تسوية؟
  bool get hasDifference => difference != 0;

  /// هل الفرق عجز (نقص في الواقع عن الدفتري)؟
  bool get isShortage => difference < 0;

  /// يحوّل سجل الجرد إلى صف قاعدة بيانات.
  Map<String, Object?> toMap({bool includeId = false}) {
    return <String, Object?>{
      if (includeId && id != null) 'id': id,
      'warehouse_id': warehouseId,
      'item_id': itemId,
      'system_quantity': systemQuantity,
      'actual_quantity': actualQuantity,
      'difference': difference,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
    };
  }

  StocktakeModel copyWith({
    int? id,
    int? warehouseId,
    int? itemId,
    int? systemQuantity,
    int? actualQuantity,
    int? difference,
    String? notes,
    DateTime? createdAt,
  }) {
    return StocktakeModel(
      id: id ?? this.id,
      warehouseId: warehouseId ?? this.warehouseId,
      itemId: itemId ?? this.itemId,
      systemQuantity: systemQuantity ?? this.systemQuantity,
      actualQuantity: actualQuantity ?? this.actualQuantity,
      difference: difference ?? this.difference,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is StocktakeModel &&
        other.id == id &&
        other.warehouseId == warehouseId &&
        other.itemId == itemId &&
        other.systemQuantity == systemQuantity &&
        other.actualQuantity == actualQuantity &&
        other.difference == difference &&
        other.notes == notes &&
        other.createdAt == createdAt;
  }

  @override
  int get hashCode => Object.hash(
    id,
    warehouseId,
    itemId,
    systemQuantity,
    actualQuantity,
    difference,
    notes,
    createdAt,
  );

  @override
  String toString() =>
      'StocktakeModel(warehouseId: $warehouseId, itemId: $itemId, '
      'systemQuantity: $systemQuantity, actualQuantity: $actualQuantity, '
      'difference: $difference)';
}
