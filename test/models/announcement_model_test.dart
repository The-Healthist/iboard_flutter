import 'package:flutter_test/flutter_test.dart';
import 'package:iboard_app/models/announcement_model.dart';

void main() {
  group('AnnouncementModel.fromJson', () {
    test('parses flexible scalar values and maps API types safely', () {
      final announcement = AnnouncementModel.fromJson({
        'id': '12',
        'createdAt': '2026-06-05T00:00:00.000Z',
        'updatedAt': 'bad date',
        'deletedAt': 'bad date',
        'title': 123,
        'description': null,
        'type': 'building',
        'isPublic': '1',
        'isIsmartNotice': 1,
        'priority': '4',
        'status': 'active',
        'startTime': 'bad date',
        'endTime': 'bad date',
        'fileId': '7',
        'file': {
          'id': '7',
          'mimeType': 'application/pdf',
          'md5': 12345,
          'url': 'https://example.test/notice.pdf',
          'fileSize': '2048',
        },
        'fileType': 99,
      });

      expect(announcement.id, 12);
      expect(announcement.title, '123');
      expect(announcement.description, '');
      expect(announcement.apiType, 'building');
      expect(announcement.uiType, AnnouncementTypeUi.corporation);
      expect(announcement.isPublic, isTrue);
      expect(announcement.isIsmartNotice, isTrue);
      expect(announcement.priority, 4);
      expect(announcement.fileId, 7);
      expect(announcement.file.url, 'https://example.test/notice.pdf');
      expect(announcement.file.fileSize, 2048);
      expect(announcement.fileType, '99');
      expect(announcement.deletedAt, isNull);
    });

    test('uses safe defaults for missing file and invalid type values', () {
      final before = DateTime.now();

      final announcement = AnnouncementModel.fromJson({
        'type': 'unknown',
      });

      final after = DateTime.now().add(const Duration(days: 366));

      expect(announcement.id, 0);
      expect(announcement.uiType, AnnouncementTypeUi.general);
      expect(announcement.file.url, '');
      expect(announcement.file.mimeType, '');
      expect(announcement.startTime.isBefore(before), isFalse);
      expect(announcement.endTime.isAfter(after), isFalse);
      expect(announcement.isPublic, isFalse);
    });
  });
}
