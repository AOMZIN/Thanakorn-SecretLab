// models/account.dart
class Account {
  final String id;
  final String name;
  final double balance;
  final AccountType type;
  final String? bankName;
  final bool isConnected;
  final String? accountNumber;
  final String currencyCode;

  Account({
    required this.id,
    required this.name,
    required this.balance,
    required this.type,
    this.bankName,
    this.isConnected = false,
    this.accountNumber,
    this.currencyCode = 'USD',
  });
}

enum AccountType { checking, savings, credit, investment, cash }