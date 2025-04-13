class DividendData {
  final DateTime date;
  final double amount;

  DividendData({
    required this.date,
    required this.amount,
  });

  factory DividendData.fromJson(Map<String, dynamic> json) {
    return DividendData(
      date: DateTime.parse(json['date']),
      amount: double.parse(json['amount'].toString()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'date': date.toIso8601String(),
      'amount': amount,
    };
  }
}