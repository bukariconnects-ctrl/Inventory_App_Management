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

/// خدمة توليد سندات PDF العربية الرسمية (استلام/صرف/إتلاف/بدل تالف/تسوية)
/// ومحاضر الجرد وتقارير المخزون، بترويسة مصنع رواء الرسمية.
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
        footer: _footer,
        build: (pw.Context context) => _rtl(<pw.Widget>[
          buildOfficialLetterhead(
            title: info.documentTitle,
            voucherNumber: transaction.voucherNumber,
            accent: info.accent,
          ),
          pw.SizedBox(height: 6),
          if (pending) ...<pw.Widget>[
            _statusBanner(
              title: pendingWatermarkText,
              subtitle:
                  'لم يُخصم أي رصيد من المخزن. يُنفَّذ السند فقط بعد اعتماد الإدارة.',
            ),
            pw.SizedBox(height: 6),
          ],
          _metaRow(
            warehouse: warehouse,
            primaryLabel: 'المخزن',
            secondaryLabel: 'تاريخ ووقت الإصدار',
            secondaryValue: AppFormatters.dateTime(transaction.createdAt),
          ),
          pw.SizedBox(height: 6),
          _quantityBanner(
            label: info.quantityLabel,
            quantity: transaction.quantity,
            item: item,
            accent: info.accent,
            soft: info.accentSoft,
          ),
          pw.SizedBox(height: 6),
          _sectionTitle('بيانات السند'),
          pw.SizedBox(height: 3),
          _detailsBox(_detailRows(transaction, item)),
          pw.SizedBox(height: 5),
          _sectionTitle('التوقيعات والاعتماد'),
          pw.SizedBox(height: 3),
          _signaturesSection(
            storekeeperName: keeperName,
            partyTitle: info.partyTitle,
            partyName: transaction.partyName,
            partyMeta: _partyMeta(transaction),
            orderReference: _orderReference(transaction),
            accent: info.accent,
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
    final String status;
    final PdfColor accent;
    final PdfColor soft;

    if (stocktake.difference == 0) {
      status = 'مطابق تماماً للرصيد الدفتري';
      accent = _pdfPrimaryDark;
      soft = PdfColor.fromHex('#E9F4FB');
    } else if (stocktake.isShortage) {
      status =
          'عجز بمقدار '
          '${AppFormatters.number(stocktake.difference.abs())} ${item.unit}';
      accent = _pdfDanger;
      soft = PdfColor.fromHex('#FBECEC');
    } else {
      status =
          'فائض بمقدار '
          '${AppFormatters.number(stocktake.difference)} ${item.unit}';
      accent = _pdfWarning;
      soft = PdfColor.fromHex('#FFF6E3');
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
        footer: _footer,
        build: (pw.Context context) => _rtl(<pw.Widget>[
          buildOfficialLetterhead(
            title: 'محضر جرد وتسوية مخزنية',
            voucherNumber: reference,
            accent: accent,
          ),
          pw.SizedBox(height: 8),
          _metaRow(
            warehouse: warehouse,
            primaryLabel: 'المخزن المجرود',
            secondaryLabel: 'تاريخ ووقت الجرد',
            secondaryValue: AppFormatters.dateTime(stocktake.createdAt),
          ),
          pw.SizedBox(height: 8),
          _quantityBanner(
            label: 'الرصيد الفعلي بعد الجرد',
            caption: 'الكمية المعدودة فعلياً داخل المخزن',
            quantity: stocktake.actualQuantity,
            item: item,
            accent: accent,
            soft: soft,
          ),
          pw.SizedBox(height: 8),
          _sectionTitle('نتيجة المطابقة'),
          pw.SizedBox(height: 5),
          _detailsBox(<_DetailEntry>[
            _DetailEntry('الصنف', item.name),
            _DetailEntry('المواصفات', _specifications(item)),
            _DetailEntry(
              'الرصيد الدفتري',
              _quantityWithUnits(stocktake.systemQuantity, item),
            ),
            _DetailEntry(
              'الرصيد الفعلي المعدود',
              _quantityWithUnits(stocktake.actualQuantity, item),
              highlight: true,
            ),
            _DetailEntry(
              'الفارق',
              stocktake.difference == 0
                  ? 'مطابق (صفر)'
                  : '${_quantityWithUnits(stocktake.difference.abs(), item)} '
                        '${stocktake.isShortage ? '(عجز)' : '(فائض)'}',
              highlight: true,
            ),
            _DetailEntry('حالة الجرد', status),
            _DetailEntry(
              'مبرر الفارق',
              (stocktake.notes ?? '').trim().isEmpty
                  ? 'لا توجد ملاحظات مسجلة.'
                  : stocktake.notes!.trim(),
            ),
          ]),
          pw.SizedBox(height: 7),
          _sectionTitle('التوقيعات والاعتماد'),
          pw.SizedBox(height: 5),
          _signaturesSection(
            storekeeperName: keeperName,
            partyTitle: 'لجنة الجرد',
            partyName: 'لجنة الجرد / المعتمد',
            partyMeta: 'الرصيد الفعلي: ${stocktake.actualQuantity}',
            orderReference: reference,
            accent: accent,
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
    final String periodLabel = period == null
        ? 'كل الفترات المسجلة'
        : '${AppFormatters.date(period.start)} إلى '
              '${AppFormatters.date(period.end)}';
    final String scopeLabel = warehouse?.name ?? 'كل المخازن';

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
        footer: _footer,
        build: (pw.Context context) => _rtl(<pw.Widget>[
          buildOfficialLetterhead(
            title: 'تقرير حركة المخزون العام',
            voucherNumber: reference,
            accent: _pdfPrimary,
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            children: <pw.Widget>[
              pw.Expanded(
                child: _metaBox(
                  label: 'نطاق التقرير',
                  value: scopeLabel,
                  sub: 'الفترة: $periodLabel',
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: _metaBox(
                  label: 'تاريخ إصدار التقرير',
                  value: AppFormatters.dateTime(generatedAt),
                  sub: 'عدد السندات: ${metrics.voucherCount}',
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 14),
          _sectionTitle('ملخص حركة المخزون'),
          pw.SizedBox(height: 8),
          _summaryMetricsGrid(metrics),
          pw.SizedBox(height: 10),
          _notesBox(
            'الصنف: ${item.name}  |  ${_specifications(item)}  |  '
            'عدد السندات: ${AppFormatters.number(metrics.voucherCount)}',
          ),
          pw.SizedBox(height: 16),
          _sectionTitle('مسحوبات المناديب (الأكثر سحباً)'),
          pw.SizedBox(height: 6),
          if (representatives.isEmpty)
            _notesBox('لا توجد عمليات صرف مسجلة في الفترة المحددة.')
          else
            _representativesBox(
              representatives: representatives,
              totalOutbound: metrics.totalOutbound,
              unit: item.unit,
            ),
          pw.SizedBox(height: 18),
          _sectionTitle('التوقيعات والاعتماد'),
          pw.SizedBox(height: 6),
          _signaturesSection(
            storekeeperName: keeperName,
            partyTitle: 'إدارة المخازن',
            partyName: 'إدارة المخازن / المشرف',
            orderReference: reference,
            accent: _pdfPrimaryDark,
          ),
        ]),
      ),
    );

    return document.save();
  }

  /// يبني كشف مسحوبات موزّع/مندوب رسميًا بمقاس A4.
  ///
  /// يتضمن بطاقة تعريف المندوب، فترة الكشف، جدول السندات المسحوبة
  /// (صرف عادي + بدل تالف معتمد)، صندوق الإجماليات، وخانات التواقيع الثلاث.
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
        '${AppFormatters.date(ledger.startDate)} إلى '
        '${AppFormatters.date(ledger.endDate)}';
    final String scopeLabel = warehouse?.name ?? 'كل المخازن';
    final String contact = _contactLine(
      phone: representativePhone,
      vehicle: representativeVehicle,
    );

    final List<List<String>> rows = <List<String>>[
      for (final TransactionModel transaction in ledger.transactions)
        <String>[
          _shortDateTime(transaction.createdAt),
          transaction.voucherNumber,
          warehouseNames[transaction.warehouseId] ??
              'مخزن #${transaction.warehouseId}',
          _typeLabel(transaction.transactionType),
          _hasText(transaction.orderReference)
              ? transaction.orderReference!.trim()
              : '—',
          AppFormatters.number(transaction.quantity.abs()),
          AppFormatters.number(transaction.quantity.abs() * perCarton),
        ],
    ];

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
        footer: _footer,
        build: (pw.Context context) => _rtl(<pw.Widget>[
          buildOfficialLetterhead(
            title: 'كشف مسحوبات موزع / مندوب',
            voucherNumber: reference,
            accent: _pdfPrimaryDark,
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            children: <pw.Widget>[
              pw.Expanded(
                child: _metaBox(
                  label: 'المندوب / الموزّع',
                  value: ledger.representativeName,
                  sub: contact,
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: _metaBox(
                  label: 'فترة الكشف',
                  value: periodLabel,
                  sub: 'النطاق: $scopeLabel',
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            children: <pw.Widget>[
              pw.Expanded(
                child: _metaBox(
                  label: 'تاريخ إصدار الكشف',
                  value: AppFormatters.dateTime(generatedAt),
                  sub: 'عدد السندات: ${ledger.voucherCount}',
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: _metaBox(
                  label: 'سعة الكرتون',
                  value: '$perCarton قنينة × ${_bottleVolume(item)} مل',
                  sub: 'الصنف: ${item.name}',
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 14),
          pw.Row(
            children: <pw.Widget>[
              pw.Expanded(
                child: _totalTile(
                  label: 'إجمالي الكراتين المنصرفة',
                  value: AppFormatters.number(ledger.totalCartons),
                  unit: AppConstants.cartonUnit,
                  accent: _pdfPrimaryDark,
                  soft: PdfColor.fromHex('#E9F0FA'),
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: _totalTile(
                  label: 'إجمالي العبوات',
                  value: AppFormatters.number(ledger.totalCartons * perCarton),
                  unit: 'عبوة',
                  accent: _pdfPrimary,
                  soft: PdfColor.fromHex('#E7F4FB'),
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: _totalTile(
                  label: 'عدد السندات',
                  value: AppFormatters.number(ledger.voucherCount),
                  unit: 'سند',
                  accent: _pdfPrimaryDark,
                  soft: _pdfSoft,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 14),
          _sectionTitle('تفاصيل السندات المسحوبة'),
          pw.SizedBox(height: 6),
          if (rows.isEmpty)
            _notesBox(
              'لا توجد سندات صرف أو بدل تالف معتمدة لهذا المندوب داخل الفترة '
              'المحددة.',
            )
          else
            ..._tableBlocks(
              headers: <String>[
                'التاريخ والوقت',
                'رقم السند',
                'المخزن',
                'نوع السند',
                'أمر الصرف',
                'كراتين',
                'عبوات',
              ],
              rows: rows,
              widths: <double>[62, 88, 90, 82, 74, 44, 50],
              accent: _pdfPrimaryDark,
            ),
          pw.SizedBox(height: 8),
          _notesBox(
            'صافي المسحوبات: '
            '${AppFormatters.formatQuantityWithBottles(ledger.totalCartons, bottlesPerCarton: perCarton)}'
            '  |  سندات الصرف: ${ledger.outboundCount}'
            '  |  سندات بدل التالف: ${ledger.replacementCount}',
          ),
          pw.SizedBox(height: 16),
          _sectionTitle('التوقيعات والاعتماد'),
          pw.SizedBox(height: 6),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.Expanded(
                child: _signatureBox(
                  title: storekeeperSignatureTitle(keeperName),
                  extra: 'المسؤول عن المخزن والعهدة',
                  accent: _pdfPrimaryDark,
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: _signatureBox(
                  title: 'المندوب / الموزّع (للمطابقة)',
                  subtitle: ledger.representativeName,
                  extra: _hasText(representativeVehicle)
                      ? 'رقم اللوحة: ${representativeVehicle!.trim()}'
                      : contact,
                  accent: _pdfPrimaryDark,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 6),
          _approvalBox(orderReference: reference, accent: _pdfPrimaryDark),
        ]),
      ),
    );

    return document.save();
  }

  /// يبني اليومية المخزنية الشاملة ليوم واحد بمقاس A4.
  ///
  /// تعرض ميزان اليوم (بداية، وارد، منصرف، تالف وبدل، نهاية) ثم جدول كل
  /// الحركات المنفذة مرتبة زمنيًا، وتُختم بتوقيع أمين المخزن واعتماد الإدارة.
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

    final List<List<String>> rows = <List<String>>[
      for (final TransactionModel transaction in journal.transactions)
        <String>[
          AppFormatters.time(transaction.createdAt),
          transaction.voucherNumber,
          _typeLabel(transaction.transactionType),
          _hasText(transaction.partyName) ? transaction.partyName!.trim() : '—',
          _hasText(transaction.orderReference)
              ? transaction.orderReference!.trim()
              : '—',
          AppFormatters.number(transaction.quantity.abs()),
          AppFormatters.number(transaction.quantity.abs() * perCarton),
        ],
    ];

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
        footer: _footer,
        build: (pw.Context context) => _rtl(<pw.Widget>[
          buildOfficialLetterhead(
            title: 'اليومية المخزنية لحركة البضائع',
            voucherNumber: reference,
            accent: _pdfPrimary,
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            children: <pw.Widget>[
              pw.Expanded(
                child: _metaBox(
                  label: 'اليوم المخزني',
                  value: AppFormatters.date(journal.date),
                  sub:
                      'عدد الحركات: ${AppFormatters.number(journal.voucherCount)}',
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: _metaBox(
                  label: 'المخزن',
                  value: scopeLabel,
                  sub: 'الصنف: ${item.name}',
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            children: <pw.Widget>[
              pw.Expanded(
                child: _metaBox(
                  label: 'أمين المخزن المسؤول',
                  value: keeperName,
                  sub:
                      'سعة الكرتون: $perCarton قنينة × ${_bottleVolume(item)} مل',
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: _metaBox(
                  label: 'تاريخ طباعة اليومية',
                  value: AppFormatters.dateTime(generatedAt),
                  sub:
                      'صافي الحركة: '
                      '${journal.netChange < 0 ? '−' : '+'}'
                      '${AppFormatters.number(journal.netChange.abs())} '
                      '${AppConstants.cartonUnit}',
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 14),
          _sectionTitle('ميزان اليوم المخزني'),
          pw.SizedBox(height: 8),
          pw.Row(
            children: <pw.Widget>[
              pw.Expanded(
                child: _totalTile(
                  label: 'رصيد بداية اليوم',
                  value: AppFormatters.number(journal.openingBalance),
                  unit: AppConstants.cartonUnit,
                  accent: _pdfPrimaryDark,
                  soft: _pdfSoft,
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: _totalTile(
                  label: 'إجمالي الوارد',
                  value: AppFormatters.number(journal.inboundCartons),
                  unit: AppConstants.cartonUnit,
                  accent: _pdfPrimary,
                  soft: PdfColor.fromHex('#E7F4FB'),
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: _totalTile(
                  label: 'إجمالي المنصرف',
                  value: AppFormatters.number(journal.outboundCartons),
                  unit: AppConstants.cartonUnit,
                  accent: _pdfPrimaryDark,
                  soft: PdfColor.fromHex('#E9F0FA'),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Row(
            children: <pw.Widget>[
              pw.Expanded(
                child: _totalTile(
                  label: 'التالف والبدل',
                  value: AppFormatters.number(
                    journal.damagedAndReplacementCartons,
                  ),
                  unit: AppConstants.cartonUnit,
                  accent: _pdfDanger,
                  soft: PdfColor.fromHex('#FBECEC'),
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: _totalTile(
                  label: 'تسويات الجرد',
                  value:
                      '${journal.adjustmentCartons < 0 ? '−' : '+'}'
                      '${AppFormatters.number(journal.adjustmentCartons.abs())}',
                  unit: AppConstants.cartonUnit,
                  accent: _pdfWarning,
                  soft: PdfColor.fromHex('#FFF6E3'),
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: _totalTile(
                  label: 'رصيد نهاية اليوم',
                  value: AppFormatters.number(journal.closingBalance),
                  unit: AppConstants.cartonUnit,
                  accent: _pdfPrimaryDark,
                  soft: PdfColor.fromHex('#EFF7FD'),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          _notesBox(
            'المعادلة: بداية اليوم + الوارد − المنصرف − التالف والبدل '
            '+ التسويات = رصيد نهاية اليوم.',
          ),
          pw.SizedBox(height: 14),
          _sectionTitle('تفاصيل الحركات المنفذة خلال اليوم'),
          pw.SizedBox(height: 6),
          if (rows.isEmpty)
            _notesBox('لا توجد حركات معتمدة مسجلة في هذا اليوم.')
          else
            ..._tableBlocks(
              headers: <String>[
                'الوقت',
                'رقم السند',
                'النوع',
                'السائق / المندوب',
                'أمر الصرف',
                'كراتين',
                'عبوات',
              ],
              rows: rows,
              widths: <double>[46, 86, 72, 104, 78, 44, 50],
              accent: _pdfPrimary,
            ),
          pw.SizedBox(height: 14),
          _sectionTitle('التوقيعات والاعتماد'),
          pw.SizedBox(height: 6),
          _signaturesSection(
            storekeeperName: keeperName,
            partyTitle: 'إدارة المخازن',
            partyName: 'إدارة المخازن / المشرف',
            partyMeta: 'اليوم: ${AppFormatters.date(journal.date)}',
            orderReference: reference,
            accent: _pdfPrimaryDark,
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
  // عناصر التصميم المشتركة
  // ---------------------------------------------------------------------------

  pw.Widget _metaRow({
    required WarehouseModel warehouse,
    required String primaryLabel,
    required String secondaryLabel,
    required String secondaryValue,
  }) {
    return pw.Row(
      children: <pw.Widget>[
        pw.Expanded(
          child: _metaBox(
            label: primaryLabel,
            value: warehouse.name,
            sub: warehouse.location.trim().isEmpty
                ? null
                : 'الموقع: ${warehouse.location}',
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          child: _metaBox(label: secondaryLabel, value: secondaryValue),
        ),
      ],
    );
  }

  pw.Widget _metaBox({
    required String label,
    required String value,
    String? sub,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: pw.BoxDecoration(
        color: _pdfSoft,
        borderRadius: pw.BorderRadius.circular(5),
        border: pw.Border.all(color: _pdfOutline, width: 0.6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Row(
            children: <pw.Widget>[
              pw.Text(
                label,
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(color: _pdfMuted, fontSize: 7),
              ),
              pw.SizedBox(width: 4),
              pw.Expanded(
                child: pw.Text(
                  value,
                  maxLines: 1,
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(
                    color: _pdfText,
                    fontSize: 8.4,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (sub != null) ...<pw.Widget>[
            pw.SizedBox(height: 1),
            pw.Text(
              sub,
              maxLines: 1,
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(color: _pdfMuted, fontSize: 6.6),
            ),
          ],
        ],
      ),
    );
  }

  pw.Widget _statusBanner({required String title, required String subtitle}) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#FBECEC'),
        borderRadius: pw.BorderRadius.circular(5),
        border: pw.Border.all(color: _pdfDanger, width: 0.9),
      ),
      child: pw.Text(
        '$title  —  $subtitle',
        maxLines: 2,
        textDirection: pw.TextDirection.rtl,
        style: pw.TextStyle(
          color: _pdfDanger,
          fontSize: 8.6,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  pw.Widget _quantityBanner({
    required String label,
    required int quantity,
    required ItemModel item,
    required PdfColor accent,
    required PdfColor soft,
    String? caption,
  }) {
    final int absolute = quantity.abs();
    final String labelText = quantity < 0 ? '$label (عجز)' : label;
    final int perCarton = _bottlesPerCarton(item);

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: pw.BoxDecoration(
        color: soft,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: accent, width: 0.8),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: <pw.Widget>[
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                pw.Text(
                  caption == null ? labelText : '$labelText  •  $caption',
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(
                    color: _pdfMuted,
                    fontSize: 7.8,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  AppFormatters.formatQuantityWithBottles(
                    absolute,
                    bottlesPerCarton: perCarton,
                  ),
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(
                    color: accent,
                    fontSize: 9.5,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 1),
                pw.Text(
                  'سعة الكرتون: $perCarton قنينة × ${_bottleVolume(item)} مل',
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(color: _pdfMuted, fontSize: 6.6),
                ),
              ],
            ),
          ),
          pw.SizedBox(width: 6),
          pw.Text(
            AppFormatters.number(absolute),
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(
              color: accent,
              fontSize: 23,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(width: 3),
          pw.Text(
            AppConstants.cartonUnit,
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(
              color: accent,
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
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

  pw.Widget _detailsBox(List<_DetailEntry> entries) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _pdfOutline, width: 0.6),
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Column(
        children: <pw.Widget>[
          for (int index = 0; index < entries.length; index++)
            _detailRow(entries[index], isLast: index == entries.length - 1),
        ],
      ),
    );
  }

  pw.Widget _detailRow(_DetailEntry entry, {required bool isLast}) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: isLast
            ? null
            : pw.Border(bottom: pw.BorderSide(color: _pdfOutline, width: 0.5)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Container(
            width: 100,
            padding: const pw.EdgeInsets.symmetric(
              horizontal: 7,
              vertical: 2.5,
            ),
            color: _pdfSoft,
            child: pw.Text(
              entry.label,
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(color: _pdfMuted, fontSize: 7.6),
            ),
          ),
          pw.Expanded(
            child: pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 7,
                vertical: 2.5,
              ),
              child: pw.Text(
                entry.value,
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(
                  color: _pdfText,
                  fontSize: 8,
                  fontWeight: entry.highlight
                      ? pw.FontWeight.bold
                      : pw.FontWeight.normal,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _notesBox(String text) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: _pdfSoft,
        borderRadius: pw.BorderRadius.circular(5),
        border: pw.Border.all(color: _pdfOutline, width: 0.6),
      ),
      child: pw.Text(
        text,
        textDirection: pw.TextDirection.rtl,
        style: pw.TextStyle(color: _pdfText, fontSize: 8.5, lineSpacing: 2),
      ),
    );
  }

  /// قسم التواقيع: أمين المخزن، الطرف الآخر، واعتماد الإدارة — بأسماء مطبوعة.
  pw.Widget _signaturesSection({
    required String storekeeperName,
    required String partyTitle,
    required String? partyName,
    String? partyMeta,
    required String orderReference,
    required PdfColor accent,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: <pw.Widget>[
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            pw.Expanded(
              child: _signatureBox(
                title: storekeeperSignatureTitle(storekeeperName),
                extra: 'المسؤول عن المخزن والعهدة',
                accent: accent,
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: _signatureBox(
                title: partyTitle,
                subtitle: _hasText(partyName) ? partyName!.trim() : 'غير محدد',
                extra: partyMeta,
                accent: accent,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 6),
        _approvalBox(orderReference: orderReference, accent: accent),
      ],
    );
  }

  pw.Widget _signatureBox({
    required String title,
    String? subtitle,
    String? extra,
    required PdfColor accent,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(5),
      decoration: pw.BoxDecoration(
        borderRadius: pw.BorderRadius.circular(4),
        border: pw.Border.all(color: _pdfOutline, width: 0.7),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: <pw.Widget>[
          pw.Text(
            title,
            maxLines: 2,
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(
              color: accent,
              fontSize: 7.2,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          if (subtitle != null) ...<pw.Widget>[
            pw.SizedBox(height: 1),
            pw.Text(
              subtitle,
              maxLines: 1,
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(
                color: _pdfText,
                fontSize: 7.2,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
          if (extra != null) ...<pw.Widget>[
            pw.SizedBox(height: 1),
            pw.Text(
              extra,
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(color: _pdfMuted, fontSize: 6.6),
            ),
          ],
          pw.SizedBox(height: 8),
          pw.Text(
            signatureLine,
            maxLines: 1,
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(color: _pdfMuted, fontSize: 6.6),
          ),
        ],
      ),
    );
  }

  pw.Widget _approvalBox({
    required String orderReference,
    required PdfColor accent,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: pw.BoxDecoration(
        color: _pdfSoft,
        borderRadius: pw.BorderRadius.circular(4),
        border: pw.Border.all(color: _pdfOutline, width: 0.7),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: <pw.Widget>[
          pw.Expanded(
            child: pw.Text(
              'رقم أمر/إذن الصرف: $orderReference',
              maxLines: 1,
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(color: _pdfText, fontSize: 7),
            ),
          ),
          pw.SizedBox(width: 6),
          pw.Text(
            approvalSignatureTitle,
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(
              color: accent,
              fontSize: 7.6,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Text(
            approvalStampLine,
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(color: _pdfMuted, fontSize: 6.8),
          ),
        ],
      ),
    );
  }

  pw.Widget _footer(pw.Context context) {
    return pw.Container(
      alignment: pw.Alignment.center,
      margin: const pw.EdgeInsets.only(top: 6),
      child: pw.Text(
        '${AppConstants.appTitle}  |  الإصدار ${AppConstants.appVersion}  |  '
        'لا يُعتد بالمستند إلا بعد التوقيع والختم  |  '
        'صفحة ${context.pageNumber} من ${context.pagesCount}',
        textAlign: pw.TextAlign.center,
        textDirection: pw.TextDirection.rtl,
        style: pw.TextStyle(color: _pdfMuted, fontSize: 6.4),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // عناصر تقرير المخزون العام
  // ---------------------------------------------------------------------------

  pw.Widget _summaryMetricsGrid(PeriodSummaryMetrics metrics) {
    final _MetricInfo inbound = _MetricInfo(
      label: 'إجمالي الوارد',
      value: metrics.totalInbound,
      accent: _pdfPrimary,
      soft: PdfColor.fromHex('#E7F4FB'),
    );
    final _MetricInfo outbound = _MetricInfo(
      label: 'إجمالي المنصرف',
      value: metrics.totalOutbound,
      accent: _pdfPrimaryDark,
      soft: PdfColor.fromHex('#E9F0FA'),
    );
    final _MetricInfo damaged = _MetricInfo(
      label: 'إجمالي التالف',
      value: metrics.totalDamaged,
      accent: _pdfDanger,
      soft: PdfColor.fromHex('#FBECEC'),
    );
    final _MetricInfo net = _MetricInfo(
      label: metrics.netChange < 0
          ? 'صافي التغير (انخفاض)'
          : 'صافي التغير (زيادة)',
      value: metrics.netChange.abs(),
      accent: metrics.netChange < 0 ? _pdfDanger : _pdfPrimaryDark,
      soft: PdfColor.fromHex('#F5F9FC'),
    );

    return pw.Column(
      children: <pw.Widget>[
        pw.Row(
          children: <pw.Widget>[
            pw.Expanded(child: _metricTile(inbound)),
            pw.SizedBox(width: 10),
            pw.Expanded(child: _metricTile(outbound)),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Row(
          children: <pw.Widget>[
            pw.Expanded(child: _metricTile(damaged)),
            pw.SizedBox(width: 10),
            pw.Expanded(child: _metricTile(net)),
          ],
        ),
      ],
    );
  }

  pw.Widget _metricTile(_MetricInfo metric) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: pw.BoxDecoration(
        color: metric.soft,
        borderRadius: pw.BorderRadius.circular(5),
        border: pw.Border.all(color: metric.accent, width: 0.7),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Text(
            metric.label,
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(color: _pdfMuted, fontSize: 8.5),
          ),
          pw.SizedBox(height: 4),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: <pw.Widget>[
              pw.Text(
                AppFormatters.number(metric.value),
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(
                  color: metric.accent,
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(width: 4),
              pw.Text(
                AppConstants.cartonUnit,
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(color: metric.accent, fontSize: 8.5),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _representativesBox({
    required List<RepresentativeSummary> representatives,
    required int totalOutbound,
    required String unit,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _pdfOutline, width: 0.6),
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Column(
        children: <pw.Widget>[
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            color: _pdfSoft,
            child: pw.Text(
              'الترتيب  •  المندوب  •  الكمية  •  السندات  •  النسبة',
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(
                color: _pdfPrimaryDark,
                fontSize: 8.5,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          for (int index = 0; index < representatives.length; index++)
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 7,
              ),
              decoration: pw.BoxDecoration(
                border: pw.Border(
                  top: pw.BorderSide(color: _pdfOutline, width: 0.5),
                ),
              ),
              child: pw.Row(
                children: <pw.Widget>[
                  pw.SizedBox(
                    width: 24,
                    child: pw.Text(
                      '${index + 1}',
                      textDirection: pw.TextDirection.rtl,
                      style: pw.TextStyle(
                        color: _pdfMuted,
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Text(
                      representatives[index].name,
                      textDirection: pw.TextDirection.rtl,
                      style: pw.TextStyle(color: _pdfText, fontSize: 9.5),
                    ),
                  ),
                  pw.SizedBox(
                    width: 74,
                    child: pw.Text(
                      '${AppFormatters.number(representatives[index].totalQuantity)} $unit',
                      textDirection: pw.TextDirection.rtl,
                      style: pw.TextStyle(
                        color: _pdfPrimaryDark,
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.SizedBox(
                    width: 46,
                    child: pw.Text(
                      '${AppFormatters.number(representatives[index].voucherCount)} سند',
                      textDirection: pw.TextDirection.rtl,
                      style: pw.TextStyle(color: _pdfMuted, fontSize: 8.5),
                    ),
                  ),
                  pw.SizedBox(
                    width: 40,
                    child: pw.Text(
                      '${(representatives[index].shareOf(totalOutbound) * 100).round()}%',
                      textDirection: pw.TextDirection.rtl,
                      style: pw.TextStyle(color: _pdfMuted, fontSize: 8.5),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // جداول التقارير الإدارية (A4)
  // ---------------------------------------------------------------------------

  /// يبني جدولاً مقسّماً إلى كتل صغيرة كي يتنقل بين صفحات A4 دون قصّ.
  List<pw.Widget> _tableBlocks({
    required List<String> headers,
    required List<List<String>> rows,
    required List<double> widths,
    required PdfColor accent,
    int rowsPerBlock = 14,
  }) {
    final List<pw.Widget> blocks = <pw.Widget>[];
    for (int start = 0; start < rows.length; start += rowsPerBlock) {
      final int end = start + rowsPerBlock > rows.length
          ? rows.length
          : start + rowsPerBlock;
      blocks.add(
        pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _pdfOutline, width: 0.6),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Column(
            children: <pw.Widget>[
              _tableHeaderRow(headers: headers, widths: widths, accent: accent),
              for (int index = start; index < end; index++)
                _tableDataRow(
                  cells: rows[index],
                  widths: widths,
                  striped: (index - start).isOdd,
                ),
            ],
          ),
        ),
      );
      blocks.add(pw.SizedBox(height: 5));
    }
    return blocks;
  }

  pw.Widget _tableHeaderRow({
    required List<String> headers,
    required List<double> widths,
    required PdfColor accent,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      decoration: pw.BoxDecoration(
        color: _pdfSoft,
        border: pw.Border(
          bottom: pw.BorderSide(color: _pdfOutline, width: 0.6),
        ),
      ),
      child: pw.Row(
        children: <pw.Widget>[
          for (int index = 0; index < headers.length; index++)
            pw.SizedBox(
              width: widths[index],
              child: pw.Text(
                headers[index],
                textAlign: pw.TextAlign.center,
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(
                  color: accent,
                  fontSize: 7.4,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  pw.Widget _tableDataRow({
    required List<String> cells,
    required List<double> widths,
    required bool striped,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3.4),
      decoration: pw.BoxDecoration(
        color: striped ? PdfColor.fromHex('#FAFCFE') : null,
        border: pw.Border(
          bottom: pw.BorderSide(color: _pdfOutline, width: 0.4),
        ),
      ),
      child: pw.Row(
        children: <pw.Widget>[
          for (int index = 0; index < cells.length; index++)
            pw.SizedBox(
              width: widths[index],
              child: pw.Text(
                cells[index],
                maxLines: 1,
                overflow: pw.TextOverflow.clip,
                textAlign: index < 2 ? pw.TextAlign.right : pw.TextAlign.center,
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(color: _pdfText, fontSize: 7.2),
              ),
            ),
        ],
      ),
    );
  }

  /// بطاقة رقم إجمالي في التقارير الإدارية.
  pw.Widget _totalTile({
    required String label,
    required String value,
    required String unit,
    required PdfColor accent,
    required PdfColor soft,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: pw.BoxDecoration(
        color: soft,
        borderRadius: pw.BorderRadius.circular(5),
        border: pw.Border.all(color: accent, width: 0.7),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Text(
            label,
            maxLines: 1,
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(color: _pdfMuted, fontSize: 8),
          ),
          pw.SizedBox(height: 4),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: <pw.Widget>[
              pw.Text(
                value,
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(
                  color: accent,
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(width: 3),
              pw.Text(
                unit,
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(color: accent, fontSize: 8),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// تاريخ ووقت مختصر لجدول السندات: `13/11 09:30`.
  static String _shortDateTime(DateTime value) =>
      '${_pad(value.day)}/${_pad(value.month)} '
      '${_pad(value.hour)}:${_pad(value.minute)}';

  /// الاسم المختصر لنوع الحركة داخل جداول التقارير.
  static String _typeLabel(String transactionType) {
    switch (transactionType) {
      case TransactionTypes.inbound:
        return 'استلام';
      case TransactionTypes.outbound:
        return 'صرف عادي';
      case TransactionTypes.marketReplacement:
        return 'بدل تالف';
      case TransactionTypes.damage:
        return 'إتلاف';
      case TransactionTypes.adjustment:
        return 'تسوية جرد';
      default:
        return transactionType;
    }
  }

  /// سطر بيانات المندوب المطبوع في بطاقة التعريف.
  static String _contactLine({String? phone, String? vehicle}) {
    final List<String> parts = <String>[
      if (_hasText(phone)) 'هاتف: ${phone!.trim()}',
      if (_hasText(vehicle)) 'اللوحة: ${vehicle!.trim()}',
    ];
    return parts.isEmpty ? 'بيانات الدليل غير مسجلة' : parts.join('  |  ');
  }

  // ---------------------------------------------------------------------------
  // البيانات النصية
  // ---------------------------------------------------------------------------

  List<_DetailEntry> _detailRows(TransactionModel transaction, ItemModel item) {
    final List<_DetailEntry> rows = _baseDetailRows(transaction, item);
    if (_hasText(transaction.notes)) {
      rows.add(_DetailEntry('ملاحظات', transaction.notes!.trim()));
    }
    return rows;
  }

  List<_DetailEntry> _baseDetailRows(
    TransactionModel transaction,
    ItemModel item,
  ) {
    final String specifications = _specifications(item);
    final String quantity = _quantityWithUnits(transaction.quantity, item);
    final String status = _statusValue(transaction);

    switch (transaction.transactionType) {
      case TransactionTypes.inbound:
        return <_DetailEntry>[
          _DetailEntry('الصنف', item.name),
          _DetailEntry('المواصفات', specifications),
          _DetailEntry('الكمية المستلمة', quantity, highlight: true),
          _DetailEntry('مسلّم المصنع', _valueOrFallback(transaction.partyName)),
          if (_hasText(transaction.orderReference))
            _DetailEntry('رقم الإذن', transaction.orderReference!.trim()),
          if (transaction.isRejected) _DetailEntry('حالة السند', status),
        ];
      case TransactionTypes.outbound:
        return <_DetailEntry>[
          _DetailEntry(
            'رقم أمر الصرف',
            _valueOrFallback(transaction.orderReference),
          ),
          _DetailEntry('الصنف', item.name),
          _DetailEntry('المواصفات', specifications),
          _DetailEntry('الكمية المصروفة', quantity, highlight: true),
          _DetailEntry(
            'اسم المندوب / المستلم',
            _valueOrFallback(transaction.partyName),
          ),
          if (_hasText(transaction.vehicleNumber))
            _DetailEntry('رقم لوحة السيارة', transaction.vehicleNumber!.trim()),
          if (transaction.isRejected) _DetailEntry('حالة السند', status),
        ];
      case TransactionTypes.damage:
        return <_DetailEntry>[
          _DetailEntry('الصنف', item.name),
          _DetailEntry('المواصفات', specifications),
          _DetailEntry('الكمية التالفة', quantity, highlight: true),
          _DetailEntry('سبب الإتلاف', _valueOrFallback(transaction.reason)),
          _DetailEntry(
            'المسؤول عن الإتلاف',
            _valueOrFallback(transaction.partyName),
          ),
          if (transaction.isRejected) _DetailEntry('حالة السند', status),
        ];
      case TransactionTypes.marketReplacement:
        return <_DetailEntry>[
          _DetailEntry(
            'رقم أمر الصرف',
            _valueOrFallback(transaction.orderReference),
          ),
          _DetailEntry('الصنف', item.name),
          _DetailEntry('المواصفات', specifications),
          _DetailEntry('الكمية المصروفة كبدل تالف', quantity, highlight: true),
          _DetailEntry(
            'اسم المندوب / المستلم',
            _valueOrFallback(transaction.partyName),
          ),
          if (_hasText(transaction.vehicleNumber))
            _DetailEntry('رقم لوحة السيارة', transaction.vehicleNumber!.trim()),
          _DetailEntry('سبب الاستبدال', _valueOrFallback(transaction.reason)),
          if (transaction.isRejected) _DetailEntry('حالة السند', status),
        ];
      case TransactionTypes.adjustment:
        return <_DetailEntry>[
          _DetailEntry('الصنف', item.name),
          _DetailEntry('المواصفات', specifications),
          _DetailEntry('الكمية المسوّاة', quantity, highlight: true),
          _DetailEntry(
            'نوع التسوية',
            transaction.quantity < 0 ? 'عجز (نقص)' : 'زيادة (فائض)',
          ),
          _DetailEntry('سبب التسوية', _valueOrFallback(transaction.reason)),
          _DetailEntry('المسؤول', _valueOrFallback(transaction.partyName)),
          if (transaction.isRejected) _DetailEntry('حالة السند', status),
        ];
      default:
        return <_DetailEntry>[
          _DetailEntry('الصنف', item.name),
          _DetailEntry('المواصفات', specifications),
          _DetailEntry('الكمية', quantity, highlight: true),
          _DetailEntry('الطرف الآخر', _valueOrFallback(transaction.partyName)),
          if (_hasText(transaction.reason))
            _DetailEntry('السبب', transaction.reason!.trim()),
          if (transaction.isRejected) _DetailEntry('حالة السند', status),
        ];
    }
  }

  static String _statusValue(TransactionModel transaction) {
    if (transaction.isRejected) {
      final String reason = (transaction.rejectionReason ?? '').trim();
      return reason.isEmpty
          ? TransactionStatus.label(transaction.status)
          : '${TransactionStatus.label(transaction.status)} — $reason';
    }
    return TransactionStatus.label(transaction.status);
  }

  /// اسم الطرف الآخر كما سيُطبع في خانة التوقيع.
  static String? _partyMeta(TransactionModel transaction) {
    if (_hasText(transaction.vehicleNumber)) {
      return 'رقم اللوحة: ${transaction.vehicleNumber!.trim()}';
    }
    if (_hasText(transaction.orderReference)) {
      return 'أمر الصرف: ${transaction.orderReference!.trim()}';
    }
    return null;
  }

  static String _orderReference(TransactionModel transaction) {
    if (_hasText(transaction.orderReference)) {
      return transaction.orderReference!.trim();
    }
    return transaction.voucherNumber;
  }

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

  /// الكمية بالوحدتين: `150 كرتون (3,000 عبوة)`.
  static String _quantityWithUnits(int quantity, ItemModel item) {
    return AppFormatters.formatQuantityWithBottles(
      quantity.abs(),
      bottlesPerCarton: _bottlesPerCarton(item),
    );
  }

  static bool _hasText(String? value) =>
      value != null && value.trim().isNotEmpty;

  static String _valueOrFallback(String? value) =>
      _hasText(value) ? value!.trim() : 'غير محدد';

  static String _pad(int value, {int width = 2}) =>
      value.toString().padLeft(width, '0');

  static _VoucherTypeInfo _infoFor(String transactionType) {
    switch (transactionType) {
      case TransactionTypes.inbound:
        return _VoucherTypeInfo(
          title: 'سند استلام بضاعة',
          documentTitle: 'سند توريد واستلام كراتين',
          quantityLabel: 'الكمية المستلمة من المصنع',
          partyTitle: 'مسلّم المصنع / السائق',
          accent: _pdfPrimary,
          accentSoft: PdfColor.fromHex('#E7F4FB'),
        );
      case TransactionTypes.outbound:
        return _VoucherTypeInfo(
          title: 'سند صرف لمندوب',
          documentTitle: 'سند صرف كراتين لمندوب',
          quantityLabel: 'الكمية المصروفة للمندوب',
          partyTitle: 'المندوب المستلم',
          accent: _pdfPrimaryDark,
          accentSoft: PdfColor.fromHex('#E9F0FA'),
        );
      case TransactionTypes.damage:
        return _VoucherTypeInfo(
          title: 'محضر إتلاف مخزني',
          documentTitle: 'محضر إتلاف كراتين مخزنية',
          quantityLabel: 'الكمية التالفة / الهالكة',
          partyTitle: 'المسؤول عن الإتلاف',
          accent: _pdfDanger,
          accentSoft: PdfColor.fromHex('#FBECEC'),
        );
      case TransactionTypes.marketReplacement:
        return _VoucherTypeInfo(
          title: 'سند صرف بدل تالف',
          documentTitle: 'سند صرف كراتين بدل تالف',
          quantityLabel: 'الكمية المصروفة كبدل تالف',
          partyTitle: 'المندوب المستلم',
          accent: _pdfWarning,
          accentSoft: PdfColor.fromHex('#FFF6E3'),
        );
      case TransactionTypes.adjustment:
        return _VoucherTypeInfo(
          title: 'سند تسوية جرد',
          documentTitle: 'سند تسوية جرد مخزني',
          quantityLabel: 'الكمية المسوّاة',
          partyTitle: 'لجنة الجرد',
          accent: _pdfWarning,
          accentSoft: PdfColor.fromHex('#FFF6E3'),
        );
      default:
        return _VoucherTypeInfo(
          title: 'سند مخزني',
          documentTitle: 'سند مخزني رسمي',
          quantityLabel: 'الكمية',
          partyTitle: 'الطرف الآخر',
          accent: _pdfPrimary,
          accentSoft: PdfColor.fromHex('#E7F4FB'),
        );
    }
  }
}

/// ألوان ونصوص خاصة بنوع السند.
class _VoucherTypeInfo {
  _VoucherTypeInfo({
    required this.title,
    required this.documentTitle,
    required this.quantityLabel,
    required this.partyTitle,
    required this.accent,
    required this.accentSoft,
  });

  final String title;

  /// العنوان المطبوع تحت شعار الترويسة (مثل: «سند صرف كراتين لمندوب»).
  final String documentTitle;
  final String quantityLabel;

  /// صفة الطرف الآخر في خانة التوقيع.
  final String partyTitle;
  final PdfColor accent;
  final PdfColor accentSoft;
}

/// بطاقة مقياس رقمية في تقرير المخزون العام.
class _MetricInfo {
  const _MetricInfo({
    required this.label,
    required this.value,
    required this.accent,
    required this.soft,
  });

  final String label;
  final int value;
  final PdfColor accent;
  final PdfColor soft;
}

/// صف واحد في جدول بيانات السند.
class _DetailEntry {
  const _DetailEntry(this.label, this.value, {this.highlight = false});

  final String label;
  final String value;
  final bool highlight;
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
