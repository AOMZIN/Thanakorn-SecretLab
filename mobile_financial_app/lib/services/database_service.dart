// services/database_service.dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/transaction.dart';
import '../models/category.dart';
import '../models/account.dart';
import '../models/budget.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  static Database? _database;

  factory DatabaseService() {
    return _instance;
  }

  DatabaseService._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'finance_app.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDatabase,
    );
  }

  Future<void> _createDatabase(Database db, int version) async {
    // Create transactions table
    await db.execute('''
      CREATE TABLE transactions(
        id TEXT PRIMARY KEY,
        amount REAL NOT NULL,
        title TEXT NOT NULL,
        date INTEGER NOT NULL,
        categoryId TEXT NOT NULL,
        accountId TEXT NOT NULL,
        notes TEXT,
        receiptImagePath TEXT,
        tags TEXT,
        type INTEGER NOT NULL,
        isRecurring INTEGER NOT NULL,
        recurringFrequency INTEGER,
        recurringInterval INTEGER,
        recurringEndDate INTEGER
      )
    ''');

    // Create categories table
    await db.execute('''
      CREATE TABLE categories(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        iconCode INTEGER NOT NULL,
        colorValue INTEGER NOT NULL,
        parentCategoryId TEXT,
        isIncome INTEGER NOT NULL
      )
    ''');

    // Create accounts table
    await db.execute('''
      CREATE TABLE accounts(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        balance REAL NOT NULL,
        type INTEGER NOT NULL,
        bankName TEXT,
        isConnected INTEGER NOT NULL,
        accountNumber TEXT,
        currencyCode TEXT NOT NULL
      )
    ''');

    // Create budgets table
    await db.execute('''
      CREATE TABLE budgets(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        amount REAL NOT NULL,
        categoryId TEXT NOT NULL,
        startDate INTEGER NOT NULL,
        endDate INTEGER NOT NULL,
        period INTEGER NOT NULL,
        isShared INTEGER NOT NULL,
        sharedWithUserIds TEXT
      )
    ''');

    // Insert default categories
    await _insertDefaultCategories(db);

    // Insert default account
    await _insertDefaultAccount(db);
  }

  Future<void> _insertDefaultCategories(Database db) async {
    // Expense categories
    final expenseCategories = [
      {'id': 'cat_food', 'name': 'Food & Dining', 'iconCode': 0xe25a, 'colorValue': 0xFFE91E63, 'isIncome': 0},
      {'id': 'cat_transport', 'name': 'Transportation', 'iconCode': 0xe571, 'colorValue': 0xFF2196F3, 'isIncome': 0},
      {'id': 'cat_shopping', 'name': 'Shopping', 'iconCode': 0xe59c, 'colorValue': 0xFF9C27B0, 'isIncome': 0},
      {'id': 'cat_bills', 'name': 'Bills & Utilities', 'iconCode': 0xe33a, 'colorValue': 0xFF3F51B5, 'isIncome': 0},
      {'id': 'cat_entertainment', 'name': 'Entertainment', 'iconCode': 0xe40f, 'colorValue': 0xFFFF9800, 'isIncome': 0},
      {'id': 'cat_health', 'name': 'Health & Fitness', 'iconCode': 0xe3db, 'colorValue': 0xFF4CAF50, 'isIncome': 0},
    ];

    // Income categories
    final incomeCategories = [
      {'id': 'cat_salary', 'name': 'Salary', 'iconCode': 0xe8f8, 'colorValue': 0xFF00BCD4, 'isIncome': 1},
      {'id': 'cat_business', 'name': 'Business', 'iconCode': 0xe0af, 'colorValue': 0xFF607D8B, 'isIncome': 1},
      {'id': 'cat_gifts', 'name': 'Gifts', 'iconCode': 0xe8f6, 'colorValue': 0xFFFF5722, 'isIncome': 1},
      {'id': 'cat_investments', 'name': 'Investments', 'iconCode': 0xe84f, 'colorValue': 0xFF795548, 'isIncome': 1},
    ];

    // Insert categories into database
    for (var category in [...expenseCategories, ...incomeCategories]) {
      await db.insert('categories', category);
    }
  }

  Future<void> _insertDefaultAccount(Database db) async {
    await db.insert('accounts', {
      'id': 'acc_cash',
      'name': 'Cash',
      'balance': 0.0,
      'type': AccountType.cash.index,
      'isConnected': 0,
      'currencyCode': 'USD'
    });
  }

  // Transaction methods
  Future<List<Transaction>> getTransactions() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('transactions');

    return List.generate(maps.length, (i) {
      final map = maps[i];

      // Parse recurring pattern if present
      RecurringPattern? recurringPattern;
      if (map['isRecurring'] == 1 && map['recurringFrequency'] != null) {
        recurringPattern = RecurringPattern(
          frequency: RecurringFrequency.values[map['recurringFrequency']],
          interval: map['recurringInterval'] ?? 1,
          endDate: map['recurringEndDate'] != null
              ? DateTime.fromMillisecondsSinceEpoch(map['recurringEndDate'])
              : null,
        );
      }

      // Parse tags if present
      List<String>? tags;
      if (map['tags'] != null && map['tags'].isNotEmpty) {
        tags = map['tags'].split(',');
      }

      return Transaction(
        id: map['id'],
        amount: map['amount'],
        title: map['title'],
        date: DateTime.fromMillisecondsSinceEpoch(map['date']),
        categoryId: map['categoryId'],
        accountId: map['accountId'],
        notes: map['notes'],
        receiptImagePath: map['receiptImagePath'],
        tags: tags,
        type: TransactionType.values[map['type']],
        isRecurring: map['isRecurring'] == 1,
        recurringPattern: recurringPattern,
      );
    });
  }

  Future<String> addTransaction(Transaction transaction) async {
    final db = await database;

    // Convert tags to string if present
    String? tagsString;
    if (transaction.tags != null && transaction.tags!.isNotEmpty) {
      tagsString = transaction.tags!.join(',');
    }

    await db.insert(
        'transactions',
        {
          'id': transaction.id,
          'amount': transaction.amount,
          'title': transaction.title,
          'date': transaction.date.millisecondsSinceEpoch,
          'categoryId': transaction.categoryId,
          'accountId': transaction.accountId,
          'notes': transaction.notes,
          'receiptImagePath': transaction.receiptImagePath,
          'tags': tagsString,
          'type': transaction.type.index,
          'isRecurring': transaction.isRecurring ? 1 : 0,
          'recurringFrequency': transaction.recurringPattern?.frequency.index,
          'recurringInterval': transaction.recurringPattern?.interval,
          'recurringEndDate': transaction.recurringPattern?.endDate?.millisecondsSinceEpoch,
        }
    );

    // Update account balance
    await _updateAccountBalance(transaction);

    return transaction.id;
  }

  Future<void> updateTransaction(Transaction transaction) async {
    final db = await database;

    // Get the old transaction to revert its effect on account balance
    final oldTransactionMaps = await db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [transaction.id],
    );

    if (oldTransactionMaps.isNotEmpty) {
      final oldMap = oldTransactionMaps.first;
      final oldTransaction = Transaction(
        id: oldMap['id'],
        amount: oldMap['amount'],
        title: oldMap['title'],
        date: DateTime.fromMillisecondsSinceEpoch(oldMap['date']),
        categoryId: oldMap['categoryId'],
        accountId: oldMap['accountId'],
        type: TransactionType.values[oldMap['type']],
      );

      // Revert old transaction's effect on account balance
      await _updateAccountBalance(oldTransaction, revert: true);
    }

    // Convert tags to string if present
    String? tagsString;
    if (transaction.tags != null && transaction.tags!.isNotEmpty) {
      tagsString = transaction.tags!.join(',');
    }

    await db.update(
      'transactions',
      {
        'amount': transaction.amount,
        'title': transaction.title,
        'date': transaction.date.millisecondsSinceEpoch,
        'categoryId': transaction.categoryId,
        'accountId': transaction.accountId,
        'notes': transaction.notes,
        'receiptImagePath': transaction.receiptImagePath,
        'tags': tagsString,
        'type': transaction.type.index,
        'isRecurring': transaction.isRecurring ? 1 : 0,
        'recurringFrequency': transaction.recurringPattern?.frequency.index,
        'recurringInterval': transaction.recurringPattern?.interval,
        'recurringEndDate': transaction.recurringPattern?.endDate?.millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [transaction.id],
    );

    // Apply new transaction's effect on account balance
    await _updateAccountBalance(transaction);
  }

  Future<void> deleteTransaction(String id) async {
    final db = await database;

    // Get the transaction to revert its effect on account balance
    final transactionMaps = await db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (transactionMaps.isNotEmpty) {
      final map = transactionMaps.first;
      final transaction = Transaction(
        id: map['id'],
        amount: map['amount'],
        title: map['title'],
        date: DateTime.fromMillisecondsSinceEpoch(map['date']),
        categoryId: map['categoryId'],
        accountId: map['accountId'],
        type: TransactionType.values[map['type']],
      );

      // Revert transaction's effect on account balance
      await _updateAccountBalance(transaction, revert: true);

      // Delete the transaction
      await db.delete(
        'transactions',
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<void> _updateAccountBalance(Transaction transaction, {bool revert = false}) async {
    final db = await database;

    // Get current account balance
    final accountMaps = await db.query(
      'accounts',
      where: 'id = ?',
      whereArgs: [transaction.accountId],
    );

    if (accountMaps.isNotEmpty) {
      final accountMap = accountMaps.first;
      double currentBalance = accountMap['balance'];
      double updatedBalance = currentBalance;

      // Calculate new balance based on transaction type
      switch (transaction.type) {
        case TransactionType.expense:
          updatedBalance = revert
              ? currentBalance + transaction.amount
              : currentBalance - transaction.amount;
          break;
        case TransactionType.income:
          updatedBalance = revert
              ? currentBalance - transaction.amount
              : currentBalance + transaction.amount;
          break;
        case TransactionType.transfer:
        // For transfers, we would need to update both accounts
        // This is simplified for now
          break;
      }

      // Update account balance
      await db.update(
        'accounts',
        {'balance': updatedBalance},
        where: 'id = ?',
        whereArgs: [transaction.accountId],
      );
    }
  }

  // Category methods
  Future<List<Category>> getCategories() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('categories');

    return List.generate(maps.length, (i) {
      final map = maps[i];
      return Category(
        id: map['id'],
        name: map['name'],
        icon: IconData(map['iconCode'], fontFamily: 'MaterialIcons'),
        color: Color(map['colorValue']),
        parentCategoryId: map['parentCategoryId'],
        isIncome: map['isIncome'] == 1,
      );
    });
  }

  Future<String> addCategory(Category category) async {
    final db = await database;
    await db.insert(
        'categories',
        {
          'id': category.id,
          'name': category.name,
          'iconCode': category.icon.codePoint,
          'colorValue': category.color.value,
          'parentCategoryId': category.parentCategoryId,
          'isIncome': category.isIncome ? 1 : 0,
        }
    );
    return category.id;
  }

  Future<void> updateCategory(Category category) async {
    final db = await database;
    await db.update(
      'categories',
      {
        'name': category.name,
        'iconCode': category.icon.codePoint,
        'colorValue': category.color.value,
        'parentCategoryId': category.parentCategoryId,
        'isIncome': category.isIncome ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [category.id],
    );
  }

  Future<void> deleteCategory(String id) async {
    final db = await database;
    await db.delete(
      'categories',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Account methods
  Future<List<Account>> getAccounts() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('accounts');

    return List.generate(maps.length, (i) {
      final map = maps[i];
      return Account(
        id: map['id'],
        name: map['name'],
        balance: map['balance'],
        type: AccountType.values[map['type']],
        bankName: map['bankName'],
        isConnected: map['isConnected'] == 1,
        accountNumber: map['accountNumber'],
        currencyCode: map['currencyCode'],
      );
    });
  }

  Future<String> addAccount(Account account) async {
    final db = await database;
    await db.insert(
        'accounts',
        {
          'id': account.id,
          'name': account.name,
          'balance': account.balance,
          'type': account.type.index,
          'bankName': account.bankName,
          'isConnected': account.isConnected ? 1 : 0,
          'accountNumber': account.accountNumber,
          'currencyCode': account.currencyCode,
        }
    );
    return account.id;
  }

  Future<void> updateAccount(Account account) async {
    final db = await database;
    await db.update(
      'accounts',
      {
        'name': account.name,
        'balance': account.balance,
        'type': account.type.index,
        'bankName': account.bankName,
        'isConnected': account.isConnected ? 1 : 0,
        'accountNumber': account.accountNumber,
        'currencyCode': account.currencyCode,
      },
      where: 'id = ?',
      whereArgs: [account.id],
    );
  }

  Future<void> deleteAccount(String id) async {
    final db = await database;
    await db.delete(
      'accounts',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Budget methods
  Future<List<Budget>> getBudgets() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('budgets');

    return List.generate(maps.length, (i) {
      final map = maps[i];

      // Parse shared user IDs if present
      List<String>? sharedWithUserIds;
      if (map['sharedWithUserIds'] != null && map['sharedWithUserIds'].isNotEmpty) {
        sharedWithUserIds = map['sharedWithUserIds'].split(',');
      }

      return Budget(
        id: map['id'],
        name: map['name'],
        amount: map['amount'],
        categoryId: map['categoryId'],
        startDate: DateTime.fromMillisecondsSinceEpoch(map['startDate']),
        endDate: DateTime.fromMillisecondsSinceEpoch(map['endDate']),
        period: BudgetPeriod.values[map['period']],
        isShared: map['isShared'] == 1,
        sharedWithUserIds: sharedWithUserIds,
      );
    });
  }

  Future<String> addBudget(Budget budget) async {
    final db = await database;

    // Convert shared user IDs to string if present
    String? sharedWithUserIdsString;
    if (budget.sharedWithUserIds != null && budget.sharedWithUserIds!.isNotEmpty) {
      sharedWithUserIdsString = budget.sharedWithUserIds!.join(',');
    }

    await db.insert(
        'budgets',
        {
          'id': budget.id,
          'name': budget.name,
          'amount': budget.amount,
          'categoryId': budget.categoryId,
          'startDate': budget.startDate.millisecondsSinceEpoch,
          'endDate': budget.endDate.millisecondsSinceEpoch,
          'period': budget.period.index,
          'isShared': budget.isShared ? 1 : 0,
          'sharedWithUserIds': sharedWithUserIdsString,
        }
    );
    return budget.id;
  }

  Future<void> updateBudget(Budget budget) async {
    final db = await database;

    // Convert shared user IDs to string if present
    String? sharedWithUserIdsString;
    if (budget.sharedWithUserIds != null && budget.sharedWithUserIds!.isNotEmpty) {
      sharedWithUserIdsString = budget.sharedWithUserIds!.join(',');
    }

    await db.update(
      'budgets',
      {
        'name': budget.name,
        'amount': budget.amount,
        'categoryId': budget.categoryId,
        'startDate': budget.startDate.millisecondsSinceEpoch,
        'endDate': budget.endDate.millisecondsSinceEpoch,
        'period': budget.period.index,
        'isShared': budget.isShared ? 1 : 0,
        'sharedWithUserIds': sharedWithUserIdsString,
      },
      where: 'id = ?',
      whereArgs: [budget.id],
    );
  }

  Future<void> deleteBudget(String id) async {
    final db = await database;
    await db.delete(
      'budgets',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}

// Add these imports to the file
import 'package:flutter/material.dart';