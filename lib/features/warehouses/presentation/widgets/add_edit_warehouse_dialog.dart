import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/models/warehouse_model.dart';
import '../providers/warehouse_provider.dart';

/// نافذة إضافة أو تعديل مخزن.
///
/// تعيد `true` عند الحفظ الناجح لتتمكن الشاشة من تحديث الأرصدة.
class AddEditWarehouseDialog extends StatefulWidget {
  const AddEditWarehouseDialog({super.key, this.warehouse});

  final WarehouseModel? warehouse;

  static Future<bool?> show(BuildContext context, {WarehouseModel? warehouse}) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) =>
          AddEditWarehouseDialog(warehouse: warehouse),
    );
  }

  @override
  State<AddEditWarehouseDialog> createState() => _AddEditWarehouseDialogState();
}

class _AddEditWarehouseDialogState extends State<AddEditWarehouseDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _locationController;
  late final TextEditingController _minAlertController;
  bool _isSubmitting = false;
  String? _dialogError;

  bool get _isEditing => widget.warehouse != null;

  @override
  void initState() {
    super.initState();
    final WarehouseModel? warehouse = widget.warehouse;
    _nameController = TextEditingController(text: warehouse?.name ?? '');
    _locationController = TextEditingController(
      text: warehouse?.location ?? '',
    );
    _minAlertController = TextEditingController(
      text: (warehouse?.minAlertLimit ?? AppConstants.defaultLowStockThreshold)
          .toString(),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _minAlertController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final WarehouseProvider provider = context.read<WarehouseProvider>();
    final int minAlertLimit =
        int.tryParse(_minAlertController.text.trim()) ??
        AppConstants.defaultLowStockThreshold;

    setState(() {
      _isSubmitting = true;
      _dialogError = null;
    });

    final bool succeeded = _isEditing
        ? await provider.updateWarehouse(
            widget.warehouse!,
            name: _nameController.text,
            location: _locationController.text,
            minAlertLimit: minAlertLimit,
          )
        : await provider.addWarehouse(
            name: _nameController.text,
            location: _locationController.text,
            minAlertLimit: minAlertLimit,
          );

    if (!mounted) {
      return;
    }
    if (succeeded) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _isSubmitting = false;
      _dialogError = provider.errorMessage ?? 'تعذر حفظ المخزن. حاول مرة أخرى.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.mist,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.warehouse_rounded,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _isEditing ? 'تعديل بيانات المخزن' : 'إضافة مخزن جديد',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextFormField(
                controller: _nameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'اسم المخزن',
                  hintText: 'مثال: مخزن الفرع الشمالي',
                  prefixIcon: Icon(Icons.badge_outlined, size: 20),
                ),
                validator: (String? value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'اسم المخزن مطلوب';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _locationController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'موقع المخزن',
                  hintText: 'مثال: المبنى الرئيسي',
                  prefixIcon: Icon(Icons.location_on_outlined, size: 20),
                ),
                validator: (String? value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'موقع المخزن مطلوب';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _minAlertController,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: const InputDecoration(
                  labelText: 'حد التنبيه الأدنى (كرتون)',
                  hintText: '100',
                  prefixIcon: Icon(
                    Icons.notifications_active_outlined,
                    size: 20,
                  ),
                ),
                validator: (String? value) {
                  final int? parsed = int.tryParse((value ?? '').trim());
                  if (parsed == null) {
                    return 'أدخل رقمًا صحيحًا لحد التنبيه';
                  }
                  if (parsed < 0) {
                    return 'حد التنبيه لا يمكن أن يكون سالبًا';
                  }
                  return null;
                },
              ),
              if (_dialogError != null) ...<Widget>[
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    const Icon(
                      Icons.error_outline_rounded,
                      color: AppColors.danger,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _dialogError!,
                        style: const TextStyle(
                          color: AppColors.danger,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      actions: <Widget>[
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        SizedBox(
          width: 120,
          child: ElevatedButton(
            onPressed: _isSubmitting ? null : _submit,
            child: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(_isEditing ? 'حفظ التعديل' : 'إضافة'),
          ),
        ),
      ],
    );
  }
}
