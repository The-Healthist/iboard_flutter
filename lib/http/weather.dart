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

  // 天氣API超時配置
  static const Duration _weatherTimeout = Duration(seconds: 15); // 15秒超時

  Future<WeatherData?> fetchWeatherData() async {
    final stopwatch = Stopwatch()..start();
    try {
      // _logger.i(' [API調用] 開始獲取天氣預報數據... - URL: $_weatherApiUrl');
      final response = await http.get(Uri.parse(_weatherApiUrl)).timeout(
        _weatherTimeout,
        onTimeout: () {
          throw Exception('天氣預報API請求超時 (${_weatherTimeout.inSeconds}秒)');
        },
      );

      stopwatch.stop();
      if (response.statusCode == 200) {
        // The API returns JSON that is not UTF-8 encoded by default in headers,
        // so we need to decode it explicitly with utf8.decode
        final decodedBody = utf8.decode(response.bodyBytes);
        final jsonData = json.decode(decodedBody) as Map<String, dynamic>;
        // _logger.i(
        //     ' [API成功] 天氣預報數據獲取成功，響應時間: ${stopwatch.elapsedMilliseconds}ms，數據大小: ${response.bodyBytes.length} bytes');
        return WeatherData.fromJson(jsonData);
      } else {
        // _logger.e(
        //     ' [API失敗] 天氣預報數據獲取失敗. Status code: ${response.statusCode}，響應時間: ${stopwatch.elapsedMilliseconds}ms');
        return null;
      }
    } catch (e) {
      stopwatch.stop();
      // 詳細的錯誤處理
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Connection timed out') ||
          e.toString().contains('ClientException')) {
        // _logger.w(
        //     ' [網絡錯誤] 天氣預報數據網絡連接失敗，響應時間: ${stopwatch.elapsedMilliseconds}ms: $e');
      } else if (e.toString().contains('TimeoutException') ||
          e.toString().contains('請求超時')) {
        // _logger.w(
        //     ' [超時錯誤] 天氣預報數據請求超時，響應時間: ${stopwatch.elapsedMilliseconds}ms: $e');
      } else {
        // _logger.e(
        //     ' [未知錯誤] 天氣預報數據獲取異常，響應時間: ${stopwatch.elapsedMilliseconds}ms',
        //     error: e,
        //     stackTrace: stackTrace);
      }
      return null;
    }
  }

  Future<CurrentWeatherDataModel?> fetchCurrentWeatherData() async {
    final stopwatch = Stopwatch()..start();
    try {
      // _logger.i(' [API調用] 開始獲取當前天氣數據... - URL: $_currentWeatherApiUrl');
      final response = await http.get(Uri.parse(_currentWeatherApiUrl)).timeout(
        _weatherTimeout,
        onTimeout: () {
          throw Exception('當前天氣API請求超時 (${_weatherTimeout.inSeconds}秒)');
        },
      );

      stopwatch.stop();
      if (response.statusCode == 200) {
        final decodedBody = utf8.decode(response.bodyBytes);
        final jsonData = json.decode(decodedBody) as Map<String, dynamic>;
        // _logger.i(
        //     ' [API成功] 當前天氣數據獲取成功，響應時間: ${stopwatch.elapsedMilliseconds}ms，數據大小: ${response.bodyBytes.length} bytes');

        // 詳細日誌記錄空字段情況，幫助調試
        // final emptyFields = <String>[];
        // if (jsonData['uvindex'] == "") emptyFields.add('uvindex');
        // if (jsonData['warningMessage'] == "") emptyFields.add('warningMessage');
        // if (jsonData['tcmessage'] == "") emptyFields.add('tcmessage');
        // if (jsonData['mintempFrom00To09'] == "") emptyFields.add('mintempFrom00To09');
        // if (jsonData['rainfallFrom00To12'] == "") emptyFields.add('rainfallFrom00To12');
        // if (jsonData['rainfallLastMonth'] == "") emptyFields.add('rainfallLastMonth');
        // if (jsonData['rainfallJanuaryToLastMonth'] == "") emptyFields.add('rainfallJanuaryToLastMonth');
        // if (emptyFields.isNotEmpty) {
        //   _logger.d(' [空字段] 發現空字符串字段: ${emptyFields.join(', ')}');
        // }

        try {
          return CurrentWeatherDataModel.fromJson(jsonData);
        } catch (parseError) {
          // _logger.e(' [解析錯誤] 當前天氣數據解析失敗', error: parseError);
          // _logger.d(' [原始數據] 解析失敗的數據: $jsonData');
          return null;
        }
      } else {
        // _logger.e(
        //     ' [API失敗] 當前天氣數據獲取失敗. Status code: ${response.statusCode}，響應時間: ${stopwatch.elapsedMilliseconds}ms');
        return null;
      }
    } catch (e) {
      stopwatch.stop();
      // 詳細的錯誤處理
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Connection timed out') ||
          e.toString().contains('ClientException')) {
        // _logger.w(
        //     ' [網絡錯誤] 當前天氣數據網絡連接失敗，響應時間: ${stopwatch.elapsedMilliseconds}ms: $e');
      } else if (e.toString().contains('TimeoutException') ||
          e.toString().contains('請求超時')) {
        // _logger.w(
        //     ' [超時錯誤] 當前天氣數據請求超時，響應時間: ${stopwatch.elapsedMilliseconds}ms: $e');
      } else {
        // _logger.e(
        //     ' [未知錯誤] 當前天氣數據獲取異常，響應時間: ${stopwatch.elapsedMilliseconds}ms',
        //     error: e,
        //     stackTrace: stackTrace);
      }
      return null;
    }
  }

  Future<WeatherWarningModel?> fetchWeatherWarnings() async {
    final stopwatch = Stopwatch()..start();
    try {
      // _logger.i(' [API調用] 開始獲取天氣警告數據... - URL: $_currentWeatherWarnUrl');
      final response =
          await http.get(Uri.parse(_currentWeatherWarnUrl)).timeout(
        _weatherTimeout,
        onTimeout: () {
          throw Exception('天氣警告API請求超時 (${_weatherTimeout.inSeconds}秒)');
        },
      );

      stopwatch.stop();
      if (response.statusCode == 200) {
        final decodedBody = utf8.decode(response.bodyBytes);
        final jsonData = json.decode(decodedBody) as Map<String, dynamic>;
        // _logger.i(
        //     ' [API成功] 天氣警告API響應成功，響應時間: ${stopwatch.elapsedMilliseconds}ms，數據鍵: ${jsonData.keys.join(', ')}');
        // _logger.d(' [原始數據] 天氣警告原始數據: $jsonData');

        // 詳細記錄每個警告的actionCode
        // jsonData.forEach((key, value) {
        //   if (value is Map<String, dynamic>) {
        //     final actionCode = value['actionCode'] ?? 'UNKNOWN';
        //     final name = value['name'] ?? key;
        //     // _logger.d(' [警告詳情] 警告 $key ($name): actionCode=$actionCode');
        //   }
        // });

        final warningModel = WeatherWarningModel.fromJson(jsonData);
        // _logger.i(' [解析成功] 天氣警告解析完成: ${warningModel.warnings.length}個警告');
        return warningModel;
      } else {
        // _logger.e(
        //     ' [API失敗] 天氣警告數據獲取失敗. Status code: ${response.statusCode}，響應時間: ${stopwatch.elapsedMilliseconds}ms');
        return null;
      }
    } catch (e) {
      stopwatch.stop();
      // 詳細的錯誤處理
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Connection timed out') ||
          e.toString().contains('ClientException')) {
        // _logger.w(
        //     ' [網絡錯誤] 天氣警告數據網絡連接失敗，響應時間: ${stopwatch.elapsedMilliseconds}ms: $e');
      } else if (e.toString().contains('TimeoutException') ||
          e.toString().contains('請求超時')) {
        // _logger.w(
        //     ' [超時錯誤] 天氣警告數據請求超時，響應時間: ${stopwatch.elapsedMilliseconds}ms: $e');
      } else {
        // _logger.e(
        //     ' [未知錯誤] 天氣警告數據獲取異常，響應時間: ${stopwatch.elapsedMilliseconds}ms',
        //     error: e,
        //     stackTrace: stackTrace);
      }
      return null;
    }
  }
}
