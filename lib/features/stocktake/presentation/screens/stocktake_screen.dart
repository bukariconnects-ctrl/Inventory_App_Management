import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_formatters.dart';
import '../../../inventory/presentation/providers/inventory_provider.dart';
import '../../../warehouses/data/models/warehouse_model.dart';
import '../../../warehouses/presentation/providers/warehouse_provider.dart';
import '../../data/models/stocktake_model.dart';
import '../providers/stocktake_provider.dart';

/// شاشة الجرد والتسوية: مطابقة الرصيد الدفتري مع الكمية الفعلية.
class StocktakeScreen extends StatefulWidget {
  const StocktakeScreen({super.key, this.initialWarehouseId});

  /// مخزن يُفتح محددًا مسبقًا (عند الوصول من بطاقة المخزن).
  final int? initialWarehouseId;

  @override
  State<StocktakeScreen> createState() => _StocktakeScreenState();
}

class _StocktakeScreenState extends State<StocktakeScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _actualQuantityController =
      TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  WarehouseProvider? _warehouseProvider;
  int? _warehouseId;

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
    _actualQuantityController.addListener(_onChanged);
  }

  @override
  void dispose() {
    _warehouseProvider?.removeListener(_syncDefaultWarehouse);
    _actualQuantityController
      ..removeListener(_onChanged)
      ..dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /// يحدد المخزن المطلوب: المخزن الممرر، أو المخزن النشط الوحيد.
  void _syncDefaultWarehouse() {
    if (!mounted || _warehouseId != null) {
      return;
    }
    final List<WarehouseModel> active = _warehouseProvider!.warehouses
        .where((WarehouseModel w) => w.isActive)
        .toList(growable: false);
    if (active.isEmpty) {
      return;
    }
    final int? target =
        widget.initialWarehouseId ??
        (active.length == 1 ? active.single.id : null);
    if (target == null || !active.any((WarehouseModel w) => w.id == target)) {
      return;
    }
    setState(() => _warehouseId = target);
    _loadHistory(target);
  }

  void _loadHistory(int warehouseId) {
    context.read<StocktakeProvider>().loadWarehouseStocktakes(warehouseId);
  }

  void _selectWarehouse(int? warehouseId) {
    setState(() => _warehouseId = warehouseId);
    if (warehouseId != null) {
      _loadHistory(warehouseId);
    }
  }

  int get _bookQuantity => _warehouseId == null
      ? 0
      : context.read<InventoryProvider>().quantityFor(_warehouseId!);

  int? get _actualQuantity =>
      int.tryParse(_actualQuantityController.text.trim());

  Future<void> _confirmAndSubmit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final int? warehouseId = _warehouseId;
    final int? actual = _actualQuantity;
    if (warehouseId == null || actual == null) {
      return;
    }

    final StocktakeProvider stocktakeProvider = context
        .read<StocktakeProvider>();
    final String warehouseName =
        _warehouseProvider!.warehouseById(warehouseId)?.name ?? 'المخزن';
    final int bookQuantity = _bookQuantity;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('تأكيد اعتماد الجرد'),
        content: Text(
          'سيتم تسوية رصيد "$warehouseName" من '
          '${AppFormatters.number(bookQuantity)} إلى '
          '${AppFormatters.number(actual)} كرتون '
          'وحفظ حركة تسوية بالفارق. هل تريد المتابعة؟',
          style: const TextStyle(height: 1.6, fontSize: 13),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('اعتماد التسوية'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    final StocktakeModel? result = await stocktakeProvider.performStocktake(
      warehouseId: warehouseId,
      actualQuantity: actual,
      notes: _notesController.text,
    );
    if (!mounted) {
      return;
    }
    if (result == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(stocktakeProvider.errorMessage ?? 'تعذر اعتماد الجرد.'),
        ),
      );
      return;
    }

    _actualQuantityController.clear();
    _notesController.clear();
    messenger.showSnackBar(
      const SnackBar(content: Text('تم اعتماد الجرد وتسوية الرصيد بنجاح.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final WarehouseProvider warehouseProvider = context
        .watch<WarehouseProvider>();
    final InventoryProvider inventoryProvider = context
        .watch<InventoryProvider>();
    final StocktakeProvider stocktakeProvider = context
        .watch<StocktakeProvider>();

    final List<WarehouseModel> activeWarehouses = warehouseProvider.warehouses
        .where((WarehouseModel w) => w.isActive)
        .toList(growable: false);
    final int bookQuantity = _warehouseId == null
        ? 0
        : inventoryProvider.quantityFor(_warehouseId!);
    final int? actual = _actualQuantity;
    final int? difference = actual == null ? null : actual - bookQuantity;

    return Scaffold(
      appBar: AppBar(title: const Text('الجرد والتسوية المخزنية')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: <Widget>[
            if (activeWarehouses.isEmpty)
              const _NoActiveWarehouse()
            else
              DropdownButtonFormField<int>(
                value: _warehouseId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'المخزن المراد جرده',
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
                onChanged: _selectWarehouse,
                validator: (int? value) =>
                    value == null ? 'اختر المخزن المراد جرده' : null,
              ),
            const SizedBox(height: 14),
            _BookBalanceCard(bookQuantity: bookQuantity),
            const SizedBox(height: 16),
            TextFormField(
              controller: _actualQuantityController,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'الكمية الفعلية الموجودة على الواقع',
                hintText: 'عدد الكراتين المعدودة فعليًا',
                suffixText: AppConstants.cartonUnit,
                prefixIcon: Icon(Icons.fact_check_outlined, size: 20),
              ),
              validator: (String? value) {
                final int? quantity = int.tryParse((value ?? '').trim());
                if (quantity == null || quantity < 0) {
                  return 'أدخل الكمية الفعلية المعدودة';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            _DifferenceCard(difference: difference, bookQuantity: bookQuantity),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: difference == 0
                    ? 'ملاحظات (اختياري)'
                    : 'ملاحظات وتبرير الفارق (إلزامي)',
                hintText: difference == 0
                    ? 'أي ملاحظة على عملية الجرد'
                    : 'اشرح سبب الفارق قبل اعتماد التسوية',
                alignLabelWithHint: true,
              ),
              validator: (String? value) {
                if (difference != 0 &&
                    (value == null || value.trim().isEmpty)) {
                  return 'تبرير الفارق مطلوب قبل اعتماد التسوية';
                }
                return null;
              },
            ),
            if (stocktakeProvider.errorMessage != null) ...<Widget>[
              const SizedBox(height: 12),
              _InlineError(message: stocktakeProvider.errorMessage!),
            ],
            const SizedBox(height: 24),
            Row(
              children: <Widget>[
                const Text(
                  'سجل عمليات الجرد السابقة',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                if (stocktakeProvider.isLoading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (stocktakeProvider.stocktakesHistory.isEmpty)
              const _EmptyHistory()
            else
              ...stocktakeProvider.stocktakesHistory.map(
                (StocktakeModel stocktake) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _StocktakeHistoryTile(stocktake: stocktake),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 14),
        child: ElevatedButton.icon(
          key: const Key('stocktake_submit_button'),
          onPressed: stocktakeProvider.isSubmitting ? null : _confirmAndSubmit,
          icon: stocktakeProvider.isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Icon(Icons.fact_check_rounded, size: 20),
          label: Text(
            stocktakeProvider.isSubmitting
                ? 'جارٍ الاعتماد...'
                : 'اعتماد وتسوية الجرد',
          ),
        ),
      ),
    );
  }
}

/// بطاقة الرصيد الدفتري الحالي.
class _BookBalanceCard extends StatelessWidget {
  const _BookBalanceCard({required this.bookQuantity});

  final int bookQuantity;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: <Color>[AppColors.primaryDark, AppColors.primary],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.menu_book_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'الرصيد الدفتري الحالي',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: <Widget>[
                    Text(
                      AppFormatters.number(bookQuantity),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                    const SizedBox(width: 5),
                    const Text(
                      'كرتون',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// بطاقة الفارق اللحظي بين الفعلي والدفتري.
class _DifferenceCard extends StatelessWidget {
  const _DifferenceCard({required this.difference, required this.bookQuantity});

  final int? difference;
  final int bookQuantity;

  @override
  Widget build(BuildContext context) {
    final int? value = difference;

    if (value == null) {
      return _buildCard(
        color: AppColors.textSecondary,
        icon: Icons.calculate_outlined,
        title: 'أدخل الكمية الفعلية',
        subtitle: 'سيُحسب الفارق تلقائيًا أثناء الكتابة.',
      );
    }
    if (value == 0) {
      return _buildCard(
        color: AppColors.success,
        icon: Icons.check_circle_outline_rounded,
        title: 'الرصيد الفعلي مطابق تمامًا للرصيد الدفتري',
        subtitle: 'لا يوجد فرق يستوجب التسوية.',
      );
    }
    if (value > 0) {
      return _buildCard(
        color: AppColors.primary,
        icon: Icons.trending_up_rounded,
        title: 'يوجد فائض في المخزن بمقدار +$value كرتون',
        subtitle:
            'الرصيد الفعلي أكبر من الدفتري '
            '(${AppFormatters.number(bookQuantity)} كرتون).',
      );
    }
    return _buildCard(
      color: AppColors.danger,
      icon: Icons.trending_down_rounded,
      title: 'يوجد عجز ونقص بمقدار $value كرتون',
      subtitle:
          'الرصيد الفعلي أقل من الدفتري '
          '(${AppFormatters.number(bookQuantity)} كرتون).',
    );
  }

  Widget _buildCard({
    required Color color,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 22, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: color.withValues(alpha: 0.9),
                    height: 1.5,
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

class _StocktakeHistoryTile extends StatelessWidget {
  const _StocktakeHistoryTile({required this.stocktake});

  final StocktakeModel stocktake;

  Color get _differenceColor {
    if (stocktake.difference > 0) {
      return AppColors.primary;
    }
    if (stocktake.difference < 0) {
      return AppColors.danger;
    }
    return AppColors.success;
  }

  @override
  Widget build(BuildContext context) {
    final String differenceLabel = stocktake.difference > 0
        ? '+${stocktake.difference}'
        : '${stocktake.difference}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(
                  Icons.event_note_rounded,
                  size: 15,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  AppFormatters.dateTime(stocktake.createdAt),
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _differenceColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'الفرق $differenceLabel',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: _differenceColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                _HistoryValue(
                  label: 'قبل الجرد',
                  value: '${stocktake.systemQuantity}',
                ),
                const SizedBox(width: 10),
                const Icon(
                  Icons.arrow_back_rounded,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 10),
                _HistoryValue(
                  label: 'الفعلي',
                  value: '${stocktake.actualQuantity}',
                ),
              ],
            ),
            if (stocktake.notes != null &&
                stocktake.notes!.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                stocktake.notes!,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HistoryValue extends StatelessWidget {
  const _HistoryValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: AppColors.primaryDark,
          ),
        ),
      ],
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: const Column(
        children: <Widget>[
          Icon(Icons.history_rounded, size: 30, color: AppColors.textSecondary),
          SizedBox(height: 8),
          Text(
            'لا توجد عمليات جرد سابقة لهذا المخزن',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 3),
          Text(
            'سيظهر هنا سجل كل جرد بعد اعتماده.',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
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
