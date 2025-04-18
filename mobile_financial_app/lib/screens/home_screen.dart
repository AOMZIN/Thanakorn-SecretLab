// screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/transaction_provider.dart';
import '../widgets/transaction_list.dart';
import '../widgets/summary_card.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    DashboardPage(),
    TransactionsPage(),
    BudgetPage(),
    AccountsPage(),
    MorePage(),
  ];

  @override
  void initState() {
    super.initState();
    // Load initial data
    Future.delayed(Duration.zero, () {
      Provider.of<TransactionProvider>(context, listen: false).fetchTransactions();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Personal Finance'),
        actions: [
          IconButton(
            icon: Icon(Icons.search),
            onPressed: () {
              // Navigate to search screen
            },
          ),
          IconButton(
            icon: Icon(Icons.notifications),
            onPressed: () {
              // Navigate to notifications screen
            },
          ),
        ],
      ),
      body: _pages[_selectedIndex],
      floatingActionButton: FloatingActionButton(
        child: Icon(Icons.add),
        onPressed: () {
          // Show bottom sheet for quick actions
          _showQuickActionsSheet();
        },
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.receipt_long), label: 'Transactions'),
          BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet), label: 'Budget'),
          BottomNavigationBarItem(icon: Icon(Icons.account_balance), label: 'Accounts'),
          BottomNavigationBarItem(icon: Icon(Icons.more_horiz), label: 'More'),
        ],
      ),
    );
  }

  void _showQuickActionsSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          padding: EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.remove_circle, color: Colors.red),
                title: Text('Add Expense'),
                onTap: () {
                  Navigator.pop(context);
                  // Navigate to add expense form
                },
              ),
              ListTile(
                leading: Icon(Icons.add_circle, color: Colors.green),
                title: Text('Add Income'),
                onTap: () {
                  Navigator.pop(context);
                  // Navigate to add income form
                },
              ),
              ListTile(
                leading: Icon(Icons.swap_horiz, color: Colors.blue),
                title: Text('Add Transfer'),
                onTap: () {
                  Navigator.pop(context);
                  // Navigate to add transfer form
                },
              ),
              ListTile(
                leading: Icon(Icons.camera_alt),
                title: Text('Scan Receipt'),
                onTap: () {
                  Navigator.pop(context);
                  // Navigate to receipt scanner
                },
              ),
            ],
          ),
        );
      },
    );
  }
}