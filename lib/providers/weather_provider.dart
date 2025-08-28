import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:iboard_app/http/weather.dart';
import 'package:iboard_app/models/weather_forecast_model.dart';
import 'package:iboard_app/models/current_weather_model.dart';
import 'package:iboard_app/models/weather_warning_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:iboard_app/providers/app_data_provider.dart';

/// 轮播状态枚举
enum CarouselState { weather, qrcode }

/// 当前天气卡片頁面枚举
enum CurrentWeatherPage { page1, page2 }

class WeatherProvider extends ChangeNotifier {
  final WeatherService _weatherService = WeatherService();

  // AppDataProvider引用 - 用于获取动态设置
  AppDataProvider? _appDataProvider;

  // 天气数据状态
  WeatherData? _weatherForecastData;
  CurrentWeatherDataModel? _currentWeatherData;
  WeatherWarningModel? _weatherWarningData;

  // 加载状态
  bool _isLoadingForecast = false;
  bool _isLoadingCurrent = false;
  bool _isLoadingWarning = false;

  // 错误状态
  String? _forecastError;
  String? _currentError;
  String? _warningError;

  // 定时更新
  Timer? _updateTimer;
  bool _isPeriodicUpdateActive = false;

  // 轮播状态管理
  Timer? _bottomTimer;
  Timer? _debugTimer;
  bool _isBottomCarouselPaused = false;
  CarouselState _currentState = CarouselState.weather;
  static const int _defaultCarouselInterval = 5;
  DateTime? _currentBottomStartTime;
  DateTime? _currentBottomPauseTime;
  Duration _bottomElapsedTime = Duration.zero;
  Duration _bottomDuration = const Duration(seconds: _defaultCarouselInterval);

  // 当前天气卡片轮播状态管理
  Timer? _currentWeatherCardTimer;
  bool _isCurrentWeatherCardPaused = false;
  CurrentWeatherPage _currentWeatherPage = CurrentWeatherPage.page1;
  static const int _defaultCurrentWeatherCardInterval = 8; // 当前天气卡片轮播间隔8秒
  DateTime? _currentWeatherCardStartTime;
  DateTime? _currentWeatherCardPauseTime;
  Duration _currentWeatherCardElapsedTime = Duration.zero;
  Duration _currentWeatherCardDuration =
      const Duration(seconds: _defaultCurrentWeatherCardInterval);

  // 缓存键
  static const String _forecastCacheKey = 'weather_forecast_cache';
  static const String _currentCacheKey = 'weather_current_cache';
  static const String _warningCacheKey = 'weather_warning_cache';
  static const String _lastUpdateKey = 'weather_last_update';

  // Getters
  WeatherData? get weatherForecastData => _weatherForecastData;
  CurrentWeatherDataModel? get currentWeatherData => _currentWeatherData;
  WeatherWarningModel? get weatherWarningData => _weatherWarningData;

  bool get isLoadingForecast => _isLoadingForecast;
  bool get isLoadingCurrent => _isLoadingCurrent;
  bool get isLoadingWarning => _isLoadingWarning;

  String? get forecastError => _forecastError;
  String? get currentError => _currentError;
  String? get warningError => _warningError;

  bool get hasForecastData => _weatherForecastData != null;
  bool get hasCurrentData => _currentWeatherData != null;
  bool get hasWarningData => _weatherWarningData != null;

  bool get isPeriodicUpdateActive => _isPeriodicUpdateActive;

  // 轮播相关getters
  bool get isBottomCarouselPaused => _isBottomCarouselPaused;
  CarouselState get currentState => _currentState;
  Duration get bottomDuration => _bottomDuration;
  DateTime? get currentBottomStartTime => _currentBottomStartTime;
  Duration get bottomElapsedTime => _bottomElapsedTime;
  bool get showWeather => _currentState == CarouselState.weather;
  bool get showQrcode => _currentState == CarouselState.qrcode;

  // 当前天气卡片轮播相关getters
  bool get isCurrentWeatherCardPaused => _isCurrentWeatherCardPaused;
  CurrentWeatherPage get currentWeatherPage => _currentWeatherPage;
  Duration get currentWeatherCardDuration => _currentWeatherCardDuration;
  DateTime? get currentWeatherCardStartTime => _currentWeatherCardStartTime;
  Duration get currentWeatherCardElapsedTime => _currentWeatherCardElapsedTime;
  bool get showCurrentWeatherPage1 =>
      _currentWeatherPage == CurrentWeatherPage.page1;
  bool get showCurrentWeatherPage2 =>
      _currentWeatherPage == CurrentWeatherPage.page2;

  /// 设置AppDataProvider引用
  void setAppDataProvider(AppDataProvider appDataProvider) {
    _appDataProvider = appDataProvider;
  }

  /// 检查并更新当前天气卡片轮播状态
  void _checkAndUpdateCurrentWeatherCardCarousel() {
    final hasWarnings = hasWarningData &&
        weatherWarningData != null &&
        weatherWarningData!.warnings.isNotEmpty;

    if (hasWarnings && _isCurrentWeatherCardPaused) {
      _isCurrentWeatherCardPaused = false;
      startCurrentWeatherCardTimer();
    } else if (!hasWarnings && !_isCurrentWeatherCardPaused) {
      _isCurrentWeatherCardPaused = true;
      _currentWeatherCardTimer?.cancel();
      _currentWeatherPage = CurrentWeatherPage.page1; // 重置到第一頁
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _updateTimer = null;
    _bottomTimer?.cancel();
    _bottomTimer = null;
    _debugTimer?.cancel();
    _debugTimer = null;
    _currentWeatherCardTimer?.cancel();
    _currentWeatherCardTimer = null;
    super.dispose();
  }

  ///2，从缓存加载天气数据
  Future<void> _loadWeatherDataFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 加载天气预报数据
      final forecastJson = prefs.getString(_forecastCacheKey);
      if (forecastJson != null) {
        try {
          final forecastData = json.decode(forecastJson);
          _weatherForecastData = WeatherData.fromJson(forecastData);
        } catch (e) {
          // 解析缓存的天气预报数据失败
          debugPrint('解析缓存的天气预报数据失败: $e');
        }
      }

      // 加载当前天气数据
      final currentJson = prefs.getString(_currentCacheKey);
      if (currentJson != null) {
        try {
          final currentData = json.decode(currentJson);
          _currentWeatherData = CurrentWeatherDataModel.fromJson(currentData);
        } catch (e) {
          // 解析缓存的当前天气数据失败
          debugPrint('解析缓存的当前天气数据失败: $e');
        }
      }

      // 加载天气警告数据
      final warningJson = prefs.getString(_warningCacheKey);
      if (warningJson != null) {
        try {
          final warningData = json.decode(warningJson);
          _weatherWarningData = WeatherWarningModel.fromJson(warningData);
        } catch (e) {
          // 解析缓存的天气警告数据失败
          debugPrint('解析缓存的天气警告数据失败: $e');
        }
      }

      notifyListeners();
    } catch (e) {
      debugPrint('从缓存加载天气数据失败: $e');
    }
  }

  ///3，保存天气数据到缓存
  Future<void> _saveWeatherDataToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 保存天气预报数据
      if (_weatherForecastData != null) {
        final forecastJson = json.encode(_weatherForecastData!.toJson());
        await prefs.setString(_forecastCacheKey, forecastJson);
      }

      // 保存当前天气数据
      if (_currentWeatherData != null) {
        final currentJson = json.encode(_currentWeatherData!.toJson());
        await prefs.setString(_currentCacheKey, currentJson);
      }

      // 保存天气警告数据
      if (_weatherWarningData != null) {
        final warningJson = json.encode(_weatherWarningData!.toJson());
        await prefs.setString(_warningCacheKey, warningJson);
      }

      // 保存最后更新时间
      await prefs.setString(_lastUpdateKey, DateTime.now().toIso8601String());
    } catch (e) {
      // 保存天气数据到缓存失败
    }
  }

  ///4，获取天气预报数据
  Future<void> fetchWeatherForecast() async {
    if (_isLoadingForecast) return;

    setState(() {
      _isLoadingForecast = true;
      _forecastError = null;
    });

    final stopwatch = Stopwatch()..start();
    try {
      final weatherData = await _weatherService.fetchWeatherData();

      if (weatherData != null) {
        _weatherForecastData = weatherData;
        _forecastError = null;
        await _saveWeatherDataToCache();
        stopwatch.stop();
      } else {
        if (_weatherForecastData != null) {
          stopwatch.stop();
        } else {
          _forecastError = '获取天气预报数据失败';
          stopwatch.stop();
        }
      }
    } catch (e) {
      _forecastError = '获取天气预报数据异常: $e';
      stopwatch.stop();
    } finally {
      setState(() {
        _isLoadingForecast = false;
      });
    }
  }

  ///5，获取当前天气数据
  Future<void> fetchCurrentWeather() async {
    if (_isLoadingCurrent) return;

    setState(() {
      _isLoadingCurrent = true;
      _currentError = null;
    });

    final stopwatch = Stopwatch()..start();
    try {
      final currentData = await _weatherService.fetchCurrentWeatherData();

      if (currentData != null) {
        _currentWeatherData = currentData;
        _currentError = null;
        await _saveWeatherDataToCache();
        stopwatch.stop();
      } else {
        if (_currentWeatherData != null) {
          stopwatch.stop();
        } else {
          _currentError = '获取当前天气数据失败';
          stopwatch.stop();
        }
      }
    } catch (e) {
      _currentError = '获取当前天气数据异常: $e';
      stopwatch.stop();
    } finally {
      setState(() {
        _isLoadingCurrent = false;
      });
    }
  }

  ///6，获取天气警告数据
  Future<void> fetchWeatherWarnings() async {
    if (_isLoadingWarning) return;

    setState(() {
      _isLoadingWarning = true;
      _warningError = null;
    });

    final stopwatch = Stopwatch()..start();
    try {
      final warningData = await _weatherService.fetchWeatherWarnings();

      if (warningData != null) {
        _weatherWarningData = warningData;
        _warningError = null;
        stopwatch.stop();
        await _saveWeatherDataToCache();
        _checkAndUpdateCurrentWeatherCardCarousel(); // 更新当前天气卡片轮播状态
      } else {
        if (_weatherWarningData != null) {
          stopwatch.stop();
        } else {
          _warningError = '获取天气警告数据失败';
          stopwatch.stop();
        }
      }
    } catch (e) {
      _warningError = '获取天气警告数据异常: $e';
      stopwatch.stop();
    } finally {
      setState(() {
        _isLoadingWarning = false;
      });
    }
  }

  ///7，获取所有天气数据
  Future<void> fetchAllWeatherData() async {
    final stopwatch = Stopwatch()..start();
    try {
      await fetchWeatherForecast();
      await fetchCurrentWeather();
      await fetchWeatherWarnings();
    } catch (e) {
      debugPrint('获取所有天气数据失败: $e');
      await _loadWeatherDataFromCache();
    }
    stopwatch.stop();
  }

  ///8，启动定时更新
  void startPeriodicUpdate({Duration interval = const Duration(hours: 2)}) {
    if (_isPeriodicUpdateActive) {
      return;
    }
    _isPeriodicUpdateActive = true;
    _updateTimer = Timer.periodic(interval, (timer) {
      fetchAllWeatherData();
    });

    notifyListeners();
  }

  ///9，停止定时更新
  void stopPeriodicUpdate() {
    if (!_isPeriodicUpdateActive) {
      return;
    }

    _updateTimer?.cancel();
    _updateTimer = null;
    _isPeriodicUpdateActive = false;

    notifyListeners();
  }

  ///10，清除缓存
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_forecastCacheKey);
      await prefs.remove(_currentCacheKey);
      await prefs.remove(_warningCacheKey);
      await prefs.remove(_lastUpdateKey);

      _weatherForecastData = null;
      _currentWeatherData = null;
      _weatherWarningData = null;

      notifyListeners();
    } catch (e) {
      // 清除天气数据缓存失败
    }
  }

  ///11，获取缓存状态信息
  Future<Map<String, dynamic>> getCacheStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastUpdate = prefs.getString(_lastUpdateKey);

      return {
        'hasForecastCache': _weatherForecastData != null,
        'hasCurrentCache': _currentWeatherData != null,
        'hasWarningCache': _weatherWarningData != null,
        'lastUpdate': lastUpdate,
        'isPeriodicUpdateActive': _isPeriodicUpdateActive,
        'forecastError': _forecastError,
        'currentError': _currentError,
        'warningError': _warningError,
      };
    } catch (e) {
      return {};
    }
  }

  // ========== 轮播逻辑管理 ==========

  ///12，初始化底部轮播
  void initializeBottomCarousel() {
    // _logger.i('🌤️ [初始化] 底部轮播初始化');
    _currentState = CarouselState.weather;
    _isBottomCarouselPaused = false;
    _bottomDuration = Duration(seconds: _getCarouselInterval());
    startBottomTimer();
  }

  ///13，初始化当前天气卡片轮播
  void initializeCurrentWeatherCardCarousel() {
    _currentWeatherPage = CurrentWeatherPage.page1;
    _isCurrentWeatherCardPaused = false;
    _currentWeatherCardDuration =
        Duration(seconds: _getCurrentWeatherCardInterval());

    // 检查是否有天气警告信息，只有在有警告时才启动轮播
    if (hasWarningData &&
        weatherWarningData != null &&
        weatherWarningData!.warnings.isNotEmpty) {
      startCurrentWeatherCardTimer();
    } else {
      _isCurrentWeatherCardPaused = true;
    }
  }

  ///14，启动底部轮播计时器
  void startBottomTimer() {
    //_logger.d('🌤️ 开始底部轮播计时器: paused=$_isBottomCarouselPaused');
    _bottomTimer?.cancel();

    if (_isBottomCarouselPaused) {
      // _logger.w('⚠️ 底部轮播计时器条件不满足: paused=$_isBottomCarouselPaused');
      return;
    }

    _currentBottomStartTime = DateTime.now();
    _bottomDuration = Duration(seconds: _getCarouselInterval());
    _bottomElapsedTime = Duration.zero;

    //.d('▶️ 启动底部轮播计时器: state=$_currentState, duration=$_bottomDuration');
    //_logger.i(
    //   '📝 记录底部轮播开始时间: $_currentBottomStartTime, 时长: ${_bottomDuration.inSeconds}秒');

    _bottomTimer = Timer(_bottomDuration, () {
      if (!_isBottomCarouselPaused) {
        // _logger.d('⏭️ 底部轮播计时器到期，切换到下一个状态');
        _switchToNextState();
      }
    });
  }

  ///15，切换到下一个轮播状态
  void _switchToNextState() {
    switch (_currentState) {
      case CarouselState.weather:
        _currentState = CarouselState.qrcode;

        break;
      case CarouselState.qrcode:
        _currentState = CarouselState.weather;

        break;
    }

    notifyListeners();
    startBottomTimer();
  }

  ///16，暂停底部轮播
  void pauseBottomCarousel() {
    _currentBottomPauseTime = DateTime.now();

    if (_currentBottomStartTime != null) {
      final rawElapsed =
          _currentBottomPauseTime!.difference(_currentBottomStartTime!);
      final totalElapsed = rawElapsed + _bottomElapsedTime;

      if (totalElapsed >= _bottomDuration) {
        _bottomElapsedTime = _bottomDuration;
        Duration.zero;
        //    _logger.i(
        //      '📊 [暂停] 底部轮播 - 已播放: ${_bottomElapsedTime.inSeconds}s/${_bottomDuration.inSeconds}s, 剩余: ${remaining.inSeconds}s (轮播已完成)');
      } else {
        _bottomElapsedTime = totalElapsed;
        //  _logger.i(
        //    '📊 [暂停] 底部轮播 - 已播放: ${_bottomElapsedTime.inSeconds}s/${_bottomDuration.inSeconds}s, 剩余: ${remaining.inSeconds}s');
      }
    }

    _isBottomCarouselPaused = true;
    _bottomTimer?.cancel();

    // 使用 addPostFrameCallback 延迟通知，避免 setState during build 错误
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (hasListeners) {
        notifyListeners();
      }
    });
  }

  ///17，恢复底部轮播
  void resumeBottomCarousel() {
    // _logger.i('▶️ 恢复底部轮播');

    _isBottomCarouselPaused = false;

    if (_currentBottomStartTime != null) {
      final remainingTime = _bottomDuration - _bottomElapsedTime;
      // _logger.i(
      //   '🔄 [恢复] 底部轮播 - 继续播放剩余时间：${remainingTime.inSeconds}s (已播放: ${_bottomElapsedTime.inSeconds}s)');

      if (remainingTime > Duration.zero) {
        _bottomTimer = Timer(remainingTime, () {
          if (!_isBottomCarouselPaused) {
            _switchToNextState();
          }
        });
      } else {
        _switchToNextState();
      }
    } else {
      startBottomTimer();
    }
  }

  ///18，启动调试定时器
  void startDebugTimer() {
    _debugTimer?.cancel();

    _debugTimer = Timer.periodic(const Duration(seconds: 1), (timer) {});
  }

  ///19，停止调试定时器
  void stopDebugTimer() {
    _debugTimer?.cancel();
  }

  ///23，设置状态并通知监听器
  void setState(VoidCallback fn) {
    fn();
    notifyListeners();
  }

  // ========== 当前天气卡片轮播逻辑管理 ==========

  ///24，启动当前天气卡片轮播计时器
  void startCurrentWeatherCardTimer() {
    _currentWeatherCardTimer?.cancel();

    if (_isCurrentWeatherCardPaused) {
      return;
    }

    _currentWeatherCardStartTime = DateTime.now();
    _currentWeatherCardDuration =
        Duration(seconds: _getCurrentWeatherCardInterval());
    _currentWeatherCardElapsedTime = Duration.zero;

    _currentWeatherCardTimer = Timer(_currentWeatherCardDuration, () {
      if (!_isCurrentWeatherCardPaused) {
        _switchToNextCurrentWeatherPage();
      }
    });
  }

  ///25，切换到下一个当前天气卡片頁面
  void _switchToNextCurrentWeatherPage() {
    switch (_currentWeatherPage) {
      case CurrentWeatherPage.page1:
        _currentWeatherPage = CurrentWeatherPage.page2;
        break;
      case CurrentWeatherPage.page2:
        _currentWeatherPage = CurrentWeatherPage.page1;
        break;
    }

    notifyListeners();
    startCurrentWeatherCardTimer();
  }

  ///26，暂停当前天气卡片轮播
  void pauseCurrentWeatherCardCarousel() {
    _currentWeatherCardPauseTime = DateTime.now();

    if (_currentWeatherCardStartTime != null) {
      final rawElapsed = _currentWeatherCardPauseTime!
          .difference(_currentWeatherCardStartTime!);
      final totalElapsed = rawElapsed + _currentWeatherCardElapsedTime;

      if (totalElapsed >= _currentWeatherCardDuration) {
        _currentWeatherCardElapsedTime = _currentWeatherCardDuration;
      } else {
        _currentWeatherCardElapsedTime = totalElapsed;
      }
    }

    _isCurrentWeatherCardPaused = true;
    _currentWeatherCardTimer?.cancel();

    // 使用 addPostFrameCallback 延迟通知，避免 setState during build 错误
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (hasListeners) {
        notifyListeners();
      }
    });
  }

  ///27，恢复当前天气卡片轮播
  void resumeCurrentWeatherCardCarousel() {
    _isCurrentWeatherCardPaused = false;

    if (_currentWeatherCardStartTime != null) {
      final remainingTime =
          _currentWeatherCardDuration - _currentWeatherCardElapsedTime;

      if (remainingTime > Duration.zero) {
        _currentWeatherCardTimer = Timer(remainingTime, () {
          if (!_isCurrentWeatherCardPaused) {
            _switchToNextCurrentWeatherPage();
          }
        });
      } else {
        _switchToNextCurrentWeatherPage();
      }
    } else {
      startCurrentWeatherCardTimer();
    }
  }

  ///28，暂停所有定时器（用于设置頁面）
  void pauseAllTimersForSettings() {
    _bottomTimer?.cancel();
    _debugTimer?.cancel();
    _currentWeatherCardTimer?.cancel();
    _isBottomCarouselPaused = true;
    _isCurrentWeatherCardPaused = true;
  }

  ///29，恢复所有定时器（从设置頁面返回）
  void resumeAllTimersFromSettings() {
    _isBottomCarouselPaused = false;
    _isCurrentWeatherCardPaused = false;
    startBottomTimer();
    startDebugTimer();
    startCurrentWeatherCardTimer();
  }

  ///30，更新轮播暂停状态（兼容性方法）
  void updateCarouselPauseState(bool isPaused) {
    if (isPaused) {
      pauseBottomCarousel();
      pauseCurrentWeatherCardCarousel();
    } else {
      resumeBottomCarousel();
      resumeCurrentWeatherCardCarousel();
    }
  }

  /// 獲取動態輪播間隔時間（秒）
  int _getCarouselInterval() {
    if (_appDataProvider?.deviceSettings != null) {
      final interval = _appDataProvider!.deviceSettings!.bottomCarouselDuration;
      return interval > 0 ? interval : _defaultCarouselInterval;
    }
    // 如果无法获取设置，使用默认值
    return _defaultCarouselInterval;
  }

  /// 获取动态当前天气卡片轮播间隔时间（秒）
  int _getCurrentWeatherCardInterval() {
    if (_appDataProvider?.deviceSettings != null) {
      // 如果设备设置中有当前天气卡片轮播间隔时间，使用它
      // 如果没有，可以使用底部轮播间隔时间作为参考
      final interval = _appDataProvider!.deviceSettings!.bottomCarouselDuration;
      return interval > 0 ? interval : _defaultCurrentWeatherCardInterval;
    }
    // 如果无法获取设置，使用默认值
    return _defaultCurrentWeatherCardInterval;
  }
}
