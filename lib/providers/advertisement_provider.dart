import 'dart:async';
import 'package:flutter/material.dart';
import 'package:iboard_app/http/api_client.dart';
import 'package:iboard_app/models/ad_model.dart';
import 'package:iboard_app/providers/app_data_provider.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:iboard_app/utils/enhanced_video_pool_manager.dart';
import 'package:iboard_app/providers/ad_top_carousel_provider.dart';
import 'package:iboard_app/providers/ad_full_carousel_provider.dart';

class AdvertisementProvider extends ChangeNotifier {
  final Logger _logger = Logger();
  // 原始广告数据缓存key
  static const String _advertisementsDataKey = 'advertisements_data';
  // 顶部广告轮播数据缓存key
  static const String _topCarouselAdvertisementsKey =
      'top_carousel_advertisements';
  // 全屏广告轮播数据缓存key
  static const String _fullCarouselAdvertisementsKey =
      'full_carousel_advertisements';

  final ApiClient _apiClient;
  final AppDataProvider _appDataProvider;
  final EnhancedVideoPoolManager _videoPoolManager = EnhancedVideoPoolManager();

  // 轮播Provider引用
  TopAdCarouselProvider? _topAdCarouselProvider;
  FullscreenAdProvider? _fullscreenAdProvider;

  List<AdModel> _advertisements = [];
  List<AdModel> _topCarouselAdvertisements = [];
  List<AdModel> _fullCarouselAdvertisements = [];
  bool _isLoading = false;
  String? _error;
  Timer? _updateTimer;
  bool _isPeriodicUpdateActive = false;

  // Getters
  List<AdModel> get advertisements => _advertisements;
  List<AdModel> get topAdvertisements => _advertisements
      .where((ad) =>
          ad.display == AdDisplayType.top ||
          ad.display == AdDisplayType.topfull)
      .toList();
  List<AdModel> get fullAdvertisements => _advertisements
      .where((ad) =>
          ad.display == AdDisplayType.full ||
          ad.display == AdDisplayType.topfull)
      .toList();
  // 新增轮播广告获取器
  List<AdModel> get topCarouselAdvertisements => _topCarouselAdvertisements;
  List<AdModel> get fullCarouselAdvertisements => _fullCarouselAdvertisements;

  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isPeriodicUpdateActive => _isPeriodicUpdateActive;
  ApiClient get apiClient => _apiClient; // 添加apiClient getter用于比较

  AdvertisementProvider(this._apiClient, this._appDataProvider) {
    _loadAdvertisementsFromCache(); // 启动时从缓存加载数据
    _loadCarouselAdvertisementsFromCache(); // 加载轮播广告数据

    // 延迟检查AppDataProvider登录状态，确保初始化完成
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_appDataProvider.isLoggedIn) {
        _logger.i('AppDataProvider已登录，自动启动广告定时更新');
        startPeriodicUpdate();
      } else {
        _logger.w('AppDataProvider未登录，跳过自动启动广告定时更新');
      }
    });
  }

  ///11，设置轮播Provider引用
  void setCarouselProviders({
    required TopAdCarouselProvider topAdCarouselProvider,
    required FullscreenAdProvider fullscreenAdProvider,
  }) {
    _topAdCarouselProvider = topAdCarouselProvider;
    _fullscreenAdProvider = fullscreenAdProvider;
  }

  ///2，保存顶部广告轮播数据到缓存
  Future<void> _saveTopCarouselAdvertisementsToCache(
      List<AdModel> advertisements) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<Map<String, dynamic>> adsJson =
          advertisements.map((ad) => ad.toJson()).toList();
      final jsonString = json.encode(adsJson);
      await prefs.setString(_topCarouselAdvertisementsKey, jsonString);
    } catch (e) {
      _logger.e('保存頂部廣告輪播數據到緩存失敗', error: e);
    }
  }

  ///3，保存全屏广告轮播数据到缓存
  Future<void> _saveFullCarouselAdvertisementsToCache(
      List<AdModel> advertisements) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<Map<String, dynamic>> adsJson =
          advertisements.map((ad) => ad.toJson()).toList();
      final jsonString = json.encode(adsJson);
      await prefs.setString(_fullCarouselAdvertisementsKey, jsonString);
    } catch (e) {
      _logger.e('保存全屏廣告輪播數據到緩存失敗', error: e);
    }
  }

  ///4，从SharedPreferences缓存加载广告数据
  Future<void> _loadAdvertisementsFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_advertisementsDataKey);
      if (jsonString != null && jsonString.isNotEmpty) {
        final List<dynamic> adsJson = json.decode(jsonString) as List<dynamic>;
        final List<AdModel> cachedAds = adsJson
            .map((adJson) => AdModel.fromJson(adJson as Map<String, dynamic>))
            .toList();

        _advertisements = cachedAds;
        notifyListeners();
      } else {
        _logger.w('緩存中沒有找到廣告數據');
      }
    } catch (e) {
      _logger.e('從緩存加載廣告數據失敗', error: e);
    }
  }

  ///12，初始化輪播Provider的緩存數據
  void _initializeCarouselProvidersWithCache() {
    // 將緩存的輪播數據傳遞給對應的Provider
    if (_topAdCarouselProvider != null &&
        _topCarouselAdvertisements.isNotEmpty) {
      _logger.i('🔄 從緩存初始化頂部廣告輪播: ${_topCarouselAdvertisements.length} 個廣告');
      _topAdCarouselProvider!.updateCarouselList(_topCarouselAdvertisements);
    }

    if (_fullscreenAdProvider != null &&
        _fullCarouselAdvertisements.isNotEmpty) {
      _logger.i('🔄 從緩存初始化全屏廣告輪播: ${_fullCarouselAdvertisements.length} 個廣告');
      _fullscreenAdProvider!.updateCarouselList(_fullCarouselAdvertisements);
    }
  }

  ///13，初始化時獲取輪播廣告數據
  Future<void> initializeCarouselAdvertisements() async {
    if (_appDataProvider.token == null) {
      _logger.w('Token為空，跳過初始化輪播廣告數據');
      return;
    }

    try {
      _logger.i('🚀 初始化時獲取輪播廣告數據...');

      // 並行獲取輪播數據
      final List<Future> futures = [
        _apiClient.getCarouselTopAdvertisements(),
        _apiClient.getCarouselFullAdvertisements(),
      ];

      final List results = await Future.wait(futures);

      // 處理頂部廣告輪播數據
      final List<Map<String, dynamic>> topCarouselData =
          results[0] as List<Map<String, dynamic>>;
      final List<AdModel> newTopCarouselAds = topCarouselData
          .map((jsonItem) => AdModel.fromJson(jsonItem))
          .toList();

      // 處理全屏廣告輪播數據
      final List<Map<String, dynamic>> fullCarouselData =
          results[1] as List<Map<String, dynamic>>;
      final List<AdModel> newFullCarouselAds = fullCarouselData
          .map((jsonItem) => AdModel.fromJson(jsonItem))
          .toList();

      // 更新頂部廣告輪播數據
      _topCarouselAdvertisements = List<AdModel>.from(newTopCarouselAds);
      await _saveTopCarouselAdvertisementsToCache(_topCarouselAdvertisements);
      _logger.i('✅ 初始化頂部廣告輪播數據: ${_topCarouselAdvertisements.length} 個廣告');

      // 更新全屏廣告輪播數據
      _fullCarouselAdvertisements = List<AdModel>.from(newFullCarouselAds);
      await _saveFullCarouselAdvertisementsToCache(_fullCarouselAdvertisements);
      _logger.i('✅ 初始化全屏廣告輪播數據: ${_fullCarouselAdvertisements.length} 個廣告');

      // 如果Provider已經設置，立即更新
      if (_topAdCarouselProvider != null) {
        _topAdCarouselProvider!.updateCarouselList(_topCarouselAdvertisements);
      }

      if (_fullscreenAdProvider != null) {
        _fullscreenAdProvider!.updateCarouselList(_fullCarouselAdvertisements);
      }

      notifyListeners();
    } catch (e) {
      _logger.e('初始化輪播廣告數據失敗', error: e);
      // 初始化失敗時，嘗試使用緩存數據
      _initializeCarouselProvidersWithCache();
    }
  }

  ///5，從緩存加載頂部廣告輪播數據
  Future<void> _loadTopCarouselAdvertisementsFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_topCarouselAdvertisementsKey);
      if (jsonString != null && jsonString.isNotEmpty) {
        final List<dynamic> adsJson = json.decode(jsonString) as List<dynamic>;
        final List<AdModel> cachedAds = adsJson
            .map((adJson) => AdModel.fromJson(adJson as Map<String, dynamic>))
            .toList();

        _topCarouselAdvertisements = cachedAds;
        _logger.i('✅ 從緩存加載頂部廣告輪播數據: ${cachedAds.length} 個廣告');
        notifyListeners();
      } else {
        _logger.w('緩存中沒有找到頂部廣告輪播數據');
      }
    } catch (e) {
      _logger.e('從緩存加載頂部廣告輪播數據失敗', error: e);
    }
  }

  ///6，从缓存加载全屏广告轮播数据
  Future<void> _loadFullCarouselAdvertisementsFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_fullCarouselAdvertisementsKey);
      if (jsonString != null && jsonString.isNotEmpty) {
        final List<dynamic> adsJson = json.decode(jsonString) as List<dynamic>;
        final List<AdModel> cachedAds = adsJson
            .map((adJson) => AdModel.fromJson(adJson as Map<String, dynamic>))
            .toList();

        _fullCarouselAdvertisements = cachedAds;

        notifyListeners();
      }
    } catch (e) {
      _logger.e('從緩存加載全屏廣告輪播數據失敗', error: e);
    }
  }

  ///7，加载所有轮播广告数据
  Future<void> _loadCarouselAdvertisementsFromCache() async {
    await _loadTopCarouselAdvertisementsFromCache();
    await _loadFullCarouselAdvertisementsFromCache();
  }

  ///8，清除广告数据缓存
  ///4，检查顶部广告轮播数据是否发生了变化
  bool _hasTopCarouselDataChanged(List<AdModel> newTopCarouselAds) {
    if (_topCarouselAdvertisements.length != newTopCarouselAds.length) {
      return true;
    }

    // 判断广告list是否变化(只需要比对id即可比对顺序和数据是否对的上)
    for (int i = 0; i < _topCarouselAdvertisements.length; i++) {
      final old = _topCarouselAdvertisements[i];
      final newer = newTopCarouselAds[i];
      if (old.id != newer.id) {
        return true;
      }
    }
    return false;
  }

  ///5，检查全屏广告轮播数据是否发生了变化
  bool _hasFullCarouselDataChanged(List<AdModel> newFullCarouselAds) {
    if (_fullCarouselAdvertisements.length != newFullCarouselAds.length) {
      return true;
    }

    // 判断广告list是否变化(只需要比对id即可比对顺序和数据是否对的上)
    for (int i = 0; i < _fullCarouselAdvertisements.length; i++) {
      final old = _fullCarouselAdvertisements[i];
      final newer = newFullCarouselAds[i];
      if (old.id != newer.id) {
        return true;
      }
    }
    return false;
  }

  ///6，检查数据是否真的发生了变化
  @override
  void dispose() {
    stopPeriodicUpdate();
    super.dispose();
  }

  /// 开始定期更新广告数据
  void startPeriodicUpdate() {
    if (_isPeriodicUpdateActive) {
      return;
    }

    // 获取更新间隔时间（从设置中获取，单位：分钟）
    final updateIntervalMinutes =
        _appDataProvider.deviceSettings?.advertisementUpdateDuration ??
            5; // 默认5分钟
    final updateIntervalSeconds = updateIntervalMinutes * 60; // 转换为秒
    _isPeriodicUpdateActive = true;

    // 立即执行一次更新
    fetchAdvertisements();

    // 设置定时器进行周期性更新
    _updateTimer =
        Timer.periodic(Duration(seconds: updateIntervalSeconds), (timer) {
      if (_isPeriodicUpdateActive) {
        fetchAdvertisements();
      } else {
        timer.cancel();
      }
    });
  }

  /// 停止定期更新
  void stopPeriodicUpdate() {
    if (_updateTimer != null) {
      _updateTimer!.cancel();
      _updateTimer = null;
    }
    _isPeriodicUpdateActive = false;
  }

  /// 重新初始化Provider（当依赖变化时调用）
  void reinitialize() {
    // 停止现有的定时更新
    stopPeriodicUpdate();

    // 重新加载缓存数据
    _loadAdvertisementsFromCache();
    _loadCarouselAdvertisementsFromCache(); // 重新加载轮播广告

    // 如果AppDataProvider已登录，重新启动定时更新
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_appDataProvider.isLoggedIn) {
        startPeriodicUpdate();
      }
    });
  }

  /// 检查文件是否已缓存（使用 FileManager 检查）
  ///7，智能对比更新广告列表
  // Interface to fetch/update advertisements
  Future<void> fetchAdvertisements() async {
    if (_appDataProvider.token == null) {
      _error = "Authentication token is missing. Cannot fetch advertisements.";
      _logger.w(_error);
      notifyListeners();
      return;
    }

    // 防止重复调用 - 如果正在加载中，直接返回
    if (_isLoading) {
      _logger.w(
          'fetchAdvertisements already in progress, skipping duplicate call.');
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _logger.i('Fetching advertisements from building...');

      // 并行获取所有轮播数据
      final List<Future> futures = [
        _apiClient.getCarouselTopAdvertisements(),
        _apiClient.getCarouselFullAdvertisements(),
        // _apiClient.getAdvertisementsBuilding(), // 保留原有的广告接口作为备用
      ];

      final List results = await Future.wait(futures);

      // 处理顶部广告轮播数据
      final List<Map<String, dynamic>> topCarouselData =
          results[0] as List<Map<String, dynamic>>;
      final List<AdModel> newTopCarouselAds = topCarouselData
          .map((jsonItem) => AdModel.fromJson(jsonItem))
          .toList();

      // 处理全屏广告轮播数据
      final List<Map<String, dynamic>> fullCarouselData =
          results[1] as List<Map<String, dynamic>>;
      final List<AdModel> newFullCarouselAds = fullCarouselData
          .map((jsonItem) => AdModel.fromJson(jsonItem))
          .toList();
      // 检查顶部广告轮播数据是否变化
      final bool hasTopCarouselChanges =
          _hasTopCarouselDataChanged(newTopCarouselAds);
      if (hasTopCarouselChanges) {
        _logger.i('检测到顶部广告轮播数据变化，开始更新...');
        _topCarouselAdvertisements = List<AdModel>.from(newTopCarouselAds);
        await _saveTopCarouselAdvertisementsToCache(_topCarouselAdvertisements);

        // 通知轮播Provider更新数据
        if (_topAdCarouselProvider != null) {
          _topAdCarouselProvider!
              .updateCarouselList(_topCarouselAdvertisements);
        }
      } else {
        _logger.i('顶部广告轮播数据无变化，跳过更新操作');
      }

      // 检查全屏广告轮播数据是否变化
      final bool hasFullCarouselChanges =
          _hasFullCarouselDataChanged(newFullCarouselAds);
      if (hasFullCarouselChanges) {
        _logger.i('检测到全屏广告轮播数据变化，开始更新...');
        _fullCarouselAdvertisements = List<AdModel>.from(newFullCarouselAds);
        await _saveFullCarouselAdvertisementsToCache(
            _fullCarouselAdvertisements);

        // 通知轮播Provider更新数据
        if (_fullscreenAdProvider != null) {
          _fullscreenAdProvider!
              .updateCarouselList(_fullCarouselAdvertisements);
        }
      } else {
        _logger.i('全屏广告轮播数据无变化，跳过更新操作');
      }

      _logger.i(
          'Advertisement update completed. Top carousel: ${_topCarouselAdvertisements.length}, Full carousel: ${_fullCarouselAdvertisements.length}, General: ${_advertisements.length}');
      _error = null; // 成功时清除错误
    } on ApiException catch (e) {
      _logger.e('Failed to fetch advertisements (ApiException)',
          error: e, stackTrace: e.errorData is StackTrace ? e.errorData : null);

      // 检查是否是 token 过期错误
      if (e.statusCode == 401 ||
          e.message.toLowerCase().contains('token is expired')) {
        _logger.w('Token expired detected, attempting to refresh token...');
        try {
          // 尝试重新登录获取新 token
          await _appDataProvider.initializeAndLogin();
          if (_appDataProvider.isLoggedIn) {
            _logger
                .i('Token refresh successful, retrying advertisement fetch...');
            // 设置标志位防止递归调用导致的问题
            _isLoading = false; // 重置状态
            // 递归调用自己重试 (只重试一次，避免无限循环)
            await fetchAdvertisements();
            return; // 成功后直接返回，不执行后续的错误处理
          } else {
            _error = 'Token refresh failed: Unable to re-authenticate';
          }
        } catch (refreshError) {
          _logger.e('Token refresh failed', error: refreshError);
          _error = 'Token expired and refresh failed: $refreshError';
        }
      } else {
        _error = 'Failed to fetch advertisements: ${e.message}';
      }
      // 网络错误或其他错误时不清除现有数据，保持现状
    } catch (e, stackTrace) {
      _logger.e('An unexpected error occurred while fetching advertisements',
          error: e, stackTrace: stackTrace);

      // 详细的网络错误处理
      String errorMessage;
      bool isNetworkError = false;

      if (e.toString().contains('SocketException') ||
          e.toString().contains('Connection timed out') ||
          e.toString().contains('ClientException')) {
        errorMessage = '網絡連線失敗，使用快取的廣告資料繼續輪播';
        isNetworkError = true;
        _logger.w('網絡連線問題檢測到，保持現有資料: $e');
      } else if (e.toString().contains('TimeoutException') ||
          e.toString().contains('請求超時')) {
        errorMessage = '請求超時，使用快取的廣告資料繼續輪播';
        isNetworkError = true;
        _logger.w('請求超時檢測到，保持現有資料: $e');
      } else if (e.toString().contains('FormatException')) {
        errorMessage = '伺服器返回資料格式錯誤，保持現有廣告資料';
        _logger.w('資料格式錯誤檢測到，保持現有資料: $e');
      } else {
        errorMessage = '發生未知錯誤，保持現有廣告資料: $e';
        _logger.w('未知錯誤檢測到，保持現有資料: $e');
      }

      _error = errorMessage;

      // 网络错误时检查并确保有可用的广告数据
      if (isNetworkError) {
        await _ensureCachedAdvertisementsAvailable();
      }

      _logger.i(
          '错误处理完成，保持现有广告数据: ${_advertisements.length}个广告，${_topCarouselAdvertisements.length}个顶部轮播广告，${_fullCarouselAdvertisements.length}个全屏轮播广告');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Interface to get a specific advertisement by ID (if needed)
  AdModel? getAdvertisementById(int id) {
    try {
      return _advertisements.firstWhere((ad) => ad.id == id);
    } catch (e) {
      return null; // Not found
    }
  }

  // Get advertisements by display type
  List<AdModel> getAdvertisementsByDisplay(AdDisplayType display) {
    return _advertisements.where((ad) => ad.display == display).toList();
  }

  /// 确保在网络错误时有可用的缓存广告数据
  Future<void> _ensureCachedAdvertisementsAvailable() async {
    try {
      // 如果当前没有广告数据，尝试从缓存中加载
      if (_advertisements.isEmpty) {
        _logger.i('当前广告列表为空，尝试从缓存中恢复广告数据...');
        await _loadAdvertisementsFromCache();

        if (_advertisements.isNotEmpty) {
          _logger.i('从缓存成功恢复广告数据: ${_advertisements.length}个广告');
          // 恢复数据后也要更新视频池
          await _updateVideoPool();
        } else {
          _logger.w('缓存中也没有可用的广告数据');
        }
      } else {
        _logger.i('当前已有广告数据，继续使用现有数据: ${_advertisements.length}个广告');
      }
    } catch (e) {
      _logger.e('确保缓存广告数据可用时发生错误', error: e);
    }
  }

  ///8，更新视频池管理器（私有方法）
  Future<void> _updateVideoPool() async {
    try {
      // 提取顶部广告中的视频文件路径
      final topAdVideos = topAdvertisements
          .where((ad) =>
              ad.type == 'video' &&
              ad.file.localFilePath != null &&
              ad.file.localFilePath!.isNotEmpty)
          .map((ad) => ad.file.localFilePath!)
          .toList();

      // 提取全屏广告中的视频文件路径
      final fullAdVideos = fullAdvertisements
          .where((ad) =>
              ad.type == 'video' &&
              ad.file.localFilePath != null &&
              ad.file.localFilePath!.isNotEmpty)
          .map((ad) => ad.file.localFilePath!)
          .toList();

      _logger.i(
          '🎬 [广告Provider] 更新视频池: 顶部${topAdVideos.length}个, 全屏${fullAdVideos.length}个');

      // 更新视频池
      await _videoPoolManager.updateVideoList(
        topAdVideos: topAdVideos,
        fullAdVideos: fullAdVideos,
        isNetwork: false, // 假设都是本地文件
      );

      final status = _videoPoolManager.getPoolStatus();
      _logger.i(
          '✅ [广告Provider] 视频池更新完成 - 总数:${status['totalSize']}, 使用中:${status['inUse']}, 可用:${status['available']}');
    } catch (e) {
      _logger.e('❌ [广告Provider] 更新视频池失败: $e');
    }
  }

  ///9，获取视频池状态信息（调试用）
  Map<String, dynamic> getVideoPoolStatus() {
    return _videoPoolManager.getPoolStatus();
  }

  ///10，强制清理特定视频的控制器
  Future<void> forceRemoveVideoController({
    required String filePath,
    required VideoType videoType,
  }) async {
    try {
      await _videoPoolManager.forceRemoveController(
        filePath: filePath,
        videoType: videoType,
        isNetwork: false,
      );
      _logger.i(
          '🗑️ [广告Provider] 强制移除视频控制器: ${videoType == VideoType.topAd ? '顶部' : '全屏'}:$filePath');
    } catch (e) {
      _logger.e('❌ [广告Provider] 强制移除视频控制器失败: $e');
    }
  }

  ///11，获取视频池管理器实例（供组件使用）
  EnhancedVideoPoolManager get videoPoolManager => _videoPoolManager;

  ///12，调试方法：打印视频池状态
  void debugPrintVideoPoolStatus() {
    _videoPoolManager.debugPrintPoolStatus();
  }

  // Potentially add methods to add/update/delete advertisements if the API supports it
  // and if such functionality is required by the app.
  // For now, focusing on fetching and displaying.
}
