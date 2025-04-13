import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yahoo_finance_data_reader/yahoo_finance_data_reader.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' as math;

void main() => runApp(const MyApp());

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

// Enhanced StockDataCache with improved error handling and expiration logic
class StockDataCache {
  static final Map<String, CachedStockData> _cache = {};
  static const Duration _cacheDuration = Duration(minutes: 15);

  static bool hasValidCache(String symbol) {
    final cached = _cache[symbol];
    return cached != null &&
        DateTime.now().difference(cached.timestamp) < _cacheDuration;
  }

  static YahooFinanceResponse? getCachedData(String symbol) =>
      hasValidCache(symbol) ? _cache[symbol]!.data : null;

  static void cacheData(String symbol, YahooFinanceResponse data) {
    _cache[symbol] = CachedStockData(
        data: data,
        timestamp: DateTime.now()
    );
  }

  static void invalidateCache(String symbol) => _cache.remove(symbol);
  static void clearAllCache() => _cache.clear();
}

class CachedStockData {
  final YahooFinanceResponse data;
  final DateTime timestamp;

  const CachedStockData({required this.data, required this.timestamp});
}

// DividendService with enhanced caching and error handling
class DividendService {
  static const String _apiKey = 'OICQLJJPW42HGD9Y';
  static final Map<String, CachedDividendData> _cache = {};
  static const Duration _cacheDuration = Duration(days: 1);

  static Future<List<Map<String, dynamic>>> fetchDividendData(String symbol) async {
    // Check cache first
    if (_cache.containsKey(symbol) &&
        DateTime.now().difference(_cache[symbol]!.timestamp) < _cacheDuration) {
      return _cache[symbol]!.data;
    }

    try {
      final response = await http.get(Uri.parse(
          'https://www.alphavantage.co/query?function=TIME_SERIES_MONTHLY_ADJUSTED&symbol=$symbol&apikey=$_apiKey'
      )).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw Exception('Failed to load dividend data: ${response.statusCode}');
      }

      final data = json.decode(response.body);

      // Check for API errors
      if (data.containsKey('Error Message') || !data.containsKey('Monthly Adjusted Time Series')) {
        return [];
      }

      final timeSeries = data['Monthly Adjusted Time Series'] as Map<String, dynamic>;
      final dividendData = <Map<String, dynamic>>[];

      for (final entry in timeSeries.entries) {
        final date = DateTime.parse(entry.key);
        final dividend = double.tryParse(entry.value['7. dividend amount'] ?? '0.0000') ?? 0.0;

        if (dividend > 0.0) {
          dividendData.add({
            'date': date,
            'dividend': dividend,
          });
        }
      }

      // Cache the result
      _cache[symbol] = CachedDividendData(
        data: dividendData,
        timestamp: DateTime.now(),
      );

      return dividendData;
    } catch (e) {
      print('Error fetching dividend data for $symbol: $e');
      return [];
    }
  }

  // Optimized dividend income calculation methods
  static double calculateDividendIncome(List<Map<String, dynamic>> dividendData, int days) {
    if (dividendData.isEmpty) return 0;

    final now = DateTime.now();
    final cutoffDate = now.subtract(Duration(days: days));

    return dividendData
        .where((dividend) => (dividend['date'] as DateTime).isAfter(cutoffDate))
        .fold(0.0, (sum, dividend) => sum + (dividend['dividend'] as double));
  }

  static double calculateAnnualDividendIncome(List<Map<String, dynamic>> dividendData) =>
      calculateDividendIncome(dividendData, 365);

  static double calculateMonthlyDividendIncome(List<Map<String, dynamic>> dividendData) =>
      calculateDividendIncome(dividendData, 30);

  static double calculateDailyDividendIncome(List<Map<String, dynamic>> dividendData) =>
      calculateAnnualDividendIncome(dividendData) / 365;

  static double calculateDividendYield(double annualDividendIncome, double currentPrice) =>
      currentPrice <= 0 ? 0 : (annualDividendIncome / currentPrice) * 100;
}

class CachedDividendData {
  final List<Map<String, dynamic>> data;
  final DateTime timestamp;

  const CachedDividendData({required this.data, required this.timestamp});
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
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

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

// More efficient StockDetailScreen with optimized rendering and data handling
class StockDetailScreen extends StatefulWidget {
  final String symbol;

  const StockDetailScreen({Key? key, required this.symbol}) : super(key: key);

  @override
  State<StockDetailScreen> createState() => _StockDetailScreenState();
}

class _StockDetailScreenState extends State<StockDetailScreen> {
  YahooFinanceResponse? _stockData;
  List<Map<String, dynamic>>? _dividendData;
  bool _isLoading = true;
  String _timeRange = '1mo';
  final ZoomPanBehavior _zoomPanBehavior = ZoomPanBehavior(
    enablePinching: true,
    enableDoubleTapZooming: true,
    enablePanning: true,
  );

  // Cache of formatted values to avoid repetitive formatting
  final Map<String, String> _formattedCache = {};
  final NumberFormat _currencyFormat = NumberFormat.currency(symbol: '\$');

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Parallel data fetching
      final stockDataFuture = _fetchStockData();
      final dividendDataFuture = DividendService.fetchDividendData(widget.symbol);

      final results = await Future.wait([stockDataFuture, dividendDataFuture]);

      if (!mounted) return;

      setState(() {
        _stockData = results[0] as YahooFinanceResponse?;
        _dividendData = results[1] as List<Map<String, dynamic>>;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString().substring(0, math.min(e.toString().length, 100))}')),
      );

      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<YahooFinanceResponse?> _fetchStockData() async {
    try {
      // Try cache first
      if (StockDataCache.hasValidCache(widget.symbol)) {
        final cachedData = StockDataCache.getCachedData(widget.symbol);
        final filteredData = _filterDataByTimeRange(cachedData!.candlesData);
        return YahooFinanceResponse(candlesData: filteredData);
      }

      // Fetch new data if not in cache
      final response = await const YahooFinanceDailyReader().getDailyDTOs(widget.symbol);

      // Cache the response
      StockDataCache.cacheData(widget.symbol, response);

      // Filter by time range
      final filteredData = _filterDataByTimeRange(response.candlesData);
      return YahooFinanceResponse(candlesData: filteredData);
    } catch (e) {
      print('Error fetching stock data: $e');
      return null;
    }
  }

  List<YahooFinanceCandleData> _filterDataByTimeRange(List<YahooFinanceCandleData> data) {
    final now = DateTime.now();
    final Map<String, int> rangeDays = {
      '1d': 1,
      '5d': 5,
      '1mo': 30,
      '3mo': 90,
      '6mo': 180,
      '1y': 365,
      '5y': 1825,
      'max': 20000, // ~55 years
    };

    final days = rangeDays[_timeRange] ?? 30;
    final startDate = now.subtract(Duration(days: days));

    return data.where((candle) => candle.date.isAfter(startDate)).toList();
  }

  // Memoized formatting function to avoid repeated work
  String _formatCurrency(double value) {
    final key = 'currency_$value';
    return _formattedCache[key] ??= _currencyFormat.format(value);
  }

  @override
  Widget build(BuildContext context) {
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
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          _buildSyncfusionChart(),
          _buildTimeRangeSelector(),
          _buildStockInfo(),
          if (_dividendData != null && _dividendData!.isNotEmpty) ...[
            _buildDividendInfo(),
            _buildDividendCalculations(),
          ] else
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('No dividend information available for this stock.'),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final latestCandle = _stockData!.candlesData.last;

    return Padding(
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
                _formatCurrency(latestCandle.close),
                style: const TextStyle(fontSize: 20),
              ),
              const SizedBox(width: 8),
              _buildChangeText(),
            ],
          ),
        ],
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

  Widget _buildSyncfusionChart() {
    if (_stockData == null || _stockData!.candlesData.isEmpty) {
      return const SizedBox(height: 300, child: Center(child: Text('No chart data available')));
    }

    final candles = _stockData!.candlesData;
    final isPositive = candles.length > 1 ? candles.last.close >= candles[candles.length - 2].close : true;
    final chartColor = isPositive ? Colors.green : Colors.red;

    return Container(
      height: 350,
      padding: const EdgeInsets.all(8),
      child: SfCartesianChart(
        plotAreaBorderWidth: 0,
        primaryXAxis: DateTimeAxis(
          dateFormat: _getAxisDateFormat(),
          majorGridLines: const MajorGridLines(width: 0),
          intervalType: _getIntervalType(),
          rangePadding: ChartRangePadding.additional,
        ),
        primaryYAxis: NumericAxis(
          numberFormat: NumberFormat.currency(symbol: '\$', decimalDigits: 2),
          axisLine: const AxisLine(width: 0),
          majorTickLines: const MajorTickLines(size: 0),
          rangePadding: ChartRangePadding.additional,
        ),
        series: <CartesianSeries>[
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

  DateFormat _getAxisDateFormat() {
    switch (_timeRange) {
      case '1d':
      case '5d': return DateFormat('h:mm a');
      case '1mo':
      case '3mo': return DateFormat('MMM d');
      case '6mo':
      case '1y': return DateFormat('MMM yyyy');
      default: return DateFormat('yyyy');
    }
  }

  DateTimeIntervalType _getIntervalType() {
    switch (_timeRange) {
      case '1d':
      case '5d': return DateTimeIntervalType.hours;
      case '1mo':
      case '3mo': return DateTimeIntervalType.days;
      case '6mo':
      case '1y': return DateTimeIntervalType.months;
      case '5y':
      case 'max': return DateTimeIntervalType.years;
      default: return DateTimeIntervalType.days;
    }
  }

  Widget _buildTimeRangeSelector() {
    final List<Map<String, String>> timeRanges = [
      {'label': '1D', 'value': '1d'},
      {'label': '1W', 'value': '5d'},
      {'label': '1M', 'value': '1mo'},
      {'label': '3M', 'value': '3mo'},
      {'label': '6M', 'value': '6mo'},
      {'label': '1Y', 'value': '1y'},
      {'label': '5Y', 'value': '5y'},
      {'label': 'Max', 'value': 'max'},
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: timeRanges.map((range) => _timeRangeButton(
            range['label']!,
            range['value']!,
          )).toList(),
        ),
      ),
    );
  }

  Widget _timeRangeButton(String label, String range) {
    final bool isSelected = _timeRange == range;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: ElevatedButton(
        onPressed: () {
          if (_timeRange != range) {
            setState(() {
              _timeRange = range;
            });
            _fetchData();
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: isSelected ? Theme.of(context).primaryColor : null,
        ),
        child: Text(label),
      ),
    );
  }

  Widget _buildStockInfo() {
    if (_stockData == null || _stockData!.candlesData.isEmpty) {
      return const SizedBox();
    }

    final latestCandle = _stockData!.candlesData.last;
    final dateFormat = DateFormat('yyyy-MM-dd');
    final numberFormat = NumberFormat.decimalPattern();

    final List<List<String>> rows = [
      ['Date', dateFormat.format(latestCandle.date)],
      ['Open', '\$${latestCandle.open.toStringAsFixed(2)}'],
      ['High', '\$${latestCandle.high.toStringAsFixed(2)}'],
      ['Low', '\$${latestCandle.low.toStringAsFixed(2)}'],
      ['Close', '\$${latestCandle.close.toStringAsFixed(2)}'],
      ['Adjusted Close', '\$${latestCandle.adjClose.toStringAsFixed(2)}'],
      ['Volume', numberFormat.format(latestCandle.volume)],
    ];

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
          ...rows.map((row) => _buildInfoRow(row[0], row[1])),
        ],
      ),
    );
  }

  Widget _buildDividendInfo() {
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
          // Use ListView.builder more efficiently with a fixed item count
          SizedBox(
            height: 200, // Fixed height or use constrainedBox
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _dividendData!.length,
              itemBuilder: (context, index) {
                final dividend = _dividendData![index];
                return _buildInfoRow(
                  DateFormat('yyyy-MM-dd').format(dividend['date']),
                  '\$${dividend['dividend'].toStringAsFixed(2)}',
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDividendCalculations() {
    if (_dividendData == null || _dividendData!.isEmpty || _stockData == null || _stockData!.candlesData.isEmpty) {
      return const SizedBox();
    }

    final annualDividendIncome = DividendService.calculateAnnualDividendIncome(_dividendData!);
    final monthlyDividendIncome = DividendService.calculateMonthlyDividendIncome(_dividendData!);
    final dailyDividendIncome = DividendService.calculateDailyDividendIncome(_dividendData!);
    final currentPrice = _stockData!.candlesData.last.close;
    final dividendYield = DividendService.calculateDividendYield(annualDividendIncome, currentPrice);

    final List<List<String>> calculations = [
      ['Annual Dividend Income', '\$${annualDividendIncome.toStringAsFixed(2)}'],
      ['Monthly Dividend Income', '\$${monthlyDividendIncome.toStringAsFixed(2)}'],
      ['Daily Dividend Income', '\$${dailyDividendIncome.toStringAsFixed(2)}'],
      ['Dividend Yield', '${dividendYield.toStringAsFixed(2)}%'],
    ];

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
          ...calculations.map((calc) => _buildInfoRow(calc[0], calc[1])),
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