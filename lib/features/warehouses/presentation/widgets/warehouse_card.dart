import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_formatters.dart';
import '../../../../core/widgets/stock_status_badge.dart';
import '../../data/models/warehouse_model.dart';

/// بطاقة مخزن: الاسم، الموقع، الرصيد بالكرتون، حد التنبيه، وشارة الحالة.
class WarehouseCard extends StatelessWidget {
  const WarehouseCard({
    super.key,
    required this.warehouse,
    required this.quantity,
    required this.onEdit,
    required this.onToggleStatus,
    required this.onStocktake,
  });

  final WarehouseModel warehouse;
  final int quantity;
  final VoidCallback onEdit;
  final VoidCallback onToggleStatus;
  final VoidCallback onStocktake;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isLowStock =
        warehouse.isActive && quantity <= warehouse.minAlertLimit;

    return Opacity(
      opacity: warehouse.isActive ? 1 : 0.65,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: warehouse.isActive
                          ? AppColors.mist
                          : AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.warehouse_rounded,
                      color: warehouse.isActive
                          ? AppColors.primary
                          : AppColors.textSecondary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          warehouse.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: <Widget>[
                            const Icon(
                              Icons.location_on_outlined,
                              size: 13,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                warehouse.location,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: AppColors.textSecondary,
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'خيارات المخزن',
                    icon: const Icon(
                      Icons.more_vert_rounded,
                      color: AppColors.textSecondary,
                    ),
                    onSelected: (String value) {
                      if (value == 'edit') {
                        onEdit();
                      } else if (value == 'stocktake') {
                        onStocktake();
                      } else if (value == 'toggle') {
                        onToggleStatus();
                      }
                    },
                    itemBuilder: (BuildContext context) =>
                        <PopupMenuEntry<String>>[
                          const PopupMenuItem<String>(
                            value: 'edit',
                            child: Row(
                              children: <Widget>[
                                Icon(Icons.edit_outlined, size: 18),
                                SizedBox(width: 10),
                                Text('تعديل البيانات'),
                              ],
                            ),
                          ),
                          const PopupMenuItem<String>(
                            value: 'stocktake',
                            child: Row(
                              children: <Widget>[
                                Icon(Icons.fact_check_outlined, size: 18),
                                SizedBox(width: 10),
                                Text('جرد هذا المخزن'),
                              ],
                            ),
                          ),
                          PopupMenuItem<String>(
                            value: 'toggle',
                            child: Row(
                              children: <Widget>[
                                Icon(
                                  warehouse.isActive
                                      ? Icons.block_outlined
                                      : Icons.check_circle_outline,
                                  size: 18,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  warehouse.isActive
                                      ? 'تعطيل المخزن'
                                      : 'تفعيل المخزن',
                                ),
                              ],
                            ),
                          ),
                        ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: <Widget>[
                          Text(
                            AppFormatters.number(quantity),
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                              color: isLowStock
                                  ? AppColors.warning
                                  : AppColors.primaryDark,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'كرتون',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'حد التنبيه: ${AppFormatters.number(warehouse.minAlertLimit)} كرتون',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  StockStatusBadge(
                    quantity: quantity,
                    minAlertLimit: warehouse.minAlertLimit,
                    isActive: warehouse.isActive,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
