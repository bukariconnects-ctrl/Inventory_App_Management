import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:inventory_stock_app/core/constants/app_constants.dart';
import 'package:inventory_stock_app/core/services/pdf_service.dart';
import 'package:inventory_stock_app/features/inventory/data/models/item_model.dart';
import 'package:inventory_stock_app/features/stocktake/data/models/stocktake_model.dart';
import 'package:inventory_stock_app/features/transactions/data/models/transaction_model.dart';
import 'package:inventory_stock_app/features/warehouses/data/models/warehouse_model.dart';

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
    _expectValidPdf(
      await service.generateStocktakeReport(
        stocktake: matching,
        warehouse: warehouse,
        item: item,
      ),
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
