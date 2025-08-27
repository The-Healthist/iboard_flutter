import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:iboard_app/http/api_client.dart';
import 'package:iboard_app/models/announcement_model.dart';
import 'package:iboard_app/providers/app_data_provider.dart'; // Assuming AppDataProvider is here
import 'package:iboard_app/managers/file_manager.dart'; // 引入 FileManager
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:iboard_app/providers/announcement_carousel_provider.dart';

class AnnouncementProvider extends ChangeNotifier {
  final Logger _logger = Logger();
  // 原始通告数据缓存key
  static const String _announcementsDataKey = 'announcements_data';

  final ApiClient _apiClient;
  final AppDataProvider
      _appDataProvider; // To access token and deviceId if needed
  final FileManager _fileManager;

  // 轮播Provider引用
  AnnouncementCarouselProvider? _announcementCarouselProvider;

  List<AnnouncementModel> _announcements = [];
  List<AnnouncementModel> _carouselAnnouncements = [];
  bool _isLoading = false;
  String? _error;
  Timer? _updateTimer; // 定时更新定时器
  bool _isPeriodicUpdateActive = false; // 是否正在进行定期更新

  // Getters
  List<AnnouncementModel> get announcements => _announcements;
  List<AnnouncementModel> get carouselAnnouncements => _carouselAnnouncements;
  bool get isLoading => _isLoading;
  String? get error => _error;
  ApiClient get apiClient => _apiClient; // 添加apiClient getter用于比较
  bool get isPeriodicUpdateActive => _isPeriodicUpdateActive;

  AnnouncementProvider(
      this._apiClient, this._appDataProvider, this._fileManager) {
    _loadAnnouncementsFromCache(); // 启动时从缓存加载数据

    // 延迟检查AppDataProvider登录状态，确保初始化完成
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_appDataProvider.isLoggedIn) {
        startPeriodicUpdate();
      }
    });
  }

  ///1，保存通告数据到SharedPreferences缓存
  Future<void> _saveAnnouncementsToCache(
      List<AnnouncementModel> announcements) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<Map<String, dynamic>> announcementsJson =
          announcements.map((announcement) => announcement.toJson()).toList();
      final jsonString = json.encode(announcementsJson);
      await prefs.setString(_announcementsDataKey, jsonString);
    } catch (e) {
      _logger.e('保存通告数据到缓存失败', error: e);
    }
  }

  ///2，從SharedPreferences緩存加載通告數據
  Future<void> _loadAnnouncementsFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_announcementsDataKey);
      if (jsonString != null && jsonString.isNotEmpty) {
        final List<dynamic> announcementsJson =
            json.decode(jsonString) as List<dynamic>;
        final List<AnnouncementModel> cachedAnnouncements = announcementsJson
            .map((announcementJson) => AnnouncementModel.fromJson(
                announcementJson as Map<String, dynamic>))
            .toList();

        _announcements = cachedAnnouncements;
        _updateCarouselAnnouncements(); // 更新轮播通告数组

        // 如果已經設置了輪播Provider引用，立即更新
        if (_announcementCarouselProvider != null) {
          _announcementCarouselProvider!
              .updateCarouselList(_carouselAnnouncements);
          _logger.i(
              '📢 緩存加載完成，已更新輪播Provider: ${_carouselAnnouncements.length} 個通告');
        }

        notifyListeners();
      } else {
        // 缓存中没有数据，也要更新轮播提供者（使用空列表）
        _announcements = [];
        _updateCarouselAnnouncements();

        if (_announcementCarouselProvider != null) {
          _announcementCarouselProvider!
              .updateCarouselList(_carouselAnnouncements);
          _logger.i('📢 緩存中無數據，已更新輪播Provider（空列表）');
        }

        notifyListeners();
      }
    } catch (e) {
      _logger.e('从缓存加载通告数据失败', error: e);

      // 即使加载失败，也要确保轮播提供者被通知
      _announcements = [];
      _updateCarouselAnnouncements();

      if (_announcementCarouselProvider != null) {
        _announcementCarouselProvider!
            .updateCarouselList(_carouselAnnouncements);
        _logger.i('📢 緩存加載失敗，已更新輪播Provider（空列表）');
      }

      notifyListeners();
    }
  }

  ///4，检查数据是否真的发生了变化
  bool _hasDataChanged(List<AnnouncementModel> newAnnouncements) {
    if (_announcements.length != newAnnouncements.length) {
      return true;
    }

    /// 判断通告list是否变化(只需要比对id即可比对顺序和数据是否对的上)
    for (int i = 0; i < _announcements.length; i++) {
      final old = _announcements[i];
      final newer = newAnnouncements[i];
      if (old.id != newer.id) {
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

  /// 开始定期更新通告数据
  void startPeriodicUpdate() {
    if (_isPeriodicUpdateActive) {
      _logger.i('开始定期更新通告数据');
      return;
    }

    // 获取更新间隔时间（从设置中获取，單位：分鈡）
    final updateIntervalMinutes =
        _appDataProvider.deviceSettings?.noticeUpdateDuration ?? 5;
    final updateIntervalSeconds = updateIntervalMinutes * 60;
    _isPeriodicUpdateActive = true;

    fetchNotices();

    // 设置定时器进行周期性更新
    _updateTimer =
        Timer.periodic(Duration(seconds: updateIntervalSeconds), (timer) {
      if (_isPeriodicUpdateActive) {
        fetchNotices();
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
    stopPeriodicUpdate();
    _loadAnnouncementsFromCache();

    // 如果AppDataProvider已登录，重新启动定时更新
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_appDataProvider.isLoggedIn) {
        startPeriodicUpdate();
      }
    });
  }

  ///8，检查文件是否已缓存（使用 FileManager 检查）
  Future<bool> _isFileCached(String md5, String url) async {
    try {
      final String fileNameFromUrl = Uri.parse(url).pathSegments.last;
      final String expectedFileName = '${md5}_$fileNameFromUrl';
      final Directory appDir = await getApplicationDocumentsDirectory();
      final Directory fileManagerCacheDir =
          Directory('${appDir.path}/file_cache');

      if (await fileManagerCacheDir.exists()) {
        final File expectedFile =
            File('${fileManagerCacheDir.path}/$expectedFileName');
        if (await expectedFile.exists()) {
          return true;
        }

        await for (FileSystemEntity entity in fileManagerCacheDir.list()) {
          if (entity is File) {
            final String basename =
                entity.path.split('/').last.split('\\').last;
            if (basename.startsWith(md5)) {
              return true;
            }
          }
        }
      }

      return false;
    } catch (e) {
      _logger.e('Error checking if announcement file is cached: $md5',
          error: e);
      return false;
    }
  }

  ///7，使用 FileManager 预下载文件
  Future<void> _predownloadFile(AnnouncementModel announcement) async {
    try {
      await _fileManager.getFile(announcement.file);
      _logger.i('成功預下載通告文件: ${announcement.title}');
    } catch (e) {
      _logger.e(
          'Error pre-downloading announcement file: ${announcement.title}',
          error: e);
    }
  }

  ///9，删除缓存文件（清理不再需要的文件）
  Future<void> _deleteCachedFile(String md5) async {
    try {
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
              _logger.i('成功刪除緩存通告文件: $md5');
              break;
            }
          }
        }
      }
    } catch (e) {
      _logger.e('Error deleting cached announcement file: $md5', error: e);
    }
  }

  ///5，更新缓存并处理文件下载或者删除
  Future<void> _smartUpdateAnnouncements(
      List<AnnouncementModel> newAnnouncements) async {
    try {
      // 检查数据是否真的发生了变化
      if (!_hasDataChanged(newAnnouncements)) {
        _logger.i('通告数据没有变化，跳过更新操作');
        return;
      }

      _logger.i('检测到通告数据变化，开始更新...');

      final Map<int, AnnouncementModel> currentAnnouncementsMap = {
        for (AnnouncementModel announcement in _announcements)
          announcement.id: announcement
      };

      final Map<int, AnnouncementModel> newAnnouncementsMap = {
        for (AnnouncementModel announcement in newAnnouncements)
          announcement.id: announcement
      };

      final List<AnnouncementModel> addedAnnouncements = [];
      for (AnnouncementModel newAnnouncement in newAnnouncements) {
        if (!currentAnnouncementsMap.containsKey(newAnnouncement.id)) {
          addedAnnouncements.add(newAnnouncement);
        }
      }

      final List<AnnouncementModel> removedAnnouncements = [];
      for (AnnouncementModel currentAnnouncement in _announcements) {
        if (!newAnnouncementsMap.containsKey(currentAnnouncement.id)) {
          removedAnnouncements.add(currentAnnouncement);
        }
      }

      // 处理新增的通告
      for (AnnouncementModel addedAnnouncement in addedAnnouncements) {
        try {
          final bool isCached = await _isFileCached(
              addedAnnouncement.file.md5, addedAnnouncement.file.url);
          if (!isCached) {
            _predownloadFile(addedAnnouncement).catchError((error) {
              _logger.e(
                  'Failed to download announcement file: ${addedAnnouncement.title}',
                  error: error);
            });
          } else {
            _logger.i(
                'Announcement file already cached: ${addedAnnouncement.title}');
          }
        } catch (e) {
          _logger.e(
              'Error checking cache for announcement: ${addedAnnouncement.title}',
              error: e);
        }
      }

      // 处理删除的通告
      for (AnnouncementModel removedAnnouncement in removedAnnouncements) {
        try {
          _deleteCachedFile(removedAnnouncement.file.md5).catchError((error) {
            _logger.e(
                'Failed to delete cached file for: ${removedAnnouncement.title}',
                error: error);
          });
        } catch (e) {
          _logger.e(
              'Error deleting cache for announcement: ${removedAnnouncement.title}',
              error: e);
        }
      }

      // 更新通告列表
      _announcements = List<AnnouncementModel>.from(newAnnouncements);

      // 更新轮播通告数组
      _updateCarouselAnnouncements();

      // 保存更新后的数据到缓存
      await _saveAnnouncementsToCache(_announcements);
    } catch (e, stackTrace) {
      _logger.e('Error in smart announcement update',
          error: e, stackTrace: stackTrace);
      try {
        _announcements = List<AnnouncementModel>.from(newAnnouncements);
        _updateCarouselAnnouncements();
        await _saveAnnouncementsToCache(_announcements);
      } catch (fallbackError) {
        _logger.e('Even fallback announcement update failed',
            error: fallbackError);
      }
    }
  }

  ///6，fetchNotices,获取轮播通告数据（支持強制初始化）
  Future<void> fetchNotices({bool forceInit = false}) async {
    if (_appDataProvider.token == null || _isLoading) {
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final List<Map<String, dynamic>> carouselNoticesData =
          await _apiClient.getCarouselNotices();
      final List<AnnouncementModel> fetchedAnnouncements = carouselNoticesData
          .map((jsonItem) => AnnouncementModel.fromJson(jsonItem))
          .toList();

      // 判断是否有数据变化(只比对id顺序和数量即可)；首啟強制更新
      final bool hasChanges =
          forceInit ? true : _hasDataChanged(fetchedAnnouncements);

      if (!hasChanges) {
        _logger.i('通告数据无变化，跳过更新与通知');
        _error = null;
        _isLoading = false;
        notifyListeners();
        return;
      }

      await _smartUpdateAnnouncements(fetchedAnnouncements);
      if (_announcementCarouselProvider != null) {
        _announcementCarouselProvider!
            .updateCarouselList(_carouselAnnouncements);
      }

      // 如果之前有网络错误，记录恢复信息
      if (_error != null &&
          (_error!.contains('网络') || _error!.contains('超时'))) {}
    } on ApiException catch (e) {
      _logger.e('Failed to fetch notices (ApiException)',
          error: e, stackTrace: e.errorData is StackTrace ? e.errorData : null);

      // 检查是否是 token 过期错误
      if (e.statusCode == 401 ||
          e.message.toLowerCase().contains('token is expired')) {
        // _logger.w('Token expired detected, attempting to refresh token...');
        try {
          // 尝试重新登录获取新 token
          await _appDataProvider.initializeAndLogin();
          if (_appDataProvider.isLoggedIn) {
            _isLoading = false;
            await fetchNotices(forceInit: forceInit);
            return;
          } else {
            _error = 'Token refresh failed: Unable to re-authenticate';
          }
        } catch (refreshError) {
          _logger.e('Token refresh failed', error: refreshError);
          _error = 'Token expired and refresh failed: $refreshError';
        }
      } else {
        _error = 'Failed to fetch notices: ${e.message}';
      }
      // 网络错误或其他错误时不清除现有数据，保持现状
    } catch (e, stackTrace) {
      _logger.e('An unexpected error occurred while fetching notices',
          error: e, stackTrace: stackTrace);

      // 详细的网络错误处理
      String errorMessage;

      if (e.toString().contains('SocketException') ||
          e.toString().contains('Connection timed out') ||
          e.toString().contains('ClientException')) {
        errorMessage = '網絡連線失敗，使用快取的通告資料繼續輪播';
      } else if (e.toString().contains('TimeoutException') ||
          e.toString().contains('請求超時')) {
        errorMessage = '請求超時，使用快取的通告資料繼續輪播';
      } else if (e.toString().contains('FormatException')) {
        errorMessage = '伺服器返回資料格式錯誤，保持現有通告資料';
      } else {
        errorMessage = '發生未知錯誤，保持現有通告資料: $e';
      }

      _error = errorMessage;
    } finally {
      _isLoading = false;

      // 确保轮播提供者被通知（即使有错误）
      if (_announcementCarouselProvider != null) {
        _announcementCarouselProvider!
            .updateCarouselList(_carouselAnnouncements);
        _logger
            .i('📢 通告获取完成，已通知輪播Provider: ${_carouselAnnouncements.length} 個通告');
      }

      notifyListeners();
    }
  }

  // 7,更新轮播通告数组 - 只包含緊急和一般通告
  void _updateCarouselAnnouncements() {
    final filtered = _announcements
        .where((announcement) =>
            announcement.uiType == AnnouncementTypeUi.emergency ||
            announcement.uiType == AnnouncementTypeUi.general)
        .toList();

    // 若過濾後為空但原始非空，臨時使用全部通告參與輪播，避免通告區被清空
    if (filtered.isEmpty && _announcements.isNotEmpty) {
      _carouselAnnouncements = List<AnnouncementModel>.from(_announcements);
      _logger.i('📢 警示：過濾後輪播通告為空，臨時使用全部通告進入輪播');
    } else {
      _carouselAnnouncements = filtered;
    }
  }

  // 获取轮播专用通告
  List<AnnouncementModel> getCarouselAnnouncements() {
    return _carouselAnnouncements;
  }

  // Interface to get a specific announcement by ID (if needed)
  AnnouncementModel? getNoticeById(int id) {
    try {
      return _announcements.firstWhere((notice) => notice.id == id);
    } catch (e) {
      return null; // Not found
    }
  }

  /// 设置轮播Provider引用
  void setCarouselProvider(AnnouncementCarouselProvider carouselProvider) {
    _announcementCarouselProvider = carouselProvider;
    _logger.i('设置通告轮播Provider引用');
  }
}
