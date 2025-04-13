import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yahoo_finance_data_reader/yahoo_finance_data_reader.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' as math;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stock Market App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system,
      home: const StockMarketApp(),
    );
  }
}

// Add this class at the top level of your file, outside any widget
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

class StockMarketApp extends StatefulWidget {
  const StockMarketApp({super.key});

  @override
  State<StockMarketApp> createState() => _StockMarketAppState();
}

class _StockMarketAppState extends State<StockMarketApp> {
  int _selectedIndex = 0;
  final PageController _pageController = PageController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Market App'),
      ),
      body: PageView(
        physics: const NeverScrollableScrollPhysics(),
        controller: _pageController,
        onPageChanged: _onItemSelected,
        children: const [
          WatchlistScreen(),
          SearchScreen(),
          PortfolioScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        onTap: _onItemSelected,
        currentIndex: _selectedIndex,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.list),
            label: 'Watchlist',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.search),
            label: 'Search',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet),
            label: 'Portfolio',
          ),
        ],
      ),
    );
  }

  void _onItemSelected(int index) {
    setState(() {
      _pageController.animateToPage(index,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      _selectedIndex = index;
    });
  }
}

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

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  YahooFinanceResponse? _searchResult;
  bool _isLoading = false;
  String? _errorMessage;
  String? _selectedYear;

  Future<void> _searchStock() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await const YahooFinanceDailyReader().getDailyDTOs(query);
      if (!mounted) return;
      setState(() {
        _searchResult = response;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not find stock: $e';
        _searchResult = null;
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  List<YahooFinanceCandleData> _filterDataByYear(List<YahooFinanceCandleData> data) {
    if (_selectedYear == null) return data;
    final year = int.parse(_selectedYear!);
    return data.where((candle) => candle.date.year == year).toList();
  }

  @override
  Widget build(BuildContext context) {
    final years = _searchResult?.candlesData.map((candle) => candle.date.year).toSet().toList() ?? [];
    years.sort();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    labelText: 'Enter stock symbol',
                    border: OutlineInputBorder(),
                    hintText: 'e.g. AAPL, MSFT, SPY',
                  ),
                  onSubmitted: (_) => _searchStock(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _searchStock,
                child: const Text('Search'),
              ),
            ],
          ),
        ),
        if (years.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: DropdownButton<String>(
              hint: const Text('Select Year'),
              value: _selectedYear,
              onChanged: (String? newValue) {
                setState(() {
                  _selectedYear = newValue;
                });
              },
              items: years.map<DropdownMenuItem<String>>((int year) {
                return DropdownMenuItem<String>(
                  value: year.toString(),
                  child: Text(year.toString()),
                );
              }).toList(),
            ),
          ),
        if (_isLoading)
          const Expanded(
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_errorMessage != null)
          Expanded(
            child: Center(child: Text(_errorMessage!)),
          )
        else if (_searchResult != null)
            Expanded(
              child: SearchResultView(
                symbol: _searchController.text.toUpperCase(),
                response: _searchResult!,
                selectedYear: _selectedYear,
              ),
            )
          else
            const Expanded(
              child: Center(
                child: Text('Search for a stock symbol to see details'),
              ),
            ),
      ],
    );
  }
}

class SearchResultView extends StatelessWidget {
  final String symbol;
  final YahooFinanceResponse response;
  final String? selectedYear;

  const SearchResultView({
    Key? key,
    required this.symbol,
    required this.response,
    this.selectedYear,
  }) : super(key: key);

  List<YahooFinanceCandleData> _filterDataByYear(List<YahooFinanceCandleData> data) {
    if (selectedYear == null) return data;
    final year = int.parse(selectedYear!);
    return data.where((candle) => candle.date.year == year).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filteredData = _filterDataByYear(response.candlesData);

    if (filteredData.isEmpty) {
      return const Center(child: Text('No data available for this stock'));
    }

    final latestCandle = filteredData.last;
    final previousCandle = filteredData.length > 1
        ? filteredData[filteredData.length - 2]
        : null;

    final change = previousCandle != null
        ? latestCandle.close - previousCandle.close
        : 0.0;
    final changePercent = previousCandle != null && previousCandle.close != 0
        ? (change / previousCandle.close) * 100
        : 0.0;

    final isPositive = change >= 0;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                symbol,
                style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    '\$${latestCandle.close.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 20),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${isPositive ? '+' : ''}${change.toStringAsFixed(2)} (${changePercent.toStringAsFixed(2)}%)',
                    style: TextStyle(
                      color: isPositive ? Colors.green : Colors.red,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => StockDetailScreen(symbol: symbol),
                    ),
                  );
                },
                child: const Text('View Details'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: filteredData.length,
            itemBuilder: (context, index) {
              // Display in reverse chronological order
              final candle = filteredData[filteredData.length - 1 - index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        DateFormat('MMM d, yyyy').format(candle.date),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text('\$${candle.close.toStringAsFixed(2)}'),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class PortfolioScreen extends StatefulWidget {
  const PortfolioScreen({super.key});

  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  final List<Map<String, dynamic>> _portfolio = [];
  final Map<String, YahooFinanceResponse?> _stockData = {};
  final Map<String, List<Map<String, dynamic>>> _dividendData = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchPortfolioData();
  }

  Future<void> _fetchPortfolioData() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Use Future.wait for parallel API calls
      final stockFutures = <Future<void>>[];
      final dividendFutures = <Future<void>>[];

      for (final asset in _portfolio) {
        final symbol = asset['symbol'];

        // Add stock data fetch to futures
        stockFutures.add(_fetchPortfolioStockData(symbol));

        // Add dividend data fetch to futures
        dividendFutures.add(_fetchPortfolioDividendData(symbol));
      }

      // Execute all stock fetches in parallel
      await Future.wait(stockFutures);

      // Execute all dividend fetches in parallel
      await Future.wait(dividendFutures);

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching portfolio data: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchPortfolioStockData(String symbol) async {
    try {
      // Check cache first
      if (StockDataCache.hasValidCache(symbol)) {
        if (!mounted) return;
        setState(() {
          _stockData[symbol] = StockDataCache.getCachedData(symbol);
        });
        return;
      }

      // Fetch if not in cache
      final response = await const YahooFinanceDailyReader().getDailyDTOs(symbol);

      if (!mounted) return;

      // Cache the response
      StockDataCache.cacheData(symbol, response);

      setState(() {
        _stockData[symbol] = response;
      });
    } catch (e) {
      print('Error fetching stock data for $symbol: $e');
    }
  }

  Future<void> _fetchPortfolioDividendData(String symbol) async {
    try {
      final dividendData = await DividendService.fetchDividendData(symbol);

      if (!mounted) return;
      setState(() {
        _dividendData[symbol] = dividendData;
      });
    } catch (e) {
      print('Error fetching dividend data for $symbol: $e');
    }
  }

  Future<List<Map<String, dynamic>>> _fetchDividendData(String symbol) async {
    final apiKey = 'OICQLJJPW42HGD9Y'; // Replace with your actual Alpha Vantage API key
    final url = 'https://www.alphavantage.co/query?function=TIME_SERIES_MONTHLY_ADJUSTED&symbol=$symbol&apikey=$apiKey';

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
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

      return dividendData;
    } else {
      throw Exception('Failed to load dividend data');
    }
  }

  void _addToPortfolio(String symbol, DateTime date, double shares) {
    setState(() {
      _portfolio.add({'symbol': symbol, 'date': date, 'shares': shares});
      _fetchPortfolioData();
    });
  }

  void _removeFromPortfolio(String symbol) {
    setState(() {
      _portfolio.removeWhere((asset) => asset['symbol'] == symbol);
      _stockData.remove(symbol);
      _dividendData.remove(symbol);
    });
  }

  double _calculatePortfolioPerformance() {
    double totalInvestment = 0;
    double totalCurrentValue = 0;

    for (final asset in _portfolio) {
      final symbol = asset['symbol'];
      final date = asset['date'];
      final shares = asset['shares'];
      final data = _stockData[symbol];

      if (data == null || data.candlesData.isEmpty) continue;

      final purchaseCandle = data.candlesData.firstWhere(
            (candle) => candle.date.isAfter(date) || candle.date.isAtSameMomentAs(date),
        orElse: () => data.candlesData.first,
      );
      final latestCandle = data.candlesData.last;

      totalInvestment += purchaseCandle.close * shares;
      totalCurrentValue += latestCandle.close * shares;
    }

    return totalCurrentValue - totalInvestment;
  }

  double _calculateAnnualDividendIncome(List<Map<String, dynamic>> dividendData) {
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

  double _calculateMonthlyDividendIncome(List<Map<String, dynamic>> dividendData) {
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

  double _calculateDailyDividendIncome(List<Map<String, dynamic>> dividendData) {
    double totalDividend = 0;
    final now = DateTime.now();
    final oneDayAgo = now.subtract(const Duration(days: 1));

    for (final dividend in dividendData) {
      final date = dividend['date'] as DateTime;
      if (date.isAfter(oneDayAgo)) {
        totalDividend += dividend['dividend'] as double;
      }
    }

    return totalDividend;
  }

  double _calculateDividendYield(double annualDividendIncome, double currentPrice) {
    if (currentPrice == 0) return 0;
    return (annualDividendIncome / currentPrice) * 100;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Portfolio'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _portfolio.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.account_balance_wallet, size: 80, color: Colors.blue),
            const SizedBox(height: 16),
            const Text(
              'Your Portfolio is Empty',
              style: TextStyle(fontSize: 20),
            ),
            const SizedBox(height: 8),
            Text(
              'Add stocks to your portfolio to track them',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      )
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Portfolio Performance',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Total Gain/Loss: \$${_calculatePortfolioPerformance().toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              'Dividend Information Summary',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          _buildDividendSummary(),
          Expanded(
            child: ListView.builder(
              itemCount: _portfolio.length,
              itemBuilder: (context, index) {
                final asset = _portfolio[index];
                final symbol = asset['symbol'];
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
                  onDismissed: (_) => _removeFromPortfolio(symbol),
                  child: ListTile(
                    title: Text(symbol),
                    subtitle: Text(
                      'Shares: ${asset['shares'].toStringAsFixed(6)} | Date: ${DateFormat('MMM d, yyyy').format(asset['date'])}',
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
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) {
              final TextEditingController _controller = TextEditingController();
              final TextEditingController _sharesController = TextEditingController();
              final TextEditingController _amountController = TextEditingController();
              DateTime? _selectedDate;
              bool _isSharesSelected = true;

              return AlertDialog(
                title: const Text('Add Stock to Portfolio'),
                content: StatefulBuilder(
                  builder: (context, setState) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: _controller,
                          decoration: const InputDecoration(
                            labelText: 'Enter stock symbol',
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Text('Enter:'),
                            const SizedBox(width: 8),
                            Row(
                              children: [
                                Radio<bool>(
                                  value: true,
                                  groupValue: _isSharesSelected,
                                  onChanged: (value) {
                                    setState(() {
                                      _isSharesSelected = value!;
                                    });
                                  },
                                ),
                                const Text('Shares'),
                              ],
                            ),
                            Row(
                              children: [
                                Radio<bool>(
                                  value: false,
                                  groupValue: _isSharesSelected,
                                  onChanged: (value) {
                                    setState(() {
                                      _isSharesSelected = value!;
                                    });
                                  },
                                ),
                                const Text('Amount (\$)'),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (_isSharesSelected)
                          TextField(
                            controller: _sharesController,
                            decoration: const InputDecoration(
                              labelText: 'Enter number of shares',
                            ),
                            keyboardType: TextInputType.number,
                          )
                        else
                          TextField(
                            controller: _amountController,
                            decoration: const InputDecoration(
                              labelText: 'Enter amount in \$',
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now(),
                              firstDate: DateTime(2000),
                              lastDate: DateTime.now(),
                            );
                            if (date != null) {
                              setState(() {
                                _selectedDate = date;
                              });
                            }
                          },
                          child: const Text('Select Date'),
                        ),
                        if (_selectedDate != null)
                          Text('Selected Date: ${DateFormat('MMM d, yyyy').format(_selectedDate!)}'),
                      ],
                    );
                  },
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      final symbol = _controller.text.trim().toUpperCase();
                      if (symbol.isNotEmpty && _selectedDate != null) {
                        final response = await const YahooFinanceDailyReader().getDailyDTOs(symbol);
                        if (response != null && response.candlesData.isNotEmpty) {
                          final purchaseCandle = response.candlesData.firstWhere(
                                (candle) => candle.date.isAfter(_selectedDate!) || candle.date.isAtSameMomentAs(_selectedDate!),
                            orElse: () => response.candlesData.first,
                          );

                          if (purchaseCandle.close == 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: Close price is zero')),
                            );
                            return;
                          }

                          double shares;
                          if (_isSharesSelected) {
                            shares = double.tryParse(_sharesController.text.trim()) ?? 0.0;
                          } else {
                            final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;
                            if (amount <= 0) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error: Amount must be greater than zero')),
                              );
                              return;
                            }

                            shares = amount / purchaseCandle.close;
                          }

                          if (shares > 0) {
                            _addToPortfolio(symbol, _selectedDate!, shares);
                          }
                        }
                      }
                      Navigator.of(context).pop();
                    },
                    child: const Text('Add'),
                  ),
                ],
              );
            },
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildDividendSummary() {
    if (_dividendData.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text(
          'No dividend information available for the assets in your portfolio.',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final asset in _portfolio)
            _buildDividendSummaryForAsset(asset['symbol']),
        ],
      ),
    );
  }

  Widget _buildDividendSummaryForAsset(String symbol) {
    final dividendData = _dividendData[symbol];
    if (dividendData == null || dividendData.isEmpty) {
      return const SizedBox();
    }

    final annualDividendIncome = DividendService.calculateAnnualDividendIncome(dividendData);
    final monthlyDividendIncome = _calculateMonthlyDividendIncome(dividendData);
    final dailyDividendIncome = _calculateDailyDividendIncome(dividendData);
    final currentPrice = _stockData[symbol]?.candlesData.last.close ?? 0.0;
    final dividendYield = _calculateDividendYield(annualDividendIncome, currentPrice);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          symbol,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        _buildInfoRow('Annual Dividend Income', '\$${annualDividendIncome.toStringAsFixed(2)}'),
        _buildInfoRow('Monthly Dividend Income', '\$${monthlyDividendIncome.toStringAsFixed(2)}'),
        _buildInfoRow('Daily Dividend Income', '\$${dailyDividendIncome.toStringAsFixed(2)}'),
        _buildInfoRow('Dividend Yield', '${dividendYield.toStringAsFixed(2)}%'),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value),
        ],
      ),
    );
  }
}

class StockDetailScreen extends StatefulWidget {
  final String symbol;

  const StockDetailScreen({Key? key, required this.symbol}) : super(key: key);

  @override
  _StockDetailScreenState createState() => _StockDetailScreenState();
}

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

class _StockDetailScreenState extends State<StockDetailScreen> {
  YahooFinanceResponse? _stockData;
  List<Map<String, dynamic>>? _dividendData;
  bool _isLoading = true;
  String _timeRange = '1mo'; // 1d, 5d, 1mo, 3mo, 6mo, 1y, 2y, 5y, 10y, ytd, max

  // For tracking zoom/pan position
  ZoomPanBehavior? _zoomPanBehavior;

  @override
  void initState() {
    super.initState();
    _zoomPanBehavior = ZoomPanBehavior(
      enablePinching: true,
      enableDoubleTapZooming: true,
      enablePanning: true,
    );
    _fetchData();
  }

  Future<void> _fetchData() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      YahooFinanceResponse? response;

      // Check cache first
      if (StockDataCache.hasValidCache(widget.symbol)) {
        response = StockDataCache.getCachedData(widget.symbol);
      } else {
        // Fetch new data if not in cache
        final yahooFinanceReader = YahooFinanceDailyReader();
        response = await yahooFinanceReader.getDailyDTOs(widget.symbol);

        // Cache the new data
        if (response != null) {
          StockDataCache.cacheData(widget.symbol, response);
        }
      }

      // Filter the response based on _timeRange
      final filteredData = response != null ?
      _filterDataByTimeRange(response.candlesData) :
      <YahooFinanceCandleData>[];

      // Fetch dividend data using our service
      final dividendResponse = await DividendService.fetchDividendData(widget.symbol);

      if (!mounted) return;

      setState(() {
        _stockData = YahooFinanceResponse(candlesData: filteredData);
        _dividendData = dividendResponse;
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading stock data: ${e.toString().substring(0, math.min(e.toString().length, 100))}')),
      );
    } finally {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _fetchDividendData(String symbol) async {
    final apiKey = 'OICQLJJPW42HGD9Y'; // Replace with your actual Alpha Vantage API key
    final url = 'https://www.alphavantage.co/query?function=TIME_SERIES_MONTHLY_ADJUSTED&symbol=$symbol&apikey=$apiKey';

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
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

      return dividendData;
    } else {
      throw Exception('Failed to load dividend data');
    }
  }

  List<YahooFinanceCandleData> _filterDataByTimeRange(List<YahooFinanceCandleData> data) {
    final now = DateTime.now();
    DateTime startDate;

    switch (_timeRange) {
      case '1d':
        startDate = now.subtract(const Duration(days: 1));
        break;
      case '5d':
        startDate = now.subtract(const Duration(days: 5));
        break;
      case '1mo':
        startDate = now.subtract(const Duration(days: 30));
        break;
      case '3mo':
        startDate = now.subtract(const Duration(days: 90));
        break;
      case '6mo':
        startDate = now.subtract(const Duration(days: 180));
        break;
      case '1y':
        startDate = now.subtract(const Duration(days: 365));
        break;
      case '5y':
        startDate = now.subtract(const Duration(days: 1825));
        break;
      case 'max':
        startDate = DateTime(1970); // Assuming data starts from 1970
        break;
      default:
        startDate = now.subtract(const Duration(days: 30));
    }

    return data.where((candle) => candle.date.isAfter(startDate)).toList();
  }

  double _calculateAnnualDividendIncome(List<Map<String, dynamic>> dividendData) {
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

  double _calculateMonthlyDividendIncome(List<Map<String, dynamic>> dividendData) {
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

  double _calculateDailyDividendIncome(List<Map<String, dynamic>> dividendData) {
    double totalDividend = 0;
    final now = DateTime.now();
    final oneDayAgo = now.subtract(const Duration(days: 1));

    for (final dividend in dividendData) {
      final date = dividend['date'] as DateTime;
      if (date.isAfter(oneDayAgo)) {
        totalDividend += dividend['dividend'] as double;
      }
    }

    return totalDividend;
  }

  double _calculateDividendYield(double annualDividendIncome, double currentPrice) {
    if (currentPrice == 0) return 0;
    return (annualDividendIncome / currentPrice) * 100;
  }

  double _calculateYieldOnCost(double annualDividendIncome, double purchasePrice) {
    if (purchasePrice == 0) return 0;
    return (annualDividendIncome / purchasePrice) * 100;
  }

  @override
  Widget build(BuildContext context) {
    final formatCurrency = NumberFormat.currency(symbol: '\$');

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.symbol),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _stockData == null || _stockData!.candlesData.isEmpty
          ? const Center(child: Text('Failed to load stock data'))
          : SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.symbol,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        formatCurrency.format(_stockData!.candlesData.last.close),
                        style: const TextStyle(fontSize: 20),
                      ),
                      const SizedBox(width: 8),
                      _buildChangeText(),
                    ],
                  ),
                ],
              ),
            ),
            _buildSyncfusionChart(),
            _buildTimeRangeSelector(),
            _buildStockInfo(),
            _buildDividendInfo(),
            _buildDividendCalculations(),
          ],
        ),
      ),
    );
  }

  Widget _buildChangeText() {
    if (_stockData!.candlesData.length < 2) return const SizedBox();

    final latestCandle = _stockData!.candlesData.last;
    final previousCandle = _stockData!.candlesData[_stockData!.candlesData.length - 2];

    final change = latestCandle.close - previousCandle.close;
    final changePercent = (change / previousCandle.close) * 100;
    final isPositive = change >= 0;

    return Text(
      '${isPositive ? '+' : ''}${change.toStringAsFixed(2)} (${changePercent.toStringAsFixed(2)}%)',
      style: TextStyle(
        color: isPositive ? Colors.green : Colors.red,
        fontSize: 16,
      ),
    );
  }

  Widget _buildTimeRangeSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _timeRangeButton('1D', '1d'),
            _timeRangeButton('1W', '5d'),
            _timeRangeButton('1M', '1mo'),
            _timeRangeButton('3M', '3mo'),
            _timeRangeButton('6M', '6mo'),
            _timeRangeButton('1Y', '1y'),
            _timeRangeButton('5Y', '5y'),
            _timeRangeButton('Max', 'max'),
          ],
        ),
      ),
    );
  }

  Widget _timeRangeButton(String label, String range) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: ElevatedButton(
        onPressed: () {
          setState(() {
            _timeRange = range;
          });
          _fetchData();
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: _timeRange == range ? Theme.of(context).primaryColor : null,
        ),
        child: Text(label),
      ),
    );
  }

  Widget _buildSyncfusionChart() {
    if (_stockData == null || _stockData!.candlesData.isEmpty) {
      return const SizedBox(height: 300, child: Center(child: Text('No chart data available')));
    }

    // Use a more efficient way to determine if price is up or down
    final candles = _stockData!.candlesData;
    final isPositive = candles.length > 1 ? candles.last.close >= candles[candles.length - 2].close : true;

    final Color chartColor = isPositive ? Colors.green : Colors.red;

    // Optimize date formatting by preparing it outside the build method
    final DateFormat xAxisLabelFormat = _getAxisDateFormat();

    // Memoize the chart to prevent unnecessary rebuilds
    return Container(
      height: 350,
      padding: const EdgeInsets.all(8),
      child: SfCartesianChart(
        plotAreaBorderWidth: 0,
        primaryXAxis: DateTimeAxis(
          dateFormat: xAxisLabelFormat,
          majorGridLines: const MajorGridLines(width: 0),
          intervalType: _getIntervalType(),
          // Add auto range padding for better visualization
          rangePadding: ChartRangePadding.additional,
        ),
        primaryYAxis: NumericAxis(
          numberFormat: NumberFormat.currency(symbol: '\$', decimalDigits: 2),
          axisLine: const AxisLine(width: 0),
          majorTickLines: const MajorTickLines(size: 0),
          // Add this for better visualization
          rangePadding: ChartRangePadding.additional,
        ),
        series: <CartesianSeries>[
          // Use FastLineSeries for better performance with large datasets
          FastLineSeries<YahooFinanceCandleData, DateTime>(
            dataSource: _stockData!.candlesData,
            xValueMapper: (YahooFinanceCandleData data, _) => data.date,
            yValueMapper: (YahooFinanceCandleData data, _) => data.close,
            name: 'Price',
            color: chartColor,
            width: 2,
          ),
          AreaSeries<YahooFinanceCandleData, DateTime>(
            dataSource: _stockData!.candlesData,
            xValueMapper: (YahooFinanceCandleData data, _) => data.date,
            yValueMapper: (YahooFinanceCandleData data, _) => data.close,
            name: 'Price Area',
            color: chartColor.withOpacity(0.2),
            borderColor: chartColor,
            borderWidth: 1,
          ),
        ],
        tooltipBehavior: TooltipBehavior(enable: true),
        zoomPanBehavior: _zoomPanBehavior,
        trackballBehavior: TrackballBehavior(
          enable: true,
          activationMode: ActivationMode.singleTap,
          tooltipSettings: const InteractiveTooltip(
            enable: true,
            format: 'point.x: \$point.y',
          ),
        ),
      ),
    );
  }

// Helper method to get the appropriate date format
  DateFormat _getAxisDateFormat() {
    switch (_timeRange) {
      case '1d':
      case '5d':
        return DateFormat('h:mm a');
      case '1mo':
      case '3mo':
        return DateFormat('MMM d');
      case '6mo':
      case '1y':
        return DateFormat('MMM yyyy');
      default:
        return DateFormat('yyyy');
    }
  }

  DateTimeIntervalType _getIntervalType() {
    switch (_timeRange) {
      case '1d':
        return DateTimeIntervalType.hours;
      case '5d':
        return DateTimeIntervalType.hours;
      case '1mo':
        return DateTimeIntervalType.days;
      case '3mo':
        return DateTimeIntervalType.days;
      case '6mo':
        return DateTimeIntervalType.months;
      case '1y':
        return DateTimeIntervalType.months;
      case '5y':
        return DateTimeIntervalType.years;
      case 'max':
        return DateTimeIntervalType.years;
      default:
        return DateTimeIntervalType.days;
    }
  }

  Widget _buildStockInfo() {
    if (_stockData == null || _stockData!.candlesData.isEmpty) {
      return const SizedBox();
    }

    final latestCandle = _stockData!.candlesData.last;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Stock Information',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _buildInfoRow('Date', DateFormat('yyyy-MM-dd').format(latestCandle.date)),
          _buildInfoRow('Open', '\$${latestCandle.open.toStringAsFixed(2)}'),
          _buildInfoRow('High', '\$${latestCandle.high.toStringAsFixed(2)}'),
          _buildInfoRow('Low', '\$${latestCandle.low.toStringAsFixed(2)}'),
          _buildInfoRow('Close', '\$${latestCandle.close.toStringAsFixed(2)}'),
          _buildInfoRow('Adjusted Close', '\$${latestCandle.adjClose.toStringAsFixed(2)}'),
          _buildInfoRow('Volume', NumberFormat.decimalPattern().format(latestCandle.volume)),
        ],
      ),
    );
  }

  Widget _buildDividendInfo() {
    if (_dividendData == null || _dividendData!.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text(
          'No dividend information available for this stock.',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Dividend Information',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _dividendData!.length,
            itemBuilder: (context, index) {
              final dividend = _dividendData![index];
              return _buildInfoRow(
                'Date: ${DateFormat('yyyy-MM-dd').format(dividend['date'])}',
                '\$${dividend['dividend'].toStringAsFixed(2)}',
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDividendCalculations() {
    if (_dividendData == null || _dividendData!.isEmpty || _stockData == null || _stockData!.candlesData.isEmpty) {
      return const SizedBox();
    }

    final annualDividendIncome = _calculateAnnualDividendIncome(_dividendData!);
    final monthlyDividendIncome = _calculateMonthlyDividendIncome(_dividendData!);
    final dailyDividendIncome = _calculateDailyDividendIncome(_dividendData!);
    final currentPrice = _stockData!.candlesData.last.close;
    final dividendYield = _calculateDividendYield(annualDividendIncome, currentPrice);

    // For yield on cost, we need the purchase price which is not available in this context.
    // You can add a field to store the purchase price in your data model and pass it to this method.
    // double yieldOnCost = _calculateYieldOnCost(annualDividendIncome, purchasePrice);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Dividend Calculations',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _buildInfoRow('Annual Dividend Income', '\$${annualDividendIncome.toStringAsFixed(2)}'),
          _buildInfoRow('Monthly Dividend Income', '\$${monthlyDividendIncome.toStringAsFixed(2)}'),
          _buildInfoRow('Daily Dividend Income', '\$${dailyDividendIncome.toStringAsFixed(2)}'),
          _buildInfoRow('Dividend Yield', '${dividendYield.toStringAsFixed(2)}%'),
          // _buildInfoRow('Yield on Cost', '${yieldOnCost.toStringAsFixed(2)}%'),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value),
        ],
      ),
    );
  }
}
