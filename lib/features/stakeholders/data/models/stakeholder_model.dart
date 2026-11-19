/// نوع جهة التعامل: مندوب/موزّع أو سائق مصنع/مورّد.
enum StakeholderType {
  /// مندوب يبيع ويوزّع ويستلم كراتين من المخزن.
  distributor('DISTRIBUTOR', 'مندوب / موزّع'),

  /// سائق مصنع أو مورّد يورّد الكراتين للمخزن.
  driver('DRIVER', 'سائق مصنع / مورّد');

  const StakeholderType(this.dbValue, this.label);

  /// القيمة المحفوظة في قاعدة البيانات.
  final String dbValue;

  /// الاسم العربي المعروض في الواجهة.
  final String label;

  /// يقرأ النوع من قيمة قاعدة البيانات، ويعيد المندوب عند قيمة غير معروفة.
  static StakeholderType fromDbValue(String? value) {
    for (final StakeholderType type in values) {
      if (type.dbValue == value) {
        return type;
      }
    }
    return StakeholderType.distributor;
  }
}

/// جهة تعامل محفوظة في دليل المناديب والموردين.
class StakeholderModel {
  const StakeholderModel({
    this.id,
    required this.name,
    this.phone,
    required this.type,
    this.vehicleNumber,
    this.isActive = true,
    required this.createdAt,
  });

  /// يقرأ جهة التعامل من صف قاعدة البيانات.
  factory StakeholderModel.fromMap(Map<String, Object?> map) {
    final String? phone = (map['phone'] as String?)?.trim();
    final String? vehicle = (map['vehicle_number'] as String?)?.trim();
    return StakeholderModel(
      id: map['id'] as int?,
      name: map['name'] as String? ?? '',
      phone: phone == null || phone.isEmpty ? null : phone,
      type: StakeholderType.fromDbValue(map['type'] as String?),
      vehicleNumber: vehicle == null || vehicle.isEmpty ? null : vehicle,
      isActive: ((map['is_active'] as int?) ?? 1) == 1,
      createdAt:
          DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  final int? id;
  final String name;
  final String? phone;
  final StakeholderType type;
  final String? vehicleNumber;
  final bool isActive;
  final DateTime createdAt;

  /// هل للجهة رقم هاتف صالح للاتصال أو واتساب؟
  bool get hasPhone => _digits.isNotEmpty;

  /// رقم الهاتف بأرقام فقط (يُستخدم في روابط tel: وwa.me).
  String get phoneDigits => _digits;

  String get _digits => (phone ?? '').replaceAll(RegExp(r'[^0-9]'), '');

  /// يحوّل الجهة إلى صف قاعدة بيانات (بدون `id` عند الإدراج).
  Map<String, Object?> toMap({bool includeId = false}) {
    return <String, Object?>{
      if (includeId && id != null) 'id': id,
      'name': name,
      'phone': phone,
      'type': type.dbValue,
      'vehicle_number': vehicleNumber,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  StakeholderModel copyWith({
    int? id,
    String? name,
    String? phone,
    StakeholderType? type,
    String? vehicleNumber,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return StakeholderModel(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      type: type ?? this.type,
      vehicleNumber: vehicleNumber ?? this.vehicleNumber,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is StakeholderModel &&
        other.id == id &&
        other.name == name &&
        other.phone == phone &&
        other.type == type &&
        other.vehicleNumber == vehicleNumber &&
        other.isActive == isActive &&
        other.createdAt == createdAt;
  }

  @override
  int get hashCode =>
      Object.hash(id, name, phone, type, vehicleNumber, isActive, createdAt);

  @override
  String toString() =>
      'StakeholderModel(id: $id, name: $name, type: ${type.dbValue}, '
      'phone: $phone, isActive: $isActive)';
}
