import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:inventory_stock_app/core/database/database_exceptions.dart';
import 'package:inventory_stock_app/core/database/database_helper.dart';
import 'package:inventory_stock_app/core/database/database_tables.dart';
import 'package:inventory_stock_app/features/transactions/data/models/transaction_model.dart';
import 'package:inventory_stock_app/features/transactions/data/transaction_repository.dart';

void main() {
  late DatabaseHelper helper;
  late TransactionRepository repository;
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

    final List<Map<String, Object?>> warehouses = await db.query(
      DatabaseTables.warehouses,
    );
    final List<Map<String, Object?>> items = await db.query(
      DatabaseTables.items,
    );
    warehouseId = warehouses.first['id'] as int;
    itemId = items.first['id'] as int;

    repository = TransactionRepository(databaseHelper: helper);
  });

  tearDown(() async {
    await helper.close();
  });

  Future<void> seedStock(int quantity) async {
    await repository.createInbound(
      warehouseId: warehouseId,
      itemId: itemId,
      quantity: quantity,
      partyName: 'مصنع رواء',
    );
  }

  Future<int> stockQuantity() async {
    final Database db = await helper.database;
    final List<Map<String, Object?>> rows = await db.query(
      DatabaseTables.stockBalances,
      where: 'warehouse_id = ? AND item_id = ?',
      whereArgs: <Object?>[warehouseId, itemId],
    );
    if (rows.isEmpty) {
      return 0;
    }
    return rows.first['current_quantity'] as int;
  }

  Future<TransactionModel> readTransaction(int id) async {
    final Database db = await helper.database;
    final List<Map<String, Object?>> rows = await db.query(
      DatabaseTables.transactions,
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    return TransactionModel.fromMap(rows.first);
  }

  Future<TransactionModel> createReplacementRequest({
    int quantity = 10,
    DateTime? createdAt,
  }) {
    return repository.createPendingMarketReplacement(
      warehouseId: warehouseId,
      itemId: itemId,
      quantity: quantity,
      partyName: 'المندوب أحمد',
      orderReference: 'ORD-2026-0111',
      reason: 'عبوات مسربة أعادها المندوب من السوق',
      vehicleNumber: '1234 أ ب ج',
      createdAt: createdAt,
    );
  }

  group('طلبات بدل التالف والإتلاف المعلقة', () {
    test('طلب بدل التالف يُسجّل بحالة PENDING دون خصم الرصيد', () async {
      await seedStock(100);

      final TransactionModel request = await createReplacementRequest(
        quantity: 15,
      );

      expect(request.transactionType, TransactionTypes.marketReplacement);
      expect(request.status, TransactionStatus.pending);
      expect(request.isPending, isTrue);
      expect(request.voucherNumber, startsWith('REP-'));
      expect(request.orderReference, 'ORD-2026-0111');
      // الرصيد بقي كما هو تمامًا.
      expect(await stockQuantity(), 100);

      final TransactionModel stored = await readTransaction(request.id!);
      expect(stored.status, TransactionStatus.pending);
      expect(stored.quantity, 15);
    });

    test(
      'الإتلاف المخزني الداخلي يُسجّل بحالة PENDING دون خصم الرصيد',
      () async {
        await seedStock(80);

        final TransactionModel request = await repository
            .createPendingInternalDamage(
              warehouseId: warehouseId,
              itemId: itemId,
              quantity: 5,
              reason: 'كسر وتمزق كراتين',
              responsibleName: 'أمين المخزن سالم',
            );

        expect(request.transactionType, TransactionTypes.damage);
        expect(request.status, TransactionStatus.pending);
        expect(request.partyName, 'أمين المخزن سالم');
        expect(request.voucherNumber, startsWith('DMG-'));
        expect(await stockQuantity(), 80);
      },
    );

    test('طلب بدل التالف يرفض البيانات الناقصة', () async {
      await expectLater(
        repository.createPendingMarketReplacement(
          warehouseId: warehouseId,
          itemId: itemId,
          quantity: 5,
          partyName: 'المندوب أحمد',
          orderReference: '   ',
          reason: 'سبب',
        ),
        throwsA(isA<ArgumentError>()),
      );

      await expectLater(
        repository.createPendingInternalDamage(
          warehouseId: warehouseId,
          itemId: itemId,
          quantity: 5,
          reason: '  ',
          responsibleName: 'أمين المخزن',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('اعتماد الطلبات المعلقة', () {
    test('الاعتماد يخصم الرصيد ذرّيًا ويحوّل الحالة إلى APPROVED', () async {
      await seedStock(100);
      final TransactionModel request = await createReplacementRequest(
        quantity: 25,
      );

      final TransactionModel approved = await repository
          .approvePendingTransaction(request.id!);

      expect(approved.status, TransactionStatus.approved);
      expect(approved.isApproved, isTrue);
      expect(await stockQuantity(), 75);

      final TransactionModel stored = await readTransaction(request.id!);
      expect(stored.status, TransactionStatus.approved);
      expect(await repository.getPendingTransactions(), isEmpty);
    });

    test('لا يمكن اعتماد السند نفسه مرتين', () async {
      await seedStock(100);
      final TransactionModel request = await createReplacementRequest(
        quantity: 10,
      );
      await repository.approvePendingTransaction(request.id!);

      await expectLater(
        repository.approvePendingTransaction(request.id!),
        throwsA(isA<ArgumentError>()),
      );
      // لا خصم إضافي.
      expect(await stockQuantity(), 90);
    });

    test('فشل الاعتماد لنقص الرصيد يبقي الرصيد والحالة دون تغيير', () async {
      await seedStock(20);
      final TransactionModel request = await createReplacementRequest(
        quantity: 50,
      );

      await expectLater(
        repository.approvePendingTransaction(request.id!),
        throwsA(isA<InsufficientStockException>()),
      );

      expect(await stockQuantity(), 20);
      final TransactionModel stored = await readTransaction(request.id!);
      expect(stored.status, TransactionStatus.pending);
    });
  });

  group('رفض الطلبات المعلقة', () {
    test('الرفض يسجل السبب ويترك الرصيد دون أي تغيير', () async {
      await seedStock(60);
      final TransactionModel request = await createReplacementRequest(
        quantity: 30,
      );

      final TransactionModel rejected = await repository
          .rejectPendingTransaction(request.id!, 'الكمية غير مطابقة للمرتجع');

      expect(rejected.status, TransactionStatus.rejected);
      expect(rejected.isRejected, isTrue);
      expect(rejected.rejectionReason, 'الكمية غير مطابقة للمرتجع');
      expect(await stockQuantity(), 60);

      final TransactionModel stored = await readTransaction(request.id!);
      expect(stored.status, TransactionStatus.rejected);
      expect(stored.rejectionReason, 'الكمية غير مطابقة للمرتجع');
    });

    test('سبب الرفض إلزامي ولا يمكن رفض سند معتمد', () async {
      await seedStock(40);
      final TransactionModel request = await createReplacementRequest(
        quantity: 5,
      );

      await expectLater(
        repository.rejectPendingTransaction(request.id!, '   '),
        throwsA(isA<ArgumentError>()),
      );

      await repository.approvePendingTransaction(request.id!);
      await expectLater(
        repository.rejectPendingTransaction(request.id!, 'متأخر'),
        throwsA(isA<ArgumentError>()),
      );
      expect(await stockQuantity(), 35);
    });
  });

  group('استعلامات الطلبات المعلقة', () {
    test('يجلب المعلقة فقط مرتبة من الأحدث ويعدّها', () async {
      await seedStock(100);
      final TransactionModel replacement = await createReplacementRequest(
        quantity: 10,
        createdAt: DateTime(2026, 11, 10, 9),
      );
      final TransactionModel damage = await repository
          .createPendingInternalDamage(
            warehouseId: warehouseId,
            itemId: itemId,
            quantity: 4,
            reason: 'سوء تخزين',
            responsibleName: 'أمين المخزن',
            createdAt: DateTime(2026, 11, 11, 9),
          );

      final List<TransactionModel> pending = await repository
          .getPendingTransactions();
      expect(pending, hasLength(2));
      expect(pending.first.id, damage.id);
      expect(pending.last.id, replacement.id);
      expect(await repository.countPendingTransactions(), 2);
      expect(
        await repository.countPendingTransactions(
          warehouseId: warehouseId + 99,
        ),
        0,
      );

      await repository.approvePendingTransaction(damage.id!);
      expect(await repository.getPendingTransactions(), hasLength(1));
      expect(await repository.countPendingTransactions(), 1);
    });
  });
}
