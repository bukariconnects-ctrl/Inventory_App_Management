import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_formatters.dart';
import '../../../../core/widgets/stock_status_badge.dart';
import '../../../inventory/data/models/stock_balance_status.dart';
import '../../../inventory/presentation/providers/inventory_provider.dart';
import '../../../stakeholders/presentation/screens/stakeholders_screen.dart';
import '../../../stocktake/presentation/screens/stocktake_screen.dart';
import '../../../transactions/presentation/providers/transaction_provider.dart';
import '../../../transactions/presentation/screens/damage_voucher_screen.dart';
import '../../../transactions/presentation/screens/inbound_voucher_screen.dart';
import '../../../transactions/presentation/screens/market_replacement_voucher_screen.dart';
import '../../../transactions/presentation/screens/outbound_voucher_screen.dart';
import '../../../transactions/presentation/screens/pending_approvals_screen.dart';
import '../../../warehouses/presentation/providers/warehouse_provider.dart';

/// محتوى لوحة التحكم: تنبيه النقص، الإحصائيات، وحالة المخازن السريعة.
class DashboardView extends StatelessWidget {
  const DashboardView({
    super.key,
    required this.onOpenInventory,
    this.onOpenArchive,
  });

  /// يُستدعى عند طلب الانتقال إلى تبويب المخزون.
  final VoidCallback onOpenInventory;

  /// يُستدعى عند طلب الانتقال إلى تبويب السجل والتقارير.
  final VoidCallback? onOpenArchive;

  Future<void> _refresh(BuildContext context) async {
    final WarehouseProvider warehouseProvider = context
        .read<WarehouseProvider>();
    final InventoryProvider inventoryProvider = context
        .read<InventoryProvider>();
    await Future.wait(<Future<void>>[
      warehouseProvider.loadWarehouses(showLoader: false),
      inventoryProvider.loadInventoryStatus(showLoader: false),
      context.read<TransactionProvider>().loadPendingApprovals(
        showLoader: false,
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final InventoryProvider inventory = context.watch<InventoryProvider>();
    final WarehouseProvider warehouses = context.watch<WarehouseProvider>();
    final TransactionProvider transactions = context
        .watch<TransactionProvider>();

    if (inventory.isLoading && inventory.statuses.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (inventory.errorMessage != null && inventory.statuses.isEmpty) {
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
                inventory.errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => inventory.loadInventoryStatus(),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    final List<StockBalanceStatus> quickList = inventory.statuses
        .take(3)
        .toList(growable: false);

    return RefreshIndicator(
      onRefresh: () => _refresh(context),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        physics: const AlwaysScrollableScrollPhysics(),
        children: <Widget>[
          if (transactions.pendingCount > 0) ...<Widget>[
            _PendingApprovalsBanner(
              count: transactions.pendingCount,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) =>
                      const PendingApprovalsScreen(),
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          if (inventory.hasLowStockAlert) ...<Widget>[
            _LowStockBanner(
              lowStockCount: inventory.lowStockCount,
              outOfStockCount: inventory.outOfStockCount,
            ),
            const SizedBox(height: 14),
          ],
          _TotalCartonsCard(
            totalCartons: inventory.totalCartons,
            activeWarehouses: warehouses.activeCount,
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: _StatCard(
                  label: 'مخازن فعالة',
                  value: '${warehouses.activeCount}',
                  icon: Icons.warehouse_rounded,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  label: 'تنبيهات حرجة',
                  value: '${inventory.lowStockCount}',
                  icon: Icons.warning_amber_rounded,
                  color: inventory.lowStockCount > 0
                      ? AppColors.warning
                      : AppColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const Text(
            'إجراءات سريعة',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          const _QuickActions(),
          const SizedBox(height: 12),
          const _SecondaryActions(),
          const SizedBox(height: 12),
          _SectionLink(
            title: 'دليل المناديب والموردين',
            subtitle: 'هواتف المناديب • سائقو المصنع • اتصال وواتساب',
            icon: Icons.contacts_rounded,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext context) => const StakeholdersScreen(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _SectionLink(
            title: 'سجل الحركات والتقارير',
            subtitle: 'بحث في السندات • إعادة الطباعة • إحصاءات الفترة',
            icon: Icons.receipt_long_rounded,
            onTap: onOpenArchive,
          ),
          const SizedBox(height: 22),
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  'حالة المخازن السريعة',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              TextButton(
                onPressed: onOpenInventory,
                child: const Text('عرض الكل'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (quickList.isEmpty)
            const _EmptyQuickList()
          else
            ...quickList.map(
              (StockBalanceStatus status) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _QuickWarehouseTile(status: status),
              ),
            ),
        ],
      ),
    );
  }
}

/// شريط يظهر عند وجود طلبات معلقة بانتظار الاعتماد.
class _PendingApprovalsBanner extends StatelessWidget {
  const _PendingApprovalsBanner({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const Key('dashboard_pending_banner'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.hourglass_top_rounded,
                  color: AppColors.warning,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '$count ${count == 1 ? 'طلب معلق' : 'طلبات معلقة'} '
                      'بانتظار الاعتماد',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF8A5A00),
                      ),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'بدل تالف ومحاضر إتلاف لم تُخصم من الرصيد بعد.',
                      style: TextStyle(fontSize: 11, color: Color(0xFF8A5A00)),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_left_rounded,
                size: 20,
                color: Color(0xFF8A5A00),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// شريط تحذيري يظهر فقط عند وجود مخازن برصيد منخفض.
class _LowStockBanner extends StatelessWidget {
  const _LowStockBanner({
    required this.lowStockCount,
    required this.outOfStockCount,
  });

  final int lowStockCount;
  final int outOfStockCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.warning,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'رصيد منخفض في $lowStockCount ${lowStockCount == 1 ? 'مخزن' : 'مخازن'}',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF8A5A00),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  outOfStockCount > 0
                      ? 'منها $outOfStockCount نافد تمامًا — راجع الأرصدة وأعد التزويد.'
                      : 'وصل الرصيد إلى حد التنبيه — راجع الأرصدة وأعد التزويد.',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF8A5A00),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// البطاقة الرئيسية لإجمالي كراتين المياه.
class _TotalCartonsCard extends StatelessWidget {
  const _TotalCartonsCard({
    required this.totalCartons,
    required this.activeWarehouses,
  });

  final int totalCartons;
  final int activeWarehouses;

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
              Icon(
                Icons.inventory_2_rounded,
                color: Colors.white.withValues(alpha: 0.85),
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'إجمالي كراتين المياه',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text(
                AppFormatters.number(totalCartons),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'كرتون',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'موزعة على $activeWarehouses مخزن نشط • '
            '${AppFormatters.bottlesFor(totalCartons)} '
            '(${AppConstants.bottlesPerCarton} عبوة في الكرتون)',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickWarehouseTile extends StatelessWidget {
  const _QuickWarehouseTile({required this.status});

  final StockBalanceStatus status;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: <Widget>[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.mist,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.warehouse_rounded,
                color: AppColors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    status.warehouse.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    status.warehouse.location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  AppFormatters.cartons(status.quantity),
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryDark,
                  ),
                ),
                const SizedBox(height: 5),
                StockStatusBadge(
                  quantity: status.quantity,
                  minAlertLimit: status.minAlertLimit,
                  isActive: status.warehouse.isActive,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// زرّا الإجراءات السريعة: توريد من المصنع وصرف للمناديب.
class _QuickActions extends StatelessWidget {
  const _QuickActions();

  void _open(BuildContext context, Widget screen) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (BuildContext context) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _QuickActionCard(
            title: 'توريد كراتين من المصنع',
            subtitle: 'سند استلام',
            icon: Icons.move_to_inbox_rounded,
            colors: <Color>[AppColors.cyan, AppColors.primary],
            onTap: () => _open(context, const InboundVoucherScreen()),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _QuickActionCard(
            title: 'صرف كراتين للمناديب',
            subtitle: 'سند صرف',
            icon: Icons.local_shipping_rounded,
            colors: <Color>[AppColors.primary, AppColors.primaryDark],
            onTap: () => _open(context, const OutboundVoucherScreen()),
          ),
        ),
      ],
    );
  }
}

/// الصف الثاني من الإجراءات: تسجيل التالف وجرد المخزن.
class _SecondaryActions extends StatelessWidget {
  const _SecondaryActions();

  void _open(BuildContext context, Widget screen) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (BuildContext context) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: _QuickActionCard(
                title: 'تسجيل تالف مخزني',
                subtitle: 'محضر إتلاف',
                icon: Icons.report_gmailerrorred_rounded,
                colors: <Color>[AppColors.warning, AppColors.danger],
                onTap: () => _open(context, const DamageVoucherScreen()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _QuickActionCard(
                title: 'جرد وتسوية',
                subtitle: 'جرد المخزن',
                icon: Icons.fact_check_rounded,
                colors: <Color>[AppColors.primaryDark, AppColors.cyan],
                onTap: () => _open(context, const StocktakeScreen()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: _QuickActionCard(
                title: 'صرف بدل تالف',
                subtitle: 'لمندوب — قيد الاعتماد',
                icon: Icons.swap_horiz_rounded,
                colors: <Color>[AppColors.cyan, AppColors.primaryDark],
                onTap: () =>
                    _open(context, const MarketReplacementVoucherScreen()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _QuickActionCard(
                title: 'الطلبات المعلقة',
                subtitle: 'اعتماد ورفض',
                icon: Icons.pending_actions_rounded,
                colors: <Color>[AppColors.warning, AppColors.danger],
                onTap: () => _open(context, const PendingApprovalsScreen()),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colors,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 126,
      child: Material(
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: colors,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(icon, color: Colors.white, size: 20),
                  ),
                  const Spacer(),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// رابط قسم داخلي في لوحة التحكم (السجل والتقارير).
class _SectionLink extends StatelessWidget {
  const _SectionLink({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.mist,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_left_rounded,
                size: 20,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyQuickList extends StatelessWidget {
  const _EmptyQuickList();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: <Widget>[
            const Icon(
              Icons.warehouse_outlined,
              size: 34,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 8),
            const Text(
              'لا توجد مخازن بعد',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'أضف مخزنك الأول من تبويب المخازن لبدء تسجيل الأرصدة.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
