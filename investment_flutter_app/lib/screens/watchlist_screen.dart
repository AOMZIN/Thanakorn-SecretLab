import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yahoo_finance_data_reader/yahoo_finance_data_reader.dart';
import '../models/stock_data.dart';
import 'stock_detail_screen.dart';

class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({super.key});

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  final List<String> _watchlist = ['AAPL', 'MSFT', 'GOOGL', 'AMZN', 'SPY', 'QQQ', 'VTI'];
  final Map<String, YahooFinanceResponse?> _stockData = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchWatchlistData();
  }

  Future<void> _fetchWatchlistData() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Use Future.wait to run API calls in parallel
      final futures = <Future<void>>[];

      for (final symbol in _watchlist) {
        // Check if we have valid cached data first
        if (StockDataCache.hasValidCache(symbol)) {
          setState(() {
            _stockData[symbol] = StockDataCache.getCachedData(symbol);
          });
          continue;
        }

        // If no valid cache, add to futures list for parallel fetching
        futures.add(_fetchStockData(symbol));
      }

      // Wait for all fetches to complete
      await Future.wait(futures);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching data: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

// Helper method to fetch individual stock data
  Future<void> _fetchStockData(String symbol) async {
    try {
      final response = await const YahooFinanceDailyReader().getDailyDTOs(symbol);
      if (!mounted) return;

      // Cache the response
      StockDataCache.cacheData(symbol, response);

      setState(() {
        _stockData[symbol] = response;
      });
    } catch (e) {
      print('Error fetching data for $symbol: $e');
      // Don't throw here - we want other stocks to continue loading
    }
  }

  void _removeFromWatchlist(String symbol) {
    setState(() {
      _watchlist.remove(symbol);
      _stockData.remove(symbol);
    });
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _fetchWatchlistData,
      child: _isLoading && _stockData.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
        itemCount: _watchlist.length,
        itemBuilder: (context, index) {
          final symbol = _watchlist[index];
          final data = _stockData[symbol];

          if (data == null || data.candlesData.isEmpty) {
            return ListTile(
              title: Text(symbol),
              subtitle: const Text('Loading...'),
            );
          }

          final latestCandle = data.candlesData.last;
          final previousCandle = data.candlesData.length > 1
              ? data.candlesData[data.candlesData.length - 2]
              : null;

          final change = previousCandle != null
              ? latestCandle.close - previousCandle.close
              : 0.0;
          final changePercent = previousCandle != null && previousCandle.close != 0
              ? (change / previousCandle.close) * 100
              : 0.0;

          final isPositive = change >= 0;

          return Dismissible(
            key: Key(symbol),
            direction: DismissDirection.endToStart,
            background: Container(
              color: Colors.red,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20.0),
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            onDismissed: (_) => _removeFromWatchlist(symbol),
            child: ListTile(
              title: Text(symbol),
              subtitle: Text(
                DateFormat('MMM d, yyyy').format(latestCandle.date),
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '\$${latestCandle.close.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${isPositive ? '+' : ''}${change.toStringAsFixed(2)} (${changePercent.toStringAsFixed(2)}%)',
                    style: TextStyle(
                      color: isPositive ? Colors.green : Colors.red,
                    ),
                  ),
                ],
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => StockDetailScreen(symbol: symbol),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
