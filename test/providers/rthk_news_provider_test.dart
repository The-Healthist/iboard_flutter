import 'package:flutter_test/flutter_test.dart';
import 'package:iboard_app/http/api_client.dart';
import 'package:iboard_app/providers/rthk_news_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('RthkNewsProvider cache loading', () {
    test('loads valid cached news and filters malformed/error entries',
        () async {
      SharedPreferences.setMockInitialValues({
        'rthk_news': '''
          [
            {
              "title": "Valid cached news",
              "guid": "valid-1",
              "link": "https://example.com/news",
              "pubDate": "2026-06-05T08:09:00.000"
            },
            "bad item",
            {
              "title": "Network error",
              "guid": "network_error_001",
              "link": "https://example.com/news",
              "pubDate": "2026-06-05T08:10:00.000"
            }
          ]
        ''',
        'rthk_news_last_update': '2026-06-05T08:30:00.000',
      });

      final provider =
          RthkNewsProvider(ApiClient(baseUrl: 'https://example.com'));
      addTearDown(provider.dispose);

      await Future<void>.delayed(Duration.zero);

      expect(provider.newsList, hasLength(1));
      expect(provider.newsList.single.title, 'Valid cached news');
      expect(provider.newsList.single.formattedTime, '08:09');
      expect(
          provider.lastUpdateTime, DateTime.parse('2026-06-05T08:30:00.000'));
    });
  });
}
