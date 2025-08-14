import 'dart:async';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:iboard_app/providers/app_data_provider.dart';

/// 底部天气和二维码轮播Provider
/// 负责管理底部右侧天气预报和二维码的轮播逻辑、暂停恢复、定时器管理等
class BottomWeatherQrcodeCarouselProvider extends ChangeNotifier {
  final Logger _logger = Logger();

  // 定时器管理
  Timer? _bottomTimer;
  Timer? _debugTimer;

  // AppDataProvider引用 - 用于获取动态设置
  AppDataProvider? _appDataProvider;

  // 状态管理
  bool _isBottomCarouselPaused = false;
  bool _showWeather = true; // true显示天气，false显示二维码

  // 轮播间隔时间（秒）- 将从设置中获取，默认为5秒
  static const int _defaultCarouselInterval = 5;

  // 时间记录相关 - 用于全屏广告暂停恢复
  DateTime? _currentBottomStartTime; // 当前底部轮播开始时间
  DateTime? _currentBottomPauseTime; // 当前底部轮播暂停时间
  Duration _bottomElapsedTime = Duration.zero; // 底部轮播已播放时间
  Duration _bottomDuration =
      const Duration(seconds: _defaultCarouselInterval); // 底部轮播总时长

  // Getters
  bool get isBottomCarouselPaused => _isBottomCarouselPaused;
  bool get showWeather => _showWeather;
  Duration get bottomDuration => _bottomDuration;
  DateTime? get currentBottomStartTime => _currentBottomStartTime;
  Duration get bottomElapsedTime => _bottomElapsedTime;

  BottomWeatherQrcodeCarouselProvider() {
    // _logger.i('🌤️ 底部天气二维码轮播Provider初始化');
  }

  /// 设置AppDataProvider引用
  void setAppDataProvider(AppDataProvider appDataProvider) {
    _appDataProvider = appDataProvider;
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
    // _logger.i('🌤️ [初始化] 底部天气二维码轮播初始化');
    startBottomTimer();
    startDebugTimer();
  }

  ///2，启动底部轮播计时器
  void startBottomTimer() {
    // _logger.d('🌤️ 开始底部轮播计时器: paused=$_isBottomCarouselPaused');
    _bottomTimer?.cancel();

    if (_isBottomCarouselPaused) {
      // _logger.w('⚠️ 底部轮播计时器条件不满足: paused=$_isBottomCarouselPaused');
      return;
    }

    // 记录当前轮播开始时间
    _currentBottomStartTime = DateTime.now();
    _bottomDuration = Duration(seconds: _getCarouselInterval());

    // 只有当切换到新状态时才重置已播放时间
    _bottomElapsedTime = Duration.zero;

    // _logger.d(
    //     '▶️ 启动底部轮播计时器: showWeather=$_showWeather, duration=$_bottomDuration');
    // _logger.i(
    //     '📝 记录底部轮播开始时间: $_currentBottomStartTime, 时长: ${_bottomDuration.inSeconds}秒');

    _bottomTimer = Timer(_bottomDuration, () {
      if (!_isBottomCarouselPaused) {
        // _logger.d('⏭️ 底部轮播计时器到期，切换显示状态');
        _switchDisplay();
      }
    });
  }

  ///3，切换显示状态（天气 <-> 二维码）
  void _switchDisplay() {
    _showWeather = !_showWeather;
    // _logger.i('🔄 底部轮播切换: ${_showWeather ? "显示天气" : "显示二维码"}');
    notifyListeners();

    // 启动下一个计时器
    startBottomTimer();
  }

  ///4，暂停底部轮播
  void pauseBottomCarousel() {
    // _logger.i('🛑 暂停底部轮播');

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
        // _logger.i(
        //     '📊 [暂停] 底部轮播 - 已播放: ${_bottomElapsedTime.inSeconds}s/${_bottomDuration.inSeconds}s, 剩余: ${remaining.inSeconds}s (轮播已完成)');
      } else {
        _bottomElapsedTime = totalElapsed;
        final remaining = _bottomDuration - _bottomElapsedTime;
        // _logger.i(
        //     '📊 [暂停] 底部轮播 - 已播放: ${_bottomElapsedTime.inSeconds}s/${_bottomDuration.inSeconds}s, 剩余: ${remaining.inSeconds}s');
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
    // _logger.i('▶️ 恢复底部轮播');

    // 设置底部轮播为运行状态
    _isBottomCarouselPaused = false;

    // 计算剩余播放时间并恢复定时器
    if (_currentBottomStartTime != null) {
      final remainingTime = _bottomDuration - _bottomElapsedTime;
      // _logger.i(
      //     '🔄 [恢复] 底部轮播 - 继续播放剩余时间：${remainingTime.inSeconds}s (已播放: ${_bottomElapsedTime.inSeconds}s)');

      if (remainingTime.inSeconds > 0) {
        // 更新当前轮播开始时间
        _currentBottomStartTime = DateTime.now();

        // 继续播放剩余时间
        _bottomTimer = Timer(remainingTime, () {
          if (!_isBottomCarouselPaused) {
            // _logger.i('⏰ [定时] 底部轮播时间到，切换显示状态');
            _switchDisplay();
          }
        });
      } else {
        // 时间已到，直接切换
        // _logger.i('⚡ [跳过] 底部轮播剩余时间为0，直接切换显示状态');
        _switchDisplay();
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
    // _logger.i('🎛️ 底部轮播状态更新: ${!_isBottomCarouselPaused ? "运行" : "暂停"}');

    if (isPaused) {
      pauseBottomCarousel();
    } else {
      resumeBottomCarousel();
    }
  }

  ///7，检查并恢复底部轮播（监控定时器使用）
  void checkAndRestoreBottomCarousel() {
    if (!_isBottomCarouselPaused && _bottomTimer == null) {
      // _logger.w('🔍 [监控] 检测到底部轮播定时器丢失，重新启动');
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

        // _logger.i(
        //     '🐛 🌤️ 底部轮播: ${_showWeather ? "天气" : "二维码"} ${remainingSeconds}s/${_bottomDuration.inSeconds}s');
      }
    });
  }

  ///9，停止调试定时器
  void stopDebugTimer() {
    _debugTimer?.cancel();
  }

  ///10，暂停所有定时器（用于设置页面）
  void pauseAllTimersForSettings() {
    // _logger.i('⚙️ 暂停底部轮播所有定时器 - 进入设置页面');
    _bottomTimer?.cancel();
    _debugTimer?.cancel();
    _isBottomCarouselPaused = true;
  }

  ///11，恢复所有定时器（从设置页面返回）
  void resumeAllTimersFromSettings() {
    // _logger.i('↩️ 恢复底部轮播所有定时器 - 从设置页面返回');
    _isBottomCarouselPaused = false;
    startBottomTimer();
    startDebugTimer();
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
