import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_formatters.dart';
import '../../../inventory/presentation/providers/inventory_provider.dart';
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
  final TextEditingController _partyController = TextEditingController();
  final TextEditingController _vehicleController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  WarehouseProvider? _warehouseProvider;
  int? _warehouseId;
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
  }

  @override
  void dispose() {
    _warehouseProvider?.removeListener(_syncDefaultWarehouse);
    _quantityController
      ..removeListener(_onQuantityChanged)
      ..dispose();
    _orderController.dispose();
    _partyController.dispose();
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

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final int? warehouseId = _warehouseId;
    final int? quantity = _requestedQuantity;
    if (warehouseId == null || quantity == null) {
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
          partyName: _partyController.text,
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
    final bool canSubmit =
        _warehouseId != null &&
        requested != null &&
        requested > 0 &&
        excess == 0 &&
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
              controller: _partyController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'اسم المندوب / جهة الصرف',
                hintText: 'مثال: المندوب أحمد السالم',
                prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
              ),
              validator: (String? value) {
                if (value == null || value.trim().isEmpty) {
                  return 'اسم المندوب أو جهة الصرف مطلوب';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _vehicleController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'رقم لوحة الشاحنة / السيارة (اختياري)',
                hintText: 'مثال: 1234-أ ب ج',
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

/// مؤشر الرصيد المتاح في المخزن المختار.
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
                        '${AppFormatters.number(available)} كرتون'
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
