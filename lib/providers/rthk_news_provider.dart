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
  static const Duration _updateInterval = Duration(minutes: 30); // 30分钟更新一次

  // 本地存储键
  static const String _storageKey = 'rthk_news';
  static const String _lastUpdateKey = 'rthk_news_last_update';

  // Getters
  List<RthkNewsModel> get newsList => _newsList;
  bool get isLoading => _isLoading;
  bool get hasError => _hasError;
  String get errorMessage => _errorMessage;
  DateTime? get lastUpdateTime => _lastUpdateTime;
  int get newsCount => _newsList.length;

  RthkNewsProvider(this._apiClient) {
    _logger.i('🔍 RthkNewsProvider 初始化完成');
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
        _newsList =
            newsData.map((item) => RthkNewsModel.fromJson(item)).toList();
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

    // 启动定时器，每30分钟检查一次
    _updateTimer = Timer.periodic(const Duration(minutes: 30), (timer) {
      _checkAndUpdate();
    });

    _logger.i('⏰ RTHK新闻更新定时器已启动，更新间隔: 30分钟');
  }

  ///4, 检查并执行更新
  Future<void> _checkAndUpdate() async {
    if (_lastUpdateTime != null) {
      final timeSinceLastUpdate = DateTime.now().difference(_lastUpdateTime!);
      if (timeSinceLastUpdate < _updateInterval) {
        return; // 距离上次更新不足30分钟，跳过
      }
    }

    _logger.i('🔄 执行定时新闻更新');
    await fetchRthkNews();
  }

  ///5, 获取RTHK新闻数据
  Future<void> fetchRthkNews({bool forceUpdate = false}) async {
    // 如果不是强制更新，检查是否需要更新
    if (!forceUpdate && _lastUpdateTime != null) {
      final timeSinceLastUpdate = DateTime.now().difference(_lastUpdateTime!);
      if (timeSinceLastUpdate < _updateInterval) {
        _logger.i('⏭️ 距离上次更新不足30分钟，跳过更新');
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
      _logger.i('🌐 开始获取RTHK新闻数据');

      final List<Map<String, dynamic>> rawNews = await _apiClient.getRthkNews();
      _logger.i('📡 从API获取到 ${rawNews.length} 条原始新闻数据');

      if (rawNews.isNotEmpty) {
        // 转换为模型对象
        final List<RthkNewsModel> newNewsList = rawNews
            .map((item) => RthkNewsModel.fromRssXml(item))
            .where((news) => news.title.isNotEmpty) // 过滤掉无效的新闻
            .toList();

        _logger.i('🔄 转换后得到 ${newNewsList.length} 条有效新闻');

        // 按发布时间排序（最新的在前）
        newNewsList.sort((a, b) => b.pubDate.compareTo(a.pubDate));

        if (newNewsList.isNotEmpty) {
          // 只有成功获取到有效数据时才更新
          _newsList = newNewsList;
          _lastUpdateTime = DateTime.now();
          _logger.i('✅ 成功获取 ${_newsList.length} 条RTHK新闻');

          // 保存到本地存储
          await _saveToLocalStorage();
          
          // 通知UI更新
          notifyListeners();
        } else {
          _logger.w('⚠️ 没有找到有效的新闻');
          // 没有有效数据时不更新存储，保持原有数据
        }
      } else {
        _logger.w('⚠️ 未获取到新闻数据');
        // 没有数据时不更新存储，保持原有数据
      }
    } catch (e) {
      _hasError = true;
      _errorMessage = e.toString();
      _logger.e('❌ 获取RTHK新闻失败: $e');

      // 如果API失败，使用备用新闻数据
      _logger.i('🔄 使用备用新闻数据');
      _useFallbackNews();
      
      // 备用数据也要保存到本地存储
      await _saveToLocalStorage();
      
      // 通知UI更新
      notifyListeners();
    } finally {
      _isLoading = false;
      // 注意：这里不再调用notifyListeners()，因为成功时已经在上面调用了
    }
  }

  ///5.1, 使用备用新闻数据
  void _useFallbackNews() {
    final now = DateTime.now();
    _newsList = [
      RthkNewsModel(
        title: '香港经济持续复苏，第二季度GDP增长3.1%',
        guid: 'fallback_001',
        link: 'https://news.rthk.hk',
        pubDate: now.subtract(const Duration(hours: 2)),
        formattedTime:
            '${(now.hour - 2).toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
      ),
      RthkNewsModel(
        title: '恒生指数今日上涨2.1%，科技股表现强劲',
        guid: 'fallback_002',
        link: 'https://news.rthk.hk',
        pubDate: now.subtract(const Duration(hours: 4)),
        formattedTime:
            '${(now.hour - 4).toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
      ),
      RthkNewsModel(
        title: '港府推出新一轮消费券计划，提振本地经济',
        guid: 'fallback_003',
        link: 'https://news.rthk.hk',
        pubDate: now.subtract(const Duration(hours: 6)),
        formattedTime:
            '${(now.hour - 6).toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
      ),
      RthkNewsModel(
        title: '香港机场客运量恢复至疫情前80%水平',
        guid: 'fallback_004',
        link: 'https://news.rthk.hk',
        pubDate: now.subtract(const Duration(hours: 8)),
        formattedTime:
            '${(now.hour - 8).toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
      ),
      RthkNewsModel(
        title: '香港科技创新发展迅速，吸引全球投资',
        guid: 'fallback_005',
        link: 'https://news.rthk.hk',
        pubDate: now.subtract(const Duration(hours: 10)),
        formattedTime:
            '${(now.hour - 10).toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
      ),
    ];

    _lastUpdateTime = now;
    _logger.i('✅ 已加载 ${_newsList.length} 条备用新闻数据');
  }

  ///6, 手动刷新新闻
  Future<void> refreshNews() async {
    _logger.i('🔄 手动刷新新闻数据');
    await fetchRthkNews(forceUpdate: true);
  }

  ///7, 清空新闻数据
  void clearNews() {
    _newsList.clear();
    _lastUpdateTime = null;
    _hasError = false;
    _errorMessage = '';
    _saveToLocalStorage();
    notifyListeners();
    _logger.i('🗑️ 新闻数据已清空');
  }

  ///8, 获取所有新闻的显示文本
  List<String> getAllNewsDisplayTexts() {
    return _newsList.map((news) => news.displayText).toList();
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }
}
