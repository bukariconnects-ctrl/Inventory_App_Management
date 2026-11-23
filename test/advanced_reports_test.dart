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
import 'package:inventory_stock_app/core/utils/app_formatters.dart';
import 'package:inventory_stock_app/features/inventory/data/models/item_model.dart';
import 'package:inventory_stock_app/features/reports/data/models/report_models.dart';
import 'package:inventory_stock_app/features/reports/presentation/providers/reports_provider.dart';
import 'package:inventory_stock_app/features/transactions/data/models/transaction_model.dart';
import 'package:inventory_stock_app/features/transactions/data/transaction_repository.dart';
import 'package:inventory_stock_app/features/warehouses/data/models/warehouse_model.dart';
import 'package:inventory_stock_app/features/warehouses/data/warehouse_repository.dart';

/// يتحقق من أن البايتات الناتجة مستند PDF فعلي وكامل.
void _expectValidPdf(Uint8List bytes) {
  expect(bytes.length, greaterThan(1000));
  expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
  final String tail = latin1.decode(
    bytes.sublist(bytes.length > 2048 ? bytes.length - 2048 : 0),
  );
  expect(tail, contains('%%EOF'));
}

/// يتحقق من أن كل صفحات المستند بمقاس A4 الرأسي.
void _expectA4Pages(Uint8List bytes) {
  final String raw = latin1.decode(bytes);
  final RegExp pattern = RegExp(
    r'/MediaBox\s*\[\s*0\s+0\s+([0-9.]+)\s+([0-9.]+)\s*\]',
  );
  final Iterable<RegExpMatch> matches = pattern.allMatches(raw);
  expect(matches, isNotEmpty, reason: 'لا يوجد MediaBox في المستند');
  for (final RegExpMatch match in matches) {
    expect(double.parse(match.group(1)!), closeTo(595.28, 0.6));
    expect(double.parse(match.group(2)!), closeTo(841.89, 0.6));
  }
}

void main() {
  late DatabaseHelper helper;
  late TransactionRepository repository;
  late WarehouseRepository warehouseRepository;
  late int warehouseId;
  late int itemId;
  late ItemModel item;
  late WarehouseModel warehouse;

  final DateTime beforeDay = DateTime(2026, 11, 22, 9);
  final DateTime beforeDayOutbound = DateTime(2026, 11, 22, 10);
  final DateTime olderInbound = DateTime(2026, 11, 20, 8);
  final DateTime olderOutbound = DateTime(2026, 11, 21, 10);
  final DateTime dayInbound = DateTime(2026, 11, 23, 8);
  final DateTime dayOutboundEarly = DateTime(2026, 11, 23, 9, 30);
  final DateTime dayOutboundLate = DateTime(2026, 11, 23, 11);
  final DateTime dayReplacement = DateTime(2026, 11, 23, 12);
  final DateTime dayDamage = DateTime(2026, 11, 23, 13);
  final DateTime day = DateTime(2026, 11, 23);

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
    warehouse = WarehouseModel.fromMap(warehouses.single);

    repository = TransactionRepository(databaseHelper: helper);
    warehouseRepository = WarehouseRepository(databaseHelper: helper);

    // رصيد افتتاحي 500 كرتون وصرف سابق للمندوب سعيد.
    await repository.createInbound(
      warehouseId: warehouseId,
      itemId: itemId,
      quantity: 500,
      partyName: 'مصنع مياه رواء',
      createdAt: beforeDay,
    );
    await repository.createOutbound(
      warehouseId: warehouseId,
      itemId: itemId,
      quantity: 50,
      partyName: 'المندوب سعيد',
      createdAt: beforeDayOutbound,
    );

    // توريد وصرف أقدم خارج فترة الكشف المختبرة.
    await repository.createInbound(
      warehouseId: warehouseId,
      itemId: itemId,
      quantity: 100,
      partyName: 'مصنع مياه رواء',
      createdAt: olderInbound,
    );
    await repository.createOutbound(
      warehouseId: warehouseId,
      itemId: itemId,
      quantity: 40,
      partyName: 'المندوب أحمد',
      createdAt: olderOutbound,
    );

    // حركة اليوم المختبر.
    await repository.createInbound(
      warehouseId: warehouseId,
      itemId: itemId,
      quantity: 100,
      partyName: 'مصنع مياه رواء',
      createdAt: dayInbound,
    );
    await repository.createOutbound(
      warehouseId: warehouseId,
      itemId: itemId,
      quantity: 120,
      partyName: 'المندوب أحمد',
      orderReference: 'ORD-2026-0101',
      createdAt: dayOutboundEarly,
    );
    await repository.createOutbound(
      warehouseId: warehouseId,
      itemId: itemId,
      quantity: 80,
      partyName: 'المندوب أحمد',
      orderReference: 'ORD-2026-0102',
      createdAt: dayOutboundLate,
    );

    final TransactionModel replacement = await repository
        .createPendingMarketReplacement(
          warehouseId: warehouseId,
          itemId: itemId,
          quantity: 20,
          partyName: 'المندوب أحمد',
          orderReference: 'ORD-2026-0103',
          reason: 'بدل كراتين مرتجعة تالفة',
          createdAt: dayReplacement,
        );
    await repository.approvePendingTransaction(replacement.id!);

    final TransactionModel damage = await repository
        .createPendingInternalDamage(
          warehouseId: warehouseId,
          itemId: itemId,
          quantity: 10,
          reason: 'تلف أثناء التخزين',
          responsibleName: 'سالم عبدالله الشامي',
          createdAt: dayDamage,
        );
    await repository.approvePendingTransaction(damage.id!);

    // طلب معلّق وآخر مرفوض: لا يظهران في أي تقرير ولا يؤثران على الرصيد.
    await repository.createPendingMarketReplacement(
      warehouseId: warehouseId,
      itemId: itemId,
      quantity: 15,
      partyName: 'المندوب أحمد',
      orderReference: 'ORD-2026-0104',
      reason: 'طلب لم يُعتمد بعد',
      createdAt: DateTime(2026, 11, 23, 14),
    );
    final TransactionModel rejected = await repository
        .createPendingMarketReplacement(
          warehouseId: warehouseId,
          itemId: itemId,
          quantity: 25,
          partyName: 'المندوب أحمد',
          orderReference: 'ORD-2026-0105',
          reason: 'طلب مرفوض',
          createdAt: DateTime(2026, 11, 23, 15),
        );
    await repository.rejectPendingTransaction(rejected.id!, 'مستندات ناقصة');
  });

  tearDown(() async {
    await helper.close();
  });

  // ---------------------------------------------------------------------------
  // 1) كشف مسحوبات المندوب
  // ---------------------------------------------------------------------------

  test('كشف المندوب يجمع الصرف وبدل التالف المعتمد فقط', () async {
    final RepresentativeLedger ledger = await repository
        .getRepresentativeLedger(
          representativeName: 'المندوب أحمد',
          startDate: day,
          endDate: day,
        );

    expect(ledger.representativeName, 'المندوب أحمد');
    expect(ledger.voucherCount, 3);
    expect(ledger.totalCartons, 220);
    expect(ledger.outboundCount, 2);
    expect(ledger.replacementCount, 1);
    expect(ledger.isEmpty, isFalse);
    expect(ledger.startDate, DateTime(2026, 11, 23));
    expect(ledger.endDate, DateTime(2026, 11, 23));

    // مرتبة زمنيًا من الأقدم إلى الأحدث.
    expect(
      ledger.transactions.first.createdAt.isBefore(
        ledger.transactions.last.createdAt,
      ),
      isTrue,
    );

    final RepresentativeLedger saeed = await repository.getRepresentativeLedger(
      representativeName: 'المندوب سعيد',
      startDate: day,
      endDate: day,
    );
    expect(saeed.totalCartons, 0);
    expect(saeed.isEmpty, isTrue);
    expect(saeed.voucherCount, 0);
  });

  test('كشف المندوب يحترم الفترة المحددة ويشمل أيامها كاملة', () async {
    final RepresentativeLedger wide = await repository.getRepresentativeLedger(
      representativeName: 'المندوب أحمد',
      startDate: DateTime(2026, 11, 21),
      endDate: day,
    );

    expect(wide.totalCartons, 260);
    expect(wide.voucherCount, 4);

    final RepresentativeLedger previousDay = await repository
        .getRepresentativeLedger(
          representativeName: 'المندوب أحمد',
          startDate: DateTime(2026, 11, 22),
          endDate: DateTime(2026, 11, 22),
        );
    expect(previousDay.isEmpty, isTrue);
  });

  test('كشف المندوب يرفض الاسم الفارغ والفترة المقلوبة', () async {
    await expectLater(
      repository.getRepresentativeLedger(
        representativeName: '   ',
        startDate: day,
        endDate: day,
      ),
      throwsA(isA<ArgumentError>()),
    );

    await expectLater(
      repository.getRepresentativeLedger(
        representativeName: 'المندوب أحمد',
        startDate: day,
        endDate: DateTime(2026, 11, 21),
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  // ---------------------------------------------------------------------------
  // 2) اليومية المخزنية
  // ---------------------------------------------------------------------------

  test('اليومية تحسب رصيد بداية ونهاية اليوم والتجميعات بدقة', () async {
    final DailyJournalReport journal = await repository.getDailyJournalReport(
      date: day,
    );

    expect(journal.openingBalance, 510);
    expect(journal.closingBalance, 380);
    expect(journal.inboundCartons, 100);
    expect(journal.outboundCartons, 200);
    expect(journal.replacementCartons, 20);
    expect(journal.damagedCartons, 10);
    expect(journal.damagedAndReplacementCartons, 30);
    expect(journal.netChange, -130);
    expect(journal.voucherCount, 5);
    expect(journal.inboundTransactions, hasLength(1));
    expect(journal.outboundTransactions, hasLength(2));
    expect(journal.replacementTransactions, hasLength(1));
    expect(journal.damageTransactions, hasLength(1));
    expect(journal.isEmpty, isFalse);
  });

  test('يومية يوم سابق تستبعد حركات الأيام اللاحقة من رصيد الإغلاق', () async {
    final DailyJournalReport previous = await repository.getDailyJournalReport(
      date: DateTime(2026, 11, 22),
    );

    expect(previous.openingBalance, 60);
    expect(previous.closingBalance, 510);
    expect(previous.inboundCartons, 500);
    expect(previous.outboundCartons, 50);
    expect(previous.voucherCount, 2);

    final DailyJournalReport empty = await repository.getDailyJournalReport(
      date: DateTime(2026, 10, 1),
    );
    expect(empty.isEmpty, isTrue);
    expect(empty.openingBalance, empty.closingBalance);
  });

  test('اليومية تحترم تحديد المخزن', () async {
    final WarehouseModel second = await warehouseRepository.create(
      WarehouseModel(
        name: 'مخزن الفرع',
        location: 'الفرع الجنوبي',
        createdAt: beforeDay,
      ),
    );

    final DailyJournalReport mainJournal = await repository
        .getDailyJournalReport(date: day, warehouseId: warehouseId);
    expect(mainJournal.voucherCount, 5);
    expect(mainJournal.closingBalance, 380);

    final DailyJournalReport branchJournal = await repository
        .getDailyJournalReport(date: day, warehouseId: second.id);
    expect(branchJournal.isEmpty, isTrue);
    expect(branchJournal.closingBalance, 0);
  });

  // ---------------------------------------------------------------------------
  // 3) مزوّد التقارير
  // ---------------------------------------------------------------------------

  test('ReportsProvider يحمّل كشف المندوب واليومية ويحسب الإجماليات', () async {
    final ReportsProvider provider = ReportsProvider(repository: repository);

    await provider.loadRepresentativeLedger(
      'المندوب أحمد',
      start: day,
      end: day,
    );
    expect(provider.selectedDistributor, 'المندوب أحمد');
    expect(provider.distributorTotalCartons, 220);
    expect(provider.distributorTotalBottles, 4400);
    expect(provider.distributorVoucherCount, 3);
    expect(provider.distributorLedgerTransactions, hasLength(3));
    expect(provider.isLoadingDistributor, isFalse);
    expect(provider.distributorError, isNull);

    await provider.loadDailyJournal(day);
    expect(provider.selectedJournalDate, DateTime(2026, 11, 23));
    expect(provider.dailyJournalData, isNotNull);
    expect(provider.dailyJournalData!.openingBalance, 510);
    expect(provider.dailyJournalData!.closingBalance, 380);
    expect(provider.isLoadingJournal, isFalse);
    expect(provider.journalError, isNull);

    provider.dispose();
  });

  // ---------------------------------------------------------------------------
  // 4) مستندات PDF
  // ---------------------------------------------------------------------------

  test('كشف مسحوبات المندوب يُطبع بمقاس A4 مع أسماء التواقيع', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initializeDateFormatting(AppConstants.localeCode);

    final ByteData fontData = await rootBundle.load(PdfService.fontAssetPath);
    final pw.Font font = pw.Font.ttf(fontData);
    final PdfService service = PdfService(
      regularFont: font,
      boldFont: font,
      allowNetworkFonts: false,
      storekeeperName: 'سالم عبدالله الشامي',
    );

    final RepresentativeLedger ledger = await repository
        .getRepresentativeLedger(
          representativeName: 'المندوب أحمد',
          startDate: DateTime(2026, 11, 21),
          endDate: day,
        );
    final DateTime generatedAt = DateTime(2026, 11, 23, 21, 30);

    final Uint8List bytes = await service.generateRepresentativeStatementPdf(
      ledger: ledger,
      item: item,
      generatedAt: generatedAt,
      representativePhone: '777123456',
      representativeVehicle: '1234-أ ب ج',
      warehouse: warehouse,
      warehouseNames: <int, String>{warehouseId: warehouse.name},
    );

    _expectValidPdf(bytes);
    _expectA4Pages(bytes);
    expect(
      PdfService.representativeStatementReference(generatedAt),
      'RST-20261123-2130',
    );
    expect(
      PdfService.fileNameForRepresentativeStatement(generatedAt),
      'REP-STATEMENT-20261123-2130.pdf',
    );
    expect(
      PdfService.storekeeperSignatureTitle('سالم عبدالله الشامي'),
      'أمين المخزن المسؤول: سالم عبدالله الشامي',
    );
    expect(
      AppFormatters.formatQuantityWithBottles(ledger.totalCartons),
      '260 كرتون (5,200 عبوة)',
    );
  });

  test('اليومية المخزنية تُطبع بمقاس A4 وتحمل مرجع اليوم', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initializeDateFormatting(AppConstants.localeCode);

    final ByteData fontData = await rootBundle.load(PdfService.fontAssetPath);
    final pw.Font font = pw.Font.ttf(fontData);
    final PdfService service = PdfService(
      regularFont: font,
      boldFont: font,
      allowNetworkFonts: false,
      storekeeperName: 'سالم عبدالله الشامي',
    );

    final DailyJournalReport journal = await repository.getDailyJournalReport(
      date: day,
    );

    final Uint8List bytes = await service.generateDailyJournalPdf(
      journal: journal,
      item: item,
      generatedAt: DateTime(2026, 11, 23, 22),
      warehouse: warehouse,
    );

    _expectValidPdf(bytes);
    _expectA4Pages(bytes);
    expect(PdfService.dailyJournalReference(day), 'DJ-20261123');
    expect(
      PdfService.fileNameForDailyJournal(day),
      'DAILY-JOURNAL-20261123.pdf',
    );
  });

  test('كشف فارغ ويومية فارغة يُولّدان مستنداً صالحاً بلا أخطاء', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initializeDateFormatting(AppConstants.localeCode);

    final ByteData fontData = await rootBundle.load(PdfService.fontAssetPath);
    final pw.Font font = pw.Font.ttf(fontData);
    final PdfService service = PdfService(
      regularFont: font,
      boldFont: font,
      allowNetworkFonts: false,
      storekeeperName: 'سالم عبدالله الشامي',
    );

    final RepresentativeLedger emptyLedger = await repository
        .getRepresentativeLedger(
          representativeName: 'مندوب جديد',
          startDate: day,
          endDate: day,
        );
    _expectValidPdf(
      await service.generateRepresentativeStatementPdf(
        ledger: emptyLedger,
        item: item,
        generatedAt: DateTime(2026, 11, 23, 21, 30),
      ),
    );

    final DailyJournalReport emptyJournal = await repository
        .getDailyJournalReport(date: DateTime(2026, 10, 1));
    _expectValidPdf(
      await service.generateDailyJournalPdf(
        journal: emptyJournal,
        item: item,
        generatedAt: DateTime(2026, 11, 23, 22),
      ),
    );
  });
}
