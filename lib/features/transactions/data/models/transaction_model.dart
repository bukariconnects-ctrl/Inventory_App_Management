/// أنواع السندات المعتمدة في النظام وقواعد ترقيمها.
abstract final class TransactionTypes {
  static const String inbound = 'INBOUND';
  static const String outbound = 'OUTBOUND';

  /// الإتلاف المخزني الداخلي (بأمر أمين المخزن).
  static const String damage = 'DAMAGE';
  static const String adjustment = 'ADJUSTMENT';

  /// صرف بدل تالف لمندوب عن كراتين مرتجعة من السوق.
  static const String marketReplacement = 'MARKET_REPLACEMENT';

  /// كل الأنواع المسموح بها.
  static const List<String> all = <String>[
    inbound,
    outbound,
    damage,
    adjustment,
    marketReplacement,
  ];

  /// بادئة رقم السند لكل نوع.
  static const Map<String, String> _voucherPrefixes = <String, String>{
    inbound: 'REC',
    outbound: 'ISS',
    damage: 'DMG',
    adjustment: 'ADJ',
    marketReplacement: 'REP',
  };

  /// يعيد بادئة السند المناسبة لنوع الحركة.
  static String voucherPrefix(String transactionType) {
    return _voucherPrefixes[transactionType] ?? 'TRX';
  }

  /// هل النوع معروف ضمن الأنواع المعتمدة؟
  static bool isKnown(String transactionType) {
    return all.contains(transactionType);
  }

  /// هل الحركة تزيد الرصيد؟ (الاستلام والتسوية الموجبة)
  static bool isInflow(String transactionType) {
    return transactionType == inbound;
  }

  /// هل يبدأ هذا النوع بحالة «بانتظار الاعتماد» قبل خصم الرصيد؟
  static bool requiresApproval(String transactionType) {
    return transactionType == damage || transactionType == marketReplacement;
  }
}

/// حالات دورة الاعتماد التي يمر بها السند.
abstract final class TransactionStatus {
  /// سند معتمد ومخصوم من الرصيد (أو استلام/تسوية منفّذة).
  static const String approved = 'APPROVED';

  /// طلب مسجّل ولم يُخصم من الرصيد بعد، بانتظار قرار الاعتماد.
  static const String pending = 'PENDING';

  /// طلب مرفوض دون أي مساس بالرصيد.
  static const String rejected = 'REJECTED';

  /// كل الحالات المسموح بها في قاعدة البيانات.
  static const List<String> all = <String>[approved, pending, rejected];

  /// هل الحالة معروفة؟
  static bool isKnown(String status) => all.contains(status);

  /// الاسم العربي المعروض للحالة.
  static String label(String status) {
    switch (status) {
      case pending:
        return 'بانتظار الاعتماد';
      case rejected:
        return 'مرفوض';
      default:
        return 'معتمد';
    }
  }
}

/// حركة مخزنية واحدة (سند استلام/صرف/إتلاف/بدل تالف/تسوية).
class TransactionModel {
  const TransactionModel({
    this.id,
    required this.transactionType,
    required this.voucherNumber,
    required this.warehouseId,
    required this.itemId,
    required this.quantity,
    this.partyName,
    this.orderReference,
    this.vehicleNumber,
    this.reason,
    this.notes,
    this.status = TransactionStatus.approved,
    this.rejectionReason,
    required this.createdAt,
  });

  /// يقرأ الحركة من صف قاعدة البيانات.
  factory TransactionModel.fromMap(Map<String, Object?> map) {
    return TransactionModel(
      id: map['id'] as int?,
      transactionType: map['transaction_type'] as String? ?? '',
      voucherNumber: map['voucher_number'] as String? ?? '',
      warehouseId: map['warehouse_id'] as int? ?? 0,
      itemId: map['item_id'] as int? ?? 0,
      quantity: map['quantity'] as int? ?? 0,
      partyName: map['party_name'] as String?,
      orderReference: map['order_reference'] as String?,
      vehicleNumber: map['vehicle_number'] as String?,
      reason: map['reason'] as String?,
      notes: map['notes'] as String?,
      status: map['status'] as String? ?? TransactionStatus.approved,
      rejectionReason: map['rejection_reason'] as String?,
      createdAt:
          DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  final int? id;

  /// أحد أنواع [TransactionTypes].
  final String transactionType;

  /// رقم السند، مثال: `REC-20261112-001`.
  final String voucherNumber;
  final int warehouseId;
  final int itemId;

  /// الكمية بالكراتين؛ سالبة في تسوية العجز وموجبة في الزيادة.
  final int quantity;

  /// الطرف الآخر: المسلّم أو المندوب أو المسؤول عن الإتلاف.
  final String? partyName;

  /// رقم أمر الصرف الإداري.
  final String? orderReference;

  /// رقم لوحة سيارة المندوب.
  final String? vehicleNumber;

  /// سبب الإتلاف أو التسوية.
  final String? reason;
  final String? notes;

  /// إحدى حالات [TransactionStatus].
  final String status;

  /// سبب الرفض عند `status == REJECTED`.
  final String? rejectionReason;

  final DateTime createdAt;

  /// هل السند ما زال بانتظار الاعتماد (لم يُخصم من الرصيد)؟
  bool get isPending => status == TransactionStatus.pending;

  /// هل السند مرفوض؟
  bool get isRejected => status == TransactionStatus.rejected;

  /// هل السند معتمد؟
  bool get isApproved => status == TransactionStatus.approved;

  /// هل السند صرف بدل تالف لمندوب؟
  bool get isMarketReplacement =>
      transactionType == TransactionTypes.marketReplacement;

  /// هل الحركة تزيد الرصيد (استلام أو تسوية زيادة)؟
  bool get isIncrement {
    return transactionType == TransactionTypes.inbound ||
        (transactionType == TransactionTypes.adjustment && quantity > 0);
  }

  /// يحوّل الحركة إلى صف قاعدة بيانات.
  Map<String, Object?> toMap({bool includeId = false}) {
    return <String, Object?>{
      if (includeId && id != null) 'id': id,
      'transaction_type': transactionType,
      'voucher_number': voucherNumber,
      'warehouse_id': warehouseId,
      'item_id': itemId,
      'quantity': quantity,
      'party_name': partyName,
      'order_reference': orderReference,
      'vehicle_number': vehicleNumber,
      'reason': reason,
      'notes': notes,
      'status': status,
      'rejection_reason': rejectionReason,
      'created_at': createdAt.toIso8601String(),
    };
  }

  TransactionModel copyWith({
    int? id,
    String? transactionType,
    String? voucherNumber,
    int? warehouseId,
    int? itemId,
    int? quantity,
    String? partyName,
    String? orderReference,
    String? vehicleNumber,
    String? reason,
    String? notes,
    String? status,
    String? rejectionReason,
    DateTime? createdAt,
  }) {
    return TransactionModel(
      id: id ?? this.id,
      transactionType: transactionType ?? this.transactionType,
      voucherNumber: voucherNumber ?? this.voucherNumber,
      warehouseId: warehouseId ?? this.warehouseId,
      itemId: itemId ?? this.itemId,
      quantity: quantity ?? this.quantity,
      partyName: partyName ?? this.partyName,
      orderReference: orderReference ?? this.orderReference,
      vehicleNumber: vehicleNumber ?? this.vehicleNumber,
      reason: reason ?? this.reason,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is TransactionModel &&
        other.id == id &&
        other.transactionType == transactionType &&
        other.voucherNumber == voucherNumber &&
        other.warehouseId == warehouseId &&
        other.itemId == itemId &&
        other.quantity == quantity &&
        other.partyName == partyName &&
        other.orderReference == orderReference &&
        other.vehicleNumber == vehicleNumber &&
        other.reason == reason &&
        other.notes == notes &&
        other.status == status &&
        other.rejectionReason == rejectionReason &&
        other.createdAt == createdAt;
  }

  @override
  int get hashCode => Object.hash(
    id,
    transactionType,
    voucherNumber,
    warehouseId,
    itemId,
    quantity,
    partyName,
    orderReference,
    vehicleNumber,
    reason,
    notes,
    status,
    rejectionReason,
    createdAt,
  );

  @override
  String toString() =>
      'TransactionModel($transactionType, voucherNumber: $voucherNumber, '
      'warehouseId: $warehouseId, itemId: $itemId, quantity: $quantity, '
      'status: $status)';
}
