import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import 'reports_screen.dart';
import 'transactions_archive_screen.dart';

/// تبويب «السجل والتقارير»: سجل الحركات + التقارير والإحصائيات.
class ReportsHubScreen extends StatelessWidget {
  const ReportsHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: <Widget>[
          Container(
            color: AppColors.surface,
            child: const TabBar(
              labelColor: AppColors.primaryDark,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
              indicatorSize: TabBarIndicatorSize.label,
              labelStyle: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
              unselectedLabelStyle: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
              tabs: <Widget>[
                Tab(text: 'سجل الحركات'),
                Tab(text: 'التقارير والإحصائيات'),
              ],
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: <Widget>[TransactionsArchiveScreen(), ReportsScreen()],
            ),
          ),
        ],
      ),
    );
  }
}
