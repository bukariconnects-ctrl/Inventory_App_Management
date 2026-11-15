import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:inventory_stock_app/core/database/database_helper.dart';
import 'package:inventory_stock_app/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:inventory_stock_app/features/stocktake/data/models/stocktake_model.dart';
import 'package:inventory_stock_app/features/stocktake/presentation/providers/stocktake_provider.dart';
import 'package:inventory_stock_app/features/transactions/data/models/transaction_model.dart';
import 'package:inventory_stock_app/features/transactions/data/transaction_repository.dart';
import 'package:inventory_stock_app/features/transactions/presentation/providers/transaction_provider.dart';

void main() {
  late InventoryProvider inventoryProvider;
  late TransactionProvider transactionProvider;
  late StocktakeProvider stocktakeProvider;
  late TransactionRepository transactionRepository;
  late int warehouseId;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    final DatabaseHelper helper = DatabaseHelper.instance;
    await helper.resetForTesting();
    helper.overrideDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    await helper.database;

    inventoryProvider = InventoryProvider();
    transactionProvider = TransactionProvider(
      inventoryProvider: inventoryProvider,
    );
    stocktakeProvider = StocktakeProvider(inventoryProvider: inventoryProvider);
    transactionRepository = TransactionRepository();

    await inventoryProvider.loadInventoryStatus();
    warehouseId = inventoryProvider.statuses.single.balance.warehouseId;
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
  });

  Future<void> stock(int quantity) async {
    await transactionProvider.createInboundReceipt(
      warehouseId: warehouseId,
      quantity: quantity,
      partyName: 'مصنع مياه رواء',
    );
  }

  // ---------------------------------------------------------------------------
  // سند الإتلاف
  // ---------------------------------------------------------------------------

  test('سند الإتلاف يخصم الكمية التالفة ويحدّث الرصيد', () async {
    await stock(120);

    final TransactionModel? damage = await transactionProvider
        .createDamageVoucher(
          warehouseId: warehouseId,
          quantity: 20,
          reason: 'كسر وتمزق كراتين — أثناء التفريغ',
          responsibleName: 'أمين المخزن سالم',
          notes: 'تلف أثناء النقل',
        );

    expect(damage, isNotNull);
    expect(damage!.transactionType, TransactionTypes.damage);
    expect(damage.voucherNumber, startsWith('DMG-'));
    expect(damage.quantity, 20);
    expect(damage.reason, 'كسر وتمزق كراتين — أثناء التفريغ');
    expect(damage.partyName, 'أمين المخزن سالم');
    expect(transactionProvider.errorMessage, isNull);
    expect(inventoryProvider.totalCartons, 100);
    expect(inventoryProvider.quantityFor(warehouseId), 100);
  });

  test('منع إتلاف كمية تتجاوز الرصيد المتاح', () async {
    await stock(50);

    final TransactionModel? damage = await transactionProvider
        .createDamageVoucher(
          warehouseId: warehouseId,
          quantity: 80,
          reason: 'تسريب عبوات',
          responsibleName: 'أمين المخزن',
        );

    expect(damage, isNull);
    expect(transactionProvider.errorMessage, contains('تتجاوز الرصيد'));
    expect(transactionProvider.errorMessage, contains('30'));
    expect(inventoryProvider.totalCartons, 50);
    expect(inventoryProvider.quantityFor(warehouseId), 50);
  });

  // ---------------------------------------------------------------------------
  // الجرد والتسوية
  // ---------------------------------------------------------------------------

  test('جرد بفائض يسوّي الرصيد لأعلى ويحفظ السجل', () async {
    await stock(100);

    final StocktakeModel? stocktake = await stocktakeProvider.performStocktake(
      warehouseId: warehouseId,
      actualQuantity: 130,
      notes: 'زيادة بعد إعادة العد',
    );

    expect(stocktake, isNotNull);
    expect(stocktake!.systemQuantity, 100);
    expect(stocktake.actualQuantity, 130);
    expect(stocktake.difference, 30);
    expect(stocktake.isShortage, isFalse);
    expect(stocktakeProvider.errorMessage, isNull);

    expect(inventoryProvider.totalCartons, 130);
    expect(inventoryProvider.quantityFor(warehouseId), 130);

    expect(stocktakeProvider.stocktakesHistory, hasLength(1));
    expect(stocktakeProvider.stocktakesHistory.first.difference, 30);

    final List<TransactionModel> adjustments = await transactionRepository
        .listTransactions(
          warehouseId: warehouseId,
          transactionType: TransactionTypes.adjustment,
        );
    expect(adjustments, hasLength(1));
    expect(adjustments.single.quantity, 30);
  });

  test('جرد بعجز يسوّي الرصيد لأقل ويحفظ السجل', () async {
    await stock(100);

    final StocktakeModel? stocktake = await stocktakeProvider.performStocktake(
      warehouseId: warehouseId,
      actualQuantity: 70,
      notes: 'تلف غير مسجّل',
    );

    expect(stocktake, isNotNull);
    expect(stocktake!.systemQuantity, 100);
    expect(stocktake.actualQuantity, 70);
    expect(stocktake.difference, -30);
    expect(stocktake.isShortage, isTrue);
    expect(inventoryProvider.totalCartons, 70);

    final List<StocktakeModel> history = stocktakeProvider.stocktakesHistory;
    expect(history, hasLength(1));
    expect(history.first.difference, -30);

    final List<TransactionModel> adjustments = await transactionRepository
        .listTransactions(
          warehouseId: warehouseId,
          transactionType: TransactionTypes.adjustment,
        );
    expect(adjustments, hasLength(1));
    expect(adjustments.single.quantity, -30);
  });

  test('جرد مطابق (فارق صفر) لا يعدّل الرصيد ولا ينشئ حركة تسوية', () async {
    await stock(100);

    final StocktakeModel? stocktake = await stocktakeProvider.performStocktake(
      warehouseId: warehouseId,
      actualQuantity: 100,
    );

    expect(stocktake, isNotNull);
    expect(stocktake!.systemQuantity, 100);
    expect(stocktake.actualQuantity, 100);
    expect(stocktake.difference, 0);
    expect(stocktake.hasDifference, isFalse);
    expect(inventoryProvider.totalCartons, 100);
    expect(stocktakeProvider.errorMessage, isNull);

    final List<TransactionModel> adjustments = await transactionRepository
        .listTransactions(
          warehouseId: warehouseId,
          transactionType: TransactionTypes.adjustment,
        );
    expect(adjustments, isEmpty);

    // السجل محفوظ رغم عدم وجود فارق.
    expect(stocktakeProvider.stocktakesHistory, hasLength(1));
  });

  test('عند وجود فارق يجب تبرير الجرد قبل الاعتماد', () async {
    await stock(100);

    final StocktakeModel? stocktake = await stocktakeProvider.performStocktake(
      warehouseId: warehouseId,
      actualQuantity: 80,
    );

    expect(stocktake, isNull);
    expect(stocktakeProvider.errorMessage, contains('تبرير الفارق'));
    expect(inventoryProvider.totalCartons, 100);
    expect(stocktakeProvider.stocktakesHistory, isEmpty);
  });
}
