import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/models/stakeholder_model.dart';
import '../providers/stakeholder_provider.dart';

/// نافذة إضافة أو تعديل جهة تعامل في دليل المناديب والموردين.
///
/// تعيد `true` عند الحفظ الناجح.
class AddEditStakeholderDialog extends StatefulWidget {
  const AddEditStakeholderDialog({
    super.key,
    this.stakeholder,
    this.initialType = StakeholderType.distributor,
  });

  /// الجهة المعدّلة، أو `null` عند الإضافة.
  final StakeholderModel? stakeholder;

  /// النوع الافتراضي عند الإضافة من تبويب معيّن.
  final StakeholderType initialType;

  static Future<bool?> show(
    BuildContext context, {
    StakeholderModel? stakeholder,
    StakeholderType initialType = StakeholderType.distributor,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => AddEditStakeholderDialog(
        stakeholder: stakeholder,
        initialType: initialType,
      ),
    );
  }

  @override
  State<AddEditStakeholderDialog> createState() =>
      _AddEditStakeholderDialogState();
}

class _AddEditStakeholderDialogState extends State<AddEditStakeholderDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _vehicleController;
  late StakeholderType _type;
  bool _isSaving = false;
  String? _errorMessage;

  bool get _isEditing => widget.stakeholder != null;

  @override
  void initState() {
    super.initState();
    final StakeholderModel? stakeholder = widget.stakeholder;
    _nameController = TextEditingController(text: stakeholder?.name ?? '');
    _phoneController = TextEditingController(text: stakeholder?.phone ?? '');
    _vehicleController = TextEditingController(
      text: stakeholder?.vehicleNumber ?? '',
    );
    _type = stakeholder?.type ?? widget.initialType;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _vehicleController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final StakeholderProvider provider = context.read<StakeholderProvider>();
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final StakeholderModel? existing = widget.stakeholder;
    final bool succeeded = existing == null
        ? await provider.addStakeholder(
            name: _nameController.text,
            type: _type,
            phone: _phoneController.text,
            vehicleNumber: _vehicleController.text,
          )
        : await provider.updateStakeholder(
            existing,
            name: _nameController.text,
            type: _type,
            phone: _phoneController.text,
            vehicleNumber: _vehicleController.text,
          );

    if (!mounted) {
      return;
    }
    if (succeeded) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _isSaving = false;
      _errorMessage = provider.errorMessage ?? 'تعذر حفظ البيانات.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        _isEditing ? 'تعديل جهة تعامل' : 'إضافة جهة تعامل',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextFormField(
                key: const Key('stakeholder_name_field'),
                controller: _nameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'الاسم *',
                  hintText: 'مثال: أحمد علي',
                  border: OutlineInputBorder(),
                ),
                validator: (String? value) =>
                    (value ?? '').trim().isEmpty ? 'الاسم مطلوب' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'رقم الهاتف (اختياري)',
                  hintText: '05xxxxxxxx',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _vehicleController,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'رقم اللوحة / المركبة (اختياري)',
                  hintText: 'مثال: 1234 أ ب ج',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'نوع الجهة',
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              SegmentedButton<StakeholderType>(
                segments: <ButtonSegment<StakeholderType>>[
                  for (final StakeholderType type in StakeholderType.values)
                    ButtonSegment<StakeholderType>(
                      value: type,
                      label: Text(
                        type.label,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                ],
                selected: <StakeholderType>{_type},
                showSelectedIcon: false,
                onSelectionChanged: (Set<StakeholderType> selection) {
                  setState(() => _type = selection.first);
                },
              ),
              if (_errorMessage != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.danger,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          key: const Key('save_stakeholder_button'),
          style: ElevatedButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Text(_isEditing ? 'حفظ التعديل' : 'حفظ'),
        ),
      ],
    );
  }
}
