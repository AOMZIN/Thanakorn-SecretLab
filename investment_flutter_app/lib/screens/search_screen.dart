import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yahoo_finance_data_reader/yahoo_finance_data_reader.dart';
import 'stock_detail_screen.dart';

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
    super.key,
    required this.symbol,
    required this.response,
    this.selectedYear,
  });

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
