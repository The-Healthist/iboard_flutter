import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:iboard_app/models/weather_forecast_model.dart';
import 'package:iboard_app/models/current_weather_model.dart';
import 'package:iboard_app/models/weather_warning_model.dart';
import 'package:logger/logger.dart';

class WeatherService {
  final String _weatherApiUrl =
      'https://data.weather.gov.hk/weatherAPI/opendata/weather.php?dataType=fnd&lang=tc';
  final String _currentWeatherApiUrl =
      'https://data.weather.gov.hk/weatherAPI/opendata/weather.php?dataType=rhrread&lang=tc';
  final String _currentWeatherWarnUrl =
      'https://data.weather.gov.hk/weatherAPI/opendata/weather.php?dataType=warnsum&lang=tc';
  final Logger _logger = Logger();

  // 天气API超时配置
  static const Duration _weatherTimeout = Duration(seconds: 15); // 15秒超时

  Future<WeatherData?> fetchWeatherData() async {
    try {
      _logger.i('开始获取天气预报数据...');
      final response = await http.get(Uri.parse(_weatherApiUrl)).timeout(
        _weatherTimeout,
        onTimeout: () {
          throw Exception('天气预报API请求超时 (${_weatherTimeout.inSeconds}秒)');
        },
      );

      if (response.statusCode == 200) {
        // The API returns JSON that is not UTF-8 encoded by default in headers,
        // so we need to decode it explicitly with utf8.decode
        final decodedBody = utf8.decode(response.bodyBytes);
        final jsonData = json.decode(decodedBody) as Map<String, dynamic>;
        _logger.i('天气预报数据获取成功');
        return WeatherData.fromJson(jsonData);
      } else {
        _logger.e(
            'Failed to load weather forecast data. Status code: ${response.statusCode}');
        return null;
      }
    } catch (e, stackTrace) {
      // 详细的错误处理
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Connection timed out') ||
          e.toString().contains('ClientException')) {
        _logger.w('天气预报数据网络连接失败，将显示默认UI: $e');
      } else if (e.toString().contains('TimeoutException') ||
          e.toString().contains('请求超时')) {
        _logger.w('天气预报数据请求超时，将显示默认UI: $e');
      } else {
        _logger.e('Error fetching weather forecast data',
            error: e, stackTrace: stackTrace);
      }
      return null;
    }
  }

  Future<CurrentWeatherDataModel?> fetchCurrentWeatherData() async {
    try {
      _logger.i('开始获取当前天气数据...');
      final response = await http.get(Uri.parse(_currentWeatherApiUrl)).timeout(
        _weatherTimeout,
        onTimeout: () {
          throw Exception('当前天气API请求超时 (${_weatherTimeout.inSeconds}秒)');
        },
      );

      if (response.statusCode == 200) {
        final decodedBody = utf8.decode(response.bodyBytes);
        final jsonData = json.decode(decodedBody) as Map<String, dynamic>;
        _logger.i('当前天气数据获取成功');
        return CurrentWeatherDataModel.fromJson(jsonData);
      } else {
        _logger.e(
            'Failed to load current weather data. Status code: ${response.statusCode}');
        return null;
      }
    } catch (e, stackTrace) {
      // 详细的错误处理
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Connection timed out') ||
          e.toString().contains('ClientException')) {
        _logger.w('当前天气数据网络连接失败，将显示默认UI: $e');
      } else if (e.toString().contains('TimeoutException') ||
          e.toString().contains('请求超时')) {
        _logger.w('当前天气数据请求超时，将显示默认UI: $e');
      } else {
        _logger.e('Error fetching current weather data',
            error: e, stackTrace: stackTrace);
      }
      return null;
    }
  }

  Future<WeatherWarningModel?> fetchWeatherWarnings() async {
    try {
      _logger.i('开始获取天气警告数据...');
      final response =
          await http.get(Uri.parse(_currentWeatherWarnUrl)).timeout(
        _weatherTimeout,
        onTimeout: () {
          throw Exception('天气警告API请求超时 (${_weatherTimeout.inSeconds}秒)');
        },
      );

      if (response.statusCode == 200) {
        final decodedBody = utf8.decode(response.bodyBytes);
        final jsonData = json.decode(decodedBody) as Map<String, dynamic>;
        _logger.i('天气警告数据获取成功');
        return WeatherWarningModel.fromJson(jsonData);
      } else {
        _logger.e(
            'Failed to load weather warnings. Status code: ${response.statusCode}');
        return null;
      }
    } catch (e, stackTrace) {
      // 详细的错误处理
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Connection timed out') ||
          e.toString().contains('ClientException')) {
        _logger.w('天气警告数据网络连接失败: $e');
      } else if (e.toString().contains('TimeoutException') ||
          e.toString().contains('请求超时')) {
        _logger.w('天气警告数据请求超时: $e');
      } else {
        _logger.e('Error fetching weather warnings',
            error: e, stackTrace: stackTrace);
      }
      return null;
    }
  }
}
