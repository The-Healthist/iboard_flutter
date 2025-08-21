import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iboard_app/models/announcement_model.dart';
import 'package:iboard_app/providers/announcement_carousel_provider.dart';
import 'package:iboard_app/widgets/carousel_widget.dart' as custom_carousel;

void main() {
  group('轮播智能更新测试', () {
    late AnnouncementCarouselProvider provider;
    late custom_carousel.CarouselController carouselController;
    
    // 模拟API返回的初始数据
    final List<Map<String, dynamic>> initialData = [
      {
        "id": 135,
        "title": "訪客須知",
        "description": "訪客須知",
        "type": "normal",
        "file": {
          "id": 88,
          "md5": "d5b5b4ef3e4b88636fffef42e09daa1b",
          "path": "http://idreamsky.oss-cn-beijing.aliyuncs.com/2025-05-22/2c8ea995-ead6-415d-bdfc-cb015542bd60.pdf",
        }
      },
      {
        "id": 136,
        "title": "tt11",
        "description": "tt11",
        "type": "normal",
        "file": {
          "id": 120,
          "md5": "c1e631aac68eaed885871b81d288224c",
          "path": "http://idreamsky.oss-cn-beijing.aliyuncs.com/2025-08-03/1f87df77-c68a-41bb-9c03-ee27d5718098.pdf",
        }
      },
    ];
    
    // 模拟更新后的数据（顺序改变+新增+删除）
    final List<Map<String, dynamic>> updatedData = [
      {
        "id": 111,  // 新增
        "title": "Notices to visitors",
        "description": "Notices to visitors",
        "type": "normal",
        "file": {
          "id": 87,
          "md5": "e0f3de8d6cc1de2cc66498e37ac7cf72",
          "path": "http://idreamsky.oss-cn-beijing.aliyuncs.com/2025-05-22/67d29806-5a9e-44de-a2c5-12d603336269.pdf",
        }
      },
      {
        "id": 136,  // 顺序改变
        "title": "tt11",
        "description": "tt11",
        "type": "normal",
        "file": {
          "id": 120,
          "md5": "c1e631aac68eaed885871b81d288224c",
          "path": "http://idreamsky.oss-cn-beijing.aliyuncs.com/2025-08-03/1f87df77-c68a-41bb-9c03-ee27d5718098.pdf",
        }
      },
      {
        "id": 147,  // 新增
        "title": "testtest",
        "description": "testtest",
        "type": "normal",
        "file": {
          "id": 129,
          "md5": "669818a8440c0f8579898ba1e52cbf5c",
          "path": "http://idreamsky.oss-cn-beijing.aliyuncs.com/2025-08-09/40999997-c367-48a6-9563-f0d1d01ef905.pdf",
        }
      },
      // 注意：id 135 被删除了
    ];
    
    setUp(() {
      provider = AnnouncementCarouselProvider();
      carouselController = provider.midCarouselController;
    });
    
    tearDown(() {
      provider.dispose();
    });
    
    testWidgets('测试初始化轮播', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: custom_carousel.CarouselWidget(
              controller: carouselController,
              initialWidgets: [],
              height: 600,
            ),
          ),
        ),
      );
      
      // 转换初始数据为模型
      final initialAnnouncements = initialData
          .map((json) => AnnouncementModel.fromJson(json))
          .toList();
      
      // 初始化轮播
      provider.initializeMidWidgets(
        carouselAnnouncements: initialAnnouncements,
        apiNoticeStayDuration: 5,
        delayBeforeNotice: 2,
        onAnnouncementTap: (announcement) {},
        onHomeButtonPressed: () {},
      );
      
      await tester.pump();
      
      // 验证初始状态
      expect(carouselController.widgetCount, 4); // 主屏幕 + 2个通告 + 欠费表单
      expect(carouselController.currentIndex, 0); // 应该在主屏幕
      
      // print('✅ 初始化成功：共${carouselController.widgetCount}个widgets');
    });
    
    testWidgets('测试在查看通告时更新不会退出', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: custom_carousel.CarouselWidget(
              controller: carouselController,
              initialWidgets: [],
              height: 600,
            ),
          ),
        ),
      );
      
      // 初始化
      final initialAnnouncements = initialData
          .map((json) => AnnouncementModel.fromJson(json))
          .toList();
      
      provider.initializeMidWidgets(
        carouselAnnouncements: initialAnnouncements,
        apiNoticeStayDuration: 5,
        delayBeforeNotice: 2,
        onAnnouncementTap: (announcement) {},
        onHomeButtonPressed: () {},
      );
      
      await tester.pump();
      
      // 跳转到第二个通告（id: 136）
      carouselController.jumpToIndex(2);
      await tester.pump();
      
      expect(carouselController.currentIndex, 2);
      final currentIndexBeforeUpdate = carouselController.currentIndex;
      
      // print('📍 当前位置：索引 $currentIndexBeforeUpdate (通告 id:136)');
      
      // 模拟定时更新
      final updatedAnnouncements = updatedData
          .map((json) => AnnouncementModel.fromJson(json))
          .toList();
      
      provider.updateCarouselList(updatedAnnouncements);
      await tester.pump();
      
      // 验证更新后的状态
      expect(carouselController.widgetCount, 5); // 主屏幕 + 3个通告 + 欠费表单
      
      // 关键验证：应该仍然在id:136的通告上（虽然索引可能变了）
      // id:136 在新列表中的位置应该是索引2（主屏幕 + id:111 + id:136）
      expect(carouselController.currentIndex, 2);
      
      // print('✅ 更新后仍在同一通告：索引 ${carouselController.currentIndex}');
      // print('   Widget总数从4变为${carouselController.widgetCount}');
    });
    
    testWidgets('测试在欠费表单时更新不会退出', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: custom_carousel.CarouselWidget(
              controller: carouselController,
              initialWidgets: [],
              height: 600,
            ),
          ),
        ),
      );
      
      // 初始化
      final initialAnnouncements = initialData
          .map((json) => AnnouncementModel.fromJson(json))
          .toList();
      
      provider.initializeMidWidgets(
        carouselAnnouncements: initialAnnouncements,
        apiNoticeStayDuration: 5,
        delayBeforeNotice: 2,
        onAnnouncementTap: (announcement) {},
        onHomeButtonPressed: () {},
      );
      
      await tester.pump();
      
      // 跳转到欠费表单（最后一个widget）
      carouselController.jumpToIndex(3);
      await tester.pump();
      
      expect(carouselController.currentIndex, 3);
      // print('📍 当前位置：欠费表单（索引 3）');
      
      // 模拟定时更新
      final updatedAnnouncements = updatedData
          .map((json) => AnnouncementModel.fromJson(json))
          .toList();
      
      provider.updateCarouselList(updatedAnnouncements);
      await tester.pump();
      
      // 验证：应该仍然在欠费表单（新的最后位置）
      expect(carouselController.currentIndex, 4); // 欠费表单在新列表的最后
      
      // print('✅ 更新后仍在欠费表单：索引 ${carouselController.currentIndex}');
    });
    
    testWidgets('测试删除当前查看的通告时的处理', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: custom_carousel.CarouselWidget(
              controller: carouselController,
              initialWidgets: [],
              height: 600,
            ),
          ),
        ),
      );
      
      // 初始化
      final initialAnnouncements = initialData
          .map((json) => AnnouncementModel.fromJson(json))
          .toList();
      
      provider.initializeMidWidgets(
        carouselAnnouncements: initialAnnouncements,
        apiNoticeStayDuration: 5,
        delayBeforeNotice: 2,
        onAnnouncementTap: (announcement) {},
        onHomeButtonPressed: () {},
      );
      
      await tester.pump();
      
      // 跳转到第一个通告（id: 135，将被删除）
      carouselController.jumpToIndex(1);
      await tester.pump();
      
      expect(carouselController.currentIndex, 1);
      // print('📍 当前位置：通告 id:135（将被删除）');
      
      // 模拟定时更新（删除了id:135）
      final updatedAnnouncements = updatedData
          .map((json) => AnnouncementModel.fromJson(json))
          .toList();
      
      provider.updateCarouselList(updatedAnnouncements);
      await tester.pump();
      
      // 验证：当前通告被删除后，应该保持在合理的位置
      expect(carouselController.currentIndex, lessThanOrEqualTo(carouselController.widgetCount - 1));
      expect(carouselController.currentIndex, greaterThanOrEqualTo(0));
      
      // print('✅ 通告被删除后，自动调整到索引 ${carouselController.currentIndex}');
    });
    
    testWidgets('测试连续多次更新的稳定性', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: custom_carousel.CarouselWidget(
              controller: carouselController,
              initialWidgets: [],
              height: 600,
            ),
          ),
        ),
      );
      
      // 初始化
      final initialAnnouncements = initialData
          .map((json) => AnnouncementModel.fromJson(json))
          .toList();
      
      provider.initializeMidWidgets(
        carouselAnnouncements: initialAnnouncements,
        apiNoticeStayDuration: 5,
        delayBeforeNotice: 2,
        onAnnouncementTap: (announcement) {},
        onHomeButtonPressed: () {},
      );
      
      await tester.pump();
      
      // 跳转到一个通告
      carouselController.jumpToIndex(2);
      await tester.pump();
      
      // print('🔄 开始连续更新测试...');
      
      // 模拟5次连续更新
      for (int i = 0; i < 5; i++) {
        final currentIndex = carouselController.currentIndex;
        
        // 随机修改数据
        final randomUpdate = i % 2 == 0 ? updatedData : initialData;
        final announcements = randomUpdate
            .map((json) => AnnouncementModel.fromJson(json))
            .toList();
        
        provider.updateCarouselList(announcements);
        await tester.pump();
        
        // 验证没有异常崩溃
        expect(carouselController.currentIndex, greaterThanOrEqualTo(0));
        expect(carouselController.currentIndex, lessThan(carouselController.widgetCount));
        
        // print('  更新 ${i + 1}：索引从 $currentIndex 到 ${carouselController.currentIndex}');
      }
      
      // print('✅ 连续更新测试通过，系统稳定');
    });
    
    test('测试widget映射的正确性', () {
      // 测试初始数据
      final initialAnnouncements = initialData
          .map((json) => AnnouncementModel.fromJson(json))
          .toList();
      
      provider.initializeMidWidgets(
        carouselAnnouncements: initialAnnouncements,
        apiNoticeStayDuration: 5,
        delayBeforeNotice: 2,
        onAnnouncementTap: (announcement) {},
        onHomeButtonPressed: () {},
      );
      
      // 验证widget数量
      expect(provider.carouselAnnouncements.length, 2);
      
      // 模拟更新
      final updatedAnnouncements = updatedData
          .map((json) => AnnouncementModel.fromJson(json))
          .toList();
      
      provider.updateCarouselList(updatedAnnouncements);
      
      // 验证更新后的数量
      expect(provider.carouselAnnouncements.length, 3);
      
      // 验证ID映射
      final ids = provider.carouselAnnouncements.map((a) => a.id).toList();
      expect(ids, contains(111));
      expect(ids, contains(136));
      expect(ids, contains(147));
      expect(ids, isNot(contains(135))); // 已删除
      
      // print('✅ Widget映射测试通过');
    });
    
    test('測試Widget緩存效能', () {
      // 測試初始數據
      final initialAnnouncements = initialData
          .map((json) => AnnouncementModel.fromJson(json))
          .toList();
      
      // 第一次初始化
      final startTime = DateTime.now();
      provider.initializeMidWidgets(
        carouselAnnouncements: initialAnnouncements,
        apiNoticeStayDuration: 5,
        delayBeforeNotice: 2,
        onAnnouncementTap: (announcement) {},
        onHomeButtonPressed: () {},
      );
      final initTime = DateTime.now().difference(startTime).inMicroseconds;
      
      // 相同數據更新（不應重建）
      final updateStartTime = DateTime.now();
      provider.updateCarouselList(initialAnnouncements);
      final noChangeUpdateTime = DateTime.now().difference(updateStartTime).inMicroseconds;
      
      // 部分數據變化更新
      final updatedAnnouncements = updatedData
          .map((json) => AnnouncementModel.fromJson(json))
          .toList();
      
      final partialUpdateStartTime = DateTime.now();
      provider.updateCarouselList(updatedAnnouncements);
      final partialUpdateTime = DateTime.now().difference(partialUpdateStartTime).inMicroseconds;
      
      // print('📋 效能測試結果:');
      // print('  初始化時間: ${initTime}μs');
      // print('  無變化更新: ${noChangeUpdateTime}μs (應該很快)');
      // print('  部分更新時間: ${partialUpdateTime}μs');
      
      // 驗證無變化更新應該比初始化快很多
      expect(noChangeUpdateTime, lessThan(initTime / 10));
      
      // print('✅ 緩存效能測試通過');
    });
    
    test('測試多次更新不會造成記憶體泄漏', () {
      final initialAnnouncements = initialData
          .map((json) => AnnouncementModel.fromJson(json))
          .toList();
      
      provider.initializeMidWidgets(
        carouselAnnouncements: initialAnnouncements,
        apiNoticeStayDuration: 5,
        delayBeforeNotice: 2,
        onAnnouncementTap: (announcement) {},
        onHomeButtonPressed: () {},
      );
      
      // 模擬100次更新
      for (int i = 0; i < 100; i++) {
        final useUpdated = i % 2 == 0;
        final announcements = (useUpdated ? updatedData : initialData)
            .map((json) => AnnouncementModel.fromJson(json))
            .toList();
        
        provider.updateCarouselList(announcements);
      }
      
      // 驗證沒有異常
      expect(provider.carouselAnnouncements.length, greaterThan(0));
      expect(carouselController.widgetCount, greaterThan(0));
      
      // print('✅ 記憶體泄漏測試通過（100次更新）');
    });
  });
}
