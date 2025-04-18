// models/transaction.dart
import 'package:flutter/foundation.dart';

class Transaction {
  final String id;
  final double amount;
  final String title;
  final DateTime date;
  final String categoryId;
  final String accountId;
  final String? notes;
  final String? receiptImagePath;
  final List<String>? tags;
  final TransactionType type;
  final bool isRecurring;
  final RecurringPattern? recurringPattern;

  Transaction({
    required this.id,
    required this.amount,
    required this.title,
    required this.date,
    required this.categoryId,
    required this.accountId,
    this.notes,
    this.receiptImagePath,
    this.tags,
    required this.type,
    this.isRecurring = false,
    this.recurringPattern,
  });

  Transaction copyWith({
    String? id,
    double? amount,
    String? title,
    DateTime? date,
    String? categoryId,
    String? accountId,
    String? notes,
    String? receiptImagePath,
    List<String>? tags,
    TransactionType? type,
    bool? isRecurring,
    RecurringPattern? recurringPattern,
  }) {
    return Transaction(
      id: id ?? this.id,
      amount: amount ?? this.amount,
      title: title ?? this.title,
      date: date ?? this.date,
      categoryId: categoryId ?? this.categoryId,
      accountId: accountId ?? this.accountId,
      notes: notes ?? this.notes,
      receiptImagePath: receiptImagePath ?? this.receiptImagePath,
      tags: tags ?? this.tags,
      type: type ?? this.type,
      isRecurring: isRecurring ?? this.isRecurring,
      recurringPattern: recurringPattern ?? this.recurringPattern,
    );
  }
}

enum TransactionType { expense, income, transfer }

class RecurringPattern {
  final RecurringFrequency frequency;
  final int interval;
  final DateTime? endDate;

  RecurringPattern({
    required this.frequency,
    this.interval = 1,
    this.endDate,
  });
}

enum RecurringFrequency { daily, weekly, monthly, yearly, custom }