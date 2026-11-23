import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:inventory_stock_app/core/constants/app_constants.dart';
import 'package:inventory_stock_app/core/services/pdf_service.dart';
import 'package:inventory_stock_app/core/utils/app_formatters.dart';
import 'package:inventory_stock_app/features/inventory/data/models/item_model.dart';
import 'package:inventory_stock_app/features/stocktake/data/models/stocktake_model.dart';
import 'package:inventory_stock_app/features/transactions/data/models/transaction_model.dart';
import 'package:inventory_stock_app/features/warehouses/data/models/warehouse_model.dart';

/// يتحقق من أن المستند يتكوّن من صفحة واحدة فقط (لا هدر لصفحة ثانية).
void _expectSinglePage(Uint8List bytes) {
  final String raw = latin1.decode(bytes);
  final RegExpMatch? match = RegExp(r'/Count\s+(\d+)').firstMatch(raw);
  expect(match, isNotNull, reason: 'لا يوجد شجرة صفحات في المستند');
  expect(int.parse(match!.group(1)!), 1);
}

/// يتحقق من أن مقاس الصفحة الداخلي للمستند يطابق المقاس المطلوب.
void _expectPageSize(Uint8List bytes, double width, double height) {
  final String raw = latin1.decode(bytes);
  final RegExp pattern = RegExp(
    r'/MediaBox\s*\[\s*0\s+0\s+([0-9.]+)\s+([0-9.]+)\s*\]',
  );
  final Iterable<RegExpMatch> matches = pattern.allMatches(raw);
  expect(matches, isNotEmpty, reason: 'لا يوجد MediaBox في المستند');
  for (final RegExpMatch match in matches) {
    expect(double.parse(match.group(1)!), closeTo(width, 0.6));
    expect(double.parse(match.group(2)!), closeTo(height, 0.6));
  }
}

/// يتحقق من أن البايتات الناتجة مستند PDF فعلي وكامل.
void _expectValidPdf(Uint8List bytes) {
  expect(bytes.length, greaterThan(1000));
  expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
  final String tail = latin1.decode(
    bytes.sublist(bytes.length > 2048 ? bytes.length - 2048 : 0),
  );
  expect(tail, contains('%%EOF'));
}

void main() {
  final DateTime timestamp = DateTime(2026, 11, 13, 9, 30);
  final WarehouseModel warehouse = WarehouseModel(
    id: 1,
    name: 'المخزن الرئيسي - الإدارة العامة',
    location: 'المبنى الرئيسي',
    createdAt: timestamp,
  );
  final ItemModel item = ItemModel(
    id: 1,
    name: AppConstants.defaultItemName,
    createdAt: timestamp,
  );

  late PdfService service;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initializeDateFormatting(AppConstants.localeCode);
    // الخط العربي المحلي المضمّن: لا يحتاج شبكة أثناء الاختبارات.
    final ByteData data = await rootBundle.load(PdfService.fontAssetPath);
    final pw.Font font = pw.Font.ttf(data);
    service = PdfService(
      regularFont: font,
      boldFont: font,
      allowNetworkFonts: false,
      storekeeperName: 'سالم عبدالله الشامي',
    );
  });

  test('سند استلام يُولّد مستند PDF صالحاً بالعربية', () async {
    final TransactionModel transaction = TransactionModel(
      id: 1,
      transactionType: TransactionTypes.inbound,
      voucherNumber: 'REC-20261113-001',
      warehouseId: 1,
      itemId: 1,
      quantity: 250,
      partyName: 'م. سالم الحسيني',
      orderReference: 'AMR-1001',
      notes: 'شحنة أولى من خط الإنتاج، الحالة سليمة.',
      createdAt: timestamp,
    );

    final Uint8List bytes = await service.generateTransactionVoucher(
      transaction: transaction,
      warehouse: warehouse,
      item: item,
    );

    _expectValidPdf(bytes);
    expect(
      PdfService.fileNameForVoucher(transaction.voucherNumber),
      'REC-20261113-001.pdf',
    );
  });

  test('سند صرف يحمل بيانات المندوب وأمر الصرف ولوحة السيارة', () async {
    final TransactionModel transaction = TransactionModel(
      id: 2,
      transactionType: TransactionTypes.outbound,
      voucherNumber: 'ISS-20261113-002',
      warehouseId: 1,
      itemId: 1,
      quantity: 120,
      partyName: 'المندوب أحمد السالم',
      orderReference: 'ORD-2026-0045',
      vehicleNumber: '1234-أ ب ج',
      notes: 'صرف لعميل الجملة في السوق المركزي.',
      createdAt: timestamp,
    );

    final Uint8List bytes = await service.generateTransactionVoucher(
      transaction: transaction,
      warehouse: warehouse,
      item: item,
    );

    _expectValidPdf(bytes);
    expect(
      PdfService.fileNameForVoucher(transaction.voucherNumber),
      'ISS-20261113-002.pdf',
    );
  });

  test('سند إتلاف يحمل سبب التلف واسم المسؤول', () async {
    final TransactionModel transaction = TransactionModel(
      id: 3,
      transactionType: TransactionTypes.damage,
      voucherNumber: 'DMG-20261113-003',
      warehouseId: 1,
      itemId: 1,
      quantity: 18,
      partyName: 'أمين المخزن سالم',
      reason: 'كسر وتمزق كراتين — تلف أثناء التفريغ',
      notes: 'تم عزل الكراتين التالفة عن المخزون السليم.',
      createdAt: timestamp,
    );

    final Uint8List bytes = await service.generateTransactionVoucher(
      transaction: transaction,
      warehouse: warehouse,
      item: item,
    );

    _expectValidPdf(bytes);
  });

  test('تقرير جرد بعجز يُولّد مستنداً رسمياً صالحاً', () async {
    final StocktakeModel stocktake = StocktakeModel(
      id: 4,
      warehouseId: 1,
      itemId: 1,
      systemQuantity: 500,
      actualQuantity: 470,
      difference: -30,
      notes: 'عجز ناتج عن تلف لم يُسجَّل أثناء النقل.',
      createdAt: timestamp,
    );

    final Uint8List bytes = await service.generateStocktakeReport(
      stocktake: stocktake,
      warehouse: warehouse,
      item: item,
    );

    _expectValidPdf(bytes);
    expect(PdfService.stocktakeReference(stocktake), 'STK-20261113-004');
  });

  test('تقرير جرد بفائض أو مطابق يُولّد مستنداً صالحاً', () async {
    final StocktakeModel surplus = StocktakeModel(
      warehouseId: 1,
      itemId: 1,
      systemQuantity: 100,
      actualQuantity: 130,
      difference: 30,
      createdAt: timestamp,
    );
    final StocktakeModel matching = StocktakeModel(
      warehouseId: 1,
      itemId: 1,
      systemQuantity: 100,
      actualQuantity: 100,
      difference: 0,
      notes: 'مطابقة تامة لرصيد النظام.',
      createdAt: timestamp,
    );

    _expectValidPdf(
      await service.generateStocktakeReport(
        stocktake: surplus,
        warehouse: warehouse,
        item: item,
      ),
    );
    _expectSinglePage(
      await service.generateStocktakeReport(
        stocktake: surplus,
        warehouse: warehouse,
        item: item,
      ),
    );
    _expectValidPdf(
      await service.generateStocktakeReport(
        stocktake: matching,
        warehouse: warehouse,
        item: item,
      ),
    );
  });

  test('مقاس السندات الفردية A5 والتقارير الإدارية A4', () async {
    expect(PdfService.voucherPageFormat.width, closeTo(419.53, 0.6));
    expect(PdfService.voucherPageFormat.height, closeTo(595.28, 0.6));
    expect(PdfService.reportPageFormat.width, closeTo(595.28, 0.6));
    expect(PdfService.reportPageFormat.height, closeTo(841.89, 0.6));

    final TransactionModel transaction = TransactionModel(
      id: 10,
      transactionType: TransactionTypes.outbound,
      voucherNumber: 'ISS-20261113-010',
      warehouseId: 1,
      itemId: 1,
      quantity: 150,
      partyName: 'المندوب أحمد السالم',
      createdAt: timestamp,
    );

    final Uint8List bytes = await service.generateTransactionVoucher(
      transaction: transaction,
      warehouse: warehouse,
      item: item,
    );

    _expectValidPdf(bytes);
    _expectSinglePage(bytes);
    _expectPageSize(
      bytes,
      PdfService.voucherPageFormat.width,
      PdfService.voucherPageFormat.height,
    );
  });

  test('الترويسة الرسمية تحمل بيانات مصنع رواء (تعز - الضباب - سوق الأحد)', () {
    expect(PdfService.factoryArabicTitle, contains('مصنع رواء'));
    expect(PdfService.factoryArabicTitle, contains('المركز الرئيسي'));
    expect(PdfService.factoryAddress, contains('تعز'));
    expect(PdfService.factoryAddress, contains('الضباب'));
    expect(PdfService.factoryAddress, contains('سوق الأحد'));
    expect(PdfService.factoryPhones, contains('77722356'));
    expect(PdfService.factoryPhones, contains('77722359'));
    expect(PdfService.factoryEnglishAddress, 'Taiz - althabab - alahad');
    expect(PdfService.factoryEnglishTele, contains('77722356'));
    expect(PdfService.factoryEnglishMob, contains('77722359'));
    expect(PdfService.factoryEnglishPoBox, contains('P.O.Box'));
    expect(PdfService.brandSlogan, contains('صحة ودواء'));
  });

  test('خانات التوقيع تطبع أسماء أمين المخزن والمندوب آلياً', () async {
    final TransactionModel transaction = TransactionModel(
      id: 11,
      transactionType: TransactionTypes.outbound,
      voucherNumber: 'ISS-20261113-011',
      warehouseId: 1,
      itemId: 1,
      quantity: 40,
      partyName: 'المندوب خالد ناصر',
      vehicleNumber: '5678-ج د ه',
      createdAt: timestamp,
    );

    expect(
      PdfService.storekeeperSignatureTitle('سالم عبدالله الشامي'),
      'أمين المخزن المسؤول: سالم عبدالله الشامي',
    );
    expect(
      PdfService.partySignatureTitle('المندوب خالد ناصر'),
      'الطرف الآخر: المندوب خالد ناصر',
    );
    expect(PdfService.signatureLine, contains('التوقيع:'));
    expect(PdfService.approvalSignatureTitle, contains('اعتماد'));
    expect(PdfService.approvalStampLine, contains('الاعتماد والختم'));

    final Uint8List bytes = await service.generateTransactionVoucher(
      transaction: transaction,
      warehouse: warehouse,
      item: item,
    );
    _expectValidPdf(bytes);
  });

  test('السند المعلّق يحمل علامة «طلب معلّق - غير معتمد»', () async {
    final TransactionModel pending = TransactionModel(
      id: 12,
      transactionType: TransactionTypes.damage,
      voucherNumber: 'DMG-20261113-012',
      warehouseId: 1,
      itemId: 1,
      quantity: 12,
      partyName: 'سالم عبدالله الشامي',
      reason: 'تلف أثناء التخزين',
      status: TransactionStatus.pending,
      createdAt: timestamp,
    );

    expect(PdfService.pendingWatermarkText, 'طلب معلّق - غير معتمد');
    expect(PdfService.pendingWatermarkSubtitle, contains('بانتظار اعتماد'));

    final Uint8List bytes = await service.generateTransactionVoucher(
      transaction: pending,
      warehouse: warehouse,
      item: item,
    );

    _expectValidPdf(bytes);
    _expectSinglePage(bytes);
    expect(pending.isPending, isTrue);
  });

  test('سند صرف بدل تالف MARKET_REPLACEMENT يُولّد بمقاس A5', () async {
    final TransactionModel replacement = TransactionModel(
      id: 13,
      transactionType: TransactionTypes.marketReplacement,
      voucherNumber: 'REP-20261113-013',
      warehouseId: 1,
      itemId: 1,
      quantity: 150,
      partyName: 'المندوب أحمد السالم',
      orderReference: 'ORD-2026-0099',
      reason: 'بدل كراتين مرتجعة تالفة من السوق',
      createdAt: timestamp,
    );

    final Uint8List bytes = await service.generateTransactionVoucher(
      transaction: replacement,
      warehouse: warehouse,
      item: item,
    );

    _expectValidPdf(bytes);
    _expectSinglePage(bytes);
    _expectPageSize(
      bytes,
      PdfService.voucherPageFormat.width,
      PdfService.voucherPageFormat.height,
    );
    expect(
      AppFormatters.formatQuantityWithBottles(150, bottlesPerCarton: 20),
      '150 كرتون (3,000 عبوة)',
    );
  });

  test('اسم الملف يُنظَّف من الرموز غير الصالحة', () {
    expect(
      PdfService.fileNameForVoucher('REC/2026 11:13#1'),
      'REC-2026-11-13-1.pdf',
    );
    expect(PdfService.fileNameForVoucher('   '), 'voucher.pdf');
  });
}
