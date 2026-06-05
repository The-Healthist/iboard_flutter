import 'package:flutter_test/flutter_test.dart';
import 'package:iboard_app/models/weather_warning_model.dart';

void main() {
  group('WeatherWarningModel.fromJson', () {
    test('parses flexible warning maps and filters malformed entries', () {
      final warnings = WeatherWarningModel.fromJson({
        'WRAIN': {
          'name': 123,
          'code': 'WRAIN',
          'actionCode': 'ISSUE',
          'issueTime': 456,
          'updateTime': null,
          'type': 1,
          'expireTime': 789,
        },
        'WTCSGNL': {
          'name': 'Tropical Cyclone Warning Signal',
          'code': 'WTCSGNL',
          'actionCode': 'CANCEL',
          'issueTime': '2026-06-05T00:00:00Z',
          'updateTime': '2026-06-05T01:00:00Z',
          'type': '',
        },
        'bad': 'not a map',
      });

      expect(warnings.warnings.keys, ['WRAIN', 'WTCSGNL']);

      final rain = warnings.warnings['WRAIN']!;
      expect(rain.name, '123');
      expect(rain.issueTime, '456');
      expect(rain.updateTime, '');
      expect(rain.type, '1');
      expect(rain.expireTime, '789');

      expect(warnings.getActiveWarnings().keys, ['WRAIN']);
      expect(
        warnings.getActiveWarningDescriptions(),
        ['暴雨警告信號', '熱帶氣旋警告信號'],
      );
    });

    test('uses empty strings and null optional values for malformed fields',
        () {
      final warnings = WeatherWarningModel.fromJson({
        'UNKNOWN': {
          'name': null,
          'code': null,
          'actionCode': null,
          'issueTime': null,
          'updateTime': null,
          'type': '',
          'expireTime': '',
        },
      });

      final warning = warnings.warnings['UNKNOWN']!;
      expect(warning.name, '');
      expect(warning.code, '');
      expect(warning.actionCode, '');
      expect(warning.issueTime, '');
      expect(warning.updateTime, '');
      expect(warning.type, isNull);
      expect(warning.expireTime, isNull);
      expect(warnings.getActiveWarnings().keys, ['UNKNOWN']);
      expect(warnings.getActiveWarningDescriptions(), ['UNKNOWN']);
    });
  });
}
