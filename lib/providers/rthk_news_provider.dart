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
    _logger.i('🔍 RthkNewsProvider 初始化完成');
    _initializeData();
    _startUpdateTimer();
  }

  ///1, 初始化数据
  Future<void> _initializeData() async {
    await _loadFromLocalStorage();
    // 暂时使用模拟数据进行测试
    if (_newsList.isEmpty) {
      _logger.i('📱 本地存储为空，加载模拟数据用于测试');
      _loadMockData();
    }
  }

  ///2, 从本地存储加载新闻数据
  Future<void> _loadFromLocalStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 加载新闻列表
      final newsJson = prefs.getString(_storageKey);
      if (newsJson != null) {
        final List<dynamic> newsData = json.decode(newsJson);
        _newsList =
            newsData.map((item) => RthkNewsModel.fromJson(item)).toList();

        // 过滤掉网络错误提示数据和模拟数据
        final originalCount = _newsList.length;
        _newsList = _newsList
            .where((news) => !news.guid.startsWith('network_error_') && 
                           !news.guid.startsWith('mock_news_'))
            .toList();
        
        if (_newsList.length < originalCount) {
          _logger.w('⚠️ 已过滤掉 ${originalCount - _newsList.length} 条测试/错误数据');
        }

        _logger.i('📱 从本地存储加载了 ${_newsList.length} 条新闻');
      } else {
        _logger.i('📱 本地存储中没有新闻数据');
      }

      // 加载最后更新时间
      final lastUpdateStr = prefs.getString(_lastUpdateKey);
      if (lastUpdateStr != null) {
        _lastUpdateTime = DateTime.tryParse(lastUpdateStr);
        _logger.i('📅 最后更新时间: $_lastUpdateTime');
      } else {
        _logger.i('📅 本地存储中没有最后更新时间记录');
      }

      notifyListeners();
    } catch (e) {
      _logger.e('❌ 从本地存储加载新闻失败: $e');
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

      _logger.i('💾 新闻数据已保存到本地存储');
    } catch (e) {
      _logger.e('❌ 保存到本地存储失败: $e');
    }
  }

  ///4, 启动定时更新定时器
  void _startUpdateTimer() {
    _updateTimer?.cancel();

    // 启动定时器，每30分鈡检查一次
    _updateTimer = Timer.periodic(const Duration(minutes: 30), (timer) {
      _checkAndUpdate();
    });

    _logger.i('⏰ RTHK新闻更新定时器已启动，更新间隔: 30分鈡');
  }

  ///5, 检查并执行更新
  Future<void> _checkAndUpdate() async {
    // 使用模拟数据时跳过自动更新
    _logger.i('⏭️ 当前使用模拟数据，跳过自动更新');
    return;
    
    /* 暂时注释掉原有的自动更新逻辑
    // 移除测试模式检查，恢复正常更新逻辑
    if (_lastUpdateTime != null) {
      final timeSinceLastUpdate = DateTime.now().difference(_lastUpdateTime!);
      if (timeSinceLastUpdate < _updateInterval) {
        return; // 距离上次更新不足30分鈡，跳过
      }
    }

    _logger.i('🔄 执行定时新闻更新');

    // 记录更新前的新闻数量，用于判断是否成功
    final newsCountBeforeUpdate = _newsList.length;

    try {
      await fetchRthkNews();

      // 检查更新是否成功（新闻数量是否有变化）
      if (_newsList.length != newsCountBeforeUpdate) {
        _logger
            .i('✅ 定时更新成功，新闻数量从 $newsCountBeforeUpdate 更新为 ${_newsList.length}');
      } else {
        _logger.i('ℹ️ 定时更新完成，新闻数量未变化（${_newsList.length}）');
      }
    } catch (e) {
      _logger.e('❌ 定时更新失败: $e');
      // 定时更新失败不影响现有数据，继续使用缓存
    }
    */
  }

  ///5, 获取RTHK新闻数据
  Future<void> fetchRthkNews({bool forceUpdate = false}) async {
    _logger.i('🔄 暂时跳过API调用，使用模拟数据进行测试');
    
    // 暂时跳过API调用，直接返回
    if (!forceUpdate && _newsList.isNotEmpty) {
      _logger.i('⏭️ 模拟数据已存在，跳过重复加载');
      return;
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
      // 模拟API调用延迟
      await Future.delayed(const Duration(milliseconds: 500));
      
      _logger.i('📱 使用模拟数据替代API调用');
      _loadMockData();
      
    } catch (e) {
      _hasError = true;
      _errorMessage = e.toString();
      _logger.e('❌ 模拟数据加载失败: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }

    /* 暂时注释掉原有的API调用逻辑
    // 如果不是强制更新，检查是否需要更新
    if (!forceUpdate && _lastUpdateTime != null) {
      final timeSinceLastUpdate = DateTime.now().difference(_lastUpdateTime!);
      if (timeSinceLastUpdate < _updateInterval) {
        _logger.i('⏭️ 距离上次更新不足30分鈡，跳过更新');
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

      // 检查缓存中是否有数据
      if (_newsList.isEmpty) {
        // 只有在缓存为空时才显示网络错误提示
        _logger.i('🔄 缓存为空，显示网络错误提示');
        _useNetworkErrorPrompt();

        // 网络错误提示也要保存到本地存储
        await _saveToLocalStorage();

        // 通知UI更新
        notifyListeners();
      } else {
        // 缓存中有数据，继续使用缓存数据，不清理或更新
        _logger.i('📱 API失败但缓存中有 ${_newsList.length} 条新闻，继续使用缓存数据');
        _logger.i('📅 最后更新时间: $_lastUpdateTime');

        // 不更新数据，保持原有缓存数据
        // 不调用notifyListeners()，避免UI刷新
      }
    } finally {
      _isLoading = false;
      // 注意：这里不再调用notifyListeners()，因为成功时已经在上面调用了
    }
    */
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
    _logger.i('⚠️ 网络連接失败，显示错误提示信息');
    _logger.w('⚠️ 注意：显示网络連接失败提示，而不是模拟数据');
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

  ///7.1, 获取当前数据状态信息
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

  ///8, 获取所有新闻的显示文本
  List<String> getAllNewsDisplayTexts() {
    return _newsList.map((news) {
      // 格式化显示文本：时间 + 标题
      final timeStr = news.formattedTime.isNotEmpty
          ? news.formattedTime
          : '${news.pubDate.hour.toString().padLeft(2, '0')}:${news.pubDate.minute.toString().padLeft(2, '0')}';

      return '【$timeStr】${news.title}';
    }).toList();
  }

  ///9, 暂停跑马灯滚动
  void pauseScrolling() {
    if (!_isScrollingPaused) {
      _isScrollingPaused = true;
      _logger.i('⏸️ RTHK新闻跑马灯已暂停');
      notifyListeners();
    }
  }

  ///10, 恢复跑马灯滚动
  void resumeScrolling() {
    if (_isScrollingPaused) {
      _isScrollingPaused = false;
      _logger.i('▶️ RTHK新闻跑马灯已恢复');
      notifyListeners();
    }
  }

  ///11, 加载模拟数据用于测试
  void _loadMockData() {
    final now = DateTime.now();
    
    _newsList = [
      RthkNewsModel(
        title: '政府宣布新一輪消費券計劃將於下月推出，每人可獲\$5000電子消費券',
        guid: 'mock_news_001',
        link: 'https://news.rthk.hk/rthk/tc/component/k2/1689234-20241227.htm',
        pubDate: now.subtract(const Duration(minutes: 5)),
        formattedTime: '${(now.hour - 0).toString().padLeft(2, '0')}:${(now.minute - 5).toString().padLeft(2, '0')}',
      ),
      RthkNewsModel(
        title: '天文台預測本週氣溫將逐步回升，週末最高可達25度',
        guid: 'mock_news_002', 
        link: 'https://news.rthk.hk/rthk/tc/component/k2/1689235-20241227.htm',
        pubDate: now.subtract(const Duration(minutes: 15)),
        formattedTime: '${(now.hour - 0).toString().padLeft(2, '0')}:${(now.minute - 15).toString().padLeft(2, '0')}',
      ),
      RthkNewsModel(
        title: '港鐵宣布新增車廂監察系統，提升乘客安全保障',
        guid: 'mock_news_003',
        link: 'https://news.rthk.hk/rthk/tc/component/k2/1689236-20241227.htm', 
        pubDate: now.subtract(const Duration(minutes: 25)),
        formattedTime: '${(now.hour - 0).toString().padLeft(2, '0')}:${(now.minute - 25).toString().padLeft(2, '0')}',
      ),
      RthkNewsModel(
        title: '教育局推出新措施支援基層學童學習，提供免費上網設備',
        guid: 'mock_news_004',
        link: 'https://news.rthk.hk/rthk/tc/component/k2/1689237-20241227.htm',
        pubDate: now.subtract(const Duration(minutes: 35)),
        formattedTime: '${(now.hour - 0).toString().padLeft(2, '0')}:${(now.minute - 35).toString().padLeft(2, '0')}',
      ),
      RthkNewsModel(
        title: '醫管局引進新醫療技術，縮短病人輪候時間',
        guid: 'mock_news_005',
        link: 'https://news.rthk.hk/rthk/tc/component/k2/1689238-20241227.htm',
        pubDate: now.subtract(const Duration(minutes: 45)),
        formattedTime: '${(now.hour - 0).toString().padLeft(2, '0')}:${(now.minute - 45).toString().padLeft(2, '0')}',
      ),
      RthkNewsModel(
        title: '環保署推行新回收計劃，鼓勵市民參與減廢行動',
        guid: 'mock_news_006',
        link: 'https://news.rthk.hk/rthk/tc/component/k2/1689239-20241227.htm',
        pubDate: now.subtract(const Duration(hours: 1, minutes: 5)),
        formattedTime: '${(now.hour - 1).toString().padLeft(2, '0')}:${(now.minute - 5).toString().padLeft(2, '0')}',
      ),
      RthkNewsModel(
        title: '運輸署宣布巴士路線重組計劃，優化公共交通服務',
        guid: 'mock_news_007',
        link: 'https://news.rthk.hk/rthk/tc/component/k2/1689240-20241227.htm',
        pubDate: now.subtract(const Duration(hours: 1, minutes: 15)),
        formattedTime: '${(now.hour - 1).toString().padLeft(2, '0')}:${(now.minute - 15).toString().padLeft(2, '0')}',
      ),
      RthkNewsModel(
        title: '房屋署公布居屋新申請安排，預計下半年推售新項目',
        guid: 'mock_news_008',
        link: 'https://news.rthk.hk/rthk/tc/component/k2/1689241-20241227.htm',
        pubDate: now.subtract(const Duration(hours: 1, minutes: 25)),
        formattedTime: '${(now.hour - 1).toString().padLeft(2, '0')}:${(now.minute - 25).toString().padLeft(2, '0')}',
      ),
      RthkNewsModel(
        title: '創新科技署推出科技券升級版，加強對中小企支援',
        guid: 'mock_news_009',
        link: 'https://news.rthk.hk/rthk/tc/component/k2/1689242-20241227.htm',
        pubDate: now.subtract(const Duration(hours: 1, minutes: 35)),
        formattedTime: '${(now.hour - 1).toString().padLeft(2, '0')}:${(now.minute - 35).toString().padLeft(2, '0')}',
      ),
      RthkNewsModel(
        title: '衞生署提醒市民注意流感高峰期，籲及時接種疫苗',
        guid: 'mock_news_010',
        link: 'https://news.rthk.hk/rthk/tc/component/k2/1689243-20241227.htm',
        pubDate: now.subtract(const Duration(hours: 2, minutes: 10)),
        formattedTime: '${(now.hour - 2).toString().padLeft(2, '0')}:${(now.minute - 10).toString().padLeft(2, '0')}',
      ),
    ];
    
    _lastUpdateTime = now;
    _hasError = false;
    _errorMessage = '';
    
    _logger.i('📱 已加載 ${_newsList.length} 條模擬新聞數據');
    
    // 保存到本地存储
    _saveToLocalStorage();
    
    notifyListeners();
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }
}
