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

/// اليومية المخزنية الشاملة: ميزان اليوم، كل حركاته، والتصدير الرسمي A4.
class DailyJournalScreen extends StatefulWidget {
  const DailyJournalScreen({super.key});

  @override
  State<DailyJournalScreen> createState() => _DailyJournalScreenState();
}

class _DailyJournalScreenState extends State<DailyJournalScreen> {
  int? _warehouseId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      final WarehouseProvider warehouses = context.read<WarehouseProvider>();
      if (warehouses.warehouses.isEmpty && !warehouses.isLoading) {
        await warehouses.loadWarehouses(showLoader: false);
      }
      if (!mounted) {
        return;
      }
      await _reload(context.read<ReportsProvider>().selectedJournalDate);
    });
  }

  Future<void> _reload(DateTime date) async {
    await context.read<ReportsProvider>().loadDailyJournal(
      date,
      warehouseId: _warehouseId,
    );
  }

  Future<void> _pickDate() async {
    final ReportsProvider provider = context.read<ReportsProvider>();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: provider.selectedJournalDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: 'اختر اليوم المخزني',
    );
    if (picked == null || !mounted) {
      return;
    }
    await _reload(picked);
  }

  void _export(DailyJournalReport journal) {
    final ItemModel? item = context.read<InventoryProvider>().item;
    final ItemModel effectiveItem =
        item ??
        ItemModel(
          name: AppConstants.defaultItemName,
          createdAt: DateTime.now(),
        );
    final WarehouseModel? warehouse = context
        .read<WarehouseProvider>()
        .warehouseById(_warehouseId);
    final Map<int, String> warehouseNames = <int, String>{
      for (final WarehouseModel entry
          in context.read<WarehouseProvider>().warehouses)
        if (entry.id != null) entry.id!: entry.name,
    };
    final DateTime generatedAt = DateTime.now();

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => VoucherPreviewScreen(
          title:
              'معاينة اليومية المخزنية - ${AppFormatters.date(journal.date)}',
          voucherNumber: PdfService.dailyJournalReference(journal.date),
          documentBuilder: () => PdfService().generateDailyJournalPdf(
            journal: journal,
            item: effectiveItem,
            generatedAt: generatedAt,
            warehouse: warehouse,
            warehouseNames: warehouseNames,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ReportsProvider provider = context.watch<ReportsProvider>();
    final List<WarehouseModel> warehouses = context
        .watch<WarehouseProvider>()
        .warehouses;
    final DailyJournalReport? journal = provider.dailyJournalData;

    return Scaffold(
      key: const Key('daily_journal_screen'),
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('اليومية المخزنية الشاملة'),
        actions: <Widget>[
          IconButton(
            key: const Key('daily_journal_export_pdf'),
            tooltip: 'معاينة وطباعة PDF',
            onPressed: journal == null ? null : () => _export(journal),
            icon: const Icon(Icons.picture_as_pdf_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _reload(provider.selectedJournalDate),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          physics: const AlwaysScrollableScrollPhysics(),
          children: <Widget>[
            InkWell(
              key: const Key('daily_journal_date_picker'),
              borderRadius: BorderRadius.circular(16),
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppColors.mist,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(
                        Icons.today_rounded,
                        size: 20,
                        color: AppColors.primaryDark,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text(
                            'اليوم المخزني',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            AppFormatters.date(provider.selectedJournalDate),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.edit_calendar_rounded,
                      size: 19,
                      color: AppColors.primary,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              value: _warehouseId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'المخزن',
                prefixIcon: Icon(Icons.warehouse_rounded, size: 20),
              ),
              items: <DropdownMenuItem<int?>>[
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('كل المخازن'),
                ),
                for (final WarehouseModel warehouse in warehouses)
                  DropdownMenuItem<int?>(
                    value: warehouse.id,
                    child: Text(
                      warehouse.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (int? value) async {
                setState(() => _warehouseId = value);
                await _reload(provider.selectedJournalDate);
              },
            ),
            if (provider.isLoadingJournal) ...<Widget>[
              const SizedBox(height: 12),
              const LinearProgressIndicator(minHeight: 2),
            ],
            if (provider.journalError != null) ...<Widget>[
              const SizedBox(height: 14),
              _ErrorBox(
                message: provider.journalError!,
                onRetry: () => _reload(provider.selectedJournalDate),
              ),
            ],
            const SizedBox(height: 16),
            _ClosingBalanceCard(
              journal: journal,
              warehouseName: _warehouseId == null
                  ? 'كل المخازن'
                  : context
                            .read<WarehouseProvider>()
                            .warehouseById(_warehouseId)
                            ?.name ??
                        'مخزن #$_warehouseId',
            ),
            const SizedBox(height: 14),
            if (journal != null) ...<Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: _BalanceTile(
                      label: 'رصيد بداية اليوم',
                      value: journal.openingBalance,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _BalanceTile(
                      label: 'الوارد',
                      value: journal.inboundCartons,
                      color: AppColors.success,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _BalanceTile(
                      label: 'المنصرف',
                      value: journal.outboundCartons,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _BalanceTile(
                      label: 'التالف والبدل',
                      value: journal.damagedAndReplacementCartons,
                      color: AppColors.danger,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 22),
            Row(
              children: <Widget>[
                const Text(
                  'حركات اليوم',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text(
                  '${AppFormatters.number(journal?.voucherCount ?? 0)} سند',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (journal == null && !provider.isLoadingJournal)
              const _HintBox(
                icon: Icons.event_busy_rounded,
                title: 'لا توجد بيانات لهذا اليوم',
                subtitle: 'اختر يوماً آخر أو تحقق من المخزن المحدد.',
              )
            else if (journal != null && journal.transactions.isEmpty)
              const _HintBox(
                icon: Icons.inbox_rounded,
                title: 'يوم بلا حركات مخزنية',
                subtitle:
                    'لم تُسجَّل سندات استلام أو صرف أو إتلاف في هذا اليوم.',
              )
            else if (journal != null)
              ...journal.transactions.map(
                (TransactionModel transaction) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _JournalTile(transaction: transaction),
                ),
              ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: journal == null ? null : () => _export(journal),
              icon: const Icon(Icons.print_rounded, size: 19),
              label: const Text('معاينة وطباعة اليومية المخزنية كـ PDF'),
            ),
            const SizedBox(height: 8),
            const Text(
              'تُطبع اليومية بمقاس A4 على الترويسة الرسمية لمصنع رواء، '
              'مع ميزان اليوم، التفاصيل الزمنية، وتوقيع أمين المخزن واعتماد الإدارة.',
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
}

/// بطاقة الإغلاق اليومي بالتدرج الأزرق.
class _ClosingBalanceCard extends StatelessWidget {
  const _ClosingBalanceCard({
    required this.journal,
    required this.warehouseName,
  });

  final DailyJournalReport? journal;
  final String warehouseName;

  @override
  Widget build(BuildContext context) {
    final int closing = journal?.closingBalance ?? 0;
    final int net = journal?.netChange ?? 0;
    final bool negative = net < 0;

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
                Icons.fact_check_rounded,
                color: Colors.white.withValues(alpha: 0.85),
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'رصيد إغلاق اليوم • $warehouseName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
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
                AppFormatters.number(closing),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 38,
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
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${AppFormatters.bottlesFor(closing)} • صافي حركة اليوم: '
            '${negative ? '−' : '+'}${AppFormatters.number(net.abs())} '
            '${AppConstants.cartonUnit}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _BalanceTile extends StatelessWidget {
  const _BalanceTile({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Flexible(
                child: Text(
                  AppFormatters.number(value),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Text(
                AppConstants.cartonUnit,
                style: TextStyle(fontSize: 9.5, color: AppColors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// صف حركة داخل اليومية مع شارة نوع ملوّنة.
class _JournalTile extends StatelessWidget {
  const _JournalTile({required this.transaction});

  final TransactionModel transaction;

  @override
  Widget build(BuildContext context) {
    final _JournalVisual visual = _visualFor(transaction.transactionType);

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
              color: visual.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(visual.icon, size: 19, color: visual.color),
          ),
          const SizedBox(width: 11),
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
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1.5,
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
                const SizedBox(height: 3),
                Text(
                  '${AppFormatters.time(transaction.createdAt)}'
                  '${transaction.partyName == null ? '' : ' • ${transaction.partyName}'}',
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
            AppFormatters.cartons(transaction.quantity.abs()),
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: AppColors.primaryDark,
            ),
          ),
        ],
      ),
    );
  }

  _JournalVisual _visualFor(String transactionType) {
    switch (transactionType) {
      case TransactionTypes.inbound:
        return const _JournalVisual(
          label: 'استلام',
          icon: Icons.move_to_inbox_rounded,
          color: AppColors.success,
        );
      case TransactionTypes.outbound:
        return const _JournalVisual(
          label: 'صرف',
          icon: Icons.local_shipping_rounded,
          color: AppColors.primary,
        );
      case TransactionTypes.marketReplacement:
        return const _JournalVisual(
          label: 'بدل تالف',
          icon: Icons.swap_horiz_rounded,
          color: AppColors.warning,
        );
      case TransactionTypes.damage:
        return const _JournalVisual(
          label: 'إتلاف',
          icon: Icons.report_gmailerrorred_rounded,
          color: AppColors.danger,
        );
      default:
        return const _JournalVisual(
          label: 'تسوية',
          icon: Icons.fact_check_rounded,
          color: AppColors.primaryDark,
        );
    }
  }
}

class _JournalVisual {
  const _JournalVisual({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;
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
