import 'dart:async';
import 'dart:convert';

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

Map<String, dynamic> _loginData({required String token}) {
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
      'settings': {},
    },
  };
}
