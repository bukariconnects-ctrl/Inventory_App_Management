import 'dart:typed_data';

import 'package:flutter/services.dart' show ByteData, rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../features/inventory/data/models/item_model.dart';
import '../../features/reports/data/models/report_models.dart';
import '../../features/stocktake/data/models/stocktake_model.dart';
import '../../features/transactions/data/models/transaction_model.dart';
import '../../features/warehouses/data/models/warehouse_model.dart';
import '../constants/app_constants.dart';
import '../database/database_helper.dart';
import '../utils/app_formatters.dart';

// ---------------------------------------------------------------------------
// هوية المستند الورقية (نفس ألوان النظام).
// ---------------------------------------------------------------------------

final PdfColor _pdfPrimary = PdfColor.fromHex('#0077B6');
final PdfColor _pdfPrimaryDark = PdfColor.fromHex('#023E8A');
final PdfColor _pdfDanger = PdfColor.fromHex('#D64545');
final PdfColor _pdfWarning = PdfColor.fromHex('#F4A100');
final PdfColor _pdfText = PdfColor.fromHex('#0B2A3D');
final PdfColor _pdfMuted = PdfColor.fromHex('#5B7A8C');
final PdfColor _pdfOutline = PdfColor.fromHex('#D3E3EE');
final PdfColor _pdfSoft = PdfColor.fromHex('#F5F9FC');
final PdfColor _pdfTotalRow = PdfColor.fromHex('#ECECEC');

/// خدمة توليد سندات PDF العربية الرسمية (استلام/صرف/إتلاف/بدل تالف/تسوية)
/// ومحاضر الجرد وتقارير المخزون، بترويسة مصنع رواء الرسمية.
///
/// التصميم محاسبي رسمي مؤطر بجداول (ERP): سندات A5 بإطار ترويسة وشبكة بيانات
/// وجدول صنف مؤطر، وتقارير A4 بجدول حركة تحليلي ورصيد تراكمي وتذييل من 3 أقسام.
///
/// الخط العربي: يُحمَّل من أصل محلي مضمَّن (`assets/fonts/Cairo-Regular.ttf`) حتى
/// تعمل الطباعة دون إنترنت، ثم يُجرَّب خط Google Fonts (Cairo) عند غياب الأصل،
/// وأخيرًا خط PDF الافتراضي. يمكن حقن خطوط/شعار جاهزين (مثلًا في الاختبارات).
class PdfService {
  PdfService({
    pw.Font? regularFont,
    pw.Font? boldFont,
    bool allowNetworkFonts = true,
    String? storekeeperName,
    pw.MemoryImage? logo,
  }) : _injectedRegular = regularFont,
       _injectedBold = boldFont,
       _allowNetworkFonts = allowNetworkFonts,
       _injectedStorekeeperName = storekeeperName,
       _injectedLogo = logo;

  /// مسار الخط العربي المضمَّن في التطبيق.
  static const String fontAssetPath = 'assets/fonts/Cairo-Regular.ttf';

  /// مسار شعار مصنع رواء المضمَّن في التطبيق.
  static const String logoAssetPath = 'assets/images/rawaa_logo.png';

  // ---------------------------------------------------------------------------
  // الهوية الرسمية لمصنع رواء (تعز - الضباب - سوق الأحد)
  // ---------------------------------------------------------------------------

  static const String factoryArabicTitle =
      'مصنع رواء للمياه المعدنيه والمشروبات الغازيه - المركز الرئيسي';
  static const String factoryAddress = 'تعز  -  الضباب  -  سوق الأحد';
  static const String factoryPhones = 'هاتف: 77722356   |   موبايل: 77722359';
  static const String factoryEnglishAddress = 'Taiz - althabab - alahad';
  static const String factoryEnglishTele = 'Tele No. 77722356';
  static const String factoryEnglishMob = 'Mob No. 77722359';
  static const String factoryEnglishPoBox = 'P.O.Box -----------';
  static const String brandSlogan = 'مياه رواء - صحة ودواء';

  /// النص المائي الذي يُرسم على السندات غير المعتمدة.
  static const String pendingWatermarkText = 'طلب معلّق - غير معتمد';
  static const String pendingWatermarkSubtitle = '( بانتظار اعتماد الإدارة )';

  /// عناوين خانات التواقيع المطبوعة آليًا.
  static const String approvalSignatureTitle = 'اعتماد مدير المصنع / الإدارة';
  static const String approvalStampLine =
      'الاعتماد والختم: ........................................';
  static const String signatureLine =
      'التوقيع: ........................................';

  /// عنوان خانة أمين المخزن مع الاسم المحفوظ في الإعدادات.
  static String storekeeperSignatureTitle(String name) =>
      'أمين المخزن المسؤول: ${name.trim().isEmpty ? AppConstants.defaultStorekeeperName : name.trim()}';

  /// عنوان خانة الطرف الآخر مع اسمه المطبوع على السند.
  static String partySignatureTitle(String? partyName) {
    final String name = (partyName ?? '').trim();
    return name.isEmpty ? 'الطرف الآخر: غير محدد' : 'الطرف الآخر: $name';
  }

  /// مقاس السندات الفردية ومحاضر الجرد (A5 رأسي: 148 × 210 مم).
  static PdfPageFormat get voucherPageFormat => PdfPageFormat.a5;

  /// مقاس التقارير الإدارية المجمعة (A4 رأسي).
  static PdfPageFormat get reportPageFormat => PdfPageFormat.a4;

  final pw.Font? _injectedRegular;
  final pw.Font? _injectedBold;
  final bool _allowNetworkFonts;
  final String? _injectedStorekeeperName;
  final pw.MemoryImage? _injectedLogo;

  _PdfFonts? _fonts;
  pw.MemoryImage? _cachedLogo;

  /// هوامش السند الفردي (14–18 pt) لملء صفحة A5 دون فراغات مهدرة.
  static const pw.EdgeInsets _voucherMargin = pw.EdgeInsets.fromLTRB(
    15,
    10,
    15,
    10,
  );

  /// هوامش التقارير الإدارية A4.
  static const pw.EdgeInsets _reportMargin = pw.EdgeInsets.fromLTRB(
    26,
    24,
    26,
    28,
  );

  // ---------------------------------------------------------------------------
  // واجهات التوليد العامة
  // ---------------------------------------------------------------------------

  /// يبني سند PDF رسميًا لحركة مخزنية واحدة بمقاس A5.
  Future<Uint8List> generateTransactionVoucher({
    required TransactionModel transaction,
    required WarehouseModel warehouse,
    required ItemModel item,
    String? storekeeperName,
  }) async {
    final _PdfFonts fonts = await _resolveFonts();
    final _VoucherTypeInfo info = _infoFor(transaction.transactionType);
    final String keeperName = await _resolveStorekeeperName(storekeeperName);
    await _ensureLogo();
    final bool pending = transaction.isPending;
    final int perCarton = _bottlesPerCarton(item);
    final int cartons = transaction.quantity.abs();

    final pw.Document document = pw.Document(
      title: '${info.title} - ${transaction.voucherNumber}',
      author: AppConstants.appTitle,
      creator: AppConstants.appTitle,
      subject: 'سند مخزني رسمي - مصنع رواء',
    );

    document.addPage(
      pw.MultiPage(
        pageTheme: _pageTheme(
          fonts: fonts,
          format: voucherPageFormat,
          margin: _voucherMargin,
          pending: pending,
        ),
        footer: (pw.Context context) => _pageFooter(
          context: context,
          printedBy: keeperName,
          printedAt: transaction.createdAt,
        ),
        build: (pw.Context context) => _rtl(<pw.Widget>[
          buildOfficialLetterhead(
            title: info.documentTitle,
            voucherNumber: transaction.voucherNumber,
            accent: info.accent,
          ),
          pw.SizedBox(height: 4),
          _voucherTitleBar(info.title, accent: info.accent),
          if (pending) ...<pw.Widget>[
            pw.SizedBox(height: 4),
            _statusBanner(
              title: pendingWatermarkText,
              subtitle:
                  'لم يُخصم أي رصيد من المخزن. يُنفَّذ السند فقط بعد اعتماد الإدارة.',
            ),
          ],
          pw.SizedBox(height: 5),
          _erpInfoGrid(
            primary: <_ErpField>[
              _ErpField('رقم السند', transaction.voucherNumber),
              _ErpField(
                'التاريخ',
                AppFormatters.dateTime(transaction.createdAt),
              ),
              _ErpField(
                'رقم أمر الصرف / المرجع',
                _valueOrFallback(_orderReference(transaction)),
              ),
              _ErpField('المخزن', _warehouseLine(warehouse)),
            ],
            secondary: <_ErpField>[
              _ErpField('نوع الحركة', info.movementLabel),
              _ErpField(
                'البيان / المستلم',
                _valueOrFallback(transaction.partyName),
              ),
              _ErpField('السبب / الملاحظات', _remarks(transaction)),
              _ErpField(
                'رقم اللوحة / السيارة',
                _valueOrFallback(transaction.vehicleNumber),
              ),
            ],
          ),
          pw.SizedBox(height: 6),
          _erpTable(
            headers: <String>[
              'م',
              'رقم الصنف',
              'اسم الصنف',
              'المواصفات',
              'الوحدة',
              'الكمية (كرتون)',
              'إجمالي العبوات',
            ],
            rows: <List<String>>[
              <String>[
                '1',
                _itemCode(item),
                item.name,
                _specifications(item),
                AppConstants.cartonUnit,
                AppFormatters.number(cartons),
                AppFormatters.number(cartons * perCarton),
              ],
            ],
            flexes: <double>[0.5, 1.2, 2.4, 2.4, 1.0, 1.4, 1.5],
            borderWidth: 0.8,
            bodyFontSize: 7.4,
          ),
          pw.SizedBox(height: 3),
          _packagesTotalBar(cartons: cartons, perCarton: perCarton),
          pw.SizedBox(height: 7),
          _voucherSignatureRow(
            storekeeperName: keeperName,
            receiverLabel: info.receiverLabel,
            receiverName: transaction.partyName,
          ),
        ]),
      ),
    );

    return document.save();
  }

  /// يبني محضر جرد وتسوية رسميًا لسجل جرد واحد بمقاس A5.
  Future<Uint8List> generateStocktakeReport({
    required StocktakeModel stocktake,
    required WarehouseModel warehouse,
    required ItemModel item,
    String? storekeeperName,
  }) async {
    final _PdfFonts fonts = await _resolveFonts();
    final String keeperName = await _resolveStorekeeperName(storekeeperName);
    await _ensureLogo();
    final String reference = stocktakeReference(stocktake);
    final int perCarton = _bottlesPerCarton(item);
    final int actual = stocktake.actualQuantity;
    final String status;
    final PdfColor accent;

    if (stocktake.difference == 0) {
      status = 'مطابق تماماً للرصيد الدفتري';
      accent = _pdfPrimaryDark;
    } else if (stocktake.isShortage) {
      status =
          'عجز بمقدار '
          '${AppFormatters.number(stocktake.difference.abs())} ${item.unit}';
      accent = _pdfDanger;
    } else {
      status =
          'فائض بمقدار '
          '${AppFormatters.number(stocktake.difference)} ${item.unit}';
      accent = _pdfWarning;
    }

    final pw.Document document = pw.Document(
      title: 'محضر جرد - $reference',
      author: AppConstants.appTitle,
      creator: AppConstants.appTitle,
      subject: 'محضر جرد وتسوية - مصنع رواء',
    );

    document.addPage(
      pw.MultiPage(
        pageTheme: _pageTheme(
          fonts: fonts,
          format: voucherPageFormat,
          margin: _voucherMargin,
          pending: false,
        ),
        footer: (pw.Context context) => _pageFooter(
          context: context,
          printedBy: keeperName,
          printedAt: stocktake.createdAt,
        ),
        build: (pw.Context context) => _rtl(<pw.Widget>[
          buildOfficialLetterhead(
            title: 'محضر جرد وتسوية مخزنية',
            voucherNumber: reference,
            accent: accent,
          ),
          pw.SizedBox(height: 4),
          _voucherTitleBar('محضر جرد وتسوية مخزنية', accent: accent),
          pw.SizedBox(height: 5),
          _erpInfoGrid(
            primary: <_ErpField>[
              _ErpField('رقم المحضر', reference),
              _ErpField('التاريخ', AppFormatters.dateTime(stocktake.createdAt)),
              _ErpField('المخزن المجرود', _warehouseLine(warehouse)),
              _ErpField('نتيجة المطابقة', status),
            ],
            secondary: <_ErpField>[
              _ErpField('نوع الحركة', 'جرد وتسوية مخزنية'),
              _ErpField('البيان / المسؤول', keeperName),
              _ErpField(
                'السبب / الملاحظات',
                _hasText(stocktake.notes)
                    ? stocktake.notes!.trim()
                    : 'لا توجد ملاحظات مسجلة.',
              ),
              _ErpField('رقم اللوحة / السيارة', '—'),
            ],
          ),
          pw.SizedBox(height: 6),
          _erpTable(
            headers: <String>[
              'م',
              'رقم الصنف',
              'اسم الصنف',
              'المواصفات',
              'الوحدة',
              'الكمية (كرتون)',
              'إجمالي العبوات',
            ],
            rows: <List<String>>[
              <String>[
                '1',
                _itemCode(item),
                item.name,
                _specifications(item),
                AppConstants.cartonUnit,
                AppFormatters.number(actual),
                AppFormatters.number(actual * perCarton),
              ],
            ],
            flexes: <double>[0.5, 1.2, 2.4, 2.4, 1.0, 1.4, 1.5],
            borderWidth: 0.8,
            bodyFontSize: 7.4,
          ),
          pw.SizedBox(height: 3),
          _summaryStrip(<_ErpField>[
            _ErpField(
              'الرصيد الدفتري',
              AppFormatters.number(stocktake.systemQuantity),
            ),
            _ErpField('الرصيد الفعلي المعدود', AppFormatters.number(actual)),
            _ErpField(
              'الفارق',
              '${stocktake.difference < 0 ? '−' : '+'}'
                  '${AppFormatters.number(stocktake.difference.abs())}',
            ),
          ]),
          pw.SizedBox(height: 7),
          _voucherSignatureRow(
            storekeeperName: keeperName,
            receiverLabel: 'لجنة الجرد / المعتمد',
            receiverName: 'لجنة الجرد',
          ),
        ]),
      ),
    );

    return document.save();
  }

  /// يبني تقرير المخزون العام (حركة الفترة + مسحوبات المناديب) بصيغة A4.
  Future<Uint8List> generateInventorySummaryReportPdf({
    required PeriodSummaryMetrics metrics,
    required List<RepresentativeSummary> representatives,
    required ItemModel item,
    required DateTime generatedAt,
    WarehouseModel? warehouse,
    DateRange? period,
    String? storekeeperName,
  }) async {
    final _PdfFonts fonts = await _resolveFonts();
    final String keeperName = await _resolveStorekeeperName(storekeeperName);
    await _ensureLogo();
    final String reference = summaryReportReference(generatedAt);
    final int perCarton = _bottlesPerCarton(item);
    final String periodLabel = period == null
        ? 'كل الفترات المسجلة'
        : 'من ${AppFormatters.date(period.start)} إلى '
              '${AppFormatters.date(period.end)}';
    final String scopeLabel = warehouse?.name ?? 'كل المخازن';
    final int totalRepVouchers = representatives.fold<int>(
      0,
      (int sum, RepresentativeSummary r) => sum + r.voucherCount,
    );

    final pw.Document document = pw.Document(
      title: 'تقرير المخزون العام - $reference',
      author: AppConstants.appTitle,
      creator: AppConstants.appTitle,
      subject: 'تقرير إداري لمجمل حركة المخزون - مصنع رواء',
    );

    document.addPage(
      pw.MultiPage(
        pageTheme: _pageTheme(
          fonts: fonts,
          format: reportPageFormat,
          margin: _reportMargin,
          pending: false,
        ),
        footer: (pw.Context context) => _pageFooter(
          context: context,
          printedBy: keeperName,
          printedAt: generatedAt,
        ),
        build: (pw.Context context) => _rtl(<pw.Widget>[
          buildOfficialLetterhead(
            title: 'تقرير حركة المخزون العام',
            voucherNumber: reference,
            accent: _pdfPrimary,
          ),
          pw.SizedBox(height: 6),
          _voucherTitleBar(
            'تقرير حركة مخزون تحليلي كميات',
            accent: _pdfPrimary,
          ),
          pw.SizedBox(height: 6),
          _identityBar(<_ErpField>[
            _ErpField('رقم الصنف', _itemCode(item), flex: 0.8),
            _ErpField(
              'اسم الصنف',
              '${item.name}  ${_specifications(item)}',
              flex: 2.0,
            ),
            _ErpField('الفترة', periodLabel, flex: 1.6),
            _ErpField('المخزن', scopeLabel, flex: 1.2),
          ]),
          pw.SizedBox(height: 10),
          _erpTable(
            headers: <String>[
              'الوارد (كرتون)',
              'المنصرف (كرتون)',
              'التالف (كرتون)',
              'صافي التغير',
              'عدد السندات',
            ],
            rows: <List<String>>[
              <String>[
                AppFormatters.number(metrics.totalInbound),
                AppFormatters.number(metrics.totalOutbound),
                AppFormatters.number(metrics.totalDamaged),
                '${metrics.netChange < 0 ? '−' : '+'}'
                    '${AppFormatters.number(metrics.netChange.abs())}',
                AppFormatters.number(metrics.voucherCount),
              ],
            ],
            flexes: <double>[1, 1, 1, 1, 1],
            bodyFontSize: 9,
          ),
          pw.SizedBox(height: 4),
          _notesBox(
            'المعادلة: الوارد − المنصرف − التالف = صافي التغير  |  '
            'سعة الكرتون: $perCarton قنينة × ${_bottleVolume(item)} مل  |  '
            'تاريخ الإصدار: ${AppFormatters.dateTime(generatedAt)}',
          ),
          pw.SizedBox(height: 12),
          _sectionTitle('مسحوبات المناديب (الأكثر سحباً)'),
          pw.SizedBox(height: 5),
          if (representatives.isEmpty)
            _notesBox('لا توجد عمليات صرف مسجلة في الفترة المحددة.')
          else
            _erpTable(
              headers: <String>[
                '#',
                'المندوب / الموزّع',
                'الكراتين',
                'العبوات',
                'عدد السندات',
                'النسبة',
              ],
              rows: <List<String>>[
                for (int index = 0; index < representatives.length; index++)
                  <String>[
                    '${index + 1}',
                    representatives[index].name,
                    AppFormatters.number(representatives[index].totalQuantity),
                    AppFormatters.number(
                      representatives[index].totalQuantity * perCarton,
                    ),
                    AppFormatters.number(representatives[index].voucherCount),
                    '${(representatives[index].shareOf(metrics.totalOutbound) * 100).round()}%',
                  ],
              ],
              flexes: <double>[0.5, 3.0, 1.2, 1.4, 1.2, 1.0],
              bodyFontSize: 8,
              alignRightIndex: 1,
              totalRow: <String>[
                '',
                'إجمالي كميات',
                AppFormatters.number(metrics.totalOutbound),
                AppFormatters.number(metrics.totalOutbound * perCarton),
                AppFormatters.number(totalRepVouchers),
                '100%',
              ],
            ),
          pw.SizedBox(height: 14),
          _signaturesLines(
            storekeeperName: keeperName,
            secondTitle: 'إدارة المخازن / المشرف',
            secondName: 'المشرف المخزني',
          ),
        ]),
      ),
    );

    return document.save();
  }

  /// يبني كشف مسحوبات موزّع/مندوب رسميًا بمقاس A4.
  ///
  /// يعرض شريط تعريف الصنف والفترة، ثم جدول الحركة التحليلي بأعمدة
  /// (المستند، التاريخ، النوع، البيان، الوحدة، الوارد، المنصرف، الرصيد)
  /// مع الرصيد التراكمي وسطر إجمالي ختامي وتذييل رسمي من 3 أقسام.
  Future<Uint8List> generateRepresentativeStatementPdf({
    required RepresentativeLedger ledger,
    required ItemModel item,
    required DateTime generatedAt,
    String? storekeeperName,
    String? representativePhone,
    String? representativeVehicle,
    WarehouseModel? warehouse,
    Map<int, String> warehouseNames = const <int, String>{},
  }) async {
    final _PdfFonts fonts = await _resolveFonts();
    final String keeperName = await _resolveStorekeeperName(storekeeperName);
    await _ensureLogo();

    final String reference = representativeStatementReference(generatedAt);
    final int perCarton = _bottlesPerCarton(item);
    final String periodLabel =
        'من ${AppFormatters.date(ledger.startDate)} إلى '
        '${AppFormatters.date(ledger.endDate)}';
    final String scopeLabel = warehouse?.name ?? 'كل المخازن';
    final String contact = _contactLine(
      phone: representativePhone,
      vehicle: representativeVehicle,
    );

    final List<_LedgerRow> rows = <_LedgerRow>[];
    int running = 0;
    for (final TransactionModel transaction in ledger.transactions) {
      final int quantity = transaction.quantity.abs();
      running += quantity;
      rows.add(
        _LedgerRow(
          voucherNumber: transaction.voucherNumber,
          date: AppFormatters.date(transaction.createdAt),
          documentType: _typeLabel(transaction.transactionType),
          description: _movementDescription(transaction),
          outbound: quantity,
          balance: running,
        ),
      );
    }
    int inboundTotal = 0;
    int outboundTotal = 0;
    for (final _LedgerRow row in rows) {
      inboundTotal += row.inbound;
      outboundTotal += row.outbound;
    }

    final pw.Document document = pw.Document(
      title: 'كشف مسحوبات ${ledger.representativeName} - $reference',
      author: AppConstants.appTitle,
      creator: AppConstants.appTitle,
      subject: 'كشف مسحوبات موزع/مندوب - مصنع رواء',
    );

    document.addPage(
      pw.MultiPage(
        pageTheme: _pageTheme(
          fonts: fonts,
          format: reportPageFormat,
          margin: _reportMargin,
          pending: false,
        ),
        footer: (pw.Context context) => _pageFooter(
          context: context,
          printedBy: keeperName,
          printedAt: generatedAt,
        ),
        build: (pw.Context context) => _rtl(<pw.Widget>[
          buildOfficialLetterhead(
            title: 'كشف مسحوبات موزع / مندوب',
            voucherNumber: reference,
            accent: _pdfPrimaryDark,
          ),
          pw.SizedBox(height: 6),
          _voucherTitleBar(
            'كشف مسحوبات تحليلي كميات — ${ledger.representativeName}',
            accent: _pdfPrimaryDark,
          ),
          pw.SizedBox(height: 6),
          _identityBar(<_ErpField>[
            _ErpField('رقم الصنف', _itemCode(item), flex: 0.8),
            _ErpField(
              'اسم الصنف',
              '${item.name}  ${_specifications(item)}',
              flex: 2.0,
            ),
            _ErpField('الفترة', periodLabel, flex: 1.6),
            _ErpField('المخزن', scopeLabel, flex: 1.2),
          ]),
          pw.SizedBox(height: 5),
          _identityBar(<_ErpField>[
            _ErpField('المندوب', ledger.representativeName, flex: 1.4),
            _ErpField('بيانات التواصل', contact, flex: 1.8),
            _ErpField('عدد السندات', '${ledger.voucherCount}', flex: 0.8),
          ]),
          pw.SizedBox(height: 8),
          if (rows.isEmpty)
            _notesBox(
              'لا توجد سندات صرف أو بدل تالف معتمدة لهذا المندوب داخل الفترة '
              'المحددة.',
            )
          else ...<pw.Widget>[
            _ledgerTable(
              rows: rows,
              unit: AppConstants.cartonUnit,
              inboundTotal: inboundTotal,
              outboundTotal: outboundTotal,
              closingBalance: running,
            ),
            pw.SizedBox(height: 3),
            _packagesTotalBar(
              cartons: inboundTotal + outboundTotal,
              perCarton: perCarton,
            ),
          ],
          pw.SizedBox(height: 10),
          _signaturesLines(
            storekeeperName: keeperName,
            secondTitle: 'المندوب / الموزّع (للمطابقة)',
            secondName: ledger.representativeName,
          ),
        ]),
      ),
    );

    return document.save();
  }

  /// يبني اليومية المخزنية الشاملة ليوم واحد بمقاس A4.
  ///
  /// تعرض رصيد بداية ونهاية اليوم في شريط مؤطر، ثم جدول كل الحركات المنفذة
  /// بأعمدة الوارد والمنصرف والرصيد التراكمي، وتُختم بالتواقيع والتذييل الرسمي.
  Future<Uint8List> generateDailyJournalPdf({
    required DailyJournalReport journal,
    required ItemModel item,
    required DateTime generatedAt,
    String? storekeeperName,
    WarehouseModel? warehouse,
    Map<int, String> warehouseNames = const <int, String>{},
  }) async {
    final _PdfFonts fonts = await _resolveFonts();
    final String keeperName = await _resolveStorekeeperName(storekeeperName);
    await _ensureLogo();

    final String reference = dailyJournalReference(journal.date);
    final int perCarton = _bottlesPerCarton(item);
    final String scopeLabel = warehouse?.name ?? 'كل المخازن';

    final List<_LedgerRow> rows = <_LedgerRow>[];
    int running = journal.openingBalance;
    for (final TransactionModel transaction in journal.transactions) {
      final int signed = _signedQuantity(transaction);
      running += signed;
      rows.add(
        _LedgerRow(
          voucherNumber: transaction.voucherNumber,
          date: AppFormatters.date(transaction.createdAt),
          documentType: _typeLabel(transaction.transactionType),
          description: _movementDescription(transaction),
          inbound: signed > 0 ? signed : 0,
          outbound: signed < 0 ? -signed : 0,
          balance: running,
        ),
      );
    }
    int inboundTotal = 0;
    int outboundTotal = 0;
    for (final _LedgerRow row in rows) {
      inboundTotal += row.inbound;
      outboundTotal += row.outbound;
    }

    final pw.Document document = pw.Document(
      title: 'اليومية المخزنية - $reference',
      author: AppConstants.appTitle,
      creator: AppConstants.appTitle,
      subject: 'اليومية المخزنية الشاملة - مصنع رواء',
    );

    document.addPage(
      pw.MultiPage(
        pageTheme: _pageTheme(
          fonts: fonts,
          format: reportPageFormat,
          margin: _reportMargin,
          pending: false,
        ),
        footer: (pw.Context context) => _pageFooter(
          context: context,
          printedBy: keeperName,
          printedAt: generatedAt,
        ),
        build: (pw.Context context) => _rtl(<pw.Widget>[
          buildOfficialLetterhead(
            title: 'اليومية المخزنية لحركة البضائع',
            voucherNumber: reference,
            accent: _pdfPrimary,
          ),
          pw.SizedBox(height: 6),
          _voucherTitleBar(
            'حركة مخزون تحليلي كميات حسب المخزن — '
            '${AppFormatters.date(journal.date)}',
            accent: _pdfPrimary,
          ),
          pw.SizedBox(height: 6),
          _identityBar(<_ErpField>[
            _ErpField('رقم الصنف', _itemCode(item), flex: 0.8),
            _ErpField(
              'اسم الصنف',
              '${item.name}  ${_specifications(item)}',
              flex: 2.0,
            ),
            _ErpField(
              'الفترة',
              'من ${AppFormatters.date(journal.date)} إلى '
                  '${AppFormatters.date(journal.date)}',
              flex: 1.6,
            ),
            _ErpField('المخزن', scopeLabel, flex: 1.2),
          ]),
          pw.SizedBox(height: 5),
          _summaryStrip(<_ErpField>[
            _ErpField(
              'رصيد بداية اليوم',
              AppFormatters.number(journal.openingBalance),
            ),
            _ErpField('إجمالي الوارد', AppFormatters.number(inboundTotal)),
            _ErpField('إجمالي المنصرف', AppFormatters.number(outboundTotal)),
            _ErpField(
              'رصيد نهاية اليوم',
              AppFormatters.number(journal.closingBalance),
            ),
          ]),
          pw.SizedBox(height: 8),
          if (rows.isEmpty)
            _notesBox('لا توجد حركات معتمدة مسجلة في هذا اليوم.')
          else ...<pw.Widget>[
            _ledgerTable(
              rows: rows,
              unit: AppConstants.cartonUnit,
              inboundTotal: inboundTotal,
              outboundTotal: outboundTotal,
              closingBalance: journal.closingBalance,
            ),
            pw.SizedBox(height: 3),
            _packagesTotalBar(
              cartons: inboundTotal + outboundTotal,
              perCarton: perCarton,
            ),
          ],
          pw.SizedBox(height: 10),
          _signaturesLines(
            storekeeperName: keeperName,
            secondTitle: 'إدارة المخازن / المشرف',
            secondName: 'المشرف المخزني',
          ),
        ]),
      ),
    );

    return document.save();
  }

  /// اسم ملف PDF آمن للسند، مثال: `ISS-20261113-001.pdf`.
  static String fileNameForVoucher(String voucherNumber) {
    final String sanitized = voucherNumber.trim().replaceAll(
      RegExp(r'[^A-Za-z0-9\-_.]'),
      '-',
    );
    return '${sanitized.isEmpty ? 'voucher' : sanitized}.pdf';
  }

  /// مرجع نصي لسجل الجرد، مثال: `STK-20261113-004`.
  static String stocktakeReference(StocktakeModel stocktake) {
    final DateTime date = stocktake.createdAt;
    final String day = '${date.year}${_pad(date.month)}${_pad(date.day)}';
    final String serial = _pad(stocktake.id ?? 0, width: 3);
    return 'STK-$day-$serial';
  }

  /// مرجع تقرير المخزون العام، مثال: `INV-20261113-2130`.
  static String summaryReportReference(DateTime generatedAt) {
    final String day =
        '${generatedAt.year}${_pad(generatedAt.month)}${_pad(generatedAt.day)}';
    final String time = '${_pad(generatedAt.hour)}${_pad(generatedAt.minute)}';
    return 'INV-$day-$time';
  }

  /// اسم ملف تقرير المخزون العام.
  static String fileNameForSummaryReport(DateTime generatedAt) =>
      'INV-REPORT-${summaryReportReference(generatedAt).substring(4)}.pdf';

  /// مرجع كشف مسحوبات المندوب، مثال: `RST-20261123-1030`.
  static String representativeStatementReference(DateTime generatedAt) {
    final String day =
        '${generatedAt.year}${_pad(generatedAt.month)}${_pad(generatedAt.day)}';
    final String time = '${_pad(generatedAt.hour)}${_pad(generatedAt.minute)}';
    return 'RST-$day-$time';
  }

  /// اسم ملف كشف مسحوبات المندوب.
  static String fileNameForRepresentativeStatement(DateTime generatedAt) =>
      'REP-STATEMENT-'
      '${representativeStatementReference(generatedAt).substring(4)}.pdf';

  /// مرجع اليومية المخزنية، مثال: `DJ-20261123`.
  static String dailyJournalReference(DateTime date) =>
      'DJ-${date.year}${_pad(date.month)}${_pad(date.day)}';

  /// اسم ملف اليومية المخزنية.
  static String fileNameForDailyJournal(DateTime date) =>
      'DAILY-JOURNAL-${date.year}${_pad(date.month)}${_pad(date.day)}.pdf';

  // ---------------------------------------------------------------------------
  // الترويسة الرسمية والعلامة المائية
  // ---------------------------------------------------------------------------

  /// ترويسة مصنع رواء الرسمية المطابقة للوثيقة الورقية المعتمدة.
  ///
  /// [title] عنوان السند المطبوع تحت الشعار، و[voucherNumber] رقم السند
  /// المعروض في السطر نفسه.
  pw.Widget buildOfficialLetterhead({
    required String title,
    required String voucherNumber,
    PdfColor? accent,
  }) {
    final PdfColor titleColor = accent ?? _pdfPrimaryDark;

    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(8, 5, 8, 5),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _pdfText, width: 1),
        borderRadius: pw.BorderRadius.circular(7),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: <pw.Widget>[
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.Expanded(child: _arabicIdentityBlock()),
              pw.SizedBox(width: 6),
              _logoBlock(),
              pw.SizedBox(width: 6),
              pw.Expanded(child: _englishIdentityBlock()),
            ],
          ),
          pw.SizedBox(height: 3),
          pw.Container(height: 0.9, color: _pdfText),
          pw.SizedBox(height: 3),
          pw.Text(
            title,
            textAlign: pw.TextAlign.center,
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(
              color: titleColor,
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 1),
          pw.Text(
            'رقم السند: $voucherNumber',
            textAlign: pw.TextAlign.center,
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(
              color: _pdfText,
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _arabicIdentityBlock() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Text(
          'مصنع رواء للمياه المعدنيه والمشروبات الغازيه',
          textAlign: pw.TextAlign.right,
          textDirection: pw.TextDirection.rtl,
          style: pw.TextStyle(
            color: _pdfText,
            fontSize: 7.2,
            fontWeight: pw.FontWeight.bold,
            lineSpacing: 1.5,
          ),
        ),
        pw.Text(
          '- المركز الرئيسي',
          textAlign: pw.TextAlign.right,
          textDirection: pw.TextDirection.rtl,
          style: pw.TextStyle(
            color: _pdfText,
            fontSize: 7.2,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          factoryAddress,
          textAlign: pw.TextAlign.right,
          textDirection: pw.TextDirection.rtl,
          style: pw.TextStyle(
            color: _pdfText,
            fontSize: 7,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 1),
        pw.Text(
          factoryPhones,
          textAlign: pw.TextAlign.right,
          textDirection: pw.TextDirection.rtl,
          style: pw.TextStyle(color: _pdfText, fontSize: 6.6),
        ),
      ],
    );
  }

  pw.Widget _englishIdentityBlock() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Text(
          factoryEnglishAddress,
          textDirection: pw.TextDirection.ltr,
          style: pw.TextStyle(
            color: _pdfText,
            fontSize: 7,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          factoryEnglishTele,
          textDirection: pw.TextDirection.ltr,
          style: pw.TextStyle(color: _pdfText, fontSize: 6.6),
        ),
        pw.Text(
          factoryEnglishMob,
          textDirection: pw.TextDirection.ltr,
          style: pw.TextStyle(color: _pdfText, fontSize: 6.6),
        ),
        pw.Text(
          factoryEnglishPoBox,
          textDirection: pw.TextDirection.ltr,
          style: pw.TextStyle(color: _pdfText, fontSize: 6.6),
        ),
      ],
    );
  }

  pw.Widget _logoBlock() {
    return pw.SizedBox(
      width: 80,
      child: pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        children: <pw.Widget>[
          _logoWidget(width: 56, height: 44),
          pw.SizedBox(height: 1),
          pw.Text(
            brandSlogan,
            textAlign: pw.TextAlign.center,
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(
              color: _pdfPrimary,
              fontSize: 5.2,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// العلامة المائية المركزية في خلفية كل صفحة.
  pw.Widget _watermark({required bool pending, required PdfPageFormat format}) {
    final bool compact = format.width < 500;
    final double logoSize = compact ? 168 : 300;

    return pw.Container(
      alignment: pw.Alignment.center,
      child: pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        children: <pw.Widget>[
          pw.Opacity(
            opacity: 0.07,
            child: _logoWidget(width: logoSize, height: logoSize),
          ),
          if (pending) ...<pw.Widget>[
            pw.SizedBox(height: compact ? 6 : 10),
            pw.Opacity(
              opacity: 0.22,
              child: pw.Text(
                pendingWatermarkText,
                textAlign: pw.TextAlign.center,
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(
                  color: _pdfDanger,
                  fontSize: compact ? 26 : 40,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Opacity(
              opacity: 0.18,
              child: pw.Text(
                pendingWatermarkSubtitle,
                textAlign: pw.TextAlign.center,
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(
                  color: _pdfDanger,
                  fontSize: compact ? 11 : 15,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  pw.PageTheme _pageTheme({
    required _PdfFonts fonts,
    required PdfPageFormat format,
    required pw.EdgeInsets margin,
    required bool pending,
  }) {
    return pw.PageTheme(
      pageFormat: format,
      margin: margin,
      theme: fonts.theme,
      buildBackground: (pw.Context context) =>
          _watermark(pending: pending, format: format),
    );
  }

  /// يفرض اتجاه RTL على كل مقطع داخل الصفحة (لأن PageTheme لا يقبل اتجاهًا).
  List<pw.Widget> _rtl(List<pw.Widget> children) => <pw.Widget>[
    for (final pw.Widget child in children)
      pw.Directionality(textDirection: pw.TextDirection.rtl, child: child),
  ];

  pw.Widget _logoWidget({required double width, required double height}) {
    final pw.MemoryImage? image = _injectedLogo ?? _cachedLogo;
    if (image != null) {
      return pw.Image(
        image,
        width: width,
        height: height,
        fit: pw.BoxFit.contain,
      );
    }

    final double side = width < height ? width : height;
    return pw.Container(
      width: side,
      height: side,
      alignment: pw.Alignment.center,
      decoration: pw.BoxDecoration(
        shape: pw.BoxShape.circle,
        border: pw.Border.all(color: _pdfPrimary, width: 1.2),
      ),
      child: pw.Text(
        'رواء',
        textDirection: pw.TextDirection.rtl,
        style: pw.TextStyle(
          color: _pdfPrimary,
          fontSize: side * 0.24,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // الخطوط والشعار
  // ---------------------------------------------------------------------------

  Future<_PdfFonts> _resolveFonts() async {
    return _fonts ??= await _loadFonts();
  }

  Future<_PdfFonts> _loadFonts() async {
    final pw.Font? injected = _injectedRegular;
    if (injected != null) {
      return _PdfFonts(regular: injected, bold: _injectedBold ?? injected);
    }

    final pw.Font? bundled = await _loadBundledFont();
    if (bundled != null) {
      return _PdfFonts(regular: bundled, bold: bundled);
    }

    if (_allowNetworkFonts) {
      try {
        final pw.Font regular = await PdfGoogleFonts.cairoRegular();
        final pw.Font bold = await PdfGoogleFonts.cairoBold();
        return _PdfFonts(regular: regular, bold: bold);
      } catch (_) {
        // بلا إنترنت: نكمل بالخط الافتراضي حتى لا تفشل الطباعة كليًا.
      }
    }

    return _PdfFonts(
      regular: pw.Font.helvetica(),
      bold: pw.Font.helveticaBold(),
    );
  }

  Future<pw.Font?> _loadBundledFont() async {
    try {
      final ByteData data = await rootBundle.load(fontAssetPath);
      return pw.Font.ttf(data);
    } catch (_) {
      return null;
    }
  }

  /// يحمّل شعار مصنع رواء مرة واحدة (أو يستخدم الشعار المحقون في الاختبارات).
  Future<void> _ensureLogo() async {
    if (_injectedLogo != null || _cachedLogo != null) {
      return;
    }
    try {
      final ByteData data = await rootBundle.load(logoAssetPath);
      _cachedLogo = pw.MemoryImage(data.buffer.asUint8List());
    } catch (_) {
      // بلا شعار: يُطبع الشعار النصي البديل «رواء».
    }
  }

  /// يقرأ اسم أمين المخزن من `app_settings` إن لم يُمرَّر صراحة.
  Future<String> _resolveStorekeeperName(String? explicit) async {
    final String? injected = _injectedStorekeeperName;
    if (_hasText(injected)) {
      return injected!.trim();
    }
    if (_hasText(explicit)) {
      return explicit!.trim();
    }
    try {
      final String? saved = await DatabaseHelper.instance.getSetting(
        AppConstants.settingStorekeeperName,
        defaultValue: AppConstants.defaultStorekeeperName,
      );
      if (_hasText(saved)) {
        return saved!.trim();
      }
    } catch (_) {
      // بلا قاعدة بيانات (اختبارات/طباعة من الأرشيف): نكمل بالاسم الافتراضي.
    }
    return AppConstants.defaultStorekeeperName;
  }

  // ---------------------------------------------------------------------------
  // عناصر التصميم المحاسبي المشتركة (ERP Tabular)
  // ---------------------------------------------------------------------------

  /// عنوان السند المؤطر في منتصف الوثيقة تحت الترويسة.
  pw.Widget _voucherTitleBar(String title, {required PdfColor accent}) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: pw.BoxDecoration(
        color: _pdfSoft,
        border: pw.Border.all(color: PdfColors.black, width: 0.8),
      ),
      child: pw.Text(
        title,
        textAlign: pw.TextAlign.center,
        textDirection: pw.TextDirection.rtl,
        style: pw.TextStyle(
          color: accent,
          fontSize: 9.5,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  /// شبكة بيانات السند في عمودين (يمين: بيانات المستند | يسار: بيانات الحركة).
  pw.Widget _erpInfoGrid({
    required List<_ErpField> primary,
    required List<_ErpField> secondary,
  }) {
    final int count = primary.length > secondary.length
        ? primary.length
        : secondary.length;
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black, width: 0.8),
      columnWidths: const <int, pw.TableColumnWidth>{
        0: pw.FlexColumnWidth(1),
        1: pw.FlexColumnWidth(1),
      },
      children: <pw.TableRow>[
        for (int index = 0; index < count; index++)
          pw.TableRow(
            children: <pw.Widget>[
              _erpInfoCell(secondary, index),
              _erpInfoCell(primary, index),
            ],
          ),
      ],
    );
  }

  pw.Widget _erpInfoCell(List<_ErpField> fields, int index) {
    if (index >= fields.length) {
      return pw.SizedBox();
    }
    final _ErpField field = fields[index];
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2.6),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Expanded(
            child: pw.Text(
              field.value,
              maxLines: 2,
              overflow: pw.TextOverflow.clip,
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(
                color: _pdfText,
                fontSize: 7.2,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.SizedBox(width: 4),
          pw.Text(
            '${field.label} :',
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(color: _pdfMuted, fontSize: 6.8),
          ),
        ],
      ),
    );
  }

  /// شريط تعريف أفقي مؤطر (رقم الصنف | الاسم | الفترة | المخزن).
  pw.Widget _identityBar(List<_ErpField> fields) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black, width: 0.6),
      columnWidths: <int, pw.TableColumnWidth>{
        for (int index = 0; index < fields.length; index++)
          index: pw.FlexColumnWidth(fields[fields.length - 1 - index].flex),
      },
      children: <pw.TableRow>[
        pw.TableRow(
          children: <pw.Widget>[
            for (final _ErpField field in fields.reversed)
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 3,
                ),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: <pw.Widget>[
                    pw.Expanded(
                      child: pw.Text(
                        field.value,
                        maxLines: 1,
                        overflow: pw.TextOverflow.clip,
                        textDirection: pw.TextDirection.rtl,
                        style: pw.TextStyle(
                          color: _pdfText,
                          fontSize: 7.4,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                    pw.SizedBox(width: 3),
                    pw.Text(
                      '${field.label} :',
                      textDirection: pw.TextDirection.rtl,
                      style: pw.TextStyle(color: _pdfMuted, fontSize: 6.6),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// شريط أرقام مؤطر (تسمية فوق القيمة) لأرصدة اليوم والمطابقة.
  pw.Widget _summaryStrip(List<_ErpField> fields) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black, width: 0.6),
      columnWidths: <int, pw.TableColumnWidth>{
        for (int index = 0; index < fields.length; index++)
          index: const pw.FlexColumnWidth(1),
      },
      children: <pw.TableRow>[
        pw.TableRow(
          children: <pw.Widget>[
            for (final _ErpField field in fields.reversed)
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 3,
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: <pw.Widget>[
                    pw.Text(
                      field.label,
                      maxLines: 1,
                      textAlign: pw.TextAlign.center,
                      textDirection: pw.TextDirection.rtl,
                      style: pw.TextStyle(color: _pdfMuted, fontSize: 6.6),
                    ),
                    pw.SizedBox(height: 1),
                    pw.Text(
                      field.value,
                      maxLines: 1,
                      textAlign: pw.TextAlign.center,
                      textDirection: pw.TextDirection.rtl,
                      style: pw.TextStyle(
                        color: _pdfPrimaryDark,
                        fontSize: 9.5,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// جدول محاسبي مؤطر بخطوط سوداء، رأس مكرر عبر الصفحات.
  pw.Widget _erpTable({
    required List<String> headers,
    required List<List<String>> rows,
    required List<double> flexes,
    double borderWidth = 0.6,
    double bodyFontSize = 7,
    int alignRightIndex = -1,
    List<String>? totalRow,
  }) {
    final List<double> physicalFlexes = flexes.reversed.toList(growable: false);

    List<pw.Widget> buildCells(
      List<String> values, {
      bool header = false,
      bool bold = false,
    }) {
      final List<pw.Widget> cells = <pw.Widget>[];
      for (int index = values.length - 1; index >= 0; index--) {
        cells.add(
          _erpTableCell(
            values[index],
            header: header,
            bold: bold,
            fontSize: bodyFontSize,
            align: index == alignRightIndex
                ? pw.TextAlign.right
                : pw.TextAlign.center,
          ),
        );
      }
      return cells;
    }

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black, width: borderWidth),
      columnWidths: <int, pw.TableColumnWidth>{
        for (int index = 0; index < physicalFlexes.length; index++)
          index: pw.FlexColumnWidth(physicalFlexes[index]),
      },
      children: <pw.TableRow>[
        pw.TableRow(
          repeat: true,
          decoration: pw.BoxDecoration(color: _pdfSoft),
          children: buildCells(headers, header: true),
        ),
        for (final List<String> row in rows)
          pw.TableRow(children: buildCells(row)),
        if (totalRow != null)
          pw.TableRow(
            decoration: pw.BoxDecoration(color: _pdfTotalRow),
            children: buildCells(totalRow, bold: true),
          ),
      ],
    );
  }

  pw.Widget _erpTableCell(
    String text, {
    required bool header,
    required bool bold,
    required double fontSize,
    required pw.TextAlign align,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2.6),
      child: pw.Text(
        text,
        textAlign: align,
        textDirection: pw.TextDirection.rtl,
        maxLines: header ? 2 : 3,
        overflow: pw.TextOverflow.clip,
        style: pw.TextStyle(
          color: header ? _pdfPrimaryDark : _pdfText,
          fontSize: header ? fontSize - 0.6 : fontSize,
          fontWeight: header || bold
              ? pw.FontWeight.bold
              : pw.FontWeight.normal,
        ),
      ),
    );
  }

  /// سطر «إجمالي العبوات = الكراتين × عدد القناني».
  pw.Widget _packagesTotalBar({
    required int cartons,
    required int perCarton,
    String label = 'إجمالي العبوات',
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2.5),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 0.6),
      ),
      child: pw.Text(
        '$label: ${AppFormatters.number(cartons * perCarton)} عبوة   =   '
        '${AppFormatters.number(cartons)} ${AppConstants.cartonUnit} × '
        '$perCarton عبوة',
        textAlign: pw.TextAlign.right,
        textDirection: pw.TextDirection.rtl,
        style: pw.TextStyle(
          color: _pdfText,
          fontSize: 6.8,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  /// جدول الحركة التحليلي A4 بأعمدة الوارد والمنصرف والرصيد التراكمي.
  pw.Widget _ledgerTable({
    required List<_LedgerRow> rows,
    required String unit,
    required int inboundTotal,
    required int outboundTotal,
    required int closingBalance,
  }) {
    return _erpTable(
      headers: <String>[
        'رقم المستند',
        'التاريخ',
        'نوع المستند',
        'البيان',
        'الوحدة',
        'الوارد',
        'التصريف / المنصرف',
        'الرصيد',
      ],
      rows: <List<String>>[
        for (final _LedgerRow row in rows)
          <String>[
            row.voucherNumber,
            row.date,
            row.documentType,
            row.description,
            unit,
            row.inbound == 0 ? '' : AppFormatters.number(row.inbound),
            row.outbound == 0 ? '' : AppFormatters.number(row.outbound),
            AppFormatters.number(row.balance),
          ],
      ],
      flexes: <double>[1.5, 1.2, 1.3, 3.6, 0.8, 1.0, 1.3, 1.2],
      bodyFontSize: 7.2,
      alignRightIndex: 3,
      totalRow: <String>[
        '',
        '',
        '',
        'إجمالي كميات',
        unit,
        AppFormatters.number(inboundTotal),
        AppFormatters.number(outboundTotal),
        AppFormatters.number(closingBalance),
      ],
    );
  }

  /// سطر التواقيع والاعتماد المؤطر أسفل السند (3 خانات).
  pw.Widget _voucherSignatureRow({
    required String storekeeperName,
    required String receiverLabel,
    required String? receiverName,
  }) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black, width: 0.8),
      columnWidths: const <int, pw.TableColumnWidth>{
        0: pw.FlexColumnWidth(1),
        1: pw.FlexColumnWidth(1),
        2: pw.FlexColumnWidth(1),
      },
      children: <pw.TableRow>[
        pw.TableRow(
          children: <pw.Widget>[
            _signatureCell(
              approvalSignatureTitle,
              'الاسم: ......................',
              'الختم: ..................',
            ),
            _signatureCell(
              receiverLabel,
              _valueOrFallback(receiverName),
              'التوقيع: ..............',
            ),
            _signatureCell(
              'المستخدم / أمين المخزن',
              storekeeperName,
              'التوقيع: ..............',
            ),
          ],
        ),
      ],
    );
  }

  /// سطرا تواقيع في التقارير (أمين المخزن + الجهة المعنية + الاعتماد).
  pw.Widget _signaturesLines({
    required String storekeeperName,
    required String secondTitle,
    required String secondName,
  }) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black, width: 0.6),
      columnWidths: const <int, pw.TableColumnWidth>{
        0: pw.FlexColumnWidth(1),
        1: pw.FlexColumnWidth(1),
        2: pw.FlexColumnWidth(1),
      },
      children: <pw.TableRow>[
        pw.TableRow(
          children: <pw.Widget>[
            _signatureCell(
              approvalSignatureTitle,
              'الاسم: ......................',
              'الختم: ..................',
            ),
            _signatureCell(secondTitle, secondName, 'التوقيع: ..............'),
            _signatureCell(
              'المستخدم / أمين المخزن',
              storekeeperName,
              'التوقيع: ..............',
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _signatureCell(String title, String name, String footer) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: <pw.Widget>[
          pw.Text(
            title,
            maxLines: 1,
            overflow: pw.TextOverflow.clip,
            textAlign: pw.TextAlign.center,
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(
              color: _pdfText,
              fontSize: 6.4,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 1.5),
          pw.Text(
            name,
            maxLines: 1,
            overflow: pw.TextOverflow.clip,
            textAlign: pw.TextAlign.center,
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(
              color: _pdfPrimaryDark,
              fontSize: 7,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 7),
          pw.Text(
            footer,
            maxLines: 1,
            overflow: pw.TextOverflow.clip,
            textAlign: pw.TextAlign.center,
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(color: _pdfMuted, fontSize: 6),
          ),
        ],
      ),
    );
  }

  /// تذييل الصفحة الرسمي: طبع بواسطة | الصفحة x / y | تاريخ التقرير بالثانية.
  pw.Widget _pageFooter({
    required pw.Context context,
    required String printedBy,
    required DateTime printedAt,
  }) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 4),
      padding: const pw.EdgeInsets.only(top: 3),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColors.black, width: 0.6),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Expanded(
            child: pw.Text(
              'تاريخ التقرير : ${_stamp(printedAt)}',
              maxLines: 1,
              overflow: pw.TextOverflow.clip,
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(color: _pdfMuted, fontSize: 6.6),
            ),
          ),
          pw.Text(
            'الصفحة : ${context.pageNumber} / ${context.pagesCount}',
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(color: _pdfMuted, fontSize: 6.6),
          ),
          pw.Expanded(
            child: pw.Text(
              'طبع بواسطة : ${printedBy.trim().isEmpty ? '' : printedBy.trim()}',
              maxLines: 1,
              overflow: pw.TextOverflow.clip,
              textAlign: pw.TextAlign.right,
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(color: _pdfMuted, fontSize: 6.6),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _statusBanner({required String title, required String subtitle}) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#FBECEC'),
        border: pw.Border.all(color: _pdfDanger, width: 0.9),
      ),
      child: pw.Text(
        '$title  —  $subtitle',
        maxLines: 2,
        textDirection: pw.TextDirection.rtl,
        style: pw.TextStyle(
          color: _pdfDanger,
          fontSize: 7.4,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  pw.Widget _notesBox(String text) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(5),
      decoration: pw.BoxDecoration(
        color: _pdfSoft,
        border: pw.Border.all(color: _pdfOutline, width: 0.6),
      ),
      child: pw.Text(
        text,
        textDirection: pw.TextDirection.rtl,
        style: pw.TextStyle(color: _pdfText, fontSize: 7.6, lineSpacing: 2),
      ),
    );
  }

  pw.Widget _sectionTitle(String text) {
    return pw.Row(
      children: <pw.Widget>[
        pw.Container(width: 3, height: 11, color: _pdfPrimary),
        pw.SizedBox(width: 5),
        pw.Text(
          text,
          textDirection: pw.TextDirection.rtl,
          style: pw.TextStyle(
            color: _pdfPrimaryDark,
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // البيانات النصية المساعدة
  // ---------------------------------------------------------------------------

  /// سطر المخزن: الاسم والموقع.
  static String _warehouseLine(WarehouseModel warehouse) {
    final String location = warehouse.location.trim();
    return location.isEmpty ? warehouse.name : '${warehouse.name} — $location';
  }

  /// خانة السبب / الملاحظات.
  static String _remarks(TransactionModel transaction) {
    final List<String> parts = <String>[
      if (_hasText(transaction.reason)) transaction.reason!.trim(),
      if (_hasText(transaction.notes)) transaction.notes!.trim(),
    ];
    return parts.isEmpty ? '—' : parts.join('  |  ');
  }

  /// بيان الحركة داخل جداول التقارير.
  static String _movementDescription(TransactionModel transaction) {
    final List<String> parts = <String>[
      if (_hasText(transaction.partyName)) transaction.partyName!.trim(),
      if (_hasText(transaction.orderReference))
        'أمر: ${transaction.orderReference!.trim()}',
      if (_hasText(transaction.reason)) transaction.reason!.trim(),
      if (_hasText(transaction.vehicleNumber))
        'لوحة: ${transaction.vehicleNumber!.trim()}',
    ];
    return parts.isEmpty ? '—' : parts.join(' — ');
  }

  /// أثر الحركة على الرصيد: موجب للوارد وسالب للمنصرف والتالف.
  static int _signedQuantity(TransactionModel transaction) {
    switch (transaction.transactionType) {
      case TransactionTypes.inbound:
        return transaction.quantity.abs();
      case TransactionTypes.outbound:
      case TransactionTypes.marketReplacement:
      case TransactionTypes.damage:
        return -transaction.quantity.abs();
      default:
        return transaction.quantity;
    }
  }

  /// الاسم المختصر لنوع المستند داخل جداول التقارير.
  static String _typeLabel(String transactionType) {
    switch (transactionType) {
      case TransactionTypes.inbound:
        return 'تحويل وارد';
      case TransactionTypes.outbound:
        return 'أمر صرف';
      case TransactionTypes.marketReplacement:
        return 'بدل تالف';
      case TransactionTypes.damage:
        return 'إتلاف مخزني';
      case TransactionTypes.adjustment:
        return 'تسوية جرد';
      default:
        return transactionType;
    }
  }

  /// سطر بيانات المندوب المطبوع في شريط التعريف.
  static String _contactLine({String? phone, String? vehicle}) {
    final List<String> parts = <String>[
      if (_hasText(phone)) 'هاتف: ${phone!.trim()}',
      if (_hasText(vehicle)) 'اللوحة: ${vehicle!.trim()}',
    ];
    return parts.isEmpty ? 'بيانات الدليل غير مسجلة' : parts.join('  |  ');
  }

  static String _itemCode(ItemModel item) => _pad(item.id ?? 1, width: 6);

  static String _orderReference(TransactionModel transaction) {
    if (_hasText(transaction.orderReference)) {
      return transaction.orderReference!.trim();
    }
    return transaction.voucherNumber;
  }

  /// الختم الزمني الكامل بالثانية للسطر السفلي.
  static String _stamp(DateTime value) =>
      '${_pad(value.year, width: 4)}/${_pad(value.month)}/${_pad(value.day)} '
      '${_pad(value.hour)}:${_pad(value.minute)}:${_pad(value.second)}';

  static int _bottlesPerCarton(ItemModel item) {
    return item.bottleCount > 0
        ? item.bottleCount
        : AppConstants.bottlesPerCarton;
  }

  static int _bottleVolume(ItemModel item) {
    return item.bottleVolumeMl > 0
        ? item.bottleVolumeMl
        : AppConstants.bottleVolumeMl;
  }

  static String _specifications(ItemModel item) =>
      '${_bottlesPerCarton(item)} قنينة × ${_bottleVolume(item)} مل';

  static bool _hasText(String? value) =>
      value != null && value.trim().isNotEmpty;

  static String _valueOrFallback(String? value) =>
      _hasText(value) ? value!.trim() : '—';

  static String _pad(int value, {int width = 2}) =>
      value.toString().padLeft(width, '0');

  static _VoucherTypeInfo _infoFor(String transactionType) {
    switch (transactionType) {
      case TransactionTypes.inbound:
        return _VoucherTypeInfo(
          title: 'سند استلام وتوريد كراتين',
          documentTitle: 'سند استلام وتوريد مخزني',
          movementLabel: 'استلام مصنع',
          receiverLabel: 'مسلّم المصنع / السائق',
          accent: _pdfPrimary,
        );
      case TransactionTypes.outbound:
        return _VoucherTypeInfo(
          title: 'سند صرف كراتين لمندوب',
          documentTitle: 'سند صرف مخزني',
          movementLabel: 'صرف لمندوب',
          receiverLabel: 'المستلم / المندوب / السائق',
          accent: _pdfPrimaryDark,
        );
      case TransactionTypes.damage:
        return _VoucherTypeInfo(
          title: 'محضر إتلاف كراتين مخزنية',
          documentTitle: 'محضر إتلاف مخزني',
          movementLabel: 'إتلاف مخزني',
          receiverLabel: 'المسؤول عن الإتلاف',
          accent: _pdfDanger,
        );
      case TransactionTypes.marketReplacement:
        return _VoucherTypeInfo(
          title: 'سند صرف كراتين بدل تالف',
          documentTitle: 'سند صرف بدل تالف',
          movementLabel: 'بدل تالف',
          receiverLabel: 'المستلم / المندوب / السائق',
          accent: _pdfWarning,
        );
      case TransactionTypes.adjustment:
        return _VoucherTypeInfo(
          title: 'سند تسوية جرد مخزني',
          documentTitle: 'سند تسوية جرد',
          movementLabel: 'تسوية جرد',
          receiverLabel: 'لجنة الجرد',
          accent: _pdfWarning,
        );
      default:
        return _VoucherTypeInfo(
          title: 'سند مخزني رسمي',
          documentTitle: 'سند مخزني',
          movementLabel: transactionType,
          receiverLabel: 'الطرف الآخر',
          accent: _pdfPrimary,
        );
    }
  }
}

/// ألوان ونصوص خاصة بنوع السند.
class _VoucherTypeInfo {
  const _VoucherTypeInfo({
    required this.title,
    required this.documentTitle,
    required this.movementLabel,
    required this.receiverLabel,
    required this.accent,
  });

  /// العنوان المطبوع في منتصف السند.
  final String title;

  /// العنوان المطبوع تحت شعار الترويسة.
  final String documentTitle;

  /// قيمة خانة «نوع الحركة».
  final String movementLabel;

  /// صفة الطرف المستلم في سطر التواقيع.
  final String receiverLabel;
  final PdfColor accent;
}

/// خانة (تسمية + قيمة) في شبكة بيانات السند وأشرطة التعريف.
class _ErpField {
  const _ErpField(this.label, this.value, {this.flex = 1});

  final String label;
  final String value;
  final double flex;
}

/// صف واحد في جدول الحركة التحليلي (A4).
class _LedgerRow {
  const _LedgerRow({
    required this.voucherNumber,
    required this.date,
    required this.documentType,
    required this.description,
    required this.balance,
    this.inbound = 0,
    this.outbound = 0,
  });

  final String voucherNumber;
  final String date;
  final String documentType;
  final String description;
  final int inbound;
  final int outbound;
  final int balance;
}

/// خطّا المستند (عادي وعريض).
class _PdfFonts {
  const _PdfFonts({required this.regular, required this.bold});

  final pw.Font regular;
  final pw.Font bold;

  pw.ThemeData get theme => pw.ThemeData.withFont(
    base: regular,
    bold: bold,
    italic: regular,
    boldItalic: bold,
  );
}
