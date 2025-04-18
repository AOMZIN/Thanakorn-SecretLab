// models/budget.dart
class Budget {
  final String id;
  final String name;
  final double amount;
  final String categoryId;
  final DateTime startDate;
  final DateTime endDate;
  final BudgetPeriod period;
  final bool isShared;
  final List<String>? sharedWithUserIds;

  Budget({
    required this.id,
    required this.name,
    required this.amount,
    required this.categoryId,
    required this.startDate,
    required this.endDate,
    required this.period,
    this.isShared = false,
    this.sharedWithUserIds,
  });
}

enum BudgetPeriod { daily, weekly, monthly, yearly, custom }