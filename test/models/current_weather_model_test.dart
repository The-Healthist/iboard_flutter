import 'package:flutter_test/flutter_test.dart';
import 'package:iboard_app/models/current_weather_model.dart';

void main() {
  group('CurrentWeatherDataModel.fromJson', () {
    test('parses flexible HKO current weather payloads safely', () {
      final weather = CurrentWeatherDataModel.fromJson({
        'updateTime': 123,
        'warningMessage': ['Amber rainstorm', 7, null],
        'icon': ['50', 62.9, 'bad'],
        'temperature': {
          'recordTime': 123,
          'data': [
            {'place': '香港天文台', 'value': '26', 'unit': 'C'},
            'bad item',
          ],
        },
        'humidity': {
          'recordTime': '2026-06-05T00:00:00Z',
          'data': [
            {'place': '香港天文台', 'value': 82.9, 'unit': 'percent'},
          ],
        },
        'rainfall': {
          'data': [
            {
              'unit': 'mm',
              'place': 123,
              'max': '12.5',
              'main': null,
              'min': '1',
            },
          ],
        },
        'lightning': {
          'data': [
            {'place': 'Hong Kong', 'occur': 'yes'},
          ],
        },
        'uvindex': {
          'recordDesc': 5,
          'data': [
            {'place': "King's Park", 'value': '3.5', 'desc': 123},
          ],
        },
        'tcmessage': ['signal 1', 3],
      });

      expect(weather.updateTime, '123');
      expect(weather.warningMessage, ['Amber rainstorm', '7']);
      expect(weather.icon, [50, 62, 0]);
      expect(weather.temperature!.recordTime, '123');
      expect(weather.temperature!.data, hasLength(1));
      expect(weather.temperature!.data.single.value, 26);
      expect(weather.humidity!.data.single.value, 82);
      expect(weather.rainfall!.data.single.place, '123');
      expect(weather.rainfall!.data.single.max, 12.5);
      expect(weather.rainfall!.data.single.min, 1);
      expect(weather.lightning!.data.single.occur, isTrue);
      expect(weather.uvindex!.recordDesc, '5');
      expect(weather.uvindex!.data.single.value, 3.5);
      expect(weather.uvindex!.data.single.desc, '123');
      expect(weather.tcmessage, ['signal 1', '3']);
    });

    test('uses empty nested models instead of throwing on malformed objects',
        () {
      final weather = CurrentWeatherDataModel.fromJson({
        'lightning': 'bad',
        'rainfall': 'bad',
        'temperature': 'bad',
        'humidity': 'bad',
        'uvindex': 'bad',
        'warningMessage': '',
        'tcmessage': '',
      });

      expect(weather.updateTime, '');
      expect(weather.warningMessage, isNull);
      expect(weather.tcmessage, isNull);
      expect(weather.lightning!.data, isEmpty);
      expect(weather.rainfall!.data, isEmpty);
      expect(weather.temperature!.data, isEmpty);
      expect(weather.humidity!.data, isEmpty);
      expect(weather.uvindex!.data, isEmpty);
    });
  });
}
