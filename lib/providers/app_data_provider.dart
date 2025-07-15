import 'package:flutter/material.dart';
import 'package:iboard_app/http/api_client.dart';
import 'package:iboard_app/models/settings_model.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppDataProvider extends ChangeNotifier {
  final Logger _logger = Logger();
  late ApiClient _apiClient;

  SettingsModel? _settingsModel;
  String? _deviceId;
  String _baseUrl; // Should be initialized, e.g., from a config

  bool _isLoading = false;
  String? _error;

  // Getters
  SettingsModel? get settingsModel => _settingsModel;
  Building? get buildingInfo => _settingsModel?.building;
  Settings? get deviceSettings => _settingsModel?.settings;
  String? get token => _settingsModel?.token;
  bool get isLoading => _isLoading;
  String? get error => _error;
  ApiClient get apiClient => _apiClient;
  String? get deviceId => _deviceId;

  static const String _deviceIdKey = 'deviceId';

  AppDataProvider({required String baseUrl}) : _baseUrl = baseUrl {
    _apiClient = ApiClient(
      baseUrl: _baseUrl,
      onNeedsTokenRefresh: _handleTokenRefresh,
    );
    _logger.i(
        'AppDataProvider initialized. ApiClient configured for token refresh.');
  }

  Future<void> _loadDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _deviceId = prefs.getString(_deviceIdKey);
      _logger.i('Loaded deviceId: $_deviceId');
    } catch (e) {
      _logger.e('Failed to load deviceId from SharedPreferences', error: e);
      _deviceId = null; // Ensure it's null if loading fails
    }
  }

  Future<void> _saveDeviceId(String deviceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_deviceIdKey, deviceId);
      _deviceId = deviceId; // Update in-memory value
      _logger.i('Saved deviceId: $deviceId');
    } catch (e) {
      _logger.e('Failed to save deviceId to SharedPreferences', error: e);
    }
  }

  // Call this method when the app starts or when device ID is set
  Future<void> initializeAndLogin({String? deviceIdToSet}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    if (deviceIdToSet != null) {
      await _saveDeviceId(deviceIdToSet);
    } else {
      await _loadDeviceId();
    }

    if (_deviceId == null || _deviceId!.isEmpty) {
      _error = 'Device ID is not set. Cannot login.';
      _isLoading = false;
      _logger.w(_error);
      notifyListeners();
      return;
    }

    try {
      _logger.i('Attempting initial login with deviceId: $_deviceId');
      final responseData = await _apiClient.login(deviceId: _deviceId!);
      _settingsModel = SettingsModel.fromJson(responseData);
      // ApiClient's internal token is already set by its login method.
      // We also update the AppDataProvider's token via settingsModel.
      _logger.i('Initial login successful. SettingsModel updated.');
      _error = null;
    } on ApiException catch (e) {
      _logger.e('Initial login failed',
          error: e, stackTrace: e.errorData is StackTrace ? e.errorData : null);
      _error = 'Login failed: ${e.message}';
      _settingsModel = null; // Clear data on login failure
    } catch (e, stackTrace) {
      _logger.e('An unexpected error occurred during initial login',
          error: e, stackTrace: stackTrace);
      _error = 'An unexpected error occurred: $e';
      _settingsModel = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // This method is called by ApiClient when a 401 is encountered
  Future<String?> _handleTokenRefresh() async {
    _logger.i('Attempting token refresh due to 401.');
    if (_deviceId == null || _deviceId!.isEmpty) {
      _logger.e('Cannot refresh token: Device ID is null or empty.');
      // Potentially notify UI or trigger a full re-login/setup flow
      _error = "Device ID not available for token refresh.";
      notifyListeners();
      return null;
    }

    // Indicate that a refresh is in progress, could be useful for UI.
    // For now, the ApiClient's _isRefreshingToken flag handles multiple concurrent refresh attempts.
    // _isLoading = true; // Be cautious with global isLoading here, might conflict with other operations.
    // notifyListeners();

    try {
      _logger
          .i('Calling login API for token refresh with deviceId: $_deviceId');
      final responseData = await _apiClient.login(deviceId: _deviceId!);
      // ApiClient's login method already updates its internal token upon success.

      _settingsModel = SettingsModel.fromJson(responseData);
      // The new token is now available via _settingsModel.token
      // and also set within the ApiClient instance.
      _logger.i(
          'Token refresh successful. SettingsModel updated. New token: ${_settingsModel?.token}');
      _error = null; // Clear previous errors
      notifyListeners(); // Notify listeners about the updated settings model (and token)
      return _settingsModel?.token; // Return the new token to ApiClient
    } on ApiException catch (e) {
      _logger.e('Token refresh failed (ApiException)',
          error: e, stackTrace: e.errorData is StackTrace ? e.errorData : null);
      _error = 'Token refresh failed: ${e.message}';
      // If refresh fails, clear sensitive data or handle logout
      _settingsModel = null;
      _apiClient.setAuthToken(null); // Ensure ApiClient's token is also cleared
      notifyListeners();
      return null; // Indicate refresh failure
    } catch (e, stackTrace) {
      _logger.e('An unexpected error occurred during token refresh',
          error: e, stackTrace: stackTrace);
      _error = 'An unexpected error during token refresh: $e';
      _settingsModel = null;
      _apiClient.setAuthToken(null);
      notifyListeners();
      return null;
    } finally {
      // _isLoading = false; // Reset global isLoading if it was set
      // notifyListeners();
    }
  }

  Future<void> logout() async {
    _logger.i('Logging out.');
    _settingsModel = null;
    _apiClient.setAuthToken(null); // Clear token in ApiClient
    // Optionally clear deviceId from SharedPreferences if desired upon logout
    // final prefs = await SharedPreferences.getInstance();
    // await prefs.remove(_deviceIdKey);
    // _deviceId = null;
    _error = null;
    _isLoading = false;
    notifyListeners();
  }

  // Example of how other API calls might be exposed or handled via provider if needed,
  // though direct use of `appDataProvider.apiClient.method()` is also fine.
  Future<Map<String, dynamic>?> fetchAdvertisements() async {
    if (token == null) {
      _error = "Not authenticated. Please login.";
      notifyListeners();
      return null;
    }
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final data = await _apiClient.getAdvertisementsBuilding();
      _isLoading = false;
      notifyListeners();
      return data;
    } on ApiException catch (e) {
      _logger.e('Failed to fetch advertisements', error: e);
      _error = e.message;
      _isLoading = false;
      notifyListeners();
      return null;
    } catch (e) {
      _logger.e('Unexpected error fetching advertisements', error: e);
      _error = "An unexpected error occurred.";
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }
}
