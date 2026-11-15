import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'features/backup/presentation/providers/backup_provider.dart';
import 'features/inventory/presentation/providers/inventory_provider.dart';
import 'features/reports/presentation/providers/reports_provider.dart';
import 'features/splash/presentation/splash_screen.dart';
import 'features/stocktake/presentation/providers/stocktake_provider.dart';
import 'features/transactions/presentation/providers/transaction_provider.dart';
import 'features/warehouses/presentation/providers/warehouse_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // تهيئة SQLite على سطح المكتب قبل أي وصول إلى قاعدة البيانات.
  _initializeDatabaseFactory();

  // تهيئة بيانات التواريخ العربية لتعمل أدوات التنسيق في AppFormatters.
  await initializeDateFormatting(AppConstants.localeCode);

  runApp(const RawaaWmsApp());
}

/// يهيّئ مصنع قاعدة البيانات حسب المنصة.
///
/// المتصفح لا يوفّر `dart:io` ولا SQLite أصلية، لذلك لا نلمس `Platform`
/// إطلاقًا عند `kIsWeb` (استدعاؤها هناك يرمي Unsupported operation).
/// على أندرويد وiOS يستخدم `sqflite` الأصلي كما هو، أما على سطح المكتب
/// (Windows/macOS/Linux) فلا يوجد تنفيذ أصلي لـ `sqflite`، لذلك نفعّل
/// `databaseFactoryFfi` عبر حزمة `sqflite_common_ffi`.
void _initializeDatabaseFactory() {
  if (kIsWeb) {
    return;
  }
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}

/// جذر تطبيق "مياه رواء - إدارة المخازن".
class RawaaWmsApp extends StatelessWidget {
  const RawaaWmsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<BackupProvider>(create: (_) => BackupProvider()),
        ChangeNotifierProvider<WarehouseProvider>(
          create: (_) => WarehouseProvider(),
        ),
        ChangeNotifierProvider<InventoryProvider>(
          create: (_) => InventoryProvider(),
        ),
        // مزوّد الحركات يحتاج مزوّد المخزون لتحديث الأرصدة بعد كل سند.
        ChangeNotifierProxyProvider<InventoryProvider, TransactionProvider>(
          create: (_) => TransactionProvider(),
          update:
              (_, InventoryProvider inventory, TransactionProvider? previous) {
                final TransactionProvider transactionProvider =
                    previous ?? TransactionProvider();
                return transactionProvider..attachInventoryProvider(inventory);
              },
        ),
        // مزوّد السجل والتقارير يعيد التحميل تلقائيًا بعد حفظ أي سند جديد.
        ChangeNotifierProxyProvider<TransactionProvider, ReportsProvider>(
          create: (_) => ReportsProvider(),
          update:
              (
                _,
                TransactionProvider transactionProvider,
                ReportsProvider? previous,
              ) {
                final ReportsProvider reportsProvider =
                    previous ?? ReportsProvider();
                return reportsProvider
                  ..attachTransactionProvider(transactionProvider);
              },
        ),
        // مزوّد الجرد يحتاج مزوّد المخزون للمقارنة والتحديث بعد التسوية.
        ChangeNotifierProxyProvider<InventoryProvider, StocktakeProvider>(
          create: (_) => StocktakeProvider(),
          update:
              (_, InventoryProvider inventory, StocktakeProvider? previous) {
                final StocktakeProvider stocktakeProvider =
                    previous ?? StocktakeProvider();
                return stocktakeProvider..attachInventoryProvider(inventory);
              },
        ),
      ],
      child: MaterialApp(
        title: AppConstants.appTitle,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        locale: const Locale(AppConstants.localeCode),
        supportedLocales: const <Locale>[Locale(AppConstants.localeCode)],
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        // فرض الاتجاه من اليمين إلى اليسار مهما كان إعداد الجهاز.
        builder: (BuildContext context, Widget? child) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: const SplashScreen(),
      ),
    );
  }
}
