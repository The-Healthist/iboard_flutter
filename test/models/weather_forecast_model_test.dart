import 'package:flutter_test/flutter_test.dart';
import 'package:iboard_app/models/weather_forecast_model.dart';

void main() {
  group('WeatherData.fromJson', () {
    test('parses flexible HKO forecast payloads safely', () {
      final weather = WeatherData.fromJson({
        'generalSituation': 123,
        'updateTime': 456,
        'weatherForecast': [
          {
            'forecastDate': 20260605,
            'week': 5,
            'forecastWind': null,
            'forecastWeather': 'Cloudy',
            'forecastMaxtemp': {'value': '31', 'unit': 'C'},
            'forecastMintemp': {'value': 26.9, 'unit': 1},
            'forecastMaxrh': {'value': '90', 'unit': 'percent'},
            'forecastMinrh': 'bad',
            'ForecastIcon': '62',
            'PSR': 3,
          },
          'bad item',
        ],
        'seaTemp': {
          'place': 1,
          'value': '27',
          'unit': 'C',
          'recordTime': 789,
        },
        'soilTemp': [
          {
            'place': 'Happy Valley',
            'value': '28.5',
            'unit': 'C',
            'recordTime': 789,
            'depth': {'unit': 'm', 'value': '0.5'},
          },
          null,
        ],
      });

      expect(weather.generalSituation, '123');
      expect(weather.updateTime, '456');
      expect(weather.weatherForecast, hasLength(1));

      final forecast = weather.weatherForecast.single;
      expect(forecast.forecastDate, '20260605');
      expect(forecast.week, '5');
      expect(forecast.forecastWind, '');
      expect(forecast.forecastMaxtemp.value, 31);
      expect(forecast.forecastMintemp.value, 26);
      expect(forecast.forecastMintemp.unit, '1');
      expect(forecast.forecastMaxrh!.value, 90);
      expect(forecast.forecastMinrh!.value, 0);
      expect(forecast.forecastIcon, 62);
      expect(forecast.psr, '3');

      expect(weather.seaTemp!.place, '1');
      expect(weather.seaTemp!.value, 27);
      expect(weather.seaTemp!.recordTime, '789');
      expect(weather.soilTemp, hasLength(1));
      expect(weather.soilTemp!.single.value, 28.5);
      expect(weather.soilTemp!.single.depth.value, 0.5);
    });

    test(
        'uses empty forecast list and fallback nested values on malformed data',
        () {
      final weather = WeatherData.fromJson({
        'weatherForecast': 'bad',
        'seaTemp': 'bad',
        'soilTemp': 'bad',
      });

      expect(weather.generalSituation, '');
      expect(weather.updateTime, '');
      expect(weather.weatherForecast, isEmpty);
      expect(weather.seaTemp!.place, '');
      expect(weather.seaTemp!.value, 0);
      expect(weather.soilTemp, isNull);
    });
  });
}
