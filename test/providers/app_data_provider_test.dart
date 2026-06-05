import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iboard_app/providers/app_data_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AppDataProvider.isLoggedIn', () {
    test('does not treat cached data with an empty token as logged in',
        () async {
      SharedPreferences.setMockInitialValues({
        'login_device_data': jsonEncode(_loginData(token: '')),
      });

      final provider = AppDataProvider(baseUrl: 'http://example.test');
      await _waitForInitialCacheLoad(provider);

      expect(provider.settingsModel, isNotNull);
      expect(provider.token, '');
      expect(provider.isLoggedIn, isFalse);

      provider.dispose();
    });

    test('treats cached data with a non-empty token as logged in', () async {
      SharedPreferences.setMockInitialValues({
        'login_device_data': jsonEncode(_loginData(token: 'token-123')),
      });

      final provider = AppDataProvider(baseUrl: 'http://example.test');
      await _waitForInitialCacheLoad(provider);

      expect(provider.settingsModel, isNotNull);
      expect(provider.token, 'token-123');
      expect(provider.isLoggedIn, isTrue);

      provider.dispose();
    });

    test('preserves OrangePi IP in validated cached settings', () async {
      SharedPreferences.setMockInitialValues({
        'login_device_data': jsonEncode(
          _loginData(
            token: 'token-123',
            settings: {'orangePiIp': ' 192.168.3.74 '},
          ),
        ),
      });

      final provider = AppDataProvider(baseUrl: 'http://example.test');
      await _waitForInitialCacheLoad(provider);

      expect(provider.validatedDeviceSettings?.orangePiIp, '192.168.3.74');

      provider.dispose();
    });

    test('initializes from cached login data without an ArrearProvider',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('app-data-test');
      addTearDown(() => tempDir.delete(recursive: true));

      final complaintQr = File('${tempDir.path}/complaint_0314100.png');
      final registrationQr = File('${tempDir.path}/registration_0314100.png');
      await complaintQr.writeAsBytes([1]);
      await registrationQr.writeAsBytes([1]);

      SharedPreferences.setMockInitialValues({
        'login_device_data': jsonEncode(_loginData(token: 'token-123')),
        'complaint_qr_code_path': complaintQr.path,
        'registration_qr_code_path': registrationQr.path,
      });

      final provider = AppDataProvider(baseUrl: 'http://example.test');
      await provider.initializeFromCache();

      expect(provider.error, isNull);
      expect(provider.settingsModel, isNotNull);
      expect(provider.cachedComplaintQrCode, complaintQr.path);
      expect(provider.cachedRegistrationQrCode, registrationQr.path);

      provider.dispose();
    });
  });
}

Future<void> _waitForInitialCacheLoad(AppDataProvider provider) async {
  final completer = Completer<void>();
  provider.addListener(() {
    if (!completer.isCompleted) {
      completer.complete();
    }
  });
  await completer.future.timeout(const Duration(seconds: 1));
}

Map<String, dynamic> _loginData({
  required String token,
  Map<String, dynamic> settings = const {},
}) {
  return {
    'message': 'ok',
    'token': token,
    'data': {
      'id': 1,
      'createdAt': '2026-06-05T00:00:00.000Z',
      'updatedAt': '2026-06-05T00:00:00.000Z',
      'deviceId': 'device-1',
      'buildingId': 20,
      'status': 'active',
      'building': {
        'id': 20,
        'createdAt': '2026-06-05T00:00:00.000Z',
        'updatedAt': '2026-06-05T00:00:00.000Z',
        'name': 'Test Building',
        'ismartId': '0314100',
        'remark': '',
        'location': '',
      },
      'settings': settings,
    },
  };
}
