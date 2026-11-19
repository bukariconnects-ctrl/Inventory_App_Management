import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/database/database_helper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_formatters.dart';
import '../../../inventory/presentation/providers/inventory_provider.dart';
import '../../../reports/presentation/providers/reports_provider.dart';
import '../../../stakeholders/presentation/screens/stakeholders_screen.dart';
import '../../../warehouses/presentation/providers/warehouse_provider.dart';
import '../../data/models/backup_models.dart';
import '../providers/backup_provider.dart';

/// الإعدادات والنسخ الاحتياطي: معلومات النظام، التصدير، والاستعادة.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _storekeeperController = TextEditingController();
  bool _isSavingStorekeeper = false;

  @override
  void initState() {
    super.initState();
    _loadStorekeeperName();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<BackupProvider>().loadStats();
      }
    });
  }

  @override
  void dispose() {
    _storekeeperController.dispose();
    super.dispose();
  }

  /// يقرأ اسم أمين المخزن من جدول الإعدادات.
  Future<void> _loadStorekeeperName() async {
    final String? name = await DatabaseHelper.instance.getSetting(
      AppConstants.settingStorekeeperName,
      defaultValue: AppConstants.defaultStorekeeperName,
    );
    if (!mounted) {
      return;
    }
    _storekeeperController.text = name ?? AppConstants.defaultStorekeeperName;
  }

  /// يحفظ اسم أمين المخزن المسؤول في جدول الإعدادات.
  Future<void> _saveStorekeeperName() async {
    final String value = _storekeeperController.text.trim();
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    if (value.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('اسم أمين المخزن مطلوب.'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }
    setState(() => _isSavingStorekeeper = true);
    try {
      await DatabaseHelper.instance.setSetting(
        AppConstants.settingStorekeeperName,
        value,
      );
      messenger.showSnackBar(
        const SnackBar(
          content: Text('تم حفظ اسم أمين المخزن بنجاح.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (error) {
      debugPrint('SettingsScreen._saveStorekeeperName: $error');
      messenger.showSnackBar(
        const SnackBar(
          content: Text('تعذر حفظ الاسم. حاول مرة أخرى.'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSavingStorekeeper = false);
      }
    }
  }

  /// يعيد تحميل كل المزوّدات بعد الاستعادة دون إعادة تشغيل التطبيق.
  Future<void> _reloadAllProviders() async {
    final WarehouseProvider warehouseProvider = context
        .read<WarehouseProvider>();
    final InventoryProvider inventoryProvider = context
        .read<InventoryProvider>();
    final ReportsProvider reportsProvider = context.read<ReportsProvider>();
    final BackupProvider backupProvider = context.read<BackupProvider>();

    await warehouseProvider.loadWarehouses(showLoader: false);
    await inventoryProvider.loadInventoryStatus(showLoader: false);
    await reportsProvider.loadReportsData(showLoader: false);
    await backupProvider.loadStats();
  }

  Future<void> _exportBackup() async {
    final BackupProvider provider = context.read<BackupProvider>();
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final BackupFile? backup = await provider.exportBackup();
    if (!mounted) {
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          backup != null
              ? provider.successMessage ?? 'تم إنشاء النسخة الاحتياطية.'
              : provider.errorMessage ?? 'تعذر إنشاء النسخة الاحتياطية.',
        ),
        backgroundColor: backup != null ? AppColors.success : AppColors.danger,
      ),
    );
  }

  Future<bool> _confirmRestore(BackupValidationResult validation) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: <Widget>[
            Icon(Icons.warning_amber_rounded, color: AppColors.danger),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'تأكيد استعادة البيانات',
                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'سيتم استبدال جميع البيانات الحالية (الحركات، المخازن، الأرصدة) '
              'ببيانات النسخة المختارة. لا يمكن التراجع بعد التأكيد.',
              style: TextStyle(fontSize: 12.5, height: 1.6),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                children: <Widget>[
                  _DetailLine(label: 'الملف', value: validation.fileName),
                  _DetailLine(
                    label: 'الحجم',
                    value: '${validation.sizeKb.round()} ك.ب',
                  ),
                  _DetailLine(
                    label: 'الحركات',
                    value: AppFormatters.number(validation.transactionCount),
                  ),
                  _DetailLine(
                    label: 'المخازن',
                    value: AppFormatters.number(validation.warehouseCount),
                  ),
                  _DetailLine(
                    label: 'سجلات الجرد',
                    value: AppFormatters.number(validation.stocktakeCount),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            key: const Key('confirm_restore_button'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 44),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('استبدال البيانات'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _restoreBackup() async {
    final BackupProvider provider = context.read<BackupProvider>();
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    final bool restored = await provider.pickAndRestoreBackup(
      confirmRestore: _confirmRestore,
      onRestoreSuccess: _reloadAllProviders,
    );

    if (!mounted) {
      return;
    }
    if (restored) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(provider.successMessage ?? 'تمت الاستعادة بنجاح.'),
          backgroundColor: AppColors.success,
        ),
      );
    } else if (provider.errorMessage != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(provider.errorMessage!),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final BackupProvider provider = context.watch<BackupProvider>();
    final DatabaseStats? stats = provider.stats;
    final bool busy = provider.isExporting || provider.isRestoring;

    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات والنسخ الاحتياطي')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: <Widget>[
          _SectionCard(
            title: 'بيانات أمين المخزن المسؤول',
            icon: Icons.badge_outlined,
            color: AppColors.cyan,
            children: <Widget>[
              const Text(
                'يُستخدم هذا الاسم في توثيق حركات المخزن وسندات التسليم '
                'والتقارير المطبوعة.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textSecondary,
                  height: 1.7,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('storekeeper_name_field'),
                controller: _storekeeperController,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'اسم أمين المخزن',
                  hintText: 'مثال: أحمد علي - مسؤول المخزن',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  key: const Key('save_storekeeper_button'),
                  onPressed: _isSavingStorekeeper ? null : _saveStorekeeperName,
                  icon: const Icon(Icons.save_rounded, size: 20),
                  label: Text(
                    _isSavingStorekeeper ? 'جارٍ الحفظ...' : 'حفظ الاسم',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Card(
            child: ListTile(
              key: const Key('open_stakeholders_button'),
              leading: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.mist,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.contacts_rounded,
                  color: AppColors.primary,
                  size: 19,
                ),
              ),
              title: const Text(
                'دليل المناديب والموردين',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'هواتف المناديب وسائقي المصنع • اتصال وواتساب',
                style: TextStyle(
                  fontSize: 10.5,
                  color: AppColors.textSecondary,
                ),
              ),
              trailing: const Icon(
                Icons.chevron_left_rounded,
                size: 20,
                color: AppColors.textSecondary,
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) => const StakeholdersScreen(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _SectionCard(
            title: 'معلومات النظام',
            icon: Icons.info_outline_rounded,
            color: AppColors.primary,
            children: <Widget>[
              _InfoRow(label: 'اسم المصنع', value: 'مصنع مياه رواء'),
              _InfoRow(
                label: 'الصنف المعتمد',
                value:
                    '${AppConstants.defaultItemName} '
                    '(${AppConstants.bottlesPerCarton} قنينة × '
                    '${AppConstants.bottleVolumeMl} مل)',
              ),
              _InfoRow(label: 'إصدار النظام', value: AppConstants.appVersion),
              const _InfoRow(
                label: 'نوع التشغيل',
                value: 'محلي بالكامل (Offline First)',
              ),
              const Divider(height: 22),
              _InfoRow(
                label: 'حجم قاعدة البيانات',
                value: stats == null
                    ? 'جارٍ الحساب...'
                    : '${stats.sizeKb.round()} ك.ب',
                highlight: true,
              ),
              _InfoRow(
                label: 'عدد الحركات',
                value: stats == null
                    ? '...'
                    : AppFormatters.number(stats.transactionCount),
              ),
              _InfoRow(
                label: 'عدد المخازن',
                value: stats == null
                    ? '...'
                    : AppFormatters.number(stats.warehouseCount),
              ),
              _InfoRow(
                label: 'سجلات الجرد',
                value: stats == null
                    ? '...'
                    : AppFormatters.number(stats.stocktakeCount),
              ),
              _InfoRow(
                label: 'آخر حركة',
                value: stats?.lastTransactionAt == null
                    ? 'لا توجد حركات بعد'
                    : AppFormatters.dateTime(stats!.lastTransactionAt!),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SectionCard(
            title: 'تصدير نسخة احتياطية',
            icon: Icons.cloud_upload_rounded,
            color: AppColors.success,
            children: <Widget>[
              const Text(
                'احفظ نسخة من جميع حركات ومخازن المصنع على هاتفك أو أرسلها '
                'للواتساب / Google Drive للرجوع إليها وقت الحاجة.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textSecondary,
                  height: 1.7,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  key: const Key('export_backup_button'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: busy ? null : _exportBackup,
                  icon: provider.isExporting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Icon(Icons.cloud_upload_rounded, size: 20),
                  label: Text(
                    provider.isExporting
                        ? 'جارٍ إنشاء النسخة...'
                        : 'إنشاء نسخة احتياطية ومشاركتها',
                  ),
                ),
              ),
              if (provider.lastBackup != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  'آخر نسخة: ${provider.lastBackup!.fileName}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          _SectionCard(
            title: 'استعادة نسخة احتياطية',
            icon: Icons.restore_rounded,
            color: AppColors.danger,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.danger.withValues(alpha: 0.3),
                  ),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: AppColors.danger,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'تحذير: استعادة نسخة احتياطية ستقوم باستبدال البيانات '
                        'الحالية بالكامل بالبيانات المستوردة.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.danger,
                          height: 1.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const Key('restore_backup_button'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger),
                    minimumSize: const Size.fromHeight(50),
                  ),
                  onPressed: busy ? null : _restoreBackup,
                  icon: provider.isRestoring
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.restore_rounded, size: 20),
                  label: Text(
                    provider.isRestoring
                        ? 'جارٍ الاستعادة...'
                        : 'استعادة البيانات من ملف',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SectionCard(
            title: 'إرشادات الاستخدام الميداني',
            icon: Icons.menu_book_rounded,
            color: AppColors.warning,
            children: const <Widget>[
              _Guideline(
                text:
                    'أنشئ نسخة احتياطية أسبوعيًا على الأقل واحفظها خارج الجهاز.',
              ),
              _Guideline(
                text:
                    'أجرِ جردًا دوريًا لمطابقة الرصيد الدفتري مع الكميات الفعلية.',
              ),
              _Guideline(
                text: 'اطبع سندات الصرف ووقّعها فور تسليم الكميات للمندوب.',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.children,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 116,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: highlight
                    ? AppColors.primaryDark
                    : AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.left,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Guideline extends StatelessWidget {
  const _Guideline({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.check_circle_outline_rounded,
            size: 16,
            color: AppColors.success,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textSecondary,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
