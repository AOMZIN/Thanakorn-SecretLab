import 'package:yahoo_finance_data_reader/yahoo_finance_data_reader.dart';

// Cache implementation for stock data
class StockDataCache {
  static final Map<String, CachedStockData> _cache = {};
  static const Duration _cacheDuration = Duration(minutes: 15);

  static bool hasValidCache(String symbol) {
    if (!_cache.containsKey(symbol)) return false;
    final cached = _cache[symbol]!;
    return DateTime.now().difference(cached.timestamp) < _cacheDuration;
  }

  static YahooFinanceResponse? getCachedData(String symbol) {
    if (!hasValidCache(symbol)) return null;
    return _cache[symbol]!.data;
  }

  static void cacheData(String symbol, YahooFinanceResponse data) {
    _cache[symbol] = CachedStockData(data: data, timestamp: DateTime.now());
  }

  static void invalidateCache(String symbol) {
    _cache.remove(symbol);
  }

  static void clearAllCache() {
    _cache.clear();
  }
}

class CachedStockData {
  final YahooFinanceResponse data;
  final DateTime timestamp;

  CachedStockData({required this.data, required this.timestamp});
}