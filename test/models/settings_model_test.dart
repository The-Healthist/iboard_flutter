import 'package:flutter_test/flutter_test.dart';
import 'package:iboard_app/models/settings_model.dart';

void main() {
  group('SettingsModel.fromJson', () {
    test('parses login payload with string ids and invalid dates safely', () {
      final model = SettingsModel.fromJson({
        'message': 200,
        'token': 12345,
        'data': {
          'id': '7',
          'createdAt': 'invalid-date',
          'updatedAt': '2026-06-05T12:00:00.000Z',
          'deletedAt': 'not-a-date',
          'deviceId': 9988,
          'buildingId': '42',
          'status': true,
          'building': {
            'id': '11',
            'createdAt': 'bad-building-date',
            'updatedAt': '2026-06-05T12:30:00.000Z',
            'deletedAt': 'bad-deleted-date',
            'name': 123,
            'ismartId': 456,
            'remark': null,
            'location': true,
            'devices': 'not-a-list',
            'notices': ['notice'],
            'advertisements': ['ad'],
          },
          'settings': {
            'noticeUpdateDuration': '9',
          },
        },
      });

      expect(model.id, 7);
      expect(model.updatedAt, DateTime.parse('2026-06-05T12:00:00.000Z'));
      expect(model.deletedAt, isNull);
      expect(model.deviceId, '9988');
      expect(model.buildingId, 42);
      expect(model.status, 'true');
      expect(model.message, '200');
      expect(model.token, '12345');
      expect(model.building.id, 11);
      expect(
          model.building.updatedAt, DateTime.parse('2026-06-05T12:30:00.000Z'));
      expect(model.building.deletedAt, isNull);
      expect(model.building.name, '123');
      expect(model.building.ismartId, '456');
      expect(model.building.remark, '');
      expect(model.building.location, 'true');
      expect(model.building.devices, isNull);
      expect(model.building.notices, ['notice']);
      expect(model.building.advertisements, ['ad']);
      expect(model.settings.noticeUpdateDuration, 9);
    });

    test('uses safe defaults when data is not an object', () {
      final model = SettingsModel.fromJson({
        'data': 'unexpected',
      });

      expect(model.id, 0);
      expect(model.deviceId, '');
      expect(model.buildingId, 0);
      expect(model.status, '');
      expect(model.message, '');
      expect(model.token, '');
      expect(model.building.id, 0);
      expect(model.settings.noticeUpdateDuration, 5);
    });
  });

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
