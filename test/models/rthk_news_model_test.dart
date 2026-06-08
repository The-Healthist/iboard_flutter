import 'package:flutter_test/flutter_test.dart';
import 'package:iboard_app/models/rthk_news_model.dart';

void main() {
  group('RthkNewsModel.fromRssXml', () {
    test('parses CDATA titles and flexible scalar values safely', () {
      final news = RthkNewsModel.fromRssXml({
        'title': '<![CDATA[ Market update ]]>',
        'guid': 123,
        'link': 456,
        'pubDate': 'Fri, 05 Jun 2026 16:40:08 +0800',
      });

      expect(news.title, 'Market update');
      expect(news.guid, '123');
      expect(news.link, '456');
      expect(news.formattedTime, '16:40');
    });
  });

  group('RthkNewsModel.fromJson', () {
    test('parses flexible cached values and derives missing formatted time',
        () {
      final news = RthkNewsModel.fromJson({
        'title': 123,
        'guid': 456,
        'link': 789,
        'pubDate': '2026-06-05T08:09:00.000',
      });

      expect(news.title, '123');
      expect(news.guid, '456');
      expect(news.link, '789');
      expect(news.formattedTime, '08:09');
    });
  });
}
