import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:inventory_stock_app/core/database/database_helper.dart';
import 'package:inventory_stock_app/features/inventory/data/inventory_repository.dart';
import 'package:inventory_stock_app/features/inventory/data/models/stock_balance_status.dart';
import 'package:inventory_stock_app/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:inventory_stock_app/features/transactions/data/transaction_repository.dart';
import 'package:inventory_stock_app/features/warehouses/data/models/warehouse_model.dart';
import 'package:inventory_stock_app/features/warehouses/data/warehouse_repository.dart';
import 'package:inventory_stock_app/features/warehouses/presentation/providers/warehouse_provider.dart';

void main() {
  late DatabaseHelper helper;
  late WarehouseRepository warehouseRepository;
  late InventoryRepository inventoryRepository;
  late TransactionRepository transactionRepository;
  late WarehouseProvider warehouseProvider;
  late InventoryProvider inventoryProvider;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    helper = DatabaseHelper.instance;
    await helper.resetForTesting();
    helper.overrideDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    await helper.database;

    warehouseRepository = WarehouseRepository(databaseHelper: helper);
    inventoryRepository = InventoryRepository(databaseHelper: helper);
    transactionRepository = TransactionRepository(databaseHelper: helper);
    warehouseProvider = WarehouseProvider(repository: warehouseRepository);
    inventoryProvider = InventoryProvider(repository: inventoryRepository);
  });

  tearDown(() async {
    await helper.close();
  });

  group('WarehouseProvider', () {
    test('يحمّل المخازن الأولية بنجاح', () async {
      await warehouseProvider.loadWarehouses();

      expect(warehouseProvider.isLoading, isFalse);
      expect(warehouseProvider.errorMessage, isNull);
      expect(warehouseProvider.warehouses, hasLength(1));
      expect(warehouseProvider.activeCount, 1);
      expect(warehouseProvider.totalCount, 1);
      expect(warehouseProvider.warehouses.single.isActive, isTrue);
    });

    test('يضيف مخزنًا جديدًا ويحدّث القائمة', () async {
      await warehouseProvider.loadWarehouses();

      final bool added = await warehouseProvider.addWarehouse(
        name: 'مخزن الفرع الشمالي',
        location: 'الفرع الشمالي',
        minAlertLimit: 60,
      );

      expect(added, isTrue);
      expect(warehouseProvider.errorMessage, isNull);
      expect(warehouseProvider.warehouses, hasLength(2));
      expect(
        warehouseProvider.warehouses.any(
          (WarehouseModel w) =>
              w.name == 'مخزن الفرع الشمالي' && w.minAlertLimit == 60,
        ),
        isTrue,
      );
    });

    test('يرفض المخزن بدون اسم أو موقع ولا يضيف شيئًا', () async {
      final bool added = await warehouseProvider.addWarehouse(
        name: '   ',
        location: '',
        minAlertLimit: 100,
      );

      expect(added, isFalse);
      expect(warehouseProvider.errorMessage, isNotNull);
      expect(warehouseProvider.warehouses, isEmpty);
    });

    test('يعدّل بيانات مخزن قائم', () async {
      await warehouseProvider.loadWarehouses();
      final WarehouseModel original = warehouseProvider.warehouses.single;

      final bool updated = await warehouseProvider.updateWarehouse(
        original,
        name: 'المخزن الرئيسي المحدّث',
        location: 'المبنى الإداري',
        minAlertLimit: 30,
      );

      expect(updated, isTrue);
      final WarehouseModel stored = warehouseProvider.warehouses.single;
      expect(stored.name, 'المخزن الرئيسي المحدّث');
      expect(stored.location, 'المبنى الإداري');
      expect(stored.minAlertLimit, 30);
    });

    test('يبدّل حالة المخزن بين نشط وغير نشط', () async {
      await warehouseProvider.loadWarehouses();
      final WarehouseModel warehouse = warehouseProvider.warehouses.single;

      final bool toggled = await warehouseProvider.toggleWarehouseStatus(
        warehouse,
      );

      expect(toggled, isTrue);
      expect(warehouseProvider.warehouses.single.isActive, isFalse);
      expect(warehouseProvider.activeCount, 0);
    });
  });

  group('InventoryProvider', () {
    test('يحسب الإجمالي والتنبيهات من الأرصدة', () async {
      await inventoryProvider.loadInventoryStatus();

      expect(inventoryProvider.isLoading, isFalse);
      expect(inventoryProvider.errorMessage, isNull);
      expect(inventoryProvider.statuses, hasLength(1));
      expect(inventoryProvider.item, isNotNull);
      expect(inventoryProvider.totalCartons, 0);
      expect(inventoryProvider.lowStockCount, 1);
      expect(inventoryProvider.hasLowStockAlert, isTrue);
      expect(inventoryProvider.outOfStockCount, 1);
      expect(inventoryProvider.activeWarehousesCount, 1);
    });

    test('يعكس الاستلام في الإجمالي وفي حالة المخزن', () async {
      await inventoryProvider.loadInventoryStatus();
      final StockBalanceStatus status = inventoryProvider.statuses.single;

      await transactionRepository.createInbound(
        warehouseId: status.balance.warehouseId,
        itemId: status.balance.itemId,
        quantity: 150,
      );
      await inventoryProvider.refresh();

      expect(inventoryProvider.totalCartons, 150);
      expect(inventoryProvider.hasLowStockAlert, isFalse);
      expect(inventoryProvider.quantityFor(status.balance.warehouseId), 150);
      expect(
        inventoryProvider.statusFor(status.balance.warehouseId),
        isNotNull,
      );
      expect(
        await inventoryProvider.fetchWarehouseQuantity(
          status.balance.warehouseId,
        ),
        150,
      );
    });

    test('المخزن الجديد يظهر فورًا برصيد صفر ومنخفض', () async {
      await warehouseProvider.loadWarehouses();
      await inventoryProvider.loadInventoryStatus();

      await warehouseProvider.addWarehouse(
        name: 'مخزن احتياطي',
        location: 'المستودع الخلفي',
        minAlertLimit: 100,
      );
      await inventoryProvider.refresh();

      expect(inventoryProvider.statuses, hasLength(2));
      expect(inventoryProvider.totalCartons, 0);
      expect(inventoryProvider.lowStockCount, 2);
    });
  });
}
