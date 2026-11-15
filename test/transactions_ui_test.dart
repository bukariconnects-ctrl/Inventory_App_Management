import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:inventory_stock_app/core/constants/app_constants.dart';
import 'package:inventory_stock_app/core/database/database_helper.dart';
import 'package:inventory_stock_app/core/theme/app_colors.dart';
import 'package:inventory_stock_app/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:inventory_stock_app/features/transactions/data/models/transaction_model.dart';
import 'package:inventory_stock_app/features/transactions/presentation/providers/transaction_provider.dart';
import 'package:inventory_stock_app/features/transactions/presentation/screens/inbound_voucher_screen.dart';
import 'package:inventory_stock_app/features/transactions/presentation/screens/outbound_voucher_screen.dart';
import 'package:inventory_stock_app/features/warehouses/presentation/providers/warehouse_provider.dart';

/// ثيم اختباري محلي لا يعتمد على تنزيل الخطوط من الشبكة.
ThemeData _testTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
    scaffoldBackgroundColor: AppColors.background,
  );
}

Widget _testApp(
  Widget home, {
  required List<ChangeNotifierProvider<ChangeNotifier>> providers,
}) {
  return MultiProvider(
    providers: providers,
    child: MaterialApp(
      theme: _testTheme(),
      locale: const Locale(AppConstants.localeCode),
      supportedLocales: const <Locale>[Locale(AppConstants.localeCode)],
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home,
    ),
  );
}

void main() {
  late WarehouseProvider warehouseProvider;
  late InventoryProvider inventoryProvider;
  late TransactionProvider transactionProvider;
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

    warehouseProvider = WarehouseProvider();
    inventoryProvider = InventoryProvider();
    transactionProvider = TransactionProvider(
      inventoryProvider: inventoryProvider,
    );

    await warehouseProvider.loadWarehouses();
    await inventoryProvider.loadInventoryStatus();
    warehouseId = inventoryProvider.statuses.single.balance.warehouseId;
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
  });

  test('سند الاستلام يزيد رصيد المخزن في المزوّد', () async {
    final TransactionModel? transaction = await transactionProvider
        .createInboundReceipt(
          warehouseId: warehouseId,
          quantity: 250,
          partyName: 'مصنع مياه رواء',
          notes: 'شحنة أولى',
        );

    expect(transaction, isNotNull);
    expect(transaction!.transactionType, TransactionTypes.inbound);
    expect(transaction.voucherNumber, startsWith('REC-'));
    expect(transaction.quantity, 250);
    expect(transactionProvider.errorMessage, isNull);
    expect(transactionProvider.isSubmitting, isFalse);
    expect(transactionProvider.lastCreatedTransaction, transaction);

    // الأرصدة تحدّثت في مزوّد المخزون مباشرة.
    expect(inventoryProvider.totalCartons, 250);
    expect(inventoryProvider.quantityFor(warehouseId), 250);
  });

  test('سند الصرف يخصم الكمية من الرصيد', () async {
    await transactionProvider.createInboundReceipt(
      warehouseId: warehouseId,
      quantity: 500,
      partyName: 'مصنع مياه رواء',
    );

    final TransactionModel? transaction = await transactionProvider
        .createOutboundIssue(
          warehouseId: warehouseId,
          quantity: 200,
          orderReference: 'ORD-2026-0045',
          partyName: 'المندوب أحمد السالم',
          vehicleNumber: '1234-أ ب ج',
        );

    expect(transaction, isNotNull);
    expect(transaction!.transactionType, TransactionTypes.outbound);
    expect(transaction.voucherNumber, startsWith('ISS-'));
    expect(transaction.orderReference, 'ORD-2026-0045');
    expect(inventoryProvider.totalCartons, 300);
  });

  test('منع الصرف عند تجاوز الرصيد المتاح', () async {
    await transactionProvider.createInboundReceipt(
      warehouseId: warehouseId,
      quantity: 100,
      partyName: 'مصنع مياه رواء',
    );

    final TransactionModel? transaction = await transactionProvider
        .createOutboundIssue(
          warehouseId: warehouseId,
          quantity: 150,
          orderReference: 'ORD-9',
          partyName: 'مندوب',
        );

    expect(transaction, isNull);
    expect(transactionProvider.errorMessage, contains('تتجاوز الرصيد'));
    expect(transactionProvider.errorMessage, contains('50'));
    // الرصيد لم يتغير ولم يُسجَّل أي سند.
    expect(inventoryProvider.totalCartons, 100);
    expect(inventoryProvider.quantityFor(warehouseId), 100);
  });

  testWidgets('شاشة سند الاستلام تعرض رقم السند المتوقع والصنف', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        const InboundVoucherScreen(),
        providers: <ChangeNotifierProvider<ChangeNotifier>>[
          ChangeNotifierProvider<WarehouseProvider>.value(
            value: warehouseProvider,
          ),
          ChangeNotifierProvider<InventoryProvider>.value(
            value: inventoryProvider,
          ),
          ChangeNotifierProvider<TransactionProvider>.value(
            value: transactionProvider,
          ),
        ],
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pump();

    expect(find.text('سند استلام مياه من المصنع'), findsOneWidget);
    expect(find.textContaining('REC-'), findsWidgets);
    expect(find.text('تأكيد واستلام الشحنة'), findsOneWidget);
    expect(find.textContaining(AppConstants.defaultItemName), findsWidgets);
  });

  testWidgets('سند الصرف يعطّل الحفظ عند تجاوز الرصيد المتاح', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        const OutboundVoucherScreen(),
        providers: <ChangeNotifierProvider<ChangeNotifier>>[
          ChangeNotifierProvider<WarehouseProvider>.value(
            value: warehouseProvider,
          ),
          ChangeNotifierProvider<InventoryProvider>.value(
            value: inventoryProvider,
          ),
          ChangeNotifierProvider<TransactionProvider>.value(
            value: transactionProvider,
          ),
        ],
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pump();

    // المخزن الوحيد نشط ويُختار تلقائيًا ورصيده صفر.
    expect(find.textContaining('الرصيد المتاح في هذا المخزن'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, '5');
    await tester.pump();

    expect(find.textContaining('تتجاوز الرصيد المتوفر'), findsWidgets);

    final ElevatedButton saveButton = tester.widget<ElevatedButton>(
      find.byKey(const Key('outbound_submit_button')),
    );
    expect(saveButton.onPressed, isNull);
  });
}
