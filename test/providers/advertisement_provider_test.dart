import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iboard_app/http/api_client.dart';
import 'package:iboard_app/providers/advertisement_provider.dart';
import 'package:iboard_app/providers/app_data_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AdvertisementProvider cache parsing', () {
    test('keeps displayable cached ads and filters malformed cache entries',
        () async {
      SharedPreferences.setMockInitialValues({
        'top_carousel_advertisements': jsonEncode([
          _adJson(id: 1, url: 'https://example.test/top.png'),
          'bad item',
          _adJson(id: 2, url: ''),
          _adJson(id: 3, url: 'https://example.test/no-mime.png', mimeType: ''),
        ]),
        'full_carousel_advertisements': jsonEncode([
          _adJson(
              id: 4,
              url: 'https://example.test/full.mp4',
              mimeType: 'video/mp4'),
        ]),
        'advertisements_data': jsonEncode({'not': 'a list'}),
      });

      final appDataProvider = AppDataProvider(baseUrl: 'http://example.test');
      final provider = AdvertisementProvider(
        ApiClient(baseUrl: 'http://example.test'),
        appDataProvider,
      );

      await _waitForCacheLoad(provider);

      expect(provider.advertisements, isEmpty);
      expect(provider.topCarouselAdvertisements, hasLength(1));
      expect(provider.topCarouselAdvertisements.single.id, 1);
      expect(provider.fullCarouselAdvertisements, hasLength(1));
      expect(provider.fullCarouselAdvertisements.single.id, 4);

      provider.dispose();
      appDataProvider.dispose();
    });
  });
}

Future<void> _waitForCacheLoad(AdvertisementProvider provider) async {
  for (var i = 0; i < 10; i++) {
    if (provider.topCarouselAdvertisements.isNotEmpty &&
        provider.fullCarouselAdvertisements.isNotEmpty) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Map<String, dynamic> _adJson({
  required int id,
  required String url,
  String mimeType = 'image/png',
}) {
  return {
    'id': id,
    'createdAt': '2026-06-05T00:00:00.000Z',
    'updatedAt': '2026-06-05T00:00:00.000Z',
    'title': 'Ad $id',
    'description': '',
    'type': 'image',
    'status': 'active',
    'duration': 15,
    'priority': 1,
    'startTime': '2026-06-05T00:00:00.000Z',
    'endTime': '2026-06-30T00:00:00.000Z',
    'display': 'top',
    'fileId': id,
    'file': {
      'id': id,
      'mimeType': mimeType,
      'md5': 'md5-$id',
      'path': url,
      'size': 1024,
    },
    'isPublic': true,
  };
}
