import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:inventory_stock_app/core/constants/app_constants.dart';
import 'package:inventory_stock_app/core/database/database_exceptions.dart';
import 'package:inventory_stock_app/core/database/database_helper.dart';
import 'package:inventory_stock_app/core/database/database_tables.dart';
import 'package:inventory_stock_app/features/inventory/data/inventory_repository.dart';
import 'package:inventory_stock_app/features/inventory/data/models/stock_balance_status.dart';
import 'package:inventory_stock_app/features/transactions/data/models/transaction_model.dart';
import 'package:inventory_stock_app/features/transactions/data/transaction_repository.dart';
import 'package:inventory_stock_app/features/warehouses/data/models/warehouse_model.dart';
import 'package:inventory_stock_app/features/warehouses/data/warehouse_repository.dart';

void main() {
  late DatabaseHelper helper;
  late InventoryRepository inventoryRepository;
  late TransactionRepository transactionRepository;
  late WarehouseRepository warehouseRepository;
  late int warehouseId;
  late int itemId;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    helper = DatabaseHelper.instance;
    await helper.resetForTesting();
    helper.overrideDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
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

    inventoryRepository = InventoryRepository(databaseHelper: helper);
    transactionRepository = TransactionRepository(databaseHelper: helper);
    warehouseRepository = WarehouseRepository(databaseHelper: helper);
  });

  tearDown(() async {
    await helper.close();
  });

  Future<int> quantityIn(int warehouse, int item) {
    return inventoryRepository.currentQuantity(
      warehouseId: warehouse,
      itemId: item,
    );
  }

  // ---------------------------------------------------------------------------
  // 1) البذر الأولي
  // ---------------------------------------------------------------------------

  test('تُبذر بيانات الصنف والمخزن الافتراضي برصيد ابتدائي صفر', () async {
    final Database db = await helper.database;

    final List<Map<String, Object?>> items = await db.query(
      DatabaseTables.items,
    );
    expect(items, hasLength(1));
    expect(items.single['name'], AppConstants.defaultItemName);
    expect(items.single['bottle_count'], 20);
    expect(items.single['bottle_volume_ml'], 75);
    expect(items.single['unit'], 'كرتون');

    final List<Map<String, Object?>> warehouses = await db.query(
      DatabaseTables.warehouses,
    );
    expect(warehouses, hasLength(1));
    expect(warehouses.single['name'], AppConstants.defaultWarehouseName);
    expect(
      warehouses.single['location'],
      AppConstants.defaultWarehouseLocation,
    );
    expect(warehouses.single['min_alert_limit'], 100);
    expect(warehouses.single['is_active'], 1);

    final StockBalanceStatus? status = await inventoryRepository
        .getBalanceStatus(warehouseId: warehouseId, itemId: itemId);
    expect(status, isNotNull);
    expect(status!.quantity, 0);
    expect(status.isLowStock, isTrue);
    expect(status.isOutOfStock, isTrue);
  });

  // ---------------------------------------------------------------------------
  // 2) الاستلام
  // ---------------------------------------------------------------------------

  test('سند الاستلام يزيد الرصيد من 0 إلى 500 كرتون', () async {
    final TransactionModel receipt = await transactionRepository.createInbound(
      warehouseId: warehouseId,
      itemId: itemId,
      quantity: 500,
      partyName: 'مصنع مياه رواء',
      orderReference: 'AMR-1001',
      vehicleNumber: '1234-أ ب ج',
    );

    expect(receipt.id, isNotNull);
    expect(receipt.transactionType, TransactionTypes.inbound);
    expect(receipt.quantity, 500);
    expect(receipt.voucherNumber, matches(RegExp(r'^REC-\d{8}-001$')));

    expect(await quantityIn(warehouseId, itemId), 500);

    final List<TransactionModel> movements = await transactionRepository
        .listTransactions(warehouseId: warehouseId);
    expect(movements, hasLength(1));
    expect(movements.single.transactionType, TransactionTypes.inbound);
  });

  // ---------------------------------------------------------------------------
  // 3) الصرف
  // ---------------------------------------------------------------------------

  test('سند الصرف يخصم 200 كرتون فيصبح الرصيد 300', () async {
    await transactionRepository.createInbound(
      warehouseId: warehouseId,
      itemId: itemId,
      quantity: 500,
    );

    final TransactionModel issue = await transactionRepository.createOutbound(
      warehouseId: warehouseId,
      itemId: itemId,
      quantity: 200,
      partyName: 'المندوب أحمد',
      orderReference: 'ORD-55',
      vehicleNumber: '9876-ج د هـ',
    );

    expect(issue.transactionType, TransactionTypes.outbound);
    expect(issue.voucherNumber, matches(RegExp(r'^ISS-\d{8}-001$')));
    expect(issue.quantity, 200);
    expect(await quantityIn(warehouseId, itemId), 300);
  });

  // ---------------------------------------------------------------------------
  // 4) منع الصرف بأكثر من الرصيد
  // ---------------------------------------------------------------------------

  test('الصرف بأكثر من الرصيد يُرفض ولا يترك أي أثر', () async {
    await transactionRepository.createInbound(
      warehouseId: warehouseId,
      itemId: itemId,
      quantity: 500,
    );

    await expectLater(
      transactionRepository.createOutbound(
        warehouseId: warehouseId,
        itemId: itemId,
        quantity: 600,
        partyName: 'المندوب سعيد',
      ),
      throwsA(
        isA<InsufficientStockException>()
            .having((e) => e.availableQuantity, 'المتاح', 500)
            .having((e) => e.requestedQuantity, 'المطلوب', 600)
            .having((e) => e.shortage, 'النقص', 100),
      ),
    );

    // الرصيد كما هو ولم تُسجَّل حركة الصرف المرفوضة.
    expect(await quantityIn(warehouseId, itemId), 500);
    final List<TransactionModel> movements = await transactionRepository
        .listTransactions(warehouseId: warehouseId);
    expect(movements, hasLength(1));
    expect(movements.single.transactionType, TransactionTypes.inbound);
  });

  // ---------------------------------------------------------------------------
  // 5) الإتلاف
  // ---------------------------------------------------------------------------

  test('سند الإتلاف يخصم الكمية التالفة من الرصيد', () async {
    await transactionRepository.createInbound(
      warehouseId: warehouseId,
      itemId: itemId,
      quantity: 300,
    );

    final TransactionModel damage = await transactionRepository.createDamage(
      warehouseId: warehouseId,
      itemId: itemId,
      quantity: 40,
      reason: 'كراتين ممزقة أثناء النقل',
      partyName: 'أمين المخزن',
    );

    expect(damage.transactionType, TransactionTypes.damage);
    expect(damage.voucherNumber, matches(RegExp(r'^DMG-\d{8}-001$')));
    expect(damage.reason, 'كراتين ممزقة أثناء النقل');
    expect(await quantityIn(warehouseId, itemId), 260);

    // إتلاف أكبر من الرصيد مرفوض.
    await expectLater(
      transactionRepository.createDamage(
        warehouseId: warehouseId,
        itemId: itemId,
        quantity: 400,
        reason: 'تلف تام',
      ),
      throwsA(isA<InsufficientStockException>()),
    );
    expect(await quantityIn(warehouseId, itemId), 260);
  });

  // ---------------------------------------------------------------------------
  // 6) الجرد والتسوية
  // ---------------------------------------------------------------------------

  test('تسوية الجرد تطابق الرصيد الفعلي وتحفظ الفارق كحركة', () async {
    await transactionRepository.createInbound(
      warehouseId: warehouseId,
      itemId: itemId,
      quantity: 500,
    );

    final stocktake = await transactionRepository.adjustStocktake(
      warehouseId: warehouseId,
      itemId: itemId,
      actualQuantity: 520,
      notes: 'زيادة نتيجة عدّ خاطئ سابق',
    );

    expect(stocktake.id, isNotNull);
    expect(stocktake.systemQuantity, 500);
    expect(stocktake.actualQuantity, 520);
    expect(stocktake.difference, 20);
    expect(stocktake.isShortage, isFalse);
    expect(await quantityIn(warehouseId, itemId), 520);

    final List<TransactionModel> adjustments = await transactionRepository
        .listTransactions(
          warehouseId: warehouseId,
          transactionType: TransactionTypes.adjustment,
        );
    expect(adjustments, hasLength(1));
    expect(adjustments.single.quantity, 20);
    expect(
      adjustments.single.voucherNumber,
      matches(RegExp(r'^ADJ-\d{8}-001$')),
    );

    // عجز: الفعلي أقل من الدفتري.
    final shortage = await transactionRepository.adjustStocktake(
      warehouseId: warehouseId,
      itemId: itemId,
      actualQuantity: 470,
    );
    expect(shortage.systemQuantity, 520);
    expect(shortage.difference, -50);
    expect(shortage.isShortage, isTrue);
    expect(await quantityIn(warehouseId, itemId), 470);

    final List<TransactionModel> allAdjustments = await transactionRepository
        .listTransactions(
          warehouseId: warehouseId,
          transactionType: TransactionTypes.adjustment,
        );
    expect(allAdjustments, hasLength(2));
    expect(allAdjustments.first.quantity, -50);
  });

  // ---------------------------------------------------------------------------
  // 7) ترقيم السندات التسلسلي
  // ---------------------------------------------------------------------------

  test('أرقام السندات متسلسلة لكل نوع ولكل يوم', () async {
    final DateTime day = DateTime(2026, 11, 12, 9);

    final TransactionModel first = await transactionRepository.createInbound(
      warehouseId: warehouseId,
      itemId: itemId,
      quantity: 10,
      createdAt: day,
    );
    final TransactionModel second = await transactionRepository.createInbound(
      warehouseId: warehouseId,
      itemId: itemId,
      quantity: 15,
      createdAt: day,
    );
    final TransactionModel issue = await transactionRepository.createOutbound(
      warehouseId: warehouseId,
      itemId: itemId,
      quantity: 5,
      createdAt: day,
    );

    expect(first.voucherNumber, 'REC-20261112-001');
    expect(second.voucherNumber, 'REC-20261112-002');
    expect(issue.voucherNumber, 'ISS-20261112-001');

    final String preview = await transactionRepository.nextVoucherNumber(
      transactionType: TransactionTypes.inbound,
      date: day,
    );
    expect(preview, 'REC-20261112-003');
  });

  // ---------------------------------------------------------------------------
  // 8) المخازن وحالة الرصيد
  // ---------------------------------------------------------------------------

  test(
    'المخزن الجديد يبدأ برصيد صفر وتُحسب حالة الانخفاض من حد التنبيه',
    () async {
      final WarehouseModel warehouse = await warehouseRepository.create(
        WarehouseModel(
          name: 'مخزن الفرع',
          location: 'الفرع الشمالي',
          minAlertLimit: 100,
          createdAt: DateTime(2026, 11, 12),
        ),
      );

      expect(warehouse.id, isNotNull);
      final int newWarehouseId = warehouse.id!;

      final StockBalanceStatus? initial = await inventoryRepository
          .getBalanceStatus(warehouseId: newWarehouseId, itemId: itemId);
      expect(initial, isNotNull);
      expect(initial!.quantity, 0);
      expect(initial.isLowStock, isTrue);

      await transactionRepository.createInbound(
        warehouseId: newWarehouseId,
        itemId: itemId,
        quantity: 150,
      );
      final StockBalanceStatus? filled = await inventoryRepository
          .getBalanceStatus(warehouseId: newWarehouseId, itemId: itemId);
      expect(filled!.quantity, 150);
      expect(filled.isLowStock, isFalse);

      await transactionRepository.createOutbound(
        warehouseId: newWarehouseId,
        itemId: itemId,
        quantity: 60,
      );
      final StockBalanceStatus? low = await inventoryRepository
          .getBalanceStatus(warehouseId: newWarehouseId, itemId: itemId);
      expect(low!.quantity, 90);
      expect(low.isLowStock, isTrue);
      expect(low.shortageToMinimum, 10);

      // رصيد المخزن الأول لم يتأثر بعمليات المخزن الجديد.
      expect(await quantityIn(warehouseId, itemId), 0);

      final List<StockBalanceStatus> lowStock = await inventoryRepository
          .listBalances(lowStockOnly: true);
      expect(lowStock, hasLength(2));
    },
  );
}
