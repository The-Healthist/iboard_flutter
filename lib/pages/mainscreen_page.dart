import 'dart:async'; // Added import for Timer

import 'package:flutter/foundation.dart'
    show listEquals; // Added import for listEquals
import 'package:flutter/material.dart' hide CarouselController;
import 'package:iboard_app/managers/managers.dart';
import 'package:iboard_app/models/ad_model.dart';
import 'package:iboard_app/models/announcement_model.dart';
import 'package:iboard_app/providers/advertisement_provider.dart';
import 'package:iboard_app/providers/announcement_provider.dart';
import 'package:iboard_app/providers/app_data_provider.dart';
import 'package:iboard_app/providers/state_provider.dart';
import 'package:iboard_app/widgets/carousel_widget.dart' as custom_carousel;
import 'package:iboard_app/widgets/mainscreen/bottom_display/weather_widget.dart';
import 'package:iboard_app/widgets/mainscreen/main_display/announcement_reader_widget.dart';
import 'package:iboard_app/widgets/mainscreen/main_display/mainscreen_widget.dart';
import 'package:iboard_app/widgets/mainscreen/top_ad_widget.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';

class AnnouncementPage extends StatefulWidget {
  @override
  _AnnouncementPageState createState() => _AnnouncementPageState();
}

class _AnnouncementPageState extends State<AnnouncementPage> {
  final Logger _logger = Logger();
  late custom_carousel.CarouselController _topCarouselController;
  late custom_carousel.CarouselController _midCarouselController;
  late custom_carousel.CarouselController _bottomCarouselController;

  Timer? _topTimer;
  Timer? _midTimer;
  Timer? _bottomTimer;
  List<AdModel> _topAds = [];
  List<AnnouncementModel>?
      _previousAnnouncementsForBuild; // Added state variable
  List<AdModel>? _previousAdvertisementsForBuild; // Added for ad tracking

  // 轮播暂停状态管理
  bool _isCarouselPaused = false;
  AppState? _previousAppState;

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

      // Trigger data fetching
      final advertisementProvider =
          Provider.of<AdvertisementProvider>(context, listen: false);
      advertisementProvider.fetchAdvertisements();
    });
  }

  @override
  void dispose() {
    _topTimer?.cancel();
    _midTimer?.cancel();
    _bottomTimer?.cancel();
    super.dispose();
  }

  /// 暂停所有轮播
  void _pauseAllCarousels() {
    if (_isCarouselPaused) return;

    _logger.i('🛑 暂停所有轮播 - 进入全屏广告状态');
    _isCarouselPaused = true;

    // 暂停并保存当前状态
    _topTimer?.cancel();
    _midTimer?.cancel();
    _bottomTimer?.cancel();

    // 暂停所有轮播中的媒体内容
    _topCarouselController.pauseAllMedia();
    _midCarouselController.pauseAllMedia();
    _bottomCarouselController.pauseAllMedia();

    // 保存当前播放索引 (如果需要精确恢复位置)
    // 这里可以根据需要实现更精确的状态保存
  }

  /// 恢复所有轮播
  void _resumeAllCarousels() {
    if (!_isCarouselPaused) return;

    _logger.i('▶️ 恢复所有轮播 - 退出全屏广告状态');
    _isCarouselPaused = false;

    // 恢复所有轮播中的媒体内容
    _topCarouselController.resumeAllMedia();
    _midCarouselController.resumeAllMedia();
    _bottomCarouselController.resumeAllMedia();

    // 恢复顶部广告轮播
    if (_topAds.isNotEmpty) {
      _startTopAdTimer(0); // 从当前位置继续
    }

    // 恢复中部通告轮播
    if (_midCarouselController.widgetCount > 1 && !_isCarouselPaused) {
      _midTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
        if (mounted && _midCarouselController.widgetCount > 1 && !_isCarouselPaused) {
          _midCarouselController.playNext();
        }
      });
    }

    // 恢复底部轮播（如果有）
    if (_bottomCarouselController.widgetCount > 1 && !_isCarouselPaused) {
      _bottomTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
        if (mounted && _bottomCarouselController.widgetCount > 1 && !_isCarouselPaused) {
          _bottomCarouselController.playNext();
        }
      });
    }
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
    if (announcementWidgets.length > 1 && !_isCarouselPaused) {
      _midTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
        if (mounted && _midCarouselController.widgetCount > 1 && !_isCarouselPaused) {
          _midCarouselController.playNext();
        }
      });
    }
  }

  void _startTopAdTimer(int currentIndex) {
    _topTimer?.cancel();
    if (_topAds.length <= 1 ||
        currentIndex < 0 ||
        currentIndex >= _topAds.length ||
        _isCarouselPaused) {
      return;
    }

    final ad = _topAds[currentIndex];
    _topTimer = Timer(ad.durationObject, () {
      if (mounted && _topCarouselController.widgetCount > 1 && !_isCarouselPaused) {
        _topCarouselController.playNext();
        // onPageChanged will then call _startTopAdTimer for the new page
      }
    });
  }

  void _initializeTopWidgets() {
    final advertisementProvider =
        Provider.of<AdvertisementProvider>(context, listen: false);
    List<AdModel> topAds = advertisementProvider.topAdvertisements;

    if (topAds.isEmpty) {
      _logger.w('No top advertisements available');
      return;
    }

    _topAds = topAds; // Store ads for timer logic

    // Create ad widgets from the API AdModel instances
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
    if (sampleWidgets.length > 1 && !_isCarouselPaused) {
      _bottomTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
        if (mounted && _bottomCarouselController.widgetCount > 1 && !_isCarouselPaused) {
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

    // Listen to AdvertisementProvider for changes
    final advertisementProvider = context.watch<AdvertisementProvider>();
    final currentAdvertisements = advertisementProvider.topAdvertisements;

    // Listen to CarouselStateProvider for fullscreen ad state changes
    final carouselStateProvider = context.watch<CarouselStateProvider>();
    final currentAppState = carouselStateProvider.currentAppState;

    // Handle fullscreen ad state changes
    if (_previousAppState != currentAppState) {
      if (currentAppState == AppState.fullscreenAd) {
        _pauseAllCarousels();
      } else if (_previousAppState == AppState.fullscreenAd) {
        _resumeAllCarousels();
      }
      _previousAppState = currentAppState;
    }

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

    // If advertisements have changed, re-initialize the top widgets
    if (_previousAdvertisementsForBuild == null ||
        !listEquals(_previousAdvertisementsForBuild, currentAdvertisements)) {
      if (mounted) {
        _initializeTopWidgets();
        _previousAdvertisementsForBuild =
            List.from(currentAdvertisements); // Update the stored list
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
