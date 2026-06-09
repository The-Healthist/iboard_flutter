import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iboard_app/http/api_client.dart';
import 'package:iboard_app/managers/file_manager.dart';
import 'package:iboard_app/models/announcement_model.dart';
import 'package:iboard_app/models/file_model.dart';
import 'package:iboard_app/providers/announcement_provider.dart';
import 'package:iboard_app/providers/announcement_carousel_provider.dart';
import 'package:iboard_app/providers/app_data_provider.dart';
import 'package:iboard_app/providers/arrear_provider.dart';
import 'package:iboard_app/providers/state_provider.dart';
import 'package:iboard_app/widgets/carousel/carousel_widget.dart'
    as custom_carousel;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

    test('keeps the 43-inch dual notice widget as one announcement slot', () {
      expect(
        AnnouncementCarouselIndexPolicy.nextIndex(
          currentIndex: 2,
          announcementCount: 1,
          hasOtherTable: true,
          hasManagementTable: true,
          firstArrearTableIndex: 3,
          otherTableIndex: 3,
          managementTableIndex: 4,
        ),
        3,
      );
      expect(
        AnnouncementCarouselIndexPolicy.nextIndex(
          currentIndex: 4,
          announcementCount: 1,
          hasOtherTable: true,
          hasManagementTable: true,
          firstArrearTableIndex: 3,
          otherTableIndex: 3,
          managementTableIndex: 4,
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

  group('AnnouncementCarouselProvider independent mode', () {
    testWidgets('home jump from independent announcement lands on main screen',
        (tester) async {
      SharedPreferences.setMockInitialValues({});

      final tempDir = Directory.systemTemp.createTempSync('notice_nav_test_');
      final attachment = File('${tempDir.path}/notice.txt')
        ..writeAsStringSync('notice');

      final appDataProvider = AppDataProvider(baseUrl: 'http://example.test');
      final apiClient = ApiClient(baseUrl: 'http://example.test');
      final fileManager = FileManager();
      final announcementProvider = AnnouncementProvider(
        apiClient,
        appDataProvider,
        fileManager,
      );
      final arrearProvider = ArrearProvider(
        apiClient: apiClient,
        appDataProvider: appDataProvider,
      );
      final carouselStateProvider = CarouselStateProvider();
      final carouselProvider = AnnouncementCarouselProvider()
        ..setAppDataProvider(appDataProvider)
        ..setArrearProvider(arrearProvider);

      addTearDown(() {
        carouselProvider.dispose();
        carouselStateProvider.dispose();
        arrearProvider.dispose();
        announcementProvider.dispose();
        appDataProvider.dispose();
        tempDir.deleteSync(recursive: true);
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppDataProvider>.value(
              value: appDataProvider,
            ),
            Provider<FileManager>.value(value: fileManager),
            ChangeNotifierProvider<AnnouncementProvider>.value(
              value: announcementProvider,
            ),
            ChangeNotifierProvider<ArrearProvider>.value(
              value: arrearProvider,
            ),
            ChangeNotifierProvider<CarouselStateProvider>.value(
              value: carouselStateProvider,
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: custom_carousel.CarouselWidget(
                  controller: carouselProvider.midCarouselController,
                  showIndicators: false,
                  allowManualSwipe: false,
                  onPageChanged: carouselProvider.updateVisibleCarouselIndex,
                ),
              ),
            ),
          ),
        ),
      );

      final announcement = _announcement(
        mimeType: 'text/plain',
        fileType: 'txt',
        localFilePath: attachment.path,
      );

      carouselProvider.updateCarouselList([announcement]);
      await tester.pump();
      carouselProvider.jumpToAnnouncementIndex(2);
      await tester.pump();

      expect(carouselProvider.currentNoticeIndex, 2);

      carouselProvider.showIndependentAnnouncement(
        announcement,
        () => carouselProvider.jumpToAnnouncementIndex(0),
      );
      await tester.pump();
      expect(carouselProvider.isInIndependentAnnouncementMode, isTrue);

      carouselProvider.jumpToAnnouncementIndex(0);
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump();

      expect(carouselProvider.isInIndependentAnnouncementMode, isFalse);
      expect(carouselProvider.currentNoticeIndex, 0);
      expect(carouselProvider.visibleCarouselIndexListenable.value, 0);
    });
  });
}

AnnouncementModel _announcement({
  String title = 'Notice',
  DateTime? endTime,
  String fileMd5 = 'md5',
  String mimeType = 'application/pdf',
  String fileType = 'pdf',
  String? localFilePath,
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
    fileType: fileType,
    file: FileModel(
      id: 10,
      mimeType: mimeType,
      md5: fileMd5,
      url: 'https://example.test/notice.pdf',
      fileSize: 1024,
      localFilePath: localFilePath,
    ),
  );
}
