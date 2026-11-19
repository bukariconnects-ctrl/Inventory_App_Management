import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../constants/app_constants.dart';
import 'database_tables.dart';

/// مدير قاعدة البيانات المحلية (Singleton).
///
/// مسؤول عن فتح قاعدة `rawaa_wms.db`، إنشاء الجداول، تفعيل قيود المفاتيح
/// الأجنبية، وبذر البيانات الافتراضية عند الإنشاء الأول.
class DatabaseHelper {
  DatabaseHelper._();

  static final DatabaseHelper instance = DatabaseHelper._();

  Database? _database;
  DatabaseFactory? _factoryOverride;
  String? _pathOverride;

  /// يوجّه الطبقة إلى قاعدة بيانات بديلة (للاختبارات الآلية فقط).
  void overrideDatabase({DatabaseFactory? factory, String? path}) {
    _factoryOverride = factory;
    _pathOverride = path;
  }

  /// يغلق القاعدة ويلغي أي توجيه مخصص (للاختبارات).
  Future<void> resetForTesting() async {
    await close();
    _factoryOverride = null;
    _pathOverride = null;
  }

  /// مصنع القاعدة الفعلي (بعد أي توجيه مخصص للاختبارات).
  DatabaseFactory get factory => _factoryOverride ?? databaseFactory;

  /// مسار ملف قاعدة البيانات الحالي (قد يكون `:memory:` في الاختبارات).
  Future<String> get databasePath async {
    final String? overridePath = _pathOverride;
    if (overridePath != null) {
      return overridePath;
    }
    return p.join(await factory.getDatabasesPath(), AppConstants.databaseName);
  }

  /// اتصال القاعدة الحالي، مع فتحه عند أول طلب.
  Future<Database> get database async {
    final Database? openDatabase = _database;
    if (openDatabase != null && openDatabase.isOpen) {
      return openDatabase;
    }
    final Database created = await _open();
    _database = created;
    return created;
  }

  /// يغلق القاعدة إن كانت مفتوحة.
  Future<void> close() async {
    final Database? openDatabase = _database;
    _database = null;
    if (openDatabase != null && openDatabase.isOpen) {
      await openDatabase.close();
    }
  }

  Future<Database> _open() async {
    final String path = await databasePath;

    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: AppConstants.databaseVersion,
        onConfigure: _configure,
        onCreate: _createSchema,
        onUpgrade: _upgrade,
      ),
    );
  }

  Future<void> _configure(Database db) async {
    // تفعيل قيود المفاتيح الأجنبية على هذا الاتصال.
    await db.execute('PRAGMA foreign_keys = ON;');
  }

  Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE ${DatabaseTables.warehouses} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        location TEXT NOT NULL,
        min_alert_limit INTEGER NOT NULL DEFAULT ${AppConstants.defaultLowStockThreshold}
          CHECK (min_alert_limit >= 0),
        is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE ${DatabaseTables.items} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        bottle_count INTEGER NOT NULL CHECK (bottle_count > 0),
        bottle_volume_ml INTEGER NOT NULL CHECK (bottle_volume_ml > 0),
        unit TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE ${DatabaseTables.stockBalances} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        warehouse_id INTEGER NOT NULL,
        item_id INTEGER NOT NULL,
        current_quantity INTEGER NOT NULL DEFAULT 0 CHECK (current_quantity >= 0),
        last_updated TEXT NOT NULL,
        UNIQUE (warehouse_id, item_id),
        FOREIGN KEY (warehouse_id) REFERENCES ${DatabaseTables.warehouses} (id)
          ON DELETE CASCADE,
        FOREIGN KEY (item_id) REFERENCES ${DatabaseTables.items} (id)
          ON DELETE RESTRICT
      )
    ''');

    await _createTransactionsTable(db, DatabaseTables.transactions);

    await db.execute('''
      CREATE TABLE ${DatabaseTables.stocktakes} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        warehouse_id INTEGER NOT NULL,
        item_id INTEGER NOT NULL,
        system_quantity INTEGER NOT NULL CHECK (system_quantity >= 0),
        actual_quantity INTEGER NOT NULL CHECK (actual_quantity >= 0),
        difference INTEGER NOT NULL,
        notes TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (warehouse_id) REFERENCES ${DatabaseTables.warehouses} (id)
          ON DELETE RESTRICT,
        FOREIGN KEY (item_id) REFERENCES ${DatabaseTables.items} (id)
          ON DELETE RESTRICT
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_transactions_warehouse
      ON ${DatabaseTables.transactions} (warehouse_id)
    ''');
    await db.execute('''
      CREATE INDEX idx_transactions_created_at
      ON ${DatabaseTables.transactions} (created_at)
    ''');
    await db.execute('''
      CREATE INDEX idx_transactions_status
      ON ${DatabaseTables.transactions} (status)
    ''');
    await db.execute('''
      CREATE INDEX idx_stock_balances_warehouse
      ON ${DatabaseTables.stockBalances} (warehouse_id)
    ''');
    await db.execute('''
      CREATE INDEX idx_stocktakes_warehouse
      ON ${DatabaseTables.stocktakes} (warehouse_id)
    ''');

    await _createStakeholdersSchema(db);
    await _createSettingsSchema(db);

    await _seedDefaults(db);
    await _seedSettings(db);
  }

  /// ترقية المخطط للإصدارات الأحدث دون فقد أي بيانات قائمة.
  Future<void> _upgrade(Database db, int oldVersion, int newVersion) async {
    // الإصدار 2: دليل جهات التعامل وإعدادات النظام.
    if (oldVersion < 2) {
      await _createStakeholdersSchema(db);
      await _createSettingsSchema(db);
      await _seedSettings(db);
    }
    // الإصدار 3: دورة الاعتماد (حالة السند + سبب الرفض) ونوع بدل التالف.
    if (oldVersion < 3) {
      await _upgradeTransactionsToV3(db);
    }
  }

  /// جدول الحركات بحالته النهائية (بعد دعم دورة الاعتماد).
  Future<void> _createTransactionsTable(Database db, String tableName) async {
    await db.execute('''
      CREATE TABLE $tableName (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        transaction_type TEXT NOT NULL CHECK (
          transaction_type IN (
            'INBOUND', 'OUTBOUND', 'DAMAGE', 'ADJUSTMENT', 'MARKET_REPLACEMENT'
          )
        ),
        voucher_number TEXT NOT NULL UNIQUE,
        warehouse_id INTEGER NOT NULL,
        item_id INTEGER NOT NULL,
        quantity INTEGER NOT NULL CHECK (quantity <> 0),
        party_name TEXT,
        order_reference TEXT,
        vehicle_number TEXT,
        reason TEXT,
        notes TEXT,
        status TEXT NOT NULL DEFAULT 'APPROVED'
          CHECK (status IN ('APPROVED', 'PENDING', 'REJECTED')),
        rejection_reason TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (warehouse_id) REFERENCES ${DatabaseTables.warehouses} (id)
          ON DELETE RESTRICT,
        FOREIGN KEY (item_id) REFERENCES ${DatabaseTables.items} (id)
          ON DELETE RESTRICT
      )
    ''');
  }

  /// يرقّي جدول الحركات للإصدار 3 بإعادة بناء الجدول.
  ///
  /// إعادة البناء ضرورية لأن SQLite لا يسمح بتعديل قيد `CHECK` على نوع
  /// الحركة عبر `ALTER TABLE`، ونحتاج السماح بالنوع الجديد
  /// `MARKET_REPLACEMENT`. كل السندات القديمة تُنقل بحالة `APPROVED`.
  Future<void> _upgradeTransactionsToV3(Database db) async {
    const String legacyTable = 'transactions_legacy_v2';

    await db.execute('DROP TABLE IF EXISTS $legacyTable');
    await _createTransactionsTable(db, legacyTable);

    await db.execute('''
      INSERT INTO $legacyTable (
        id, transaction_type, voucher_number, warehouse_id, item_id, quantity,
        party_name, order_reference, vehicle_number, reason, notes, status,
        created_at
      )
      SELECT
        id, transaction_type, voucher_number, warehouse_id, item_id, quantity,
        party_name, order_reference, vehicle_number, reason, notes, 'APPROVED',
        created_at
      FROM ${DatabaseTables.transactions}
    ''');

    await db.execute('DROP TABLE ${DatabaseTables.transactions}');
    await db.execute(
      'ALTER TABLE $legacyTable RENAME TO ${DatabaseTables.transactions}',
    );

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_transactions_warehouse
      ON ${DatabaseTables.transactions} (warehouse_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_transactions_created_at
      ON ${DatabaseTables.transactions} (created_at)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_transactions_status
      ON ${DatabaseTables.transactions} (status)
    ''');
  }

  /// جدول جهات التعامل: المناديب/الموزعون وسائقو المصنع/الموردون.
  Future<void> _createStakeholdersSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DatabaseTables.stakeholders} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        type TEXT NOT NULL CHECK (type IN ('DISTRIBUTOR', 'DRIVER')),
        vehicle_number TEXT,
        is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_stakeholders_type
      ON ${DatabaseTables.stakeholders} (type)
    ''');
  }

  /// جدول إعدادات النظام (مفتاح/قيمة).
  Future<void> _createSettingsSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DatabaseTables.appSettings} (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
  }

  /// يبذر إعدادات النظام الافتراضية دون استبدال القيم المحفوظة.
  Future<void> _seedSettings(Database db) async {
    await db.insert(DatabaseTables.appSettings, <String, Object?>{
      'key': AppConstants.settingStorekeeperName,
      'value': AppConstants.defaultStorekeeperName,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  // ---------------------------------------------------------------------------
  // إعدادات النظام
  // ---------------------------------------------------------------------------

  /// يقرأ إعدادًا محفوظًا، أو `defaultValue` إذا لم يوجد.
  Future<String?> getSetting(String key, {String? defaultValue}) async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      DatabaseTables.appSettings,
      columns: <String>['value'],
      where: 'key = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    if (rows.isEmpty) {
      return defaultValue;
    }
    final Object? value = rows.first['value'];
    if (value is String && value.trim().isNotEmpty) {
      return value;
    }
    return defaultValue;
  }

  /// يحفظ إعدادًا (إضافة أو تحديث).
  Future<void> setSetting(String key, String value) async {
    final Database db = await database;
    await db.insert(DatabaseTables.appSettings, <String, Object?>{
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// البيانات الأولية: صنف كرتون الماء + المخزن الرئيسي + رصيد صفري.
  Future<void> _seedDefaults(Database db) async {
    final String now = DateTime.now().toIso8601String();

    final int itemId = await db.insert(DatabaseTables.items, <String, Object?>{
      'name': AppConstants.defaultItemName,
      'bottle_count': AppConstants.bottlesPerCarton,
      'bottle_volume_ml': AppConstants.bottleVolumeMl,
      'unit': AppConstants.cartonUnit,
      'created_at': now,
    });

    final int warehouseId = await db
        .insert(DatabaseTables.warehouses, <String, Object?>{
          'name': AppConstants.defaultWarehouseName,
          'location': AppConstants.defaultWarehouseLocation,
          'min_alert_limit': AppConstants.defaultLowStockThreshold,
          'is_active': 1,
          'created_at': now,
        });

    await db.insert(DatabaseTables.stockBalances, <String, Object?>{
      'warehouse_id': warehouseId,
      'item_id': itemId,
      'current_quantity': 0,
      'last_updated': now,
    });
  }
}
