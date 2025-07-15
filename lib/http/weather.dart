import 'dart:convert';
import 'dart:developer';
import 'package:http/http.dart' as http;
import 'package:iboard_app/models/weather_forecast_model.dart';
import 'package:iboard_app/models/current_weather_model.dart';
import 'package:logger/logger.dart';

class WeatherService {
  final String _weatherApiUrl =
      'https://data.weather.gov.hk/weatherAPI/opendata/weather.php?dataType=fnd&lang=tc';
  final String _currentWeatherApiUrl =
      'https://data.weather.gov.hk/weatherAPI/opendata/weather.php?dataType=rhrread&lang=tc';
  final Logger _logger = Logger();

  Future<WeatherData?> fetchWeatherData() async {
    try {
      final response = await http.get(Uri.parse(_weatherApiUrl));
      if (response.statusCode == 200) {
        // The API returns JSON that is not UTF-8 encoded by default in headers,
        // so we need to decode it explicitly with utf8.decode
        final decodedBody = utf8.decode(response.bodyBytes);
        final jsonData = json.decode(decodedBody) as Map<String, dynamic>;
        return WeatherData.fromJson(jsonData);
      } else {
        _logger.e(
            'Failed to load weather forecast data. Status code: ${response.statusCode}');
        return null;
      }
    } catch (e, stackTrace) {
      _logger.e('Error fetching weather forecast data',
          error: e, stackTrace: stackTrace);
      return null;
    }
  }

  Future<CurrentWeatherDataModel?> fetchCurrentWeatherData() async {
    try {
      final response = await http.get(Uri.parse(_currentWeatherApiUrl));
      if (response.statusCode == 200) {
        final decodedBody = utf8.decode(response.bodyBytes);
        final jsonData = json.decode(decodedBody) as Map<String, dynamic>;
        return CurrentWeatherDataModel.fromJson(jsonData);
      } else {
        _logger.e(
            'Failed to load current weather data. Status code: ${response.statusCode}');
        return null;
      }
    } catch (e, stackTrace) {
      _logger.e('Error fetching current weather data',
          error: e, stackTrace: stackTrace);
      return null;
    }
  }
}
