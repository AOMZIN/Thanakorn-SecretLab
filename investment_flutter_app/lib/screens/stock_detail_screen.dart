import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yahoo_finance_data_reader/yahoo_finance_data_reader.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'dart:math' as math;
import '../models/stock_data.dart';
import '../services/dividend_service.dart';

class StockDetailScreen extends StatefulWidget {
  final String symbol;

  const StockDetailScreen({super.key, required this.symbol});

  @override
  _StockDetailScreenState createState() => _StockDetailScreenState();
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
        StockDataCache.cacheData(widget.symbol, response);
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
