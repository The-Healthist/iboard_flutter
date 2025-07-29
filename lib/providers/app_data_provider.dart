import 'package:flutter/material.dart';
import 'package:iboard_app/http/api_client.dart';
import 'package:iboard_app/models/settings_model.dart';
import 'package:iboard_app/providers/state_provider.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:iboard_app/providers/arrear_provider.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

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

  // 二维码缓存相关 - 现在存储本地文件路径
  String? _cachedComplaintQrCode;
  String? _cachedRegistrationQrCode;
  static const String _complaintQrCodeKey = 'complaint_qr_code_path';
  static const String _registrationQrCodeKey = 'registration_qr_code_path';

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
            // 初始化二维码
            await initializeQrCodes();
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

  ///1，生成意见投诉二维码（下载到本地）
  Future<String?> generateComplaintQrCode() async {
    if (_cachedComplaintQrCode != null) {
      // 检查是网络URL还是本地文件
      if (_cachedComplaintQrCode!.startsWith('http')) {
        _logger.i('📱 使用缓存的意见投诉二维码URL: $_cachedComplaintQrCode');
        return _cachedComplaintQrCode;
      } else {
        // 检查本地文件是否存在
        final file = File(_cachedComplaintQrCode!);
        if (await file.exists()) {
          _logger.i('📱 使用缓存的意见投诉二维码文件: $_cachedComplaintQrCode');
          return _cachedComplaintQrCode;
        } else {
          _logger.w('⚠️ 缓存的二维码文件不存在，重新下载');
          _cachedComplaintQrCode = null;
        }
      }
    }

    final ismartId = _settingsModel?.building.ismartId;
    _logger.i('🔍 当前ismartId: $ismartId');
    if (ismartId == null || ismartId.isEmpty) {
      _logger.w('⚠️ 无法生成意见投诉二维码：ismartId为空');
      return null;
    }

    try {
      final qrCodeUrl =
          'https://api.qrserver.com/v1/create-qr-code/?size=88x88&data=https://ismart.legend-in.com.hk/blg_cs_public/$ismartId';
      _logger.i('🔗 生成的投诉二维码URL: $qrCodeUrl');

      // 下载二维码图片到本地
      _logger.i('🔄 开始尝试下载投诉二维码到本地...');
      final localPath =
          await _downloadQrCodeToLocal(qrCodeUrl, 'complaint_qr_$ismartId.png');
      if (localPath != null) {
        _cachedComplaintQrCode = localPath;
        await _saveQrCodeToCache(_complaintQrCodeKey, localPath);
        _logger.i('✅ 意见投诉二维码下载成功并缓存到: $localPath');
        notifyListeners();
        return localPath;
      } else {
        // 回退策略：如果下载失败，直接使用网络URL
        _logger.w('⚠️ 下载意见投诉二维码失败，回退到使用网络URL');
        _cachedComplaintQrCode = qrCodeUrl;
        await _saveQrCodeToCache(_complaintQrCodeKey, qrCodeUrl);
        _logger.i('🔄 意见投诉二维码回退到网络URL: $qrCodeUrl');
        notifyListeners();
        return qrCodeUrl;
      }
    } catch (e) {
      _logger.e('❌ 生成意见投诉二维码失败', error: e);
      return null;
    }
  }

  ///2，生成住户登记二维码（下载到本地）
  Future<String?> generateRegistrationQrCode() async {
    if (_cachedRegistrationQrCode != null) {
      // 检查是网络URL还是本地文件
      if (_cachedRegistrationQrCode!.startsWith('http')) {
        _logger.i('📱 使用缓存的住户登记二维码URL: $_cachedRegistrationQrCode');
        return _cachedRegistrationQrCode;
      } else {
        // 检查本地文件是否存在
        final file = File(_cachedRegistrationQrCode!);
        if (await file.exists()) {
          _logger.i('📱 使用缓存的住户登记二维码文件: $_cachedRegistrationQrCode');
          return _cachedRegistrationQrCode;
        } else {
          _logger.w('⚠️ 缓存的二维码文件不存在，重新下载');
          _cachedRegistrationQrCode = null;
        }
      }
    }

    final ismartId = _settingsModel?.building.ismartId;
    _logger.i('🔍 当前ismartId: $ismartId');
    if (ismartId == null || ismartId.isEmpty) {
      _logger.w('⚠️ 无法生成住户登记二维码：ismartId为空');
      return null;
    }

    try {
      final qrCodeUrl =
          'https://api.qrserver.com/v1/create-qr-code/?size=88x88&data=https://ismart.legend-in.com.hk/regform/$ismartId';
      _logger.i('🔗 生成的登记二维码URL: $qrCodeUrl');

      // 下载二维码图片到本地
      final localPath = await _downloadQrCodeToLocal(
          qrCodeUrl, 'registration_qr_$ismartId.png');
      if (localPath != null) {
        _cachedRegistrationQrCode = localPath;
        await _saveQrCodeToCache(_registrationQrCodeKey, localPath);
        _logger.i('✅ 住户登记二维码下载成功并缓存到: $localPath');
        notifyListeners();
        return localPath;
      } else {
        // 回退策略：如果下载失败，直接使用网络URL
        _logger.w('⚠️ 下载住户登记二维码失败，回退到使用网络URL');
        _cachedRegistrationQrCode = qrCodeUrl;
        await _saveQrCodeToCache(_registrationQrCodeKey, qrCodeUrl);
        _logger.i('🔄 住户登记二维码回退到网络URL: $qrCodeUrl');
        notifyListeners();
        return qrCodeUrl;
      }
    } catch (e) {
      _logger.e('❌ 生成住户登记二维码失败', error: e);
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

  ///4，保存二维码路径到SharedPreferences缓存
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

    // 如果是网络URL，不需要检查文件存在
    if (cachedQrCode.startsWith('http')) {
      return false;
    }

    // 如果是本地文件路径，检查文件是否存在
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
      // 如果投诉二维码为空，使用网络URL
      if (_cachedComplaintQrCode == null) {
        _cachedComplaintQrCode =
            'https://api.qrserver.com/v1/create-qr-code/?size=88x88&data=https://ismart.legend-in.com.hk/blg_cs_public/$ismartId';
        _logger.i('🔄 投诉二维码使用网络URL备选方案');
      }

      // 如果登记二维码为空，使用网络URL
      if (_cachedRegistrationQrCode == null) {
        _cachedRegistrationQrCode =
            'https://api.qrserver.com/v1/create-qr-code/?size=88x88&data=https://ismart.legend-in.com.hk/regform/$ismartId';
        _logger.i('🔄 登记二维码使用网络URL备选方案');
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
          _logger.w('⏰ 投诉二维码生成超时，使用网络URL');
          final ismartId = _settingsModel?.building.ismartId;
          if (ismartId != null) {
            _cachedComplaintQrCode =
                'https://api.qrserver.com/v1/create-qr-code/?size=88x88&data=https://ismart.legend-in.com.hk/blg_cs_public/$ismartId';
          }
          return null;
        },
      );
    } catch (e) {
      _logger.w('⚠️ 投诉二维码生成失败，使用网络URL备选方案', error: e);
      final ismartId = _settingsModel?.building.ismartId;
      if (ismartId != null) {
        _cachedComplaintQrCode =
            'https://api.qrserver.com/v1/create-qr-code/?size=88x88&data=https://ismart.legend-in.com.hk/blg_cs_public/$ismartId';
      }
    }
  }

  ///11，带超时的登记二维码生成
  Future<void> _generateRegistrationQrCodeWithTimeout() async {
    try {
      await generateRegistrationQrCode().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          _logger.w('⏰ 登记二维码生成超时，使用网络URL');
          final ismartId = _settingsModel?.building.ismartId;
          if (ismartId != null) {
            _cachedRegistrationQrCode =
                'https://api.qrserver.com/v1/create-qr-code/?size=88x88&data=https://ismart.legend-in.com.hk/regform/$ismartId';
          }
          return null;
        },
      );
    } catch (e) {
      _logger.w('⚠️ 登记二维码生成失败，使用网络URL备选方案', error: e);
      final ismartId = _settingsModel?.building.ismartId;
      if (ismartId != null) {
        _cachedRegistrationQrCode =
            'https://api.qrserver.com/v1/create-qr-code/?size=88x88&data=https://ismart.legend-in.com.hk/regform/$ismartId';
      }
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
}
