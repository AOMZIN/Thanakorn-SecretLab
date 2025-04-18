import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart'; // For visualization
import 'package:intl/intl.dart'; // For date/currency formatting

// Constants
const String _apiKey = '95CNBUXiPASeEmnDHPcUH9AP21Mh_n7i'; // Should be in .env file
const String _dbName = 'dividends.db';
const String _tableName = 'dividends';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DividendPortfolioApp());
}

class DividendPortfolioApp extends StatelessWidget {
  const DividendPortfolioApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dividend Portfolio Visualizer',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        useMaterial3: true,
      ),
      darkTheme: ThemeData.dark().copyWith(
        primaryColor: Colors.blueAccent,
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const DividendDashboardScreen(),
    );
  }
}

// Data Models
class Dividend {
  final String id;
  final String ticker;
  final double cashAmount;
  final String currency;
  final String? declarationDate;
  final String? dividendType;
  final String? exDividendDate;
  final int? frequency;
  final String? payDate;
  final String? recordDate;

  Dividend({
    required this.id,
    required this.ticker,
    required this.cashAmount,
    this.currency = 'USD',
    this.declarationDate,
    this.dividendType,
    this.exDividendDate,
    this.frequency,
    this.payDate,
    this.recordDate,
  });

  factory Dividend.fromMap(Map<String, dynamic> map) {
    return Dividend(
      id: map['id'] ?? '',
      ticker: map['ticker'] ?? '',
      cashAmount: map['cash_amount'] is num ? map['cash_amount'].toDouble() : 0.0,
      currency: map['currency'] ?? 'USD',
      declarationDate: map['declaration_date'],
      dividendType: map['dividend_type'],
      exDividendDate: map['ex_dividend_date'],
      frequency: map['frequency'] is int ? map['frequency'] : 0,
      payDate: map['pay_date'],
      recordDate: map['record_date'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'ticker': ticker,
      'cash_amount': cashAmount,
      'currency': currency,
      'declaration_date': declarationDate,
      'dividend_type': dividendType,
      'ex_dividend_date': exDividendDate,
      'frequency': frequency,
      'pay_date': payDate,
      'record_date': recordDate,
    };
  }
}

// Repository pattern for database operations
class DividendRepository {
  static final DividendRepository instance = DividendRepository._init();
  static Database? _database;

  DividendRepository._init();

  Future<Database> get database async {
    _database ??= await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, _dbName);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_tableName(
        id TEXT PRIMARY KEY,
        ticker TEXT NOT NULL,
        cash_amount REAL NOT NULL,
        currency TEXT,
        declaration_date TEXT,
        dividend_type TEXT,
        ex_dividend_date TEXT,
        frequency INTEGER,
        pay_date TEXT,
        record_date TEXT
      )
    ''');
  }

  Future<void> insertOrUpdateDividend(Dividend dividend) async {
    try {
      final db = await database;

      final List<Map<String, dynamic>> existingRecords = await db.query(
        _tableName,
        where: 'id = ?',
        whereArgs: [dividend.id],
      );

      if (existingRecords.isEmpty) {
        await db.insert(_tableName, dividend.toMap());
      } else {
        await db.update(
          _tableName,
          dividend.toMap(),
          where: 'id = ?',
          whereArgs: [dividend.id],
        );
      }
    } catch (e) {
      debugPrint('Error inserting/updating dividend: $e');
      rethrow;
    }
  }

  Future<List<Dividend>> getAllDividends({
    String orderBy = 'ex_dividend_date DESC'
  }) async {
    try {
      final db = await instance.database;
      final results = await db.query(_tableName, orderBy: orderBy);
      return results.map((map) => Dividend.fromMap(map)).toList();
    } catch (e) {
      debugPrint('Error getting all dividends: $e');
      return [];
    }
  }

  Future<List<Dividend>> getDividendsByTicker(String ticker) async {
    try {
      final db = await instance.database;
      final results = await db.query(
        _tableName,
        where: 'ticker = ?',
        whereArgs: [ticker],
        orderBy: 'ex_dividend_date DESC',
      );
      return results.map((map) => Dividend.fromMap(map)).toList();
    } catch (e) {
      debugPrint('Error getting dividends by ticker: $e');
      return [];
    }
  }

  Future<Map<String, double>> getAggregatedDividendsByTicker() async {
    try {
      final db = await instance.database;
      final results = await db.rawQuery('''
        SELECT ticker, SUM(cash_amount) as total 
        FROM $_tableName 
        GROUP BY ticker 
        ORDER BY total DESC
      ''');

      Map<String, double> aggregated = {};
      for (var result in results) {
        aggregated[result['ticker'] as String] = result['total'] as double;
      }
      return aggregated;
    } catch (e) {
      debugPrint('Error aggregating dividends: $e');
      return {};
    }
  }

  Future<Map<String, double>> getMonthlyDividends({int? year}) async {
    try {
      final db = await instance.database;
      String whereClause = '';

      if (year != null) {
        whereClause = "WHERE ex_dividend_date LIKE '$year-%'";
      }

      final results = await db.rawQuery('''
        SELECT 
          substr(ex_dividend_date, 6, 2) as month, 
          SUM(cash_amount) as total 
        FROM $_tableName 
        $whereClause
        GROUP BY month 
        ORDER BY month
      ''');

      Map<String, double> monthlyData = {};
      for (var result in results) {
        String month = result['month'] as String;
        monthlyData[month] = result['total'] as double;
      }
      return monthlyData;
    } catch (e) {
      debugPrint('Error getting monthly dividends: $e');
      return {};
    }
  }

  Future<void> resetDatabase() async {
    try {
      final db = await instance.database;
      await db.delete(_tableName);
    } catch (e) {
      debugPrint('Error resetting database: $e');
      rethrow;
    }
  }

  Future<void> close() async {
    final db = await instance.database;
    await db.close();
  }
}

// Service for API and import/export operations
class DividendService {
  final DividendRepository _repository = DividendRepository.instance;

  Future<void> fetchPolygonDividendsForTicker(String ticker) async {
    try {
      final url = 'https://api.polygon.io/v3/reference/dividends?ticker=$ticker&apiKey=$_apiKey';
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['results'] != null) {
          for (var item in data['results']) {
            Dividend dividend = Dividend(
              id: item['id'].toString(),
              ticker: item['ticker'].toString(),
              cashAmount: item['cash_amount'] is num ? item['cash_amount'] : 0.0,
              currency: item['currency']?.toString() ?? 'USD',
              declarationDate: item['declaration_date']?.toString(),
              dividendType: item['dividend_type']?.toString(),
              exDividendDate: item['ex_dividend_date']?.toString(),
              frequency: item['frequency'] is int ? item['frequency'] : 0,
              payDate: item['pay_date']?.toString(),
              recordDate: item['record_date']?.toString(),
            );

            await _repository.insertOrUpdateDividend(dividend);
          }
        }
      } else {
        throw Exception('Failed to load dividend data: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching from API: $e');
      rethrow;
    }
  }

  Future<void> importFromCSV(String csvContent) async {
    try {
      List<List<dynamic>> rowsAsListOfValues = const CsvToListConverter().convert(csvContent);

      if (rowsAsListOfValues.isEmpty) {
        throw Exception('CSV file is empty or invalid');
      }

      List<String> headers = rowsAsListOfValues[0].map((e) => e.toString().trim()).toList();

      // Normalize headers to match expected ones
      Map<String, int> headerIndexMap = {
        'Ticker': headers.indexOf('Ticker'),
        'Adj. Amount': headers.indexOf('Adj. Amount'),
        'Dividend Type': headers.indexOf('Dividend Type'),
        'Frequency': headers.indexOf('Frequency'),
        'Ex-Div Date': headers.indexOf('Ex-Div Date'),
        'Record Date': headers.indexOf('Record Date'),
        'Pay Date': headers.indexOf('Pay Date'),
        'Declare Date': headers.indexOf('Declare Date'),
      };

      // Check for required columns
      List<String> required = ['Ticker', 'Adj. Amount', 'Ex-Div Date', 'Pay Date', 'Declare Date'];
      for (var key in required) {
        if (headerIndexMap[key] == -1) throw Exception('Missing required column: $key');
      }

      for (int i = 1; i < rowsAsListOfValues.length; i++) {
        var row = rowsAsListOfValues[i];

        String ticker = row[headerIndexMap['Ticker']!].toString();
        String exDate = row[headerIndexMap['Ex-Div Date']!].toString();
        String payDate = row[headerIndexMap['Pay Date']!].toString();
        String uniqueId = 'E${_generateUniqueId(ticker, exDate, payDate)}';

        Dividend dividend = Dividend(
          id: uniqueId,
          ticker: ticker,
          cashAmount: double.tryParse(row[headerIndexMap['Adj. Amount']!].toString()) ?? 0.0,
          currency: 'USD',
          declarationDate: row[headerIndexMap['Declare Date']!].toString(),
          dividendType: headerIndexMap['Dividend Type'] != -1
              ? row[headerIndexMap['Dividend Type']!].toString()
              : '',
          exDividendDate: exDate,
          frequency: headerIndexMap['Frequency'] != -1
              ? (int.tryParse(row[headerIndexMap['Frequency']!].toString()) ?? 0)
              : 0,
          payDate: payDate,
          recordDate: headerIndexMap['Record Date'] != -1
              ? row[headerIndexMap['Record Date']!].toString()
              : '',
        );

        await _repository.insertOrUpdateDividend(dividend);
      }
    } catch (e) {
      debugPrint('Error importing CSV: $e');
      rethrow;
    }
  }

  String _generateUniqueId(String ticker, String exDivDate, String payDate) {
    String combined = '$ticker$exDivDate$payDate';
    return combined.hashCode.toRadixString(16);
  }
}

// Main Dashboard Screen
class DividendDashboardScreen extends StatefulWidget {
  const DividendDashboardScreen({Key? key}) : super(key: key);

  @override
  State<DividendDashboardScreen> createState() => _DividendDashboardScreenState();
}

class _DividendDashboardScreenState extends State<DividendDashboardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Dividend> _dividends = [];
  bool _isLoading = false;
  final DividendService _service = DividendService();
  final DividendRepository _repository = DividendRepository.instance;
  Map<String, double> _portfolioDistribution = {};
  Map<String, double> _monthlyDividends = {};
  final TextEditingController _tickerController = TextEditingController();
  final currencyFormatter = NumberFormat.currency(symbol: '\$');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _refreshData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _tickerController.dispose();
    super.dispose();
  }

  Future<void> _refreshData() async {
    if (!mounted) return;

    setState(() => _isLoading = true);
    try {
      _dividends = await _repository.getAllDividends();
      _portfolioDistribution = await _repository.getAggregatedDividendsByTicker();
      _monthlyDividends = await _repository.getMonthlyDividends();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error refreshing data: ${e.toString()}')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _importCSV() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result != null &&
          result.files.isNotEmpty &&
          result.files.single.path != null) {
        File file = File(result.files.single.path!);
        String csvContent = await file.readAsString();

        setState(() => _isLoading = true);
        await _service.importFromCSV(csvContent);
        await _refreshData();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('CSV import successful')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error importing CSV: ${e.toString()}')));
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchTickerData() async {
    final ticker = _tickerController.text.trim().toUpperCase();
    if (ticker.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a ticker symbol')));
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _service.fetchPolygonDividendsForTicker(ticker);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Successfully updated $ticker dividend data')));
      }
      await _refreshData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _resetAllData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Reset'),
        content: const Text('Are you sure you want to delete all dividend data?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete')),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      await _repository.resetDatabase();
      await _refreshData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All dividend data has been deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error resetting data: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dividend Portfolio Visualizer'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.list), text: 'Dividends'),
            Tab(icon: Icon(Icons.pie_chart), text: 'Portfolio'),
            Tab(icon: Icon(Icons.bar_chart), text: 'Monthly Income'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Data',
            onPressed: _isLoading ? null : _refreshData,
          ),
          IconButton(
            icon: const Icon(Icons.delete_forever),
            tooltip: 'Reset Data',
            onPressed: _isLoading ? null : _resetAllData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
        controller: _tabController,
        children: [
          _buildDividendListTab(),
          _buildPortfolioDistributionTab(),
          _buildMonthlyIncomeTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isLoading ? null : _importCSV,
        tooltip: 'Import CSV',
        child: const Icon(Icons.file_upload),
      ),
    );
  }

  Widget _buildDividendListTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _tickerController,
                  decoration: const InputDecoration(
                    labelText: 'Ticker Symbol',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _fetchTickerData,
                icon: const Icon(Icons.download),
                label: const Text('Fetch'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _dividends.isEmpty
              ? const Center(child: Text('No dividend data available'))
              : ListView.builder(
            itemCount: _dividends.length,
            itemBuilder: (context, index) {
              final dividend = _dividends[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text(dividend.ticker[0]),
                  ),
                  title: Row(
                    children: [
                      Text(dividend.ticker, style: const TextStyle(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      Text(
                        currencyFormatter.format(dividend.cashAmount),
                        style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 14),
                          const SizedBox(width: 4),
                          Text('Ex-Date: ${dividend.exDividendDate ?? 'N/A'}'),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.payment, size: 14),
                          const SizedBox(width: 4),
                          Text('Pay Date: ${dividend.payDate ?? 'N/A'}'),
                        ],
                      ),
                      if (dividend.dividendType != null && dividend.dividendType!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline, size: 14),
                              const SizedBox(width: 4),
                              Text('Type: ${dividend.dividendType}'),
                            ],
                          ),
                        ),
                    ],
                  ),
                  isThreeLine: true,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPortfolioDistributionTab() {
    if (_portfolioDistribution.isEmpty) {
      return const Center(child: Text('No portfolio distribution data available'));
    }

    // Calculate total for percentages
    double total = _portfolioDistribution.values.fold(0, (sum, value) => sum + value);

    // Prepare data for pie chart
    List<PieChartSectionData> sections = [];
    int colorIndex = 0;
    List<Color> colors = [
      Colors.blue,
      Colors.red,
      Colors.green,
      Colors.amber,
      Colors.purple,
      Colors.orange,
      Colors.teal,
      Colors.pink,
    ];

    _portfolioDistribution.forEach((ticker, amount) {
      double percentage = (amount / total) * 100;
      sections.add(
        PieChartSectionData(
          color: colors[colorIndex % colors.length],
          value: amount,
          title: '$ticker\n${percentage.toStringAsFixed(1)}%',
          radius: 100,
          titleStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      );
      colorIndex++;
    });

    return Column(
      children: [
        const SizedBox(height: 20),
        const Text(
          'Portfolio Distribution',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        Expanded(
          child: PieChart(
            PieChartData(
              sections: sections,
              sectionsSpace: 2,
              centerSpaceRadius: 40,
              startDegreeOffset: -90,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _portfolioDistribution.length,
            itemBuilder: (context, index) {
              String ticker = _portfolioDistribution.keys.elementAt(index);
              double amount = _portfolioDistribution.values.elementAt(index);
              double percentage = (amount / total) * 100;

              return ListTile(
                leading: Container(
                  width: 20,
                  height: 20,
                  color: colors[index % colors.length],
                ),
                title: Text(ticker),
                trailing: Text(
                  '${currencyFormatter.format(amount)} (${percentage.toStringAsFixed(1)}%)',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMonthlyIncomeTab() {
    if (_monthlyDividends.isEmpty) {
      return const Center(child: Text('No monthly dividend data available'));
    }

    final Map<String, String> monthNames = {
      '01': 'Jan', '02': 'Feb', '03': 'Mar', '04': 'Apr',
      '05': 'May', '06': 'Jun', '07': 'Jul', '08': 'Aug',
      '09': 'Sep', '10': 'Oct', '11': 'Nov', '12': 'Dec',
    };

    // Calculate max for scaling
    double maxAmount = _monthlyDividends.values.reduce((curr, next) => curr > next ? curr : next);

    // Prepare data for bar chart
    List<BarChartGroupData> barGroups = [];
    int index = 0;

    // Ensure all months are represented
    Map<String, double> sortedData = {};
    for (var month in monthNames.keys) {
      sortedData[month] = _monthlyDividends[month] ?? 0;
    }

    sortedData.forEach((month, amount) {
      barGroups.add(
        BarChartGroupData(
          x: index,
          barRods: [
            BarChartRodData(
              toY: amount,
              color: Colors.blue,
              width: 16,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(6),
                topRight: Radius.circular(6),
              ),
            ),
          ],
        ),
      );
      index++;
    });

    return Column(
      children: [
        const SizedBox(height: 20),
        const Text(
          'Monthly Dividend Income',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxAmount * 1.2,
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    // Remove tooltipBgColor property
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      String month = monthNames[sortedData.keys.elementAt(group.x.toInt())] ?? '';
                      return BarTooltipItem(
                        '$month: ${currencyFormatter.format(rod.toY)}',
                        const TextStyle(color: Colors.white),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        if (value >= 0 && value < monthNames.length) {
                          return Text(
                            monthNames[sortedData.keys.elementAt(value.toInt())] ?? '',
                            style: const TextStyle(fontSize: 10),
                          );
                        }
                        return const Text('');
                      },
                      reservedSize: 30,
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 50,
                      getTitlesWidget: (value, meta) {
                        if (value == 0) return const Text('\$0');
                        return Text(currencyFormatter.format(value), style: const TextStyle(fontSize: 10));
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border.all(color: const Color(0xff37434d), width: 1),
                ),
                barGroups: barGroups,
                gridData: const FlGridData(show: true),
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: sortedData.length,
            itemBuilder: (context, index) {
              String month = sortedData.keys.elementAt(index);
              double amount = sortedData[month] ?? 0;

              return ListTile(
                leading: const Icon(Icons.calendar_month),
                title: Text(monthNames[month] ?? ''),
                trailing: amount > 0
                    ? Text(
                  currencyFormatter.format(amount),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                )
                    : const Text('\$0.00'),
              );
            },
          ),
        ),
      ],
    );
  }
}