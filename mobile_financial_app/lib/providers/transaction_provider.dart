// providers/transaction_provider.dart
import 'package:flutter/foundation.dart';
import '../models/transaction.dart';
import '../services/database_service.dart';

class TransactionProvider with ChangeNotifier {
  List<Transaction> _transactions = [];
  bool _isLoading = false;

  List<Transaction> get transactions => [..._transactions];
  bool get isLoading => _isLoading;

  Future<void> fetchTransactions() async {
    _isLoading = true;
    notifyListeners();

    try {
      final dbService = DatabaseService();
      _transactions = await dbService.getTransactions();
    } catch (error) {
      print('Error fetching transactions: $error');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addTransaction(Transaction transaction) async {
    try {
      final dbService = DatabaseService();
      final newTransactionId = await dbService.addTransaction(transaction);

      final newTransaction = Transaction(
        id: newTransactionId,
        amount: transaction.amount,
        title: transaction.title,
        date: transaction.date,
        categoryId: transaction.categoryId,
        accountId: transaction.accountId,
        notes: transaction.notes,
        receiptImagePath: transaction.receiptImagePath,
        tags: transaction.tags,
        type: transaction.type,
        isRecurring: transaction.isRecurring,
        recurringPattern: transaction.recurringPattern,
      );

      _transactions.add(newTransaction);
      notifyListeners();
    } catch (error) {
      print('Error adding transaction: $error');
      throw error;
    }
  }

  Future<void> updateTransaction(Transaction transaction) async {
    try {
      final dbService = DatabaseService();
      await dbService.updateTransaction(transaction);

      final index = _transactions.indexWhere((t) => t.id == transaction.id);
      if (index >= 0) {
        _transactions[index] = transaction;
        notifyListeners();
      }
    } catch (error) {
      print('Error updating transaction: $error');
      throw error;
    }
  }

  Future<void> deleteTransaction(String id) async {
    try {
      final dbService = DatabaseService();
      await dbService.deleteTransaction(id);

      _transactions.removeWhere((t) => t.id == id);
      notifyListeners();
    } catch (error) {
      print('Error deleting transaction: $error');
      throw error;
    }
  }

  List<Transaction> getTransactionsByCategory(String categoryId) {
    return _transactions.where((t) => t.categoryId == categoryId).toList();
  }

  List<Transaction> getTransactionsByAccount(String accountId) {
    return _transactions.where((t) => t.accountId == accountId).toList();
  }

  List<Transaction> getTransactionsByDateRange(DateTime start, DateTime end) {
    return _transactions.where((t) =>
    t.date.isAfter(start.subtract(Duration(days: 1))) &&
        t.date.isBefore(end.add(Duration(days: 1)))
    ).toList();
  }
}