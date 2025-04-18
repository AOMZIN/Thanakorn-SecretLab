import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Investment Flutter App',
    home: PortfolioScreen(),
    debugShowCheckedModeBanner: false,
  );
}

class PortfolioScreen extends StatefulWidget {
  @override
  _PortfolioScreenState createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  Database? _database;
  List<Map<String, dynamic>> portfolios = [];
  List<Map<String, dynamic>> assets = [];

  @override
  void initState() {
    super.initState();
    initDb();
  }

  Future<void> initDb() async {
    final dbPath = await getDatabasesPath();
    _database = await openDatabase(
      p.join(dbPath, 'investment_app.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE portfolios (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE assets (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            portfolio_id INTEGER,
            asset_name TEXT,
            price REAL,
            shares REAL,
            purchase_date TEXT
          )
        ''');
        await db.insert('portfolios', {'name': 'My First Portfolio'});
      },
    );
    fetchPortfolios();
  }

  Future<void> fetchPortfolios() async {
    final results = await _database!.query('portfolios');
    setState(() => portfolios = results);
  }

  Future<void> fetchAssets(int portfolioId) async {
    final results = await _database!.query('assets', where: 'portfolio_id = ?', whereArgs: [portfolioId]);
    setState(() => assets = results);
  }

  void _navigateToAddAsset(BuildContext context, int portfolioId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => AddAssetScreen(
          portfolioId: portfolioId,
          database: _database!,
        ),
      ),
    );
    fetchAssets(portfolioId); // Refresh assets after adding a new one
  }

  double _calculatePortfolioPerformance() {
    double totalInvestment = 0;
    double currentValue = 0;

    for (var asset in assets) {
      double price = asset['price'];
      double shares = asset['shares'];
      totalInvestment += price * shares;
      currentValue += price * shares; // Assuming current price is the same as purchase price
    }

    if (totalInvestment == 0) return 0;
    return (currentValue - totalInvestment) / totalInvestment * 100;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Portfolios')),
    body: ListView.builder(
      itemCount: portfolios.length,
      itemBuilder: (context, index) {
        final portfolio = portfolios[index];
        return ExpansionTile(
          title: Text(portfolio['name']),
          subtitle: Text('Performance: ${_calculatePortfolioPerformance().toStringAsFixed(2)}%'),
          children: [
            ListTile(
              title: Text('Assets'),
              trailing: IconButton(
                icon: Icon(Icons.add),
                onPressed: () => _navigateToAddAsset(context, portfolio['id']),
              ),
            ),
            ...assets.map((asset) => ListTile(
              title: Text(asset['asset_name']),
              subtitle: Text('Shares: ${asset['shares']}, Price: \$${asset['price']}'),
            )).toList(),
          ],
        );
      },
    ),
  );
}

class AddAssetScreen extends StatefulWidget {
  final int portfolioId;
  final Database database;

  AddAssetScreen({required this.portfolioId, required this.database});

  @override
  _AddAssetScreenState createState() => _AddAssetScreenState();
}

class _AddAssetScreenState extends State<AddAssetScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _assetNameController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _sharesController = TextEditingController();
  final TextEditingController _investmentAmountController = TextEditingController();
  DateTime? _selectedDate;

  // This will store the calculated value for shares
  double? _calculatedShares;

  @override
  void initState() {
    super.initState();

    _priceController.addListener(_calculateShares);
    _investmentAmountController.addListener(_calculateShares);
  }

  Future<void> _saveAsset() async {
    if (_formKey.currentState!.validate() && _selectedDate != null) {
      try {
        double price = double.parse(_priceController.text);
        double shares = _calculatedShares ?? double.parse(_sharesController.text);

        await widget.database.insert('assets', {
          'portfolio_id': widget.portfolioId,
          'asset_name': _assetNameController.text,
          'price': price,
          'shares': shares,
          'purchase_date': DateFormat('yyyy-MM-dd').format(_selectedDate!),
        });

        print('Asset saved successfully');
        Navigator.pop(context);
      } catch (e) {
        print('Error saving asset: $e');
      }
    }
  }

  // Calculate the number of shares based on the entered amount
  void _calculateShares() {
    if (_investmentAmountController.text.isNotEmpty && _priceController.text.isNotEmpty) {
      final investmentAmount = double.parse(_investmentAmountController.text);
      final price = double.parse(_priceController.text);
      setState(() {
        _calculatedShares = investmentAmount / price;
        _sharesController.text = _calculatedShares!.toStringAsFixed(2);
      });
    }
  }

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 20),
      lastDate: now,
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Add Asset')),
    body: Padding(
      padding: EdgeInsets.all(16.0),
      child: Form(
        key: _formKey,
        child: Column(children: [
          TextFormField(
            controller: _assetNameController,
            decoration: InputDecoration(labelText: 'Asset Name'),
            validator: (value) =>
            value!.isEmpty ? 'Please enter asset name' : null,
          ),
          TextFormField(
            controller: _priceController,
            decoration: InputDecoration(labelText: 'Price per Share'),
            keyboardType: TextInputType.numberWithOptions(decimal: true),
            validator: (value) {
              if (value!.isEmpty && _investmentAmountController.text.isEmpty) {
                return 'Please enter price per share';
              }
              return null;
            },
            onChanged: (value) => _calculateShares(), // Recalculate on price change
          ),
          // Either input shares or the investment amount
          TextFormField(
            controller: _sharesController,
            decoration: InputDecoration(labelText: 'Number of Shares'),
            keyboardType: TextInputType.numberWithOptions(decimal: true),
            validator: (value) {
              if (value!.isEmpty && _investmentAmountController.text.isEmpty) {
                return 'Please enter either number of shares or investment amount';
              }
              return null;
            },
            onChanged: (value) {
              if (value.isNotEmpty) {
                setState(() {
                  _calculatedShares = null; // Clear calculated shares if user types manually
                });
              }
            },
          ),
          TextFormField(
            controller: _investmentAmountController,
            decoration: InputDecoration(labelText: 'Investment Amount (\$)'),
            keyboardType: TextInputType.numberWithOptions(decimal: true),
            validator: (value) {
              if (value!.isEmpty && _sharesController.text.isEmpty) {
                return 'Please enter either investment amount or number of shares';
              }
              return null;
            },
            onChanged: (value) => _calculateShares(), // Recalculate when investment amount changes
          ),
          SizedBox(height: 16),
          Row(
            children: [
              Text(_selectedDate == null
                  ? 'No date selected'
                  : DateFormat('yyyy-MM-dd').format(_selectedDate!)),
              Spacer(),
              ElevatedButton(
                onPressed: () => _pickDate(context),
                child: Text('Pick Date'),
              ),
            ],
          ),
          Spacer(),
          ElevatedButton(
            onPressed: _saveAsset,
            child: Text('Save Asset'),
          ),
        ]),
      ),
    ),
  );
}
