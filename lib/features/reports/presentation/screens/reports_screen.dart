import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/pdf_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_formatters.dart';
import '../../../inventory/data/models/item_model.dart';
import '../../../inventory/presentation/providers/inventory_provider.dart';
import '../../../transactions/presentation/screens/voucher_preview_screen.dart';
import '../../../warehouses/data/models/warehouse_model.dart';
import '../../../warehouses/presentation/providers/warehouse_provider.dart';
import '../../data/models/report_models.dart';
import '../providers/reports_provider.dart';

/// التقارير والإحصائيات: مقاييس الفترة، مسحوبات المناديب، وتصدير تقرير PDF.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      context.read<ReportsProvider>().loadReportsData(showLoader: false);
    });
  }

  Future<void> _exportReport(ReportsProvider provider) async {
    final DateTime generatedAt = DateTime.now();
    final WarehouseModel? warehouse = context
        .read<WarehouseProvider>()
        .warehouseById(provider.warehouseId);
    final ItemModel? item = context.read<InventoryProvider>().item;
    final ItemModel effectiveItem =
        item ??
        ItemModel(name: AppConstants.defaultItemName, createdAt: generatedAt);
    final PeriodSummaryMetrics metrics = provider.metrics;
    final List<RepresentativeSummary> representatives =
        provider.representatives;
    final DateRange? period = provider.dateRange;

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => VoucherPreviewScreen(
          title: 'معاينة تقرير المخزون العام',
          voucherNumber: PdfService.summaryReportReference(generatedAt),
          documentBuilder: () => PdfService().generateInventorySummaryReportPdf(
            metrics: metrics,
            representatives: representatives,
            item: effectiveItem,
            generatedAt: generatedAt,
            warehouse: warehouse,
            period: period,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ReportsProvider provider = context.watch<ReportsProvider>();
    final WarehouseProvider warehouseProvider = context
        .watch<WarehouseProvider>();
    final String scopeLabel = provider.warehouseId == null
        ? 'كل المخازن'
        : warehouseProvider.warehouseById(provider.warehouseId)?.name ??
              'مخزن #${provider.warehouseId}';

    return RefreshIndicator(
      onRefresh: provider.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        physics: const AlwaysScrollableScrollPhysics(),
        children: <Widget>[
          if (provider.isLoading) ...<Widget>[
            const LinearProgressIndicator(minHeight: 2),
            const SizedBox(height: 10),
          ],
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: <Widget>[
                _periodChip(provider, 'كل الفترات', null),
                _periodChip(provider, 'اليوم', DateRange.day(DateTime.now())),
                _periodChip(provider, 'آخر 7 أيام', DateRange.lastDays(7)),
                _periodChip(provider, 'هذا الشهر', DateRange.thisMonth()),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              const Icon(
                Icons.filter_alt_outlined,
                size: 15,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'النطاق: $scopeLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              Text(
                '${AppFormatters.number(provider.metrics.voucherCount)} سند',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          if (provider.errorMessage != null) ...<Widget>[
            const SizedBox(height: 12),
            _ErrorBox(
              message: provider.errorMessage!,
              onRetry: provider.refresh,
            ),
          ],
          const SizedBox(height: 14),
          _MetricsGrid(metrics: provider.metrics),
          const SizedBox(height: 20),
          Row(
            children: <Widget>[
              const Text(
                'مسحوبات المناديب',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                'الأكثر سحباً',
                style: TextStyle(
                  fontSize: 10.5,
                  color: AppColors.textSecondary.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _RepresentativesCard(
            representatives: provider.representatives,
            totalOutbound: provider.metrics.totalOutbound,
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            key: const Key('reports_export_pdf_button'),
            onPressed: () => _exportReport(provider),
            icon: const Icon(Icons.picture_as_pdf_rounded, size: 19),
            label: const Text('تصدير تقرير المخزون العام PDF'),
          ),
          const SizedBox(height: 8),
          const Text(
            'يُصدَّر التقرير وفق نفس الفترة والنطاق المحددين أعلاه.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10.5, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _periodChip(ReportsProvider provider, String label, DateRange? range) {
    final bool selected = provider.dateRange == range;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => provider.setDateRange(range),
        labelStyle: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: selected ? AppColors.primaryDark : AppColors.textSecondary,
        ),
        selectedColor: AppColors.mist,
        backgroundColor: AppColors.surface,
        side: BorderSide(
          color: selected ? AppColors.primary : AppColors.outline,
        ),
      ),
    );
  }
}

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({required this.metrics});

  final PeriodSummaryMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final bool netNegative = metrics.netChange < 0;
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: _MetricCard(
                label: 'إجمالي الوارد',
                value: metrics.totalInbound,
                icon: Icons.move_to_inbox_rounded,
                color: AppColors.success,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                label: 'إجمالي المنصرف',
                value: metrics.totalOutbound,
                icon: Icons.local_shipping_rounded,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: _MetricCard(
                label: 'إجمالي التالف',
                value: metrics.totalDamaged,
                icon: Icons.report_gmailerrorred_rounded,
                color: AppColors.danger,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                label: netNegative ? 'صافي التغير (انخفاض)' : 'صافي التغير',
                value: metrics.netChange.abs(),
                icon: netNegative
                    ? Icons.trending_down_rounded
                    : Icons.trending_up_rounded,
                color: netNegative ? AppColors.danger : AppColors.primaryDark,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 17, color: color),
              ),
              const Spacer(),
              Icon(
                Icons.water_drop_outlined,
                size: 14,
                color: color.withValues(alpha: 0.35),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            AppFormatters.number(value),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.1,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _RepresentativesCard extends StatelessWidget {
  const _RepresentativesCard({
    required this.representatives,
    required this.totalOutbound,
  });

  final List<RepresentativeSummary> representatives;
  final int totalOutbound;

  @override
  Widget build(BuildContext context) {
    if (representatives.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: const <Widget>[
              Icon(
                Icons.people_outline_rounded,
                size: 34,
                color: AppColors.textSecondary,
              ),
              SizedBox(height: 8),
              Text(
                'لا توجد عمليات صرف في هذه الفترة',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 4),
              Text(
                'ستظهر قائمة المناديب تلقائيًا بعد تسجيل أول سند صرف.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
        child: Column(
          children: <Widget>[
            for (int index = 0; index < representatives.length; index++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: _RepresentativeRow(
                  rank: index + 1,
                  representative: representatives[index],
                  share: representatives[index].shareOf(totalOutbound),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RepresentativeRow extends StatelessWidget {
  const _RepresentativeRow({
    required this.rank,
    required this.representative,
    required this.share,
  });

  final int rank;
  final RepresentativeSummary representative;
  final double share;

  @override
  Widget build(BuildContext context) {
    final bool isTop = rank == 1;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isTop
                ? AppColors.primary
                : AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$rank',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: isTop ? Colors.white : AppColors.primary,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      representative.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    AppFormatters.cartons(representative.totalQuantity),
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: share.clamp(0, 1),
                  minHeight: 5,
                  backgroundColor: AppColors.surfaceVariant,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${AppFormatters.number(representative.voucherCount)} سند '
                '• ${(share * 100).round()}% من إجمالي الصرف',
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: AppColors.danger,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 11.5, color: AppColors.danger),
            ),
          ),
          TextButton(onPressed: () => onRetry(), child: const Text('إعادة')),
        ],
      ),
    );
  }
}
