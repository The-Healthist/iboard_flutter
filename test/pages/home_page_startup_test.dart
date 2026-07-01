import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iboard_app/main.dart';
import 'package:iboard_app/managers/file_manager.dart';
import 'package:iboard_app/models/announcement_model.dart';
import 'package:iboard_app/models/settings_model.dart';
import 'package:iboard_app/providers/ad_full_carousel_provider.dart';
import 'package:iboard_app/providers/ad_top_carousel_provider.dart';
import 'package:iboard_app/providers/advertisement_provider.dart';
import 'package:iboard_app/providers/announcement_carousel_provider.dart';
import 'package:iboard_app/providers/announcement_provider.dart';
import 'package:iboard_app/providers/app_data_provider.dart';
import 'package:iboard_app/providers/app_update_provider.dart';
import 'package:iboard_app/providers/arrear_provider.dart';
import 'package:iboard_app/providers/printer_provider.dart';
import 'package:iboard_app/providers/state_provider.dart';
import 'package:iboard_app/providers/weather_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('HomePage startup can finish after the page is disposed',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'device_id': 'DEVICE_AB12CD34',
    });

    final initializeCompleter = Completer<void>();
    final appDataProvider = _BlockingAppDataProvider(initializeCompleter);
    final advertisementProvider = _FakeAdvertisementProvider(appDataProvider);
    final announcementProvider = _FakeAnnouncementProvider(appDataProvider);
    final weatherProvider = _FakeWeatherProvider();
    final arrearProvider = _FakeArrearProvider(appDataProvider);
    final carouselStateProvider = CarouselStateProvider();
    final topAdCarouselProvider = TopAdCarouselProvider();
    final fullscreenAdProvider = FullscreenAdProvider(appDataProvider);
    final announcementCarouselProvider = AnnouncementCarouselProvider();
    final updateProvider = AppUpdateProvider(
      currentVersionLoader: () async => {
        'version': '1.0.0',
        'buildNumber': '1',
      },
      appVersionLoader: () async => const <String, dynamic>{},
    );
    final printerProvider = PrinterProvider();

    addTearDown(() {
      appDataProvider.dispose();
      advertisementProvider.dispose();
      announcementProvider.dispose();
      weatherProvider.dispose();
      arrearProvider.dispose();
      carouselStateProvider.dispose();
      topAdCarouselProvider.dispose();
      fullscreenAdProvider.dispose();
      announcementCarouselProvider.dispose();
      updateProvider.dispose();
      printerProvider.dispose();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppDataProvider>.value(value: appDataProvider),
          ChangeNotifierProvider<CarouselStateProvider>.value(
            value: carouselStateProvider,
          ),
          ChangeNotifierProvider<AdvertisementProvider>.value(
            value: advertisementProvider,
          ),
          ChangeNotifierProvider<AnnouncementProvider>.value(
            value: announcementProvider,
          ),
          ChangeNotifierProvider<WeatherProvider>.value(value: weatherProvider),
          ChangeNotifierProvider<ArrearProvider>.value(value: arrearProvider),
          ChangeNotifierProvider<PrinterProvider>.value(value: printerProvider),
          ChangeNotifierProvider<TopAdCarouselProvider>.value(
            value: topAdCarouselProvider,
          ),
          ChangeNotifierProvider<FullscreenAdProvider>.value(
            value: fullscreenAdProvider,
          ),
          ChangeNotifierProvider<AnnouncementCarouselProvider>.value(
            value: announcementCarouselProvider,
          ),
          ChangeNotifierProvider<AppUpdateProvider>.value(
            value: updateProvider,
          ),
        ],
        child: MaterialApp(
          home: const HomePage(),
          routes: {
            '/main': (_) => const SizedBox.shrink(),
          },
        ),
      ),
    );
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    initializeCompleter.complete();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
  });
}

class _BlockingAppDataProvider extends AppDataProvider {
  _BlockingAppDataProvider(this.initializeCompleter)
      : super(baseUrl: 'http://example.test');

  final Completer<void> initializeCompleter;

  @override
  Future<void> initialize({String? deviceId}) => initializeCompleter.future;

  @override
  Settings? get deviceSettings => null;

  @override
  bool get isLoggedIn => false;

  @override
  void setArrearProvider(ArrearProvider? provider) {}

  @override
  void setCarouselStateProvider(CarouselStateProvider? provider) {}
}

class _FakeAdvertisementProvider extends AdvertisementProvider {
  _FakeAdvertisementProvider(AppDataProvider appDataProvider)
      : super(appDataProvider.apiClient, appDataProvider);

  @override
  Future<void> fetchAdvertisements({bool forceInit = false}) async {}

  @override
  void setCarouselProviders({
    TopAdCarouselProvider? topAdCarouselProvider,
    FullscreenAdProvider? fullscreenAdProvider,
  }) {}

  @override
  void startPeriodicUpdate() {}
}

class _FakeAnnouncementProvider extends AnnouncementProvider {
  _FakeAnnouncementProvider(AppDataProvider appDataProvider)
      : super(appDataProvider.apiClient, appDataProvider, FileManager());

  @override
  Future<void> fetchNotices({bool forceInit = false}) async {}

  @override
  List<AnnouncementModel> getCarouselAnnouncements() => [];

  @override
  void setCarouselProvider(AnnouncementCarouselProvider carouselProvider) {}

  @override
  void startPeriodicUpdate() {}
}

class _FakeWeatherProvider extends WeatherProvider {
  @override
  Future<void> fetchAllWeatherDataWithWarnings() async {}

  @override
  void startPeriodicUpdate({Duration interval = const Duration(hours: 2)}) {}

  @override
  void startWarningPeriodicUpdate({
    Duration interval = const Duration(minutes: 15),
  }) {}
}

class _FakeArrearProvider extends ArrearProvider {
  _FakeArrearProvider(AppDataProvider appDataProvider)
      : super(
          apiClient: appDataProvider.apiClient,
          appDataProvider: appDataProvider,
        );

  @override
  Future<void> fetchFeeData({bool reset = false, String? buildingId}) async {}

  @override
  Future<void> loadFromCache() async {}

  @override
  void startPeriodicUpdate({int? updateIntervalMinutes}) {}
}
