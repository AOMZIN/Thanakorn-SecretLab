import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yahoo_finance_data_reader/yahoo_finance_data_reader.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

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
    setState(() {
      _isLoading = true;
    });

    try {
      for (final symbol in _watchlist) {
        final response = await const YahooFinanceDailyReader().getDailyDTOs(symbol);
        setState(() {
          _stockData[symbol] = response;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching data: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
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

  Future<void> _searchStock() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await const YahooFinanceDailyReader().getDailyDTOs(query);
      setState(() {
        _searchResult = response;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Could not find stock: $e';
        _searchResult = null;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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

  const SearchResultView({
    super.key,
    required this.symbol,
    required this.response,
  });

  @override
  Widget build(BuildContext context) {
    if (response.candlesData.isEmpty) {
      return const Center(child: Text('No data available for this stock'));
    }

    final latestCandle = response.candlesData.last;
    final previousCandle = response.candlesData.length > 1
        ? response.candlesData[response.candlesData.length - 2]
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
            itemCount: response.candlesData.length,
            itemBuilder: (context, index) {
              // Display in reverse chronological order
              final candle = response.candlesData[response.candlesData.length - 1 - index];
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

class PortfolioScreen extends StatelessWidget {
  const PortfolioScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.account_balance_wallet, size: 80, color: Colors.blue),
          const SizedBox(height: 16),
          const Text(
            'Portfolio Feature Coming Soon',
            style: TextStyle(fontSize: 20),
          ),
          const SizedBox(height: 8),
          Text(
            'Track your investments and monitor performance',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}

class StockDetailScreen extends StatefulWidget {
  final String symbol;

  const StockDetailScreen({super.key, required this.symbol});

  @override
  _StockDetailScreenState createState() => _StockDetailScreenState();
}

class _StockDetailScreenState extends State<StockDetailScreen> {
  YahooFinanceResponse? _stockData;
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
    setState(() {
      _isLoading = true;
    });

    try {
      // Get the appropriate interval based on time range
      String interval = '1d';
      if (_timeRange == '1d') {
        interval = '5m';
      } else if (_timeRange == '5d') interval = '30m';

      // Use the standard constructor without named parameters
      // The package doesn't support interval and period as named parameters
      final yahooFinanceReader = YahooFinanceDailyReader();
      final response = await yahooFinanceReader.getDailyDTOs(widget.symbol);

      // TODO: Filter the response based on _timeRange if needed
      // This would require implementing custom filtering logic

      setState(() {
        _stockData = response;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching data: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
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

    // Determine if price is up or down from previous close
    final isPositive = _stockData!.candlesData.length > 1
        ? _stockData!.candlesData.last.close >= _stockData!.candlesData[_stockData!.candlesData.length - 2].close
        : true;

    final Color chartColor = isPositive ? Colors.green : Colors.red;

    // Determine if we should show time or date on the x-axis
    final bool showTimeOnXAxis = _timeRange == '1d' || _timeRange == '5d';
    final DateFormat xAxisLabelFormat = showTimeOnXAxis
        ? DateFormat('h:mm a')
        : _timeRange == '1mo' || _timeRange == '3mo'
        ? DateFormat('MMM d')
        : DateFormat('MMM yyyy');

    return Container(
      height: 350,
      padding: const EdgeInsets.all(8),
      child: SfCartesianChart(
        plotAreaBorderWidth: 0,
        primaryXAxis: DateTimeAxis(
          dateFormat: xAxisLabelFormat,
          majorGridLines: const MajorGridLines(width: 0),
          intervalType: _getIntervalType(),
        ),
        primaryYAxis: NumericAxis(
          numberFormat: NumberFormat.currency(symbol: '\$', decimalDigits: 2),
          axisLine: const AxisLine(width: 0),
          majorTickLines: const MajorTickLines(size: 0),
        ),
        series: <CartesianSeries>[
          // Line series for price
          LineSeries<YahooFinanceCandleData, DateTime>(
            dataSource: _stockData!.candlesData,
            xValueMapper: (YahooFinanceCandleData data, _) => data.date,
            yValueMapper: (YahooFinanceCandleData data, _) => data.close,
            name: 'Price',
            color: chartColor,
            width: 2,
          ),
          // Area series for visual appeal
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