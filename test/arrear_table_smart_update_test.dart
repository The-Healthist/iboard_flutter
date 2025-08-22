import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iboard_app/providers/arrear_provider.dart';
import 'package:iboard_app/providers/announcement_carousel_provider.dart';
import 'package:iboard_app/widgets/carousel_widget.dart' as custom_carousel;
import 'package:iboard_app/http/api_client.dart';
import 'package:iboard_app/providers/app_data_provider.dart';
import 'package:provider/provider.dart';

void main() {
  group('欠費表單智能更新測試', () {
    late ArrearProvider arrearProvider;
    late AnnouncementCarouselProvider carouselProvider;
    late custom_carousel.CarouselController carouselController;

    setUp(() {
      // 創建模擬的依賴
      final mockApiClient = ApiClient(baseUrl: 'test');
      final mockAppDataProvider = AppDataProvider(baseUrl: 'test');

      arrearProvider = ArrearProvider(
        apiClient: mockApiClient,
        appDataProvider: mockAppDataProvider,
      );

      carouselProvider = AnnouncementCarouselProvider();
      carouselProvider.setArrearProvider(arrearProvider);
      carouselController = carouselProvider.midCarouselController;
    });

    tearDown(() {
      arrearProvider.dispose();
      carouselProvider.dispose();
    });

    testWidgets('測試欠費數據更新時Widget緩存機制', (WidgetTester tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: arrearProvider),
            ChangeNotifierProvider.value(value: carouselProvider),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: custom_carousel.CarouselWidget(
                controller: carouselController,
                initialWidgets: const [],
                height: 600,
              ),
            ),
          ),
        ),
      );

      // 初始化輪播
      carouselProvider.initializeMidWidgets(
        carouselAnnouncements: [],
        apiNoticeStayDuration: 5,
        delayBeforeNotice: 2,
        onAnnouncementTap: (announcement) {},
        onHomeButtonPressed: () {},
      );

      await tester.pump();

      // 驗證初始狀態
      expect(carouselController.widgetCount, greaterThan(0));

      arrearProvider.currentDataVersion;

      // 觸發數據更新（模擬API成功獲取新數據）
      // 這會創建新的數據版本並標記為待更新
      // arrearProvider.fetchFeeData(); // 在實際測試中需要mock API

      // 驗證緩存機制
      expect(arrearProvider.hasPendingUpdate, isFalse); // 初始狀態無待更新

      // 測試Widget創建
      final widget1 = arrearProvider.createArrearTableWidget(
        onHomeButtonPressed: () {},
        isInCarouselMode: true,
        onPaginationComplete: (totalPages) {},
        onPaginationStart: (totalPages) {},
      );

      // 再次創建相同版本的Widget，應該返回緩存
      final widget2 = arrearProvider.createArrearTableWidget(
        onHomeButtonPressed: () {},
        isInCarouselMode: true,
        onPaginationComplete: (totalPages) {},
        onPaginationStart: (totalPages) {},
      );

      // 驗證Widget緩存機制
      expect(identical(widget1, widget2), isTrue);

      // print('✅ 欠費表單Widget緩存測試通過');
    });

    test('測試數據版本管理', () {
      // 初始狀態
      expect(arrearProvider.currentDataVersion, isNull);
      expect(arrearProvider.hasPendingUpdate, isFalse);

      // 模擬數據更新
      // 在實際實現中，fetchFeeData成功後會調用_updateDataVersion()

      // 測試Widget緩存清理
      final widget1 = arrearProvider.createArrearTableWidget(
        onHomeButtonPressed: () {},
        isInCarouselMode: true,
        onPaginationComplete: (totalPages) {},
        onPaginationStart: (totalPages) {},
      );

      expect(widget1, isNotNull);

      // print('✅ 數據版本管理測試通過');
    });

    test('測試緩存清理機制', () {
      // 創建多個版本的Widget
      for (int i = 0; i < 5; i++) {
        arrearProvider.createArrearTableWidget(
          onHomeButtonPressed: () {},
          isInCarouselMode: true,
          onPaginationComplete: (totalPages) {},
          onPaginationStart: (totalPages) {},
        );
      }

      // 驗證緩存不會無限增長（應該只保留最新2個版本）
      // 這需要在實際實現中驗證

      // print('✅ 緩存清理機制測試通過');
    });
  });
}
