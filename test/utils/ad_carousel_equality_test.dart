import 'package:flutter_test/flutter_test.dart';
import 'package:iboard_app/models/ad_model.dart';
import 'package:iboard_app/models/file_model.dart';
import 'package:iboard_app/utils/ad_carousel_equality.dart';

void main() {
  group('areCarouselAdListsEqual', () {
    test('treats identical carousel ad payloads as equal', () {
      final ad = _ad();

      expect(areCarouselAdListsEqual([ad], [_ad()]), isTrue);
    });

    test('detects same-id duration changes', () {
      expect(
        areCarouselAdListsEqual([_ad(duration: 10)], [_ad(duration: 20)]),
        isFalse,
      );
    });

    test('detects same-id file changes', () {
      expect(
        areCarouselAdListsEqual(
          [_ad(fileUrl: 'https://example.test/a.png')],
          [_ad(fileUrl: 'https://example.test/b.png')],
        ),
        isFalse,
      );
    });

    test('detects same-id schedule changes', () {
      expect(
        areCarouselAdListsEqual([_ad()], [_ad(startOffsetHours: 1)]),
        isFalse,
      );
    });
  });
}

AdModel _ad({
  int id = 1,
  int duration = 10,
  String fileUrl = 'https://example.test/a.png',
  int startOffsetHours = 0,
}) {
  final timestamp = DateTime.parse('2026-06-05T00:00:00.000Z');
  final startTime = timestamp.add(Duration(hours: startOffsetHours));
  return AdModel(
    id: id,
    createdAt: timestamp,
    updatedAt: timestamp,
    title: 'Ad $id',
    description: 'Description',
    type: 'image',
    status: 'active',
    duration: duration,
    priority: 1,
    startTime: startTime,
    endTime: startTime.add(const Duration(days: 1)),
    display: AdDisplayType.top,
    fileId: id,
    file: FileModel(
      id: id,
      mimeType: 'image/png',
      md5: 'md5-$id',
      url: fileUrl,
      fileSize: 1024,
    ),
    isPublic: true,
  );
}
