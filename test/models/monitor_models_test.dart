import 'package:flutter_test/flutter_test.dart';
import 'package:iboard_app/models/monitor_models.dart';

void main() {
  group('MonitorResponse.fromJson', () {
    test('parses flexible monitor payloads and filters unusable channels', () {
      final response = MonitorResponse.fromJson({
        'success': 'true',
        'data': {
          'orangepis': [
            {
              'orangepi_id': '12',
              'orangepi_name': 345,
              'is_active': 1,
              'token': 999,
              'urls': [
                'https://example.test/cam-1',
                '',
                42,
              ],
            },
            {
              'orangepi_id': 'bad',
              'orangepi_name': 'no-url',
              'is_active': 'false',
              'token': null,
              'urls': [],
            },
            'malformed',
          ],
        },
      });

      expect(response.success, isTrue);
      expect(response.data.orangepis, hasLength(1));

      final orangepi = response.data.orangepis.single;
      expect(orangepi.orangepi_id, 12);
      expect(orangepi.orangepi_name, '345');
      expect(orangepi.is_active, isTrue);
      expect(orangepi.token, '999');
      expect(orangepi.urls, ['https://example.test/cam-1', '42']);
    });

    test('uses safe defaults for malformed response envelopes', () {
      final response = MonitorResponse.fromJson({
        'success': null,
        'data': 'not-a-map',
      });

      expect(response.success, isFalse);
      expect(response.data.orangepis, isEmpty);
    });
  });

  group('MonitorRequest.fromJson', () {
    test('parses dynamic request values safely', () {
      final request = MonitorRequest.fromJson({
        'ismartid': 12345,
        'is_staff': '1',
      });

      expect(request.ismartId, '12345');
      expect(request.isStaff, isTrue);
    });
  });
}
