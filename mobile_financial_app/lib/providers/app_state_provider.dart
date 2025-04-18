// providers/app_state_provider.dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppStateProvider with ChangeNotifier {
  bool _isLoading = false;
  bool _isAuthenticated = false;
  User? _currentUser;
  String _selectedCurrency = 'USD';
  ThemeMode _themeMode = ThemeMode.system;
  bool _isFirstLaunch = true;

  // Getters
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _isAuthenticated;
  User? get currentUser => _currentUser;
  String get selectedCurrency => _selectedCurrency;
  ThemeMode get themeMode => _themeMode;
  bool get isFirstLaunch => _isFirstLaunch;

  AppStateProvider() {
    _loadSavedState();
  }

  Future<void> _loadSavedState() async {
    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();

      // Load theme preferences
      final savedThemeMode = prefs.getString('themeMode') ?? 'system';
      _themeMode = _getThemeModeFromString(savedThemeMode);

      // Load currency preference
      _selectedCurrency = prefs.getString('currency') ?? 'USD';

      // Check if first launch
      _isFirstLaunch = prefs.getBool('isFirstLaunch') ?? true;

      // Check authentication state (in a real app, you'd verify tokens here)
      _isAuthenticated = prefs.getBool('isAuthenticated') ?? false;

      // Load user if authenticated
      if (_isAuthenticated) {
        final userId = prefs.getString('userId');
        final userName = prefs.getString('userName');
        final userEmail = prefs.getString('userEmail');

        if (userId != null && userName != null && userEmail != null) {
          _currentUser = User(
            id: userId,
            name: userName,
            email: userEmail,
          );
        } else {
          // Invalid saved state, reset authentication
          _isAuthenticated = false;
        }
      }
    } catch (error) {
      print('Error loading app state: $error');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('themeMode', _getStringFromThemeMode(mode));
    } catch (error) {
      print('Error saving theme mode: $error');
    }
  }

  Future<void> setCurrency(String currencyCode) async {
    _selectedCurrency = currencyCode;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('currency', currencyCode);
    } catch (error) {
      print('Error saving currency: $error');
    }
  }

  Future<void> completeFirstLaunch() async {
    _isFirstLaunch = false;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isFirstLaunch', false);
    } catch (error) {
      print('Error saving first launch state: $error');
    }
  }

  Future<bool> login(String email, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      // In a real app, you would call an authentication API here
      // This is just a placeholder for demonstration purposes
      await Future.delayed(Duration(seconds: 2)); // Simulate network request

      // Simulate successful login
      _isAuthenticated = true;
      _currentUser = User(
        id: 'user123',
        name: 'John Doe',
        email: email,
      );

      // Save authentication state
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isAuthenticated', true);
      await prefs.setString('userId', _currentUser!.id);
      await prefs.setString('userName', _currentUser!.name);
      await prefs.setString('userEmail', _currentUser!.email);

      notifyListeners();
      return true;
    } catch (error) {
      print('Error during login: $error');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Clear authentication state
      _isAuthenticated = false;
      _currentUser = null;

      // Clear saved authentication data
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isAuthenticated', false);
      await prefs.remove('userId');
      await prefs.remove('userName');
      await prefs.remove('userEmail');
    } catch (error) {
      print('Error during logout: $error');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  ThemeMode _getThemeModeFromString(String mode) {
    switch (mode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  String _getStringFromThemeMode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      default:
        return 'system';
    }
  }
}

// models/user.dart
class User {
  final String id;
  final String name;
  final String email;
  final String? profileImageUrl;

  User({
    required this.id,
    required this.name,
    required this.email,
    this.profileImageUrl,
  });
}

// Add this import to the necessary files
enum ThemeMode { system, light, dark }