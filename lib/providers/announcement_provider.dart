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

  static const String _announcementsDataKey =
      'announcements_data'; // 原始通告数据缓存key

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

    // 创建ID到通告的映射以便快速比较
    final currentAnnouncementsMap = {
      for (AnnouncementModel announcement in _announcements)
        announcement.id: announcement
    };
    final newAnnouncementsMap = {
      for (AnnouncementModel announcement in newAnnouncements)
        announcement.id: announcement
    };

    // 检查是否有新增或删除的通告
    if (currentAnnouncementsMap.keys
            .toSet()
            .difference(newAnnouncementsMap.keys.toSet())
            .isNotEmpty ||
        newAnnouncementsMap.keys
            .toSet()
            .difference(currentAnnouncementsMap.keys.toSet())
            .isNotEmpty) {
      return true;
    }

    // 检查现有通告是否有内容变化
    for (final id in currentAnnouncementsMap.keys) {
      final currentAnnouncement = currentAnnouncementsMap[id]!;
      final newAnnouncement = newAnnouncementsMap[id]!;

      // 比较关键字段
      if (currentAnnouncement.title != newAnnouncement.title ||
          currentAnnouncement.description != newAnnouncement.description ||
          currentAnnouncement.file.url != newAnnouncement.file.url ||
          currentAnnouncement.file.md5 != newAnnouncement.file.md5) {
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
      // _logger.i('Periodic announcement update is already active.');
      return;
    }

    // 获取更新间隔时间（从设置中获取，单位：分钟）
    final updateIntervalMinutes =
        _appDataProvider.deviceSettings?.noticeUpdateDuration ?? 5; // 默认5分钟
    final updateIntervalSeconds = updateIntervalMinutes * 60; // 转换为秒
    // _logger.i(
    // 'Starting periodic announcement update with interval: ${updateIntervalMinutes} minutes (${updateIntervalSeconds}s)');

    _isPeriodicUpdateActive = true;

    // 立即执行一次更新
    fetchNotices();

    // 设置定时器进行周期性更新
    _updateTimer =
        Timer.periodic(Duration(seconds: updateIntervalSeconds), (timer) {
      if (_isPeriodicUpdateActive) {
        // _logger.i('Performing periodic announcement update...');
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
    // _logger.i('Periodic announcement update stopped.');
  }

  /// 重新初始化Provider（当依赖变化时调用）
  void reinitialize() {
    // _logger.i('AnnouncementProvider reinitializing...');

    // 停止现有的定时更新
    stopPeriodicUpdate();

    // 重新加载缓存数据
    _loadAnnouncementsFromCache();

    // 如果AppDataProvider已登录，重新启动定时更新
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_appDataProvider.isLoggedIn) {
        // _logger.i('重新初始化完成，重启通告定时更新');
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

  ///5，智能对比更新通告列表
  Future<void> _smartUpdateAnnouncements(
      List<AnnouncementModel> newAnnouncements) async {
    try {
      // 检查数据是否真的发生了变化
      if (!_hasDataChanged(newAnnouncements)) {
        // _logger.i('通告数据没有变化，跳过更新操作');
        return;
      }

      // _logger.i('检测到通告数据变化，开始更新...');

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

      // _logger.i(
      // 'Announcement update analysis: ${addedAnnouncements.length} added, ${removedAnnouncements.length} removed');

      // 处理新增的通告 - 检查并下载文件（异步处理，不阻塞主流程）
      for (AnnouncementModel addedAnnouncement in addedAnnouncements) {
        try {
          final bool isCached = await _isFileCached(
              addedAnnouncement.file.md5, addedAnnouncement.file.url);
          if (!isCached) {
            // _logger.i(
            // 'Downloading new announcement file: ${addedAnnouncement.title}');
            // 异步下载，不等待完成
            _predownloadFile(addedAnnouncement).catchError((error) {
              _logger.e(
                  'Failed to download announcement file: ${addedAnnouncement.title}',
                  error: error);
            });
          } else {
            // _logger.i(
            // 'Announcement file already cached: ${addedAnnouncement.title}');
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
          // _logger.i(
          // 'Removing cached file for deleted announcement: ${removedAnnouncement.title}');
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

      // 保存更新后的数据到缓存
      await _saveAnnouncementsToCache(_announcements);

      // _logger.i('Smart announcement update completed successfully.');
    } catch (e, stackTrace) {
      _logger.e('Error in smart announcement update',
          error: e, stackTrace: stackTrace);
      // 如果智能更新失败，至少确保基本更新完成
      try {
        _announcements = List<AnnouncementModel>.from(newAnnouncements);
        _updateCarouselAnnouncements();
        await _saveAnnouncementsToCache(_announcements);
        // _logger.w('Fallback to basic announcement update completed.');
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
      // _logger.w('fetchNotices already in progress, skipping duplicate call.');
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // _logger.i('Fetching notices from building...');
      // Using getNoticesBuilding as per httpapi.json for general notices
      final responseData = await _apiClient.getNoticesBuilding();

      if (responseData.containsKey('data') && responseData['data'] is List) {
        final List<dynamic> noticeListJson = responseData['data'];
        final List<AnnouncementModel> newAnnouncements = noticeListJson
            .map((jsonItem) =>
                AnnouncementModel.fromJson(jsonItem as Map<String, dynamic>))
            .toList();

        // _logger.i(
        // 'Successfully fetched ${newAnnouncements.length} announcements from API.');

        // 使用智能对比更新通告列表
        await _smartUpdateAnnouncements(newAnnouncements);

        // _logger.i(
        // 'Announcement update completed. Total: ${_announcements.length}, Carousel announcements: ${_carouselAnnouncements.length}');
        _error = null; // 成功时清除错误

        // 如果之前有网络错误，记录恢复信息
        if (_error != null &&
            (_error!.contains('网络') || _error!.contains('超时'))) {
          // _logger.i('网络已恢复，通告数据更新成功');
        }
      } else {
        // _logger.w(
        // 'Fetched notices data is not in the expected format: $responseData');
        // 不清除现有数据，保持现状
        _error = "Failed to parse notices data.";
      }
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
      bool isNetworkError = false;

      if (e.toString().contains('SocketException') ||
          e.toString().contains('Connection timed out') ||
          e.toString().contains('ClientException')) {
        errorMessage = '网络连接失败，使用缓存的通告数据继续轮播';
        isNetworkError = true;
        // _logger.w('网络连接问题检测到，保持现有数据: $e');
      } else if (e.toString().contains('TimeoutException') ||
          e.toString().contains('请求超时')) {
        errorMessage = '请求超时，使用缓存的通告数据继续轮播';
        isNetworkError = true;
        // _logger.w('请求超时检测到，保持现有数据: $e');
      } else if (e.toString().contains('FormatException')) {
        errorMessage = '服务器返回数据格式错误，保持现有通告数据';
        // _logger.w('数据格式错误检测到，保持现有数据: $e');
      } else {
        errorMessage = '发生未知错误，保持现有通告数据: $e';
        // _logger.w('未知错误检测到，保持现有数据: $e');
      }

      _error = errorMessage;

      // 网络错误时检查并确保有可用的通告数据
      if (isNetworkError) {
        await _ensureCachedAnnouncementsAvailable();
      }

      // 发生任何错误时都不清除现有数据，保持现状让轮播继续
      // _logger.i(
      // '错误处理完成，保持现有通告数据: ${_announcements.length}个通告，${_carouselAnnouncements.length}个轮播通告');
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
    // _logger.i(
    // 'Updated carousel announcements: ${_carouselAnnouncements.length} announcements (emergency + general only)');
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

  /// 确保在网络错误时有可用的缓存通告数据
  Future<void> _ensureCachedAnnouncementsAvailable() async {
    try {
      // 如果当前没有通告数据，尝试从缓存中加载
      if (_announcements.isEmpty) {
        // _logger.i('当前通告列表为空，尝试从缓存中恢复通告数据...');

        // 这里可以实现从本地缓存（SharedPreferences或数据库）加载通告数据的逻辑
        // 目前先记录日志，未来可以扩展实际的缓存恢复逻辑
        // _logger.w('TODO: 实现从本地缓存恢复通告数据的功能');

        // 暂时创建一个默认的通告以确保轮播能够继续工作
        // 在实际应用中，这应该从缓存中加载真实的通告数据
        /*
        final defaultAnnouncement = AnnouncementModel(
          id: -1,
          title: '网络连接中断 - 使用缓存数据',
          content: '正在尝试重新连接网络，请稍候...',
          uiType: AnnouncementTypeUi.general,
          file: FileModel(url: '', md5: ''),
          fromDate: DateTime.now().subtract(Duration(days: 1)),
          toDate: DateTime.now().add(Duration(days: 1)),
        );
        _announcements = [defaultAnnouncement];
        _updateCarouselAnnouncements();
        // _logger.i('已创建默认通告以确保轮播继续工作');
        */
      } else {
        // _logger.i('当前有 ${_announcements.length} 个通告数据可用，继续使用现有数据');
      }

      // 确保轮播通告数组也有数据
      if (_carouselAnnouncements.isEmpty && _announcements.isNotEmpty) {
        _updateCarouselAnnouncements();
        // _logger.i('重新更新轮播通告数组: ${_carouselAnnouncements.length} 个轮播通告');
      }
    } catch (e) {
      _logger.e('检查缓存通告数据时发生错误', error: e);
    }
  }

  // Potentially add methods to add/update/delete announcements if the API supports it
  // and if such functionality is required by the app.
  // For now, focusing on fetching and displaying.
}
