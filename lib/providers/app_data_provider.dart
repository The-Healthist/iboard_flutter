import 'package:flutter/material.dart';
import 'package:iboard_app/http/api_client.dart';
import 'package:iboard_app/models/settings_model.dart';
import 'package:iboard_app/providers/state_provider.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:iboard_app/providers/arrear_provider.dart';
import 'package:iboard_app/utils/qr_code_util.dart';
import 'package:iboard_app/utils/device_id_util.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

class AppDataProvider extends ChangeNotifier {
  final Logger _logger = Logger();
  late ApiClient _apiClient;

  SettingsModel? _settingsModel;
  String? _deviceId;
  String _baseUrl; // Should be initialized, e.g., from a config
  String? _fallbackUrl; // 备用服务器地址
  CarouselStateProvider? _carouselStateProvider; // 添加对CarouselStateProvider的引用
  ArrearProvider? _arrearProvider; // 添加对ArrearProvider的引用

  bool _isLoading = false;
  String? _error;

  // 二维码缓存相关 - 现在存储本地文件路径
  String? _cachedComplaintQrCode;
  String? _cachedRegistrationQrCode;
  static const String _complaintQrCodeKey = 'complaint_qr_code_path';
  static const String _registrationQrCodeKey = 'registration_qr_code_path';

  // 添加登录设备数据持久化相关常量
  static const String _loginDeviceDataKey = 'login_device_data';

  // 定时登录相关
  Timer? _loginTimer; // 定时登录定时器
  bool _isPeriodicLoginActive = false; // 是否正在进行定期登录
  static const int _loginIntervalHours = 12; // 12小时登录一次

  // 健康检查定时任务相关
  Timer? _healthCheckTimer; // 健康检查定时器
  bool _isPeriodicHealthCheckActive = false; // 是否正在进行定期健康检查
  static const int _healthCheckIntervalMinutes = 30; // 30分钟健康检查一次
  DateTime? _lastHealthCheckTime; // 最后一次健康检查时间
  String? _lastHealthCheckResult; // 最后一次健康检查结果

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

  // 二维码相关getters
  String? get cachedComplaintQrCode => _cachedComplaintQrCode;
  String? get cachedRegistrationQrCode => _cachedRegistrationQrCode;

  // 定时登录状态getter
  bool get isPeriodicLoginActive => _isPeriodicLoginActive;

  // 健康检查状态getter
  bool get isPeriodicHealthCheckActive => _isPeriodicHealthCheckActive;
  DateTime? get lastHealthCheckTime => _lastHealthCheckTime;
  String? get lastHealthCheckResult => _lastHealthCheckResult;

  static const String _deviceIdKey = 'deviceId';

  AppDataProvider({
    required String baseUrl,
    String? fallbackUrl,
  })  : _baseUrl = baseUrl,
        _fallbackUrl = fallbackUrl {
    _apiClient = ApiClient(
      baseUrl: _baseUrl,
      onNeedsTokenRefresh: _handleTokenRefresh,
    );
    // _logger.i(
    //     'AppDataProvider initialized. ApiClient configured for token refresh.');
  }

  ///1, 切换到备用服务器
  void _switchToFallbackServer() {
    if (_fallbackUrl != null && _fallbackUrl!.isNotEmpty) {
      _logger.w('主服务器连接失败，切换到备用服务器: $_fallbackUrl');
      _baseUrl = _fallbackUrl!;
      _apiClient = ApiClient(
        baseUrl: _baseUrl,
        onNeedsTokenRefresh: _handleTokenRefresh,
      );
      notifyListeners();
    } else {
      _logger.e('没有配置备用服务器地址');
    }
  }

  ///1，保存登录设备数据到SharedPreferences缓存
  Future<void> _saveLoginDeviceData(Map<String, dynamic> responseData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = json.encode(responseData);
      await prefs.setString(_loginDeviceDataKey, jsonString);
      // _logger.i('登录设备数据已保存到缓存');
    } catch (e) {
      _logger.e('保存登录设备数据到缓存失败', error: e);
    }
  }

  ///2，从SharedPreferences缓存加载登录设备数据
  Future<Map<String, dynamic>?> _loadLoginDeviceData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_loginDeviceDataKey);
      if (jsonString != null && jsonString.isNotEmpty) {
        final data = json.decode(jsonString) as Map<String, dynamic>;
        // _logger.i('从缓存加载登录设备数据成功');
        return data;
      }
    } catch (e) {
      _logger.e('从缓存加载登录设备数据失败', error: e);
    }
    return null;
  }

  ///3，清除登录设备数据缓存
  Future<void> _clearLoginDeviceData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_loginDeviceDataKey);
      // _logger.i('登录设备数据缓存已清除');
    } catch (e) {
      _logger.e('清除登录设备数据缓存失败', error: e);
    }
  }

  ///4，应用启动时的完整初始化方法 - 优先登录，失败时使用缓存数据作为备用
  Future<void> initialize({String? deviceIdToSet}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // 如果有新设备ID，保存它
      if (deviceIdToSet != null) {
        await _saveDeviceId(deviceIdToSet);
      } else {
        await _loadDeviceId();
      }

      if (_deviceId == null || _deviceId!.isEmpty) {
        _error = 'Device ID is not set. Cannot initialize.';
        _isLoading = false;
        _logger.w(_error);
        notifyListeners();
        return;
      }

      // _logger.i('优先尝试登录（包含自动设备注册），如果失败则使用缓存数据，设备ID: $_deviceId');

      // 尝试登录（包含自动设备注册逻辑）
      try {
        await initializeAndLogin();
        // _logger.i('登录成功，已更新最新数据到缓存');
      } catch (loginError) {
        _logger.w('登录失败，尝试使用缓存数据作为备用: $loginError');

        // 登录失败，尝试从缓存加载数据
        await _loadFromCacheAsFallback();
      }
    } catch (e) {
      _logger.e('应用初始化失败', error: e);
      _error = 'Application initialization failed: $e';
    }

    _isLoading = false;
    notifyListeners();
    _logger.i(
        'initialize方法完成，最终状态: isLoggedIn=${isLoggedIn}, token=${token != null ? '有效' : '无效'}, settingsModel=${_settingsModel != null ? '已设置' : '未设置'}');
  }

  ///5，登录失败时的缓存数据备用加载方法
  Future<void> _loadFromCacheAsFallback() async {
    try {
      final cachedData = await _loadLoginDeviceData();
      if (cachedData != null) {
        try {
          _settingsModel = SettingsModel.fromJson(cachedData);
          // _logger.i('从缓存成功加载备用数据');

          // 设置API客户端的token
          if (_settingsModel?.token != null) {
            _apiClient.setAuthToken(_settingsModel!.token);
            // _logger.i('API客户端token已从缓存设置');
          }

          // 更新CarouselStateProvider的时间配置
          if (_carouselStateProvider != null &&
              _settingsModel?.settings != null) {
            _carouselStateProvider!.updateSettings(_settingsModel!.settings);
            _logger.i('CarouselStateProvider配置已从缓存更新');
          }

          // 设置ArrearProvider的楼宇ID
          if (_settingsModel != null) {
            final buildingIsmartId = _settingsModel!.building.ismartId;
            if (buildingIsmartId.isNotEmpty) {
              setBuildingIdToArrearProvider(buildingIsmartId);
              // 初始化二维码
              await initializeQrCodes();
            }
          }

          // 清除登录错误，因为缓存数据可用
          _error = null;
          _logger.i('使用缓存数据初始化完成');
          _logger.i(
              '缓存数据状态: isLoggedIn=${isLoggedIn}, token=${token != null ? '有效' : '无效'}, settingsModel=${_settingsModel != null ? '已设置' : '未设置'}');
        } catch (e) {
          _logger.e('解析缓存数据失败', error: e);
          // 清除损坏的缓存数据
          await _clearLoginDeviceData();
          _error = 'Login failed and cached data is corrupted: $e';
          _settingsModel = null;
        }
      } else {
        _logger.w('没有可用的缓存数据作为备用');
        _error = 'Login failed and no cached data available';
        _settingsModel = null;
      }
    } catch (e) {
      _logger.e('加载缓存备用数据时发生错误', error: e);
      _error = 'Failed to load cached data: $e';
      _settingsModel = null;
    }
  }

  ///10，执行登录逻辑的私有方法
  Future<void> _performLogin() async {
    try {
      _logger.i('执行登录，设备ID: $_deviceId');
      final responseData = await _apiClient.login(deviceId: _deviceId!);
      _settingsModel = SettingsModel.fromJson(responseData);
      _logger.i('登录成功，SettingsModel已更新');

      // 保存登录设备数据到缓存
      await _saveLoginDeviceData(responseData);

      // 更新CarouselStateProvider的时间配置
      if (_carouselStateProvider != null && _settingsModel?.settings != null) {
        _carouselStateProvider!.updateSettings(_settingsModel!.settings);
        _logger.i('CarouselStateProvider配置更新成功');
      }

      // 设置ArrearProvider的楼宇ID
      if (_settingsModel != null) {
        final buildingIsmartId = _settingsModel!.building.ismartId;
        if (buildingIsmartId.isNotEmpty) {
          setBuildingIdToArrearProvider(buildingIsmartId);
          // 初始化二维码
          await initializeQrCodes();
        }
      }

      _error = null;
      _logger.i(
          '登录状态检查: isLoggedIn=${isLoggedIn}, token=${token != null ? '有效' : '无效'}, settingsModel=${_settingsModel != null ? '已设置' : '未设置'}');
    } catch (e) {
      _logger.e('登录失败', error: e);
      _error = 'Login failed: $e';
      _settingsModel = null;
    }
  }

  ///11，从缓存加载登录设备数据的方法（保留原有方法以供其他地方使用）
  Future<void> initializeFromCache() async {
    _isLoading = true;
    notifyListeners();

    try {
      // 先加载设备ID
      await _loadDeviceId();

      // 尝试从缓存加载登录设备数据
      final cachedData = await _loadLoginDeviceData();
      if (cachedData != null) {
        try {
          _settingsModel = SettingsModel.fromJson(cachedData);
          _logger.i('从缓存成功初始化登录设备数据');

          // 设置API客户端的token
          if (_settingsModel?.token != null) {
            _apiClient.setAuthToken(_settingsModel!.token);
            // _logger.i('API客户端token已从缓存设置');
          }

          // 更新CarouselStateProvider的时间配置
          if (_carouselStateProvider != null &&
              _settingsModel?.settings != null) {
            _carouselStateProvider!.updateSettings(_settingsModel!.settings);
            _logger.i('CarouselStateProvider配置已从缓存更新');
          }

          // 设置ArrearProvider的楼宇ID
          if (_settingsModel != null) {
            final buildingIsmartId = _settingsModel!.building.ismartId;
            if (buildingIsmartId.isNotEmpty) {
              setBuildingIdToArrearProvider(buildingIsmartId);
              // 初始化二维码
              await initializeQrCodes();
            }
          }
        } catch (e) {
          _logger.e('解析缓存的登录设备数据失败', error: e);
          // 清除损坏的缓存数据
          await _clearLoginDeviceData();
        }
      } else {
        _logger.i('缓存中未找到登录设备数据');
      }
    } catch (e) {
      _logger.e('从缓存初始化失败', error: e);
    }

    _isLoading = false;
    notifyListeners();
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
  Future<void> initializeAndLogin(
      {String? deviceIdToSet, bool useFallbackUrl = true}) async {
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

    // 保存原始baseUrl用于可能的恢复
    String? originalBaseUrl;

    try {
      _logger.i('Attempting initial login with deviceId: $_deviceId');
      final responseData = await _apiClient.login(deviceId: _deviceId!);
      _settingsModel = SettingsModel.fromJson(responseData);
      // ApiClient's internal token is already set by its login method.
      // We also update the AppDataProvider's token via settingsModel.
      _logger.i('Initial login successful. SettingsModel updated.');

      ///5，登录成功后保存登录设备数据到缓存
      await _saveLoginDeviceData(responseData);

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
          // 初始化二维码
          await initializeQrCodes();
        } else {
          _logger.w('楼宇ID为空，无法设置楼宇ID');
        }
      } else {
        _logger.w('设置信息不完整，无法设置楼宇ID');
      }

      _error = null;
      _logger.i('登录成功，已更新最新数据到缓存');
      _logger.i(
          '最终状态检查: isLoggedIn=${isLoggedIn}, token=${token != null ? '有效' : '无效'}, settingsModel=${_settingsModel != null ? '已设置' : '未设置'}');
    } on ApiException catch (e) {
      _logger.e('Initial login failed',
          error: e, stackTrace: e.errorData is StackTrace ? e.errorData : null);

      // 检查是否是设备ID无效错误（状态码400且消息包含Invalid device ID）
      // 改进错误检测逻辑，支持多种错误消息格式
      bool isInvalidDeviceIdError = false;

      if (e.statusCode == 400) {
        String errorMessage = '';

        // 尝试从不同位置获取错误消息
        if (e.errorData is Map) {
          errorMessage = e.errorData['message']?.toString() ?? '';
        } else if (e.message.isNotEmpty) {
          errorMessage = e.message;
        }

        // 检查多种可能的错误消息格式
        isInvalidDeviceIdError =
            errorMessage.toLowerCase().contains('invalid device id') ||
                errorMessage.toLowerCase().contains('device not found') ||
                errorMessage.toLowerCase().contains('device id not found') ||
                errorMessage.toLowerCase().contains('设备不存在') ||
                errorMessage.toLowerCase().contains('设备id无效');
      }

      if (isInvalidDeviceIdError) {
        _logger.w(
            'Device ID not found, attempting to register device: $_deviceId');
        _logger.d(
            'Error details - Status: ${e.statusCode}, Message: ${e.message}, ErrorData: ${e.errorData}');

        try {
          // 尝试注册设备
          await _registerNewDevice(_deviceId!);
          _logger.i('Device registration successful, retrying login...');

          // 重新尝试登录
          final retryResponseData =
              await _apiClient.login(deviceId: _deviceId!);
          _settingsModel = SettingsModel.fromJson(retryResponseData);
          _logger.i('Login successful after device registration.');

          ///6，设备注册后登录成功也要保存登录设备数据到缓存
          await _saveLoginDeviceData(retryResponseData);

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
            // 初始化二维码
            await initializeQrCodes();
          } else {
            _logger.w('楼宇信息不完整，无法设置楼宇ID');
          }

          _error = null;
          _logger.i('设备注册后登录成功，已更新最新数据到缓存');
          _logger.i(
              '设备注册后最终状态检查: isLoggedIn=${isLoggedIn}, token=${token != null ? '有效' : '无效'}, settingsModel=${_settingsModel != null ? '已设置' : '未设置'}');
        } catch (registrationError) {
          _logger.e('Device registration or retry login failed',
              error: registrationError);
          _logger.e('Registration error details: $registrationError');
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

      // 如果是网络连接错误且启用了备用URL，则尝试使用IP地址重新登录
      if (useFallbackUrl &&
          (e.toString().contains('SocketException') ||
              e.toString().contains('Failed host lookup'))) {
        _logger.i('尝试使用备用URL重新登录...');
        try {
          // 保存原始baseUrl
          originalBaseUrl = _baseUrl;

          // 切换到IP地址
          _baseUrl = 'http://39.108.49.167:10031';
          _apiClient = ApiClient(
            baseUrl: _baseUrl,
            onNeedsTokenRefresh: _handleTokenRefresh,
          );

          _logger.i(
              'Attempting fallback login with IP address and deviceId: $_deviceId');
          final responseData = await _apiClient.login(deviceId: _deviceId!);
          _settingsModel = SettingsModel.fromJson(responseData);
          _logger.i('Fallback login successful. SettingsModel updated.');

          ///7，备用URL登录成功也要保存登录设备数据到缓存
          await _saveLoginDeviceData(responseData);

          // 更新CarouselStateProvider的时间配置
          if (_carouselStateProvider != null &&
              _settingsModel?.settings != null) {
            _carouselStateProvider!.updateSettings(_settingsModel!.settings);
            _logger.i(
                'CarouselStateProvider settings updated successfully after fallback.');
          }

          // 设置ArrearProvider的楼宇ID
          if (_settingsModel != null) {
            final buildingIsmartId = _settingsModel!.building.ismartId;
            if (buildingIsmartId.isNotEmpty) {
              setBuildingIdToArrearProvider(buildingIsmartId);
              // 初始化二维码
              await initializeQrCodes();
            } else {
              _logger.w('楼宇ID为空，无法设置楼宇ID');
            }
          } else {
            _logger.w('设置信息不完整，无法设置楼宇ID');
          }

          _error = null;
        } catch (fallbackError, fallbackStack) {
          _logger.e('Fallback login also failed',
              error: fallbackError, stackTrace: fallbackStack);
          // 恢复原始baseUrl
          if (originalBaseUrl != null) {
            _baseUrl = originalBaseUrl;
            _apiClient = ApiClient(
              baseUrl: _baseUrl,
              onNeedsTokenRefresh: _handleTokenRefresh,
            );
          }
          _error = 'Login failed: $e';
          _settingsModel = null;
        }
      } else {
        _error = 'An unexpected error occurred: $e';
        _settingsModel = null;
      }
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

      ///8，token刷新成功也要保存登录设备数据到缓存
      await _saveLoginDeviceData(responseData);

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

  ///9，登出时清除所有缓存数据
  Future<void> logout() async {
    _logger.i('Logging out.');
    _settingsModel = null;
    _apiClient.setAuthToken(null); // Clear token in ApiClient

    // 清除登录设备数据缓存
    await _clearLoginDeviceData();

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
          _logger.i('AppDataProvider: 使用楼宇ismartId $buildingIsmartId 初始化欠费数据');
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

  ///1，生成意见投诉二维码（使用本地生成工具）
  Future<String?> generateComplaintQrCode() async {
    if (_cachedComplaintQrCode != null) {
      // 检查本地文件是否存在
      final file = File(_cachedComplaintQrCode!);
      if (await file.exists()) {
        _logger.i('📱 使用缓存的意见投诉二维码文件: $_cachedComplaintQrCode');
        return _cachedComplaintQrCode;
      } else {
        // _logger.w('⚠️ 缓存的二维码文件不存在，重新生成');
        _cachedComplaintQrCode = null;
      }
    }

    final ismartId = _settingsModel?.building.ismartId;
    _logger.i('🔍 当前ismartId: $ismartId');
    if (ismartId == null || ismartId.isEmpty) {
      _logger.w('⚠️ 无法生成意见投诉二维码：ismartId为空');
      return null;
    }

    try {
      // 构建投诉二维码的目标URL
      final targetUrl =
          'https://ismart.legend-in.com.hk/blg_cs_public/$ismartId';
      _logger.i('🔗 投诉二维码目标URL: $targetUrl');

      // 使用本地二维码生成工具
      final qrCodeUtil = QrCodeUtil();
      final qrCodeImageData = await qrCodeUtil.generateQrCodeImageData(
        data: targetUrl,
        size: 88,
      );

      if (qrCodeImageData != null) {
        // 保存到本地文件
        final localPath = await _saveQrCodeImageToLocal(
          qrCodeImageData,
          'complaint_qr_$ismartId.png',
        );

        if (localPath != null) {
          _cachedComplaintQrCode = localPath;
          await _saveQrCodeToCache(_complaintQrCodeKey, localPath);
          _logger.i('✅ 意见投诉二维码生成成功并保存到: $localPath');
          notifyListeners();
          return localPath;
        }
      }

      _logger.e('❌ 生成意见投诉二维码失败');
      return null;
    } catch (e) {
      _logger.e('❌ 生成意见投诉二维码异常', error: e);
      return null;
    }
  }

  ///2，生成住户登记二维码（使用本地生成工具）
  Future<String?> generateRegistrationQrCode() async {
    if (_cachedRegistrationQrCode != null) {
      // 检查本地文件是否存在
      final file = File(_cachedRegistrationQrCode!);
      if (await file.exists()) {
        _logger.i('📱 使用缓存的住户登记二维码文件: $_cachedRegistrationQrCode');
        return _cachedRegistrationQrCode;
      } else {
        _logger.w('⚠️ 缓存的二维码文件不存在，重新生成');
        _cachedRegistrationQrCode = null;
      }
    }

    final ismartId = _settingsModel?.building.ismartId;
    _logger.i('🔍 当前ismartId: $ismartId');
    if (ismartId == null || ismartId.isEmpty) {
      _logger.w('⚠️ 无法生成住户登记二维码：ismartId为空');
      return null;
    }

    try {
      // 构建登记二维码的目标URL
      final targetUrl = 'https://ismart.legend-in.com.hk/regform/$ismartId';
      _logger.i('🔗 登记二维码目标URL: $targetUrl');

      // 使用本地二维码生成工具
      final qrCodeUtil = QrCodeUtil();
      final qrCodeImageData = await qrCodeUtil.generateQrCodeImageData(
        data: targetUrl,
        size: 88,
      );

      if (qrCodeImageData != null) {
        // 保存到本地文件
        final localPath = await _saveQrCodeImageToLocal(
          qrCodeImageData,
          'registration_qr_$ismartId.png',
        );

        if (localPath != null) {
          _cachedRegistrationQrCode = localPath;
          await _saveQrCodeToCache(_registrationQrCodeKey, localPath);
          _logger.i('✅ 住户登记二维码生成成功并保存到: $localPath');
          notifyListeners();
          return localPath;
        }
      }

      _logger.e('❌ 生成住户登记二维码失败');
      return null;
    } catch (e) {
      _logger.e('❌ 生成住户登记二维码异常', error: e);
      return null;
    }
  }

  ///3，下载二维码到本地文件（带重试机制）
  Future<String?> _downloadQrCodeToLocal(
      String qrCodeUrl, String fileName) async {
    const maxRetries = 3;
    const retryDelay = Duration(seconds: 2);

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        _logger.i('📥 开始下载二维码 (尝试 $attempt/$maxRetries): $qrCodeUrl');

        // 创建HTTP客户端，设置超时
        final client = http.Client();
        final request = http.Request('GET', Uri.parse(qrCodeUrl));

        // 发起HTTP请求获取图片数据，设置30秒超时
        final streamedResponse = await client.send(request).timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            client.close();
            throw Exception('请求超时');
          },
        );

        if (streamedResponse.statusCode != 200) {
          _logger.w(
              '⚠️ 下载二维码失败，HTTP状态码: ${streamedResponse.statusCode}，尝试 $attempt/$maxRetries');
          client.close();
          if (attempt < maxRetries) {
            await Future.delayed(retryDelay);
            continue;
          }
          return null;
        }

        // 读取响应数据
        final responseBytes = await streamedResponse.stream.toBytes();
        client.close();

        // 获取应用文档目录
        final directory = await getApplicationDocumentsDirectory();
        final qrCodeDir = Directory('${directory.path}/qr_codes');

        // 确保目录存在
        if (!await qrCodeDir.exists()) {
          await qrCodeDir.create(recursive: true);
          _logger.d('📁 创建二维码目录: ${qrCodeDir.path}');
        }

        // 保存文件
        final filePath = '${qrCodeDir.path}/$fileName';
        final file = File(filePath);
        await file.writeAsBytes(responseBytes);

        _logger
            .i('💾 二维码已保存到本地: $filePath (文件大小: ${responseBytes.length} bytes)');
        return filePath;
      } catch (e) {
        _logger.w('⚠️ 下载二维码失败 (尝试 $attempt/$maxRetries): $e');
        if (attempt < maxRetries) {
          _logger.i('🔄 ${retryDelay.inSeconds}秒后重试...');
          await Future.delayed(retryDelay);
        } else {
          _logger.e('❌ 下载二维码到本地最终失败，所有重试都已用完', error: e);
        }
      }
    }

    return null;
  }

  ///4，保存二维码图片数据到本地文件
  Future<String?> _saveQrCodeImageToLocal(
      Uint8List imageData, String fileName) async {
    try {
      _logger.i('💾 开始保存二维码图片到本地: $fileName');

      // 获取应用文档目录
      final directory = await getApplicationDocumentsDirectory();
      final qrCodeDir = Directory('${directory.path}/qr_codes');

      // 确保目录存在
      if (!await qrCodeDir.exists()) {
        await qrCodeDir.create(recursive: true);
        _logger.d('📁 创建二维码目录: ${qrCodeDir.path}');
      }

      // 保存文件
      final filePath = '${qrCodeDir.path}/$fileName';
      final file = File(filePath);
      await file.writeAsBytes(imageData);

      _logger.i('✅ 二维码图片已保存到本地: $filePath (文件大小: ${imageData.length} bytes)');
      return filePath;
    } catch (e) {
      _logger.e('❌ 保存二维码图片到本地失败', error: e);
      return null;
    }
  }

  ///5，保存二维码路径到SharedPreferences缓存
  Future<void> _saveQrCodeToCache(String key, String localPath) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, localPath);
      _logger.d('💾 二维码路径已保存到缓存: $key -> $localPath');
    } catch (e) {
      _logger.e('❌ 保存二维码路径到缓存失败', error: e);
    }
  }

  ///5，检查二维码是否需要重新生成
  Future<bool> _needRegenerateQrCode(
      String? cachedQrCode, String ismartId) async {
    if (cachedQrCode == null || !cachedQrCode.contains(ismartId)) {
      return true;
    }

    // 检查本地文件是否存在
    return !await File(cachedQrCode).exists();
  }

  ///6，从缓存加载二维码路径
  Future<void> _loadQrCodesFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _cachedComplaintQrCode = prefs.getString(_complaintQrCodeKey);
      _cachedRegistrationQrCode = prefs.getString(_registrationQrCodeKey);

      if (_cachedComplaintQrCode != null) {
        _logger.i('📂 从缓存加载意见投诉二维码路径: $_cachedComplaintQrCode');
      }
      if (_cachedRegistrationQrCode != null) {
        _logger.i('📂 从缓存加载住户登记二维码路径: $_cachedRegistrationQrCode');
      }
    } catch (e) {
      _logger.e('❌ 从缓存加载二维码失败', error: e);
    }
  }

  ///7，初始化二维码（在获得ismartId后调用）- 带超时和错误处理
  Future<void> initializeQrCodes() async {
    _logger.i('🚀 开始初始化二维码');

    try {
      // 设置总超时时间为60秒
      await _initializeQrCodesInternal().timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          _logger.w('⏰ 二维码初始化超时，将使用网络URL作为备选方案');
          _ensureQrCodeFallback();
          return;
        },
      );
    } catch (e) {
      _logger.e('❌ 二维码初始化过程中发生错误，使用备选方案', error: e);
      _ensureQrCodeFallback();
    }

    _logger.i('✅ 二维码初始化完成（可能使用了备选方案）');
  }

  ///8，内部二维码初始化方法
  Future<void> _initializeQrCodesInternal() async {
    // 先从缓存加载
    await _loadQrCodesFromCache();

    // 如果缓存中没有或ismartId发生变化，重新生成
    final ismartId = _settingsModel?.building.ismartId;
    _logger.i('🏢 当前楼宇ismartId: $ismartId');
    if (ismartId != null && ismartId.isNotEmpty) {
      // 检查缓存的二维码是否需要重新生成
      bool needRegenerateComplaint =
          await _needRegenerateQrCode(_cachedComplaintQrCode, ismartId);
      bool needRegenerateRegistration =
          await _needRegenerateQrCode(_cachedRegistrationQrCode, ismartId);

      _logger.i(
          '🔍 二维码检查结果: 投诉需重新生成=$needRegenerateComplaint, 登记需重新生成=$needRegenerateRegistration');

      // 并行生成二维码以提高效率
      final futures = <Future<void>>[];

      if (needRegenerateComplaint) {
        _cachedComplaintQrCode = null; // 清除旧缓存
        futures.add(_generateComplaintQrCodeWithTimeout());
      }

      if (needRegenerateRegistration) {
        _cachedRegistrationQrCode = null; // 清除旧缓存
        futures.add(_generateRegistrationQrCodeWithTimeout());
      }

      // 等待所有二维码生成完成，但不会因为单个失败而阻塞
      if (futures.isNotEmpty) {
        await Future.wait(futures, eagerError: false);
      }
    }
  }

  ///9，确保二维码有备选方案
  void _ensureQrCodeFallback() {
    final ismartId = _settingsModel?.building.ismartId;
    if (ismartId != null && ismartId.isNotEmpty) {
      // 如果投诉二维码为空，记录日志但不设置网络URL
      if (_cachedComplaintQrCode == null) {
        _logger.w('⚠️ 投诉二维码为空，需要重新生成');
      }

      // 如果登记二维码为空，记录日志但不设置网络URL
      if (_cachedRegistrationQrCode == null) {
        _logger.w('⚠️ 登记二维码为空，需要重新生成');
      }
    }
    notifyListeners(); // 通知UI更新
  }

  ///10，带超时的投诉二维码生成
  Future<void> _generateComplaintQrCodeWithTimeout() async {
    try {
      await generateComplaintQrCode().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          _logger.w('⏰ 投诉二维码生成超时');
          return null;
        },
      );
    } catch (e) {
      _logger.w('⚠️ 投诉二维码生成失败', error: e);
    }
  }

  ///11，带超时的登记二维码生成
  Future<void> _generateRegistrationQrCodeWithTimeout() async {
    try {
      await generateRegistrationQrCode().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          _logger.w('⏰ 登记二维码生成超时');
          return null;
        },
      );
    } catch (e) {
      _logger.w('⚠️ 登记二维码生成失败', error: e);
    }
    notifyListeners(); // 通知UI更新
  }

  ///8，清除二维码缓存
  Future<void> clearQrCodeCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_complaintQrCodeKey);
      await prefs.remove(_registrationQrCodeKey);

      _cachedComplaintQrCode = null;
      _cachedRegistrationQrCode = null;

      _logger.i('🗑️ 二维码缓存已清除');
      notifyListeners();
    } catch (e) {
      _logger.e('❌ 清除二维码缓存失败', error: e);
    }
  }

  ///9，清除投诉二维码缓存
  void clearComplaintQrCodeCache() {
    _cachedComplaintQrCode = null;
    _logger.i('🗑️ 投诉二维码缓存已清除');
  }

  ///10，清除登记二维码缓存
  void clearRegistrationQrCodeCache() {
    _cachedRegistrationQrCode = null;
    _logger.i('🗑️ 登记二维码缓存已清除');
  }

  ///11，直接设置投诉二维码
  Future<void> setComplaintQrCodeDirect(String qrCodeUrl) async {
    _cachedComplaintQrCode = qrCodeUrl;
    await _saveQrCodeToCache(_complaintQrCodeKey, qrCodeUrl);
    _logger.i('✅ 投诉二维码已直接设置: $qrCodeUrl');
    notifyListeners();
  }

  ///12，直接设置登记二维码
  Future<void> setRegistrationQrCodeDirect(String qrCodeUrl) async {
    _cachedRegistrationQrCode = qrCodeUrl;
    await _saveQrCodeToCache(_registrationQrCodeKey, qrCodeUrl);
    _logger.i('✅ 登记二维码已直接设置: $qrCodeUrl');
    notifyListeners();
  }

  ///13，开始定时登录任务
  void startPeriodicLogin() {
    if (_isPeriodicLoginActive) {
      _logger.i('Periodic login is already active.');
      return;
    }

    _logger
        .i('Starting periodic login with interval: $_loginIntervalHours hours');
    _isPeriodicLoginActive = true;

    // 设置定时器进行周期性登录
    _loginTimer =
        Timer.periodic(Duration(hours: _loginIntervalHours), (timer) async {
      if (_isPeriodicLoginActive && _deviceId != null) {
        _logger.i('Performing periodic login...');
        try {
          await initializeAndLogin(deviceIdToSet: _deviceId);
          if (isLoggedIn) {
            _logger.i('Periodic login successful');
          } else {
            _logger.w('Periodic login failed');
          }
        } catch (e) {
          _logger.e('Periodic login error', error: e);
        }
      } else {
        timer.cancel();
      }
    });
  }

  ///14，停止定时登录任务
  void stopPeriodicLogin() {
    if (_loginTimer != null) {
      _loginTimer!.cancel();
      _loginTimer = null;
    }
    _isPeriodicLoginActive = false;
    _logger.i('Periodic login stopped.');
  }

  ///15，开始健康检查定时任务
  void startPeriodicHealthCheck() {
    if (_isPeriodicHealthCheckActive) {
      _logger.i('Periodic health check is already active.');
      return;
    }

    _logger.i(
        'Starting periodic health check with interval: $_healthCheckIntervalMinutes minutes');
    _isPeriodicHealthCheckActive = true;

    // 设置定时器进行周期性健康检查
    _healthCheckTimer = Timer.periodic(
        Duration(minutes: _healthCheckIntervalMinutes), (timer) async {
      if (_isPeriodicHealthCheckActive && isLoggedIn) {
        _logger.i('Performing periodic health check...');
        await performHealthCheck();
      } else {
        if (!isLoggedIn) {
          _logger.w('Device not logged in, skipping health check');
        }
        if (!_isPeriodicHealthCheckActive) {
          timer.cancel();
        }
      }
    });

    // 立即执行一次健康检查
    if (isLoggedIn) {
      performHealthCheck();
    }
  }

  ///16，停止健康检查定时任务
  void stopPeriodicHealthCheck() {
    if (_healthCheckTimer != null) {
      _healthCheckTimer!.cancel();
      _healthCheckTimer = null;
    }
    _isPeriodicHealthCheckActive = false;
    _logger.i('Periodic health check stopped.');
  }

  ///17，执行健康检查
  Future<void> performHealthCheck() async {
    if (!isLoggedIn) {
      _logger.w('Device not logged in, cannot perform health check');
      _lastHealthCheckResult = '设备未登录，无法执行健康检查';
      _lastHealthCheckTime = DateTime.now();
      notifyListeners();
      return;
    }

    try {
      _logger.i('🏥 [健康检查] 开始执行健康检查');
      final startTime = DateTime.now();

      final result = await _apiClient.healthTest();

      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);

      _lastHealthCheckTime = endTime;
      _lastHealthCheckResult = '✅ 健康检查成功 (${duration.inMilliseconds}ms)';

      _logger.i('🏥 [健康检查] 健康检查成功，耗时: ${duration.inMilliseconds}ms');
      _logger.d('🏥 [健康检查] 响应数据: $result');

      notifyListeners();
    } catch (e) {
      final endTime = DateTime.now();
      _lastHealthCheckTime = endTime;
      _lastHealthCheckResult = '❌ 健康检查失败: $e';

      _logger.e('🏥 [健康检查] 健康检查失败', error: e);
      notifyListeners();
    }
  }

  /// 强制重新生成设备ID并尝试登录
  Future<void> forceRegenerateDeviceIdAndLogin() async {
    _logger.i('强制重新生成设备ID并尝试登录');

    try {
      // 清除存储的设备ID
      await DeviceIdUtil().clearStoredDeviceId();

      // 重新生成设备ID
      String newDeviceId = await DeviceIdUtil().generateUniqueDeviceId();
      _logger.i('新生成的设备ID: $newDeviceId');

      // 使用新设备ID尝试登录
      await initializeAndLogin(deviceIdToSet: newDeviceId);
    } catch (e) {
      _logger.e('强制重新生成设备ID失败', error: e);
      _error = '强制重新生成设备ID失败: $e';
      notifyListeners();
    }
  }

  /// 测试设备注册流程
  Future<void> testDeviceRegistration() async {
    _logger.i('开始测试设备注册流程');

    if (_deviceId == null || _deviceId!.isEmpty) {
      _logger.e('设备ID为空，无法测试注册');
      return;
    }

    try {
      await _registerNewDevice(_deviceId!);
      _logger.i('设备注册测试成功');
    } catch (e) {
      _logger.e('设备注册测试失败', error: e);
      throw e;
    }
  }

  @override
  void dispose() {
    stopPeriodicLogin();
    stopPeriodicHealthCheck();
    super.dispose();
  }
}
