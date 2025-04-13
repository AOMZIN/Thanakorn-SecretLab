class DividendData {
  final DateTime date;
  final double amount;

  DividendData({
    required this.date,
    required this.amount,
  });

  factory DividendData.fromJson(Map<String, dynamic> json) {
    return DividendData(
      date: json['date'] is DateTime ? json['date'] : DateTime.parse(json['date']),
      amount: json['amount'] is double ? json['amount'] : double.parse(json['amount'].toString()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'date': date.toIso8601String(),
      'amount': amount,
    };
  }

  // Create a standardized map for internal use
  Map<String, dynamic> toStandardMap() {
    return {
      'date': date,
      'dividend': amount,
    };
  }
}