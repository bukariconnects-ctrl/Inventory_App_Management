import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../inventory/data/models/stock_balance_status.dart';
import '../../../inventory/presentation/providers/inventory_provider.dart';
import '../../../stocktake/presentation/screens/stocktake_screen.dart';
import '../../data/models/warehouse_model.dart';
import '../providers/warehouse_provider.dart';
import '../widgets/add_edit_warehouse_dialog.dart';
import '../widgets/warehouse_card.dart';

/// شاشة إدارة المخازن: عرض الأرصدة والمواقع مع الإضافة والتعديل والتعطيل.
class WarehousesScreen extends StatelessWidget {
  const WarehousesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final WarehouseProvider warehouseProvider = context
        .watch<WarehouseProvider>();
    final InventoryProvider inventoryProvider = context
        .watch<InventoryProvider>();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddDialog(context),
        icon: const Icon(Icons.add_business_rounded),
        label: const Text('مخزن جديد'),
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(context),
        child: _buildContent(context, warehouseProvider, inventoryProvider),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WarehouseProvider warehouseProvider,
    InventoryProvider inventoryProvider,
  ) {
    if (warehouseProvider.isLoading && warehouseProvider.warehouses.isEmpty) {
      return const _CenteredScrollable(child: CircularProgressIndicator());
    }

    if (warehouseProvider.errorMessage != null &&
        warehouseProvider.warehouses.isEmpty) {
      return _CenteredScrollable(
        child: _ErrorState(
          message: warehouseProvider.errorMessage!,
          onRetry: () => warehouseProvider.loadWarehouses(),
        ),
      );
    }

    if (warehouseProvider.warehouses.isEmpty) {
      return _CenteredScrollable(
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
              child: const Icon(
                Icons.warehouse_outlined,
                size: 40,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'لا توجد مخازن بعد',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'ابدأ بإضافة مخزن لتسجيل الأرصدة والعمليات.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: () => _openAddDialog(context),
              icon: const Icon(Icons.add_business_rounded, size: 18),
              label: const Text('إضافة مخزن جديد'),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: warehouseProvider.warehouses.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (BuildContext context, int index) {
        final WarehouseModel warehouse = warehouseProvider.warehouses[index];
        final StockBalanceStatus? status = inventoryProvider.statusFor(
          warehouse.id ?? -1,
        );
        return WarehouseCard(
          warehouse: warehouse,
          quantity: status?.quantity ?? 0,
          onEdit: () => _openEditDialog(context, warehouse),
          onToggleStatus: () => _toggleStatus(context, warehouse),
          onStocktake: () => _openStocktake(context, warehouse),
        );
      },
    );
  }

  Future<void> _refresh(BuildContext context) async {
    final WarehouseProvider warehouseProvider = context
        .read<WarehouseProvider>();
    final InventoryProvider inventoryProvider = context
        .read<InventoryProvider>();
    await Future.wait(<Future<void>>[
      warehouseProvider.loadWarehouses(showLoader: false),
      inventoryProvider.loadInventoryStatus(showLoader: false),
    ]);
  }

  Future<void> _openAddDialog(BuildContext context) async {
    final InventoryProvider inventoryProvider = context
        .read<InventoryProvider>();
    final bool? saved = await AddEditWarehouseDialog.show(context);
    if (saved == true) {
      // المخزن الجديد يبدأ برصيد صفر، لذا نحدّث الأرصدة لعرضه فورًا.
      await inventoryProvider.loadInventoryStatus(showLoader: false);
    }
  }

  Future<void> _openEditDialog(
    BuildContext context,
    WarehouseModel warehouse,
  ) async {
    final InventoryProvider inventoryProvider = context
        .read<InventoryProvider>();
    final bool? saved = await AddEditWarehouseDialog.show(
      context,
      warehouse: warehouse,
    );
    if (saved == true) {
      // قد يتغير حد التنبيه، فنعيد حساب حالات الانخفاض.
      await inventoryProvider.loadInventoryStatus(showLoader: false);
    }
  }

  Future<void> _openStocktake(
    BuildContext context,
    WarehouseModel warehouse,
  ) async {
    final int? warehouseId = warehouse.id;
    if (warehouseId == null) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            StocktakeScreen(initialWarehouseId: warehouseId),
      ),
    );
  }

  Future<void> _toggleStatus(
    BuildContext context,
    WarehouseModel warehouse,
  ) async {
    final WarehouseProvider warehouseProvider = context
        .read<WarehouseProvider>();
    final InventoryProvider inventoryProvider = context
        .read<InventoryProvider>();
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    final bool succeeded = await warehouseProvider.toggleWarehouseStatus(
      warehouse,
    );
    if (succeeded) {
      await inventoryProvider.refresh();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            warehouse.isActive
                ? 'تم تعطيل المخزن: ${warehouse.name}'
                : 'تم تفعيل المخزن: ${warehouse.name}',
          ),
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            warehouseProvider.errorMessage ?? 'تعذر تغيير حالة المخزن.',
          ),
        ),
      );
    }
  }
}

/// حاوية قابلة للسحب تُبقي مؤشر التحديث يعمل في الحالات الفارغة.
class _CenteredScrollable extends StatelessWidget {
  const _CenteredScrollable({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: <Widget>[
        SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.6,
          child: Center(
            child: Padding(padding: const EdgeInsets.all(28), child: child),
          ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Icon(
          Icons.cloud_off_rounded,
          size: 44,
          color: AppColors.textSecondary,
        ),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('إعادة المحاولة'),
        ),
      ],
    );
  }
}
