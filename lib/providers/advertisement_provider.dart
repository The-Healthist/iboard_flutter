import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:iboard_app/http/api_client.dart';
import 'package:iboard_app/models/ad_model.dart';
import 'package:iboard_app/providers/app_data_provider.dart';
import 'package:iboard_app/managers/file_manager.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class AdvertisementProvider extends ChangeNotifier {
  final Logger _logger = Logger();
  final ApiClient _apiClient;
  final AppDataProvider _appDataProvider;
  final FileManager _fileManager;

  List<AdModel> _advertisements = [];
  bool _isLoading = false;
  String? _error;
  Timer? _updateTimer; // 定时更新定时器
  bool _isPeriodicUpdateActive = false; // 是否正在进行定期更新

  static const String _advertisementsDataKey =
      'advertisements_data'; // 原始广告数据缓存key

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
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isPeriodicUpdateActive => _isPeriodicUpdateActive;

  AdvertisementProvider(
      this._apiClient, this._appDataProvider, this._fileManager) {
    _logger.i('AdvertisementProvider initialized.');
    _loadAdvertisementsFromCache(); // 启动时从缓存加载数据

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

  ///1，保存广告数据到SharedPreferences缓存
  Future<void> _saveAdvertisementsToCache(List<AdModel> advertisements) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<Map<String, dynamic>> adsJson =
          advertisements.map((ad) => ad.toJson()).toList();
      final jsonString = json.encode(adsJson);
      await prefs.setString(_advertisementsDataKey, jsonString);
      _logger.i('💾 广告数据已保存到缓存: ${advertisements.length}个广告');
    } catch (e) {
      _logger.e('保存广告数据到缓存失败', error: e);
    }
  }

  ///2，从SharedPreferences缓存加载广告数据
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
        _logger.i('📂 从缓存加载广告数据成功: ${cachedAds.length}个广告');
        notifyListeners();
      } else {
        _logger.w('缓存中没有找到广告数据');
      }
    } catch (e) {
      _logger.e('从缓存加载广告数据失败', error: e);
    }
  }

  ///3，清除广告数据缓存
  Future<void> _clearAdvertisementsCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_advertisementsDataKey);
      _logger.i('广告数据缓存已清除');
    } catch (e) {
      _logger.e('清除广告数据缓存失败', error: e);
    }
  }

  ///4，检查数据是否真的发生了变化
  bool _hasDataChanged(List<AdModel> newAdvertisements) {
    if (_advertisements.length != newAdvertisements.length) {
      return true;
    }

    // 创建ID到广告的映射以便快速比较
    final currentAdsMap = {for (AdModel ad in _advertisements) ad.id: ad};
    final newAdsMap = {for (AdModel ad in newAdvertisements) ad.id: ad};

    // 检查是否有新增或删除的广告
    if (currentAdsMap.keys
            .toSet()
            .difference(newAdsMap.keys.toSet())
            .isNotEmpty ||
        newAdsMap.keys
            .toSet()
            .difference(currentAdsMap.keys.toSet())
            .isNotEmpty) {
      return true;
    }

    // 检查现有广告是否有内容变化
    for (final id in currentAdsMap.keys) {
      final currentAd = currentAdsMap[id]!;
      final newAd = newAdsMap[id]!;

      // 比较关键字段
      if (currentAd.title != newAd.title ||
          currentAd.description != newAd.description ||
          currentAd.duration != newAd.duration ||
          currentAd.file.url != newAd.file.url ||
          currentAd.file.md5 != newAd.file.md5) {
        return true;
      }
    }

    return false;
  }

  @override
  void dispose() {
    stopPeriodicUpdate();
    super.dispose();
  }

  /// 开始定期更新广告数据
  void startPeriodicUpdate() {
    if (_isPeriodicUpdateActive) {
      _logger.i('Periodic advertisement update is already active.');
      return;
    }

    // 获取更新间隔时间（从设置中获取，单位：分钟）
    final updateIntervalMinutes =
        _appDataProvider.deviceSettings?.advertisementUpdateDuration ??
            5; // 默认5分钟
    final updateIntervalSeconds = updateIntervalMinutes * 60; // 转换为秒
    _logger.i(
        'Starting periodic advertisement update with interval: ${updateIntervalMinutes} minutes (${updateIntervalSeconds}s)');

    _isPeriodicUpdateActive = true;

    // 立即执行一次更新
    fetchAdvertisements();

    // 设置定时器进行周期性更新
    _updateTimer =
        Timer.periodic(Duration(seconds: updateIntervalSeconds), (timer) {
      if (_isPeriodicUpdateActive) {
        _logger.i('Performing periodic advertisement update...');
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
    _logger.i('Periodic advertisement update stopped.');
  }

  /// 检查文件是否已缓存（使用 FileManager 检查）
  Future<bool> _isFileCached(String md5, String url) async {
    try {
      // 使用 FileManager 的命名规则检查文件是否存在
      final String fileNameFromUrl = Uri.parse(url).pathSegments.last;
      final String expectedFileName = '${md5}_$fileNameFromUrl';

      // 检查 FileManager 的缓存目录
      final Directory appDir = await getApplicationDocumentsDirectory();
      final Directory fileManagerCacheDir =
          Directory('${appDir.path}/file_cache');

      if (await fileManagerCacheDir.exists()) {
        final File expectedFile =
            File('${fileManagerCacheDir.path}/$expectedFileName');
        if (await expectedFile.exists()) {
          _logger.i(
              'Found cached advertisement file in FileManager cache: $expectedFileName');
          return true;
        }

        // 兼容性检查：检查是否有任何以 MD5 开头的文件
        await for (FileSystemEntity entity in fileManagerCacheDir.list()) {
          if (entity is File) {
            final String basename =
                entity.path.split('/').last.split('\\').last;
            if (basename.startsWith(md5)) {
              _logger.i(
                  'Found cached advertisement file with MD5 prefix: $basename');
              return true;
            }
          }
        }
      }

      return false;
    } catch (e) {
      _logger.e('Error checking if advertisement file is cached: $md5',
          error: e);
      return false;
    }
  }

  /// 使用 FileManager 预下载文件
  Future<void> _predownloadFile(AdModel ad) async {
    try {
      _logger.i(
          'Pre-downloading advertisement file using FileManager: ${ad.title}');

      // 使用 FileManager 下载文件
      final File? downloadedFile = await _fileManager.getFile(ad.file);

      if (downloadedFile != null) {
        _logger.i(
            'Advertisement file downloaded successfully via FileManager: ${ad.title}');
      } else {
        _logger.w(
            'Failed to download advertisement file via FileManager: ${ad.title}');
      }
    } catch (e) {
      _logger.e('Error pre-downloading advertisement file: ${ad.title}',
          error: e);
      // 不重新抛出异常，让调用方继续处理其他文件
    }
  }

  /// 删除缓存文件（清理不再需要的文件）
  Future<void> _deleteCachedFile(String md5) async {
    try {
      // 检查 FileManager 的缓存目录
      final Directory appDir = await getApplicationDocumentsDirectory();
      final Directory fileManagerCacheDir =
          Directory('${appDir.path}/file_cache');

      if (await fileManagerCacheDir.exists()) {
        await for (FileSystemEntity entity in fileManagerCacheDir.list()) {
          if (entity is File) {
            final String basename =
                entity.path.split('/').last.split('\\').last;
            if (basename.startsWith(md5)) {
              await entity.delete();
              _logger.i('Deleted cached advertisement file: $basename');
              break; // 找到并删除第一个匹配的文件即可
            }
          }
        }
      }
    } catch (e) {
      _logger.e('Error deleting cached advertisement file: $md5', error: e);
    }
  }

  ///5，智能对比更新广告列表
  Future<void> _smartUpdateAdvertisements(
      List<AdModel> newAdvertisements) async {
    try {
      // 检查数据是否真的发生了变化
      if (!_hasDataChanged(newAdvertisements)) {
        _logger.i('广告数据没有变化，跳过更新操作');
        return;
      }

      _logger.i('检测到广告数据变化，开始更新...');

      // 将现有广告转换为 Map，以 ID 为键方便查找
      final Map<int, AdModel> currentAdsMap = {
        for (AdModel ad in _advertisements) ad.id: ad
      };

      // 将新广告转换为 Map
      final Map<int, AdModel> newAdsMap = {
        for (AdModel ad in newAdvertisements) ad.id: ad
      };

      // 找出新增的广告
      final List<AdModel> addedAds = [];
      for (AdModel newAd in newAdvertisements) {
        if (!currentAdsMap.containsKey(newAd.id)) {
          addedAds.add(newAd);
        }
      }

      // 找出删除的广告
      final List<AdModel> removedAds = [];
      for (AdModel currentAd in _advertisements) {
        if (!newAdsMap.containsKey(currentAd.id)) {
          removedAds.add(currentAd);
        }
      }

      _logger.i(
          'Advertisement update analysis: ${addedAds.length} added, ${removedAds.length} removed');

      // 处理新增的广告 - 检查并下载文件（异步处理，不阻塞主流程）
      for (AdModel addedAd in addedAds) {
        try {
          final bool isCached =
              await _isFileCached(addedAd.file.md5, addedAd.file.url);
          if (!isCached) {
            _logger.i('Downloading new advertisement file: ${addedAd.title}');
            // 异步下载，不等待完成
            _predownloadFile(addedAd).catchError((error) {
              _logger.e(
                  'Failed to download advertisement file: ${addedAd.title}',
                  error: error);
            });
          } else {
            _logger.i('Advertisement file already cached: ${addedAd.title}');
          }
        } catch (e) {
          _logger.e('Error checking cache for advertisement: ${addedAd.title}',
              error: e);
          // 继续处理其他文件，不中断整个流程
        }
      }

      // 处理删除的广告 - 删除缓存文件（异步处理）
      for (AdModel removedAd in removedAds) {
        try {
          _logger.i(
              'Removing cached file for deleted advertisement: ${removedAd.title}');
          // 异步删除，不等待完成
          _deleteCachedFile(removedAd.file.md5).catchError((error) {
            _logger.e('Failed to delete cached file for: ${removedAd.title}',
                error: error);
          });
        } catch (e) {
          _logger.e(
              'Error deleting cache for advertisement: ${removedAd.title}',
              error: e);
          // 继续处理其他文件，不中断整个流程
        }
      }

      // 更新广告列表（主要操作，确保成功）
      _advertisements = List<AdModel>.from(newAdvertisements); // 创建副本，避免引用问题

      // 保存更新后的数据到缓存
      await _saveAdvertisementsToCache(_advertisements);

      _logger.i('Smart advertisement update completed successfully.');

      // 通知listeners，这会触发mainscreen_page.dart中的监听器更新轮播
    } catch (e, stackTrace) {
      _logger.e('Error in smart advertisement update',
          error: e, stackTrace: stackTrace);
      // 如果智能更新失败，至少确保基本更新完成
      try {
        _advertisements = List<AdModel>.from(newAdvertisements);
        await _saveAdvertisementsToCache(_advertisements);
        _logger.w('Fallback to basic advertisement update completed.');
      } catch (fallbackError) {
        _logger.e('Even fallback advertisement update failed',
            error: fallbackError);
        // 保持现有数据不变
      }
    }
  }

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
      // Using getAdvertisementsBuilding as per httpapi.json for general advertisements
      final responseData = await _apiClient.getAdvertisementsBuilding();

      if (responseData.containsKey('data') && responseData['data'] is List) {
        final List<dynamic> advertisementListJson = responseData['data'];
        final List<AdModel> newAdvertisements = advertisementListJson
            .map((jsonItem) =>
                AdModel.fromJson(jsonItem as Map<String, dynamic>))
            .toList();

        _logger.i(
            'Successfully fetched ${newAdvertisements.length} advertisements from API.');

        // 使用智能对比更新广告列表
        await _smartUpdateAdvertisements(newAdvertisements);

        _logger.i(
            'Advertisement update completed. Total: ${_advertisements.length}, Top ads: ${topAdvertisements.length}, Full ads: ${fullAdvertisements.length}');
        _error = null; // 成功时清除错误
      } else {
        _logger.w(
            'Fetched advertisements data is not in the expected format: $responseData');
        // 不清除现有数据，保持现状
        _error = "Failed to parse advertisements data.";
      }
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
        errorMessage = '网络连接失败，使用缓存的广告数据继续轮播';
        isNetworkError = true;
        _logger.w('网络连接问题检测到，保持现有数据: $e');
      } else if (e.toString().contains('TimeoutException') ||
          e.toString().contains('请求超时')) {
        errorMessage = '请求超时，使用缓存的广告数据继续轮播';
        isNetworkError = true;
        _logger.w('请求超时检测到，保持现有数据: $e');
      } else if (e.toString().contains('FormatException')) {
        errorMessage = '服务器返回数据格式错误，保持现有广告数据';
        _logger.w('数据格式错误检测到，保持现有数据: $e');
      } else {
        errorMessage = '发生未知错误，保持现有广告数据: $e';
        _logger.w('未知错误检测到，保持现有数据: $e');
      }

      _error = errorMessage;

      // 网络错误时检查并确保有可用的广告数据
      if (isNetworkError) {
        await _ensureCachedAdvertisementsAvailable();
      }

      // 发生任何错误时都不清除现有数据，保持现状让轮播继续
      _logger.i(
          '错误处理完成，保持现有广告数据: ${_advertisements.length}个广告，${topAdvertisements.length}个顶部广告，${fullAdvertisements.length}个全屏广告');
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

  // Potentially add methods to add/update/delete advertisements if the API supports it
  // and if such functionality is required by the app.
  // For now, focusing on fetching and displaying.
}
