import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/models/stakeholder_model.dart';
import '../providers/stakeholder_provider.dart';
import '../widgets/add_edit_stakeholder_dialog.dart';

/// دليل المناديب والموزعين وسائقي المصنع والموردين.
class StakeholdersScreen extends StatefulWidget {
  const StakeholdersScreen({super.key});

  @override
  State<StakeholdersScreen> createState() => _StakeholdersScreenState();
}

class _StakeholdersScreenState extends State<StakeholdersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<StakeholderProvider>().loadStakeholders();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  StakeholderType get _currentType => _tabController.index == 0
      ? StakeholderType.distributor
      : StakeholderType.driver;

  Future<void> _openDialog({
    StakeholderModel? stakeholder,
    StakeholderType? initialType,
  }) async {
    final bool? saved = await AddEditStakeholderDialog.show(
      context,
      stakeholder: stakeholder,
      initialType: initialType ?? _currentType,
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            stakeholder == null
                ? 'تمت إضافة جهة التعامل إلى الدليل.'
                : 'تم تحديث بيانات جهة التعامل.',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Future<void> _confirmDelete(StakeholderModel stakeholder) async {
    final StakeholderProvider provider = context.read<StakeholderProvider>();
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'حذف جهة تعامل',
          style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
        ),
        content: Text(
          'سيتم حذف «${stakeholder.name}» من الدليل نهائيًا. '
          'السندات السابقة تحتفظ بالاسم كما كُتب فيها.',
          style: const TextStyle(fontSize: 12.5, height: 1.6),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 44),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await provider.deleteStakeholder(stakeholder);
  }

  Future<void> _toggle(StakeholderModel stakeholder) async {
    await context.read<StakeholderProvider>().toggleStakeholder(stakeholder);
  }

  @override
  Widget build(BuildContext context) {
    final StakeholderProvider provider = context.watch<StakeholderProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('دليل المناديب والموردين'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: <Widget>[
            Tab(text: 'المناديب (${provider.distributors.length})'),
            Tab(text: 'السائقون (${provider.drivers.length})'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add_stakeholder_fab'),
        onPressed: () => _openDialog(initialType: _currentType),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('إضافة'),
      ),
      body: TabBarView(
        controller: _tabController,
        children: <Widget>[
          _StakeholderList(
            stakeholders: provider.distributors,
            isLoading: provider.isLoading,
            type: StakeholderType.distributor,
            onRefresh: () => provider.loadStakeholders(showLoader: false),
            onEdit: (StakeholderModel s) => _openDialog(stakeholder: s),
            onToggle: _toggle,
            onDelete: _confirmDelete,
          ),
          _StakeholderList(
            stakeholders: provider.drivers,
            isLoading: provider.isLoading,
            type: StakeholderType.driver,
            onRefresh: () => provider.loadStakeholders(showLoader: false),
            onEdit: (StakeholderModel s) => _openDialog(stakeholder: s),
            onToggle: _toggle,
            onDelete: _confirmDelete,
          ),
        ],
      ),
    );
  }
}

/// قائمة جهات التعامل داخل تبويب واحد.
class _StakeholderList extends StatelessWidget {
  const _StakeholderList({
    required this.stakeholders,
    required this.isLoading,
    required this.type,
    required this.onRefresh,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  final List<StakeholderModel> stakeholders;
  final bool isLoading;
  final StakeholderType type;
  final Future<void> Function() onRefresh;
  final void Function(StakeholderModel) onEdit;
  final Future<void> Function(StakeholderModel) onToggle;
  final Future<void> Function(StakeholderModel) onDelete;

  @override
  Widget build(BuildContext context) {
    if (isLoading && stakeholders.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (stakeholders.isEmpty) {
      return _EmptyStakeholders(type: type);
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: stakeholders.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (BuildContext context, int index) {
          final StakeholderModel stakeholder = stakeholders[index];
          return _StakeholderCard(
            stakeholder: stakeholder,
            onEdit: () => onEdit(stakeholder),
            onToggle: () => onToggle(stakeholder),
            onDelete: () => onDelete(stakeholder),
          );
        },
      ),
    );
  }
}

class _EmptyStakeholders extends StatelessWidget {
  const _EmptyStakeholders({required this.type});

  final StakeholderType type;

  @override
  Widget build(BuildContext context) {
    final bool isDistributor = type == StakeholderType.distributor;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: AppColors.mist,
                borderRadius: BorderRadius.circular(26),
              ),
              child: Icon(
                isDistributor
                    ? Icons.local_shipping_outlined
                    : Icons.agriculture_outlined,
                size: 40,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              isDistributor ? 'لا يوجد مناديب بعد' : 'لا يوجد سائقون بعد',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              isDistributor
                  ? 'أضف مناديب التوزيع مع أرقام هواتفهم للاتصال بهم بسرعة.'
                  : 'أضف سائقي المصنع والموردين مع أرقام لوحات مركباتهم.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.7,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _StakeholderAction { edit, toggle, delete }

/// بطاقة جهة تعامل واحدة مع الاتصال والواتساب.
class _StakeholderCard extends StatelessWidget {
  const _StakeholderCard({
    required this.stakeholder,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  final StakeholderModel stakeholder;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  bool get _isDistributor => stakeholder.type == StakeholderType.distributor;

  Future<void> _openUri(
    BuildContext context,
    Uri uri,
    String failureMessage,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      final bool opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        messenger.showSnackBar(SnackBar(content: Text(failureMessage)));
      }
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failureMessage)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = _isDistributor ? AppColors.primary : AppColors.cyan;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    _isDistributor
                        ? Icons.person_rounded
                        : Icons.local_shipping_rounded,
                    color: accent,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              stakeholder.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: stakeholder.isActive
                                    ? AppColors.textPrimary
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ),
                          if (!stakeholder.isActive)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.disabled.withValues(
                                  alpha: 0.18,
                                ),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'غير نشط',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        stakeholder.type.label,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: accent,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<_StakeholderAction>(
                  tooltip: 'خيارات',
                  onSelected: (_StakeholderAction action) {
                    switch (action) {
                      case _StakeholderAction.edit:
                        onEdit();
                      case _StakeholderAction.toggle:
                        onToggle();
                      case _StakeholderAction.delete:
                        onDelete();
                    }
                  },
                  itemBuilder: (BuildContext context) =>
                      <PopupMenuEntry<_StakeholderAction>>[
                        const PopupMenuItem<_StakeholderAction>(
                          value: _StakeholderAction.edit,
                          child: Text('تعديل البيانات'),
                        ),
                        PopupMenuItem<_StakeholderAction>(
                          value: _StakeholderAction.toggle,
                          child: Text(stakeholder.isActive ? 'تعطيل' : 'تنشيط'),
                        ),
                        const PopupMenuItem<_StakeholderAction>(
                          value: _StakeholderAction.delete,
                          child: Text('حذف'),
                        ),
                      ],
                ),
              ],
            ),
            if (stakeholder.vehicleNumber != null) ...<Widget>[
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  const Icon(
                    Icons.badge_outlined,
                    size: 15,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'اللوحة: ${stakeholder.vehicleNumber}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (stakeholder.hasPhone) ...<Widget>[
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  const Icon(
                    Icons.phone_outlined,
                    size: 15,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      stakeholder.phone ?? '',
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 36),
                    ),
                    onPressed: () => _openUri(
                      context,
                      Uri(scheme: 'tel', path: stakeholder.phoneDigits),
                      'تعذر فتح تطبيق الاتصال على هذا الجهاز.',
                    ),
                    icon: const Icon(Icons.call_rounded, size: 17),
                    label: const Text(
                      'اتصال',
                      style: TextStyle(fontSize: 11.5),
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.success,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 36),
                    ),
                    onPressed: () => _openUri(
                      context,
                      Uri.parse('https://wa.me/${stakeholder.phoneDigits}'),
                      'تعذر فتح واتساب على هذا الجهاز.',
                    ),
                    icon: const Icon(Icons.chat_rounded, size: 17),
                    label: const Text(
                      'واتساب',
                      style: TextStyle(fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
