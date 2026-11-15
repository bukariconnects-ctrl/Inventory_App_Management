import 'package:sqflite/sqflite.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/database/database_tables.dart';
import 'models/warehouse_model.dart';

/// عمليات إدارة المخازن على قاعدة البيانات.
///
/// عند إنشاء مخزن جديد تُهيّأ له تلقائيًا سجلات رصيد صفرية لكل الأصناف،
/// بحيث تظهر الأرصدة فورًا دون حاجة إلى صرف أو استلام مسبق.
class WarehouseRepository {
  WarehouseRepository({DatabaseHelper? databaseHelper})
    : _helper = databaseHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _helper;

  /// كل المخازن، مرتبة بالاسم؛ ويمكن حصرها على النشطة فقط.
  Future<List<WarehouseModel>> getAll({bool activeOnly = false}) async {
    final Database db = await _helper.database;
    final List<Map<String, Object?>> rows = await db.query(
      DatabaseTables.warehouses,
      where: activeOnly ? 'is_active = 1' : null,
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(WarehouseModel.fromMap).toList(growable: false);
  }

  /// مخزن واحد بالمعرّف، أو `null` إن لم يوجد.
  Future<WarehouseModel?> getById(int id) async {
    final Database db = await _helper.database;
    final List<Map<String, Object?>> rows = await db.query(
      DatabaseTables.warehouses,
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return WarehouseModel.fromMap(rows.first);
  }

  /// ينشئ مخزنًا جديدًا مع سجلات رصيد صفرية لكل الأصناف (عملية ذرية).
  Future<WarehouseModel> create(WarehouseModel warehouse) async {
    final Database db = await _helper.database;
    return db.transaction<WarehouseModel>((Transaction txn) async {
      final int id = await txn.insert(
        DatabaseTables.warehouses,
        warehouse.toMap(),
      );

      final List<Map<String, Object?>> items = await txn.query(
        DatabaseTables.items,
        columns: <String>['id'],
      );
      final String now = DateTime.now().toIso8601String();
      for (final Map<String, Object?> item in items) {
        await txn.insert(DatabaseTables.stockBalances, <String, Object?>{
          'warehouse_id': id,
          'item_id': item['id'],
          'current_quantity': 0,
          'last_updated': now,
        });
      }

      return warehouse.copyWith(id: id);
    });
  }

  /// يحدّث بيانات مخزن قائم، ويعيد عدد الصفوف المتأثرة.
  Future<int> update(WarehouseModel warehouse) async {
    final int? id = warehouse.id;
    if (id == null) {
      throw ArgumentError('لا يمكن تحديث مخزن بدون معرّف (id).');
    }
    final Database db = await _helper.database;
    return db.update(
      DatabaseTables.warehouses,
      warehouse.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// يفعّل أو يعطّل مخزنًا (التعطيل يُخفيه من شاشات العمليات).
  Future<int> setActive(int id, {required bool isActive}) async {
    final Database db = await _helper.database;
    return db.update(
      DatabaseTables.warehouses,
      <String, Object?>{'is_active': isActive ? 1 : 0},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// يحذف مخزنًا بلا حركات (تُحذف أرصدته تلقائيًا).
  ///
  /// تمنع قاعدة البيانات الحذف إذا كانت للمخزن حركات مسجّلة (RESTRICT).
  Future<int> delete(int id) async {
    final Database db = await _helper.database;
    return db.delete(
      DatabaseTables.warehouses,
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }
}
