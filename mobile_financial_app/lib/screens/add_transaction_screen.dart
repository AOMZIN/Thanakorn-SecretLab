// screens/add_transaction_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/transaction.dart';
import '../models/category.dart';
import '../models/account.dart';
import '../providers/transaction_provider.dart';
import '../providers/category_provider.dart';
import '../providers/account_provider.dart';
import '../widgets/date_time_picker.dart';
import '../widgets/category_selector.dart';
import '../widgets/account_selector.dart';
import '../widgets/recurring_options.dart';
import '../widgets/receipt_scanner.dart';

class AddTransactionScreen extends StatefulWidget {
  final TransactionType transactionType;

  AddTransactionScreen({required this.transactionType});

  @override
  _AddTransactionScreenState createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  String? _selectedCategoryId;
  String? _selectedAccountId;
  String? _receiptImagePath;
  List<String> _tags = [];
  bool _isRecurring = false;
  RecurringPattern? _recurringPattern;

  bool _isLoading = false;

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categoryProvider = Provider.of<CategoryProvider>(context);
    final accountProvider = Provider.of<AccountProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_getScreenTitle()),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _amountController,
                decoration: InputDecoration(
                  labelText: 'Amount',
                  prefixText: '\$',
                ),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter an amount';
                  }
                  if (double.tryParse(value) == null) {
                    return 'Please enter a valid number';
                  }
                  return null;
                },
              ),
              SizedBox(height: 16),
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: 'Title',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a title';
                  }
                  return null;
                },
              ),
              SizedBox(height: 16),
              DateTimePicker(
                initialDate: _selectedDate,
                onDateChanged: (date) {
                  setState(() {
                    _selectedDate = date;
                  });
                },
              ),
              SizedBox(height: 16),
              CategorySelector(
                selectedCategoryId: _selectedCategoryId,
                transactionType: widget.transactionType,
                onCategorySelected: (categoryId) {
                  setState(() {
                    _selectedCategoryId = categoryId;
                  });
                },
              ),
              SizedBox(height: 16),
              AccountSelector(
                selectedAccountId: _selectedAccountId,
                onAccountSelected: (accountId) {
                  setState(() {
                    _selectedAccountId = accountId;
                  });
                },
              ),
              SizedBox(height: 16),
              TextFormField(
                controller: _notesController,
                decoration: InputDecoration(
                  labelText: 'Notes',
                ),
                maxLines: 3,
              ),
              SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: Icon(Icons.camera_alt),
                      label: Text('Add Receipt'),
                      onPressed: _scanReceipt,
                    ),
                  ),
                  if (_receiptImagePath != null) ...[
                    SizedBox(width: 8),
                    InkWell(
                      onTap: () {
                        // Show receipt preview
                      },
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(4),
                          image: DecorationImage(
                            image: FileImage(File(_receiptImagePath!)),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              SizedBox(height: 16),
              // Tags input field would go here
              SizedBox(height: 16),
              SwitchListTile(
                title: Text('Recurring Transaction'),
                value: _isRecurring,
                onChanged: (value) {
                  setState(() {
                    _isRecurring = value;
                    if (!value) {
                      _recurringPattern = null;
                    } else {
                      _recurringPattern = RecurringPattern(
                        frequency: RecurringFrequency.monthly,
                      );
                    }
                  });
                },
              ),
              if (_isRecurring) ...[
                RecurringOptions(
                  initialPattern: _recurringPattern,
                  onPatternChanged: (pattern) {
                    setState(() {
                      _recurringPattern = pattern;
                    });
                  },
                ),
              ],
              SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  child: Text('Save'),
                  onPressed: _saveTransaction,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getScreenTitle() {
    switch (widget.transactionType) {
      case TransactionType.expense:
        return 'Add Expense';
      case TransactionType.income:
        return 'Add Income';
      case TransactionType.transfer:
        return 'Add Transfer';
    }
  }

  Future<void> _scanReceipt() async {
    // Implementation for receipt scanning would go here
    // This would involve camera access and possibly OCR
  }

  Future<void> _saveTransaction() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please select a category')),
      );
      return;
    }
    if (_selectedAccountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please select an account')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final transaction = Transaction(
        id: DateTime.now().millisecondsSinceEpoch.toString(), // Temporary ID
        amount: double.parse(_amountController.text),
        title: _titleController.text,
        date: _selectedDate,
        categoryId: _selectedCategoryId!,
        accountId: _selectedAccountId!,
        notes: _notesController.text.isEmpty ? null : _notesController.text,
        receiptImagePath: _receiptImagePath,
        tags: _tags.isEmpty ? null : _tags,
        type: widget.transactionType,
        isRecurring: _isRecurring,
        recurringPattern: _recurringPattern,
      );

      await Provider.of<TransactionProvider>(context, listen: false)
          .addTransaction(transaction);

      Navigator.of(context).pop();
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save transaction. Please try again.')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
}