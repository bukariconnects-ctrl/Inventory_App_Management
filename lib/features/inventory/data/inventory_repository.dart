import 'package:sqflite/sqflite.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/database/database_tables.dart';
import '../../warehouses/data/models/warehouse_model.dart';
import 'models/item_model.dart';
import 'models/stock_balance_model.dart';
import 'models/stock_balance_status.dart';

/// استعلامات الأرصدة: قراءة الرصيد، وتحديد ما إذا وصل لحد التنبيه.
class InventoryRepository {
  InventoryRepository({DatabaseHelper? databaseHelper})
    : _helper = databaseHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _helper;

  /// رصيد صنف محدد داخل مخزن محدد مع حالة التنبيه، أو `null` إن لم يوجد.
  Future<StockBalanceStatus?> getBalanceStatus({
    required int warehouseId,
    required int itemId,
  }) async {
    final Database db = await _helper.database;
    final List<Map<String, Object?>> balanceRows = await db.query(
      DatabaseTables.stockBalances,
      where: 'warehouse_id = ? AND item_id = ?',
      whereArgs: <Object?>[warehouseId, itemId],
      limit: 1,
    );
    if (balanceRows.isEmpty) {
      return null;
    }

    final StockBalanceModel balance = StockBalanceModel.fromMap(
      balanceRows.first,
    );
    final WarehouseModel? warehouse = await _warehouseById(
      db,
      balance.warehouseId,
    );
    final ItemModel? item = await _itemById(db, balance.itemId);
    if (warehouse == null || item == null) {
      return null;
    }

    return StockBalanceStatus(
      balance: balance,
      warehouse: warehouse,
      item: item,
    );
  }

  /// كل الأرصدة (أو أرصدة مخزن واحد) مع حالة التنبيه لكل صف.
  Future<List<StockBalanceStatus>> listBalances({
    int? warehouseId,
    bool lowStockOnly = false,
  }) async {
    final Database db = await _helper.database;
    final List<Map<String, Object?>> balanceRows = await db.query(
      DatabaseTables.stockBalances,
      where: warehouseId == null ? null : 'warehouse_id = ?',
      whereArgs: warehouseId == null ? null : <Object?>[warehouseId],
      orderBy: 'warehouse_id ASC, item_id ASC',
    );
    if (balanceRows.isEmpty) {
      return const <StockBalanceStatus>[];
    }

    final Map<int, WarehouseModel> warehouses = <int, WarehouseModel>{
      for (final Map<String, Object?> row in await db.query(
        DatabaseTables.warehouses,
      ))
        row['id'] as int: WarehouseModel.fromMap(row),
    };
    final Map<int, ItemModel> items = <int, ItemModel>{
      for (final Map<String, Object?> row in await db.query(
        DatabaseTables.items,
      ))
        row['id'] as int: ItemModel.fromMap(row),
    };

    final List<StockBalanceStatus> statuses = <StockBalanceStatus>[];
    for (final Map<String, Object?> row in balanceRows) {
      final StockBalanceModel balance = StockBalanceModel.fromMap(row);
      final WarehouseModel? warehouse = warehouses[balance.warehouseId];
      final ItemModel? item = items[balance.itemId];
      if (warehouse == null || item == null) {
        continue;
      }
      final StockBalanceStatus status = StockBalanceStatus(
        balance: balance,
        warehouse: warehouse,
        item: item,
      );
      if (lowStockOnly && !status.isLowStock) {
        continue;
      }
      statuses.add(status);
    }
    return List<StockBalanceStatus>.unmodifiable(statuses);
  }

  /// الكمية الحالية فقط، وتعيد صفرًا إذا لم يوجد سجل رصيد.
  Future<int> currentQuantity({
    required int warehouseId,
    required int itemId,
  }) async {
    final Database db = await _helper.database;
    final List<Map<String, Object?>> rows = await db.query(
      DatabaseTables.stockBalances,
      columns: <String>['current_quantity'],
      where: 'warehouse_id = ? AND item_id = ?',
      whereArgs: <Object?>[warehouseId, itemId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return 0;
    }
    return rows.first['current_quantity'] as int? ?? 0;
  }

  /// الصنف الأساسي المسجّل في النظام (أول صنف)، أو `null` إن لم يوجد.
  Future<ItemModel?> getPrimaryItem() async {
    final Database db = await _helper.database;
    final List<Map<String, Object?>> rows = await db.query(
      DatabaseTables.items,
      orderBy: 'id ASC',
      limit: 1,
    );
    return rows.isEmpty ? null : ItemModel.fromMap(rows.first);
  }

  Future<WarehouseModel?> _warehouseById(Database db, int id) async {
    final List<Map<String, Object?>> rows = await db.query(
      DatabaseTables.warehouses,
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : WarehouseModel.fromMap(rows.first);
  }

  Future<ItemModel?> _itemById(Database db, int id) async {
    final List<Map<String, Object?>> rows = await db.query(
      DatabaseTables.items,
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : ItemModel.fromMap(rows.first);
  }
}
