/// يُرمى عند محاولة صرف أو إتلاف كمية أكبر من الرصيد المتاح.
class InsufficientStockException implements Exception {
  const InsufficientStockException({
    required this.availableQuantity,
    required this.requestedQuantity,
    this.warehouseId,
    this.itemId,
    this.operationType,
  });

  /// الرصيد الحالي في المخزن.
  final int availableQuantity;

  /// الكمية المطلوبة في السند.
  final int requestedQuantity;

  final int? warehouseId;
  final int? itemId;

  /// نوع العملية التي فشلت (`OUTBOUND` أو `DAMAGE`).
  final String? operationType;

  /// النقص المطلوب لتغطية العملية.
  int get shortage => requestedQuantity - availableQuantity;

  @override
  String toString() {
    return 'الرصيد غير كافٍ: المتاح $availableQuantity كرتون، '
        'المطلوب $requestedQuantity كرتون.';
  }
}
