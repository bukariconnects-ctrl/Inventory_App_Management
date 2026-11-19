import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/models/transaction_model.dart';

/// نافذة تأكيد موحّدة تُعرض بعد رفع طلب بحالة «بانتظار الاعتماد».
class PendingRequestDialog extends StatelessWidget {
  const PendingRequestDialog({super.key, required this.transaction});

  final TransactionModel transaction;

  static Future<void> show(
    BuildContext context, {
    required TransactionModel transaction,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) =>
          PendingRequestDialog(transaction: transaction),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.hourglass_top_rounded,
              color: AppColors.warning,
              size: 34,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'تم رفع الطلب بنجاح',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'رقم السند: ${transaction.voucherNumber}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryDark,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'الطلب الآن قيد الاعتماد ولم يُخصم من رصيد المخزن. '
            'اعتمده من شاشة «الطلبات المعلقة» ليُخصم الرصيد.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11.5,
              color: AppColors.textSecondary,
              height: 1.6,
            ),
          ),
        ],
      ),
      actions: <Widget>[
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            key: const Key('pending_request_ack_button'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('تم'),
          ),
        ),
      ],
    );
  }
}
