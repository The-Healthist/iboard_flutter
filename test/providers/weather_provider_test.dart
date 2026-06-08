import 'package:flutter_test/flutter_test.dart';
import 'package:iboard_app/providers/weather_provider.dart';

void main() {
  group('WeatherProvider periodic updates', () {
    test('starts and stops weather and warning timers', () {
      final provider = WeatherProvider();

      provider.startPeriodicUpdate(interval: const Duration(hours: 12));
      provider.startWarningPeriodicUpdate(interval: const Duration(hours: 12));

      expect(provider.isPeriodicUpdateActive, isTrue);
      expect(provider.isWarningPeriodicUpdateActive, isTrue);

      provider.stopPeriodicUpdate();
      provider.stopWarningPeriodicUpdate();

      expect(provider.isPeriodicUpdateActive, isFalse);
      expect(provider.isWarningPeriodicUpdateActive, isFalse);

      provider.dispose();
    });
  });
}
