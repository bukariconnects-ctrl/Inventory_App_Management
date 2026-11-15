import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// شارة حالة الرصيد: مستقر / رصيد منخفض / نافد / غير نشط.
class StockStatusBadge extends StatelessWidget {
  const StockStatusBadge({
    super.key,
    required this.quantity,
    required this.minAlertLimit,
    this.isActive = true,
  });

  final int quantity;
  final int minAlertLimit;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    late final String label;
    late final Color color;

    if (!isActive) {
      label = 'غير نشط';
      color = AppColors.textSecondary;
    } else if (quantity == 0) {
      label = 'نافد';
      color = AppColors.danger;
    } else if (quantity <= minAlertLimit) {
      label = 'رصيد منخفض';
      color = AppColors.warning;
    } else {
      label = 'مستقر';
      color = AppColors.success;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
