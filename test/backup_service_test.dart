import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:inventory_stock_app/core/database/database_helper.dart';
import 'package:inventory_stock_app/core/database/database_tables.dart';
import 'package:inventory_stock_app/core/services/backup_service.dart';
import 'package:inventory_stock_app/features/backup/data/models/backup_models.dart';
import 'package:inventory_stock_app/features/transactions/data/transaction_repository.dart';

void main() {
  late Directory workDir;
  late Directory backupDir;
  late DatabaseHelper helper;
  late TransactionRepository transactionRepository;
  late BackupService backupService;
  late int warehouseId;
  late int itemId;

  final DateTime morning = DateTime(2026, 11, 13, 9);
  final DateTime noon = DateTime(2026, 11, 13, 12);

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    workDir = await Directory.systemTemp.createTemp('rawaa_wms_backup_test');
    backupDir = Directory(p.join(workDir.path, 'backups'));

    helper = DatabaseHelper.instance;
    await helper.resetForTesting();
    helper.overrideDatabase(
      factory: databaseFactoryFfi,
      path: p.join(workDir.path, 'rawaa_wms.db'),
    );

    final Database db = await helper.database;
    final List<Map<String, Object?>> items = await db.query(
      DatabaseTables.items,
    );
    final List<Map<String, Object?>> warehouses = await db.query(
      DatabaseTables.warehouses,
    );
    itemId = items.single['id']! as int;
    warehouseId = warehouses.single['id']! as int;

    transactionRepository = TransactionRepository(databaseHelper: helper);
    backupService = BackupService(
      databaseHelper: helper,
      temporaryDirectory: () async => backupDir,
    );

    await transactionRepository.createInbound(
      warehouseId: warehouseId,
      itemId: itemId,
      quantity: 500,
      partyName: 'مصنع مياه رواء',
      createdAt: morning,
    );
    await transactionRepository.createOutbound(
      warehouseId: warehouseId,
      itemId: itemId,
      quantity: 120,
      partyName: 'المندوب أحمد',
      createdAt: noon,
    );
  });

  tearDown(() async {
    await helper.resetForTesting();
    if (await workDir.exists()) {
      await workDir.delete(recursive: true);
    }
  });

  Future<int> transactionCount() async {
    final Database db = await helper.database;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM ${DatabaseTables.transactions}',
    );
    return (rows.first['total'] as num?)?.toInt() ?? 0;
  }

  Future<int> warehouseStock() async {
    final Database db = await helper.database;
    final List<Map<String, Object?>> rows = await db.query(
      DatabaseTables.stockBalances,
      where: 'warehouse_id = ? AND item_id = ?',
      whereArgs: <Object?>[warehouseId, itemId],
    );
    return rows.single['current_quantity']! as int;
  }

  test('إنشاء نسخة احتياطية ينشئ ملف SQLite صالحاً باسم مؤرّخ', () async {
    final BackupFile backup = await backupService.createBackup();

    final File file = File(backup.path);
    expect(await file.exists(), isTrue);
    expect(backup.sizeBytes, greaterThan(0));
    expect(backup.fileName, startsWith(BackupService.backupPrefix));
    expect(
      backup.fileName,
      matches(RegExp(r'rawaa_wms_backup_\d{8}_\d{4}\.db$')),
    );
    expect(p.dirname(backup.path), backupDir.path);

    final List<int> header = await file.openRead(0, 16).first;
    expect(latin1.decode(header).startsWith('SQLite format 3'), isTrue);
  });

  test('التحقق يقبل نسخة نظام رواء الصحيحة مع إحصاءاتها', () async {
    final BackupFile backup = await backupService.createBackup();
    final BackupValidationResult validation = await backupService
        .validateBackupFile(backup.path);

    expect(validation.isValid, isTrue);
    expect(validation.transactionCount, 2);
    expect(validation.warehouseCount, 1);
    expect(validation.itemCount, 1);
    expect(validation.sizeBytes, greaterThan(0));
    expect(validation.fileName, backup.fileName);
  });

  test('التحقق يرفض ملفاً وهمياً وملفاً غير موجود', () async {
    final File fake = File(p.join(workDir.path, 'fake.db'));
    await fake.writeAsString('هذا ليس ملف قاعدة بيانات ' * 60);

    final BackupValidationResult fakeResult = await backupService
        .validateBackupFile(fake.path);
    expect(fakeResult.isValid, isFalse);
    expect(fakeResult.message, contains('SQLite'));

    final BackupValidationResult missing = await backupService
        .validateBackupFile(p.join(workDir.path, 'missing.db'));
    expect(missing.isValid, isFalse);
    expect(missing.message, contains('غير موجود'));
  });

  test('التحقق يرفض قاعدة SQLite بلا جداول نظام رواء', () async {
    final String otherPath = p.join(workDir.path, 'other.db');
    final Database other = await databaseFactoryFfi.openDatabase(otherPath);
    await other.execute('CREATE TABLE notes (id INTEGER PRIMARY KEY)');
    await other.close();

    final BackupValidationResult validation = await backupService
        .validateBackupFile(otherPath);
    expect(validation.isValid, isFalse);
    expect(validation.message, contains('جداول ناقصة'));
  });

  test('الاستعادة تعيد البيانات السابقة وتعيد فتح القاعدة', () async {
    final BackupFile backup = await backupService.createBackup();

    await transactionRepository.createInbound(
      warehouseId: warehouseId,
      itemId: itemId,
      quantity: 100,
      partyName: 'شحنة لاحقة',
      createdAt: DateTime(2026, 11, 14, 8),
    );
    expect(await transactionCount(), 3);
    expect(await warehouseStock(), 480);

    await backupService.restoreBackup(backup.path);

    expect(helper.database, completes);
    expect(await transactionCount(), 2);
    expect(await warehouseStock(), 380);
  });

  test('رفض استعادة ملف غير صالح دون المساس بالبيانات', () async {
    final File fake = File(p.join(workDir.path, 'broken.db'));
    await fake.writeAsString('بيانات عشوائية ' * 80);

    await expectLater(
      backupService.restoreBackup(fake.path),
      throwsA(isA<BackupException>()),
    );
    expect(await transactionCount(), 2);
    expect(await warehouseStock(), 380);
  });

  test('إحصائيات القاعدة تعكس الحجم والحركات وآخر عملية', () async {
    final DatabaseStats stats = await backupService.getDatabaseStats();

    expect(stats.sizeBytes, greaterThan(0));
    expect(stats.transactionCount, 2);
    expect(stats.warehouseCount, 1);
    expect(stats.lastTransactionAt, noon);
    expect(stats.sizeKb, greaterThan(0));
  });
}
