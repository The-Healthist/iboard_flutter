import 'package:flutter/material.dart';
import 'package:iboard_app/http/api_client.dart';
import 'package:iboard_app/models/settings_model.dart';
import 'package:iboard_app/providers/state_provider.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:iboard_app/providers/arrear_provider.dart';

class AppDataProvider extends ChangeNotifier {
  final Logger _logger = Logger();
  late ApiClient _apiClient;

  SettingsModel? _settingsModel;
  String? _deviceId;
  String _baseUrl; // Should be initialized, e.g., from a config
  CarouselStateProvider? _carouselStateProvider; // 添加对CarouselStateProvider的引用
  ArrearProvider? _arrearProvider; // 添加对ArrearProvider的引用

  bool _isLoading = false;
  String? _error;

  // Getters
  SettingsModel? get settingsModel => _settingsModel;
  ArrearProvider? get arrearProvider =>
      _arrearProvider; // 添加对ArrearProvider的getter
  Building? get buildingInfo => _settingsModel?.building;
  Settings? get deviceSettings => _settingsModel?.settings;
  String? get token => _settingsModel?.token;
  bool get isLoading => _isLoading;
  String? get error => _error;
  ApiClient get apiClient => _apiClient;
  String? get deviceId => _deviceId;
  bool get isLoggedIn => _settingsModel != null && token != null;

  static const String _deviceIdKey = 'deviceId';

  AppDataProvider({required String baseUrl}) : _baseUrl = baseUrl {
    _apiClient = ApiClient(
      baseUrl: _baseUrl,
      onNeedsTokenRefresh: _handleTokenRefresh,
    );
    _logger.i(
        'AppDataProvider initialized. ApiClient configured for token refresh.');
  }

  /// 设置CarouselStateProvider的引用，用于更新时间配置
  void setCarouselStateProvider(CarouselStateProvider? provider) {
    _carouselStateProvider = provider;
    // 如果已有设置数据，立即更新
    if (_settingsModel?.settings != null) {
      _carouselStateProvider?.updateSettings(_settingsModel!.settings);
    }
  }

  /// 设置ArrearProvider的引用，用于设置楼宇ID
  void setArrearProvider(ArrearProvider? provider) {
    _arrearProvider = provider;
    _logger.i('ArrearProvider引用已设置');
  }

  /// 设置楼宇ID到ArrearProvider
  void setBuildingIdToArrearProvider(String? ismartId) {
    if (_arrearProvider != null && ismartId != null && ismartId.isNotEmpty) {
      // 检查Provider是否已被销毁
      if (!_arrearProvider!.isDisposed) {
        _logger.i('设置ArrearProvider楼宇ID: $ismartId');
        _arrearProvider!.setSelectedBuildingId(ismartId);
      } else {
        _logger.w('ArrearProvider已被销毁，无法设置楼宇ID');
      }
    } else {
      _logger.w('ArrearProvider未设置或楼宇ID无效，跳过设置');
    }
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

      // 更新CarouselStateProvider的时间配置
      if (_carouselStateProvider != null && _settingsModel?.settings != null) {
        _carouselStateProvider!.updateSettings(_settingsModel!.settings);
        _logger.i('CarouselStateProvider settings updated successfully.');
      }

      // 设置ArrearProvider的楼宇ID
      if (_settingsModel != null) {
        final buildingIsmartId = _settingsModel!.building.ismartId;
        if (buildingIsmartId.isNotEmpty) {
          setBuildingIdToArrearProvider(buildingIsmartId);
        } else {
          _logger.w('楼宇ID为空，无法设置楼宇ID');
        }
      } else {
        _logger.w('设置信息不完整，无法设置楼宇ID');
      }

      _error = null;
    } on ApiException catch (e) {
      _logger.e('Initial login failed',
          error: e, stackTrace: e.errorData is StackTrace ? e.errorData : null);

      // 检查是否是设备ID无效错误（状态码400且消息包含Invalid device ID）
      if (e.statusCode == 400 &&
          e.errorData is Map &&
          e.errorData['message'] != null &&
          e.errorData['message'].toString().contains('Invalid device ID')) {
        _logger.w(
            'Device ID not found, attempting to register device: $_deviceId');

        try {
          // 尝试注册设备
          await _registerNewDevice(_deviceId!);
          _logger.i('Device registration successful, retrying login...');

          // 重新尝试登录
          final retryResponseData =
              await _apiClient.login(deviceId: _deviceId!);
          _settingsModel = SettingsModel.fromJson(retryResponseData);
          _logger.i('Login successful after device registration.');

          // 更新CarouselStateProvider的时间配置
          if (_carouselStateProvider != null &&
              _settingsModel?.settings != null) {
            _carouselStateProvider!.updateSettings(_settingsModel!.settings);
            _logger.i(
                'CarouselStateProvider settings updated successfully after registration.');
          }

          // 设置ArrearProvider的楼宇ID
          final building = _settingsModel?.building;
          if (building?.ismartId != null) {
            setBuildingIdToArrearProvider(building!.ismartId);
          } else {
            _logger.w('楼宇信息不完整，无法设置楼宇ID');
          }

          _error = null;
        } catch (registrationError) {
          _logger.e('Device registration or retry login failed',
              error: registrationError);
          _error = 'Device registration failed: $registrationError';
          _settingsModel = null;
        }
      } else {
        _error = 'Login failed: ${e.message}';
        _settingsModel = null; // Clear data on login failure
      }
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

      // 更新CarouselStateProvider的时间配置
      if (_carouselStateProvider != null && _settingsModel?.settings != null) {
        _carouselStateProvider!.updateSettings(_settingsModel!.settings);
        _logger
            .i('CarouselStateProvider settings updated after token refresh.');
      }

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

  // 注册新设备的私有方法
  Future<void> _registerNewDevice(String deviceId) async {
    _logger.i('Starting device registration process for deviceId: $deviceId');

    try {
      // 第一步：使用管理员账号登录获取 token
      _logger.i('Step 1: Admin login to get admin token');
      final adminLoginResponse = await _apiClient.adminLogin(
        email: 'admin@example.com',
        password: 'admin123',
      );

      if (!adminLoginResponse.containsKey('token')) {
        throw Exception('Admin login failed: No token in response');
      }

      final adminToken = adminLoginResponse['token'] as String;
      _logger.i('Admin login successful, received token');

      // 第二步：使用管理员 token 创建设备
      _logger.i('Step 2: Creating device with admin token');
      await _apiClient.createDevice(
        deviceId: deviceId,
        adminToken: adminToken,
        buildingId: 20, // 固定值
      );

      _logger.i(
          'Device registration completed successfully for deviceId: $deviceId');
    } catch (e, stackTrace) {
      _logger.e('Device registration failed for deviceId: $deviceId',
          error: e, stackTrace: stackTrace);
      throw Exception('Failed to register device: $e');
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

  /// 初始化获取欠费数据
  Future<void> initGetArrearData() async {
    _logger.i('AppDataProvider: 开始初始化获取欠费数据');
    if (_arrearProvider != null && !(_arrearProvider!.isDisposed)) {
      try {
        // 确保我们有有效的楼宇ID
        final buildingIsmartId =
            _settingsModel != null ? _settingsModel!.building.ismartId : null;
        if (buildingIsmartId != null && buildingIsmartId.isNotEmpty) {
          _logger.i('AppDataProvider: 使用楼宇ID $buildingIsmartId 初始化欠费数据');
          // 设置楼宇ID到ArrearProvider
          _arrearProvider!.setSelectedBuildingId(buildingIsmartId);
          // 获取欠费数据
          await _arrearProvider!
              .fetchArrears(reset: true, buildingId: buildingIsmartId);
          _logger.i('AppDataProvider: 欠费数据初始化完成');
        } else {
          _logger.w('AppDataProvider: 楼宇ID无效，无法初始化欠费数据');
        }
      } catch (e, stackTrace) {
        _logger.e('AppDataProvider: 欠费数据初始化失败: $e',
            error: e, stackTrace: stackTrace);
      }
    } else {
      if (_arrearProvider == null) {
        _logger.w('AppDataProvider: ArrearProvider未设置，无法初始化欠费数据');
      } else {
        _logger.w('AppDataProvider: ArrearProvider已被销毁，无法初始化欠费数据');
      }
    }
  }
}
