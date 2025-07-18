import 'dart:async'; // Added import for Timer

import 'package:flutter/foundation.dart'
    show listEquals; // Added import for listEquals
import 'package:flutter/material.dart' hide CarouselController;
import 'package:iboard_app/managers/managers.dart';
import 'package:iboard_app/models/ad_model.dart';
import 'package:iboard_app/models/announcement_model.dart';
import 'package:iboard_app/models/file_model.dart';
import 'package:iboard_app/providers/announcement_provider.dart';
import 'package:iboard_app/providers/app_data_provider.dart';
import 'package:iboard_app/widgets/carousel_widget.dart' as custom_carousel;
import 'package:iboard_app/widgets/mainscreen/bottom_display/weather_widget.dart';
import 'package:iboard_app/widgets/mainscreen/main_display/announcement_reader_widget.dart';
import 'package:iboard_app/widgets/mainscreen/main_display/mainscreen_widget.dart';
import 'package:iboard_app/widgets/mainscreen/top_ad_widget.dart';
import 'package:provider/provider.dart';

class AnnouncementPage extends StatefulWidget {
  @override
  _AnnouncementPageState createState() => _AnnouncementPageState();
}

class _AnnouncementPageState extends State<AnnouncementPage> {
  late custom_carousel.CarouselController _topCarouselController;
  late custom_carousel.CarouselController _midCarouselController;
  late custom_carousel.CarouselController _bottomCarouselController;

  Timer? _topTimer;
  Timer? _midTimer;
  Timer? _bottomTimer;
  List<AdModel> _topAds = [];
  List<AnnouncementModel>?
      _previousAnnouncementsForBuild; // Added state variable

  @override
  void initState() {
    super.initState();
    _topCarouselController = custom_carousel.CarouselController();
    _midCarouselController = custom_carousel.CarouselController();
    _bottomCarouselController = custom_carousel.CarouselController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeMidWidgets();
      _initializeTopWidgets();
      _initializeBottomWidgets();
    });
  }

  @override
  void dispose() {
    _topTimer?.cancel();
    _midTimer?.cancel();
    _bottomTimer?.cancel();
    super.dispose();
  }

  void _initializeMidWidgets() {
    final announcementProvider =
        Provider.of<AnnouncementProvider>(context, listen: false);
    List<AnnouncementModel> announcements = announcementProvider.announcements;

    // 创建带回调的主屏幕部件
    Widget mainScreenWidget = MainScreenWidget(
      onAnnouncementTap: (AnnouncementModel announcement) {
        // 查找announcement在列表中的索引
        int announcementIndex = announcements.indexOf(announcement);
        if (announcementIndex != -1) {
          // 计算在carousel中的实际索引（主屏幕是索引0，所以announcement从索引1开始）
          int carouselIndex = announcementIndex + 1;
          // 跳转到对应的公告页面
          _midCarouselController.jumpToIndex(carouselIndex);
          print(
              'Jumping to announcement at index: $carouselIndex (${announcement.title})');
        }
      },
    );

    List<Widget> announcementWidgets = announcements.map((announcement) {
      FileManager fileManager = FileManager();
      fileManager.getFile(announcement.file);
      return Center(
          child: AnnouncementReaderWidget(
        announcement: announcement,
        fileManager: fileManager,
        onHomeButtonPressed: () {
          // 主頁按鈕被按下時，跳轉到第一個項目（主屏幕）
          _midCarouselController.jumpToIndex(0);
        },
      ));
    }).toList();

    final midWidgets = [
      mainScreenWidget,
      ...announcementWidgets,
    ];
    _midCarouselController.setCarouselArray(midWidgets);

    _midTimer?.cancel();
    if (announcementWidgets.length > 1) {
      _midTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
        if (mounted && _midCarouselController.widgetCount > 1) {
          _midCarouselController.playNext();
        }
      });
    }
  }

  void _startTopAdTimer(int currentIndex) {
    _topTimer?.cancel();
    if (_topAds.length <= 1 ||
        currentIndex < 0 ||
        currentIndex >= _topAds.length) {
      return;
    }

    final ad = _topAds[currentIndex];
    _topTimer = Timer(ad.duration, () {
      if (mounted && _topCarouselController.widgetCount > 1) {
        _topCarouselController.playNext();
        // onPageChanged will then call _startTopAdTimer for the new page
      }
    });
  }

  void _initializeTopWidgets() {
    // Assuming you have an AdModel instance ready
    List<AdModel> adsData = [
      AdModel(
        title: 'Ad 1',
        description: 'This is the first ad',
        duration: Duration(seconds: 5),
        display: AdDisplayType.top,
        file: FileModel(
          id: 1, // Added dummy ID
          mimeType: 'image/png',
          url:
              'http://idreamsky.oss-cn-beijing.aliyuncs.com/2025-01-03/eec63ad5-a85e-47ef-b7d9-7a3ac0a77ea0.png',
          md5: 'dummy_md5_1', // Added dummy md5
          fileSize: 1024, // Added dummy fileSize
        ),
      ),
      AdModel(
        title: 'Ad 2',
        description: 'This is the second ad',
        duration: Duration(seconds: 5),
        display: AdDisplayType.top,
        file: FileModel(
          id: 2, // Added dummy ID
          mimeType: 'image/gif',
          url:
              'http://idreamsky.oss-cn-beijing.aliyuncs.com/2025-04-14/6c9f92ed-7290-462e-96dc-37615880d830.gif',
          md5: 'dummy_md5_2', // Added dummy md5
          fileSize: 2048, // Added dummy fileSize
        ),
      ),
      AdModel(
        title: 'Ad 3',
        description: 'This is the third ad',
        duration: Duration(seconds: 30), // Changed duration for testing
        display: AdDisplayType.top,
        file: FileModel(
          id: 3, // Added dummy ID
          mimeType: 'video/mp4',
          url:
              'http://idreamsky.oss-cn-beijing.aliyuncs.com/2025-04-23/57a1301f-0e5f-45f8-aa6d-77049487939d.mp4',
          md5: 'dummy_md5_3', // Added dummy md5
          fileSize: 30720, // Added dummy fileSize
        ),
      ),
    ];
    _topAds = adsData; // Store ads for timer logic

    // Create ad widgets from the AdModel instances
    List<Widget> adWidgets = _topAds.map((ad) {
      FileManager fileManager = FileManager();
      fileManager.getFile(ad.file);
      return Center(
        child: TopAdWidget(
          ad: ad,
          fileManager: fileManager,
        ),
      );
    }).toList();
    _topCarouselController.setCarouselArray(adWidgets);

    if (_topAds.length > 1) {
      _startTopAdTimer(0); // Start timer for the first ad
    }
  }

  void _initializeBottomWidgets() {
    final sampleWidgets = [const WeatherWidget()];
    _bottomCarouselController.setCarouselArray(sampleWidgets);

    _bottomTimer?.cancel();
    if (sampleWidgets.length > 1) {
      _bottomTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
        if (mounted && _bottomCarouselController.widgetCount > 1) {
          _bottomCarouselController.playNext();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen to AnnouncementProvider for changes
    final announcementProvider = context.watch<AnnouncementProvider>();
    final currentAnnouncements = announcementProvider.announcements;

    // If announcements have changed, re-initialize the mid widgets
    if (_previousAnnouncementsForBuild == null ||
        !listEquals(_previousAnnouncementsForBuild, currentAnnouncements)) {
      if (mounted) {
        // Ensure widget is still in the tree
        _initializeMidWidgets();
        _previousAnnouncementsForBuild =
            List.from(currentAnnouncements); // Update the stored list
      }
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 上部區域 - 6/24 比例
            Expanded(
              flex: 6,
              child: Container(
                  width: double.infinity,
                  child: custom_carousel.CarouselWidget(
                    controller: _topCarouselController,
                    // autoPlayDuration is effectively managed by _startTopAdTimer
                    showIndicators: false,
                    allowManualSwipe: false,
                    onPageChanged: (index) {
                      if (_topAds.length > 1) {
                        _startTopAdTimer(index);
                      }
                      // setState(() {
                      //   _topCurrentIndex = index;
                      // });
                    },
                  )),
            ),
            // 中部區域 - 14/24 比例
            Expanded(
              flex: 14,
              child: Container(
                  width: double.infinity,
                  color:
                      Colors.grey.shade50, // Background for the carousel area
                  child: custom_carousel.CarouselWidget(
                    controller: _midCarouselController,
                    showIndicators: false,
                    allowManualSwipe: false,
                    onPageChanged: (index) {},
                  )),
            ),
            // 底部區域 - 4/24 比例 (减少到3/24，为设备码预留空间)
            Expanded(
              flex: 3,
              child: Container(
                width: double.infinity,
                child: custom_carousel.CarouselWidget(
                  controller: _bottomCarouselController,
                  autoPlayDuration: const Duration(seconds: 10),
                  showIndicators: false,
                  allowManualSwipe: false,
                  onPageChanged: (index) {
                    // setState(() {
                    //   _bottomCurrentIndex = index;
                    // });
                  },
                ),
              ),
            ),
            // 设备码显示区域 - 1/24 比例
            Container(
              width: double.infinity,
              height: 30,
              color: Colors.grey.shade100,
              child: Consumer<AppDataProvider>(
                builder: (context, appDataProvider, child) {
                  return Center(
                    child: Text(
                      appDataProvider.deviceId != null 
                          ? '設備碼: ${appDataProvider.deviceId}' 
                          : '設備碼: 未設定',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
