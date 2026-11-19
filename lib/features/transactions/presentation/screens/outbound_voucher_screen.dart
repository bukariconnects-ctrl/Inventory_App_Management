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
import '../widgets/transaction_success_dialog.dart';

/// سند صرف كراتين لمندوب/موزع مع فحص الرصيد اللحظي.
class OutboundVoucherScreen extends StatefulWidget {
  const OutboundVoucherScreen({super.key});

  @override
  State<OutboundVoucherScreen> createState() => _OutboundVoucherScreenState();
}

class _OutboundVoucherScreenState extends State<OutboundVoucherScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _orderController = TextEditingController();
  final TextEditingController _vehicleController = TextEditingController();
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
    _vehicleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadVoucherNumber() async {
    final String number = await context
        .read<TransactionProvider>()
        .previewVoucherNumber(TransactionTypes.outbound);
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

  /// إعادة البناء عند الكتابة لتحديث تحذير الرصيد وحالة زر الحفظ.
  void _onQuantityChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  int? get _requestedQuantity => int.tryParse(_quantityController.text.trim());

  /// يفتح حوار إضافة مندوب ثم يختاره ويملأ لوحة سيارته تلقائيًا.
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
    if (created == null) {
      return;
    }
    setState(() {
      _distributorId = created.id;
      _vehicleController.text = created.vehicleNumber ?? '';
    });
  }

  StakeholderModel? _selectedDistributor(List<StakeholderModel> distributors) {
    for (final StakeholderModel distributor in distributors) {
      if (distributor.id == _distributorId) {
        return distributor;
      }
    }
    return null;
  }

  void _onDistributorChanged(StakeholderModel? distributor) {
    setState(() {
      _distributorId = distributor?.id;
      _vehicleController.text = distributor?.vehicleNumber ?? '';
    });
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
    final WarehouseProvider warehouseProvider = context
        .read<WarehouseProvider>();
    final InventoryProvider inventoryProvider = context
        .read<InventoryProvider>();
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    final TransactionModel? transaction = await transactionProvider
        .createOutboundIssue(
          warehouseId: warehouseId,
          quantity: quantity,
          orderReference: _orderController.text,
          partyName: distributor.name,
          vehicleNumber: _vehicleController.text,
          notes: _notesController.text,
        );

    if (!mounted) {
      return;
    }
    if (transaction == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            transactionProvider.errorMessage ?? 'تعذر حفظ سند الصرف.',
          ),
        ),
      );
      return;
    }

    await TransactionSuccessDialog.show(
      context,
      transaction: transaction,
      warehouseName:
          warehouseProvider.warehouseById(warehouseId)?.name ?? 'المخزن',
      balanceAfter: inventoryProvider.quantityFor(warehouseId),
      warehouse: warehouseProvider.warehouseById(warehouseId),
      item: inventoryProvider.item,
    );
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
    final int excess = (requested != null && requested > availableStock)
        ? requested - availableStock
        : 0;
    final StakeholderModel? selectedDistributor = _selectedDistributor(
      distributors,
    );
    final bool canSubmit =
        _warehouseId != null &&
        requested != null &&
        requested > 0 &&
        excess == 0 &&
        selectedDistributor != null &&
        !transactionProvider.isSubmitting;

    return Scaffold(
      appBar: AppBar(title: const Text('سند صرف كراتين لمندوب / موزع')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: <Widget>[
            _VoucherHeader(voucherNumber: _voucherNumber),
            const SizedBox(height: 14),
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
                    key: const Key('outbound_distributor_dropdown'),
                    value: selectedDistributor,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'المندوب / جهة الصرف',
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
                    onChanged: _onDistributorChanged,
                    validator: (StakeholderModel? value) =>
                        value == null ? 'اختر المندوب' : null,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  key: const Key('add_outbound_distributor_button'),
                  tooltip: 'إضافة مندوب جديد',
                  onPressed: _addDistributor,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            if (distributors.isEmpty) ...<Widget>[
              const SizedBox(height: 6),
              const Text(
                'لا يوجد مناديب مسجلون — أضف مندوبًا بزر (+) أو من دليل المناديب.',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
            if (selectedDistributor?.vehicleNumber != null) ...<Widget>[
              const SizedBox(height: 8),
              _DistributorInfo(distributor: selectedDistributor!),
            ],
            const SizedBox(height: 14),
            TextFormField(
              controller: _quantityController,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'الكمية المطلوبة',
                hintText: 'مثال: 200',
                suffixText: AppConstants.cartonUnit,
                prefixIcon: const Icon(Icons.outbox_rounded, size: 20),
                errorMaxLines: 2,
                fillColor: excess > 0
                    ? AppColors.danger.withValues(alpha: 0.05)
                    : AppColors.surface,
              ),
              validator: (String? value) {
                final int? quantity = int.tryParse((value ?? '').trim());
                if (quantity == null || quantity <= 0) {
                  return 'أدخل كمية صحيحة أكبر من صفر';
                }
                if (quantity > availableStock) {
                  return 'الكمية المطلوبة تتجاوز الرصيد المتوفر في المخزن '
                      'بمقدار ${quantity - availableStock} كرتون';
                }
                return null;
              },
            ),
            if (requested != null && requested > 0) ...<Widget>[
              const SizedBox(height: 8),
              _DualQuantityHint(
                cartons: requested,
                bottlesPerCarton:
                    inventoryProvider.item?.bottleCount ??
                    AppConstants.bottlesPerCarton,
              ),
            ],
            if (excess > 0) ...<Widget>[
              const SizedBox(height: 8),
              _StockWarning(excess: excess, available: availableStock),
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
              controller: _vehicleController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'رقم لوحة الشاحنة / السيارة',
                hintText: 'يُملأ تلقائيًا من بيانات المندوب',
                prefixIcon: Icon(Icons.local_shipping_outlined, size: 20),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _notesController,
              maxLines: 3,
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
          key: const Key('outbound_submit_button'),
          onPressed: canSubmit ? _submit : null,
          icon: transactionProvider.isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Icon(Icons.local_shipping_rounded, size: 20),
          label: Text(
            transactionProvider.isSubmitting
                ? 'جارٍ الحفظ...'
                : 'تأكيد وصرف الكمية',
          ),
        ),
      ),
    );
  }
}

/// بطاقة معلومات المندوب المختار (الهاتف ورقم المركبة).
class _DistributorInfo extends StatelessWidget {
  const _DistributorInfo({required this.distributor});

  final StakeholderModel distributor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.local_shipping_outlined,
            size: 16,
            color: AppColors.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'رقم المركبة: ${distributor.vehicleNumber}',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// سطر الكمية بالوحدتين (كرتون + عبوة).
class _DualQuantityHint extends StatelessWidget {
  const _DualQuantityHint({
    required this.cartons,
    required this.bottlesPerCarton,
  });

  final int cartons;
  final int bottlesPerCarton;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Text(
        'ما يعادل '
        '${AppFormatters.formatQuantityWithBottles(cartons, bottlesPerCarton: bottlesPerCarton)}',
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
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
            Icons.north_east_rounded,
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

/// مؤشر الرصيد المتاح في المخزن المختار بالوحدتين.
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

class _StockWarning extends StatelessWidget {
  const _StockWarning({required this.excess, required this.available});

  final int excess;
  final int available;

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: AppColors.danger,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'الكمية المطلوبة تتجاوز الرصيد المتوفر في المخزن '
              'بمقدار $excess كرتون (المتاح ${AppFormatters.number(available)} كرتون).',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.danger,
                height: 1.5,
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
