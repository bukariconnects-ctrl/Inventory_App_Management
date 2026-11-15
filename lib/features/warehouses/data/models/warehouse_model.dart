import '../../../../core/constants/app_constants.dart';

/// مخزن مستقل بأرصدة منفصلة داخل النظام.
class WarehouseModel {
  const WarehouseModel({
    this.id,
    required this.name,
    required this.location,
    this.minAlertLimit = AppConstants.defaultLowStockThreshold,
    this.isActive = true,
    required this.createdAt,
  });

  /// يقرأ المخزن من صف قاعدة البيانات.
  factory WarehouseModel.fromMap(Map<String, Object?> map) {
    return WarehouseModel(
      id: map['id'] as int?,
      name: map['name'] as String? ?? '',
      location: map['location'] as String? ?? '',
      minAlertLimit:
          map['min_alert_limit'] as int? ??
          AppConstants.defaultLowStockThreshold,
      isActive: ((map['is_active'] as int?) ?? 1) == 1,
      createdAt:
          DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  final int? id;
  final String name;
  final String location;

  /// حد التنبيه: إذا نزل الرصيد إلى هذا الحد أو أقل عُدّ منخفضًا.
  final int minAlertLimit;
  final bool isActive;
  final DateTime createdAt;

  /// يحوّل المخزن إلى صف قاعدة بيانات (بدون `id` عند الإدراج).
  Map<String, Object?> toMap({bool includeId = false}) {
    return <String, Object?>{
      if (includeId && id != null) 'id': id,
      'name': name,
      'location': location,
      'min_alert_limit': minAlertLimit,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  WarehouseModel copyWith({
    int? id,
    String? name,
    String? location,
    int? minAlertLimit,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return WarehouseModel(
      id: id ?? this.id,
      name: name ?? this.name,
      location: location ?? this.location,
      minAlertLimit: minAlertLimit ?? this.minAlertLimit,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is WarehouseModel &&
        other.id == id &&
        other.name == name &&
        other.location == location &&
        other.minAlertLimit == minAlertLimit &&
        other.isActive == isActive &&
        other.createdAt == createdAt;
  }

  @override
  int get hashCode =>
      Object.hash(id, name, location, minAlertLimit, isActive, createdAt);

  @override
  String toString() =>
      'WarehouseModel(id: $id, name: $name, location: $location, '
      'minAlertLimit: $minAlertLimit, isActive: $isActive)';
}
