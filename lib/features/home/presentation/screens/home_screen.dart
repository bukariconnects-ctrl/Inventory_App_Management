import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../backup/presentation/screens/settings_screen.dart';
import '../../../inventory/presentation/providers/inventory_provider.dart';
import '../../../inventory/presentation/screens/inventory_screen.dart';
import '../../../reports/presentation/providers/reports_provider.dart';
import '../../../reports/presentation/screens/reports_hub_screen.dart';
import '../../../transactions/presentation/providers/transaction_provider.dart';
import '../../../warehouses/presentation/providers/warehouse_provider.dart';
import '../../../warehouses/presentation/screens/warehouses_screen.dart';
import '../widgets/dashboard_view.dart';

/// الشاشة الرئيسية: لوحة التحكم + تبويبات المخازن والمخزون.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    // تحميل البيانات بعد بناء الشاشة الأولى (بعد شاشة البداية).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _loadData();
    });
  }

  Future<void> _loadData({bool showLoader = true}) async {
    final WarehouseProvider warehouses = context.read<WarehouseProvider>();
    final InventoryProvider inventory = context.read<InventoryProvider>();
    final TransactionProvider transactions = context
        .read<TransactionProvider>();
    await Future.wait(<Future<void>>[
      warehouses.loadWarehouses(showLoader: showLoader),
      inventory.loadInventoryStatus(showLoader: showLoader),
      transactions.loadPendingApprovals(showLoader: false),
    ]);
  }

  void _openTab(int index) {
    if (_currentIndex == index) {
      return;
    }
    setState(() => _currentIndex = index);
    if (index == 3) {
      // تحديث السجل والتقارير عند فتح تبويبهما.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.read<ReportsProvider>().refresh();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool hasLowStockAlert = context
        .watch<InventoryProvider>()
        .hasLowStockAlert;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          AppConstants.appTitle,
          style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'الإعدادات والنسخ الاحتياطي',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext context) => const SettingsScreen(),
              ),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            tooltip: 'تحديث البيانات',
            onPressed: () => _loadData(showLoader: false),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: <Widget>[
          DashboardView(
            onOpenInventory: () => _openTab(2),
            onOpenArchive: () => _openTab(3),
          ),
          const WarehousesScreen(),
          const InventoryScreen(),
          const ReportsHubScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _openTab,
        type: BottomNavigationBarType.fixed,
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondary,
        selectedFontSize: 11.5,
        unselectedFontSize: 11,
        elevation: 12,
        items: <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Badge(
              isLabelVisible: hasLowStockAlert,
              backgroundColor: AppColors.danger,
              smallSize: 8,
              child: const Icon(Icons.dashboard_rounded),
            ),
            label: 'الرئيسية',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.warehouse_rounded),
            label: 'المخازن',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.inventory_2_rounded),
            label: 'المخزون',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long_rounded),
            label: 'السجل والتقارير',
          ),
        ],
      ),
    );
  }
}
