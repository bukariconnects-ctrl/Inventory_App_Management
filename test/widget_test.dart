import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:inventory_stock_app/core/constants/app_constants.dart';
import 'package:inventory_stock_app/core/database/database_helper.dart';
import 'package:inventory_stock_app/core/theme/app_colors.dart';
import 'package:inventory_stock_app/features/home/presentation/screens/home_screen.dart';
import 'package:inventory_stock_app/features/home/presentation/widgets/dashboard_view.dart';
import 'package:inventory_stock_app/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:inventory_stock_app/features/reports/presentation/providers/reports_provider.dart';
import 'package:inventory_stock_app/features/splash/presentation/splash_screen.dart';
import 'package:inventory_stock_app/features/warehouses/presentation/providers/warehouse_provider.dart';

/// ثيم اختباري محلي لا يعتمد على تنزيل الخطوط من الشبكة.
ThemeData _testTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
    scaffoldBackgroundColor: AppColors.background,
  );
}

/// يبني تطبيقًا مصغّرًا بنفس إعدادات التعريب.
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
  setUpAll(() async {
    sqfliteFfiInit();
    DatabaseHelper.instance.overrideDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    await DatabaseHelper.instance.database;
  });

  tearDownAll(() async {
    await DatabaseHelper.instance.resetForTesting();
  });

  testWidgets('تعرض شاشة البداية اسم النظام', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: _testTheme(), home: const SplashScreen()),
    );
    await tester.pump();

    expect(find.text(AppConstants.appBrandName), findsOneWidget);
    expect(find.text(AppConstants.appSubtitle), findsOneWidget);

    // إزالة الشجرة لإلغاء مؤقت الانتقال قبل نهاية الاختبار.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('لوحة التحكم تعرض الإجماليات وشريط التنبيه', (
    WidgetTester tester,
  ) async {
    // شاشة أطول لعرض كل أقسام اللوحة دون تمرير.
    tester.view.physicalSize = const Size(420, 1700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final WarehouseProvider warehouses = WarehouseProvider();
    final InventoryProvider inventory = InventoryProvider();

    // الوصول لقاعدة البيانات يحتاج زمنًا حقيقيًا (خارج التوقيت الوهمي).
    await tester.runAsync(() async {
      await warehouses.loadWarehouses();
      await inventory.loadInventoryStatus();
    });

    await tester.pumpWidget(
      _testApp(
        Scaffold(body: DashboardView(onOpenInventory: () {})),
        providers: <ChangeNotifierProvider<ChangeNotifier>>[
          ChangeNotifierProvider<WarehouseProvider>.value(value: warehouses),
          ChangeNotifierProvider<InventoryProvider>.value(value: inventory),
        ],
      ),
    );
    await tester.pump();

    expect(find.text('إجمالي كراتين المياه'), findsOneWidget);
    expect(find.text('مخازن فعالة'), findsOneWidget);
    expect(find.text('تنبيهات حرجة'), findsOneWidget);
    expect(find.text('حالة المخازن السريعة'), findsOneWidget);
    expect(find.text('توريد كراتين من المصنع'), findsOneWidget);
    expect(find.text('صرف كراتين للمناديب'), findsOneWidget);
    expect(find.textContaining('رصيد منخفض'), findsWidgets);
  });

  testWidgets('التنقل السفلي يفتح تبويب المخازن والمخزون', (
    WidgetTester tester,
  ) async {
    final WarehouseProvider warehouses = WarehouseProvider();
    final InventoryProvider inventory = InventoryProvider();
    final ReportsProvider reports = ReportsProvider();

    await tester.runAsync(() async {
      await warehouses.loadWarehouses();
      await inventory.loadInventoryStatus();
    });

    await tester.pumpWidget(
      _testApp(
        const HomeScreen(),
        providers: <ChangeNotifierProvider<ChangeNotifier>>[
          ChangeNotifierProvider<WarehouseProvider>.value(value: warehouses),
          ChangeNotifierProvider<InventoryProvider>.value(value: inventory),
          ChangeNotifierProvider<ReportsProvider>.value(value: reports),
        ],
      ),
    );

    // ترك تحميل الشاشة الأولى يكتمل بزمن حقيقي ثم إعادة الرسم.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();

    expect(find.text('الرئيسية'), findsOneWidget);
    expect(find.text('المخازن'), findsOneWidget);
    expect(find.text('المخزون'), findsOneWidget);
    expect(find.text('السجل والتقارير'), findsOneWidget);

    await tester.tap(find.text('المخازن'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('مخزن جديد'), findsOneWidget);
    expect(find.text(AppConstants.defaultWarehouseName), findsWidgets);

    await tester.tap(find.text('المخزون'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('توزيع الأرصدة على المخازن'), findsOneWidget);
    expect(find.text(AppConstants.defaultItemName), findsOneWidget);
  });
}
