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

/// خدمة توليد سندات PDF العربية الرسمية (استلام/صرف/إتلاف/تسوية) وتقارير الجرد.
///
/// الخط العربي: يُحمَّل من أصل محلي مضمَّن (`assets/fonts/Cairo-Regular.ttf`) حتى
/// تعمل الطباعة دون إنترنت، ثم يُجرَّب خط Google Fonts (Cairo) عند غياب الأصل،
/// وأخيرًا خط PDF الافتراضي. يمكن حقن خطوط جاهزة (مثلًا في الاختبارات).
class PdfService {
  PdfService({
    pw.Font? regularFont,
    pw.Font? boldFont,
    bool allowNetworkFonts = true,
  }) : _injectedRegular = regularFont,
       _injectedBold = boldFont,
       _allowNetworkFonts = allowNetworkFonts;

  /// مسار الخط العربي المضمَّن في التطبيق.
  static const String fontAssetPath = 'assets/fonts/Cairo-Regular.ttf';

  final pw.Font? _injectedRegular;
  final pw.Font? _injectedBold;
  final bool _allowNetworkFonts;

  _PdfFonts? _fonts;

  // ---------------------------------------------------------------------------
  // واجهات التوليد العامة
  // ---------------------------------------------------------------------------

  /// يبني سند PDF رسميًا لحركة مخزنية واحدة.
  Future<Uint8List> generateTransactionVoucher({
    required TransactionModel transaction,
    required WarehouseModel warehouse,
    required ItemModel item,
  }) async {
    final _PdfFonts fonts = await _resolveFonts();
    final _VoucherTypeInfo info = _infoFor(transaction.transactionType);

    final pw.Document document = pw.Document(
      title: '${info.title} - ${transaction.voucherNumber}',
      author: AppConstants.appTitle,
      creator: AppConstants.appTitle,
      subject: 'سند مخزني رسمي',
    );

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(26, 24, 26, 28),
        theme: fonts.theme,
        textDirection: pw.TextDirection.rtl,
        footer: _footer,
        build: (pw.Context context) => <pw.Widget>[
          _header(
            info: info,
            voucherNumber: transaction.voucherNumber,
            subtitle: 'مصنع مياه رواء  |  سند مخزني رسمي',
          ),
          pw.SizedBox(height: 12),
          _metaRow(
            warehouse: warehouse,
            primaryLabel: 'المخزن',
            secondaryLabel: 'تاريخ ووقت الإصدار',
            secondaryValue: AppFormatters.dateTime(transaction.createdAt),
          ),
          pw.SizedBox(height: 14),
          _quantityBanner(
            label: info.quantityLabel,
            quantity: transaction.quantity,
            accent: info.accent,
            soft: info.accentSoft,
          ),
          pw.SizedBox(height: 14),
          _sectionTitle('بيانات السند'),
          pw.SizedBox(height: 6),
          _detailsBox(_detailRows(transaction, item)),
          if ((transaction.notes ?? '').trim().isNotEmpty) ...<pw.Widget>[
            pw.SizedBox(height: 12),
            _sectionTitle('ملاحظات'),
            pw.SizedBox(height: 6),
            _notesBox(transaction.notes!.trim()),
          ],
          pw.SizedBox(height: 18),
          _sectionTitle('التوقيعات'),
          pw.SizedBox(height: 8),
          _signatures(
            rightTitle: 'أمين المخزن',
            leftTitle: info.receiverLabel,
            accent: info.accent,
          ),
          pw.SizedBox(height: 12),
          _legalNote(
            'وثيقة صادرة آلياً من نظام إدارة مخازن مياه رواء. '
            'لا يُعتد بهذا المستند إلا بعد التوقيع والختم.',
          ),
        ],
      ),
    );

    return document.save();
  }

  /// يبني تقرير جرد وتسوية رسميًا لسجل جرد واحد.
  Future<Uint8List> generateStocktakeReport({
    required StocktakeModel stocktake,
    required WarehouseModel warehouse,
    required ItemModel item,
  }) async {
    final _PdfFonts fonts = await _resolveFonts();
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
          'عجز في المخزون بمقدار '
          '${AppFormatters.number(stocktake.difference.abs())} ${item.unit}';
      accent = _pdfDanger;
      soft = PdfColor.fromHex('#FBECEC');
    } else {
      status =
          'فائض في المخزون بمقدار '
          '${AppFormatters.number(stocktake.difference)} ${item.unit}';
      accent = _pdfWarning;
      soft = PdfColor.fromHex('#FFF6E3');
    }

    final pw.Document document = pw.Document(
      title: 'تقرير جرد - $reference',
      author: AppConstants.appTitle,
      creator: AppConstants.appTitle,
      subject: 'تقرير جرد وتسوية',
    );

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(26, 24, 26, 28),
        theme: fonts.theme,
        textDirection: pw.TextDirection.rtl,
        footer: _footer,
        build: (pw.Context context) => <pw.Widget>[
          _header(
            info: _stocktakeInfo,
            voucherNumber: reference,
            subtitle: 'مصنع مياه رواء  |  تقرير جرد وتسوية',
          ),
          pw.SizedBox(height: 12),
          _metaRow(
            warehouse: warehouse,
            primaryLabel: 'المخزن المجرود',
            secondaryLabel: 'تاريخ ووقت الجرد',
            secondaryValue: AppFormatters.dateTime(stocktake.createdAt),
          ),
          pw.SizedBox(height: 14),
          _quantityBanner(
            label: 'الرصيد الفعلي بعد الجرد',
            caption: 'الكمية المعدودة فعلياً داخل المخزن',
            quantity: stocktake.actualQuantity,
            accent: accent,
            soft: soft,
          ),
          pw.SizedBox(height: 14),
          _sectionTitle('نتيجة المطابقة'),
          pw.SizedBox(height: 6),
          _detailsBox(<_DetailEntry>[
            _DetailEntry('الصنف', item.name),
            _DetailEntry(
              'المواصفات',
              '${item.bottleCount} قنينة × ${item.bottleVolumeMl} مل',
            ),
            _DetailEntry(
              'الرصيد الدفتري',
              '${AppFormatters.number(stocktake.systemQuantity)} ${item.unit}',
            ),
            _DetailEntry(
              'الرصيد الفعلي المعدود',
              '${AppFormatters.number(stocktake.actualQuantity)} ${item.unit}',
              highlight: true,
            ),
            _DetailEntry(
              'الفارق',
              stocktake.difference == 0
                  ? 'مطابق (صفر)'
                  : '${AppFormatters.number(stocktake.difference.abs())} '
                        '${item.unit} '
                        '${stocktake.isShortage ? '(عجز)' : '(فائض)'}',
              highlight: true,
            ),
            _DetailEntry('حالة الجرد', status),
          ]),
          pw.SizedBox(height: 12),
          _sectionTitle('مبرر الفارق وملاحظات لجنة الجرد'),
          pw.SizedBox(height: 6),
          _notesBox(
            (stocktake.notes ?? '').trim().isEmpty
                ? 'لا توجد ملاحظات مسجلة.'
                : stocktake.notes!.trim(),
          ),
          pw.SizedBox(height: 18),
          _sectionTitle('التوقيعات'),
          pw.SizedBox(height: 8),
          _signatures(
            rightTitle: 'أمين المخزن',
            leftTitle: 'لجنة الجرد / المعتمد',
            accent: accent,
          ),
          pw.SizedBox(height: 12),
          _legalNote(
            'تقرير صادر آلياً من نظام إدارة مخازن مياه رواء. '
            'يُعتمد التقرير بعد توقيع لجنة الجرد وختمه.',
          ),
        ],
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
  }) async {
    final _PdfFonts fonts = await _resolveFonts();
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
      subject: 'تقرير إداري لمجمل حركة المخزون',
    );

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(26, 24, 26, 28),
        theme: fonts.theme,
        textDirection: pw.TextDirection.rtl,
        footer: _footer,
        build: (pw.Context context) => <pw.Widget>[
          _header(
            info: _summaryInfo,
            voucherNumber: reference,
            subtitle: 'مصنع مياه رواء  |  تقرير إداري',
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
            'الصنف: ${item.name}  |  الوحدة: ${item.unit}  |  '
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
          _sectionTitle('التوقيعات'),
          pw.SizedBox(height: 8),
          _signatures(
            rightTitle: 'أمين المخزن',
            leftTitle: 'إدارة المخازن / المعتمد',
            accent: _pdfPrimaryDark,
          ),
          pw.SizedBox(height: 12),
          _legalNote(
            'تقرير إداري صادر آلياً من نظام إدارة مخازن مياه رواء. '
            'يُعتمد بعد التوقيع والختم.',
          ),
        ],
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

  // ---------------------------------------------------------------------------
  // الخطوط
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

  // ---------------------------------------------------------------------------
  // عناصر التصميم المشتركة
  // ---------------------------------------------------------------------------

  pw.Widget _header({
    required _VoucherTypeInfo info,
    required String voucherNumber,
    required String subtitle,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: pw.BoxDecoration(
        color: _pdfPrimaryDark,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: <pw.Widget>[
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                pw.Text(
                  AppConstants.appBrandName,
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 19,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  subtitle,
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(
                    color: PdfColor.fromHex('#CAF0F8'),
                    fontSize: 8.5,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: <pw.Widget>[
                pw.Text(
                  info.badge,
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(
                    color: info.accent,
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  voucherNumber,
                  textDirection: pw.TextDirection.ltr,
                  style: pw.TextStyle(
                    color: _pdfText,
                    fontSize: 10.5,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

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
        pw.SizedBox(width: 10),
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
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: pw.BoxDecoration(
        color: _pdfSoft,
        borderRadius: pw.BorderRadius.circular(5),
        border: pw.Border.all(color: _pdfOutline, width: 0.6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Text(
            label,
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(color: _pdfMuted, fontSize: 8),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            value,
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(
              color: _pdfText,
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          if (sub != null) ...<pw.Widget>[
            pw.SizedBox(height: 2),
            pw.Text(
              sub,
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(color: _pdfMuted, fontSize: 8),
            ),
          ],
        ],
      ),
    );
  }

  pw.Widget _quantityBanner({
    required String label,
    required int quantity,
    required PdfColor accent,
    required PdfColor soft,
    String caption = 'الكمية المعتمدة في هذا السند',
  }) {
    final int absolute = quantity.abs();
    final String labelText = quantity < 0 ? '$label (عجز)' : label;

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                  labelText,
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(color: _pdfMuted, fontSize: 9.5),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  caption,
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(color: _pdfText, fontSize: 8),
                ),
              ],
            ),
          ),
          pw.Text(
            AppFormatters.number(absolute),
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(
              color: accent,
              fontSize: 30,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(width: 6),
          pw.Text(
            AppConstants.cartonUnit,
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(
              color: accent,
              fontSize: 11,
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
        pw.Container(width: 3, height: 12, color: _pdfPrimary),
        pw.SizedBox(width: 6),
        pw.Text(
          text,
          textDirection: pw.TextDirection.rtl,
          style: pw.TextStyle(
            color: _pdfPrimaryDark,
            fontSize: 11,
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
            width: 118,
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            color: _pdfSoft,
            child: pw.Text(
              entry.label,
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(color: _pdfMuted, fontSize: 9),
            ),
          ),
          pw.Expanded(
            child: pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 7,
              ),
              child: pw.Text(
                entry.value,
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(
                  color: _pdfText,
                  fontSize: 9.5,
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
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: _pdfSoft,
        borderRadius: pw.BorderRadius.circular(5),
        border: pw.Border.all(color: _pdfOutline, width: 0.6),
      ),
      child: pw.Text(
        text,
        textDirection: pw.TextDirection.rtl,
        style: pw.TextStyle(color: _pdfText, fontSize: 9.5, lineSpacing: 3),
      ),
    );
  }

  pw.Widget _signatures({
    required String rightTitle,
    required String leftTitle,
    required PdfColor accent,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Expanded(child: _signatureBox(rightTitle, accent)),
        pw.SizedBox(width: 12),
        pw.Expanded(child: _signatureBox(leftTitle, accent)),
      ],
    );
  }

  pw.Widget _signatureBox(String title, PdfColor accent) {
    return pw.Container(
      height: 82,
      padding: const pw.EdgeInsets.all(9),
      decoration: pw.BoxDecoration(
        borderRadius: pw.BorderRadius.circular(5),
        border: pw.Border.all(color: _pdfOutline, width: 0.7),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: <pw.Widget>[
          pw.Text(
            title,
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(
              color: accent,
              fontSize: 9.5,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.Spacer(),
          pw.Text(
            'الاسم: ............................',
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(color: _pdfMuted, fontSize: 8.5),
          ),
          pw.SizedBox(height: 7),
          pw.Text(
            'التوقيع: ........................',
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(color: _pdfMuted, fontSize: 8.5),
          ),
        ],
      ),
    );
  }

  pw.Widget _legalNote(String text) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#EAF2F8'),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        textDirection: pw.TextDirection.rtl,
        style: pw.TextStyle(color: _pdfPrimaryDark, fontSize: 8),
      ),
    );
  }

  pw.Widget _footer(pw.Context context) {
    return pw.Container(
      alignment: pw.Alignment.center,
      margin: const pw.EdgeInsets.only(top: 10),
      child: pw.Text(
        '${AppConstants.appTitle}  |  الإصدار ${AppConstants.appVersion}  |  '
        'صفحة ${context.pageNumber} من ${context.pagesCount}',
        textAlign: pw.TextAlign.center,
        textDirection: pw.TextDirection.rtl,
        style: pw.TextStyle(color: _pdfMuted, fontSize: 7.5),
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
  // البيانات النصية
  // ---------------------------------------------------------------------------

  List<_DetailEntry> _detailRows(TransactionModel transaction, ItemModel item) {
    final String unit = item.unit.trim().isEmpty
        ? AppConstants.cartonUnit
        : item.unit;
    final String quantity =
        '${AppFormatters.number(transaction.quantity.abs())} $unit';
    final String specifications =
        '${item.bottleCount} قنينة × ${item.bottleVolumeMl} مل';

    switch (transaction.transactionType) {
      case TransactionTypes.inbound:
        return <_DetailEntry>[
          _DetailEntry('الصنف', item.name),
          _DetailEntry('المواصفات', specifications),
          _DetailEntry('الكمية المستلمة', quantity, highlight: true),
          _DetailEntry('مسلّم المصنع', _valueOrFallback(transaction.partyName)),
          if (_hasText(transaction.orderReference))
            _DetailEntry('رقم الإذن', transaction.orderReference!.trim()),
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
        ];
      default:
        return <_DetailEntry>[
          _DetailEntry('الصنف', item.name),
          _DetailEntry('المواصفات', specifications),
          _DetailEntry('الكمية', quantity, highlight: true),
          _DetailEntry('الطرف الآخر', _valueOrFallback(transaction.partyName)),
          if (_hasText(transaction.reason))
            _DetailEntry('السبب', transaction.reason!.trim()),
        ];
    }
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
          badge: 'استلام بضاعة',
          quantityLabel: 'الكمية المستلمة من المصنع',
          receiverLabel: 'مسلّم المصنع',
          accent: _pdfPrimary,
          accentSoft: PdfColor.fromHex('#E7F4FB'),
        );
      case TransactionTypes.outbound:
        return _VoucherTypeInfo(
          title: 'سند صرف لمندوب',
          badge: 'صرف لمندوب',
          quantityLabel: 'الكمية المصروفة للمندوب',
          receiverLabel: 'المستلم / المندوب',
          accent: _pdfPrimaryDark,
          accentSoft: PdfColor.fromHex('#E9F0FA'),
        );
      case TransactionTypes.damage:
        return _VoucherTypeInfo(
          title: 'سند إتلاف / هدر',
          badge: 'إتلاف بضاعة',
          quantityLabel: 'الكمية التالفة / الهالكة',
          receiverLabel: 'المعتمد',
          accent: _pdfDanger,
          accentSoft: PdfColor.fromHex('#FBECEC'),
        );
      case TransactionTypes.adjustment:
        return _VoucherTypeInfo(
          title: 'سند تسوية جرد',
          badge: 'تسوية جرد',
          quantityLabel: 'الكمية المسوّاة',
          receiverLabel: 'لجنة الجرد',
          accent: _pdfWarning,
          accentSoft: PdfColor.fromHex('#FFF6E3'),
        );
      default:
        return _VoucherTypeInfo(
          title: 'سند مخزني',
          badge: 'حركة مخزنية',
          quantityLabel: 'الكمية',
          receiverLabel: 'المستلم',
          accent: _pdfPrimary,
          accentSoft: PdfColor.fromHex('#E7F4FB'),
        );
    }
  }

  static final _VoucherTypeInfo _stocktakeInfo = _VoucherTypeInfo(
    title: 'تقرير جرد وتسوية',
    badge: 'تقرير جرد',
    quantityLabel: 'الرصيد الفعلي',
    receiverLabel: 'لجنة الجرد',
    accent: _pdfPrimaryDark,
    accentSoft: PdfColor.fromHex('#E9F0FA'),
  );

  static final _VoucherTypeInfo _summaryInfo = _VoucherTypeInfo(
    title: 'تقرير المخزون العام',
    badge: 'تقرير إداري',
    quantityLabel: 'صافي التغير',
    receiverLabel: 'إدارة المخازن',
    accent: _pdfPrimary,
    accentSoft: PdfColor.fromHex('#E7F4FB'),
  );
}

/// ألوان ونصوص خاصة بنوع السند.
class _VoucherTypeInfo {
  _VoucherTypeInfo({
    required this.title,
    required this.badge,
    required this.quantityLabel,
    required this.receiverLabel,
    required this.accent,
    required this.accentSoft,
  });

  final String title;
  final String badge;
  final String quantityLabel;
  final String receiverLabel;
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
