import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_formatters.dart';
import '../../../../core/widgets/stock_status_badge.dart';
import '../../data/models/item_model.dart';
import '../../data/models/stock_balance_status.dart';
import '../providers/inventory_provider.dart';

/// شاشة المخزون: بطاقة الصنف وإجمالي المتوفر وتوزيع الأرصدة على المخازن.
class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final InventoryProvider provider = context.watch<InventoryProvider>();

    if (provider.isLoading && provider.statuses.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.errorMessage != null && provider.statuses.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.cloud_off_rounded,
                size: 44,
                color: AppColors.textSecondary,
              ),
              const SizedBox(height: 12),
              Text(
                provider.errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => provider.loadInventoryStatus(),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    final ItemModel? item = provider.item;
    final int total = provider.totalCartons;

    return RefreshIndicator(
      onRefresh: provider.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        physics: const AlwaysScrollableScrollPhysics(),
        children: <Widget>[
          _ItemSummaryCard(
            itemName: item?.name ?? AppConstants.defaultItemName,
            bottleCount: item?.bottleCount ?? AppConstants.bottlesPerCarton,
            bottleVolumeMl: item?.bottleVolumeMl ?? AppConstants.bottleVolumeMl,
            totalCartons: total,
            warehousesCount: provider.activeWarehousesCount,
          ),
          const SizedBox(height: 22),
          Row(
            children: <Widget>[
              const Text(
                'توزيع الأرصدة على المخازن',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                '${provider.statuses.length} مخزن',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (provider.statuses.isEmpty)
            const _EmptyBalances()
          else
            ...provider.statuses.map(
              (StockBalanceStatus status) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _BalanceCard(status: status, totalCartons: total),
              ),
            ),
        ],
      ),
    );
  }
}

/// بطاقة الصنف العلوية: الاسم والمواصفات وإجمالي الكميات المتوفرة.
class _ItemSummaryCard extends StatelessWidget {
  const _ItemSummaryCard({
    required this.itemName,
    required this.bottleCount,
    required this.bottleVolumeMl,
    required this.totalCartons,
    required this.warehousesCount,
  });

  final String itemName;
  final int bottleCount;
  final int bottleVolumeMl;
  final int totalCartons;
  final int warehousesCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: <Color>[
            AppColors.primaryDark,
            AppColors.primary,
            AppColors.cyan,
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.28),
            blurRadius: 20,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.25),
                  ),
                ),
                child: const Icon(
                  Icons.water_drop_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      itemName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$bottleCount قنينة × $bottleVolumeMl مل',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Divider(color: Colors.white.withValues(alpha: 0.22), height: 1),
          const SizedBox(height: 16),
          Text(
            'إجمالي المتوفر في كل المخازن',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text(
                AppFormatters.number(totalCartons),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                AppConstants.cartonUnit,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'في $warehousesCount مخزن نشط',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// بطاقة رصيد مخزن واحد مع نسبته من الإجمالي وشريط تقدم.
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.status, required this.totalCartons});

  final StockBalanceStatus status;
  final int totalCartons;

  Color get _barColor {
    if (status.isOutOfStock) {
      return AppColors.danger;
    }
    if (status.isLowStock) {
      return AppColors.warning;
    }
    return AppColors.primary;
  }

  @override
  Widget build(BuildContext context) {
    final double share = totalCartons > 0
        ? (status.quantity / totalCartons).clamp(0.0, 1.0)
        : 0.0;
    final int percentage = (share * 100).round();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    status.warehouse.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                StockStatusBadge(
                  quantity: status.quantity,
                  minAlertLimit: status.minAlertLimit,
                  isActive: status.warehouse.isActive,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                const Icon(
                  Icons.location_on_outlined,
                  size: 13,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 3),
                Text(
                  status.warehouse.location,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Text(
                  AppFormatters.cartons(status.quantity),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryDark,
                  ),
                ),
                const Spacer(),
                Text(
                  '$percentage% من الإجمالي',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: share,
                minHeight: 8,
                backgroundColor: AppColors.divider,
                valueColor: AlwaysStoppedAnimation<Color>(_barColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyBalances extends StatelessWidget {
  const _EmptyBalances();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: <Widget>[
            const Icon(
              Icons.inventory_2_outlined,
              size: 38,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 10),
            const Text(
              'لا توجد أرصدة مسجّلة',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'أضف مخزنًا من تبويب المخازن ليظهر رصيده هنا.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
