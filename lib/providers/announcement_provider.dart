import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:iboard_app/http/api_client.dart';
import 'package:iboard_app/models/announcement_model.dart';
import 'package:iboard_app/providers/app_data_provider.dart'; // Assuming AppDataProvider is here
import 'package:iboard_app/managers/file_manager.dart'; // 引入 FileManager
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';

class AnnouncementProvider extends ChangeNotifier {
  final Logger _logger = Logger();
  final ApiClient _apiClient;
  final AppDataProvider
      _appDataProvider; // To access token and deviceId if needed
  final FileManager _fileManager; // 添加 FileManager 实例

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

  AnnouncementProvider(
      this._apiClient, this._appDataProvider, this._fileManager) {
    _logger.i('AnnouncementProvider initialized.');
    // Optionally fetch announcements immediately or provide a method to do so.
    // fetchNotices(); // Example: Fetch on init if desired
  }

  @override
  void dispose() {
    stopPeriodicUpdate();
    super.dispose();
  }

  /// 开始定期更新通告数据
  void startPeriodicUpdate() {
    if (_isPeriodicUpdateActive) {
      _logger.i('Periodic announcement update is already active.');
      return;
    }

    // 获取更新间隔时间（从设置中获取，单位：分钟）
    final updateIntervalMinutes =
        _appDataProvider.deviceSettings?.noticeUpdateDuration ?? 5; // 默认5分钟
    final updateIntervalSeconds = updateIntervalMinutes * 60; // 转换为秒
    _logger.i(
        'Starting periodic announcement update with interval: ${updateIntervalMinutes} minutes (${updateIntervalSeconds}s)');

    _isPeriodicUpdateActive = true;

    // 立即执行一次更新
    fetchNotices();

    // 设置定时器进行周期性更新
    _updateTimer =
        Timer.periodic(Duration(seconds: updateIntervalSeconds), (timer) {
      if (_isPeriodicUpdateActive) {
        _logger.i('Performing periodic announcement update...');
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
    _logger.i('Periodic announcement update stopped.');
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
              'Found cached announcement file in FileManager cache: $expectedFileName');
          return true;
        }

        // 兼容性检查：检查是否有任何以 MD5 开头的文件
        await for (FileSystemEntity entity in fileManagerCacheDir.list()) {
          if (entity is File) {
            final String basename =
                entity.path.split('/').last.split('\\').last;
            if (basename.startsWith(md5)) {
              _logger.i(
                  'Found cached announcement file with MD5 prefix: $basename');
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
      _logger.i(
          'Pre-downloading announcement file using FileManager: ${announcement.title}');

      // 使用 FileManager 下载文件
      final File? downloadedFile =
          await _fileManager.getFile(announcement.file);

      if (downloadedFile != null) {
        _logger.i(
            'Announcement file downloaded successfully via FileManager: ${announcement.title}');
      } else {
        _logger.w(
            'Failed to download announcement file via FileManager: ${announcement.title}');
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
              _logger.i('Deleted cached announcement file: $basename');
              break; // 找到并删除第一个匹配的文件即可
            }
          }
        }
      }
    } catch (e) {
      _logger.e('Error deleting cached announcement file: $md5', error: e);
    }
  }

  /// 智能对比更新通告列表
  Future<void> _smartUpdateAnnouncements(
      List<AnnouncementModel> newAnnouncements) async {
    try {
      // 将现有通告转换为 Map，以 ID 为键方便查找
      final Map<int, AnnouncementModel> currentAnnouncementsMap = {
        for (AnnouncementModel announcement in _announcements)
          announcement.id: announcement
      };

      // 将新通告转换为 Map
      final Map<int, AnnouncementModel> newAnnouncementsMap = {
        for (AnnouncementModel announcement in newAnnouncements)
          announcement.id: announcement
      };

      // 找出新增的通告
      final List<AnnouncementModel> addedAnnouncements = [];
      for (AnnouncementModel newAnnouncement in newAnnouncements) {
        if (!currentAnnouncementsMap.containsKey(newAnnouncement.id)) {
          addedAnnouncements.add(newAnnouncement);
        }
      }

      // 找出删除的通告
      final List<AnnouncementModel> removedAnnouncements = [];
      for (AnnouncementModel currentAnnouncement in _announcements) {
        if (!newAnnouncementsMap.containsKey(currentAnnouncement.id)) {
          removedAnnouncements.add(currentAnnouncement);
        }
      }

      _logger.i(
          'Announcement update analysis: ${addedAnnouncements.length} added, ${removedAnnouncements.length} removed');

      // 处理新增的通告 - 检查并下载文件（异步处理，不阻塞主流程）
      for (AnnouncementModel addedAnnouncement in addedAnnouncements) {
        try {
          final bool isCached = await _isFileCached(
              addedAnnouncement.file.md5, addedAnnouncement.file.url);
          if (!isCached) {
            _logger.i(
                'Downloading new announcement file: ${addedAnnouncement.title}');
            // 异步下载，不等待完成
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
          // 继续处理其他文件，不中断整个流程
        }
      }

      // 处理删除的通告 - 删除缓存文件（异步处理）
      for (AnnouncementModel removedAnnouncement in removedAnnouncements) {
        try {
          _logger.i(
              'Removing cached file for deleted announcement: ${removedAnnouncement.title}');
          // 异步删除，不等待完成
          _deleteCachedFile(removedAnnouncement.file.md5).catchError((error) {
            _logger.e(
                'Failed to delete cached file for: ${removedAnnouncement.title}',
                error: error);
          });
        } catch (e) {
          _logger.e(
              'Error deleting cache for announcement: ${removedAnnouncement.title}',
              error: e);
          // 继续处理其他文件，不中断整个流程
        }
      }

      // 更新通告列表（主要操作，确保成功）
      _announcements =
          List<AnnouncementModel>.from(newAnnouncements); // 创建副本，避免引用问题

      // 更新轮播通告数组
      _updateCarouselAnnouncements();

      _logger.i('Smart announcement update completed successfully.');
    } catch (e, stackTrace) {
      _logger.e('Error in smart announcement update',
          error: e, stackTrace: stackTrace);
      // 如果智能更新失败，至少确保基本更新完成
      try {
        _announcements = List<AnnouncementModel>.from(newAnnouncements);
        _updateCarouselAnnouncements();
        _logger.w('Fallback to basic announcement update completed.');
      } catch (fallbackError) {
        _logger.e('Even fallback announcement update failed',
            error: fallbackError);
        // 保持现有数据不变
      }
    }
  }

  // Interface to fetch/update announcements
  Future<void> fetchNotices() async {
    if (_appDataProvider.token == null) {
      _error = "Authentication token is missing. Cannot fetch notices.";
      _logger.w(_error);
      notifyListeners();
      return;
    }

    // 防止重复调用 - 如果正在加载中，直接返回
    if (_isLoading) {
      _logger.w('fetchNotices already in progress, skipping duplicate call.');
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _logger.i('Fetching notices from building...');
      // Using getNoticesBuilding as per httpapi.json for general notices
      final responseData = await _apiClient.getNoticesBuilding();

      if (responseData.containsKey('data') && responseData['data'] is List) {
        final List<dynamic> noticeListJson = responseData['data'];
        final List<AnnouncementModel> newAnnouncements = noticeListJson
            .map((jsonItem) =>
                AnnouncementModel.fromJson(jsonItem as Map<String, dynamic>))
            .toList();

        _logger.i(
            'Successfully fetched ${newAnnouncements.length} announcements from API.');

        // 使用智能对比更新通告列表
        await _smartUpdateAnnouncements(newAnnouncements);

        _logger.i(
            'Announcement update completed. Total: ${_announcements.length}, Carousel announcements: ${_carouselAnnouncements.length}');
        _error = null; // 成功时清除错误
      } else {
        _logger.w(
            'Fetched notices data is not in the expected format: $responseData');
        // 不清除现有数据，保持现状
        _error = "Failed to parse notices data.";
      }
    } on ApiException catch (e) {
      _logger.e('Failed to fetch notices (ApiException)',
          error: e, stackTrace: e.errorData is StackTrace ? e.errorData : null);

      // 检查是否是 token 过期错误
      if (e.statusCode == 401 ||
          e.message.toLowerCase().contains('token is expired')) {
        _logger.w('Token expired detected, attempting to refresh token...');
        try {
          // 尝试重新登录获取新 token
          await _appDataProvider.initializeAndLogin();
          if (_appDataProvider.isLoggedIn) {
            _logger.i('Token refresh successful, retrying notices fetch...');
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
      _error = 'An unexpected error occurred: $e';
      // 发生意外错误时不清除现有数据，保持现状
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // 更新轮播通告数组 - 只包含緊急和一般通告
  void _updateCarouselAnnouncements() {
    _carouselAnnouncements = _announcements
        .where((announcement) =>
            announcement.uiType == AnnouncementTypeUi.emergency ||
            announcement.uiType == AnnouncementTypeUi.general)
        .toList();
    _logger.i(
        'Updated carousel announcements: ${_carouselAnnouncements.length} announcements (emergency + general only)');
  }

  // 获取轮播专用通告 - 返回緊急和一般通告
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

  // Potentially add methods to add/update/delete announcements if the API supports it
  // and if such functionality is required by the app.
  // For now, focusing on fetching and displaying.
}
