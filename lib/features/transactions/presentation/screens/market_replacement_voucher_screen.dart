import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_formatters.dart';
import '../../../inventory/presentation/providers/inventory_provider.dart';
import '../../../stakeholders/data/models/stakeholder_model.dart';
import '../../../stakeholders/presentation/providers/stakeholder_provider.dart';
import '../../../stakeholders/presentation/widgets/add_edit_stakeholder_dialog.dart';
import '../../../warehouses/data/models/warehouse_model.dart';
import '../../../warehouses/presentation/providers/warehouse_provider.dart';
import '../../data/models/transaction_model.dart';
import '../providers/transaction_provider.dart';
import '../widgets/pending_request_dialog.dart';

/// سند صرف بدل تالف لمندوب عن كراتين مرتجعة من السوق.
///
/// يُسجَّل السند بحالة `PENDING` ولا يُخصم من الرصيد إلا بعد اعتماده.
class MarketReplacementVoucherScreen extends StatefulWidget {
  const MarketReplacementVoucherScreen({super.key});

  @override
  State<MarketReplacementVoucherScreen> createState() =>
      _MarketReplacementVoucherScreenState();
}

class _MarketReplacementVoucherScreenState
    extends State<MarketReplacementVoucherScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _orderController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  WarehouseProvider? _warehouseProvider;
  int? _warehouseId;
  int? _distributorId;
  String _voucherNumber = '';

  @override
  void initState() {
    super.initState();
    _warehouseProvider = context.read<WarehouseProvider>();
    _warehouseProvider!.addListener(_syncDefaultWarehouse);
    if (_warehouseProvider!.warehouses.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _warehouseProvider!.loadWarehouses();
        }
      });
    }
    _syncDefaultWarehouse();
    _quantityController.addListener(_onQuantityChanged);
    _loadVoucherNumber();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<StakeholderProvider>().loadStakeholders();
      }
    });
  }

  @override
  void dispose() {
    _warehouseProvider?.removeListener(_syncDefaultWarehouse);
    _quantityController
      ..removeListener(_onQuantityChanged)
      ..dispose();
    _orderController.dispose();
    _reasonController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadVoucherNumber() async {
    final String number = await context
        .read<TransactionProvider>()
        .previewVoucherNumber(TransactionTypes.marketReplacement);
    if (!mounted || number.isEmpty) {
      return;
    }
    setState(() => _voucherNumber = number);
  }

  void _syncDefaultWarehouse() {
    if (!mounted) {
      return;
    }
    final List<WarehouseModel> active = _warehouseProvider!.warehouses
        .where((WarehouseModel w) => w.isActive)
        .toList(growable: false);
    if (_warehouseId == null && active.length == 1) {
      setState(() => _warehouseId = active.single.id);
    }
  }

  void _onQuantityChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  int? get _requestedQuantity => int.tryParse(_quantityController.text.trim());

  Future<void> _addDistributor() async {
    final bool? added = await AddEditStakeholderDialog.show(
      context,
      initialType: StakeholderType.distributor,
    );
    if (!mounted || added != true) {
      return;
    }
    final StakeholderModel? created = context
        .read<StakeholderProvider>()
        .lastSavedStakeholder;
    if (created?.id != null) {
      setState(() => _distributorId = created!.id);
    }
  }

  StakeholderModel? _selectedDistributor(List<StakeholderModel> distributors) {
    for (final StakeholderModel distributor in distributors) {
      if (distributor.id == _distributorId) {
        return distributor;
      }
    }
    return null;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final int? warehouseId = _warehouseId;
    final int? quantity = _requestedQuantity;
    final StakeholderModel? distributor = _selectedDistributor(
      context.read<StakeholderProvider>().distributors,
    );
    if (warehouseId == null || quantity == null || distributor == null) {
      return;
    }

    final TransactionProvider transactionProvider = context
        .read<TransactionProvider>();
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    final TransactionModel? request = await transactionProvider
        .createMarketReplacementRequest(
          warehouseId: warehouseId,
          quantity: quantity,
          partyName: distributor.name,
          orderReference: _orderController.text,
          reason: _reasonController.text,
          vehicleNumber: distributor.vehicleNumber,
          notes: _notesController.text,
        );

    if (!mounted) {
      return;
    }
    if (request == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            transactionProvider.errorMessage ?? 'تعذر رفع طلب بدل التالف.',
          ),
        ),
      );
      return;
    }

    await PendingRequestDialog.show(context, transaction: request);
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final WarehouseProvider warehouseProvider = context
        .watch<WarehouseProvider>();
    final InventoryProvider inventoryProvider = context
        .watch<InventoryProvider>();
    final TransactionProvider transactionProvider = context
        .watch<TransactionProvider>();
    final List<StakeholderModel> distributors = context
        .watch<StakeholderProvider>()
        .distributors;

    final List<WarehouseModel> activeWarehouses = warehouseProvider.warehouses
        .where((WarehouseModel w) => w.isActive)
        .toList(growable: false);
    final int availableStock = _warehouseId == null
        ? 0
        : inventoryProvider.quantityFor(_warehouseId!);
    final int? requested = _requestedQuantity;
    final StakeholderModel? selectedDistributor = _selectedDistributor(
      distributors,
    );
    final int bottlesPerCarton =
        inventoryProvider.item?.bottleCount ?? AppConstants.bottlesPerCarton;

    return Scaffold(
      appBar: AppBar(title: const Text('صرف بدل تالف لمندوب')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: <Widget>[
            _VoucherHeader(voucherNumber: _voucherNumber),
            const SizedBox(height: 12),
            const _PendingNotice(),
            const SizedBox(height: 16),
            if (activeWarehouses.isEmpty)
              const _NoActiveWarehouse()
            else
              DropdownButtonFormField<int>(
                value: _warehouseId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'المخزن المصروف منه',
                  prefixIcon: Icon(Icons.warehouse_rounded, size: 20),
                ),
                hint: const Text('اختر المخزن'),
                items: activeWarehouses
                    .map(
                      (WarehouseModel warehouse) => DropdownMenuItem<int>(
                        value: warehouse.id,
                        child: Text(
                          warehouse.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (int? value) => setState(() => _warehouseId = value),
                validator: (int? value) =>
                    value == null ? 'اختر المخزن المصروف منه' : null,
              ),
            const SizedBox(height: 10),
            _AvailableStockBadge(
              available: availableStock,
              hasWarehouse: _warehouseId != null,
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: DropdownButtonFormField<StakeholderModel>(
                    key: const Key('replacement_distributor_dropdown'),
                    value: selectedDistributor,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'المندوب المستفيد',
                      prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
                    ),
                    hint: const Text('اختر المندوب'),
                    items: distributors
                        .map(
                          (StakeholderModel distributor) =>
                              DropdownMenuItem<StakeholderModel>(
                                value: distributor,
                                child: Text(
                                  distributor.phone == null
                                      ? distributor.name
                                      : '${distributor.name} — '
                                            '${distributor.phone}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                        )
                        .toList(growable: false),
                    onChanged: (StakeholderModel? value) =>
                        setState(() => _distributorId = value?.id),
                    validator: (StakeholderModel? value) =>
                        value == null ? 'اختر المندوب المستفيد' : null,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  key: const Key('add_replacement_distributor_button'),
                  tooltip: 'إضافة مندوب جديد',
                  onPressed: _addDistributor,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            if (distributors.isEmpty) ...<Widget>[
              const SizedBox(height: 6),
              const Text(
                'لا يوجد مناديب مسجلون — أضف مندوبًا بزر (+) أولًا.',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
            const SizedBox(height: 14),
            TextFormField(
              controller: _orderController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'رقم أمر الصرف الإداري',
                hintText: 'مثال: ORD-2026-0045',
                prefixIcon: Icon(Icons.receipt_long_outlined, size: 20),
              ),
              validator: (String? value) {
                if (value == null || value.trim().isEmpty) {
                  return 'رقم أمر الصرف الإداري مطلوب';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _quantityController,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'كمية بدل التالف',
                hintText: 'مثال: 15',
                suffixText: AppConstants.cartonUnit,
                prefixIcon: Icon(Icons.swap_horiz_rounded, size: 20),
              ),
              validator: (String? value) {
                final int? quantity = int.tryParse((value ?? '').trim());
                if (quantity == null || quantity <= 0) {
                  return 'أدخل كمية صحيحة أكبر من صفر';
                }
                return null;
              },
            ),
            if ((requested ?? 0) > 0) ...<Widget>[
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  'ما يعادل '
                  '${AppFormatters.formatQuantityWithBottles(requested!, bottlesPerCarton: bottlesPerCarton)}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            TextFormField(
              controller: _reasonController,
              maxLines: 3,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'مبرر التلف المرتجع من السوق',
                hintText: 'مثال: عبوات مسربة أعادها المندوب من السوق',
                alignLabelWithHint: true,
              ),
              validator: (String? value) {
                if (value == null || value.trim().isEmpty) {
                  return 'مبرر بدل التالف مطلوب';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _notesController,
              maxLines: 2,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'ملاحظات (اختياري)',
                alignLabelWithHint: true,
              ),
            ),
            if (transactionProvider.errorMessage != null) ...<Widget>[
              const SizedBox(height: 14),
              _InlineError(message: transactionProvider.errorMessage!),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 14),
        child: ElevatedButton.icon(
          key: const Key('replacement_submit_button'),
          onPressed: transactionProvider.isSubmitting ? null : _submit,
          icon: transactionProvider.isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Icon(Icons.hourglass_top_rounded, size: 20),
          label: Text(
            transactionProvider.isSubmitting
                ? 'جارٍ رفع الطلب...'
                : 'رفع طلب صرف بدل تالف (قيد الاعتماد)',
          ),
        ),
      ),
    );
  }
}

class _PendingNotice extends StatelessWidget {
  const _PendingNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline_rounded, size: 18, color: AppColors.warning),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'يُسجَّل الطلب كمسودة معلقة دون خصم الرصيد، '
              'ويُخصم من المخزن عند اعتماده من شاشة الطلبات المعلقة.',
              style: TextStyle(
                fontSize: 11.5,
                color: Color(0xFF8A5A00),
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VoucherHeader extends StatelessWidget {
  const _VoucherHeader({required this.voucherNumber});

  final String voucherNumber;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.mist,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.swap_horiz_rounded,
            size: 18,
            color: AppColors.primary,
          ),
          const SizedBox(width: 8),
          const Text(
            'رقم السند المتوقع',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const Spacer(),
          Text(
            voucherNumber.isEmpty ? '...' : voucherNumber,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.primaryDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _AvailableStockBadge extends StatelessWidget {
  const _AvailableStockBadge({
    required this.available,
    required this.hasWarehouse,
  });

  final int available;
  final bool hasWarehouse;

  @override
  Widget build(BuildContext context) {
    final bool isLow = available <= 0;
    final Color color = !hasWarehouse
        ? AppColors.textSecondary
        : (isLow ? AppColors.danger : AppColors.success);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.inventory_2_outlined, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hasWarehouse
                  ? 'الرصيد المتاح في هذا المخزن: '
                        '${AppFormatters.formatQuantityWithBottles(available)}'
                  : 'اختر المخزن لعرض الرصيد المتاح',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoActiveWarehouse extends StatelessWidget {
  const _NoActiveWarehouse();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: const Row(
        children: <Widget>[
          Icon(Icons.info_outline_rounded, size: 18, color: AppColors.warning),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'لا يوجد مخزن نشط. فعّل أو أضف مخزنًا من تبويب المخازن أولًا.',
              style: TextStyle(fontSize: 12, color: Color(0xFF8A5A00)),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

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
              style: const TextStyle(fontSize: 12, color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }
}
