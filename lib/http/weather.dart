import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:iboard_app/models/weather_forecast_model.dart';
import 'package:iboard_app/models/current_weather_model.dart';
import 'package:iboard_app/models/weather_warning_model.dart';
// import 'package:logger/logger.dart';

class WeatherService {
  final String _weatherApiUrl =
      'https://data.weather.gov.hk/weatherAPI/opendata/weather.php?dataType=fnd&lang=tc';
  final String _currentWeatherApiUrl =
      'https://data.weather.gov.hk/weatherAPI/opendata/weather.php?dataType=rhrread&lang=tc';
  final String _currentWeatherWarnUrl =
      'https://data.weather.gov.hk/weatherAPI/opendata/weather.php?dataType=warnsum&lang=tc';
  // final Logger _logger = Logger();

  // 天气API超时配置
  static const Duration _weatherTimeout = Duration(seconds: 15); // 15秒超时

  Future<WeatherData?> fetchWeatherData() async {
    final stopwatch = Stopwatch()..start();
    try {
      // _logger.i('🌤️ [API调用] 开始获取天气预报数据... - URL: $_weatherApiUrl');
      final response = await http.get(Uri.parse(_weatherApiUrl)).timeout(
        _weatherTimeout,
        onTimeout: () {
          throw Exception('天气预报API请求超时 (${_weatherTimeout.inSeconds}秒)');
        },
      );

      stopwatch.stop();
      if (response.statusCode == 200) {
        // The API returns JSON that is not UTF-8 encoded by default in headers,
        // so we need to decode it explicitly with utf8.decode
        final decodedBody = utf8.decode(response.bodyBytes);
        final jsonData = json.decode(decodedBody) as Map<String, dynamic>;
        // _logger.i(
        //     '✅ [API成功] 天气预报数据获取成功，响应时间: ${stopwatch.elapsedMilliseconds}ms，数据大小: ${response.bodyBytes.length} bytes');
        return WeatherData.fromJson(jsonData);
      } else {
        // _logger.e(
        //     '❌ [API失败] 天气预报数据获取失败. Status code: ${response.statusCode}，响应时间: ${stopwatch.elapsedMilliseconds}ms');
        return null;
      }
    } catch (e) {
      stopwatch.stop();
      // 详细的错误处理
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Connection timed out') ||
          e.toString().contains('ClientException')) {
        // _logger.w(
        //     '🌐 [网络错误] 天气预报数据网络连接失败，响应时间: ${stopwatch.elapsedMilliseconds}ms: $e');
      } else if (e.toString().contains('TimeoutException') ||
          e.toString().contains('请求超时')) {
        // _logger.w(
        //     '⏰ [超时错误] 天气预报数据请求超时，响应时间: ${stopwatch.elapsedMilliseconds}ms: $e');
      } else {
        // _logger.e(
        //     '❌ [未知错误] 天气预报数据获取异常，响应时间: ${stopwatch.elapsedMilliseconds}ms',
        //     error: e,
        //     stackTrace: stackTrace);
      }
      return null;
    }
  }

  Future<CurrentWeatherDataModel?> fetchCurrentWeatherData() async {
    final stopwatch = Stopwatch()..start();
    try {
      // _logger.i('🌡️ [API调用] 开始获取当前天气数据... - URL: $_currentWeatherApiUrl');
      final response = await http.get(Uri.parse(_currentWeatherApiUrl)).timeout(
        _weatherTimeout,
        onTimeout: () {
          throw Exception('当前天气API请求超时 (${_weatherTimeout.inSeconds}秒)');
        },
      );

      stopwatch.stop();
      if (response.statusCode == 200) {
        final decodedBody = utf8.decode(response.bodyBytes);
        final jsonData = json.decode(decodedBody) as Map<String, dynamic>;
        // _logger.i(
        //     '✅ [API成功] 当前天气数据获取成功，响应时间: ${stopwatch.elapsedMilliseconds}ms，数据大小: ${response.bodyBytes.length} bytes');
        return CurrentWeatherDataModel.fromJson(jsonData);
      } else {
        // _logger.e(
        //     '❌ [API失败] 当前天气数据获取失败. Status code: ${response.statusCode}，响应时间: ${stopwatch.elapsedMilliseconds}ms');
        return null;
      }
    } catch (e) {
      stopwatch.stop();
      // 详细的错误处理
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Connection timed out') ||
          e.toString().contains('ClientException')) {
        // _logger.w(
        //     '🌐 [网络错误] 当前天气数据网络连接失败，响应时间: ${stopwatch.elapsedMilliseconds}ms: $e');
      } else if (e.toString().contains('TimeoutException') ||
          e.toString().contains('请求超时')) {
        // _logger.w(
        //     '⏰ [超时错误] 当前天气数据请求超时，响应时间: ${stopwatch.elapsedMilliseconds}ms: $e');
      } else {
        // _logger.e(
        //     '❌ [未知错误] 当前天气数据获取异常，响应时间: ${stopwatch.elapsedMilliseconds}ms',
        //     error: e,
        //     stackTrace: stackTrace);
      }
      return null;
    }
  }

  Future<WeatherWarningModel?> fetchWeatherWarnings() async {
    final stopwatch = Stopwatch()..start();
    try {
      // _logger.i('⚠️ [API调用] 开始获取天气警告数据... - URL: $_currentWeatherWarnUrl');
      final response =
          await http.get(Uri.parse(_currentWeatherWarnUrl)).timeout(
        _weatherTimeout,
        onTimeout: () {
          throw Exception('天气警告API请求超时 (${_weatherTimeout.inSeconds}秒)');
        },
      );

      stopwatch.stop();
      if (response.statusCode == 200) {
        final decodedBody = utf8.decode(response.bodyBytes);
        final jsonData = json.decode(decodedBody) as Map<String, dynamic>;
        // _logger.i(
        //     '✅ [API成功] 天气警告API响应成功，响应时间: ${stopwatch.elapsedMilliseconds}ms，数据键: ${jsonData.keys.join(', ')}');
        // _logger.d('📋 [原始数据] 天气警告原始数据: $jsonData');

        // 详细记录每个警告的actionCode
        // jsonData.forEach((key, value) {
        //   if (value is Map<String, dynamic>) {
        //     final actionCode = value['actionCode'] ?? 'UNKNOWN';
        //     final name = value['name'] ?? key;
        //     // _logger.d('🌦️ [警告详情] 警告 $key ($name): actionCode=$actionCode');
        //   }
        // });

        final warningModel = WeatherWarningModel.fromJson(jsonData);
        // _logger.i('✅ [解析成功] 天气警告解析完成: ${warningModel.warnings.length}个警告');
        return warningModel;
      } else {
        // _logger.e(
        //     '❌ [API失败] 天气警告数据获取失败. Status code: ${response.statusCode}，响应时间: ${stopwatch.elapsedMilliseconds}ms');
        return null;
      }
    } catch (e) {
      stopwatch.stop();
      // 详细的错误处理
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Connection timed out') ||
          e.toString().contains('ClientException')) {
        // _logger.w(
        //     '🌐 [网络错误] 天气警告数据网络连接失败，响应时间: ${stopwatch.elapsedMilliseconds}ms: $e');
      } else if (e.toString().contains('TimeoutException') ||
          e.toString().contains('请求超时')) {
        // _logger.w(
        //     '⏰ [超时错误] 天气警告数据请求超时，响应时间: ${stopwatch.elapsedMilliseconds}ms: $e');
      } else {
        // _logger.e(
        //     '❌ [未知错误] 天气警告数据获取异常，响应时间: ${stopwatch.elapsedMilliseconds}ms',
        //     error: e,
        //     stackTrace: stackTrace);
      }
      return null;
    }
  }
}
