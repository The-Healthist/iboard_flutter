import 'package:flutter_test/flutter_test.dart';
import 'package:iboard_app/providers/app_update_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AppUpdateProvider.checkForUpdate', () {
    test('parses flexible remote version fields without requiring update',
        () async {
      SharedPreferences.setMockInitialValues({});

      final provider = AppUpdateProvider(
        currentVersionLoader: () async => {
          'version': '124.0.0',
          'buildNumber': '1',
        },
        appVersionLoader: () async => {
          'data': {
            'currentVersion': {
              'versionNumber': 123,
              'buildNumber': 2,
              'downloadUrl': 789,
              'description': 456,
            },
          },
        },
      );
      addTearDown(provider.dispose);

      await provider.checkForUpdate();

      expect(provider.error, isNull);
      expect(provider.currentVersion, 'v124.0.0 (1)');
      expect(provider.remoteVersion, 'v123 (2)');
      expect(provider.remoteVersionNumber, '123');
      expect(provider.remoteBuildNumber, '2');
      expect(provider.downloadUrl, '789');
      expect(provider.updateDescription, '456');
      expect(provider.hasUpdate, isFalse);
      expect(provider.hasLocalApk, isFalse);
    });

    test('handles malformed remote version envelope safely', () async {
      SharedPreferences.setMockInitialValues({});

      final provider = AppUpdateProvider(
        currentVersionLoader: () async => {
          'version': '1.2.15',
          'buildNumber': '1',
        },
        appVersionLoader: () async => {
          'data': ['unexpected'],
        },
      );
      addTearDown(provider.dispose);

      await provider.checkForUpdate();

      expect(provider.error, '获取版本信息失败');
      expect(provider.hasUpdate, isFalse);
      expect(provider.hasLocalApk, isFalse);
    });
  });
}
