import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/pdf_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_formatters.dart';
import '../../../inventory/data/models/item_model.dart';
import '../../../warehouses/data/models/warehouse_model.dart';
import '../../data/models/transaction_model.dart';
import '../screens/voucher_preview_screen.dart';

/// نافذة نجاح موحّدة تُعرض بعد حفظ أي سند مخزني.
class TransactionSuccessDialog extends StatelessWidget {
  const TransactionSuccessDialog({
    super.key,
    required this.transaction,
    required this.warehouseName,
    required this.balanceAfter,
    this.warehouse,
    this.item,
  });

  final TransactionModel transaction;
  final String warehouseName;

  /// رصيد المخزن بعد تنفيذ السند.
  final int balanceAfter;

  /// المخزن الكامل (للطباعة) إن توفر.
  final WarehouseModel? warehouse;

  /// الصنف المعتمد (للطباعة) إن توفر.
  final ItemModel? item;

  static Future<void> show(
    BuildContext context, {
    required TransactionModel transaction,
    required String warehouseName,
    required int balanceAfter,
    WarehouseModel? warehouse,
    ItemModel? item,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => TransactionSuccessDialog(
        transaction: transaction,
        warehouseName: warehouseName,
        balanceAfter: balanceAfter,
        warehouse: warehouse,
        item: item,
      ),
    );
  }

  String get _typeLabel {
    switch (transaction.transactionType) {
      case TransactionTypes.inbound:
        return 'استلام كراتين من المصنع';
      case TransactionTypes.outbound:
        return 'صرف كراتين لمندوب';
      case TransactionTypes.damage:
        return 'إتلاف كراتين';
      case TransactionTypes.adjustment:
        return 'تسوية جرد';
      default:
        return 'حركة مخزنية';
    }
  }

  /// الاسم المختصر للنوع المستخدم في عنوان المعاينة.
  String get _voucherTypeName {
    switch (transaction.transactionType) {
      case TransactionTypes.inbound:
        return 'استلام';
      case TransactionTypes.outbound:
        return 'صرف';
      case TransactionTypes.damage:
        return 'إتلاف';
      case TransactionTypes.adjustment:
        return 'تسوية جرد';
      default:
        return 'مخزني';
    }
  }

  /// يفتح معاينة PDF للسند جاهزة للطباعة أو المشاركة.
  void _openVoucherPreview(BuildContext context) {
    final WarehouseModel effectiveWarehouse =
        warehouse ??
        WarehouseModel(
          name: warehouseName,
          location: '',
          createdAt: transaction.createdAt,
        );
    final ItemModel effectiveItem =
        item ??
        ItemModel(
          name: AppConstants.defaultItemName,
          createdAt: transaction.createdAt,
        );

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => VoucherPreviewScreen(
          title: 'معاينة سند $_voucherTypeName ${transaction.voucherNumber}',
          voucherNumber: transaction.voucherNumber,
          documentBuilder: () => PdfService().generateTransactionVoucher(
            transaction: transaction,
            warehouse: effectiveWarehouse,
            item: effectiveItem,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.6, end: 1),
              duration: const Duration(milliseconds: 450),
              curve: Curves.elasticOut,
              builder: (BuildContext context, double value, Widget? child) {
                return Transform.scale(scale: value, child: child);
              },
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: AppColors.success,
                  size: 42,
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'تم حفظ السند بنجاح',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              _typeLabel,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                children: <Widget>[
                  _DetailRow(
                    label: 'رقم السند',
                    value: transaction.voucherNumber,
                    highlight: true,
                  ),
                  const SizedBox(height: 10),
                  _DetailRow(label: 'المخزن', value: warehouseName),
                  const SizedBox(height: 10),
                  _DetailRow(
                    label: 'الكمية',
                    value: AppFormatters.cartons(transaction.quantity.abs()),
                  ),
                  const SizedBox(height: 10),
                  _DetailRow(
                    label: 'الرصيد الجديد',
                    value:
                        '${AppFormatters.number(balanceAfter)} '
                        '${AppConstants.cartonUnit}',
                    highlight: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                key: const Key('success_print_voucher_button'),
                onPressed: () => _openVoucherPreview(context),
                icon: const Icon(Icons.picture_as_pdf_rounded, size: 19),
                label: const Text('معاينة وطباعة / مشاركة السند'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('تم / العودة للرئيسية'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.left,
            style: TextStyle(
              fontSize: highlight ? 13.5 : 12.5,
              fontWeight: highlight ? FontWeight.w800 : FontWeight.w600,
              color: highlight ? AppColors.primaryDark : AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
