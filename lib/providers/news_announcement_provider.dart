import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:iboard_app/http/api_client.dart';
import 'package:iboard_app/models/news_announcement_model.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 新闻公报提供者
/// 负责管理香港特区政府新闻公报的获取、存储和定时更新
class NewsAnnouncementProvider extends ChangeNotifier {
  final Logger _logger = Logger();
  final ApiClient _apiClient;

  // 新闻数据
  List<NewsAnnouncementModel> _newsList = [];

  // 状态管理
  bool _isLoading = false;
  bool _hasError = false;
  String _errorMessage = '';

  // 定时更新管理
  Timer? _updateTimer;
  DateTime? _lastUpdateTime;
  DateTime? _nextUpdateTime;
  static const Duration _updateInterval = Duration(hours: 2); // 2小时更新一次

  // 本地存储键
  static const String _storageKey = 'news_announcements';
  static const String _lastUpdateKey = 'news_last_update';

  // Getters
  List<NewsAnnouncementModel> get newsList => _newsList;
  bool get isLoading => _isLoading;
  bool get hasError => _hasError;
  String get errorMessage => _errorMessage;
  DateTime? get lastUpdateTime => _lastUpdateTime;
  DateTime? get nextUpdateTime => _nextUpdateTime;
  int get newsCount => _newsList.length;

  // 获取当前新闻（用于轮播显示）
  NewsAnnouncementModel? getCurrentNews(int index) {
    if (_newsList.isEmpty || index < 0 || index >= _newsList.length) {
      return null;
    }
    return _newsList[index];
  }

  NewsAnnouncementProvider(this._apiClient) {
    _logger.i('🔍 NewsAnnouncementProvider 初始化完成');
    _loadFromLocalStorage();
    _startUpdateTimer();
  }

  ///1, 从本地存储加载新闻数据
  Future<void> _loadFromLocalStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 加载新闻列表
      final newsJson = prefs.getString(_storageKey);
      if (newsJson != null) {
        final List<dynamic> newsData = json.decode(newsJson);
        _newsList = newsData
            .map((item) => NewsAnnouncementModel.fromJson(item))
            .toList();
        _logger.i('📱 从本地存储加载了 ${_newsList.length} 条新闻');
      }

      // 加载最后更新时间
      final lastUpdateStr = prefs.getString(_lastUpdateKey);
      if (lastUpdateStr != null) {
        _lastUpdateTime = DateTime.tryParse(lastUpdateStr);
        _logger.i('📅 最后更新时间: $_lastUpdateTime');
      }

      notifyListeners();
    } catch (e) {
      _logger.e('❌ 从本地存储加载新闻失败: $e');
    }
  }

  ///2, 保存到本地存储
  Future<void> _saveToLocalStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 保存新闻列表
      final newsJson =
          json.encode(_newsList.map((news) => news.toJson()).toList());
      await prefs.setString(_storageKey, newsJson);

      // 保存最后更新时间
      if (_lastUpdateTime != null) {
        await prefs.setString(
            _lastUpdateKey, _lastUpdateTime!.toIso8601String());
      }

      _logger.i('💾 新闻数据已保存到本地存储');
    } catch (e) {
      _logger.e('❌ 保存到本地存储失败: $e');
    }
  }

  ///3, 启动定时更新定时器
  void _startUpdateTimer() {
    _updateTimer?.cancel();

    // 计算下次更新时间
    if (_lastUpdateTime != null) {
      _nextUpdateTime = _lastUpdateTime!.add(_updateInterval);
    } else {
      _nextUpdateTime = DateTime.now().add(_updateInterval);
    }

    // 启动定时器
    _updateTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _checkAndUpdate();
    });

    _logger.i('⏰ 新闻更新定时器已启动，下次更新: $_nextUpdateTime');
  }

  ///4, 检查并执行更新
  Future<void> _checkAndUpdate() async {
    if (_nextUpdateTime != null && DateTime.now().isAfter(_nextUpdateTime!)) {
      _logger.i('🔄 执行定时新闻更新');
      await fetchNewsAnnouncements();
    }
  }

  ///5, 获取新闻公报数据
  Future<void> fetchNewsAnnouncements({bool forceUpdate = false}) async {
    // 如果不是强制更新，检查是否需要更新
    if (!forceUpdate && _lastUpdateTime != null) {
      final timeSinceLastUpdate = DateTime.now().difference(_lastUpdateTime!);
      if (timeSinceLastUpdate < _updateInterval) {
        _logger.i('⏭️ 距离上次更新不足2小时，跳过更新');
        return;
      }
    }

    if (_isLoading) {
      _logger.i('⏳ 新闻更新已在进行中，跳过重复请求');
      return;
    }

    _isLoading = true;
    _hasError = false;
    _errorMessage = '';
    notifyListeners();

    try {
      _logger.i('🌐 开始获取新闻公报数据');

      final List<Map<String, dynamic>> rawNews =
          await _apiClient.getNewsAnnouncements();

      if (rawNews.isNotEmpty) {
        // 转换为模型对象，并过滤掉无效的新闻
        final List<NewsAnnouncementModel> newNewsList = [];

        for (final rawItem in rawNews) {
          try {
            final news = NewsAnnouncementModel.fromRssXml(rawItem);
            if (news.isValid) {
              newNewsList.add(news);
            }
          } catch (e) {
            // 跳过无效的新闻（比如不是今天的）
            _logger.d('⏭️ 跳过无效新闻: ${e.toString()}');
          }
        }

        if (newNewsList.isNotEmpty) {
          _newsList = newNewsList;
          _lastUpdateTime = DateTime.now();
          _logger.i('✅ 成功获取 ${_newsList.length} 条新闻公报');
        } else {
          _logger.w('⚠️ 没有找到有效的新闻公报');
        }
      } else {
        _logger.w('⚠️ 未获取到新闻公报数据');
      }
    } catch (e) {
      _hasError = true;
      _errorMessage = e.toString();
      _logger.e('❌ 获取新闻公报失败: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  ///6, 手动刷新新闻
  Future<void> refreshNews() async {
    _logger.i('🔄 手动刷新新闻数据');
    await fetchNewsAnnouncements(forceUpdate: true);
  }

  ///7, 获取更新倒计时
  String getUpdateCountdown() {
    if (_nextUpdateTime == null) return '未知';

    final now = DateTime.now();
    if (now.isAfter(_nextUpdateTime!)) {
      return '立即更新';
    }

    final remaining = _nextUpdateTime!.difference(now);
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes % 60;

    if (hours > 0) {
      return '${hours}小时${minutes}分钟';
    } else {
      return '${minutes}分钟';
    }
  }

  ///8, 获取最后更新时间的友好显示
  String getLastUpdateDisplay() {
    if (_lastUpdateTime == null) return '从未更新';

    final now = DateTime.now();
    final difference = now.difference(_lastUpdateTime!);

    if (difference.inMinutes < 1) {
      return '刚刚';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}分钟前';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}小时前';
    } else {
      return '${difference.inDays}天前';
    }
  }

  ///9, 清空新闻数据
  void clearNews() {
    _newsList.clear();
    _lastUpdateTime = null;
    _nextUpdateTime = null;
    _hasError = false;
    _errorMessage = '';
    _saveToLocalStorage();
    notifyListeners();
    _logger.i('🗑️ 新闻数据已清空');
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }
}
