// screens/dashboard_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/transaction_provider.dart';
import '../providers/budget_provider.dart';
import '../widgets/summary_card.dart';
import '../widgets/recent_transactions.dart';
import '../widgets/spending_chart.dart';
import '../widgets/budget_progress.dart';

class DashboardPage extends StatefulWidget {
  @override
  _DashboardPageState createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SummaryCard(),
            SizedBox(height: 16),
            Text(
              'Spending Overview',
              style: Theme.of(context).textTheme.headline6,
            ),
            SizedBox(height: 8),
            SpendingChart(),
            SizedBox(height: 16),
            Text(
              'Budget Progress',
              style: Theme.of(context).textTheme.headline6,
            ),
            SizedBox(height: 8),
            BudgetProgress(),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Transactions',
                  style: Theme.of(context).textTheme.headline6,
                ),
                TextButton(
                  onPressed: () {
                    // Navigate to all transactions
                  },
                  child: Text('See All'),
                ),
              ],
            ),
            SizedBox(height: 8),
            RecentTransactions(),
          ],
        ),
      ),
    );
  }
}