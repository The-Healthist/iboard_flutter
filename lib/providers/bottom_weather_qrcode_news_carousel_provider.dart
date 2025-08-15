import 'dart:async';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:iboard_app/providers/app_data_provider.dart';
import 'package:iboard_app/models/news_announcement_model.dart';
import 'package:iboard_app/providers/news_announcement_provider.dart';

/// 轮播状态枚举
enum CarouselState { weather, qrcode, news }

/// 底部天气、二维码和新闻公报轮播Provider
/// 负责管理底部右侧天气预报、二维码和新闻公报的轮播逻辑
class BottomWeatherQrcodeNewsCarouselProvider extends ChangeNotifier {
  final Logger _logger = Logger();

  // 定时器管理
  Timer? _bottomTimer;
  Timer? _debugTimer;

  // AppDataProvider引用 - 用于获取动态设置
  AppDataProvider? _appDataProvider;

  // NewsAnnouncementProvider引用 - 用于获取新闻数据
  NewsAnnouncementProvider? _newsProvider;

  // 状态管理
  bool _isBottomCarouselPaused = false;

  // 轮播状态
  CarouselState _currentState = CarouselState.weather;

  // 轮播间隔时间（秒）- 将从设置中获取，默认为5秒
  static const int _defaultCarouselInterval = 5;

  // 时间记录相关 - 用于全屏广告暂停恢复
  DateTime? _currentBottomStartTime; // 当前底部轮播开始时间
  DateTime? _currentBottomPauseTime; // 当前底部轮播暂停时间
  Duration _bottomElapsedTime = Duration.zero; // 底部轮播已播放时间
  Duration _bottomDuration =
      const Duration(seconds: _defaultCarouselInterval); // 底部轮播总时长

  // 新闻轮播索引
  int _currentNewsIndex = 0;

  // Getters
  bool get isBottomCarouselPaused => _isBottomCarouselPaused;
  CarouselState get currentState => _currentState;
  Duration get bottomDuration => _bottomDuration;
  DateTime? get currentBottomStartTime => _currentBottomStartTime;
  Duration get bottomElapsedTime => _bottomElapsedTime;
  int get currentNewsIndex => _currentNewsIndex;

  // 便捷getter
  bool get showWeather => _currentState == CarouselState.weather;
  bool get showQrcode => _currentState == CarouselState.qrcode;
  bool get showNews => _currentState == CarouselState.news;

  BottomWeatherQrcodeNewsCarouselProvider() {
    _logger.i('🌤️ 底部天气二维码新闻轮播Provider初始化');
  }

  /// 设置AppDataProvider引用
  void setAppDataProvider(AppDataProvider appDataProvider) {
    _appDataProvider = appDataProvider;
  }

  /// 设置NewsAnnouncementProvider引用
  void setNewsProvider(NewsAnnouncementProvider newsProvider) {
    _newsProvider = newsProvider;
  }

  /// 获取动态轮播间隔时间（秒）
  int _getCarouselInterval() {
    if (_appDataProvider?.deviceSettings != null) {
      final interval = _appDataProvider!.deviceSettings!.bottomCarouselDuration;
      _logger.i('🌤️ [动态设置] 底部轮播间隔时间: ${interval}秒');
      return interval;
    }
    // 如果无法获取设置，使用默认值
    _logger.w('🌤️ [动态设置] 无法获取设置，使用默认轮播间隔: $_defaultCarouselInterval秒');
    return _defaultCarouselInterval;
  }

  ///1，初始化底部轮播
  void initializeBottomCarousel() {
    _logger.i('🌤️ [初始化] 底部天气二维码新闻轮播初始化');
    startBottomTimer();
    startDebugTimer();
  }

  ///2，启动底部轮播计时器
  void startBottomTimer() {
    _logger.d('🌤️ 开始底部轮播计时器: paused=$_isBottomCarouselPaused');
    _bottomTimer?.cancel();

    if (_isBottomCarouselPaused) {
      _logger.w('⚠️ 底部轮播计时器条件不满足: paused=$_isBottomCarouselPaused');
      return;
    }

    // 记录当前轮播开始时间
    _currentBottomStartTime = DateTime.now();
    _bottomDuration = Duration(seconds: _getCarouselInterval());

    // 只有当切换到新状态时才重置已播放时间
    _bottomElapsedTime = Duration.zero;

    _logger.d('▶️ 启动底部轮播计时器: state=$_currentState, duration=$_bottomDuration');
    _logger.i(
        '📝 记录底部轮播开始时间: $_currentBottomStartTime, 时长: ${_bottomDuration.inSeconds}秒');

    _bottomTimer = Timer(_bottomDuration, () {
      if (!_isBottomCarouselPaused) {
        _logger.d('⏭️ 底部轮播计时器到期，切换到下一个状态');
        _switchToNextState();
      }
    });
  }

  ///3，切换到下一个轮播状态
  void _switchToNextState() {
    switch (_currentState) {
      case CarouselState.weather:
        _currentState = CarouselState.qrcode;
        _logger.i('🔄 底部轮播切换: 天气 -> 二维码');
        break;
      case CarouselState.qrcode:
        // 检查是否有新闻数据
        if (_newsProvider != null && _newsProvider!.newsList.isNotEmpty) {
          _currentState = CarouselState.news;
          _currentNewsIndex = 0; // 重置新闻索引
          _logger.i('🔄 底部轮播切换: 二维码 -> 新闻公报');
        } else {
          // 如果没有新闻，直接回到天气
          _currentState = CarouselState.weather;
          _logger.i('🔄 底部轮播切换: 二维码 -> 天气 (无新闻数据)');
        }
        break;
      case CarouselState.news:
        // 新闻公报显示完毕后，回到天气
        _currentState = CarouselState.weather;
        _currentNewsIndex = 0; // 重置新闻索引
        _logger.i('🔄 底部轮播切换: 新闻公报 -> 天气');
        break;
    }
    
    notifyListeners();

    // 启动下一个计时器
    startBottomTimer();
  }

  ///4，暂停底部轮播
  void pauseBottomCarousel() {
    _logger.i('🛑 暂停底部轮播');

    // 记录当前播放时间
    _currentBottomPauseTime = DateTime.now();

    // 计算已播放时间
    if (_currentBottomStartTime != null) {
      final rawElapsed =
          _currentBottomPauseTime!.difference(_currentBottomStartTime!);
      final totalElapsed = rawElapsed + _bottomElapsedTime;

      // 确保已播放时间不超过轮播总时长
      if (totalElapsed >= _bottomDuration) {
        _bottomElapsedTime = _bottomDuration;
        final remaining = Duration.zero;
        _logger.i(
            '📊 [暂停] 底部轮播 - 已播放: ${_bottomElapsedTime.inSeconds}s/${_bottomDuration.inSeconds}s, 剩余: ${remaining.inSeconds}s (轮播已完成)');
      } else {
        _bottomElapsedTime = totalElapsed;
        final remaining = _bottomDuration - _bottomElapsedTime;
        _logger.i(
            '📊 [暂停] 底部轮播 - 已播放: ${_bottomElapsedTime.inSeconds}s/${_bottomDuration.inSeconds}s, 剩余: ${remaining.inSeconds}s');
      }
    }

    // 设置底部轮播为暂停状态
    _isBottomCarouselPaused = true;

    // 暂停定时器
    _bottomTimer?.cancel();

    notifyListeners();
  }

  ///5，恢复底部轮播
  void resumeBottomCarousel() {
    _logger.i('▶️ 恢复底部轮播');

    // 设置底部轮播为运行状态
    _isBottomCarouselPaused = false;

    // 计算剩余播放时间并恢复定时器
    if (_currentBottomStartTime != null) {
      final remainingTime = _bottomDuration - _bottomElapsedTime;
      _logger.i(
          '🔄 [恢复] 底部轮播 - 继续播放剩余时间：${remainingTime.inSeconds}s (已播放: ${_bottomElapsedTime.inSeconds}s)');

      if (remainingTime.inSeconds > 0) {
        // 更新当前轮播开始时间
        _currentBottomStartTime = DateTime.now();

        // 继续播放剩余时间
        _bottomTimer = Timer(remainingTime, () {
          if (!_isBottomCarouselPaused) {
            _logger.i('⏰ [定时] 底部轮播时间到，切换显示状态');
            _switchToNextState();
          }
        });
      } else {
        // 时间已到，直接切换
        _logger.i('⚡ [跳过] 底部轮播剩余时间为0，直接切换显示状态');
        _switchToNextState();
      }
    } else {
      // 如果没有记录开始时间，重新开始计时
      startBottomTimer();
    }

    notifyListeners();
  }

  ///6，更新轮播暂停状态
  void updateCarouselPauseState(bool isPaused) {
    _isBottomCarouselPaused = isPaused;
    _logger.i('🎛️ 底部轮播状态更新: ${!_isBottomCarouselPaused ? "运行" : "暂停"}');

    if (isPaused) {
      pauseBottomCarousel();
    } else {
      resumeBottomCarousel();
    }
  }

  ///7，检查并恢复底部轮播（监控定时器使用）
  void checkAndRestoreBottomCarousel() {
    if (!_isBottomCarouselPaused && _bottomTimer == null) {
      _logger.w('🔍 [监控] 检测到底部轮播定时器丢失，重新启动');
      startBottomTimer();
    }
  }

  ///8，启动调试定时器
  void startDebugTimer() {
    _debugTimer?.cancel();
    _debugTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isBottomCarouselPaused) return;

      if (_currentBottomStartTime != null) {
        final elapsed = DateTime.now().difference(_currentBottomStartTime!) +
            _bottomElapsedTime;
        final remaining = _bottomDuration - elapsed;
        final remainingSeconds = remaining.isNegative ? 0 : remaining.inSeconds;

        String stateInfo = '';
        switch (_currentState) {
          case CarouselState.weather:
            stateInfo = '天气';
            break;
          case CarouselState.qrcode:
            stateInfo = '二维码';
            break;
          case CarouselState.news:
            stateInfo =
                '新闻公报 (${_currentNewsIndex + 1}/${_newsProvider?.newsList.length ?? 0})';
            break;
        }

        _logger.i(
            '🐛 🌤️ 底部轮播: $stateInfo ${remainingSeconds}s/${_bottomDuration.inSeconds}s');
      }
    });
  }

  ///9，停止调试定时器
  void stopDebugTimer() {
    _debugTimer?.cancel();
  }

  ///10，暂停所有定时器（用于设置页面）
  void pauseAllTimersForSettings() {
    _logger.i('⚙️ 暂停底部轮播所有定时器 - 进入设置页面');
    _bottomTimer?.cancel();
    _debugTimer?.cancel();
    _isBottomCarouselPaused = true;
  }

  ///11，恢复所有定时器（从设置页面返回）
  void resumeAllTimersFromSettings() {
    _logger.i('↩️ 恢复底部轮播所有定时器 - 从设置页面返回');
    _isBottomCarouselPaused = false;
    startBottomTimer();
    startDebugTimer();
  }

  ///12，获取当前新闻（如果当前状态是新闻）
  NewsAnnouncementModel? getCurrentNews() {
    if (_currentState == CarouselState.news && 
        _newsProvider != null && 
        _newsProvider!.newsList.isNotEmpty &&
        _currentNewsIndex < _newsProvider!.newsList.length) {
      return _newsProvider!.newsList[_currentNewsIndex];
    }
    return null;
  }

  ///13，获取下一条新闻（用于手动切换）
  NewsAnnouncementModel? getNextNews() {
    if (_newsProvider != null && 
        _newsProvider!.newsList.isNotEmpty &&
        _currentNewsIndex < _newsProvider!.newsList.length - 1) {
      return _newsProvider!.newsList[_currentNewsIndex + 1];
    }
    return null;
  }

  ///14，手动切换到下一条新闻
  void switchToNextNews() {
    if (_currentState == CarouselState.news &&
        _newsProvider != null && 
        _newsProvider!.newsList.isNotEmpty &&
        _currentNewsIndex < _newsProvider!.newsList.length - 1) {
      _currentNewsIndex++;
      _logger.i('🔄 手动切换新闻: ${_currentNewsIndex + 1}/${_newsProvider!.newsList.length}');
      notifyListeners();
    }
  }

  ///15，手动切换到上一条新闻
  void switchToPreviousNews() {
    if (_currentState == CarouselState.news &&
        _currentNewsIndex > 0) {
      _currentNewsIndex--;
      _logger.i('🔄 手动切换新闻: ${_currentNewsIndex + 1}/${_newsProvider!.newsList.length}');
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _bottomTimer?.cancel();
    _bottomTimer = null;

    _debugTimer?.cancel();
    _debugTimer = null;

    super.dispose();
  }
}
