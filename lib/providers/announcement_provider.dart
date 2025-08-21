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
  final FileManager _fileManager; // 添加 FileManager 实例

  // 轮播Provider引用
  AnnouncementCarouselProvider? _announcementCarouselProvider;

  List<AnnouncementModel> _announcements = [];
  List<AnnouncementModel> _carouselAnnouncements = []; // 轮播专用通告数组
  bool _isLoading = false;
  String? _error;
  Timer? _updateTimer; // 定时更新定时器
  bool _isPeriodicUpdateActive = false; // 是否正在进行定期更新

  // Getters
  List<AnnouncementModel> get announcements => _announcements;
  List<AnnouncementModel> get carouselAnnouncements =>
      _carouselAnnouncements; // 轮播通告获取器
  bool get isLoading => _isLoading;
  String? get error => _error;
  ApiClient get apiClient => _apiClient; // 添加apiClient getter用于比较
  bool get isPeriodicUpdateActive => _isPeriodicUpdateActive;

  AnnouncementProvider(
      this._apiClient, this._appDataProvider, this._fileManager) {
    // _logger.i('AnnouncementProvider initialized.');
    _loadAnnouncementsFromCache(); // 启动时从缓存加载数据

    // 延迟检查AppDataProvider登录状态，确保初始化完成
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_appDataProvider.isLoggedIn) {
        // _logger.i('AppDataProvider已登录，自动启动通告定时更新');
        startPeriodicUpdate();
      } else {
        // _logger.w('AppDataProvider未登录，跳过自动启动通告定时更新');
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
      // _logger.i('💾 通告数据已保存到缓存: ${announcements.length}个通告');
    } catch (e) {
      _logger.e('保存通告数据到缓存失败', error: e);
    }
  }

  ///2，从SharedPreferences缓存加载通告数据
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
        // _logger.i('📂 从缓存加载通告数据成功: ${cachedAnnouncements.length}个通告');
        notifyListeners();
      } else {
        // _logger.w('缓存中没有找到通告数据');
      }
    } catch (e) {
      _logger.e('从缓存加载通告数据失败', error: e);
    }
  }

  ///3，清除通告数据缓存
  Future<void> _clearAnnouncementsCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_announcementsDataKey);
      // _logger.i('通告数据缓存已清除');
    } catch (e) {
      _logger.e('清除通告数据缓存失败', error: e);
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

    // 获取更新间隔时间（从设置中获取，单位：分钟）
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
          // _logger.i(
          // 'Found cached announcement file in FileManager cache: $expectedFileName');
          return true;
        }

        // 兼容性检查：检查是否有任何以 MD5 开头的文件
        await for (FileSystemEntity entity in fileManagerCacheDir.list()) {
          if (entity is File) {
            final String basename =
                entity.path.split('/').last.split('\\').last;
            if (basename.startsWith(md5)) {
              // _logger.i(
              // 'Found cached announcement file with MD5 prefix: $basename');
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

  /// 使用 FileManager 预下载文件
  Future<void> _predownloadFile(AnnouncementModel announcement) async {
    try {
      // _logger.i(
      // 'Pre-downloading announcement file using FileManager: ${announcement.title}');

      // 使用 FileManager 下载文件
      final File? downloadedFile =
          await _fileManager.getFile(announcement.file);

      if (downloadedFile != null) {
        // _logger.i(
        // 'Announcement file downloaded successfully via FileManager: ${announcement.title}');
      } else {
        // _logger.w(
        // 'Failed to download announcement file via FileManager: ${announcement.title}');
      }
    } catch (e) {
      _logger.e(
          'Error pre-downloading announcement file: ${announcement.title}',
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
              // _logger.i('Deleted cached announcement file: $basename');
              break; // 找到并删除第一个匹配的文件即可
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

  ///6，fetchNotices,获取轮播通告数据
  Future<void> fetchNotices() async {
    if (_appDataProvider.token == null) {
      _error = "Authentication token is missing. Cannot fetch notices.";
      _logger.w(_error);
      notifyListeners();
      return;
    }

    if (_isLoading) {
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

      // 判断是否有数据变化(只比对id顺序和数量即可)
      final bool hasChanges = _hasDataChanged(fetchedAnnouncements);

      if (!hasChanges) {
        _logger.i('通告数据无变化，跳过更新与通知');
        _error = null;
        return;
      }
      await _smartUpdateAnnouncements(fetchedAnnouncements);
      if (_announcementCarouselProvider != null) {
        _announcementCarouselProvider!
            .updateCarouselList(_carouselAnnouncements);
        _logger.i('通告数据变更，已通知轮播Provider更新列表');
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
            // _logger.i('Token refresh successful, retrying notices fetch...');
            // 设置标志位防止递归调用导致的问题
            _isLoading = false; // 重置状态
            // 递归调用自己重试 (只重试一次，避免无限循环)
            await fetchNotices();
            return; // 成功后直接返回，不执行后续的错误处理
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
        errorMessage = '网络连接失败，使用缓存的通告数据继续轮播';
      } else if (e.toString().contains('TimeoutException') ||
          e.toString().contains('请求超时')) {
        errorMessage = '请求超时，使用缓存的通告数据继续轮播';
      } else if (e.toString().contains('FormatException')) {
        errorMessage = '服务器返回数据格式错误，保持现有通告数据';
      } else {
        errorMessage = '发生未知错误，保持现有通告数据: $e';
      }

      _error = errorMessage;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // 7,更新轮播通告数组 - 只包含緊急和一般通告
  void _updateCarouselAnnouncements() {
    _carouselAnnouncements = _announcements
        .where((announcement) =>
            announcement.uiType == AnnouncementTypeUi.emergency ||
            announcement.uiType == AnnouncementTypeUi.general)
        .toList();
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
