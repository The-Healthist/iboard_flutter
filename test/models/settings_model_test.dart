import 'package:flutter_test/flutter_test.dart';
import 'package:iboard_app/models/settings_model.dart';

void main() {
  group('Settings.fromJson', () {
    test('parses numeric settings from strings and trims OrangePi IP', () {
      final settings = Settings.fromJson({
        'arrearageUpdateDuration': '30',
        'noticeUpdateDuration': '5',
        'advertisementUpdateDuration': '10',
        'appUpdateDuration': '60',
        'advertisementPlayDuration': '15',
        'noticeStayDuration': '8',
        'bottomCarouselDuration': '12',
        'paymentTableOnePageDuration': '20',
        'normalToAnnouncementCarouselDuration': '25',
        'announcementCarouselToFullAdsCarouselDuration': '40',
        'printPassword': 123456,
        'orangePiIp': ' 192.168.3.74 ',
      });

      expect(settings.arrearageUpdateDuration, 30);
      expect(settings.noticeUpdateDuration, 5);
      expect(settings.advertisementUpdateDuration, 10);
      expect(settings.appUpdateDuration, 60);
      expect(settings.advertisementPlayDuration, 15);
      expect(settings.noticeStayDuration, 8);
      expect(settings.bottomCarouselDuration, 12);
      expect(settings.paymentTableOnePageDuration, 20);
      expect(settings.normalToAnnouncementCarouselDuration, 25);
      expect(settings.announcementCarouselToFullAdsCarouselDuration, 40);
      expect(settings.printPassWord, '123456');
      expect(settings.orangePiIp, '192.168.3.74');
    });

    test('falls back when numeric settings are empty, invalid, or not positive',
        () {
      final settings = Settings.fromJson({
        'arrearageUpdateDuration': '',
        'noticeUpdateDuration': 'abc',
        'advertisementUpdateDuration': -1,
        'appUpdateDuration': 0,
        'advertisementPlayDuration': null,
        'noticeStayDuration': [],
        'bottomCarouselDuration': {},
        'paymentTableOnePageDuration': false,
        'normalToAnnouncementCarouselDuration': '-5',
        'announcementCarouselToFullAdsCarouselDuration': '0',
      });

      expect(settings.arrearageUpdateDuration, 30);
      expect(settings.noticeUpdateDuration, 5);
      expect(settings.advertisementUpdateDuration, 10);
      expect(settings.appUpdateDuration, 60);
      expect(settings.advertisementPlayDuration, 10);
      expect(settings.noticeStayDuration, 5);
      expect(settings.bottomCarouselDuration, 10);
      expect(settings.paymentTableOnePageDuration, 10);
      expect(settings.normalToAnnouncementCarouselDuration, 5);
      expect(settings.announcementCarouselToFullAdsCarouselDuration, 5);
      expect(settings.printPassWord, '1090119');
      expect(settings.orangePiIp, '');
    });
  });
}
