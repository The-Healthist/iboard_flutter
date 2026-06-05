import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iboard_app/http/weather.dart';

void main() {
  group('WeatherService object responses', () {
    test('parses successful forecast map responses', () async {
      final server = await _jsonServer({
        'generalSituation': 'Cloudy',
        'updateTime': '2026-06-05T00:00:00Z',
        'weatherForecast': [
          {
            'forecastDate': '20260605',
            'week': 'Friday',
            'forecastWeather': 'Cloudy',
            'forecastMaxtemp': {'value': 31, 'unit': 'C'},
            'forecastMintemp': {'value': 26, 'unit': 'C'},
            'ForecastIcon': 62,
          },
        ],
      });

      try {
        final service = WeatherService(weatherApiUrl: _serverUrl(server));

        final data = await service.fetchWeatherData();

        expect(data, isNotNull);
        expect(data!.generalSituation, 'Cloudy');
        expect(data.weatherForecast, hasLength(1));
      } finally {
        await server.close(force: true);
      }
    });

    test('uses forecast model defaults for non-map successful JSON', () async {
      final server = await _jsonServer(['unexpected']);

      try {
        final service = WeatherService(weatherApiUrl: _serverUrl(server));

        final data = await service.fetchWeatherData();

        expect(data, isNotNull);
        expect(data!.generalSituation, isEmpty);
        expect(data.weatherForecast, isEmpty);
      } finally {
        await server.close(force: true);
      }
    });

    test('uses current weather defaults for non-map successful JSON', () async {
      final server = await _jsonServer('unexpected');

      try {
        final service =
            WeatherService(currentWeatherApiUrl: _serverUrl(server));

        final data = await service.fetchCurrentWeatherData();

        expect(data, isNotNull);
        expect(data!.updateTime, isEmpty);
        expect(data.warningMessage, isNull);
      } finally {
        await server.close(force: true);
      }
    });

    test('uses warning defaults for non-map successful JSON', () async {
      final server = await _jsonServer(123);

      try {
        final service =
            WeatherService(currentWeatherWarnUrl: _serverUrl(server));

        final data = await service.fetchWeatherWarnings();

        expect(data, isNotNull);
        expect(data!.warnings, isEmpty);
      } finally {
        await server.close(force: true);
      }
    });
  });
}

Future<HttpServer> _jsonServer(Object? payload) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(payload))
      ..close();
  });
  return server;
}

String _serverUrl(HttpServer server) => 'http://127.0.0.1:${server.port}';
