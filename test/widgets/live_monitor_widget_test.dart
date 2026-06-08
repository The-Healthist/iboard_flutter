import 'package:flutter_test/flutter_test.dart';
import 'package:iboard_app/widgets/mainscreen/live_monitor_widget.dart';

void main() {
  group('hasLiveMonitorConfigChanged', () {
    test('returns false when channels and layout are unchanged', () {
      expect(
        hasLiveMonitorConfigChanged(
          previousChannels: ['1_channel1', '2_channel1'],
          currentChannels: ['1_channel1', '2_channel1'],
          previousLayout: 'grid4',
          currentLayout: 'grid4',
        ),
        isFalse,
      );
    });

    test('detects channel order, length, and layout changes', () {
      expect(
        hasLiveMonitorConfigChanged(
          previousChannels: ['1_channel1', '2_channel1'],
          currentChannels: ['2_channel1', '1_channel1'],
          previousLayout: 'grid4',
          currentLayout: 'grid4',
        ),
        isTrue,
      );
      expect(
        hasLiveMonitorConfigChanged(
          previousChannels: ['1_channel1'],
          currentChannels: ['1_channel1', '2_channel1'],
          previousLayout: 'grid4',
          currentLayout: 'grid4',
        ),
        isTrue,
      );
      expect(
        hasLiveMonitorConfigChanged(
          previousChannels: ['1_channel1'],
          currentChannels: ['1_channel1'],
          previousLayout: 'grid4',
          currentLayout: 'grid1',
        ),
        isTrue,
      );
    });

    test('does not collapse comma-containing channel names', () {
      expect(
        hasLiveMonitorConfigChanged(
          previousChannels: ['a,b', 'c'],
          currentChannels: ['a', 'b,c'],
          previousLayout: 'grid4',
          currentLayout: 'grid4',
        ),
        isTrue,
      );
    });
  });
}
