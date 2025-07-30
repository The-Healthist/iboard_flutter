import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:iboard_app/http/weather.dart';
import 'package:iboard_app/models/weather_forecast_model.dart';
import 'package:iboard_app/models/current_weather_model.dart';
import 'package:iboard_app/models/weather_warning_model.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WeatherProvider extends ChangeNotifier {
  final Logger _logger = Logger();
  final WeatherService _weatherService = WeatherService();

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

  // 添加初始化状态跟踪
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  WeatherProvider() {
    _logger.i('WeatherProvider初始化');
    _initializeProvider(); // 启动时初始化Provider
  }

  ///0，初始化Provider
  Future<void> _initializeProvider() async {
    await _loadWeatherDataFromCache(); // 从缓存加载数据
    _isInitialized = true;
    _logger.i('WeatherProvider初始化完成');
  }

  ///12，等待初始化完成
  Future<void> waitForInitialization() async {
    if (_isInitialized) return;

    // 等待初始化完成
    while (!_isInitialized) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  ///1，从缓存加载天气数据
  Future<void> _loadWeatherDataFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 加载天气预报数据
      final forecastJson = prefs.getString(_forecastCacheKey);
      if (forecastJson != null) {
        try {
          final forecastData = json.decode(forecastJson);
          _weatherForecastData = WeatherData.fromJson(forecastData);
          _logger.i('从缓存加载天气预报数据成功');
        } catch (e) {
          _logger.w('解析缓存的天气预报数据失败: $e');
        }
      }

      // 加载当前天气数据
      final currentJson = prefs.getString(_currentCacheKey);
      if (currentJson != null) {
        try {
          final currentData = json.decode(currentJson);
          _currentWeatherData = CurrentWeatherDataModel.fromJson(currentData);
          _logger.i('从缓存加载当前天气数据成功');
        } catch (e) {
          _logger.w('解析缓存的当前天气数据失败: $e');
        }
      }

      // 加载天气警告数据
      final warningJson = prefs.getString(_warningCacheKey);
      if (warningJson != null) {
        try {
          final warningData = json.decode(warningJson);
          _weatherWarningData = WeatherWarningModel.fromJson(warningData);
          _logger.i('从缓存加载天气警告数据成功');
        } catch (e) {
          _logger.w('解析缓存的天气警告数据失败: $e');
        }
      }

      notifyListeners();
    } catch (e) {
      _logger.e('从缓存加载天气数据失败', error: e);
    }
  }

  ///2，保存天气数据到缓存
  Future<void> _saveWeatherDataToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 保存天气预报数据
      if (_weatherForecastData != null) {
        final forecastJson = json.encode(_weatherForecastData!.toJson());
        await prefs.setString(_forecastCacheKey, forecastJson);
        _logger.i('天气预报数据已缓存');
      }

      // 保存当前天气数据
      if (_currentWeatherData != null) {
        final currentJson = json.encode(_currentWeatherData!.toJson());
        await prefs.setString(_currentCacheKey, currentJson);
        _logger.i('当前天气数据已缓存');
      }

      // 保存天气警告数据
      if (_weatherWarningData != null) {
        final warningJson = json.encode(_weatherWarningData!.toJson());
        await prefs.setString(_warningCacheKey, warningJson);
        _logger.i('天气警告数据已缓存');
      }

      // 保存最后更新时间
      await prefs.setString(_lastUpdateKey, DateTime.now().toIso8601String());

      _logger.i('天气数据已保存到缓存');
    } catch (e) {
      _logger.e('保存天气数据到缓存失败', error: e);
    }
  }

  ///3，获取天气预报数据
  Future<void> fetchWeatherForecast() async {
    if (_isLoadingForecast) return;

    setState(() {
      _isLoadingForecast = true;
      _forecastError = null;
    });

    try {
      _logger.i('开始获取天气预报数据...');
      final weatherData = await _weatherService.fetchWeatherData();

      if (weatherData != null) {
        _weatherForecastData = weatherData;
        await _saveWeatherDataToCache(); // 成功时保存到缓存
        _logger.i('天气预报数据获取成功并已缓存');
      } else {
        _forecastError = '获取天气预报数据失败';
        _logger.w('天气预报数据获取失败，保持原有缓存数据');
      }
    } catch (e) {
      _forecastError = '获取天气预报数据异常: $e';
      _logger.e('获取天气预报数据异常', error: e);
    } finally {
      setState(() {
        _isLoadingForecast = false;
      });
    }
  }

  ///4，获取当前天气数据
  Future<void> fetchCurrentWeather() async {
    if (_isLoadingCurrent) return;

    setState(() {
      _isLoadingCurrent = true;
      _currentError = null;
    });

    try {
      _logger.i('开始获取当前天气数据...');
      final currentData = await _weatherService.fetchCurrentWeatherData();

      if (currentData != null) {
        _currentWeatherData = currentData;
        await _saveWeatherDataToCache(); // 成功时保存到缓存
        _logger.i('当前天气数据获取成功并已缓存');
      } else {
        _currentError = '获取当前天气数据失败';
        _logger.w('当前天气数据获取失败，保持原有缓存数据');
      }
    } catch (e) {
      _currentError = '获取当前天气数据异常: $e';
      _logger.e('获取当前天气数据异常', error: e);
    } finally {
      setState(() {
        _isLoadingCurrent = false;
      });
    }
  }

  ///5，获取天气警告数据
  Future<void> fetchWeatherWarnings() async {
    if (_isLoadingWarning) return;

    setState(() {
      _isLoadingWarning = true;
      _warningError = null;
    });

    try {
      _logger.i('开始获取天气警告数据...');
      final warningData = await _weatherService.fetchWeatherWarnings();

      if (warningData != null) {
        _weatherWarningData = warningData;
        await _saveWeatherDataToCache(); // 成功时保存到缓存
        _logger.i('天气警告数据获取成功并已缓存');
      } else {
        _warningError = '获取天气警告数据失败';
        _logger.w('天气警告数据获取失败，保持原有缓存数据');
      }
    } catch (e) {
      _warningError = '获取天气警告数据异常: $e';
      _logger.e('获取天气警告数据异常', error: e);
    } finally {
      setState(() {
        _isLoadingWarning = false;
      });
    }
  }

  ///6，获取所有天气数据
  Future<void> fetchAllWeatherData() async {
    _logger.i('开始获取所有天气数据...');

    // 并行获取所有天气数据
    await Future.wait([
      fetchWeatherForecast(),
      fetchCurrentWeather(),
      fetchWeatherWarnings(),
    ]);

    _logger.i('所有天气数据获取完成');
  }

  ///7，启动定时更新
  void startPeriodicUpdate({Duration interval = const Duration(hours: 2)}) {
    if (_isPeriodicUpdateActive) {
      _logger.w('定时更新已在运行中');
      return;
    }

    _logger.i('启动天气数据定时更新，间隔: ${interval.inHours}小时');
    _isPeriodicUpdateActive = true;

    _updateTimer = Timer.periodic(interval, (timer) {
      _logger.i('定时更新天气数据...');
      fetchAllWeatherData();
    });

    notifyListeners();
  }

  ///8，停止定时更新
  void stopPeriodicUpdate() {
    if (!_isPeriodicUpdateActive) {
      _logger.w('定时更新未在运行');
      return;
    }

    _logger.i('停止天气数据定时更新');
    _updateTimer?.cancel();
    _updateTimer = null;
    _isPeriodicUpdateActive = false;

    notifyListeners();
  }

  ///9，清除缓存
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

      _logger.i('天气数据缓存已清除');
      notifyListeners();
    } catch (e) {
      _logger.e('清除天气数据缓存失败', error: e);
    }
  }

  ///10，获取缓存状态信息
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
      _logger.e('获取缓存状态失败', error: e);
      return {};
    }
  }

  ///11，设置状态并通知监听器
  void setState(VoidCallback fn) {
    fn();
    notifyListeners();
  }
}
