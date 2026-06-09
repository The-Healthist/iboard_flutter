import 'package:flutter_test/flutter_test.dart';
import 'package:iboard_app/models/announcement_model.dart';
import 'package:iboard_app/models/file_model.dart';
import 'package:iboard_app/providers/announcement_carousel_provider.dart';

void main() {
  group('announcement carousel signatures', () {
    test('stay stable for identical announcement payloads', () {
      final announcement = _announcement();

      expect(
        debugAnnouncementCarouselSignature(announcement),
        debugAnnouncementCarouselSignature(_announcement()),
      );
    });

    test('detect same-id content, schedule, and file changes', () {
      final baseSignature = debugAnnouncementCarouselSignature(_announcement());

      expect(
        debugAnnouncementCarouselSignature(
          _announcement(title: 'Updated title'),
        ),
        isNot(baseSignature),
      );
      expect(
        debugAnnouncementCarouselSignature(
          _announcement(
            endTime: DateTime.utc(2026, 7, 1),
          ),
        ),
        isNot(baseSignature),
      );
      expect(
        debugAnnouncementCarouselSignature(
          _announcement(fileMd5: 'new-md5'),
        ),
        isNot(baseSignature),
      );
    });
  });

  group('AnnouncementCarouselIndexPolicy', () {
    test('cycles announcements before arrear tables', () {
      expect(
        AnnouncementCarouselIndexPolicy.nextIndex(
          currentIndex: 2,
          announcementCount: 2,
          hasOtherTable: true,
          hasManagementTable: true,
          firstArrearTableIndex: 4,
          otherTableIndex: 4,
          managementTableIndex: 5,
        ),
        3,
      );
      expect(
        AnnouncementCarouselIndexPolicy.nextIndex(
          currentIndex: 3,
          announcementCount: 2,
          hasOtherTable: true,
          hasManagementTable: true,
          firstArrearTableIndex: 4,
          otherTableIndex: 4,
          managementTableIndex: 5,
        ),
        4,
      );
    });

    test('returns from arrear tables to first announcement when notices exist',
        () {
      expect(
        AnnouncementCarouselIndexPolicy.nextIndex(
          currentIndex: 5,
          announcementCount: 2,
          hasOtherTable: true,
          hasManagementTable: true,
          firstArrearTableIndex: 4,
          otherTableIndex: 4,
          managementTableIndex: 5,
        ),
        2,
      );
    });

    test('alternates other and management tables when there are no notices',
        () {
      expect(
        AnnouncementCarouselIndexPolicy.nextIndex(
          currentIndex: 2,
          announcementCount: 0,
          hasOtherTable: true,
          hasManagementTable: true,
          firstArrearTableIndex: 2,
          otherTableIndex: 2,
          managementTableIndex: 3,
        ),
        3,
      );
      expect(
        AnnouncementCarouselIndexPolicy.nextIndex(
          currentIndex: 3,
          announcementCount: 0,
          hasOtherTable: true,
          hasManagementTable: true,
          firstArrearTableIndex: 2,
          otherTableIndex: 2,
          managementTableIndex: 3,
        ),
        2,
      );
    });

    test('keeps single management table on its current index', () {
      expect(
        AnnouncementCarouselIndexPolicy.nextIndex(
          currentIndex: 2,
          announcementCount: 0,
          hasOtherTable: false,
          hasManagementTable: true,
          firstArrearTableIndex: 2,
          otherTableIndex: -1,
          managementTableIndex: 2,
        ),
        2,
      );
    });

    test('falls back to main screen when no carousel content exists', () {
      expect(
        AnnouncementCarouselIndexPolicy.nextIndex(
          currentIndex: 2,
          announcementCount: 0,
          hasOtherTable: false,
          hasManagementTable: false,
          firstArrearTableIndex: -1,
          otherTableIndex: -1,
          managementTableIndex: -1,
        ),
        0,
      );
    });
  });

  group('AnnouncementCarouselExitPolicy', () {
    test('honors main screen target when exiting independent announcement', () {
      expect(
        AnnouncementCarouselExitPolicy.resolveTargetIndex(
          requestedTargetIndex: 0,
          savedCarouselIndex: 2,
          widgetCount: 4,
          initialCarouselIndex: 2,
        ),
        0,
      );
    });

    test('restores saved carousel index when no explicit target is requested',
        () {
      expect(
        AnnouncementCarouselExitPolicy.resolveTargetIndex(
          requestedTargetIndex: null,
          savedCarouselIndex: 3,
          widgetCount: 5,
          initialCarouselIndex: 2,
        ),
        3,
      );
    });

    test('falls back to first content index when saved target is invalid', () {
      expect(
        AnnouncementCarouselExitPolicy.resolveTargetIndex(
          requestedTargetIndex: null,
          savedCarouselIndex: 9,
          widgetCount: 4,
          initialCarouselIndex: 0,
        ),
        2,
      );
    });
  });
}

AnnouncementModel _announcement({
  String title = 'Notice',
  DateTime? endTime,
  String fileMd5 = 'md5',
}) {
  final createdAt = DateTime.utc(2026, 6, 1);
  return AnnouncementModel(
    id: 1,
    createdAt: createdAt,
    updatedAt: createdAt,
    title: title,
    description: 'Description',
    apiType: 'normal',
    uiType: AnnouncementTypeUi.general,
    isPublic: true,
    isIsmartNotice: false,
    priority: 1,
    status: 'published',
    startTime: createdAt,
    endTime: endTime ?? DateTime.utc(2026, 6, 30),
    fileId: 10,
    fileType: 'pdf',
    file: FileModel(
      id: 10,
      mimeType: 'application/pdf',
      md5: fileMd5,
      url: 'https://example.test/notice.pdf',
      fileSize: 1024,
    ),
  );
}
