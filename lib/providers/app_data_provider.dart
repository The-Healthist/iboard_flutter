import 'package:flutter/material.dart';
import 'package:iboard_app/http/api_client.dart';
import 'package:iboard_app/models/settings_model.dart';
import 'package:iboard_app/providers/state_provider.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:iboard_app/providers/arrear_provider.dart';
import 'package:iboard_app/utils/qr_code_util.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'dart:async';

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

  //缓存键
  String? _cachedComplaintQrCode;
  String? _cachedRegistrationQrCode;
  static const String _complaintQrCodeKey = 'complaint_qr_code_path';
  static const String _registrationQrCodeKey = 'registration_qr_code_path';
  static const String _loginDeviceDataKey = 'login_device_data';

  // 定时登录相关
  Timer? _loginTimer; // 定时登录定时器
  bool _isPeriodicLoginActive = false; // 是否正在进行定期登录
  static const int _loginIntervalHours = 12; // 12小时登录一次

  // 健康检查定时任务相关
  Timer? _healthCheckTimer; // 健康检查定时器
  bool _isPeriodicHealthCheckActive = false; // 是否正在进行定期健康检查
  static const int _healthCheckIntervalMinutes = 30; // 30分鈡健康检查一次
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

  AppDataProvider({
    required String baseUrl,
  }) : _baseUrl = baseUrl {
    _apiClient = ApiClient(
      baseUrl: _baseUrl,
      onNeedsTokenRefresh: _handleTokenRefresh,
    );
  }

  ///1，保存登录设备数据到SharedPreferences缓存
  Future<void> _saveLoginDeviceData(Map<String, dynamic> responseData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = json.encode(responseData);
      await prefs.setString(_loginDeviceDataKey, jsonString);
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
    } catch (e) {
      _logger.e('清除登录设备数据缓存失败', error: e);
    }
  }

  ///4，应用启动时的完整初始化方法(优先登录，失败时使用缓存数据作为备用)
  Future<void> initialize({String? deviceId}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _deviceId = deviceId;
      if (_deviceId == null || _deviceId!.isEmpty) {
        _error = 'Device ID is not set. Cannot initialize.';
        _isLoading = false;
        notifyListeners();
        return;
      }

      // 尝试登录（包含自动设备注册逻辑）
      try {
        await initializeAndLogin();
      } catch (loginError) {
        // 登录失败，尝试从缓存加载数据
        await _loadFromCacheAsFallback();
      }
    } catch (e) {
      _logger.e('应用初始化过程中发生异常', error: e);

      // 即使发生异常，也尝试从缓存加载数据作为最后的备选方案
      try {
        await _loadFromCacheAsFallback();
        if (_settingsModel == null) {
          _error = 'Application initialization failed: $e';
        }
      } catch (cacheError) {
        _logger.e('缓存备选方案也失败', error: cacheError);
        _error = 'Application initialization failed: $e';
      }
    }

    // 在初始化完成后，尝试从缓存加载验证后的设置
    await _loadValidatedSettingsFromCacheAndApply();

    _isLoading = false;
    notifyListeners();
  }

  /// 5,从缓存加载验证后的设置并应用
  Future<void> _loadValidatedSettingsFromCacheAndApply() async {
    try {
      final cachedSettings = await _loadValidatedSettingsFromCache();

      if (cachedSettings != null) {
        // 更新CarouselStateProvider的配置
        if (_carouselStateProvider != null) {
          _carouselStateProvider!.updateSettings(cachedSettings);
        }
      }
    } catch (e) {
      _logger.e('从缓存加载验证后设置失败', error: e);
    }
  }

  /// 6，手动刷新设置 - 用于定时任务或其他需要刷新设置的场景
  Future<void> refreshSettings() async {
    try {
      if (_settingsModel?.settings != null) {
        // 验证并持久化当前设置
        await _validateAndPersistSettings(_settingsModel!.settings);
      } else {
        // 如果没有当前设置，尝试从缓存加载
        await _loadValidatedSettingsFromCacheAndApply();
      }
    } catch (e) {
      _logger.e('设置刷新失败', error: e);
    }
  }

  /// 7，登录失败时的缓存数据备用加载方法
  Future<void> _loadFromCacheAsFallback() async {
    try {
      final cachedData = await _loadLoginDeviceData();
      if (cachedData != null) {
        try {
          _settingsModel = SettingsModel.fromJson(cachedData);

          // 设置API客户端的token
          if (_settingsModel?.token != null) {
            _apiClient.setAuthToken(_settingsModel!.token);
          }

          // 验证并持久化Settings配置
          if (_settingsModel?.settings != null) {
            await _validateAndPersistSettings(_settingsModel!.settings);
          }

          // 设置ArrearProvider的樓宇ID
          if (_settingsModel != null) {
            final buildingIsmartId = _settingsModel!.building.ismartId;
            if (buildingIsmartId.isNotEmpty) {
              _arrearProvider!.setIsmartId(buildingIsmartId);
              // 初始化二维码
              await initializeQrCodesInternal();
            }
          }

          // 清除登录错误，因为缓存数据可用
          _error = null;
        } catch (e) {
          _logger.e('解析缓存数据失败', error: e);
          // 清除损坏的缓存数据
          await _clearLoginDeviceData();
          _error = 'Login failed and cached data is corrupted: $e';
          _settingsModel = null;
        }
      } else {
        _error = 'Login failed and no cached data available';
        _settingsModel = null;
      }
    } catch (e) {
      _logger.e('加载缓存备用数据时发生错误', error: e);
      _error = 'Failed to load cached data: $e';
      _settingsModel = null;
    }
  }

  /// 8，从缓存加载登录设备数据的方法（保留原有方法以供其他地方使用）
  Future<void> initializeFromCache() async {
    _isLoading = true;
    _error = null; // 清除之前的错误状态
    notifyListeners();

    try {
      // 尝试从缓存加载登录设备数据
      final cachedData = await _loadLoginDeviceData();
      if (cachedData != null) {
        try {
          _settingsModel = SettingsModel.fromJson(cachedData);

          // 设置API客户端的token
          if (_settingsModel?.token != null) {
            _apiClient.setAuthToken(_settingsModel!.token);
          }

          // 验证并持久化Settings配置
          if (_settingsModel?.settings != null) {
            await _validateAndPersistSettings(_settingsModel!.settings);
          }

          // 设置ArrearProvider的樓宇ID
          if (_settingsModel != null) {
            final buildingIsmartId = _settingsModel!.building.ismartId;
            if (buildingIsmartId.isNotEmpty) {
              _arrearProvider!.setIsmartId(buildingIsmartId);
              // 初始化二维码
              await initializeQrCodesInternal();
            }
          }

          // 缓存数据加载成功，清除错误状态
          _error = null;
        } catch (e) {
          _logger.e('解析缓存的登录设备数据失败', error: e);
          // 清除损坏的缓存数据
          await _clearLoginDeviceData();
          _error = 'Failed to parse cached data: $e';
        }
      } else {
        _error = 'No cached data available';
      }
    } catch (e) {
      _logger.e('从缓存初始化失败', error: e);
      _error = 'Failed to initialize from cache: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  /// 9，设置CarouselStateProvider的引用，用于更新时间配置
  void setCarouselStateProvider(CarouselStateProvider? provider) {
    _carouselStateProvider = provider;
    // 如果已有设置数据，立即验证并更新
    if (_settingsModel?.settings != null) {
      _validateAndPersistSettings(_settingsModel!.settings);
    }
  }

  /// 10，设置ArrearProvider的引用，用于设置樓宇ID
  void setArrearProvider(ArrearProvider? provider) {
    _arrearProvider = provider;
  }

  /// 11，验证并持久化Settings配置 - 确保所有时间字段都有合理的默认值
  Future<void> _validateAndPersistSettings(Settings settings) async {
    try {
      _logger.i('🔧 [设置验证] 开始验证和持久化Settings配置');

      // 创建验证后的Settings对象，确保所有字段都有合理的默认值
      final validatedSettings = Settings(
        arrearageUpdateDuration: settings.arrearageUpdateDuration > 0
            ? settings.arrearageUpdateDuration
            : 30,
        noticeUpdateDuration: settings.noticeUpdateDuration > 0
            ? settings.noticeUpdateDuration
            : 5,
        advertisementUpdateDuration: settings.advertisementUpdateDuration > 0
            ? settings.advertisementUpdateDuration
            : 10,
        appUpdateDuration:
            settings.appUpdateDuration > 0 ? settings.appUpdateDuration : 60,
        advertisementPlayDuration: settings.advertisementPlayDuration > 0
            ? settings.advertisementPlayDuration
            : 10,
        noticePlayDuration:
            settings.noticePlayDuration > 0 ? settings.noticePlayDuration : 15,
        spareDuration: settings.spareDuration > 0 ? settings.spareDuration : 30,
        noticeStayDuration:
            settings.noticeStayDuration > 0 ? settings.noticeStayDuration : 5,
        bottomCarouselDuration: settings.bottomCarouselDuration > 0
            ? settings.bottomCarouselDuration
            : 10,
        paymentTableOnePageDuration: settings.paymentTableOnePageDuration > 0
            ? settings.paymentTableOnePageDuration
            : 5,
        normalToAnnouncementCarouselDuration:
            settings.normalToAnnouncementCarouselDuration > 0
                ? settings.normalToAnnouncementCarouselDuration
                : 5,
        announcementCarouselToFullAdsCarouselDuration:
            settings.announcementCarouselToFullAdsCarouselDuration > 0
                ? settings.announcementCarouselToFullAdsCarouselDuration
                : 5,
      );

      // 检查是否有字段被修正为默认值
      final corrections = <String>[];
      if (settings.arrearageUpdateDuration == 0) {
        corrections.add('arrearageUpdateDuration: 0 -> 30');
      }
      if (settings.noticeUpdateDuration == 0) {
        corrections.add('noticeUpdateDuration: 0 -> 5');
      }
      if (settings.advertisementUpdateDuration == 0) {
        corrections.add('advertisementUpdateDuration: 0 -> 10');
      }
      if (settings.appUpdateDuration == 0) {
        corrections.add('appUpdateDuration: 0 -> 60');
      }
      if (settings.advertisementPlayDuration == 0) {
        corrections.add('advertisementPlayDuration: 0 -> 10');
      }
      if (settings.noticePlayDuration == 0) {
        corrections.add('noticePlayDuration: 0 -> 15');
      }
      if (settings.spareDuration == 0) {
        corrections.add('spareDuration: 0 -> 30');
      }
      if (settings.noticeStayDuration == 0) {
        corrections.add('noticeStayDuration: 0 -> 5');
      }
      if (settings.bottomCarouselDuration == 0) {
        corrections.add('bottomCarouselDuration: 0 -> 10');
      }
      if (settings.paymentTableOnePageDuration == 0) {
        corrections.add('paymentTableOnePageDuration: 0 -> 5');
      }
      if (settings.normalToAnnouncementCarouselDuration == 0) {
        corrections.add('normalToAnnouncementCarouselDuration: 0 -> 5');
      }
      if (settings.announcementCarouselToFullAdsCarouselDuration == 0) {
        corrections
            .add('announcementCarouselToFullAdsCarouselDuration: 0 -> 5');
      }
      // 将验证后的设置保存到缓存
      await _saveSettingsToCache(validatedSettings);

      // 更新CarouselStateProvider的配置
      if (_carouselStateProvider != null) {
        _carouselStateProvider!.updateSettings(validatedSettings);
      }
    } catch (e) {
      _logger.e('Settings验证和持久化失败', error: e);
    }
  }

  /// 12，保存Settings配置到缓存
  Future<void> _saveSettingsToCache(Settings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsKey = 'validated_settings_${_deviceId ?? 'default'}';

      // 将Settings转换为JSON并保存
      final settingsJson = {
        'arrearageUpdateDuration': settings.arrearageUpdateDuration,
        'noticeUpdateDuration': settings.noticeUpdateDuration,
        'advertisementUpdateDuration': settings.advertisementUpdateDuration,
        'appUpdateDuration': settings.appUpdateDuration,
        'advertisementPlayDuration': settings.advertisementPlayDuration,
        'noticePlayDuration': settings.noticePlayDuration,
        'spareDuration': settings.spareDuration,
        'noticeStayDuration': settings.noticeStayDuration,
        'bottomCarouselDuration': settings.bottomCarouselDuration,
        'paymentTableOnePageDuration': settings.paymentTableOnePageDuration,
        'normalToAnnouncementCarouselDuration':
            settings.normalToAnnouncementCarouselDuration,
        'announcementCarouselToFullAdsCarouselDuration':
            settings.announcementCarouselToFullAdsCarouselDuration,
        'lastUpdated': DateTime.now().toIso8601String(),
      };

      final jsonString = json.encode(settingsJson);
      await prefs.setString(settingsKey, jsonString);
    } catch (e) {
      _logger.e('保存Settings配置到缓存失败', error: e);
    }
  }

  /// 13，从缓存加载验证后的Settings配置
  Future<Settings?> _loadValidatedSettingsFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsKey = 'validated_settings_${_deviceId ?? 'default'}';
      final jsonString = prefs.getString(settingsKey);

      if (jsonString != null && jsonString.isNotEmpty) {
        final settingsData = json.decode(jsonString) as Map<String, dynamic>;

        // 检查缓存是否过期（7天）
        if (settingsData.containsKey('lastUpdated')) {
          final lastUpdated = DateTime.parse(settingsData['lastUpdated']);
          final daysSinceUpdate = DateTime.now().difference(lastUpdated).inDays;

          if (daysSinceUpdate > 7) {
            await prefs.remove(settingsKey);
            return null;
          }
        }

        // 创建Settings对象
        final settings = Settings(
          arrearageUpdateDuration:
              settingsData['arrearageUpdateDuration'] ?? 30,
          noticeUpdateDuration: settingsData['noticeUpdateDuration'] ?? 5,
          advertisementUpdateDuration:
              settingsData['advertisementUpdateDuration'] ?? 10,
          appUpdateDuration: settingsData['appUpdateDuration'] ?? 60,
          advertisementPlayDuration:
              settingsData['advertisementPlayDuration'] ?? 10,
          noticePlayDuration: settingsData['noticePlayDuration'] ?? 15,
          spareDuration: settingsData['spareDuration'] ?? 30,
          noticeStayDuration: settingsData['noticeStayDuration'] ?? 5,
          bottomCarouselDuration: settingsData['bottomCarouselDuration'] ?? 10,
          paymentTableOnePageDuration:
              settingsData['paymentTableOnePageDuration'] ?? 5,
          normalToAnnouncementCarouselDuration:
              settingsData['normalToAnnouncementCarouselDuration'] ?? 5,
          announcementCarouselToFullAdsCarouselDuration:
              settingsData['announcementCarouselToFullAdsCarouselDuration'] ??
                  5,
        );

        return settings;
      }
    } catch (e) {
      _logger.e('🔧 [设置缓存] 从缓存加载Settings配置失败', error: e);
    }
    return null;
  }

  /// 15，初始化登录
  Future<void> initializeAndLogin(
      {String? deviceId,
      bool useFallbackUrl = true,
      bool throwOnFailure = false}) async {
    // 統一確定將要使用的設備ID
    final String? loginDeviceId = deviceId ?? _deviceId;

    if (loginDeviceId == null || loginDeviceId.isEmpty) {
      _error = 'Device ID is not set. Cannot login.';
      _isLoading = false;
      _logger.w(_error);
      notifyListeners();
      return;
    }

    // 保存当前的设置模型，以便登录失败时可以恢复
    final backupSettingsModel = _settingsModel;

    _isLoading = true;
    _error = null;
    notifyListeners();

    // 保存原始baseUrl用于可能的恢复
    String? originalBaseUrl;

    try {
      final responseData = await _apiClient.login(deviceId: loginDeviceId);
      try {
        _settingsModel = SettingsModel.fromJson(responseData);
      } catch (parseError) {
        _logger.e('Failed to parse login response data', error: parseError);
        throw ApiException(
          statusCode: 500,
          message: 'Failed to parse server response: $parseError',
          errorData: responseData,
        );
      }

      // 15.1，保存登录设备数据到缓存
      await _saveLoginDeviceData(responseData);

      // 15.2，验证并持久化Settings配置
      if (_settingsModel?.settings != null) {
        await _validateAndPersistSettings(_settingsModel!.settings);
      }

      // 15.3，设置ArrearProvider的樓宇ID
      if (_settingsModel != null) {
        final buildingIsmartId = _settingsModel!.building.ismartId;
        if (buildingIsmartId.isNotEmpty) {
          _arrearProvider!.setIsmartId(buildingIsmartId);
          await initializeQrCodesInternal();
        }
      }

      _error = null;
    } on ApiException catch (e) {
      _logger.e('Initial login failed',
          error: e, stackTrace: e.errorData is StackTrace ? e.errorData : null);

      // 15.4，检查是否是设备ID无效错误
      bool isInvalidDeviceIdError = false;
      if (e.statusCode == 400) {
        String errorMessage = '';
        if (e.errorData is Map) {
          errorMessage = e.errorData['message']?.toString() ?? '';
        } else if (e.message.isNotEmpty) {
          errorMessage = e.message;
        }
        isInvalidDeviceIdError =
            errorMessage.toLowerCase().contains('invalid device id') ||
                errorMessage.toLowerCase().contains('device not found') ||
                errorMessage.toLowerCase().contains('device id not found') ||
                errorMessage.toLowerCase().contains('设备不存在') ||
                errorMessage.toLowerCase().contains('设备id无效');
      }

      if (isInvalidDeviceIdError) {
        try {
          // 15.5，尝试注册设备
          await _registerNewDevice(loginDeviceId);

          // 15.6，重新尝试登录
          final retryResponseData =
              await _apiClient.login(deviceId: loginDeviceId);
          try {
            _settingsModel = SettingsModel.fromJson(retryResponseData);
            _logger.i('Login successful after device registration.');
          } catch (parseError) {
            _logger.e('Failed to parse retry login response data',
                error: parseError);
            _logger.e('Retry response data: $retryResponseData');
            throw ApiException(
              statusCode: 500,
              message:
                  'Failed to parse server response after device registration: $parseError',
              errorData: retryResponseData,
            );
          }

          ///15.7，设备注册后登录成功也要保存登录设备数据到缓存
          await _saveLoginDeviceData(retryResponseData);

          // 15.8，验证并持久化Settings配置
          if (_settingsModel?.settings != null) {
            await _validateAndPersistSettings(_settingsModel!.settings);
          }

          // 15.9，设置ArrearProvider的樓宇ID
          final building = _settingsModel?.building;
          if (building?.ismartId != null) {
            _arrearProvider!.setIsmartId(building!.ismartId);
            await initializeQrCodesInternal();
          }

          _error = null;
        } catch (registrationError) {
          _logger.e('Device registration or retry login failed',
              error: registrationError);
          _error = 'Device registration failed: $registrationError';
          _settingsModel = backupSettingsModel;
          if (backupSettingsModel?.token != null) {
            _apiClient.setAuthToken(backupSettingsModel!.token);
          }
          if (throwOnFailure) {
            rethrow;
          }
        }
      } else {
        _error = 'Login failed: ${e.message}';
        _settingsModel = backupSettingsModel;
        if (backupSettingsModel?.token != null) {
          _apiClient.setAuthToken(backupSettingsModel!.token);
        }
        if (throwOnFailure) {
          rethrow;
        }
      }
    } catch (e, stackTrace) {
      _logger.e('An unexpected error occurred during initial login',
          error: e, stackTrace: stackTrace);

      // 15.10，網絡錯誤用備用URL重試
      if (useFallbackUrl &&
          (e.toString().contains('SocketException') ||
              e.toString().contains('Failed host lookup'))) {
        try {
          originalBaseUrl = _baseUrl;
          _baseUrl = 'http://39.108.49.167:10031';
          _apiClient = ApiClient(
            baseUrl: _baseUrl,
            onNeedsTokenRefresh: _handleTokenRefresh,
          );

          final responseData = await _apiClient.login(deviceId: loginDeviceId);
          try {
            _settingsModel = SettingsModel.fromJson(responseData);
          } catch (parseError) {
            _logger.e('Failed to parse fallback login response data',
                error: parseError);
            throw ApiException(
              statusCode: 500,
              message:
                  'Failed to parse server response during fallback login: $parseError',
              errorData: responseData,
            );
          }

          ///15.11，備用URL成功也保存
          await _saveLoginDeviceData(responseData);

          // 15.12，驗證並持久化設定
          if (_settingsModel?.settings != null) {
            await _validateAndPersistSettings(_settingsModel!.settings);
          }

          // 設置樓宇ID
          if (_settingsModel != null) {
            final buildingIsmartId = _settingsModel!.building.ismartId;
            if (buildingIsmartId.isNotEmpty) {
              _arrearProvider!.setIsmartId(buildingIsmartId);
              await initializeQrCodesInternal();
            }
          }

          _error = null;
        } catch (fallbackError, fallbackStack) {
          _logger.e('Fallback login also failed',
              error: fallbackError, stackTrace: fallbackStack);
          if (originalBaseUrl != null) {
            _baseUrl = originalBaseUrl;
            _apiClient = ApiClient(
              baseUrl: _baseUrl,
              onNeedsTokenRefresh: _handleTokenRefresh,
            );
          }
          _error = 'Login failed: $e';
          _settingsModel = backupSettingsModel;
          if (backupSettingsModel?.token != null) {
            _apiClient.setAuthToken(backupSettingsModel!.token);
          }
          if (throwOnFailure) {
            rethrow;
          }
        }
      } else {
        _error = 'An unexpected error occurred: $e';
        _settingsModel = backupSettingsModel;
        if (backupSettingsModel?.token != null) {
          _apiClient.setAuthToken(backupSettingsModel!.token);
        }
        if (throwOnFailure) {
          rethrow;
        }
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 16，token刷新
  Future<String?> _handleTokenRefresh() async {
    // 保存当前的设置模型，以便刷新失败时可以恢复
    final backupSettingsModel = _settingsModel;

    if (_deviceId == null || _deviceId!.isEmpty) {
      _logger.e('Cannot refresh token: Device ID is null or empty.');
      // Potentially notify UI or trigger a full re-login/setup flow
      _error = "Device ID not available for token refresh.";
      notifyListeners();
      return null;
    }

    try {
      final responseData = await _apiClient.login(deviceId: _deviceId!);
      // ApiClient's login method already updates its internal token upon success.

      _settingsModel = SettingsModel.fromJson(responseData);

      ///8，token刷新成功也要保存登录设备数据到缓存
      await _saveLoginDeviceData(responseData);

      // 验证并持久化Settings配置
      if (_settingsModel?.settings != null) {
        await _validateAndPersistSettings(_settingsModel!.settings);
      }

      _error = null; // Clear previous errors
      notifyListeners(); // Notify listeners about the updated settings model (and token)
      return _settingsModel?.token; // Return the new token to ApiClient
    } on ApiException catch (e) {
      _logger.e('Token refresh failed (ApiException)',
          error: e, stackTrace: e.errorData is StackTrace ? e.errorData : null);
      _error = 'Token refresh failed: ${e.message}';
      // 恢复备份的设置模型，而不是清空
      _settingsModel = backupSettingsModel;
      if (backupSettingsModel?.token != null) {
        _apiClient.setAuthToken(backupSettingsModel!.token);
      } else {
        _apiClient.setAuthToken(null); // 如果没有备份token，则清空
      }
      notifyListeners();
      return null; // Indicate refresh failure
    } catch (e, stackTrace) {
      _logger.e('An unexpected error occurred during token refresh',
          error: e, stackTrace: stackTrace);
      _error = 'An unexpected error during token refresh: $e';
      // 恢复备份的设置模型，而不是清空
      _settingsModel = backupSettingsModel;
      if (backupSettingsModel?.token != null) {
        _apiClient.setAuthToken(backupSettingsModel!.token);
      } else {
        _apiClient.setAuthToken(null); // 如果没有备份token，则清空
      }
      notifyListeners();
      return null;
    } finally {
      // _isLoading = false; // Reset global isLoading if it was set
      // notifyListeners();
    }
  }

  /// 17，注册新设备
  Future<void> _registerNewDevice(String deviceId) async {
    try {
      // 第一步：使用管理员账号登录获取 token
      final adminLoginResponse = await _apiClient.adminLogin(
        email: 'admin@example.com',
        password: 'admin123',
      );

      if (!adminLoginResponse.containsKey('token')) {
        throw Exception('Admin login failed: No token in response');
      }

      final adminToken = adminLoginResponse['token'] as String;

      // 第二步：使用管理员 token 创建设备
      await _apiClient.createDevice(
        deviceId: deviceId,
        adminToken: adminToken,
        buildingId: 20, // 固定值
      );
    } catch (e, stackTrace) {
      _logger.e('Device registration failed for deviceId: $deviceId',
          error: e, stackTrace: stackTrace);
      throw Exception('Failed to register device: $e');
    }
  }

  /// 18，登出时清除所有缓存数据
  Future<void> logout() async {
    _settingsModel = null;
    _apiClient.setAuthToken(null); // Clear token in ApiClient

    // 清除登录设备数据缓存
    await _clearLoginDeviceData();

    _error = null;
    _isLoading = false;
    notifyListeners();
  }

  /// 20，生成意见投诉二维码（使用本地生成工具）
  Future<String?> generateComplaintQrCode() async {
    if (_cachedComplaintQrCode != null) {
      // 检查本地文件是否存在
      final file = File(_cachedComplaintQrCode!);
      if (await file.exists()) {
        return _cachedComplaintQrCode;
      } else {
        _cachedComplaintQrCode = null;
      }
    }

    final ismartId = _settingsModel?.building.ismartId;
    if (ismartId == null || ismartId.isEmpty) {
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
          notifyListeners();
          return localPath;
        }
      }

      return null;
    } catch (e) {
      _logger.e('生成意见投诉二维码异常', error: e);
      return null;
    }
  }

  /// 21，生成住户登记二维码（使用本地生成工具）
  Future<String?> generateRegistrationQrCode() async {
    if (_cachedRegistrationQrCode != null) {
      // 检查本地文件是否存在
      final file = File(_cachedRegistrationQrCode!);
      if (await file.exists()) {
        return _cachedRegistrationQrCode;
      } else {
        _cachedRegistrationQrCode = null;
      }
    }

    final ismartId = _settingsModel?.building.ismartId;
    if (ismartId == null || ismartId.isEmpty) {
      return null;
    }

    try {
      // 构建登记二维码的目标URL
      final targetUrl = 'https://ismart.legend-in.com.hk/regform/$ismartId';

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
          notifyListeners();
          return localPath;
        }
      }

      return null;
    } catch (e) {
      _logger.e('生成住户登记二维码异常', error: e);
      return null;
    }
  }

  /// 22，保存二维码图片数据到本地文件
  Future<String?> _saveQrCodeImageToLocal(
      Uint8List imageData, String fileName) async {
    try {
      // 获取应用文档目录
      final directory = await getApplicationDocumentsDirectory();
      final qrCodeDir = Directory('${directory.path}/qr_codes');

      // 确保目录存在
      if (!await qrCodeDir.exists()) {
        await qrCodeDir.create(recursive: true);
      }

      // 保存文件
      final filePath = '${qrCodeDir.path}/$fileName';
      final file = File(filePath);
      await file.writeAsBytes(imageData);

      return filePath;
    } catch (e) {
      _logger.e('保存二维码图片到本地失败', error: e);
      return null;
    }
  }

  /// 23，保存二维码路径到SharedPreferences缓存
  Future<void> _saveQrCodeToCache(String key, String localPath) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, localPath);
    } catch (e) {
      _logger.e('保存二维码路径到缓存失败', error: e);
    }
  }

  /// 24，检查二维码是否需要重新生成（根据二维码路径和ismartId）
  Future<bool> _needRegenerateQrCode(
      String? cachedQrCode, String ismartId) async {
    if (cachedQrCode == null || !cachedQrCode.contains(ismartId)) {
      return true;
    }

    // 检查本地文件是否存在
    return !await File(cachedQrCode).exists();
  }

  /// 25，从缓存加载二维码路径
  Future<void> _loadQrCodesFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _cachedComplaintQrCode = prefs.getString(_complaintQrCodeKey);
      _cachedRegistrationQrCode = prefs.getString(_registrationQrCodeKey);
    } catch (e) {
      debugPrint('从缓存加载二维码失败: $e');
    }
  }

  /// 26，二维码初始化
  Future<void> initializeQrCodesInternal() async {
    // 7.1，从缓存加载二维码路径
    await _loadQrCodesFromCache();
    final ismartId = _settingsModel?.building.ismartId;
    if (ismartId != null && ismartId.isNotEmpty) {
      // 7.2，检查缓存的二维码是否需要重新生成
      bool needRegenerateComplaint =
          await _needRegenerateQrCode(_cachedComplaintQrCode, ismartId);
      bool needRegenerateRegistration =
          await _needRegenerateQrCode(_cachedRegistrationQrCode, ismartId);

      final futures = <Future<void>>[];
      // 7.3，如果需要重新生成，则生成二维码（设置超时时間30秒）
      if (needRegenerateComplaint) {
        _cachedComplaintQrCode = null;
        futures.add(
          generateComplaintQrCode().timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              debugPrint('⚠️ 投訴二維碼生成超時（30秒）');
              return;
            },
          ),
        );
      }

      if (needRegenerateRegistration) {
        _cachedRegistrationQrCode = null;
        futures.add(
          generateRegistrationQrCode().timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              debugPrint('⚠️ 登記二維碼生成超時（30秒）');
              return;
            },
          ),
        );
      }

      // 7.4，等待所有二维码生成完成，但不会因为單个失败而阻塞
      if (futures.isNotEmpty) {
        await Future.wait(futures, eagerError: false);
      }
    }
  }

  /// 27，清除二维码缓存
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

  /// 28，清除投诉二维码缓存
  void clearComplaintQrCodeCache() {
    _cachedComplaintQrCode = null;
  }

  /// 29，清除登记二维码缓存
  void clearRegistrationQrCodeCache() {
    _cachedRegistrationQrCode = null;
  }

  /// 30，直接设置投诉二维码
  Future<void> setComplaintQrCodeDirect(String qrCodeUrl) async {
    _cachedComplaintQrCode = qrCodeUrl;
    await _saveQrCodeToCache(_complaintQrCodeKey, qrCodeUrl);
    notifyListeners();
  }

  /// 31，直接设置登记二维码
  Future<void> setRegistrationQrCodeDirect(String qrCodeUrl) async {
    _cachedRegistrationQrCode = qrCodeUrl;
    await _saveQrCodeToCache(_registrationQrCodeKey, qrCodeUrl);
    notifyListeners();
  }

  /// 32，开始定时登录任务
  void startPeriodicLogin() {
    if (_isPeriodicLoginActive) {
      return;
    }

    _isPeriodicLoginActive = true;

    // 设置定时器进行周期性登录
    _loginTimer = Timer.periodic(const Duration(hours: _loginIntervalHours),
        (timer) async {
      if (_isPeriodicLoginActive && _deviceId != null) {
        final loginSuccess = await _safeLogin(context: '定时登录');
        if (loginSuccess) {
          // 定时登录成功后，刷新设置以确保配置是最新的
          await refreshSettings();
        }
      } else {
        timer.cancel();
      }
    });
  }

  /// 33，停止定时登录任务
  void stopPeriodicLogin() {
    if (_loginTimer != null) {
      _loginTimer!.cancel();
      _loginTimer = null;
    }
    _isPeriodicLoginActive = false;
  }

  /// 34，开始健康检查定时任务
  void startPeriodicHealthCheck() {
    if (_isPeriodicHealthCheckActive) {
      return;
    }

    _isPeriodicHealthCheckActive = true;

    // 设置定时器进行周期性健康检查
    _healthCheckTimer = Timer.periodic(
        const Duration(minutes: _healthCheckIntervalMinutes), (timer) async {
      if (_isPeriodicHealthCheckActive && isLoggedIn) {
        await performHealthCheck();
      } else {
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

  /// 35，停止健康检查定时任务
  void stopPeriodicHealthCheck() {
    if (_healthCheckTimer != null) {
      _healthCheckTimer!.cancel();
      _healthCheckTimer = null;
    }
    _isPeriodicHealthCheckActive = false;
    _logger.i('Periodic health check stopped.');
  }

  /// 36，执行健康检查
  Future<void> performHealthCheck() async {
    if (!isLoggedIn) {
      _logger.w('Device not logged in, cannot perform health check');
      _lastHealthCheckResult = '设备未登录，无法执行健康检查';
      _lastHealthCheckTime = DateTime.now();
      notifyListeners();
      return;
    }

    try {
      final startTime = DateTime.now();

      await _apiClient.healthTest();

      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);

      _lastHealthCheckTime = endTime;
      _lastHealthCheckResult = '✅ 健康检查成功 (${duration.inMilliseconds}ms)';

      notifyListeners();
    } catch (e) {
      final endTime = DateTime.now();
      _lastHealthCheckTime = endTime;
      _lastHealthCheckResult = '❌ 健康检查失败: $e';

      _logger.e('健康检查失败', error: e);
      notifyListeners();
    }
  }

  /// 测试设备注册流程
  Future<void> testDeviceRegistration() async {
    if (_deviceId == null || _deviceId!.isEmpty) {
      _logger.e('设备ID为空，无法测试注册');
      return;
    }

    try {
      await _registerNewDevice(_deviceId!);
    } catch (e) {
      _logger.e('设备注册测试失败', error: e);
      rethrow;
    }
  }

  /// 37，检查缓存中是否存在登录数据
  Future<bool> hasCachedLoginData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_loginDeviceDataKey);
      final hasData = jsonString != null && jsonString.isNotEmpty;
      return hasData;
    } catch (e) {
      _logger.e('检查缓存数据失败', error: e);
      return false;
    }
  }

  /// 38，获取所有SharedPreferences键
  Future<void> debugSharedPreferencesKeys() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      _logger.i('SharedPreferences中的所有键: ${keys.toList()}');

      for (final key in keys) {
        try {
          final value = prefs.get(key);
          final valueStr = value.toString();
          final truncated = valueStr.length > 100
              ? '${valueStr.substring(0, 100)}...'
              : valueStr;
          _logger.d('键: $key, 值类型: ${value.runtimeType}, 值预览: $truncated');
        } catch (e) {
          _logger.w('无法读取键 $key 的值: $e');
        }
      }
    } catch (e) {
      _logger.e('获取SharedPreferences键失败', error: e);
    }
  }

  /// 39，安全登录方法 - 成功才更新缓存，失败则保持现状
  Future<bool> _safeLogin({
    String? context = '登录',
    bool throwOnFailure = false,
  }) async {
    // 保存当前的设置模型，以便登录失败时可以恢复
    final backupSettingsModel = _settingsModel;

    try {
      if (_deviceId == null || _deviceId!.isEmpty) {
        throw Exception('设备ID未设置，无法执行登录');
      }

      final responseData = await _apiClient.login(deviceId: _deviceId!);

      // 只有登录成功时才更新设置模型和缓存
      _settingsModel = SettingsModel.fromJson(responseData);

      // 保存登录设备数据到缓存
      await _saveLoginDeviceData(responseData);

      // 验证并持久化Settings配置
      if (_settingsModel?.settings != null) {
        await _validateAndPersistSettings(_settingsModel!.settings);
      }

      // 设置ArrearProvider的樓宇ID
      if (_settingsModel != null) {
        final buildingIsmartId = _settingsModel!.building.ismartId;
        if (buildingIsmartId.isNotEmpty) {
          _arrearProvider!.setIsmartId(buildingIsmartId);
          // 初始化二维码
          await initializeQrCodesInternal();
        }
      }

      _error = null;
      return true;
    } catch (e) {
      _logger.e('登录失败，保持原有数据状态', error: e);

      // 恢复原有的设置模型，不清除缓存数据
      _settingsModel = backupSettingsModel;

      // 如果有备份的设置模型，确保API客户端有正确的token
      if (backupSettingsModel?.token != null) {
        _apiClient.setAuthToken(backupSettingsModel!.token);
      }

      // 只有在没有任何数据时才设置错误信息
      if (backupSettingsModel == null) {
        _error = '$context failed: $e';
      }

      if (throwOnFailure) {
        rethrow;
      }
      return false;
    }
  }

  /// 40，手动登录方法 - 使用安全登录机制
  Future<void> manualLogin() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _safeLogin(context: '手动登录', throwOnFailure: true);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    stopPeriodicLogin();
    stopPeriodicHealthCheck();
    super.dispose();
  }

  /// 41，获取验证后的设置 - 确保所有时间字段都有合理的默认值
  Settings? get validatedDeviceSettings {
    final settings = _settingsModel?.settings;
    if (settings == null) return null;

    // 返回验证后的设置对象
    return Settings(
      arrearageUpdateDuration: settings.arrearageUpdateDuration > 0
          ? settings.arrearageUpdateDuration
          : 30,
      noticeUpdateDuration:
          settings.noticeUpdateDuration > 0 ? settings.noticeUpdateDuration : 5,
      advertisementUpdateDuration: settings.advertisementUpdateDuration > 0
          ? settings.advertisementUpdateDuration
          : 10,
      appUpdateDuration:
          settings.appUpdateDuration > 0 ? settings.appUpdateDuration : 60,
      advertisementPlayDuration: settings.advertisementPlayDuration > 0
          ? settings.advertisementPlayDuration
          : 10,
      noticePlayDuration:
          settings.noticePlayDuration > 0 ? settings.noticePlayDuration : 15,
      spareDuration: settings.spareDuration > 0 ? settings.spareDuration : 30,
      noticeStayDuration:
          settings.noticeStayDuration > 0 ? settings.noticeStayDuration : 5,
      bottomCarouselDuration: settings.bottomCarouselDuration > 0
          ? settings.bottomCarouselDuration
          : 10,
      paymentTableOnePageDuration: settings.paymentTableOnePageDuration > 0
          ? settings.paymentTableOnePageDuration
          : 5,
      normalToAnnouncementCarouselDuration:
          settings.normalToAnnouncementCarouselDuration > 0
              ? settings.normalToAnnouncementCarouselDuration
              : 5,
      announcementCarouselToFullAdsCarouselDuration:
          settings.announcementCarouselToFullAdsCarouselDuration > 0
              ? settings.announcementCarouselToFullAdsCarouselDuration
              : 5,
    );
  }
}
