import '../../../../core/constants/app_constants.dart';

/// صنف مخزني (حاليًا: كرتون ماء رواء).
class ItemModel {
  const ItemModel({
    this.id,
    required this.name,
    this.bottleCount = AppConstants.bottlesPerCarton,
    this.bottleVolumeMl = AppConstants.bottleVolumeMl,
    this.unit = AppConstants.cartonUnit,
    required this.createdAt,
  });

  /// يقرأ الصنف من صف قاعدة البيانات.
  factory ItemModel.fromMap(Map<String, Object?> map) {
    return ItemModel(
      id: map['id'] as int?,
      name: map['name'] as String? ?? '',
      bottleCount: map['bottle_count'] as int? ?? AppConstants.bottlesPerCarton,
      bottleVolumeMl:
          map['bottle_volume_ml'] as int? ?? AppConstants.bottleVolumeMl,
      unit: map['unit'] as String? ?? AppConstants.cartonUnit,
      createdAt:
          DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  final int? id;
  final String name;

  /// عدد القناني في الكرتون.
  final int bottleCount;

  /// حجم القنينة بالمل.
  final int bottleVolumeMl;

  /// وحدة القياس المخزنية.
  final String unit;
  final DateTime createdAt;

  /// يحوّل الصنف إلى صف قاعدة بيانات (بدون `id` عند الإدراج).
  Map<String, Object?> toMap({bool includeId = false}) {
    return <String, Object?>{
      if (includeId && id != null) 'id': id,
      'name': name,
      'bottle_count': bottleCount,
      'bottle_volume_ml': bottleVolumeMl,
      'unit': unit,
      'created_at': createdAt.toIso8601String(),
    };
  }

  ItemModel copyWith({
    int? id,
    String? name,
    int? bottleCount,
    int? bottleVolumeMl,
    String? unit,
    DateTime? createdAt,
  }) {
    return ItemModel(
      id: id ?? this.id,
      name: name ?? this.name,
      bottleCount: bottleCount ?? this.bottleCount,
      bottleVolumeMl: bottleVolumeMl ?? this.bottleVolumeMl,
      unit: unit ?? this.unit,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ItemModel &&
        other.id == id &&
        other.name == name &&
        other.bottleCount == bottleCount &&
        other.bottleVolumeMl == bottleVolumeMl &&
        other.unit == unit &&
        other.createdAt == createdAt;
  }

  @override
  int get hashCode =>
      Object.hash(id, name, bottleCount, bottleVolumeMl, unit, createdAt);

  @override
  String toString() =>
      'ItemModel(id: $id, name: $name, bottleCount: $bottleCount, '
      'bottleVolumeMl: $bottleVolumeMl, unit: $unit)';
}
