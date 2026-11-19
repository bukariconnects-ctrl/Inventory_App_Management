import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_formatters.dart';
import '../../../inventory/presentation/providers/inventory_provider.dart';
import '../../../warehouses/presentation/providers/warehouse_provider.dart';
import '../../data/models/transaction_model.dart';
import '../providers/transaction_provider.dart';

/// شاشة الطلبات المعلقة: بدل تالف للمناديب والإتلاف المخزني الداخلي.
///
/// لا يُخصم أي رصيد حتى يضغط المستخدم «اعتماد وتأكيد الخصم».
class PendingApprovalsScreen extends StatefulWidget {
  const PendingApprovalsScreen({super.key});

  @override
  State<PendingApprovalsScreen> createState() => _PendingApprovalsScreenState();
}

class _PendingApprovalsScreenState extends State<PendingApprovalsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<TransactionProvider>().loadPendingApprovals();
      }
    });
  }

  Future<void> _refresh() async {
    final TransactionProvider provider = context.read<TransactionProvider>();
    final InventoryProvider inventory = context.read<InventoryProvider>();
    await provider.loadPendingApprovals(showLoader: false);
    await inventory.refresh();
  }

  Future<void> _openDetails(
    TransactionModel transaction,
    String warehouseName,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    final String? result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => _ApprovalDetailsDialog(
        transaction: transaction,
        warehouseName: warehouseName,
      ),
    );

    if (!mounted || result == null) {
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(result)));
    if (mounted) {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final TransactionProvider provider = context.watch<TransactionProvider>();
    final WarehouseProvider warehouses = context.watch<WarehouseProvider>();
    final List<TransactionModel> pending = provider.pendingTransactions;

    return Scaffold(
      appBar: AppBar(
        title: const Text('الطلبات المعلقة بانتظار الاعتماد'),
        actions: <Widget>[
          IconButton(
            tooltip: 'تحديث القائمة',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _buildBody(provider, warehouses, pending),
    );
  }

  Widget _buildBody(
    TransactionProvider provider,
    WarehouseProvider warehouses,
    List<TransactionModel> pending,
  ) {
    if (provider.isLoadingPending && !provider.hasLoadedPending) {
      return const Center(child: CircularProgressIndicator());
    }

    if (pending.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
          children: <Widget>[
            const Icon(
              Icons.verified_rounded,
              size: 52,
              color: AppColors.success,
            ),
            const SizedBox(height: 14),
            const Text(
              'لا توجد طلبات معلقة',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              'كل سندات بدل التالف ومحاضر الإتلاف تمت معالجتها.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.6,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        physics: const AlwaysScrollableScrollPhysics(),
        children: <Widget>[
          _SummaryBanner(count: pending.length),
          const SizedBox(height: 14),
          ...pending.map((TransactionModel transaction) {
            final String warehouseName =
                warehouses.warehouseById(transaction.warehouseId)?.name ??
                'مخزن غير معروف';
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _PendingCard(
                transaction: transaction,
                warehouseName: warehouseName,
                onTap: () => _openDetails(transaction, warehouseName),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _SummaryBanner extends StatelessWidget {
  const _SummaryBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.32)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.hourglass_top_rounded,
              color: AppColors.warning,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '$count ${count == 1 ? 'طلب معلق' : 'طلبات معلقة'}',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF8A5A00),
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'الرصيد لم يُخصم بعد — الاعتماد يخصم الكمية فورًا.',
                  style: TextStyle(fontSize: 11.5, color: Color(0xFF8A5A00)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingCard extends StatelessWidget {
  const _PendingCard({
    required this.transaction,
    required this.warehouseName,
    required this.onTap,
  });

  final TransactionModel transaction;
  final String warehouseName;
  final VoidCallback onTap;

  String get _typeLabel =>
      transaction.isMarketReplacement ? 'بدل تالف لمندوب' : 'إتلاف مخزني داخلي';

  IconData get _icon => transaction.isMarketReplacement
      ? Icons.swap_horiz_rounded
      : Icons.report_gmailerrorred_rounded;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.mist,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(_icon, color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          _typeLabel,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          transaction.voucherNumber,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const _PendingBadge(),
                ],
              ),
              const SizedBox(height: 12),
              _InfoLine(
                icon: Icons.person_outline_rounded,
                label: transaction.partyName ?? 'غير محدد',
              ),
              const SizedBox(height: 6),
              _InfoLine(icon: Icons.warehouse_rounded, label: warehouseName),
              const SizedBox(height: 6),
              _InfoLine(
                icon: Icons.inventory_2_outlined,
                label: AppFormatters.formatQuantityWithBottles(
                  transaction.quantity.abs(),
                ),
              ),
              if ((transaction.reason ?? '').trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                _InfoLine(
                  icon: Icons.notes_rounded,
                  label: transaction.reason!,
                ),
              ],
              const SizedBox(height: 10),
              const Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  Text(
                    'اضغط لاعتماد أو رفض الطلب',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(
                    Icons.chevron_left_rounded,
                    size: 18,
                    color: AppColors.textSecondary,
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

class _PendingBadge extends StatelessWidget {
  const _PendingBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Text(
        'بانتظار الاعتماد',
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          color: Color(0xFF8A5A00),
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

/// تفاصيل الطلب مع زرّي الاعتماد والرفض.
class _ApprovalDetailsDialog extends StatefulWidget {
  const _ApprovalDetailsDialog({
    required this.transaction,
    required this.warehouseName,
  });

  final TransactionModel transaction;
  final String warehouseName;

  @override
  State<_ApprovalDetailsDialog> createState() => _ApprovalDetailsDialogState();
}

class _ApprovalDetailsDialogState extends State<_ApprovalDetailsDialog> {
  bool _isBusy = false;
  String? _errorMessage;

  String get _typeLabel => widget.transaction.isMarketReplacement
      ? 'طلب صرف بدل تالف لمندوب'
      : 'محضر إتلاف مخزني داخلي';

  Future<void> _approve() async {
    final TransactionProvider provider = context.read<TransactionProvider>();
    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });

    final bool succeeded = await provider.approvePending(widget.transaction);
    if (!mounted) {
      return;
    }
    if (succeeded) {
      Navigator.of(context).pop(
        'تم اعتماد السند ${widget.transaction.voucherNumber} وخصم الكمية من الرصيد.',
      );
      return;
    }
    setState(() {
      _isBusy = false;
      _errorMessage = provider.errorMessage ?? 'تعذر اعتماد الطلب.';
    });
  }

  Future<void> _reject() async {
    final String? reason = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => const _RejectionReasonDialog(),
    );
    if (!mounted || reason == null) {
      return;
    }

    final TransactionProvider provider = context.read<TransactionProvider>();
    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });

    final bool succeeded = await provider.rejectPending(
      widget.transaction,
      reason,
    );
    if (!mounted) {
      return;
    }
    if (succeeded) {
      Navigator.of(context).pop(
        'تم رفض السند ${widget.transaction.voucherNumber} دون خصم أي كمية.',
      );
      return;
    }
    setState(() {
      _isBusy = false;
      _errorMessage = provider.errorMessage ?? 'تعذر رفض الطلب.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final TransactionModel transaction = widget.transaction;
    final int bottlesPerCarton =
        context.watch<InventoryProvider>().item?.bottleCount ??
        AppConstants.bottlesPerCarton;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Text(
        _typeLabel,
        style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                children: <Widget>[
                  _DetailRow(
                    label: 'رقم السند',
                    value: transaction.voucherNumber,
                  ),
                  _DetailRow(label: 'المخزن', value: widget.warehouseName),
                  _DetailRow(
                    label: transaction.isMarketReplacement
                        ? 'المندوب'
                        : 'المسؤول',
                    value: transaction.partyName ?? 'غير محدد',
                  ),
                  if (transaction.orderReference != null)
                    _DetailRow(
                      label: 'أمر الصرف',
                      value: transaction.orderReference!,
                    ),
                  _DetailRow(
                    label: 'الكمية',
                    value: AppFormatters.formatQuantityWithBottles(
                      transaction.quantity.abs(),
                      bottlesPerCarton: bottlesPerCarton,
                    ),
                  ),
                  _DetailRow(
                    label: 'تاريخ الطلب',
                    value: AppFormatters.dateTime(transaction.createdAt),
                  ),
                  if ((transaction.reason ?? '').trim().isNotEmpty)
                    _DetailRow(label: 'السبب', value: transaction.reason!),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'الاعتماد يخصم الكمية من الرصيد فورًا. الرفض يحفظ سبب الرفض '
              'ويترك الرصيد كما هو.',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
                height: 1.6,
              ),
            ),
            if (_errorMessage != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                _errorMessage!,
                style: const TextStyle(fontSize: 11.5, color: AppColors.danger),
              ),
            ],
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      actions: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('reject_pending_button'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: BorderSide(
                    color: AppColors.danger.withValues(alpha: 0.5),
                  ),
                  minimumSize: const Size(0, 46),
                ),
                onPressed: _isBusy ? null : _reject,
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('رفض الطلب'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                key: const Key('approve_pending_button'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 46),
                ),
                onPressed: _isBusy ? null : _approve,
                icon: _isBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Icon(Icons.check_rounded, size: 18),
                label: const Text('اعتماد وتأكيد الخصم'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: _isBusy ? null : () => Navigator.of(context).pop(),
          child: const Text('إغلاق'),
        ),
      ],
    );
  }
}

/// نافذة إدخال سبب الرفض (إلزامي).
class _RejectionReasonDialog extends StatefulWidget {
  const _RejectionReasonDialog();

  @override
  State<_RejectionReasonDialog> createState() => _RejectionReasonDialogState();
}

class _RejectionReasonDialogState extends State<_RejectionReasonDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() {
    final String reason = _controller.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'سبب الرفض مطلوب');
      return;
    }
    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text(
        'رفض الطلب',
        style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text(
            'اكتب سبب الرفض ليُحفظ مع السند.',
            style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('rejection_reason_field'),
            controller: _controller,
            maxLines: 3,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'سبب الرفض *',
              hintText: 'مثال: الكمية غير مطابقة للمرتجع من السوق',
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          key: const Key('confirm_rejection_button'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.danger,
            foregroundColor: Colors.white,
          ),
          onPressed: _confirm,
          child: const Text('تأكيد الرفض'),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
