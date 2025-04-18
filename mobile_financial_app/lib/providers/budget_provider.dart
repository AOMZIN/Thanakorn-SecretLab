// providers/budget_provider.dart
import 'package:flutter/foundation.dart';
import '../models/budget.dart';
import '../models/transaction.dart';
import '../services/database_service.dart';

class BudgetProvider with ChangeNotifier {
  List<Budget> _budgets = [];
  bool _isLoading = false;

  List<Budget> get budgets => [..._budgets];
  bool get isLoading => _isLoading;

  Future<void> fetchBudgets() async {
    _isLoading = true;
    notifyListeners();

    try {
      final dbService = DatabaseService();
      _budgets = await dbService.getBudgets();
    } catch (error) {
      print('Error fetching budgets: $error');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addBudget(Budget budget) async {
    try {
      final dbService = DatabaseService();
      final newBudgetId = await dbService.addBudget(budget);

      final newBudget = Budget(
        id: newBudgetId,
        name: budget.name,
        amount: budget.amount,
        categoryId: budget.categoryId,
        startDate: budget.startDate,
        endDate: budget.endDate,
        period: budget.period,
        isShared: budget.isShared,
        sharedWithUserIds: budget.sharedWithUserIds,
      );

      _budgets.add(newBudget);
      notifyListeners();
    } catch (error) {
      print('Error adding budget: $error');
      throw error;
    }
  }

  Future<void> updateBudget(Budget budget) async {
    try {
      final dbService = DatabaseService();
      await dbService.updateBudget(budget);

      final index = _budgets.indexWhere((b) => b.id == budget.id);
      if (index >= 0) {
        _budgets[index] = budget;
        notifyListeners();
      }
    } catch (error) {
      print('Error updating budget: $error');
      throw error;
    }
  }

  Future<void> deleteBudget(String id) async {
    try {
      final dbService = DatabaseService();
      await dbService.deleteBudget(id);

      _budgets.removeWhere((b) => b.id == id);
      notifyListeners();
    } catch (error) {
      print('Error deleting budget: $error');
      throw error;
    }
  }

  Budget? getBudgetByCategory(String categoryId) {
    return _budgets.firstWhere(
          (b) => b.categoryId == categoryId,
      orElse: () => null as Budget,
    );
  }

  double getBudgetProgress(Budget budget, List<Transaction> transactions) {
    // Calculate how much has been spent in this budget category
    final relevantTransactions = transactions.where((t) =>
    t.categoryId == budget.categoryId &&
        t.date.isAfter(budget.startDate.subtract(Duration(days: 1))) &&
        t.date.isBefore(budget.endDate.add(Duration(days: 1))) &&
        t.type == TransactionType.expense
    );

    final totalSpent = relevantTransactions.fold(
        0.0, (sum, transaction) => sum + transaction.amount);

    return totalSpent / budget.amount;
  }

  double getRemainingAmount(Budget budget, List<Transaction> transactions) {
    final relevantTransactions = transactions.where((t) =>
    t.categoryId == budget.categoryId &&
        t.date.isAfter(budget.startDate.subtract(Duration(days: 1))) &&
        t.date.isBefore(budget.endDate.add(Duration(days: 1))) &&
        t.type == TransactionType.expense
    );

    final totalSpent = relevantTransactions.fold(
        0.0, (sum, transaction) => sum + transaction.amount);

    return budget.amount - totalSpent;
  }

  List<Budget> getActiveBudgets() {
    final now = DateTime.now();
    return _budgets.where((b) =>
    b.startDate.isBefore(now) && b.endDate.isAfter(now)
    ).toList();
  }

  List<Budget> getSharedBudgets() {
    return _budgets.where((b) => b.isShared).toList();
  }
}