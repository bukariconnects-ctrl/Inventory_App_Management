import 'package:path/path.dart' as p;

/// ملف نسخة احتياطية تم إنشاؤه على الجهاز.
class BackupFile {
  const BackupFile({
    required this.path,
    required this.createdAt,
    required this.sizeBytes,
  });

  final String path;
  final DateTime createdAt;
  final int sizeBytes;

  /// اسم الملف بدون المسار.
  String get fileName => p.basename(path);

  /// الحجم بالكيلوبايت.
  double get sizeKb => sizeBytes / 1024;

  @override
  String toString() => 'BackupFile($fileName, $sizeBytes bytes)';
}

/// نتيجة فحص ملف نسخة احتياطية قبل استعادته.
class BackupValidationResult {
  const BackupValidationResult({
    required this.isValid,
    required this.message,
    this.path,
    this.sizeBytes = 0,
    this.transactionCount = 0,
    this.warehouseCount = 0,
    this.itemCount = 0,
    this.stocktakeCount = 0,
  });

  factory BackupValidationResult.invalid(String message) =>
      BackupValidationResult(isValid: false, message: message);

  final bool isValid;
  final String message;
  final String? path;
  final int sizeBytes;
  final int transactionCount;
  final int warehouseCount;
  final int itemCount;
  final int stocktakeCount;

  double get sizeKb => sizeBytes / 1024;

  String get fileName => path == null ? '' : p.basename(path!);
}

/// إحصائيات تشخيصية سريعة عن قاعدة البيانات الحالية.
class DatabaseStats {
  const DatabaseStats({
    required this.sizeBytes,
    required this.transactionCount,
    required this.warehouseCount,
    required this.stocktakeCount,
    this.lastTransactionAt,
  });

  static const DatabaseStats empty = DatabaseStats(
    sizeBytes: 0,
    transactionCount: 0,
    warehouseCount: 0,
    stocktakeCount: 0,
  );

  final int sizeBytes;
  final int transactionCount;
  final int warehouseCount;
  final int stocktakeCount;
  final DateTime? lastTransactionAt;

  double get sizeKb => sizeBytes / 1024;

  @override
  String toString() =>
      'DatabaseStats(size: $sizeBytes, transactions: $transactionCount, '
      'warehouses: $warehouseCount, stocktakes: $stocktakeCount)';
}

/// خطأ في النسخ الاحتياطي/الاستعادة برسالة عربية جاهزة للعرض.
class BackupException implements Exception {
  const BackupException(this.message);

  final String message;

  @override
  String toString() => message;
}
