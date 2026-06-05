import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iboard_app/http/api_client.dart';
import 'package:iboard_app/managers/file_manager.dart';
import 'package:iboard_app/providers/announcement_provider.dart';
import 'package:iboard_app/providers/app_data_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AnnouncementProvider cache parsing', () {
    test('keeps displayable cached notices and filters malformed entries',
        () async {
      SharedPreferences.setMockInitialValues({
        'announcements_data': jsonEncode([
          _noticeJson(id: 1, type: 'normal', url: 'https://example.test/a.pdf'),
          'bad item',
          _noticeJson(id: 2, type: 'normal', url: ''),
          _noticeJson(
            id: 3,
            type: 'government',
            url: 'https://example.test/government.pdf',
          ),
          _noticeJson(
            id: 4,
            type: 'building',
            url: 'https://example.test/no-mime.pdf',
            mimeType: '',
          ),
        ]),
      });

      final appDataProvider = AppDataProvider(baseUrl: 'http://example.test');
      final provider = AnnouncementProvider(
        ApiClient(baseUrl: 'http://example.test'),
        appDataProvider,
        FileManager(),
      );

      await _waitForCacheLoad(provider);

      expect(provider.announcements.map((notice) => notice.id), [1, 3]);
      expect(provider.carouselAnnouncements.map((notice) => notice.id), [1]);

      provider.dispose();
      appDataProvider.dispose();
    });
  });
}

Future<void> _waitForCacheLoad(AnnouncementProvider provider) async {
  for (var i = 0; i < 10; i++) {
    if (provider.announcements.isNotEmpty) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Map<String, dynamic> _noticeJson({
  required int id,
  required String type,
  required String url,
  String mimeType = 'application/pdf',
}) {
  return {
    'id': id,
    'createdAt': '2026-06-05T00:00:00.000Z',
    'updatedAt': '2026-06-05T00:00:00.000Z',
    'title': 'Notice $id',
    'description': '',
    'type': type,
    'isPublic': true,
    'isIsmartNotice': false,
    'priority': 1,
    'status': 'active',
    'startTime': '2026-06-05T00:00:00.000Z',
    'endTime': '2026-06-30T00:00:00.000Z',
    'fileId': id,
    'file': {
      'id': id,
      'mimeType': mimeType,
      'md5': 'md5-$id',
      'path': url,
      'size': 1024,
    },
    'fileType': 'pdf',
  };
}
