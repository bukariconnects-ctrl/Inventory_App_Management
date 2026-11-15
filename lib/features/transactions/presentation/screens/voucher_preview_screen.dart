import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../../../core/services/pdf_service.dart';
import '../../../../core/theme/app_colors.dart';

/// شاشة معاينة السند قبل الطباعة أو المشاركة (واتساب وغيره).
class VoucherPreviewScreen extends StatefulWidget {
  const VoucherPreviewScreen({
    super.key,
    required this.title,
    required this.voucherNumber,
    required this.documentBuilder,
  });

  /// عنوان الشاشة، مثل: «معاينة سند استلام REC-20261113-001».
  final String title;

  /// رقم السند المستخدم في اسم ملف PDF.
  final String voucherNumber;

  /// دالة تبني بايتات المستند عند فتح الشاشة.
  final Future<Uint8List> Function() documentBuilder;

  @override
  State<VoucherPreviewScreen> createState() => _VoucherPreviewScreenState();
}

class _VoucherPreviewScreenState extends State<VoucherPreviewScreen> {
  Uint8List? _bytes;
  Object? _error;
  bool _isBuilding = true;

  String get _fileName => PdfService.fileNameForVoucher(widget.voucherNumber);

  @override
  void initState() {
    super.initState();
    _buildDocument();
  }

  Future<void> _buildDocument() async {
    setState(() {
      _isBuilding = true;
      _error = null;
    });
    try {
      final Uint8List bytes = await widget.documentBuilder();
      if (!mounted) {
        return;
      }
      setState(() {
        _bytes = bytes;
        _isBuilding = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
        _isBuilding = false;
      });
    }
  }

  Future<void> _share() async {
    final Uint8List? bytes = _bytes;
    if (bytes == null) {
      return;
    }
    try {
      await Printing.sharePdf(bytes: bytes, filename: _fileName);
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر مشاركة السند على هذا الجهاز.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final Uint8List? bytes = _bytes;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              _fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            key: const Key('voucher_preview_share'),
            onPressed: bytes == null ? null : _share,
            tooltip: 'مشاركة السند',
            icon: const Icon(Icons.share_rounded),
          ),
        ],
      ),
      body: _buildBody(bytes),
    );
  }

  Widget _buildBody(Uint8List? bytes) {
    if (_isBuilding) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            SizedBox(height: 14),
            Text(
              'جارٍ توليد السند...',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    if (_error != null || bytes == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.error_outline_rounded,
                size: 42,
                color: AppColors.danger,
              ),
              const SizedBox(height: 12),
              const Text(
                'تعذر توليد ملف السند.',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text(
                'تأكد من توفر مساحة تخزين كافية ثم أعد المحاولة.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _buildDocument,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    return PdfPreview(
      build: (PdfPageFormat format) async => bytes,
      initialPageFormat: PdfPageFormat.a4,
      pdfFileName: _fileName,
      allowPrinting: true,
      allowSharing: true,
      canChangePageFormat: false,
      canChangeOrientation: false,
      canDebug: false,
      onError: (BuildContext context, Object error) {
        return Center(
          child: Text(
            'تعذر عرض المعاينة: $error',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: AppColors.danger),
          ),
        );
      },
      pdfPreviewPageDecoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
    );
  }
}
