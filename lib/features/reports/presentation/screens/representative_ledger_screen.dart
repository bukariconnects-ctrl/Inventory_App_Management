import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/pdf_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_formatters.dart';
import '../../../inventory/data/models/item_model.dart';
import '../../../inventory/presentation/providers/inventory_provider.dart';
import '../../../stakeholders/data/models/stakeholder_model.dart';
import '../../../stakeholders/presentation/providers/stakeholder_provider.dart';
import '../../../transactions/data/models/transaction_model.dart';
import '../../../transactions/presentation/screens/voucher_preview_screen.dart';
import '../../../warehouses/data/models/warehouse_model.dart';
import '../../../warehouses/presentation/providers/warehouse_provider.dart';
import '../../data/models/report_models.dart';
import '../providers/reports_provider.dart';

/// الفترات السريعة في كشف مسحوبات المندوب.
enum _PeriodPreset { today, last7, thisMonth, custom }

/// كشف مسحوبات موزّع/مندوب: اختيار المندوب، فلترة الفترة، الإجماليات، والتصدير.
class RepresentativeLedgerScreen extends StatefulWidget {
  const RepresentativeLedgerScreen({super.key});

  @override
  State<RepresentativeLedgerScreen> createState() =>
      _RepresentativeLedgerScreenState();
}

class _RepresentativeLedgerScreenState
    extends State<RepresentativeLedgerScreen> {
  _PeriodPreset _preset = _PeriodPreset.last7;
  DateTimeRange? _customRange;
  String? _distributorName;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      final StakeholderProvider stakeholders = context
          .read<StakeholderProvider>();
      if (stakeholders.distributors.isEmpty && !stakeholders.isLoading) {
        await stakeholders.loadStakeholders(showLoader: false);
      }
      if (!mounted) {
        return;
      }
      final List<StakeholderModel> distributors = stakeholders.distributors;
      if (distributors.isEmpty) {
        return;
      }
      setState(() => _distributorName = distributors.first.name);
      await _reload();
    });
  }

  /// النطاق الزمني المطابق للشريحة المحددة.
  DateRange get _range {
    switch (_preset) {
      case _PeriodPreset.today:
        return DateRange.day(DateTime.now());
      case _PeriodPreset.last7:
        return DateRange.lastDays(7);
      case _PeriodPreset.thisMonth:
        return DateRange.thisMonth();
      case _PeriodPreset.custom:
        final DateTimeRange? custom = _customRange;
        if (custom == null) {
          return DateRange.lastDays(7);
        }
        return DateRange(start: custom.start, end: custom.end);
    }
  }

  Future<void> _reload() async {
    final String? name = _distributorName;
    if (name == null || name.trim().isEmpty) {
      return;
    }
    final DateRange range = _range;
    await context.read<ReportsProvider>().loadRepresentativeLedger(
      name,
      start: range.start,
      end: range.end,
    );
  }

  Future<void> _selectPreset(_PeriodPreset preset) async {
    if (preset == _PeriodPreset.custom) {
      final DateRange current = _range;
      final DateTimeRange? picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
        initialDateRange:
            _customRange ??
            DateTimeRange(start: current.start, end: current.end),
        helpText: 'اختر فترة الكشف',
        saveText: 'تطبيق',
      );
      if (picked == null || !mounted) {
        return;
      }
      setState(() {
        _preset = _PeriodPreset.custom;
        _customRange = picked;
      });
    } else {
      setState(() => _preset = preset);
    }
    await _reload();
  }

  void _export(RepresentativeLedger ledger) {
    final StakeholderModel? stakeholder = _findStakeholder(
      context.read<StakeholderProvider>().distributors,
      ledger.representativeName,
    );
    final ItemModel? item = context.read<InventoryProvider>().item;
    final ItemModel effectiveItem =
        item ??
        ItemModel(
          name: AppConstants.defaultItemName,
          createdAt: DateTime.now(),
        );
    final Map<int, String> warehouseNames = <int, String>{
      for (final WarehouseModel warehouse
          in context.read<WarehouseProvider>().warehouses)
        if (warehouse.id != null) warehouse.id!: warehouse.name,
    };
    final DateTime generatedAt = DateTime.now();

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => VoucherPreviewScreen(
          title: 'معاينة كشف مسحوبات ${ledger.representativeName}',
          voucherNumber: PdfService.representativeStatementReference(
            generatedAt,
          ),
          documentBuilder: () =>
              PdfService().generateRepresentativeStatementPdf(
                ledger: ledger,
                item: effectiveItem,
                generatedAt: generatedAt,
                representativePhone: stakeholder?.phone,
                representativeVehicle: stakeholder?.vehicleNumber,
                warehouseNames: warehouseNames,
              ),
        ),
      ),
    );
  }

  StakeholderModel? _findStakeholder(
    List<StakeholderModel> stakeholders,
    String name,
  ) {
    for (final StakeholderModel stakeholder in stakeholders) {
      if (stakeholder.name.trim() == name.trim()) {
        return stakeholder;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ReportsProvider provider = context.watch<ReportsProvider>();
    final List<StakeholderModel> distributors = context
        .watch<StakeholderProvider>()
        .distributors;
    final bool hasDistributors = distributors.isNotEmpty;
    final String? dropdownValue =
        hasDistributors &&
            distributors.any((StakeholderModel s) => s.name == _distributorName)
        ? _distributorName
        : null;

    return Scaffold(
      key: const Key('representative_ledger_screen'),
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('كشف مسحوبات مندوب'),
        actions: <Widget>[
          IconButton(
            key: const Key('distributor_ledger_export_pdf'),
            tooltip: 'معاينة وتصدير PDF',
            onPressed: provider.distributorLedger == null
                ? null
                : () => _export(provider.distributorLedger!),
            icon: const Icon(Icons.picture_as_pdf_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          physics: const AlwaysScrollableScrollPhysics(),
          children: <Widget>[
            if (hasDistributors)
              DropdownButtonFormField<String>(
                key: const Key('distributor_ledger_dropdown'),
                value: dropdownValue,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'المندوب / الموزّع',
                  prefixIcon: Icon(Icons.person_search_rounded, size: 20),
                ),
                items: <DropdownMenuItem<String>>[
                  for (final StakeholderModel stakeholder in distributors)
                    DropdownMenuItem<String>(
                      value: stakeholder.name,
                      child: Text(
                        stakeholder.vehicleNumber == null
                            ? stakeholder.name
                            : '${stakeholder.name} • ${stakeholder.vehicleNumber}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (String? value) async {
                  if (value == null) {
                    return;
                  }
                  setState(() => _distributorName = value);
                  await _reload();
                },
              )
            else
              _EmptyDistributors(),
            const SizedBox(height: 12),
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: <Widget>[
                  _presetChip('اليوم', _PeriodPreset.today),
                  _presetChip('آخر 7 أيام', _PeriodPreset.last7),
                  _presetChip('هذا الشهر', _PeriodPreset.thisMonth),
                  _presetChip(
                    _preset == _PeriodPreset.custom
                        ? 'فترة: ${AppFormatters.date(_range.start)}'
                        : 'فترة مخصصة',
                    _PeriodPreset.custom,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'الفترة: ${AppFormatters.date(_range.start)} إلى '
              '${AppFormatters.date(_range.end)}',
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textSecondary,
              ),
            ),
            if (provider.isLoadingDistributor) ...<Widget>[
              const SizedBox(height: 12),
              const LinearProgressIndicator(minHeight: 2),
            ],
            if (provider.distributorError != null) ...<Widget>[
              const SizedBox(height: 14),
              _ErrorBox(message: provider.distributorError!, onRetry: _reload),
            ],
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: _StatCard(
                    label: 'إجمالي الكراتين',
                    value: AppFormatters.number(
                      provider.distributorTotalCartons,
                    ),
                    unit: AppConstants.cartonUnit,
                    icon: Icons.inventory_2_rounded,
                    color: AppColors.primaryDark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    label: 'إجمالي العبوات',
                    value: AppFormatters.number(
                      provider.distributorTotalBottles,
                    ),
                    unit: 'عبوة',
                    icon: Icons.water_drop_rounded,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _StatCard(
              label: 'عدد السندات المسحوبة',
              value: AppFormatters.number(provider.distributorVoucherCount),
              unit: 'سند',
              icon: Icons.receipt_long_rounded,
              color: AppColors.cyan,
            ),
            const SizedBox(height: 22),
            const Text(
              'السندات المسحوبة',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (_distributorName == null && hasDistributors)
              const _HintBox(
                icon: Icons.person_search_rounded,
                title: 'اختر مندوباً لعرض كشفه',
                subtitle: 'يظهر الكشف بعد تحديد المندوب والفترة.',
              )
            else if (!provider.isLoadingDistributor &&
                provider.distributorLedgerTransactions.isEmpty)
              const _HintBox(
                icon: Icons.inbox_rounded,
                title: 'لا توجد سندات مسحوبة في هذه الفترة',
                subtitle: 'غيّر الفترة أو تحقق من اختيار المندوب.',
              )
            else
              ...provider.distributorLedgerTransactions.map(
                (TransactionModel transaction) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _LedgerTile(transaction: transaction),
                ),
              ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: provider.distributorLedger == null
                  ? null
                  : () => _export(provider.distributorLedger!),
              icon: const Icon(Icons.print_rounded, size: 19),
              label: const Text('معاينة وتصدير الكشف كـ PDF'),
            ),
            const SizedBox(height: 8),
            const Text(
              'يُطبع الكشف بمقاس A4 على الترويسة الرسمية لمصنع رواء، '
              'مع أسماء أمين المخزن والمندوب في خانات التواقيع.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10.5,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _presetChip(String label, _PeriodPreset preset) {
    final bool selected = _preset == preset;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => _selectPreset(preset),
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

/// بطاقة رقم مختصرة في رأس الكشف.
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final String unit;
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                unit,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
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

/// صف سند مسحوب داخل القائمة.
class _LedgerTile extends StatelessWidget {
  const _LedgerTile({required this.transaction});

  final TransactionModel transaction;

  @override
  Widget build(BuildContext context) {
    final bool replacement =
        transaction.transactionType == TransactionTypes.marketReplacement;
    final Color color = replacement ? AppColors.warning : AppColors.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              replacement
                  ? Icons.swap_horiz_rounded
                  : Icons.local_shipping_rounded,
              size: 19,
              color: color,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  transaction.voucherNumber,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${AppFormatters.dateTime(transaction.createdAt)}'
                  '${transaction.orderReference == null ? '' : ' • ${transaction.orderReference}'}',
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
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                AppFormatters.cartons(transaction.quantity.abs()),
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryDark,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                replacement ? 'بدل تالف' : 'صرف عادي',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyDistributors extends StatelessWidget {
  const _EmptyDistributors();

  @override
  Widget build(BuildContext context) {
    return const _HintBox(
      icon: Icons.contacts_rounded,
      title: 'دليل المناديب فارغ',
      subtitle: 'أضف مندوباً من دليل المناديب والموردين لعرض كشف مسحوباته.',
    );
  }
}

class _HintBox extends StatelessWidget {
  const _HintBox({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: <Widget>[
          Icon(icon, size: 32, color: AppColors.textSecondary),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.error_outline_rounded, color: AppColors.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 11.5, color: AppColors.danger),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
        ],
      ),
    );
  }
}
