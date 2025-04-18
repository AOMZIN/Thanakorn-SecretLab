import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:debounce_throttle/debounce_throttle.dart';

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
    final ColorScheme lightColorScheme = ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: Brightness.light,
    );

    final ColorScheme darkColorScheme = ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: Brightness.dark,
    );

    return ChangeNotifierProvider(
      create: (_) => DividendProvider()..refreshData(),
      child: MaterialApp(
        title: 'Dividend Portfolio Visualizer',
        theme: ThemeData(
          colorScheme: lightColorScheme,
          useMaterial3: true,
          appBarTheme: AppBarTheme(
            backgroundColor: lightColorScheme.primaryContainer,
            foregroundColor: lightColorScheme.onPrimaryContainer,
          ),
          cardTheme: CardTheme(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        darkTheme: ThemeData(
          colorScheme: darkColorScheme,
          useMaterial3: true,
          appBarTheme: AppBarTheme(
            backgroundColor: darkColorScheme.primaryContainer,
            foregroundColor: darkColorScheme.onPrimaryContainer,
          ),
          cardTheme: CardTheme(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        themeMode: ThemeMode.system,
        home: const DividendDashboardScreen(),
      ),
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
    String orderBy = 'ex_dividend_date DESC',
    int limit = 50,
    int offset = 0
  }) async {
    try {
      final db = await instance.database;
      final results = await db.query(
          _tableName,
          orderBy: orderBy,
          limit: limit,
          offset: offset
      );
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

  Future<List<Dividend>> searchDividends({
    String? searchTerm,
    String? startDate,
    String? endDate,
    double? minAmount,
    double? maxAmount,
  }) async {
    try {
      final db = await instance.database;
      List<String> whereClauses = [];
      List<dynamic> whereArgs = [];

      if (searchTerm != null && searchTerm.isNotEmpty) {
        whereClauses.add('ticker LIKE ?');
        whereArgs.add('%$searchTerm%');
      }

      if (startDate != null) {
        whereClauses.add('ex_dividend_date >= ?');
        whereArgs.add(startDate);
      }

      if (endDate != null) {
        whereClauses.add('ex_dividend_date <= ?');
        whereArgs.add(endDate);
      }

      if (minAmount != null) {
        whereClauses.add('cash_amount >= ?');
        whereArgs.add(minAmount);
      }

      if (maxAmount != null) {
        whereClauses.add('cash_amount <= ?');
        whereArgs.add(maxAmount);
      }

      String whereString = whereClauses.isNotEmpty
          ? whereClauses.join(' AND ')
          : null;

      final results = await db.query(
        _tableName,
        where: whereString,
        whereArgs: whereArgs,
        orderBy: 'ex_dividend_date DESC',
      );

      return results.map((map) => Dividend.fromMap(map)).toList();
    } catch (e) {
      debugPrint('Error searching dividends: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> getDividendStatistics() async {
    try {
      final db = await instance.database;

      // รวมเงินปันผลทั้งหมด
      final totalResult = await db.rawQuery(
          'SELECT SUM(cash_amount) as total FROM $_tableName'
      );
      double totalDividends = totalResult.first['total'] as double? ?? 0.0;

      // เฉลี่ยต่อเดือน
      final monthlyAvgResult = await db.rawQuery('''
        SELECT AVG(monthly_total) as monthly_avg FROM (
          SELECT strftime('%Y-%m', ex_dividend_date) as month,
          SUM(cash_amount) as monthly_total
          FROM $_tableName
          GROUP BY month
        )
      ''');
      double monthlyAvg = monthlyAvgResult.first['monthly_avg'] as double? ?? 0.0;

      // จำนวนบริษัท
      final companyCountResult = await db.rawQuery(
          'SELECT COUNT(DISTINCT ticker) as company_count FROM $_tableName'
      );
      int companyCount = companyCountResult.first['company_count'] as int? ?? 0;

      return {
        'totalDividends': totalDividends,
        'monthlyAverage': monthlyAvg,
        'companyCount': companyCount,
      };
    } catch (e) {
      debugPrint('Error getting dividend statistics: $e');
      return {
        'totalDividends': 0.0,
        'monthlyAverage': 0.0,
        'companyCount': 0,
      };
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
              cashAmount: item['cash_amount'] is num ? item['cash_amount'].toDouble() : 0.0,
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

// Provider pattern for state management
class DividendProvider extends ChangeNotifier {
  final DividendRepository _repository = DividendRepository.instance;
  final DividendService _service = DividendService();

  List<Dividend> _dividends = [];
  Map<String, double> _portfolioDistribution = {};
  Map<String, double> _monthlyDividends = {};
  bool _isLoading = false;
  Map<String, dynamic> _dividendStatistics = {};
  int _selectedYear = 0;
  List<int> _availableYears = [];

  List<Dividend> get dividends => _dividends;
  Map<String, double> get portfolioDistribution => _portfolioDistribution;
  Map<String, double> get monthlyDividends => _monthlyDividends;
  bool get isLoading => _isLoading;
  Map<String, dynamic> get dividendStatistics => _dividendStatistics;
  int get selectedYear => _selectedYear;
  List<int> get availableYears => _availableYears;

  // เพิ่มฟังก์ชันที่ปรับปรุง
  Future<void> refreshData() async {
    _isLoading = true;
    notifyListeners();

    try {
      _dividends = await _repository.getAllDividends();
      _portfolioDistribution = await _repository.getAggregatedDividendsByTicker();
      _monthlyDividends = await _repository.getMonthlyDividends();
      _dividendStatistics = await _repository.getDividendStatistics();
      _availableYears = _getAvailableYears(_dividends);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchTickerData(String ticker) async {
    if (ticker.isEmpty) return;

    _isLoading = true;
    notifyListeners();

    try {
      await _service.fetchPolygonDividendsForTicker(ticker);
      await refreshData();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> importFromCSV(String csvContent) async {
    _isLoading = true;
    notifyListeners();

    try {
      await _service.importFromCSV(csvContent);
      await refreshData();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> searchDividends({
    String? searchTerm,
    String? startDate,
    String? endDate,
    double? minAmount,
    double? maxAmount,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      _dividends = await _repository.searchDividends(
        searchTerm: searchTerm,
        startDate: startDate,
        endDate: endDate,
        minAmount: minAmount,
        maxAmount: maxAmount,
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> filterByPeriod({int? days}) async {
    _isLoading = true;
    notifyListeners();

    try {
      if (days != null) {
        DateTime now = DateTime.now();
        DateTime startDate = now.subtract(Duration(days: days));
        _dividends = await _repository.searchDividends(
          startDate: startDate.toIso8601String(),
        );
      } else {
        await refreshData();
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setSelectedYear(int year) {
    _selectedYear = year;
    notifyListeners();
    refreshData();
  }

  List<int> _getAvailableYears(List<Dividend> dividends) {
    Set<int> years = {};
    for (var dividend in dividends) {
      if (dividend.exDividendDate != null) {
        int year = DateTime.parse(dividend.exDividendDate!).year;
        years.add(year);
      }
    }
    return years.toList()..sort((a, b) => b.compareTo(a));
  }
}

// Main Dashboard Screen
class DividendDashboardScreen extends StatefulWidget {
  const DividendDashboardScreen({Key? key}) : super(key: key);

  @override
  State<DividendDashboardScreen> createState() => _DividendDashboardScreenState();
}

class _DividendDashboardScreenState extends State<DividendDashboardScreen> {
  int _selectedIndex = 0;
  final List<Widget> _screens = [
    const DashboardTab(),
    const DividendListTab(),
    const PortfolioDistributionTab(),
    const MonthlyIncomeTab(),
  ];

  final List<String> _titles = [
    'Dashboard',
    'Dividends',
    'Portfolio',
    'Monthly Income',
  ];

  final List<IconData> _icons = [
    Icons.dashboard,
    Icons.list,
    Icons.pie_chart,
    Icons.bar_chart,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_selectedIndex]),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search',
            onPressed: () {
              showSearch(
                context: context,
                delegate: DividendSearchDelegate(),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Data',
            onPressed: () {
              Provider.of<DividendProvider>(context, listen: false).refreshData();
            },
          ),
        ],
      ),
      drawer: NavigationDrawer(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
          Navigator.pop(context); // Close drawer
        },
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 16, 16, 10),
            child: Text(
              'Dividend Portfolio',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(28, 0, 28, 16),
            child: Divider(),
          ),
          for (int i = 0; i < _titles.length; i++)
            NavigationDrawerDestination(
              icon: Icon(_icons[i]),
              label: Text(_titles[i]),
            ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            child: Divider(),
          ),
          const NavigationDrawerDestination(
            icon: Icon(Icons.add),
            label: Text('Add Dividend'),
          ),
          const NavigationDrawerDestination(
            icon: Icon(Icons.file_upload),
            label: Text('Import CSV'),
          ),
          const NavigationDrawerDestination(
            icon: Icon(Icons.settings),
            label: Text('Settings'),
          ),
        ],
      ),
      body: _screens[_selectedIndex],
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Show add dividend dialog or navigate to add screen
          _showAddDividendDialog();
        },
        tooltip: 'Add Dividend',
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddDividendDialog() {
    // Implement dialog to add new dividend manually
  }
}

// Dashboard Tab
class DashboardTab extends StatelessWidget {
  const DashboardTab({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<DividendProvider>(context);
    final stats = provider.dividendStatistics;
    final currencyFormatter = NumberFormat.currency(symbol: '\$');

    return RefreshIndicator(
      onRefresh: () => provider.refreshData(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Dividend Portfolio Summary',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),

            // Stats Cards
            Row(
              children: [
                _buildStatCard(
                  context,
                  'Total Dividends',
                  currencyFormatter.format(stats['totalDividends'] ?? 0),
                  Icons.monetization_on,
                  Colors.green,
                ),
                const SizedBox(width: 16),
                _buildStatCard(
                  context,
                  'Companies',
                  '${stats['companyCount'] ?? 0}',
                  Icons.business,
                  Colors.blue,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildStatCard(
                  context,
                  'Monthly Average',
                  currencyFormatter.format(stats['monthlyAverage'] ?? 0),
                  Icons.calendar_month,
                  Colors.orange,
                ),
                const SizedBox(width: 16),
                _buildStatCard(
                  context,
                  'Annual Estimate',
                  currencyFormatter.format((stats['monthlyAverage'] ?? 0) * 12),
                  Icons.calendar_today,
                  Colors.purple,
                ),
              ],
            ),

            const SizedBox(height: 32),

            // Mini Charts
            const Text(
              'Quick Overview',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            Container(
              height: 200,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: _buildMiniMonthlyChart(context),
            ),

            const SizedBox(height: 20),

            Container(
              height: 200,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: _buildMiniPortfolioChart(context),
            ),

            const SizedBox(height: 24),

            // Recent Activity
            const Text(
              'Recent Activity',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            _buildRecentActivityList(context),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(BuildContext context, String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniMonthlyChart(BuildContext context) {
    final provider = Provider.of<DividendProvider>(context);
    final monthlyDividends = provider.monthlyDividends;
    final currencyFormatter = NumberFormat.currency(symbol: '\$');

    final Map<String, String> monthNames = {
      '01': 'Jan', '02': 'Feb', '03': 'Mar', '04': 'Apr',
      '05': 'May', '06': 'Jun', '07': 'Jul', '08': 'Aug',
      '09': 'Sep', '10': 'Oct', '11': 'Nov', '12': 'Dec',
    };

    // Calculate max for scaling
    double maxAmount = monthlyDividends.values.reduce((curr, next) => curr > next ? curr : next);

    // Prepare data for bar chart
    List<BarChartGroupData> barGroups = [];
    int index = 0;

    // Ensure all months are represented
    Map<String, double> sortedData = {};
    for (var month in monthNames.keys) {
      sortedData[month] = monthlyDividends[month] ?? 0;
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

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxAmount * 1.2,
        barTouchData: BarTouchData(
          enabled: false,
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
              showTitles: false,
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(
          show: false,
        ),
        barGroups: barGroups,
        gridData: const FlGridData(show: false),
      ),
    );
  }

  Widget _buildMiniPortfolioChart(BuildContext context) {
    final provider = Provider.of<DividendProvider>(context);
    final portfolioDistribution = provider.portfolioDistribution;

    if (portfolioDistribution.isEmpty) {
      return const Center(child: Text('No portfolio distribution data available'));
    }

    // Calculate total for percentages
    double total = portfolioDistribution.values.fold(0, (sum, value) => sum + value);

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

    portfolioDistribution.forEach((ticker, amount) {
      double percentage = (amount / total) * 100;
      sections.add(
        PieChartSectionData(
          color: colors[colorIndex % colors.length],
          value: amount,
          title: '',
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

    return PieChart(
      PieChartData(
        sections: sections,
        sectionsSpace: 2,
        centerSpaceRadius: 40,
        startDegreeOffset: -90,
        pieTouchData: PieTouchData(
          touchCallback: (FlTouchEvent event, pieTouchResponse) {
            // Handle touch events if needed
          },
        ),
      ),
    );
  }

  Widget _buildRecentActivityList(BuildContext context) {
    final provider = Provider.of<DividendProvider>(context);
    final dividends = provider.dividends;
    final currencyFormatter = NumberFormat.currency(symbol: '\$');

    if (dividends.isEmpty) {
      return const Center(child: Text('No recent activity'));
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: dividends.length > 5 ? 5 : dividends.length,
      itemBuilder: (context, index) {
        final dividend = dividends[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Text(
                dividend.ticker[0],
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            title: Row(
              children: [
                Text(
                  dividend.ticker,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const Spacer(),
                Text(
                  currencyFormatter.format(dividend.cashAmount),
                  style: TextStyle(
                    color: Theme.of(context).brightness == Brightness.light
                        ? Colors.green.shade700
                        : Colors.green.shade300,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildInfoItem(
                      context,
                      Icons.calendar_today,
                      'Ex-Date: ${_formatDate(dividend.exDividendDate)}',
                    ),
                    const SizedBox(width: 16),
                    _buildInfoItem(
                      context,
                      Icons.payment,
                      'Pay: ${_formatDate(dividend.payDate)}',
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (dividend.dividendType != null && dividend.dividendType!.isNotEmpty)
                  _buildInfoItem(
                    context,
                    Icons.info_outline,
                    'Type: ${_formatDividendType(dividend.dividendType)}',
                  ),
              ],
            ),
            onTap: () => _showDividendDetails(context, dividend),
          ),
        );
      },
    );
  }

  Widget _buildInfoItem(BuildContext context, IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  void _showDividendDetails(BuildContext context, Dividend dividend) {
    final currencyFormatter = NumberFormat.currency(symbol: '\$');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        builder: (_, scrollController) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: Text(
                      dividend.ticker[0],
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dividend.ticker,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _formatDividendType(dividend.dividendType),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    currencyFormatter.format(dividend.cashAmount),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).brightness == Brightness.light
                          ? Colors.green.shade700
                          : Colors.green.shade300,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 30),

              // Date information
              Text(
                'Date Information',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 12),

              _buildDetailRow(
                context,
                'Declaration Date',
                _formatDate(dividend.declarationDate),
                Icons.event_note,
              ),
              _buildDetailRow(
                context,
                'Ex-Dividend Date',
                _formatDate(dividend.exDividendDate),
                Icons.event_available,
              ),
              _buildDetailRow(
                context,
                'Record Date',
                _formatDate(dividend.recordDate),
                Icons.bookmark,
              ),
              _buildDetailRow(
                context,
                'Payment Date',
                _formatDate(dividend.payDate),
                Icons.payments,
              ),

              const SizedBox(height: 30),

              // Additional information
              Text(
                'Additional Information',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 12),

              _buildDetailRow(
                context,
                'Currency',
                dividend.currency,
                Icons.currency_exchange,
              ),
              _buildDetailRow(
                context,
                'Frequency',
                dividend.frequency != null && dividend.frequency! > 0
                    ? '${dividend.frequency} payments per year'
                    : 'Not specified',
                Icons.repeat,
              ),

              const SizedBox(height: 30),

              // Annual estimate if frequency is available
              if (dividend.frequency != null && dividend.frequency! > 0) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Estimated Annual Income',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            currencyFormatter.format(dividend.cashAmount * dividend.frequency!),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],

              const Spacer(),

              Center(
                child: FilledButton.icon(
                  onPressed: () {
                    launchUrl(Uri.parse('https://polygon.io/stocks/${dividend.ticker}'));
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('View More Information'),
                  style: ButtonStyle(
                    minimumSize: MaterialStateProperty.all(const Size(double.infinity, 48)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context, String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 20,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Dividend List Tab
class DividendListTab extends StatefulWidget {
  const DividendListTab({Key? key}) : super(key: key);

  @override
  State<DividendListTab> createState() => _DividendListTabState();
}

class _DividendListTabState extends State<DividendListTab> {
  final TextEditingController _searchController = TextEditingController();
  final Debouncer _debouncer = Debouncer(delay: const Duration(milliseconds: 500));
  String _filterPeriod = 'all';

  @override
  void initState() {
    super.initState();
    _debouncer.values.listen((value) {
      Provider.of<DividendProvider>(context, listen: false).searchDividends(searchTerm: value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<DividendProvider>(context);
    final dividends = provider.dividends;
    final currencyFormatter = NumberFormat.currency(symbol: '\$');

    return Column(
      children: [
        // Search and Filter Bar
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 5,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  labelText: 'Search by Ticker or Company',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                ),
                onChanged: (value) {
                  _debouncer.add(value);
                },
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildFilterChip(
                    label: 'Last 30 Days',
                    selected: _filterPeriod == 'last30',
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _filterPeriod = 'last30';
                        });
                        provider.filterByPeriod(days: 30);
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    label: 'Last 90 Days',
                    selected: _filterPeriod == 'last90',
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _filterPeriod = 'last90';
                        });
                        provider.filterByPeriod(days: 90);
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    label: 'All Time',
                    selected: _filterPeriod == 'all',
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _filterPeriod = 'all';
                        });
                        provider.refreshData();
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),

        // Dividends List with Grouping
        Expanded(
          child: dividends.isEmpty
              ? const Center(child: Text('No dividend data available'))
              : ListView.builder(
            itemCount: dividends.length,
            itemBuilder: (context, index) {
              final dividend = dividends[index];
              bool isFirstOfMonth = index == 0 ||
                  !_isSameMonth(dividend.exDividendDate, dividends[index - 1].exDividendDate);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isFirstOfMonth)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text(
                        _formatMonthYear(dividend.exDividendDate),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(
                            color: _getDividendTypeColor(dividend.dividendType),
                            width: 4,
                          ),
                        ),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                          child: Text(
                            dividend.ticker[0],
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                        title: Row(
                          children: [
                            Text(
                              dividend.ticker,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const Spacer(),
                            Text(
                              currencyFormatter.format(dividend.cashAmount),
                              style: TextStyle(
                                color: Theme.of(context).brightness == Brightness.light
                                    ? Colors.green.shade700
                                    : Colors.green.shade300,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                _buildInfoItem(
                                  context,
                                  Icons.calendar_today,
                                  'Ex-Date: ${_formatDate(dividend.exDividendDate)}',
                                ),
                                const SizedBox(width: 16),
                                _buildInfoItem(
                                  context,
                                  Icons.payment,
                                  'Pay: ${_formatDate(dividend.payDate)}',
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            if (dividend.dividendType != null && dividend.dividendType!.isNotEmpty)
                              _buildInfoItem(
                                context,
                                Icons.info_outline,
                                'Type: ${_formatDividendType(dividend.dividendType)}',
                              ),
                          ],
                        ),
                        onTap: () => _showDividendDetails(context, dividend),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool selected,
    required ValueChanged<bool> onSelected,
  }) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
      selectedColor: Theme.of(context).colorScheme.primary,
      checkmarkColor: Theme.of(context).colorScheme.onPrimary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }

  Widget _buildInfoItem(BuildContext context, IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  String _formatMonthYear(String? date) {
    if (date == null) return '';
    DateTime parsedDate = DateTime.parse(date);
    return DateFormat.yMMMM().format(parsedDate);
  }

  bool _isSameMonth(String? date1, String? date2) {
    if (date1 == null || date2 == null) return false;
    DateTime parsedDate1 = DateTime.parse(date1);
    DateTime parsedDate2 = DateTime.parse(date2);
    return parsedDate1.year == parsedDate2.year && parsedDate1.month == parsedDate2.month;
  }

  Color _getDividendTypeColor(String? type) {
    switch (type?.toLowerCase()) {
      case 'cash':
        return Colors.green;
      case 'stock':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  void _showDividendDetails(BuildContext context, Dividend dividend) {
    final currencyFormatter = NumberFormat.currency(symbol: '\$');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        builder: (_, scrollController) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: Text(
                      dividend.ticker[0],
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dividend.ticker,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _formatDividendType(dividend.dividendType),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    currencyFormatter.format(dividend.cashAmount),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).brightness == Brightness.light
                          ? Colors.green.shade700
                          : Colors.green.shade300,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 30),

              // Date information
              Text(
                'Date Information',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 12),

              _buildDetailRow(
                context,
                'Declaration Date',
                _formatDate(dividend.declarationDate),
                Icons.event_note,
              ),
              _buildDetailRow(
                context,
                'Ex-Dividend Date',
                _formatDate(dividend.exDividendDate),
                Icons.event_available,
              ),
              _buildDetailRow(
                context,
                'Record Date',
                _formatDate(dividend.recordDate),
                Icons.bookmark,
              ),
              _buildDetailRow(
                context,
                'Payment Date',
                _formatDate(dividend.payDate),
                Icons.payments,
              ),

              const SizedBox(height: 30),

              // Additional information
              Text(
                'Additional Information',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 12),

              _buildDetailRow(
                context,
                'Currency',
                dividend.currency,
                Icons.currency_exchange,
              ),
              _buildDetailRow(
                context,
                'Frequency',
                dividend.frequency != null && dividend.frequency! > 0
                    ? '${dividend.frequency} payments per year'
                    : 'Not specified',
                Icons.repeat,
              ),

              const SizedBox(height: 30),

              // Annual estimate if frequency is available
              if (dividend.frequency != null && dividend.frequency! > 0) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Estimated Annual Income',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            currencyFormatter.format(dividend.cashAmount * dividend.frequency!),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],

              const Spacer(),

              Center(
                child: FilledButton.icon(
                  onPressed: () {
                    launchUrl(Uri.parse('https://polygon.io/stocks/${dividend.ticker}'));
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('View More Information'),
                  style: ButtonStyle(
                    minimumSize: MaterialStateProperty.all(const Size(double.infinity, 48)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context, String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 20,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Portfolio Distribution Tab
class PortfolioDistributionTab extends StatelessWidget {
  const PortfolioDistributionTab({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<DividendProvider>(context);
    final portfolioDistribution = provider.portfolioDistribution;
    final currencyFormatter = NumberFormat.currency(symbol: '\$');

    if (portfolioDistribution.isEmpty) {
      return const Center(child: Text('No portfolio distribution data available'));
    }

    // Calculate total for percentages
    double total = portfolioDistribution.values.fold(0, (sum, value) => sum + value);

    // Sort by amount descending
    List<MapEntry<String, double>> sortedEntries = portfolioDistribution.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Colors with better contrast
    List<Color> sectorColors = [
      Colors.blue.shade600,
      Colors.red.shade600,
      Colors.green.shade600,
      Colors.amber.shade600,
      Colors.purple.shade600,
      Colors.teal.shade600,
      Colors.pink.shade600,
      Colors.orange.shade600,
      Colors.indigo.shade600,
      Colors.brown.shade600,
    ];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Text(
                'Total Portfolio Value',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                currencyFormatter.format(total),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        ),

        // Enhanced Pie Chart
        Expanded(
          flex: 3,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sections: List.generate(sortedEntries.length, (i) {
                    final entry = sortedEntries[i];
                    double percentage = (entry.value / total) * 100;

                    return PieChartSectionData(
                      color: sectorColors[i % sectorColors.length],
                      value: entry.value,
                      title: percentage >= 5 ? '${percentage.toStringAsFixed(1)}%' : '',
                      radius: 110,
                      titleStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    );
                  }),
                  sectionsSpace: 2,
                  centerSpaceRadius: 70,
                  startDegreeOffset: -90,
                  pieTouchData: PieTouchData(
                    touchCallback: (FlTouchEvent event, pieTouchResponse) {
                      // Handle touch events if needed
                    },
                  ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${sortedEntries.length}',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  Text(
                    'Companies',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Legend and Details
        Expanded(
          flex: 4,
          child: Card(
            margin: const EdgeInsets.all(16),
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: sortedEntries.length,
              separatorBuilder: (context, index) => Divider(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                height: 1,
              ),
              itemBuilder: (context, index) {
                final entry = sortedEntries[index];
                final ticker = entry.key;
                final amount = entry.value;
                final percentage = (amount / total) * 100;
                final color = sectorColors[index % sectorColors.length];

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 12,
                    height: 24,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  title: Text(
                    ticker,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        currencyFormatter.format(amount),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${percentage.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  onTap: () => _showTickerDetails(context, ticker),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  void _showTickerDetails(BuildContext context, String ticker) {
    // Implement the logic to show ticker details
  }
}

// Monthly Income Tab
class MonthlyIncomeTab extends StatelessWidget {
  const MonthlyIncomeTab({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<DividendProvider>(context);
    final monthlyDividends = provider.monthlyDividends;
    final currencyFormatter = NumberFormat.currency(symbol: '\$');

    // Years dropdown
    final availableYears = provider.availableYears;
    final selectedYear = provider.selectedYear;

    if (monthlyDividends.isEmpty) {
      return const Center(child: Text('No monthly dividend data available'));
    }

    final Map<String, String> monthNames = {
      '01': 'Jan', '02': 'Feb', '03': 'Mar', '04': 'Apr',
      '05': 'May', '06': 'Jun', '07': 'Jul', '08': 'Aug',
      '09': 'Sep', '10': 'Oct', '11': 'Nov', '12': 'Dec',
    };

    // Calculate max for scaling
    double maxAmount = monthlyDividends.values.reduce((curr, next) => curr > next ? curr : next);
    double total = monthlyDividends.values.fold(0, (sum, value) => sum + value);
    double yearlyEstimate = total;

    // Fill in missing months
    Map<String, double> completeMonthlyData = {};
    for (var month in monthNames.keys) {
      completeMonthlyData[month] = monthlyDividends[month] ?? 0;
    }

    return Column(
      children: [
        // Header with year filter
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              const Text(
                'Monthly Income',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              DropdownButton<int>(
                value: selectedYear,
                icon: const Icon(Icons.arrow_drop_down),
                underline: const SizedBox(),
                onChanged: (int? newValue) {
                  if (newValue != null) {
                    provider.setSelectedYear(newValue);
                  }
                },
                items: availableYears.map<DropdownMenuItem<int>>((int year) {
                  return DropdownMenuItem<int>(
                    value: year,
                    child: Text(
                      year == 0 ? 'All Years' : year.toString(),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),

        // Summary Cards
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _buildSummaryCard(
                context,
                'Total',
                currencyFormatter.format(total),
                Icons.account_balance_wallet,
                Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 16),
              _buildSummaryCard(
                context,
                selectedYear == 0 ? 'Yearly Avg' : 'Annual Est.',
                currencyFormatter.format(yearlyEstimate),
                Icons.calendar_today,
                Theme.of(context).colorScheme.tertiary,
              ),
            ],
          ),
        ),

        // Enhanced Bar Chart
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxAmount * 1.2,
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    tooltipBgColor: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.8),
                    tooltipRoundedRadius: 8,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      String month = monthNames[completeMonthlyData.keys.elementAt(group.x.toInt())] ?? '';
                      return BarTooltipItem(
                        '$month: ${currencyFormatter.format(rod.toY)}',
                        TextStyle(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
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
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              monthNames[completeMonthlyData.keys.elementAt(value.toInt())] ?? '',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
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
                        if (value == maxAmount * 0.5 || value == maxAmount) {
                          return Text(
                            currencyFormatter.format(value),
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          );
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(
                  show: false,
                ),
                barGroups: List.generate(completeMonthlyData.length, (index) {
                  final String month = completeMonthlyData.keys.elementAt(index);
                  final double amount = completeMonthlyData[month] ?? 0;

                  return BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: amount,
                        color: Theme.of(context).colorScheme.primary,
                        gradient: LinearGradient(
                          colors: [
                            Theme.of(context).colorScheme.primary.withOpacity(0.7),
                            Theme.of(context).colorScheme.primary,
                          ],
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                        ),
                        width: 20,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(6),
                          topRight: Radius.circular(6),
                        ),
                        backDrawRodData: BackgroundBarChartRodData(
                          show: true,
                          toY: maxAmount * 1.05,
                          color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                        ),
                      ),
                    ],
                  );
                }),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                      strokeWidth: 1,
                      dashArray: [5, 5],
                    );
                  },
                ),
              ),
            ),
          ),
        ),

        // Monthly details list
        Expanded(
          flex: 2,
          child: Card(
            margin: const EdgeInsets.all(16),
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ListView.separated(
              padding: const EdgeInsets.all(8),
              itemCount: completeMonthlyData.length,
              separatorBuilder: (context, index) => Divider(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                height: 1,
              ),
              itemBuilder: (context, index) {
                String month = completeMonthlyData.keys.elementAt(index);
                double amount = completeMonthlyData[month] ?? 0;

                final monthStr = monthNames[month] ?? '';
                final percentage = total > 0 ? (amount / total) * 100 : 0;

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: amount > 0
                        ? Theme.of(context).colorScheme.primary.withOpacity(0.2)
                        : Theme.of(context).colorScheme.surfaceVariant,
                    child: Text(
                      monthStr,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: amount > 0
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  title: Row(
                    children: [
                      Text(
                        selectedYear == 0 ? '$monthStr' : '$monthStr $selectedYear',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (amount > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${percentage.toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  trailing: Text(
                    amount > 0
                        ? currencyFormatter.format(amount)
                        : '—',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: amount > 0
                          ? Theme.of(context).brightness == Brightness.light
                          ? Colors.green.shade700
                          : Colors.green.shade300
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  onTap: amount > 0 ? () => _showMonthDetails(context, month, selectedYear) : null,
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(BuildContext context, String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMonthDetails(BuildContext context, String month, int year) {
    // Implement the logic to show month details
  }
}

// Settings Screen
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 16),

          // Display Settings
          ListTile(
            title: const Text(
              'Display',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            leading: const Icon(Icons.palette),
            tileColor: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
          ),

          SwitchListTile(
            title: const Text('Dark Mode'),
            subtitle: const Text('Use dark theme'),
            value: Theme.of(context).brightness == Brightness.dark,
            onChanged: (bool value) {
              // Implement theme switching logic
            },
          ),

          ListTile(
            title: const Text('Currency Display'),
            subtitle: const Text('USD'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              // Show currency options
            },
          ),

          const Divider(),

          // Data Settings
          ListTile(
            title: const Text(
              'Data Management',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            leading: const Icon(Icons.storage),
            tileColor: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
          ),

          ListTile(
            title: const Text('Export Data'),
            subtitle: const Text('Save your dividend data as CSV'),
            trailing: const Icon(Icons.file_download, size: 20),
            onTap: () {
              // Implement export functionality
            },
          ),

          ListTile(
            title: const Text('Clear All Data'),
            subtitle: const Text('Delete all dividend records'),
            trailing: const Icon(Icons.delete_forever, size: 20),
            onTap: () {
              // Show confirmation dialog before deleting
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Clear All Data'),
                  content: const Text(
                      'Are you sure you want to delete all dividend records? This action cannot be undone.'
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('CANCEL'),
                    ),
                    FilledButton(
                      onPressed: () {
                        // Implement data deletion
                        Navigator.pop(context);
                      },
                      child: const Text('DELETE'),
                    ),
                  ],
                ),
              );
            },
          ),

          const Divider(),

          // API Settings
          ListTile(
            title: const Text(
              'API Configuration',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            leading: const Icon(Icons.api),
            tileColor: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
          ),

          ListTile(
            title: const Text('API Key'),
            subtitle: const Text('Configure Polygon.io API key'),
            trailing: const Icon(Icons.edit, size: 20),
            onTap: () {
              // Show API key configuration dialog
            },
          ),

          const Divider(),

          // About section
          ListTile(
            title: const Text(
              'About',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            leading: const Icon(Icons.info),
            tileColor: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
          ),

          ListTile(
            title: const Text('Version'),
            subtitle: const Text('1.0.0'),
          ),

          ListTile(
            title: const Text('Developer'),
            subtitle: const Text('Your Name'),
            onTap: () {
              // Open developer website or social media
            },
          ),
        ],
      ),
    );
  }
}

// Utility Functions
String _formatDate(String? date) {
  if (date == null) return '';
  DateTime parsedDate = DateTime.parse(date);
  return DateFormat.yMd().format(parsedDate);
}

String _formatDividendType(String? type) {
  if (type == null) return '';
  return type.replaceAll(RegExp(r'(_)'), ' ').capitalize();
}

extension Capitalize on String {
  String capitalize() {
    if (isEmpty) return this;
    return this[0].toUpperCase() + substring(1);
  }
}

// Search Delegate
class DividendSearchDelegate extends SearchDelegate<Dividend> {
  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () {
          query = '';
        },
      ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () {
        close(context, null);
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    // Implement search results
    return Container();
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    // Implement search suggestions
    return Container();
  }
}
