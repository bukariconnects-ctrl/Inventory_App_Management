import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import '../../features/backup/data/models/backup_models.dart';
import '../database/database_helper.dart';
import '../database/database_tables.dart';
import '../utils/app_formatters.dart';

/// نسخ احتياطي محلي لقاعدة بيانات SQLite ومشاركتها، مع تحقق واستعادة آمنة.
///
/// كل العمليات محلية بالكامل (بلا إنترنت)، وملف النسخة هو ملف SQLite واحد
/// يمكن حفظه أو إرساله عبر واتساب/Drive ثم استعادته لاحقًا.
class BackupService {
  BackupService({
    DatabaseHelper? databaseHelper,
    Future<Directory> Function()? temporaryDirectory,
  }) : _helper = databaseHelper ?? DatabaseHelper.instance,
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  /// الجداول التي يجب وجودها لاعتبار الملف نسخة صالحة لهذا النظام.
  static const List<String> requiredTables = <String>[
    DatabaseTables.warehouses,
    DatabaseTables.items,
    DatabaseTables.stockBalances,
    DatabaseTables.transactions,
  ];

  static const String backupPrefix = 'rawaa_wms_backup_';
  static const String _undoFileName = 'rawaa_wms_before_restore.db';

  final DatabaseHelper _helper;
  final Future<Directory> Function() _temporaryDirectory;

  // ---------------------------------------------------------------------------
  // الإنشاء والمشاركة
  // ---------------------------------------------------------------------------

  /// ينشئ نسخة من قاعدة البيانات في مجلد مؤقت باسم يحمل التاريخ والوقت.
  Future<BackupFile> createBackup({String? destinationDirectory}) async {
    final Database db = await _helper.database;
    // ضمان كتابة أي تغييرات معلّقة في WAL قبل نسخ الملف.
    await db.rawQuery('PRAGMA wal_checkpoint(FULL);');

    final String databasePath = await _helper.databasePath;
    if (databasePath == inMemoryDatabasePath) {
      throw const BackupException(
        'النسخ الاحتياطي غير متاح لقاعدة بيانات في الذاكرة.',
      );
    }

    final File source = File(databasePath);
    if (!await source.exists()) {
      throw const BackupException('ملف قاعدة البيانات غير موجود على الجهاز.');
    }

    final Directory directory = destinationDirectory == null
        ? await _temporaryDirectory()
        : Directory(destinationDirectory);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final DateTime createdAt = DateTime.now();
    final File backup = File(
      p.join(directory.path, '$backupPrefix${_timestamp(createdAt)}.db'),
    );
    await source.copy(backup.path);

    final int size = await backup.length();
    if (size <= 0) {
      throw const BackupException('فشل إنشاء ملف النسخة الاحتياطية.');
    }

    return BackupFile(path: backup.path, createdAt: createdAt, sizeBytes: size);
  }

  /// يفتح نافذة المشاركة (واتساب/Drive/حفظ) لملف النسخة الاحتياطية.
  Future<void> shareBackup(BackupFile backup) async {
    if (!await File(backup.path).exists()) {
      throw const BackupException('ملف النسخة الاحتياطية غير موجود.');
    }
    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(backup.path, mimeType: 'application/x-sqlite3')],
        subject: 'نسخة احتياطية - نظام مخازن مياه رواء',
        text:
            'نسخة احتياطية من بيانات مخازن مياه رواء\n'
            'تاريخ النسخة: ${AppFormatters.dateTime(backup.createdAt)}',
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // التحقق
  // ---------------------------------------------------------------------------

  /// يتحقق أن الملف قاعدة SQLite صالحة وتحتوي جداول نظام رواء الأساسية.
  Future<BackupValidationResult> validateBackupFile(String filePath) async {
    final File file = File(filePath);
    if (!await file.exists()) {
      return BackupValidationResult.invalid('الملف المحدد غير موجود.');
    }

    final int size = await file.length();
    if (size < 512) {
      return BackupValidationResult.invalid(
        'حجم الملف صغير جداً ولا يبدو قاعدة بيانات صالحة.',
      );
    }

    if (!await _hasSqliteHeader(file)) {
      return BackupValidationResult.invalid(
        'الملف المحدد ليس قاعدة بيانات SQLite صالحة.',
      );
    }

    Database? database;
    try {
      database = await _helper.factory.openDatabase(
        filePath,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );

      final List<String> tables =
          (await database.rawQuery(
                "SELECT name FROM sqlite_master WHERE type = 'table'",
              ))
              .map((Map<String, Object?> row) => row['name'] as String? ?? '')
              .toList();

      final List<String> missing = requiredTables
          .where((String table) => !tables.contains(table))
          .toList(growable: false);
      if (missing.isNotEmpty) {
        return BackupValidationResult.invalid(
          'النسخة غير متوافقة مع نظام رواء: جداول ناقصة '
          '(${missing.join('، ')}).',
        );
      }

      final List<Map<String, Object?>> integrity = await database.rawQuery(
        'PRAGMA integrity_check;',
      );
      final bool integrityOk =
          integrity.isNotEmpty &&
          '${integrity.first.values.first}'.toLowerCase() == 'ok';
      if (!integrityOk) {
        return BackupValidationResult.invalid(
          'فحص سلامة قاعدة البيانات فشل. الملف تالف أو غير مكتمل.',
        );
      }

      return BackupValidationResult(
        isValid: true,
        message: 'نسخة احتياطية صالحة وجاهزة للاستعادة.',
        path: filePath,
        sizeBytes: size,
        transactionCount: await _count(database, DatabaseTables.transactions),
        warehouseCount: await _count(database, DatabaseTables.warehouses),
        itemCount: await _count(database, DatabaseTables.items),
        stocktakeCount: await _count(database, DatabaseTables.stocktakes),
      );
    } catch (error) {
      return BackupValidationResult.invalid(
        'تعذر قراءة الملف كقاعدة بيانات: تأكد أنه ملف نسخة صادر من التطبيق.',
      );
    } finally {
      await database?.close();
    }
  }

  // ---------------------------------------------------------------------------
  // الاستعادة
  // ---------------------------------------------------------------------------

  /// يستبدل قاعدة البيانات الحالية بالنسخة المحددة بعد التحقق منها.
  ///
  /// في حال فشل الاستبدال يعيد ملف قاعدة البيانات السابق (نسخة أمان مؤقتة)
  /// حتى لا يتم فقد أي بيانات.
  Future<void> restoreBackup(String sourceFilePath) async {
    final BackupValidationResult validation = await validateBackupFile(
      sourceFilePath,
    );
    if (!validation.isValid) {
      throw BackupException(validation.message);
    }

    final String databasePath = await _helper.databasePath;
    if (databasePath == inMemoryDatabasePath) {
      throw const BackupException(
        'الاستعادة غير متاحة لقاعدة بيانات في الذاكرة.',
      );
    }

    final File source = File(sourceFilePath);
    final File target = File(databasePath);
    final File undo = File(p.join(target.parent.path, _undoFileName));

    await _helper.close();
    bool undoCreated = false;

    try {
      if (await target.exists()) {
        await target.copy(undo.path);
        undoCreated = true;
      }
      await _deleteSidecarFiles(databasePath);
      await source.copy(databasePath);

      final Database db = await _helper.database;
      final List<Map<String, Object?>> integrity = await db.rawQuery(
        'PRAGMA integrity_check;',
      );
      final bool integrityOk =
          integrity.isNotEmpty &&
          '${integrity.first.values.first}'.toLowerCase() == 'ok';
      if (!integrityOk) {
        throw const BackupException(
          'فشل فحص سلامة البيانات المستعادة، أُلغيت العملية.',
        );
      }

      if (undoCreated && await undo.exists()) {
        await undo.delete();
      }
    } catch (error) {
      await _helper.close();
      if (undoCreated && await undo.exists()) {
        await target.copy(databasePath);
        await undo.delete();
      } else if (await target.exists()) {
        await target.delete();
      }
      await _deleteSidecarFiles(databasePath);
      try {
        // إعادة فتح قاعدة البيانات الأصلية (أو إنشاء قاعدة جديدة عند الفشل).
        await _helper.database;
      } catch (_) {
        // لا شيء إضافي يمكن فعله هنا.
      }
      if (error is BackupException) {
        rethrow;
      }
      throw const BackupException(
        'تعذر استعادة النسخة الاحتياطية. لم يتم تغيير بياناتك الحالية.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // الإحصائيات
  // ---------------------------------------------------------------------------

  /// إحصائيات سريعة: حجم القاعدة وعدد الحركات والمخازن وآخر عملية.
  Future<DatabaseStats> getDatabaseStats() async {
    final Database db = await _helper.database;
    final String databasePath = await _helper.databasePath;

    int sizeBytes = 0;
    if (databasePath != inMemoryDatabasePath) {
      final File file = File(databasePath);
      if (await file.exists()) {
        sizeBytes = await file.length();
      }
    }

    final List<Map<String, Object?>> lastRows = await db.rawQuery(
      'SELECT MAX(created_at) AS last_created FROM '
      '${DatabaseTables.transactions}',
    );
    final String? lastCreated = lastRows.isEmpty
        ? null
        : lastRows.first['last_created'] as String?;

    return DatabaseStats(
      sizeBytes: sizeBytes,
      transactionCount: await _count(db, DatabaseTables.transactions),
      warehouseCount: await _count(db, DatabaseTables.warehouses),
      stocktakeCount: await _count(db, DatabaseTables.stocktakes),
      lastTransactionAt: lastCreated == null
          ? null
          : DateTime.tryParse(lastCreated),
    );
  }

  // ---------------------------------------------------------------------------
  // أدوات داخلية
  // ---------------------------------------------------------------------------

  Future<bool> _hasSqliteHeader(File file) async {
    final RandomAccessFile reader = await file.open();
    try {
      final List<int> header = await reader.read(16);
      return header.length == 16 &&
          latin1.decode(header).startsWith('SQLite format 3');
    } finally {
      await reader.close();
    }
  }

  Future<int> _count(DatabaseExecutor db, String table) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM $table',
    );
    return (rows.first['total'] as num?)?.toInt() ?? 0;
  }

  /// يحذف ملفات WAL/SHM/Journal المرافقة حتى لا تتعارض مع الملف الجديد.
  Future<void> _deleteSidecarFiles(String databasePath) async {
    for (final String suffix in <String>['-wal', '-shm', '-journal']) {
      final File file = File('$databasePath$suffix');
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  static String _timestamp(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}${two(value.month)}${two(value.day)}'
        '_${two(value.hour)}${two(value.minute)}';
  }
}
