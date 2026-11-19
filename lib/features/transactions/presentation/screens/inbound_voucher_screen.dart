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

/// سند استلام كراتين من المصنع إلى أحد المخازن.
class InboundVoucherScreen extends StatefulWidget {
  const InboundVoucherScreen({super.key});

  @override
  State<InboundVoucherScreen> createState() => _InboundVoucherScreenState();
}

class _InboundVoucherScreenState extends State<InboundVoucherScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  WarehouseProvider? _warehouseProvider;
  int? _warehouseId;
  int? _driverId;
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
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadVoucherNumber() async {
    final String number = await context
        .read<TransactionProvider>()
        .previewVoucherNumber(TransactionTypes.inbound);
    if (!mounted || number.isEmpty) {
      return;
    }
    setState(() => _voucherNumber = number);
  }

  /// يختار المخزن تلقائيًا إذا كان هناك مخزن نشط واحد فقط.
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

  /// يفتح حوار إضافة سائق مصنع ثم يختاره تلقائيًا في القائمة.
  Future<void> _addDriver() async {
    final bool? added = await AddEditStakeholderDialog.show(
      context,
      initialType: StakeholderType.driver,
    );
    if (!mounted || added != true) {
      return;
    }
    final StakeholderModel? created = context
        .read<StakeholderProvider>()
        .lastSavedStakeholder;
    if (created?.id != null) {
      setState(() => _driverId = created!.id);
    }
  }

  StakeholderModel? _selectedDriver(List<StakeholderModel> drivers) {
    for (final StakeholderModel driver in drivers) {
      if (driver.id == _driverId) {
        return driver;
      }
    }
    return null;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final int? warehouseId = _warehouseId;
    final StakeholderModel? driver = _selectedDriver(
      context.read<StakeholderProvider>().drivers,
    );
    if (warehouseId == null || driver == null) {
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
        .createInboundReceipt(
          warehouseId: warehouseId,
          quantity: int.parse(_quantityController.text.trim()),
          partyName: driver.name,
          notes: _notesController.text,
        );

    if (!mounted) {
      return;
    }
    if (transaction == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            transactionProvider.errorMessage ?? 'تعذر حفظ سند الاستلام.',
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
    final List<StakeholderModel> drivers = context
        .watch<StakeholderProvider>()
        .drivers;

    final List<WarehouseModel> activeWarehouses = warehouseProvider.warehouses
        .where((WarehouseModel w) => w.isActive)
        .toList(growable: false);
    final String itemName =
        inventoryProvider.item?.name ?? AppConstants.defaultItemName;
    final int bottleCount =
        inventoryProvider.item?.bottleCount ?? AppConstants.bottlesPerCarton;
    final int bottleVolume =
        inventoryProvider.item?.bottleVolumeMl ?? AppConstants.bottleVolumeMl;
    final int? selectedDriverId =
        drivers.any((StakeholderModel d) => d.id == _driverId)
        ? _driverId
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('سند استلام مياه من المصنع')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: <Widget>[
            _VoucherHeader(voucherNumber: _voucherNumber, isInbound: true),
            const SizedBox(height: 14),
            _ItemCard(
              itemName: itemName,
              bottleCount: bottleCount,
              bottleVolumeMl: bottleVolume,
            ),
            const SizedBox(height: 18),
            const _SectionLabel(text: 'بيانات الاستلام'),
            const SizedBox(height: 10),
            if (activeWarehouses.isEmpty)
              const _NoActiveWarehouse()
            else
              DropdownButtonFormField<int>(
                value: _warehouseId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'المخزن المستلم',
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
                    value == null ? 'اختر المخزن المستلم' : null,
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
                labelText: 'كمية الكراتين المستلمة',
                hintText: 'مثال: 500',
                suffixText: 'كرتون',
                prefixIcon: Icon(Icons.inventory_2_outlined, size: 20),
              ),
              validator: (String? value) {
                final int? quantity = int.tryParse((value ?? '').trim());
                if (quantity == null || quantity <= 0) {
                  return 'أدخل كمية صحيحة أكبر من صفر';
                }
                return null;
              },
            ),
            if ((_requestedQuantity ?? 0) > 0) ...<Widget>[
              const SizedBox(height: 8),
              _DualQuantityHint(
                cartons: _requestedQuantity!,
                bottlesPerCarton: bottleCount,
              ),
            ],
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: DropdownButtonFormField<StakeholderModel>(
                    key: const Key('inbound_driver_dropdown'),
                    value: selectedDriverId == null
                        ? null
                        : drivers.firstWhere(
                            (StakeholderModel d) => d.id == selectedDriverId,
                          ),
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'سائق المصنع / مسؤول التسليم',
                      prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
                    ),
                    hint: const Text('اختر السائق'),
                    items: drivers
                        .map(
                          (StakeholderModel driver) =>
                              DropdownMenuItem<StakeholderModel>(
                                value: driver,
                                child: Text(
                                  driver.phone == null
                                      ? driver.name
                                      : '${driver.name} — ${driver.phone}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                        )
                        .toList(growable: false),
                    onChanged: (StakeholderModel? value) =>
                        setState(() => _driverId = value?.id),
                    validator: (StakeholderModel? value) =>
                        value == null ? 'اختر سائق المصنع' : null,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  key: const Key('add_inbound_driver_button'),
                  tooltip: 'إضافة سائق جديد',
                  onPressed: _addDriver,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            if (drivers.isEmpty) ...<Widget>[
              const SizedBox(height: 6),
              const Text(
                'لا يوجد سائقون مسجلون — أضف سائقًا بزر (+) أو من دليل المناديب.',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
            const SizedBox(height: 14),
            TextFormField(
              controller: _notesController,
              maxLines: 3,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'ملاحظات الشحنة (اختياري)',
                hintText: 'رقم السيارة، حالة الشحنة، أي ملاحظة أخرى',
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
          key: const Key('inbound_submit_button'),
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
              : const Icon(Icons.move_to_inbox_rounded, size: 20),
          label: Text(
            transactionProvider.isSubmitting
                ? 'جارٍ الحفظ...'
                : 'تأكيد واستلام الشحنة',
          ),
        ),
      ),
    );
  }
}

/// سطر يوضح الكمية بالوحدتين (كرتون + عبوة).
class _DualQuantityHint extends StatelessWidget {
  const _DualQuantityHint({
    required this.cartons,
    required this.bottlesPerCarton,
  });

  final int cartons;
  final int bottlesPerCarton;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.mist,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.water_drop_outlined,
            size: 16,
            color: AppColors.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'الكمية بالوحدتين: '
              '${AppFormatters.formatQuantityWithBottles(cartons, bottlesPerCarton: bottlesPerCarton)}',
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

class _VoucherHeader extends StatelessWidget {
  const _VoucherHeader({required this.voucherNumber, required this.isInbound});

  final String voucherNumber;
  final bool isInbound;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isInbound ? AppColors.mist : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            isInbound ? Icons.south_west_rounded : Icons.north_east_rounded,
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

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.itemName,
    required this.bottleCount,
    required this.bottleVolumeMl,
  });

  final String itemName;
  final int bottleCount;
  final int bottleVolumeMl;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.mist,
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.water_drop_rounded,
              color: AppColors.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'الصنف المعتمد',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  itemName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$bottleCount قنينة × $bottleVolumeMl مل',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
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
