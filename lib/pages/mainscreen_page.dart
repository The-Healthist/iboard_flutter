import 'dart:async'; // Added import for Timer

import 'package:flutter/foundation.dart'
    show listEquals; // Added import for listEquals
import 'package:flutter/material.dart' hide CarouselController;
import 'package:iboard_app/managers/managers.dart';
import 'package:iboard_app/models/ad_model.dart';
import 'package:iboard_app/models/announcement_model.dart';
import 'package:iboard_app/providers/advertisement_provider.dart';
import 'package:iboard_app/providers/announcement_provider.dart';
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

  // 轮播暂停状态管理 - 按区域分别控制
  bool _isTopCarouselPaused = false;
  bool _isMidCarouselPaused = false;
  bool _isBottomCarouselPaused = false;
  AppState? _previousAppState;

  /// 根据当前应用状态更新轮播暂停状态
  void _updateCarouselStateBasedOnAppState(AppState appState) {
    switch (appState) {
      case AppState.defaultState:
        // 默认状态：所有轮播都正常播放
        _isTopCarouselPaused = false;
        _isMidCarouselPaused = false;
        _isBottomCarouselPaused = false;
        break;
      case AppState.fullscreenAd:
        // 全屏广告状态：所有轮播都暂停
        _isTopCarouselPaused = true;
        _isMidCarouselPaused = true;
        _isBottomCarouselPaused = true;
        break;
      case AppState.manualOperation:
        // 手动操作状态：顶部和底部继续，中部暂停
        _isTopCarouselPaused = false;
        _isMidCarouselPaused = true;
        _isBottomCarouselPaused = false;
        break;
    }

    _logger.i(
        '🎛️ 轮播状态更新[${appState.name}]: Top=${!_isTopCarouselPaused ? "运行" : "暂停"}, Mid=${!_isMidCarouselPaused ? "运行" : "暂停"}, Bottom=${!_isBottomCarouselPaused ? "运行" : "暂停"}');
  }

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
    _logger.i('🛑 暂停所有轮播 - 进入全屏广告状态');

    // 设置所有轮播为暂停状态
    _isTopCarouselPaused = true;
    _isMidCarouselPaused = true;
    _isBottomCarouselPaused = true;

    // 暂停所有定时器
    _topTimer?.cancel();
    _midTimer?.cancel();
    _bottomTimer?.cancel();

    // 暂停所有轮播中的媒体内容
    _topCarouselController.pauseAllMedia();
    _midCarouselController.pauseAllMedia();
    _bottomCarouselController.pauseAllMedia();
  }

  /// 恢复所有轮播
  void _resumeAllCarousels() {
    _logger.i('▶️ 恢复所有轮播 - 退出全屏广告状态');

    // 设置所有轮播为运行状态
    _isTopCarouselPaused = false;
    _isMidCarouselPaused = false;
    _isBottomCarouselPaused = false;

    // 恢复所有轮播中的媒体内容
    _topCarouselController.resumeAllMedia();
    _midCarouselController.resumeAllMedia();
    _bottomCarouselController.resumeAllMedia();

    // 恢复顶部广告轮播
    if (_topAds.isNotEmpty) {
      _startTopAdTimer(0); // 从当前位置继续
    }

    // 恢复中部通告轮播
    if (_midCarouselController.widgetCount > 1 && !_isMidCarouselPaused) {
      _midTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
        if (mounted &&
            _midCarouselController.widgetCount > 1 &&
            !_isMidCarouselPaused) {
          _midCarouselController.playNext();
        }
      });
    }

    // 恢复底部轮播（如果有）
    if (_bottomCarouselController.widgetCount > 1 && !_isBottomCarouselPaused) {
      _bottomTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
        if (mounted &&
            _bottomCarouselController.widgetCount > 1 &&
            !_isBottomCarouselPaused) {
          _bottomCarouselController.playNext();
        }
      });
    }
  }

  /// 处理手动操作模式
  void _handleManualOperationMode() {
    _logger.i('🖱️ 进入手动操作模式 - 暂停通告轮播，恢复顶部和底部轮播');

    // 暂停中部通告轮播，但保持顶部和底部轮播
    _midTimer?.cancel();

    // 恢复顶部广告轮播（如果被暂停了）
    _logger.d(
        '🔍 检查顶部广告恢复条件: ads=${_topAds.length}, paused=$_isTopCarouselPaused');
    if (_topAds.isNotEmpty && !_isTopCarouselPaused) {
      _logger.d('✅ 满足条件，恢复顶部广告轮播');
      // 获取当前显示的广告索引
      int currentIndex = _topCarouselController.currentIndex;
      _logger.d('📍 当前顶部广告索引: $currentIndex');

      // 强制恢复顶部轮播的媒体播放（防止状态不同步）
      _topCarouselController.resumeAllMedia();

      _startTopAdTimer(currentIndex);
    } else {
      _logger
          .w('❌ 不满足恢复条件: ads=${_topAds.length}, paused=$_isTopCarouselPaused');
    }

    // 恢复底部轮播（如果被暂停了）
    if (_bottomCarouselController.widgetCount > 1 && !_isBottomCarouselPaused) {
      _bottomTimer?.cancel();
      _bottomTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
        if (mounted &&
            _bottomCarouselController.widgetCount > 1 &&
            !_isBottomCarouselPaused) {
          _bottomCarouselController.playNext();
        }
      });
    }
  }

  void _initializeMidWidgets() {
    final announcementProvider =
        Provider.of<AnnouncementProvider>(context, listen: false);
    // 使用轮播专用通告数组 - 只包含緊急和一般通告
    List<AnnouncementModel> carouselAnnouncements =
        announcementProvider.getCarouselAnnouncements();

    // 创建带回调的主屏幕部件
    Widget mainScreenWidget = MainScreenWidget(
      onAnnouncementTap: (AnnouncementModel announcement) {
        // 查找announcement在轮播通告列表中的索引
        int announcementIndex = carouselAnnouncements.indexOf(announcement);
        if (announcementIndex != -1) {
          // 计算在carousel中的实际索引（主屏幕是索引0，所以announcement从索引1开始）
          int carouselIndex = announcementIndex + 1;
          // 跳转到对应的公告页面
          _midCarouselController.jumpToIndex(carouselIndex);
          _logger.i(
              '跳转到轮播通告: $carouselIndex (${announcement.title}) - 类型: ${announcement.uiType}');
        } else {
          // 如果点击的通告不在轮播列表中（不是緊急或一般通告），提示用户
          _logger.w(
              '点击的通告不在轮播列表中: ${announcement.title} - 类型: ${announcement.uiType}');
        }
      },
    );

    // 只为轮播通告（緊急和一般）创建widget
    List<Widget> announcementWidgets =
        carouselAnnouncements.map((announcement) {
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

    _logger
        .i('初始化中部轮播: 主屏幕 + ${carouselAnnouncements.length} 个轮播通告 (只包含緊急和一般通告)');

    _midTimer?.cancel();
    if (announcementWidgets.length > 1 && !_isMidCarouselPaused) {
      _midTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
        if (mounted &&
            _midCarouselController.widgetCount > 1 &&
            !_isMidCarouselPaused) {
          _midCarouselController.playNext();
        }
      });
    }
  }

  void _startTopAdTimer(int currentIndex) {
    _logger.d(
        '🎬 开始顶部广告计时器: index=$currentIndex, ads=${_topAds.length}, paused=$_isTopCarouselPaused');
    _topTimer?.cancel();
    if (_topAds.length <= 1 ||
        currentIndex < 0 ||
        currentIndex >= _topAds.length ||
        _isTopCarouselPaused) {
      _logger.w(
          '⚠️ 顶部广告计时器条件不满足: ads=${_topAds.length}, index=$currentIndex, paused=$_isTopCarouselPaused');
      return;
    }

    final ad = _topAds[currentIndex];
    _logger.d('▶️ 启动顶部广告计时器: ${ad.title}, duration=${ad.durationObject}');
    _topTimer = Timer(ad.durationObject, () {
      if (mounted &&
          _topCarouselController.widgetCount > 1 &&
          !_isTopCarouselPaused) {
        _logger.d('⏭️ 顶部广告计时器到期，切换到下一个');
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
    if (sampleWidgets.length > 1 && !_isBottomCarouselPaused) {
      _bottomTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
        if (mounted &&
            _bottomCarouselController.widgetCount > 1 &&
            !_isBottomCarouselPaused) {
          _bottomCarouselController.playNext();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen to AnnouncementProvider for changes
    final announcementProvider = context.watch<AnnouncementProvider>();
    final currentCarouselAnnouncements =
        announcementProvider.carouselAnnouncements; // 监听轮播专用通告数组

    // Listen to AdvertisementProvider for changes
    final advertisementProvider = context.watch<AdvertisementProvider>();
    final currentAdvertisements = advertisementProvider.topAdvertisements;

    // Listen to CarouselStateProvider for fullscreen ad state changes
    final carouselStateProvider = context.watch<CarouselStateProvider>();
    final currentAppState = carouselStateProvider.currentAppState;

    // Handle state changes for carousel and media control
    if (_previousAppState != currentAppState) {
      // 更新轮播状态基于当前应用状态
      _updateCarouselStateBasedOnAppState(currentAppState);

      if (currentAppState == AppState.fullscreenAd) {
        _pauseAllCarousels();
      } else if (currentAppState == AppState.manualOperation) {
        _handleManualOperationMode();
      } else if (currentAppState == AppState.defaultState) {
        _resumeAllCarousels();
      }
      _previousAppState = currentAppState;
    }

    // If carousel announcements have changed, re-initialize the mid widgets
    // 现在监听轮播通告数组的变化而不是所有通告的变化
    if (_previousAnnouncementsForBuild == null ||
        !listEquals(
            _previousAnnouncementsForBuild, currentCarouselAnnouncements)) {
      if (mounted) {
        // Ensure widget is still in the tree
        _initializeMidWidgets();
        _previousAnnouncementsForBuild =
            List.from(currentCarouselAnnouncements); // 更新存储的轮播通告列表
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
            // 底部區域 - 4/24 比例
            Expanded(
              flex: 4,
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
          ],
        ),
      ),
    );
  }
}
