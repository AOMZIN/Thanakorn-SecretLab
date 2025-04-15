import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:http/http.dart' as http;
import 'package:csv/csv.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';

// Main application entry point
void main() {
  WidgetsFlutterBinding.ensureInitialized(); // Required for SQLite initialization
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dividend Manager',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const DividendManagerScreen(),
    );
  }
}

// Database Helper Class
class DividendDatabase {
  static final DividendDatabase instance = DividendDatabase._init();
  static Database? _database;

  // Replace with your actual API key
  final String polygonApiKey = '95CNBUXiPASeEmnDHPcUH9AP21Mh_n7i';

  DividendDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('dividends.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE dividends(
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

  // Insert or update dividend data with error handling
  Future<void> insertOrUpdateDividend(Map<String, dynamic> dividend) async {
    try {
      final db = await instance.database;

      // Check if record exists
      final List<Map<String, dynamic>> existingRecords = await db.query(
        'dividends',
        where: 'id = ?',
        whereArgs: [dividend['id']],
      );

      if (existingRecords.isEmpty) {
        // Insert new record
        await db.insert('dividends', dividend);
      } else {
        // Update existing record
        await db.update(
          'dividends',
          dividend,
          where: 'id = ?',
          whereArgs: [dividend['id']],
        );
      }
    } catch (e) {
      debugPrint('Error inserting/updating dividend: $e');
      rethrow;
    }
  }

  // Import CSV data with better error handling
  Future<void> importFromCSV(String csvContent) async {
    try {
      List<List<dynamic>> rowsAsListOfValues =
      const CsvToListConverter().convert(csvContent);

      if (rowsAsListOfValues.isEmpty) {
        throw Exception('CSV file is empty or invalid');
      }

      // Assuming first row contains headers
      List<String> headers = rowsAsListOfValues[0].map((e) => e.toString()).toList();

      // Find indexes of required columns
      int tickerIndex = headers.indexOf('Ticker');
      int amountIndex = headers.indexOf('Adj. Amount');
      int dividendTypeIndex = headers.indexOf('Dividend Type');
      int frequencyIndex = headers.indexOf('Frequency');
      int exDivDateIndex = headers.indexOf('Ex-Div Date');
      int recordDateIndex = headers.indexOf('Record Date');
      int payDateIndex = headers.indexOf('Pay Date');
      int declareDateIndex = headers.indexOf('Declare Date');

      // Check if all required columns are present
      if (tickerIndex == -1 || amountIndex == -1 || exDivDateIndex == -1 ||
          payDateIndex == -1 || declareDateIndex == -1) {
        throw Exception('CSV is missing required columns');
      }

      // Process data rows
      for (int i = 1; i < rowsAsListOfValues.length; i++) {
        var row = rowsAsListOfValues[i];

        // Skip rows that are too short
        if (row.length <= [tickerIndex, amountIndex, exDivDateIndex,
          payDateIndex, declareDateIndex].reduce((max, val) => max > val ? max : val)) {
          continue;
        }

        // Generate a unique ID
        String uniqueId = 'E${generateUniqueId(
            row[tickerIndex].toString(),
            row[exDivDateIndex].toString(),
            row[payDateIndex].toString())}';

        Map<String, dynamic> dividend = {
          'id': uniqueId,
          'ticker': row[tickerIndex].toString(),
          'cash_amount': double.tryParse(row[amountIndex].toString()) ?? 0.0,
          'currency': 'USD', // Default
          'declaration_date': row[declareDateIndex].toString(),
          'dividend_type': dividendTypeIndex >= 0 && dividendTypeIndex < row.length
              ? row[dividendTypeIndex].toString()
              : '',
          'ex_dividend_date': row[exDivDateIndex].toString(),
          'frequency': frequencyIndex >= 0 && frequencyIndex < row.length
              ? (int.tryParse(row[frequencyIndex].toString()) ?? 0)
              : 0,
          'pay_date': row[payDateIndex].toString(),
          'record_date': recordDateIndex >= 0 && recordDateIndex < row.length
              ? row[recordDateIndex].toString()
              : '',
        };

        await insertOrUpdateDividend(dividend);
      }
    } catch (e) {
      debugPrint('Error importing CSV: $e');
      rethrow;
    }
  }

  // Fetch dividend data from Polygon.io API for a specific ticker
  Future<void> fetchPolygonDividendsForTicker(String ticker) async {
    try {
      final url = 'https://api.polygon.io/v3/reference/dividends?ticker=$ticker&apiKey=$polygonApiKey';
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['results'] != null) {
          for (var item in data['results']) {
            Map<String, dynamic> dividend = {
              'id': item['id'].toString(),
              'ticker': item['ticker'].toString(),
              'cash_amount': item['cash_amount'] is num ? item['cash_amount'] : 0.0,
              'currency': item['currency']?.toString() ?? 'USD',
              'declaration_date': item['declaration_date']?.toString() ?? '',
              'dividend_type': item['dividend_type']?.toString() ?? '',
              'ex_dividend_date': item['ex_dividend_date']?.toString() ?? '',
              'frequency': item['frequency'] is int ? item['frequency'] : 0,
              'pay_date': item['pay_date']?.toString() ?? '',
              'record_date': item['record_date']?.toString() ?? '',
            };

            await insertOrUpdateDividend(dividend);
          }
        }
      } else {
        throw Exception('Failed to load dividend data from Polygon.io: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching from API: $e');
      rethrow;
    }
  }

  // Generate unique ID for CSV imports to match Polygon's format
  String generateUniqueId(String ticker, String exDivDate, String payDate) {
    String combined = '$ticker$exDivDate$payDate';
    return combined.hashCode.toRadixString(16);
  }

  // Get all dividends
  Future<List<Map<String, dynamic>>> getAllDividends() async {
    try {
      final db = await instance.database;
      return await db.query('dividends', orderBy: 'ex_dividend_date DESC');
    } catch (e) {
      debugPrint('Error getting all dividends: $e');
      return [];
    }
  }

  // Get dividends for a specific ticker
  Future<List<Map<String, dynamic>>> getDividendsByTicker(String ticker) async {
    try {
      final db = await instance.database;
      return await db.query(
        'dividends',
        where: 'ticker = ?',
        whereArgs: [ticker],
        orderBy: 'ex_dividend_date DESC',
      );
    } catch (e) {
      debugPrint('Error getting dividends by ticker: $e');
      return [];
    }
  }

  // Close database
  Future<void> close() async {
    final db = await instance.database;
    await db.close();
  }
}

// Main screen widget
class DividendManagerScreen extends StatefulWidget {
  const DividendManagerScreen({Key? key}) : super(key: key);

  @override
  State<DividendManagerScreen> createState() => _DividendManagerScreenState();
}

class _DividendManagerScreenState extends State<DividendManagerScreen> {
  List<Map<String, dynamic>> dividends = [];
  bool isLoading = false;
  TextEditingController tickerController = TextEditingController();

  @override
  void initState() {
    super.initState();
    refreshDividends();
  }

  @override
  void dispose() {
    tickerController.dispose();
    super.dispose();
  }

  Future<void> refreshDividends() async {
    if (!mounted) return;

    setState(() => isLoading = true);
    try {
      dividends = await DividendDatabase.instance.getAllDividends();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context as BuildContext).showSnackBar(
            SnackBar(content: Text('Error loading dividends: ${e.toString()}'))
        );
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> importCSV() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result != null && result.files.isNotEmpty && result.files.single.path != null) {
        File file = File(result.files.single.path!);
        String csvContent = await file.readAsString();

        setState(() => isLoading = true);
        await DividendDatabase.instance.importFromCSV(csvContent);
        await refreshDividends();

        if (mounted) {
          ScaffoldMessenger.of(context as BuildContext).showSnackBar(
              const SnackBar(content: Text('CSV import successful'))
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context as BuildContext).showSnackBar(
            SnackBar(content: Text('Error importing CSV: ${e.toString()}'))
        );
      }
      setState(() => isLoading = false);
    }
  }

  Future<void> fetchTickerData() async {
    final ticker = tickerController.text.trim().toUpperCase();
    if (ticker.isEmpty) {
      ScaffoldMessenger.of(context as BuildContext).showSnackBar(
          const SnackBar(content: Text('Please enter a ticker symbol'))
      );
      return;
    }

    setState(() => isLoading = true);
    try {
      await DividendDatabase.instance.fetchPolygonDividendsForTicker(ticker);
      if (mounted) {
        ScaffoldMessenger.of(context as BuildContext).showSnackBar(
            SnackBar(content: Text('Successfully updated $ticker dividend data'))
        );
      }
      await refreshDividends();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context as BuildContext).showSnackBar(
            SnackBar(content: Text('Error: ${e.toString()}'))
        );
        setState(() => isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dividend Manager')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: tickerController,
                    decoration: const InputDecoration(
                      labelText: 'Ticker Symbol',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: isLoading ? null : fetchTickerData,
                  child: const Text('Fetch'),
                ),
              ],
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : dividends.isEmpty
                ? const Center(child: Text('No dividend data available'))
                : ListView.builder(
              itemCount: dividends.length,
              itemBuilder: (context, index) {
                final dividend = dividends[index];
                return ListTile(
                  title: Text('${dividend['ticker']} - \$${dividend['cash_amount']}'),
                  subtitle: Text('Ex-Date: ${dividend['ex_dividend_date']} | Pay Date: ${dividend['pay_date']}'),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: isLoading ? null : importCSV,
        tooltip: 'Import CSV',
        child: const Icon(Icons.file_upload),
      ),
    );
  }
}