import 'package:flutter_test/flutter_test.dart';
import 'package:iboard_app/models/ad_model.dart';

void main() {
  group('AdModel.fromJson', () {
    test('parses flexible scalar values and file metadata safely', () {
      final ad = AdModel.fromJson({
        'id': '42',
        'createdAt': '2026-06-05T00:00:00.000Z',
        'updatedAt': 'bad date',
        'deletedAt': 'bad date',
        'title': 123,
        'description': null,
        'type': 'image',
        'status': 'active',
        'duration': '15',
        'priority': 3.8,
        'startTime': 'bad date',
        'endTime': 'bad date',
        'display': 'TOPFULL',
        'fileId': '7',
        'file': {
          'id': '7',
          'mimeType': 'image/png',
          'md5': 12345,
          'url': 'https://example.test/ad.png',
          'fileSize': '2048',
          'uploaderId': '9',
          'createdAt': 'not a date',
        },
        'isPublic': '1',
      });

      expect(ad.id, 42);
      expect(ad.title, '123');
      expect(ad.description, '');
      expect(ad.duration, 15);
      expect(ad.priority, 3);
      expect(ad.display, AdDisplayType.topfull);
      expect(ad.fileId, 7);
      expect(ad.file.id, 7);
      expect(ad.file.mimeType, 'image/png');
      expect(ad.file.md5, '12345');
      expect(ad.file.url, 'https://example.test/ad.png');
      expect(ad.file.fileSize, 2048);
      expect(ad.file.uploaderId, 9);
      expect(ad.file.createdAt, isNull);
      expect(ad.isPublic, isTrue);
      expect(ad.deletedAt, isNull);
    });

    test('uses safe defaults for missing file and invalid display values', () {
      final before = DateTime.now();

      final ad = AdModel.fromJson({
        'display': 'unsupported',
      });

      final after = DateTime.now().add(const Duration(days: 366));

      expect(ad.id, 0);
      expect(ad.duration, 10);
      expect(ad.display, AdDisplayType.top);
      expect(ad.file.url, '');
      expect(ad.file.mimeType, '');
      expect(ad.startTime.isBefore(before), isFalse);
      expect(ad.endTime.isAfter(after), isFalse);
      expect(ad.isPublic, isFalse);
    });
  });
}
