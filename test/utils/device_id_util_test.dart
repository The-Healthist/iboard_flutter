import 'package:flutter_test/flutter_test.dart';
import 'package:iboard_app/utils/device_id_util.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('DeviceIdUtil.generateUniqueDeviceId', () {
    test('uses and migrates the legacy cached_device_id value', () async {
      SharedPreferences.setMockInitialValues({
        'cached_device_id': 'DEVICE_AB12CD34',
      });

      final deviceId = await DeviceIdUtil().generateUniqueDeviceId();
      final prefs = await SharedPreferences.getInstance();

      expect(deviceId, 'DEVICE_AB12CD34');
      expect(prefs.getString('device_id'), 'DEVICE_AB12CD34');
      expect(prefs.getString('cached_device_id'), 'DEVICE_AB12CD34');
    });

    test('falls back safely when cached data is invalid', () async {
      SharedPreferences.setMockInitialValues({
        'device_id': 'bad-device-id',
        'cached_device_id': '',
      });

      final util = DeviceIdUtil();
      final deviceId = await util.generateUniqueDeviceId();
      final prefs = await SharedPreferences.getInstance();

      expect(util.isValidDeviceId(deviceId), isTrue);
      expect(prefs.getString('device_id'), deviceId);
      expect(prefs.getString('cached_device_id'), deviceId);
    });
  });

  group('DeviceIdUtil.clearStoredDeviceId', () {
    test('clears current, legacy, and fallback ids', () async {
      SharedPreferences.setMockInitialValues({
        'device_id': 'DEVICE_AB12CD34',
        'cached_device_id': 'DEVICE_AB12CD34',
        'fallback_device_id': 'fallback-1',
      });

      await DeviceIdUtil().clearStoredDeviceId();
      final prefs = await SharedPreferences.getInstance();

      expect(prefs.getString('device_id'), isNull);
      expect(prefs.getString('cached_device_id'), isNull);
      expect(prefs.getString('fallback_device_id'), isNull);
    });
  });
}
