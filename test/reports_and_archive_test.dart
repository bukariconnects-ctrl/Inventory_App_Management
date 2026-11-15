import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:inventory_stock_app/core/constants/app_constants.dart';
import 'package:inventory_stock_app/core/database/database_helper.dart';
import 'package:inventory_stock_app/core/database/database_tables.dart';
import 'package:inventory_stock_app/core/services/pdf_service.dart';
import 'package:inventory_stock_app/features/inventory/data/models/item_model.dart';
import 'package:inventory_stock_app/features/reports/data/models/report_models.dart';
import 'package:inventory_stock_app/features/reports/presentation/providers/reports_provider.dart';
import 'package:inventory_stock_app/features/transactions/data/models/transaction_model.dart';
import 'package:inventory_stock_app/features/transactions/data/transaction_repository.dart';
import 'package:inventory_stock_app/features/warehouses/data/models/warehouse_model.dart';
import 'package:inventory_stock_app/features/warehouses/data/warehouse_repository.dart';

void main() {
  late DatabaseHelper helper;
  late TransactionRepository transactionRepository;
  late WarehouseRepository warehouseRepository;
  late int warehouseId;
  late int secondWarehouseId;
  late int itemId;
  late ItemModel item;

  final DateTime day10 = DateTime(2026, 11, 10, 8);
  final DateTime day11Morning = DateTime(2026, 11, 11, 9);
  final DateTime day11Late = DateTime(2026, 11, 11, 10);
  final DateTime day12Morning = DateTime(2026, 11, 12, 9);
  final DateTime day12Late = DateTime(2026, 11, 12, 11);
  final DateTime day13 = DateTime(2026, 11, 13, 8);

  /// بيانات موزّعة على أيام ومناديب مختلفين.
  Future<void> seed() async {
    await transactionRepository.createInbound(
      warehouseId: warehouseId,
      itemId: itemId,
      quantity: 500,
      partyName: 'مصنع مياه رواء',
      createdAt: day10,
    );
    await transactionRepository.createInbound(
      warehouseId: warehouseId,
      itemId: itemId,
      quantity: 100,
      partyName: 'مصنع مياه رواء',
      createdAt: day13,
    );
    await transactionRepository.createInbound(
      warehouseId: secondWarehouseId,
      itemId: itemId,
      quantity: 40,
      partyName: 'مصنع مياه رواء',
      createdAt: day13,
    );
    await transactionRepository.createOutbound(
      warehouseId: warehouseId,
      itemId: itemId,
      quantity: 120,
      partyName: 'المندوب أحمد',
      orderReference: 'ORD-77',
      createdAt: day11Morning,
    );
    await transactionRepository.createOutbound(
      warehouseId: warehouseId,
      itemId: itemId,
      quantity: 80,
      partyName: 'المندوب أحمد',
      createdAt: day11Late,
    );
    await transactionRepository.createOutbound(
      warehouseId: warehouseId,
      itemId: itemId,
      quantity: 50,
      partyName: 'المندوب سعيد',
      createdAt: day12Morning,
    );
    await transactionRepository.createDamage(
      warehouseId: warehouseId,
      itemId: itemId,
      quantity: 30,
      reason: 'تلف أثناء النقل',
      partyName: 'أمين المخزن سالم',
      createdAt: day12Late,
    );
  }

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
    item = ItemModel.fromMap(items.single);
    warehouseId = warehouses.single['id']! as int;

    transactionRepository = TransactionRepository(databaseHelper: helper);
    warehouseRepository = WarehouseRepository(databaseHelper: helper);

    final WarehouseModel secondWarehouse = await warehouseRepository.create(
      WarehouseModel(
        name: 'مخزن الفرع',
        location: 'الفرع الجنوبي',
        createdAt: day10,
      ),
    );
    secondWarehouseId = secondWarehouse.id!;

    await seed();
  });

  tearDown(() async {
    await helper.close();
  });

  // ---------------------------------------------------------------------------
  // 1) الفلترة
  // ---------------------------------------------------------------------------

  test('فلترة الحركات بنوع السند والمخزن', () async {
    final List<TransactionModel> inbound = await transactionRepository
        .filterTransactions(transactionType: TransactionTypes.inbound);
    expect(inbound, hasLength(3));
    expect(
      inbound.every(
        (TransactionModel t) => t.transactionType == TransactionTypes.inbound,
      ),
      isTrue,
    );

    final List<TransactionModel> mainWarehouse = await transactionRepository
        .filterTransactions(warehouseId: warehouseId);
    expect(mainWarehouse, hasLength(6));
    expect(
      mainWarehouse.every((TransactionModel t) => t.warehouseId == warehouseId),
      isTrue,
    );

    final List<TransactionModel> branch = await transactionRepository
        .filterTransactions(warehouseId: secondWarehouseId);
    expect(branch, hasLength(1));
    expect(branch.single.quantity, 40);
  });

  test('فلترة الحركات بالنطاق الزمني تشمل يوم النهاية كاملًا', () async {
    final List<TransactionModel> day11 = await transactionRepository
        .filterTransactions(
          startDate: DateRange.day(day11Morning).start,
          endDate: DateRange.day(day11Morning).endOfDay,
        );

    expect(day11, hasLength(2));
    expect(
      day11.every(
        (TransactionModel t) => t.transactionType == TransactionTypes.outbound,
      ),
      isTrue,
    );
  });

  test('البحث الفوري برقم السند واسم المندوب وأمر الصرف', () async {
    final List<TransactionModel> byOrder = await transactionRepository
        .filterTransactions(searchQuery: 'ORD-77');
    expect(byOrder, hasLength(1));
    expect(byOrder.single.partyName, 'المندوب أحمد');

    final List<TransactionModel> byName = await transactionRepository
        .filterTransactions(searchQuery: 'أحمد');
    expect(byName, hasLength(2));

    final List<TransactionModel> byVoucher = await transactionRepository
        .filterTransactions(searchQuery: byName.first.voucherNumber);
    expect(byVoucher, hasLength(1));
    expect(byVoucher.single.voucherNumber, byName.first.voucherNumber);
  });

  test('الترتيب من الأحدث ويدعم limit/offset', () async {
    final List<TransactionModel> page = await transactionRepository
        .filterTransactions(warehouseId: warehouseId, limit: 2, offset: 1);

    expect(page, hasLength(2));
    expect(page.first.createdAt.isBefore(page.last.createdAt), isFalse);

    final List<TransactionModel> all = await transactionRepository
        .filterTransactions(warehouseId: warehouseId);
    expect(page.first.id, all[1].id);
    expect(page.last.id, all[2].id);
  });

  test('نوع حركة غير معروف يُرفض أثناء الفلترة', () async {
    await expectLater(
      transactionRepository.filterTransactions(transactionType: 'UNKNOWN'),
      throwsA(isA<ArgumentError>()),
    );
  });

  // ---------------------------------------------------------------------------
  // 2) المقاييس
  // ---------------------------------------------------------------------------

  test('مقاييس الفترة تحسب الوارد والمنصرف والتالف وصافي التغير', () async {
    final PeriodSummaryMetrics all = await transactionRepository
        .getPeriodSummaryMetrics();

    expect(all.totalInbound, 640);
    expect(all.totalOutbound, 250);
    expect(all.totalDamaged, 30);
    expect(all.voucherCount, 7);
    expect(all.netChange, 360);

    final PeriodSummaryMetrics mainWarehouse = await transactionRepository
        .getPeriodSummaryMetrics(warehouseId: warehouseId);
    expect(mainWarehouse.totalInbound, 600);
    expect(mainWarehouse.totalOutbound, 250);
    expect(mainWarehouse.totalDamaged, 30);
    expect(mainWarehouse.netChange, 320);
  });

  test('مقاييس يوم واحد تحصر الحركات في ذلك اليوم فقط', () async {
    final DateRange range = DateRange.day(day11Morning);
    final PeriodSummaryMetrics metrics = await transactionRepository
        .getPeriodSummaryMetrics(
          warehouseId: warehouseId,
          startDate: range.start,
          endDate: range.endOfDay,
        );

    expect(metrics.totalInbound, 0);
    expect(metrics.totalOutbound, 200);
    expect(metrics.totalDamaged, 0);
    expect(metrics.voucherCount, 2);
    expect(metrics.netChange, -200);
  });

  test('فترة بلا حركات تعيد مقاييس صفرية', () async {
    final PeriodSummaryMetrics metrics = await transactionRepository
        .getPeriodSummaryMetrics(
          startDate: DateTime(2025, 1, 1),
          endDate: DateTime(2025, 1, 31, 23, 59, 59, 999),
        );

    expect(metrics.isEmpty, isTrue);
    expect(metrics.netChange, 0);
  });

  // ---------------------------------------------------------------------------
  // 3) مسحوبات المناديب
  // ---------------------------------------------------------------------------

  test('مسحوبات المناديب مرتبة بالإجمالي مع عدد السندات', () async {
    final List<RepresentativeSummary> representatives =
        await transactionRepository.getTopRepresentatives();

    expect(representatives, hasLength(2));
    expect(representatives.first.name, 'المندوب أحمد');
    expect(representatives.first.totalQuantity, 200);
    expect(representatives.first.voucherCount, 2);
    expect(representatives.last.name, 'المندوب سعيد');
    expect(representatives.last.totalQuantity, 50);
    expect(representatives.first.shareOf(250), closeTo(0.8, 0.001));
  });

  test('مسحوبات المناديب تحترم حدّ العدد والفترة', () async {
    final List<RepresentativeSummary> topOne = await transactionRepository
        .getTopRepresentatives(limit: 1);
    expect(topOne, hasLength(1));
    expect(topOne.single.name, 'المندوب أحمد');

    final DateRange range = DateRange.day(day12Morning);
    final List<RepresentativeSummary> day12 = await transactionRepository
        .getTopRepresentatives(startDate: range.start, endDate: range.endOfDay);
    expect(day12, hasLength(1));
    expect(day12.single.name, 'المندوب سعيد');
    expect(day12.single.totalQuantity, 50);
  });

  // ---------------------------------------------------------------------------
  // 4) مزوّد التقارير
  // ---------------------------------------------------------------------------

  test('ReportsProvider يحمّل السجل والمقاييس ويطبّق الفلاتر', () async {
    final ReportsProvider provider = ReportsProvider(
      repository: transactionRepository,
    );

    await provider.loadReportsData();
    expect(provider.transactions, hasLength(7));
    expect(provider.metrics.totalInbound, 640);
    expect(provider.representatives, hasLength(2));
    expect(provider.errorMessage, isNull);
    expect(provider.isLoading, isFalse);

    // فلتر النوع يخص السجل فقط؛ المقاييس والمناديب للفترة والمخزن.
    await provider.applyFilters(transactionType: TransactionTypes.damage);
    expect(provider.transactions, hasLength(1));
    expect(provider.metrics.totalDamaged, 30);
    expect(provider.metrics.totalInbound, 640);
    expect(provider.representatives, hasLength(2));

    await provider.applyFilters(warehouseId: secondWarehouseId);
    expect(provider.transactions, hasLength(1));
    expect(provider.metrics.totalInbound, 40);

    await provider.clearFilters();
    expect(provider.hasActiveFilters, isFalse);
    expect(provider.transactions, hasLength(7));

    provider.dispose();
  });

  test('البحث في المزوّد يحدّث القائمة فورًا', () async {
    final ReportsProvider provider = ReportsProvider(
      repository: transactionRepository,
    );

    await provider.setSearchQuery('سعيد');
    expect(provider.transactions, hasLength(1));
    expect(provider.transactions.single.partyName, 'المندوب سعيد');
    expect(provider.hasActiveFilters, isTrue);
    expect(provider.activeFiltersCount, 1);

    await provider.setSearchQuery('');
    expect(provider.transactions, hasLength(7));

    provider.dispose();
  });

  // ---------------------------------------------------------------------------
  // 5) تقرير PDF
  // ---------------------------------------------------------------------------

  test('تقرير المخزون العام يُولّد مستند PDF صالحًا', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initializeDateFormatting(AppConstants.localeCode);

    final ByteData fontData = await rootBundle.load(PdfService.fontAssetPath);
    final pw.Font font = pw.Font.ttf(fontData);
    final PdfService service = PdfService(
      regularFont: font,
      boldFont: font,
      allowNetworkFonts: false,
    );

    final PeriodSummaryMetrics metrics = await transactionRepository
        .getPeriodSummaryMetrics(warehouseId: warehouseId);
    final List<RepresentativeSummary> representatives =
        await transactionRepository.getTopRepresentatives(
          warehouseId: warehouseId,
        );
    final WarehouseModel? warehouse = await warehouseRepository.getById(
      warehouseId,
    );
    final DateTime generatedAt = DateTime(2026, 11, 13, 21, 30);

    final Uint8List bytes = await service.generateInventorySummaryReportPdf(
      metrics: metrics,
      representatives: representatives,
      item: item,
      generatedAt: generatedAt,
      warehouse: warehouse,
      period: DateRange(start: day10, end: day13),
    );

    expect(bytes.length, greaterThan(1000));
    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
    expect(
      latin1.decode(bytes.sublist(bytes.length - 2048)),
      contains('%%EOF'),
    );
    expect(PdfService.summaryReportReference(generatedAt), 'INV-20261113-2130');
    expect(
      PdfService.fileNameForSummaryReport(generatedAt),
      'INV-REPORT-20261113-2130.pdf',
    );
  });
}
