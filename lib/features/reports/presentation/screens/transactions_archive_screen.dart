import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/pdf_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_formatters.dart';
import '../../../inventory/data/models/item_model.dart';
import '../../../inventory/presentation/providers/inventory_provider.dart';
import '../../../transactions/data/models/transaction_model.dart';
import '../../../transactions/presentation/screens/voucher_preview_screen.dart';
import '../../../warehouses/data/models/warehouse_model.dart';
import '../../../warehouses/presentation/providers/warehouse_provider.dart';
import '../../data/models/report_models.dart';
import '../providers/reports_provider.dart';

/// سجل الحركات: بحث فوري، شرائح نوع، تصفية متقدمة، وإعادة طباعة أي سند.
class TransactionsArchiveScreen extends StatefulWidget {
  const TransactionsArchiveScreen({super.key});

  @override
  State<TransactionsArchiveScreen> createState() =>
      _TransactionsArchiveScreenState();
}

class _TransactionsArchiveScreenState extends State<TransactionsArchiveScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final ReportsProvider provider = context.read<ReportsProvider>();
      _searchController.text = provider.searchQuery;
      provider.loadReportsData(showLoader: false);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) {
        return;
      }
      context.read<ReportsProvider>().setSearchQuery(value);
    });
  }

  Future<void> _openAdvancedFilters() async {
    final ReportsProvider provider = context.read<ReportsProvider>();
    final List<WarehouseModel> warehouses = context
        .read<WarehouseProvider>()
        .warehouses;

    final _FilterResult? result = await showModalBottomSheet<_FilterResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) => _AdvancedFiltersSheet(
        warehouses: warehouses,
        initialWarehouseId: provider.warehouseId,
        initialRange: provider.dateRange,
      ),
    );

    if (result == null || !mounted) {
      return;
    }
    if (result.resetAll) {
      _searchController.clear();
      await provider.clearFilters();
      return;
    }
    await provider.applyFilters(
      warehouseId: result.warehouseId,
      transactionType: provider.transactionType,
      dateRange: result.dateRange,
      searchQuery: provider.searchQuery,
    );
  }

  void _openVoucherPdf(TransactionModel transaction) {
    final WarehouseModel? warehouse = context
        .read<WarehouseProvider>()
        .warehouseById(transaction.warehouseId);
    final ItemModel? item = context.read<InventoryProvider>().item;
    final _TransactionVisual visual = _visualFor(transaction.transactionType);

    final WarehouseModel effectiveWarehouse =
        warehouse ??
        WarehouseModel(
          name: 'مخزن #${transaction.warehouseId}',
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
          title: 'معاينة سند ${visual.shortLabel} ${transaction.voucherNumber}',
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

  void _openTransactionDetails(
    TransactionModel transaction,
    String warehouseName,
  ) {
    final _TransactionVisual visual = _visualFor(transaction.transactionType);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppColors.outline,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: <Widget>[
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: visual.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Icon(visual.icon, color: visual.color, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              visual.label,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              transaction.voucherNumber,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Column(
                      children: <Widget>[
                        _DetailRow(label: 'المخزن', value: warehouseName),
                        _DetailRow(
                          label: 'التاريخ والوقت',
                          value: AppFormatters.dateTime(transaction.createdAt),
                        ),
                        _DetailRow(
                          label: 'الكمية',
                          value: _signedQuantity(transaction),
                          valueColor: visual.color,
                        ),
                        if (_hasText(transaction.partyName))
                          _DetailRow(
                            label: visual.partyLabel,
                            value: transaction.partyName!.trim(),
                          ),
                        if (_hasText(transaction.orderReference))
                          _DetailRow(
                            label: 'رقم أمر الصرف',
                            value: transaction.orderReference!.trim(),
                          ),
                        if (_hasText(transaction.vehicleNumber))
                          _DetailRow(
                            label: 'رقم لوحة السيارة',
                            value: transaction.vehicleNumber!.trim(),
                          ),
                        if (_hasText(transaction.reason))
                          _DetailRow(
                            label: 'السبب',
                            value: transaction.reason!.trim(),
                          ),
                        if (_hasText(transaction.notes))
                          _DetailRow(
                            label: 'ملاحظات',
                            value: transaction.notes!.trim(),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton.icon(
                    key: const Key('archive_print_voucher_button'),
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      _openVoucherPdf(transaction);
                    },
                    icon: const Icon(Icons.picture_as_pdf_rounded, size: 19),
                    label: const Text('معاينة وطباعة السند PDF'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ReportsProvider provider = context.watch<ReportsProvider>();
    final WarehouseProvider warehouseProvider = context
        .watch<WarehouseProvider>();

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            key: const Key('archive_search_field'),
            controller: _searchController,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: 'ابحث برقم السند أو المندوب أو أمر الصرف',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'مسح البحث',
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                        setState(() {});
                      },
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
            ),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: _typeFilters
                .map((_TypeFilter filter) {
                  final bool selected =
                      provider.transactionType == filter.transactionType;
                  return Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: ChoiceChip(
                      label: Text(filter.label),
                      selected: selected,
                      showCheckmark: false,
                      onSelected: (_) =>
                          provider.setTypeFilter(filter.transactionType),
                      labelStyle: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? AppColors.primaryDark
                            : AppColors.textSecondary,
                      ),
                      selectedColor: AppColors.mist,
                      backgroundColor: AppColors.surface,
                      side: BorderSide(
                        color: selected ? AppColors.primary : AppColors.outline,
                      ),
                    ),
                  );
                })
                .toList(growable: false),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '${AppFormatters.number(provider.transactions.length)} حركة',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              OutlinedButton.icon(
                key: const Key('archive_advanced_filters'),
                onPressed: _openAdvancedFilters,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: Text(
                  provider.activeFiltersCount == 0
                      ? 'تصفية متقدمة'
                      : 'تصفية (${provider.activeFiltersCount})',
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _buildList(
            provider: provider,
            warehouseNameOf: (int id) =>
                warehouseProvider.warehouseById(id)?.name ?? 'مخزن #$id',
          ),
        ),
      ],
    );
  }

  Widget _buildList({
    required ReportsProvider provider,
    required String Function(int) warehouseNameOf,
  }) {
    if (provider.isLoading && provider.transactions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.errorMessage != null && provider.transactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.cloud_off_rounded,
              size: 40,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 10),
            Text(
              provider.errorMessage!,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => provider.loadReportsData(),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }

    if (provider.transactions.isEmpty) {
      return RefreshIndicator(
        onRefresh: provider.refresh,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: const <Widget>[_EmptyArchive()],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: provider.refresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: provider.transactions.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (BuildContext context, int index) {
          final TransactionModel transaction = provider.transactions[index];
          final String warehouseName = warehouseNameOf(transaction.warehouseId);
          return _ArchiveTile(
            transaction: transaction,
            warehouseName: warehouseName,
            onTap: () => _openTransactionDetails(transaction, warehouseName),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// أدوات مساعدة للعرض
// ---------------------------------------------------------------------------

bool _hasText(String? value) => value != null && value.trim().isNotEmpty;

String _signedQuantity(TransactionModel transaction) {
  final String sign = transaction.isIncrement ? '+' : '−';
  return '$sign${AppFormatters.number(transaction.quantity.abs())} '
      '${AppConstants.cartonUnit}';
}

class _TypeFilter {
  const _TypeFilter(this.label, this.transactionType);

  final String label;
  final String? transactionType;
}

const List<_TypeFilter> _typeFilters = <_TypeFilter>[
  _TypeFilter('الكل', null),
  _TypeFilter('استلام من المصنع', TransactionTypes.inbound),
  _TypeFilter('صرف للمناديب', TransactionTypes.outbound),
  _TypeFilter('إتلاف وهدر', TransactionTypes.damage),
  _TypeFilter('تسوية جرد', TransactionTypes.adjustment),
];

class _TransactionVisual {
  const _TransactionVisual({
    required this.label,
    required this.shortLabel,
    required this.color,
    required this.icon,
    required this.partyLabel,
  });

  final String label;
  final String shortLabel;
  final Color color;
  final IconData icon;
  final String partyLabel;
}

_TransactionVisual _visualFor(String transactionType) {
  switch (transactionType) {
    case TransactionTypes.inbound:
      return const _TransactionVisual(
        label: 'استلام من المصنع',
        shortLabel: 'استلام',
        color: AppColors.success,
        icon: Icons.move_to_inbox_rounded,
        partyLabel: 'مسلّم المصنع',
      );
    case TransactionTypes.outbound:
      return const _TransactionVisual(
        label: 'صرف لمندوب',
        shortLabel: 'صرف',
        color: AppColors.primary,
        icon: Icons.local_shipping_rounded,
        partyLabel: 'المندوب / المستلم',
      );
    case TransactionTypes.damage:
      return const _TransactionVisual(
        label: 'إتلاف / هدر',
        shortLabel: 'إتلاف',
        color: AppColors.danger,
        icon: Icons.report_gmailerrorred_rounded,
        partyLabel: 'المسؤول',
      );
    case TransactionTypes.adjustment:
      return const _TransactionVisual(
        label: 'تسوية جرد',
        shortLabel: 'تسوية',
        color: AppColors.warning,
        icon: Icons.fact_check_rounded,
        partyLabel: 'المسؤول',
      );
    default:
      return const _TransactionVisual(
        label: 'حركة مخزنية',
        shortLabel: 'حركة',
        color: AppColors.textSecondary,
        icon: Icons.receipt_long_rounded,
        partyLabel: 'الطرف الآخر',
      );
  }
}

class _ArchiveTile extends StatelessWidget {
  const _ArchiveTile({
    required this.transaction,
    required this.warehouseName,
    required this.onTap,
  });

  final TransactionModel transaction;
  final String warehouseName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final _TransactionVisual visual = _visualFor(transaction.transactionType);
    final String? party = _hasText(transaction.partyName)
        ? transaction.partyName!.trim()
        : null;

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
                  color: visual.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(visual.icon, color: visual.color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            transaction.voucherNumber,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: visual.color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            visual.label,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: visual.color,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      AppFormatters.dateTime(transaction.createdAt),
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      party == null
                          ? warehouseName
                          : '$warehouseName  ·  $party',
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
              Text(
                _signedQuantity(transaction),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: visual.color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyArchive extends StatelessWidget {
  const _EmptyArchive();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const <Widget>[
        SizedBox(height: 60),
        Icon(
          Icons.receipt_long_outlined,
          size: 46,
          color: AppColors.textSecondary,
        ),
        SizedBox(height: 12),
        Text(
          'لا توجد حركات مطابقة',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 6),
        Text(
          'جرّب تغيير نوع السند أو كلمة البحث أو النطاق الزمني.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: valueColor ?? AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// نافذة التصفية المتقدمة
// ---------------------------------------------------------------------------

class _FilterResult {
  const _FilterResult({
    this.warehouseId,
    this.dateRange,
    this.resetAll = false,
  });

  final int? warehouseId;
  final DateRange? dateRange;
  final bool resetAll;
}

class _AdvancedFiltersSheet extends StatefulWidget {
  const _AdvancedFiltersSheet({
    required this.warehouses,
    required this.initialWarehouseId,
    required this.initialRange,
  });

  final List<WarehouseModel> warehouses;
  final int? initialWarehouseId;
  final DateRange? initialRange;

  @override
  State<_AdvancedFiltersSheet> createState() => _AdvancedFiltersSheetState();
}

class _AdvancedFiltersSheetState extends State<_AdvancedFiltersSheet> {
  late int _warehouseValue;
  DateRange? _range;

  @override
  void initState() {
    super.initState();
    _warehouseValue = widget.initialWarehouseId ?? 0;
    _range = widget.initialRange;
  }

  Future<void> _pickCustomRange() async {
    final DateTime now = DateTime.now();
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _range == null
          ? null
          : DateTimeRange(start: _range!.start, end: _range!.end),
      helpText: 'اختر فترة التقرير',
      saveText: 'اعتماد',
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _range = DateRange(start: picked.start, end: picked.end);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'تصفية متقدمة',
                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                value: _warehouseValue,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'المخزن',
                  prefixIcon: Icon(Icons.warehouse_rounded, size: 20),
                ),
                items: <DropdownMenuItem<int>>[
                  const DropdownMenuItem<int>(
                    value: 0,
                    child: Text('كل المخازن'),
                  ),
                  ...widget.warehouses.map(
                    (WarehouseModel warehouse) => DropdownMenuItem<int>(
                      value: warehouse.id ?? 0,
                      child: Text(
                        warehouse.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: (int? value) =>
                    setState(() => _warehouseValue = value ?? 0),
              ),
              const SizedBox(height: 18),
              const Text(
                'النطاق الزمني',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _presetChip('كل الفترات', null),
                  _presetChip('اليوم', DateRange.day(DateTime.now())),
                  _presetChip('آخر 7 أيام', DateRange.lastDays(7)),
                  _presetChip('هذا الشهر', DateRange.thisMonth()),
                  ChoiceChip(
                    label: const Text('فترة مخصصة'),
                    selected: _range != null && !_isPreset(_range),
                    showCheckmark: false,
                    onSelected: (_) => _pickCustomRange(),
                    labelStyle: const TextStyle(fontSize: 11.5),
                  ),
                ],
              ),
              if (_range != null) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  'الفترة المختارة: ${AppFormatters.date(_range!.start)} '
                  '— ${AppFormatters.date(_range!.end)}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop(
                  _FilterResult(
                    warehouseId: _warehouseValue == 0 ? null : _warehouseValue,
                    dateRange: _range,
                  ),
                ),
                icon: const Icon(Icons.check_rounded, size: 19),
                label: const Text('تطبيق التصفية'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(
                  context,
                ).pop(const _FilterResult(resetAll: true)),
                child: const Text('إعادة تعيين كل الفلاتر'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isPreset(DateRange? value) {
    if (value == null) {
      return false;
    }
    final List<DateRange> presets = <DateRange>[
      DateRange.day(DateTime.now()),
      DateRange.lastDays(7),
      DateRange.thisMonth(),
    ];
    return presets.contains(value);
  }

  Widget _presetChip(String label, DateRange? value) {
    final bool selected = _range == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => setState(() => _range = value),
      labelStyle: const TextStyle(fontSize: 11.5),
    );
  }
}
