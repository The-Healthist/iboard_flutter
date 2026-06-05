import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:iboard_app/http/api_client.dart';
import 'package:iboard_app/models/rthk_news_model.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 香港电台新闻提供者
/// 负责管理RTHK新闻的获取、存储和定时更新
class RthkNewsProvider extends ChangeNotifier {
  final Logger _logger = Logger();
  final ApiClient _apiClient;

  // 新闻数据
  List<RthkNewsModel> _newsList = [];

  // 状态管理
  bool _isLoading = false;
  bool _hasError = false;
  String _errorMessage = '';

  // 定时更新管理
  Timer? _updateTimer;
  DateTime? _lastUpdateTime;
  static const Duration _updateInterval = Duration(minutes: 30); // 30分鈡更新一次

  // 本地存储键
  static const String _storageKey = 'rthk_news';
  static const String _lastUpdateKey = 'rthk_news_last_update';

  // 滚动控制状态
  bool _isScrollingPaused = false;

  // Getters
  List<RthkNewsModel> get newsList => _newsList;
  bool get isLoading => _isLoading;
  bool get hasError => _hasError;
  String get errorMessage => _errorMessage;
  DateTime? get lastUpdateTime => _lastUpdateTime;
  int get newsCount => _newsList.length;
  bool get isScrollingPaused => _isScrollingPaused;

  RthkNewsProvider(this._apiClient) {
    _initializeData();
    _startUpdateTimer();
  }

  ///1, 初始化数据
  Future<void> _initializeData() async {
    await _loadFromLocalStorage();
  }

  ///2, 从本地存储加载新闻数据
  Future<void> _loadFromLocalStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 加载新闻列表
      final newsJson = prefs.getString(_storageKey);
      if (newsJson != null) {
        final decoded = json.decode(newsJson);
        if (decoded is List) {
          _newsList = decoded
              .whereType<Map>()
              .map((item) => RthkNewsModel.fromJson(_parseMap(item)))
              .toList();
        } else {
          _newsList = [];
        }

        // 过滤掉网络错误提示数据和模拟数据
        _newsList = _newsList
            .where((news) =>
                !news.guid.startsWith('network_error_') &&
                !news.guid.startsWith('mock_news_'))
            .toList();
      }

      // 加载最后更新时间
      final lastUpdateStr = prefs.getString(_lastUpdateKey);
      if (lastUpdateStr != null) {
        _lastUpdateTime = DateTime.tryParse(lastUpdateStr);
      }

      notifyListeners();
    } catch (e) {
      _logger.e(' 从本地存储加载新闻失败: $e');
      // 加载失败时，保持空列表状态
      _newsList = [];
      _lastUpdateTime = null;
    }
  }

  ///3, 保存到本地存储
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
    } catch (e) {
      _logger.e(' 保存到本地存储失败: $e');
    }
  }

  ///4, 启动定时更新定时器
  void _startUpdateTimer() {
    _updateTimer?.cancel();

    // 启动定时器，每30分鈡检查一次
    _updateTimer = Timer.periodic(const Duration(minutes: 30), (timer) {
      _checkAndUpdate();
    });
  }

  ///5, 检查并执行更新
  Future<void> _checkAndUpdate() async {
    if (_lastUpdateTime != null) {
      final timeSinceLastUpdate = DateTime.now().difference(_lastUpdateTime!);
      if (timeSinceLastUpdate < _updateInterval) {
        return; // 距离上次更新不足30分鈡，跳过
      }
    }

    // 记录更新前的新闻数量，用于判断是否成功
    final newsCountBeforeUpdate = _newsList.length;

    try {
      await fetchRthkNews();

      // 检查更新是否成功（新闻数量是否有变化）
      final didUpdate = _newsList.length != newsCountBeforeUpdate;
      if (!didUpdate && _newsList.isEmpty) {
        _logger.w(' 定时更新完成但仍无新闻数据');
      }
    } catch (e) {
      _logger.e(' 定时更新失败: $e');
      // 定时更新失败不影响现有数据，继续使用缓存
    }
  }

  ///6, 获取RTHK新闻数据
  Future<void> fetchRthkNews({bool forceUpdate = false}) async {
    // 如果不是强制更新，检查是否需要更新
    if (!forceUpdate && _lastUpdateTime != null) {
      final timeSinceLastUpdate = DateTime.now().difference(_lastUpdateTime!);
      if (timeSinceLastUpdate < _updateInterval) {
        return;
      }
    }

    if (_isLoading) {
      return;
    }

    _isLoading = true;
    _hasError = false;
    _errorMessage = '';
    notifyListeners();

    try {
      final List<Map<String, dynamic>> rawNews = await _apiClient.getRthkNews();

      if (rawNews.isNotEmpty) {
        // 转换为模型对象
        final List<RthkNewsModel> newNewsList = rawNews
            .map((item) => RthkNewsModel.fromRssXml(item))
            .where((news) => news.title.isNotEmpty) // 过滤掉无效的新闻
            .toList();

        // 按发布时间排序（最新的在前）
        newNewsList.sort((a, b) => b.pubDate.compareTo(a.pubDate));

        if (newNewsList.isNotEmpty) {
          // 只有成功获取到有效数据时才更新
          _newsList = newNewsList;
          _lastUpdateTime = DateTime.now();

          // 保存到本地存储
          await _saveToLocalStorage();

          // 通知UI更新
          notifyListeners();
        } else {
          _logger.w(' 没有找到有效的新闻');
          // 没有有效数据时不更新存储，保持原有数据
        }
      } else {
        _logger.w(' 未获取到新闻数据');
        // 没有数据时不更新存储，保持原有数据
      }
    } catch (e) {
      // 检查缓存中是否有数据
      if (_newsList.isEmpty) {
        _hasError = true;
        _errorMessage = e.toString();
        _logger.e(' 获取RTHK新闻失败且无缓存可用: $e');

        // 只有在缓存为空时才显示网络错误提示
        _useNetworkErrorPrompt();

        // 网络错误提示也要保存到本地存储
        await _saveToLocalStorage();

        // 通知UI更新
        notifyListeners();
      } else {
        _hasError = false;
        _errorMessage = '';

        // 缓存中有数据，继续使用缓存数据，不清理或更新
        _logger.w(' RTHK新闻API暂不可用，继续使用 ${_newsList.length} 条缓存新闻: $e');

        // 不更新数据，保持原有缓存数据
        // 不调用notifyListeners()，避免UI刷新
      }
    } finally {
      _isLoading = false;
      // 注意：这里不再调用notifyListeners()，因为成功时已经在上面调用了
    }
  }

  ///5.1, 使用网络連接失败提示
  void _useNetworkErrorPrompt() {
    final now = DateTime.now();
    _newsList = [
      RthkNewsModel(
        title: '網絡未能運接，暫無法顯示資訊',
        guid: 'network_error_001',
        link: 'https://news.rthk.hk',
        pubDate: now,
        formattedTime:
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
      ),
    ];

    _lastUpdateTime = now;
    _logger.w(' 注意：显示网络連接失败提示，而不是模拟数据');
  }

  ///7, 手动刷新新闻
  Future<void> refreshNews() async {
    await fetchRthkNews(forceUpdate: true);
  }

  ///8, 清空新闻数据
  void clearNews() {
    _newsList.clear();
    _lastUpdateTime = null;
    _hasError = false;
    _errorMessage = '';
    _saveToLocalStorage();
    notifyListeners();
  }

  ///8.1, 获取当前数据状态信息
  Map<String, dynamic> getDataStatus() {
    return {
      'newsCount': _newsList.length,
      'hasError': _hasError,
      'errorMessage': _errorMessage,
      'lastUpdateTime': _lastUpdateTime?.toIso8601String(),
      'isLoading': _isLoading,
      'isUsingNetworkErrorPrompt': _newsList.isNotEmpty &&
          _newsList.any((news) => news.guid.startsWith('network_error_')),
    };
  }

  ///9, 获取所有新闻的显示文本
  List<String> getAllNewsDisplayTexts() {
    return _newsList.map((news) {
      // 格式化显示文本：时间 + 标题
      final timeStr = news.formattedTime.isNotEmpty
          ? news.formattedTime
          : '${news.pubDate.hour.toString().padLeft(2, '0')}:${news.pubDate.minute.toString().padLeft(2, '0')}';

      return '【$timeStr】${news.title}';
    }).toList();
  }

  ///10, 暂停跑马灯滚动
  void pauseScrolling() {
    if (!_isScrollingPaused) {
      _isScrollingPaused = true;
      notifyListeners();
    }
  }

  ///11, 恢复跑马灯滚动
  void resumeScrolling() {
    if (_isScrollingPaused) {
      _isScrollingPaused = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }
}

Map<String, dynamic> _parseMap(Object? value) {
  return _nullableMap(value) ?? const {};
}

Map<String, dynamic>? _nullableMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return null;
}
