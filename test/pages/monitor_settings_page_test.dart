import 'package:flutter_test/flutter_test.dart';
import 'package:iboard_app/models/monitor_models.dart';
import 'package:iboard_app/pages/monitor_settings_page.dart';

void main() {
  group('parseMonitorChannelKey', () {
    test('parses channel keys without truncating channel names', () {
      final key = parseMonitorChannelKey('12_channel_1_extra');

      expect(key?.orangepiId, 12);
      expect(key?.channelName, 'channel_1_extra');
    });

    test('rejects malformed channel keys', () {
      expect(parseMonitorChannelKey('channel1'), isNull);
      expect(parseMonitorChannelKey('_channel1'), isNull);
      expect(parseMonitorChannelKey('12_'), isNull);
      expect(parseMonitorChannelKey('bad_channel1'), isNull);
    });
  });

  group('getMonitorChannelDisplayName', () {
    final orangepis = [
      Orangepi(
        orangepi_id: 12,
        orangepi_name: 'Lobby',
        is_active: true,
        token: 'token',
        urls: const ['https://example.test/channel1'],
      ),
      Orangepi(
        orangepi_id: 34,
        orangepi_name: 'Car Park',
        is_active: false,
        token: 'token',
        urls: const ['https://example.test/channel2'],
      ),
    ];

    test('uses matching device names for known channel keys', () {
      expect(
        getMonitorChannelDisplayName('34_channel2', orangepis),
        'Car Park-channel2',
      );
    });

    test('does not mislabel stale saved channels as the first device', () {
      expect(
        getMonitorChannelDisplayName('99_channel3', orangepis),
        'channel3',
      );
    });

    test('returns malformed keys unchanged', () {
      expect(
        getMonitorChannelDisplayName('bad_channel3', orangepis),
        'bad_channel3',
      );
    });
  });
}
