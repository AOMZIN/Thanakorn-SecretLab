import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yahoo_finance_data_reader/yahoo_finance_data_reader.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/cache_service.dart'; // Changed import
import '../services/dividend_service.dart';
import 'stock_detail_screen.dart';

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

    // Use the service methods consistently
    final annualDividendIncome = DividendService.calculateAnnualDividendIncome(dividendData);
    final monthlyDividendIncome = DividendService.calculateMonthlyDividendIncome(dividendData);
    final dailyDividendIncome = DividendService.calculateDailyDividendIncome(dividendData);
    final currentPrice = _stockData[symbol]?.candlesData.last.close ?? 0.0;
    final dividendYield = DividendService.calculateDividendYield(annualDividendIncome, currentPrice);

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