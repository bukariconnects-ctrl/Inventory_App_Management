import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/database/database_helper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_formatters.dart';
import '../../../inventory/presentation/providers/inventory_provider.dart';
import '../../../warehouses/data/models/warehouse_model.dart';
import '../../../warehouses/presentation/providers/warehouse_provider.dart';
import '../../data/models/transaction_model.dart';
import '../providers/transaction_provider.dart';
import '../widgets/pending_request_dialog.dart';

/// أسباب التلف الشائعة المعروضة كشرائح اختيار.
const List<String> damageReasons = <String>[
  'كسر وتمزق كراتين',
  'تسريب عبوات',
  'سوء تخزين',
  'عيب تصنيعي',
  'أخرى',
];

/// سند إتلاف / هدر كراتين من أحد المخازن.
///
/// يُسجَّل المحضر بحالة `PENDING` باسم أمين المخزن المسجل في الإعدادات،
/// ولا يُخصم الرصيد إلا بعد اعتماده من شاشة الطلبات المعلقة.
class DamageVoucherScreen extends StatefulWidget {
  const DamageVoucherScreen({super.key});

  @override
  State<DamageVoucherScreen> createState() => _DamageVoucherScreenState();
}

class _DamageVoucherScreenState extends State<DamageVoucherScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _detailsController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  WarehouseProvider? _warehouseProvider;
  int? _warehouseId;
  String? _selectedReason;
  String? _reasonError;
  String _voucherNumber = '';
  String _storekeeperName = AppConstants.defaultStorekeeperName;

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
    _loadStorekeeperName();
  }

  @override
  void dispose() {
    _warehouseProvider?.removeListener(_syncDefaultWarehouse);
    _quantityController
      ..removeListener(_onQuantityChanged)
      ..dispose();
    _detailsController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadVoucherNumber() async {
    final String number = await context
        .read<TransactionProvider>()
        .previewVoucherNumber(TransactionTypes.damage);
    if (!mounted || number.isEmpty) {
      return;
    }
    setState(() => _voucherNumber = number);
  }

  Future<void> _loadStorekeeperName() async {
    final String? name = await DatabaseHelper.instance.getSetting(
      AppConstants.settingStorekeeperName,
      defaultValue: AppConstants.defaultStorekeeperName,
    );
    if (!mounted || name == null) {
      return;
    }
    setState(() => _storekeeperName = name);
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

  /// السبب النهائي المحفوظ: الشريحة المختارة + التفاصيل الإضافية.
  String get _composedReason {
    final String reason = _selectedReason?.trim() ?? '';
    final String details = _detailsController.text.trim();
    if (details.isEmpty) {
      return reason;
    }
    return reason.isEmpty ? details : '$reason — $details';
  }

  Future<void> _submit() async {
    if (_selectedReason == null) {
      setState(() => _reasonError = 'اختر سبب التلف');
      return;
    }
    if (_selectedReason == 'أخرى' && _detailsController.text.trim().isEmpty) {
      setState(() => _reasonError = 'اكتب تفاصيل سبب التلف');
      return;
    }
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
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    final TransactionModel? request = await transactionProvider
        .createInternalDamageRequest(
          warehouseId: warehouseId,
          quantity: quantity,
          reason: _composedReason,
          responsibleName: _storekeeperName,
          notes: _notesController.text,
        );

    if (!mounted) {
      return;
    }
    if (request == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            transactionProvider.errorMessage ?? 'تعذر رفع محضر الإتلاف.',
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
    final int bottlesPerCarton =
        inventoryProvider.item?.bottleCount ?? AppConstants.bottlesPerCarton;
    final bool canSubmit =
        _warehouseId != null &&
        requested != null &&
        requested > 0 &&
        !transactionProvider.isSubmitting;

    return Scaffold(
      appBar: AppBar(title: const Text('محضر إتلاف / هدر كراتين')),
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
                  labelText: 'المخزن',
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
                validator: (int? value) => value == null ? 'اختر المخزن' : null,
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
              decoration: const InputDecoration(
                labelText: 'الكمية التالفة',
                hintText: 'مثال: 25',
                suffixText: AppConstants.cartonUnit,
                prefixIcon: Icon(Icons.delete_outline_rounded, size: 20),
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
            if (excess > 0) ...<Widget>[
              const SizedBox(height: 8),
              _StockWarning(excess: excess, available: availableStock),
            ],
            const SizedBox(height: 18),
            const Text(
              'سبب التلف',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: damageReasons
                  .map((String reason) {
                    final bool selected = _selectedReason == reason;
                    return ChoiceChip(
                      label: Text(reason),
                      selected: selected,
                      onSelected: (_) => setState(() {
                        _selectedReason = reason;
                        _reasonError = null;
                      }),
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? AppColors.danger
                            : AppColors.textPrimary,
                      ),
                      selectedColor: AppColors.danger.withValues(alpha: 0.12),
                      backgroundColor: AppColors.surface,
                      side: BorderSide(
                        color: selected
                            ? AppColors.danger.withValues(alpha: 0.5)
                            : AppColors.outline,
                      ),
                      showCheckmark: false,
                    );
                  })
                  .toList(growable: false),
            ),
            if (_reasonError != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                _reasonError!,
                style: const TextStyle(fontSize: 11.5, color: AppColors.danger),
              ),
            ],
            const SizedBox(height: 14),
            TextFormField(
              controller: _detailsController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'تفاصيل إضافية عن سبب التلف (اختياري)',
                hintText: 'مثال: تلف أثناء التفريغ في المخزن',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            _StorekeeperCard(name: _storekeeperName),
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
          key: const Key('damage_submit_button'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.danger,
            foregroundColor: Colors.white,
          ),
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
              : const Icon(Icons.hourglass_top_rounded, size: 20),
          label: Text(
            transactionProvider.isSubmitting
                ? 'جارٍ رفع المحضر...'
                : 'رفع محضر إتلاف (قيد الاعتماد)',
          ),
        ),
      ),
    );
  }
}

/// بطاقة أمين المخزن المسؤول عن المحضر (تُقرأ من الإعدادات).
class _StorekeeperCard extends StatelessWidget {
  const _StorekeeperCard({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.badge_outlined, size: 20, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'المسؤول عن الإتلاف',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            key: const Key('damage_open_settings_button'),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'يُعدَّل اسم أمين المخزن من الإعدادات ← البيانات الرسمية.',
                  ),
                ),
              );
            },
            child: const Text('تعديل'),
          ),
        ],
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
              'يُسجَّل المحضر كطلب معلق دون خصم الرصيد، '
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
        color: AppColors.danger.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.report_gmailerrorred_rounded,
            size: 18,
            color: AppColors.danger,
          ),
          const SizedBox(width: 8),
          const Text(
            'رقم المحضر المتوقع',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const Spacer(),
          Text(
            voucherNumber.isEmpty ? '...' : voucherNumber,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.danger,
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
                  ? 'الرصيد الحالي في هذا المخزن: '
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
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: AppColors.warning,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'الكمية تتجاوز الرصيد الحالي بمقدار $excess كرتون '
              '(المتاح ${AppFormatters.number(available)} كرتون). '
              'سيُرفض الاعتماد إن لم يتوفر الرصيد عند المراجعة.',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF8A5A00),
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
