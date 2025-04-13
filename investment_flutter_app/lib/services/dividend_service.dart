import 'package:http/http.dart' as http;
import 'dart:convert';

class DividendService {
  static const String _apiKey = 'OICQLJJPW42HGD9Y'; // Consider storing this in a secure config file
  static final Map<String, CachedDividendData> _cache = {};
  static const Duration _cacheDuration = Duration(days: 1); // Dividend data doesn't change as frequently

  static Future<List<Map<String, dynamic>>> fetchDividendData(String symbol) async {
    // Check cache first
    if (_cache.containsKey(symbol) &&
        DateTime.now().difference(_cache[symbol]!.timestamp) < _cacheDuration) {
      return _cache[symbol]!.data;
    }

    final url = 'https://www.alphavantage.co/query?function=TIME_SERIES_MONTHLY_ADJUSTED&symbol=$symbol&apikey=$_apiKey';

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Check if API returned an error message or empty data
        if (data.containsKey('Error Message') || !data.containsKey('Monthly Adjusted Time Series')) {
          return [];
        }

        final timeSeries = data['Monthly Adjusted Time Series'];
        final dividendData = <Map<String, dynamic>>[];

        timeSeries.forEach((key, value) {
          final date = DateTime.parse(key);
          final dividend = value['7. dividend amount'].toString();
          if (dividend != '0.0000') {
            dividendData.add({
              'date': date,
              'dividend': double.parse(dividend),
            });
          }
        });

        // Cache the result
        _cache[symbol] = CachedDividendData(
          data: dividendData,
          timestamp: DateTime.now(),
        );

        return dividendData;
      } else {
        throw Exception('Failed to load dividend data: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching dividend data for $symbol: $e');
      return [];
    }
  }

  static double calculateAnnualDividendIncome(List<Map<String, dynamic>> dividendData) {
    if (dividendData.isEmpty) return 0;

    double totalDividend = 0;
    final now = DateTime.now();
    final oneYearAgo = now.subtract(const Duration(days: 365));

    for (final dividend in dividendData) {
      final date = dividend['date'] as DateTime;
      if (date.isAfter(oneYearAgo)) {
        totalDividend += dividend['dividend'] as double;
      }
    }

    return totalDividend;
  }

  static double calculateMonthlyDividendIncome(List<Map<String, dynamic>> dividendData) {
    if (dividendData.isEmpty) return 0;

    double totalDividend = 0;
    final now = DateTime.now();
    final oneMonthAgo = now.subtract(const Duration(days: 30));

    for (final dividend in dividendData) {
      final date = dividend['date'] as DateTime;
      if (date.isAfter(oneMonthAgo)) {
        totalDividend += dividend['dividend'] as double;
      }
    }

    return totalDividend;
  }

  static double calculateDailyDividendIncome(List<Map<String, dynamic>> dividendData) {
    if (dividendData.isEmpty) return 0;

    // Since dividends are usually paid quarterly or annually, this is an approximation
    return calculateAnnualDividendIncome(dividendData) / 365;
  }

  static double calculateDividendYield(double annualDividendIncome, double currentPrice) {
    if (currentPrice <= 0) return 0;
    return (annualDividendIncome / currentPrice) * 100;
  }
}

class CachedDividendData {
  final List<Map<String, dynamic>> data;
  final DateTime timestamp;

  CachedDividendData({required this.data, required this.timestamp});
}
