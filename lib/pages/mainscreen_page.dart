import 'dart:async'; // Added import for Timer

import 'package:flutter/material.dart';
import 'package:iboard_app/models/ad_model.dart';
import 'package:iboard_app/models/announcement_model.dart';
import 'package:iboard_app/providers/advertisement_provider.dart';
import 'package:iboard_app/providers/announcement_provider.dart';
import 'package:iboard_app/providers/announcement_carousel_provider.dart';
import 'package:iboard_app/providers/app_data_provider.dart';
import 'package:iboard_app/providers/state_provider.dart';
import 'package:iboard_app/providers/ad_top_carousel_provider.dart';
import 'package:iboard_app/providers/ad_full_carousel_provider.dart';
import 'package:iboard_app/providers/weather_provider.dart';
import 'package:iboard_app/providers/rthk_news_provider.dart';
import 'package:iboard_app/widgets/carousel/carousel_widget.dart'
    as custom_carousel;
import 'package:iboard_app/widgets/mainscreen/bottom_display/bottom_display_widget.dart';
import 'package:iboard_app/widgets/news/rthk_news_ticker_widget.dart';
import 'package:iboard_app/pages/settings_page.dart';
import 'package:provider/provider.dart';
import 'package:iboard_app/providers/arrear_provider.dart';

class AnnouncementPage extends StatefulWidget {
  const AnnouncementPage({super.key});

  @override
  AnnouncementPageState createState() => AnnouncementPageState();
}

class AnnouncementPageState extends State<AnnouncementPage> {
  late custom_carousel.CarouselController _bottomCarouselController;

  Timer? _bottomTimer;
  Timer? _debugTimer; // 添加调试定时器
  Timer? _watchdogTimer; // 添加监控定时器
  List<AnnouncementModel>?
      _previousAnnouncementsForBuild; // Added state variable
  List<AdModel>? _previousAdvertisementsForBuild; // Added for ad tracking

  // 轮播暂停状态管理 - 按区域分别控制
  bool _isBottomCarouselPaused = false;
  AppState? _previousAppState;
  AppState? _lastLoggedAppState; // 添加用于追踪上次记录的应用状态
  String? _previousAnnouncementSignature;
  String? _previousAdvertisementSignature;

  // 设备ID点击计数相关
  int _deviceIdClickCount = 0; // 设备ID点击次数
  Timer? _clickResetTimer; // 点击重置定时器

  // 欠费组件的GlobalKey，用于调用组件方法
  // ArrearDisplayWidget已删除，功能整合到MainScreenWidget
  late ArrearProvider _arrearProvider;

  ///1， 根据当前应用状态更新轮播暂停状态
  void _updateCarouselStateBasedOnAppState(AppState appState) {
    // 使用 addPostFrameCallback 延迟执行状态更新，避免在构建过程中调用 setState()
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final topAdProvider = context.read<TopAdCarouselProvider>();
      final announcementCarouselProvider =
          context.read<AnnouncementCarouselProvider>();
      final bottomProvider = context.read<WeatherProvider>();

      // 检查状态是否发生变化
      if (_previousAppState != appState) {
        _previousAppState = appState;

        //  修复：只有从全屏广告切换到手动操作状态时才跳转到主屏幕
        // 从全屏广告直接切换到默认状态时，应该保持当前轮播位置
        if (_previousAppState == AppState.fullscreenAd &&
            appState == AppState.manualOperation) {
          //  在跳转到主屏幕前保存当前轮播索引
          announcementCarouselProvider.saveManualOperationState();
          announcementCarouselProvider.jumpToAnnouncementIndex(0);
        }
      }

      switch (appState) {
        case AppState.defaultState:
          // 默认状态：所有轮播都正常播放
          topAdProvider.updateCarouselPauseState(false);
          announcementCarouselProvider.updateCarouselPauseState(false);
          bottomProvider.updateCarouselPauseState(false);
          _isBottomCarouselPaused = false;
          break;
        case AppState.fullscreenAd:
          // 全屏广告状态：所有轮播都暂停
          topAdProvider.updateCarouselPauseState(true);
          announcementCarouselProvider.updateCarouselPauseState(true);
          bottomProvider.updateCarouselPauseState(true);
          _isBottomCarouselPaused = true;
          break;
        case AppState.manualOperation:
          // 手动操作状态：顶部和底部继续，中部暂停
          topAdProvider.updateCarouselPauseState(false);
          announcementCarouselProvider.updateCarouselPauseState(true);
          bottomProvider.updateCarouselPauseState(false);
          _isBottomCarouselPaused = false;
          break;
      }
    });
  }

  @override

  ///2， 初始化状态
  void initState() {
    super.initState();

    _bottomCarouselController = custom_carousel.CarouselController();
    _arrearProvider = Provider.of<ArrearProvider>(context, listen: false);

    final announcementCarouselProvider =
        Provider.of<AnnouncementCarouselProvider>(context, listen: false);
    announcementCarouselProvider.setArrearProvider(_arrearProvider);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final carouselStateProvider = context.read<CarouselStateProvider>();
      carouselStateProvider.enterDefaultState();

      _setupProviderReferences();
      _initializeTopWidgets();
      _initializeBottomWidgets();
      _initializeNewsAnnouncements();
      _startDebugTimer();
      _startCarouselWatchdog();

      //  初始化时主动获取费用数据，确保轮播内容完整
      _arrearProvider.initGetFeeData().then((_) {
        // 费用数据加载完成后，重新初始化中部轮播以包含费用表格
        _initializeMidWidgets();
      }).catchError((error) {});

      // Trigger data fetching
      final advertisementProvider =
          Provider.of<AdvertisementProvider>(context, listen: false);
      advertisementProvider.fetchAdvertisements();
    });
  }

  ///2.1，初始化RTHK新闻
  void _initializeNewsAnnouncements() {
    final rthkNewsProvider = context.read<RthkNewsProvider>();
    // 启动RTHK新闻的定时更新
    rthkNewsProvider.fetchRthkNews();
  }

  ///2.3，设置Provider引用
  void _setupProviderReferences() {
    final stateProvider = context.read<CarouselStateProvider>();
    final topAdProvider = context.read<TopAdCarouselProvider>();
    final fullscreenAdProvider = context.read<FullscreenAdProvider>(); //  新增
    final announcementCarouselProvider =
        context.read<AnnouncementCarouselProvider>(); //  新增
    final rthkNewsProvider = context.read<RthkNewsProvider>();

    // 设置顶部广告轮播Provider引用（修复音视频不同步问题）
    stateProvider.setTopCarouselProvider(topAdProvider);

    //  重要修复：设置全屏广告轮播Provider引用
    stateProvider.setFullscreenAdProvider(fullscreenAdProvider);

    //  关键修复：设置通告轮播Provider引用
    stateProvider.setAnnouncementCarouselProvider(announcementCarouselProvider);

    // 设置RTHK新闻Provider引用（用于直接控制跑马灯暂停恢复）
    stateProvider.setRthkNewsProvider(rthkNewsProvider);
  }

  @override

  ///3， 释放资源
  void dispose() {
    _bottomTimer?.cancel();
    _bottomTimer = null;

    _debugTimer?.cancel();
    _debugTimer = null;

    _watchdogTimer?.cancel();
    _watchdogTimer = null;

    _clickResetTimer?.cancel();
    _clickResetTimer = null;

    super.dispose();
  }

  ///4，启动调试定时器 - 每秒输出轮播的实时状态
  void _startDebugTimer() {
    _debugTimer?.cancel();

    // 启动通告轮播调试定时器（只启动一次）
    final announcementCarouselProvider =
        context.read<AnnouncementCarouselProvider>();
    final carouselStateProvider = context.read<CarouselStateProvider>();
    final apiNoticeStayDuration = carouselStateProvider.noticeStayDuration;
    announcementCarouselProvider.startDebugTimer(apiNoticeStayDuration);

    _debugTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;

      final currentAppState = carouselStateProvider.currentAppState;

      // 只在应用状态变化时输出日志
      if (_lastLoggedAppState != currentAppState) {
        _lastLoggedAppState = currentAppState;
      }
    });
  }

  ///5， 进入全屏广告状态，暂停所有轮播
  void _pauseAllCarousels() {
    final fullAdCarouselProvider =
        Provider.of<FullscreenAdProvider>(context, listen: false);
    final topAdCarouselProvider =
        Provider.of<TopAdCarouselProvider>(context, listen: false);
    final announcementCarouselProvider =
        Provider.of<AnnouncementCarouselProvider>(context, listen: false);
    final stateProvider =
        Provider.of<CarouselStateProvider>(context, listen: false);

    // 暂停顶部广告轮播
    topAdCarouselProvider.pauseTopCarousel();

    // 暂停通告轮播
    announcementCarouselProvider.pauseMidCarousel();

    // 启动全屏广告轮播
    fullAdCarouselProvider.enterFullscreenMode();

    // 设置日志输出标志 - 全屏广告模式下只显示全屏广告的日志
    fullAdCarouselProvider.startDebugTimer();
    announcementCarouselProvider.startDebugTimer(
        stateProvider.noticeStayDuration,
        enableLogging: false);
  }

  ///5.1，进入设置页面前暂停所有轮播和计时器
  void _pauseAllCarouselsForSettings() {
    final topAdProvider = context.read<TopAdCarouselProvider>();
    final announcementCarouselProvider =
        context.read<AnnouncementCarouselProvider>();
    final fullAdCarouselProvider = context.read<FullscreenAdProvider>();
    final bottomProvider = context.read<WeatherProvider>();

    // 暂停顶部广告计时器
    topAdProvider.pauseAllTimersForSettings();

    // 暂停通告轮播计时器
    announcementCarouselProvider.pauseAllTimersForSettings();

    // 暂停底部天气二维码轮播计时器
    bottomProvider.pauseAllTimersForSettings();

    // 暂停全屏广告轮播（如果活跃状态）
    if (fullAdCarouselProvider.isActive) {
      fullAdCarouselProvider.pauseCarousel();
      fullAdCarouselProvider.stopDebugTimer();
    }

    // 暂停其他定时器
    _bottomTimer?.cancel();
    _debugTimer?.cancel();
    _watchdogTimer?.cancel();

    // 暂停其他轮播中的媒体内容
    _bottomCarouselController.pauseAllMedia();

    // 设置其他轮播为暂停状态
    _isBottomCarouselPaused = true;

    // 暂停全屏广告计时器（通过设置状态为手动操作模式）
    final carouselStateProvider = context.read<CarouselStateProvider>();
    carouselStateProvider.enterManualOperation();
  }

  ///6，正常退出全屏广告状态，恢复所有轮播
  void _resumeAllCarousels() {
    final fullAdCarouselProvider =
        Provider.of<FullscreenAdProvider>(context, listen: false);

    final announcementCarouselProvider =
        Provider.of<AnnouncementCarouselProvider>(context, listen: false);
    final stateProvider =
        Provider.of<CarouselStateProvider>(context, listen: false);

    //  修复：判断是否从手动操作状态恢复
    final isFromManual = _previousAppState == AppState.manualOperation;

    // 恢复通告轮播 - 根据上一个状态决定是否为手动操作恢复
    announcementCarouselProvider.resumeMidCarousel(
        stateProvider.noticeStayDuration,
        isFromManualOperation: isFromManual);

    // 设置日志输出标志 - 默认状态下只显示顶部广告和通告轮播的日志
    fullAdCarouselProvider.startDebugTimer();
    announcementCarouselProvider
        .startDebugTimer(stateProvider.noticeStayDuration, enableLogging: true);
  }

  ///6.1，启动持续通告轮播（独立方法以确保一致性）- 真正的无限循环
  ///6，启动轮播监控定时器（检测并自动恢复中断的轮播）
  void _startCarouselWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final carouselStateProvider = context.read<CarouselStateProvider>();
      final currentAppState = carouselStateProvider.currentAppState;
      final announcementCarouselProvider =
          context.read<AnnouncementCarouselProvider>();

      // 只在默认状态下检查通告轮播
      if (currentAppState == AppState.defaultState &&
          !announcementCarouselProvider.isMidCarouselPaused) {
        final apiNoticeStayDuration = carouselStateProvider.noticeStayDuration;
        announcementCarouselProvider
            .checkAndRestoreMidCarousel(apiNoticeStayDuration);
      }
    });
  }

  ///6，进入手动操作模式
  void _handleManualOperationMode() {
    final announcementCarouselProvider =
        context.read<AnnouncementCarouselProvider>();

    // 暂停中部通告轮播
    announcementCarouselProvider.pauseMidCarousel();

    // 恢复顶部广告轮播（如果被暂停了）
    // final topAdProvider = context.read<TopAdCarouselProvider>();
    // // 确保顶部广告能够立即恢复视频播放和轮播
    // if (topAdProvider.isTopCarouselPaused) {
    //   topAdProvider.resumeTopCarousel();
    // } else {
    //   topAdProvider.checkAndRestoreTopCarousel();
    // }

    // 恢复底部轮播（如果被暂停了）
    if (_bottomCarouselController.widgetCount > 1 && !_isBottomCarouselPaused) {
      _bottomTimer?.cancel();

      // 从设置中获取底部轮播时间，默认为10秒
      final appDataProvider = context.read<AppDataProvider>();
      final deviceSettings = appDataProvider.deviceSettings;
      final bottomCarouselDuration =
          deviceSettings?.bottomCarouselDuration ?? 10;

      _bottomTimer =
          Timer.periodic(Duration(seconds: bottomCarouselDuration), (timer) {
        if (mounted &&
            _bottomCarouselController.widgetCount > 1 &&
            !_isBottomCarouselPaused) {
          _bottomCarouselController.playNext();
        }
      });
    }
  }

  ///8，初始化中部轮播
  void _initializeMidWidgets() {
    final announcementProvider =
        Provider.of<AnnouncementProvider>(context, listen: false);
    final carouselStateProvider = context.read<CarouselStateProvider>();
    final announcementCarouselProvider =
        context.read<AnnouncementCarouselProvider>();

    // 使用轮播专用通告数组 - 只包含緊急和一般通告
    List<AnnouncementModel> carouselAnnouncements =
        announcementProvider.getCarouselAnnouncements();

    // 获取API配置的通告停留时间
    final apiNoticeStayDuration = carouselStateProvider.noticeStayDuration;
    final delayBeforeNotice =
        carouselStateProvider.announcementCarouselToFullAdsCarouselDuration;

    // 即使没有通告数据也要初始化轮播组件，确保主屏幕能正常显示
    carouselStateProvider.enterDefaultState();
    // 初始化通告轮播
    announcementCarouselProvider.initializeMidWidgets(
      carouselAnnouncements: carouselAnnouncements,
      apiNoticeStayDuration: apiNoticeStayDuration,
      delayBeforeNotice: delayBeforeNotice,
      onAnnouncementTap: (AnnouncementModel? announcement) {
        if (announcement == null) {
          // 点击主屏幕时，不改变应用状态，保持轮播继续
          debugPrint('[MainScreenPage] 点击主屏幕，保持轮播状态');
        } else {
          announcementCarouselProvider.showIndependentAnnouncement(announcement,
              () {
            announcementCarouselProvider.jumpToAnnouncementIndex(0);
          });
          // 显示独立通告时也不进入手动模式，让轮播继续
          debugPrint('[MainScreenPage] 显示独立通告，保持轮播状态');
        }
      },
      onHomeButtonPressed: () {
        announcementCarouselProvider.jumpToAnnouncementIndex(0);
      },
    );
  }

  ///9，初始化顶部轮播
  void _initializeTopWidgets() {
    final advertisementProvider =
        Provider.of<AdvertisementProvider>(context, listen: false);
    final topAdProvider = context.read<TopAdCarouselProvider>();

    // 優先使用輪播專用的緩存數據
    List<AdModel> topAds = advertisementProvider.topCarouselAdvertisements;

    // 如果輪播數據為空，則使用舊的廣告數據作為後備
    if (topAds.isEmpty) {
      topAds = advertisementProvider.topAdvertisements;
    }

    if (topAds.isNotEmpty) {
      topAdProvider.initializeTopWidgets(topAds);
    }
  }

  ///10，初始化底部轮播
  void _initializeBottomWidgets() {
    // 底部轮播现在由BottomWeatherQrcodeNewsCarouselProvider管理
    final bottomProvider = context.read<WeatherProvider>();
    bottomProvider.initializeBottomCarousel();
  }

  ///11，处理设备ID点击事件
  void _handleDeviceIdClick() {
    _deviceIdClickCount++;

    // 取消之前的重置定时器
    _clickResetTimer?.cancel();

    if (_deviceIdClickCount >= 8) {
      // 达到8次点击，进入设置页面
      _deviceIdClickCount = 0; // 重置计数

      // 进入设置页面前暂停所有轮播和计时器
      _pauseAllCarouselsForSettings();

      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const SettingsPage()),
      );
    } else {
      // 设置5秒后重置计数器
      _clickResetTimer = Timer(const Duration(seconds: 5), () {
        _deviceIdClickCount = 0;
      });
    }
  }

  void _handleAppStateChange(AppState currentAppState) {
    if (_previousAppState == currentAppState) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      _updateCarouselStateBasedOnAppState(currentAppState);

      if (currentAppState == AppState.fullscreenAd) {
        _pauseAllCarousels();
      } else if (currentAppState == AppState.manualOperation) {
        _handleManualOperationMode();
      } else if (currentAppState == AppState.defaultState) {
        _resumeAllCarousels();
      }
    });

    _previousAppState = currentAppState;
  }

  void _handleAnnouncementDataChange(_AnnouncementListenerData data) {
    if (_previousAnnouncementSignature == data.signature) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final currentCarouselAnnouncements = data.carouselAnnouncements;
      final bool shouldUpdate = currentCarouselAnnouncements.isNotEmpty ||
          _previousAnnouncementsForBuild == null ||
          (_previousAnnouncementsForBuild != null &&
              _previousAnnouncementsForBuild!.isNotEmpty &&
              currentCarouselAnnouncements.isEmpty);

      if (shouldUpdate) {
        try {
          _initializeMidWidgets();
          _previousAnnouncementsForBuild =
              List.from(currentCarouselAnnouncements);
          _previousAnnouncementSignature = data.signature;
        } catch (e) {
          debugPrint('[MainScreenPage] 初始化中部轮播失败，保持现有状态: $e');
        }
      } else if (data.error != null) {
        debugPrint('[MainScreenPage] 通告获取错误: ${data.error}');
      }
    });
  }

  void _handleAdvertisementDataChange(_AdvertisementListenerData data) {
    if (_previousAdvertisementSignature == data.signature) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final currentAdvertisements = data.topAdvertisements;
      if (currentAdvertisements.isNotEmpty ||
          _previousAdvertisementsForBuild == null) {
        try {
          _initializeTopWidgets();

          final fullAdCarouselProvider = context.read<FullscreenAdProvider>();
          fullAdCarouselProvider.updateFullscreenAds(data.fullAdvertisements);

          _previousAdvertisementsForBuild = List.from(currentAdvertisements);
          _previousAdvertisementSignature = data.signature;
        } catch (e) {
          debugPrint('[MainScreenPage] 初始化顶部轮播失败，保持现有状态: $e');
        }
      } else if (data.error != null) {
        debugPrint('[MainScreenPage] 广告获取错误: ${data.error}');
      }
    });
  }

  @override

  ///12，处理视频播放器的初始化和播放
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            const _AnnouncementDataListener(),
            const _AdvertisementDataListener(),
            const _AppStateListener(),
            Column(
              children: [
                // 上部區域 - 6/24 比例
                Expanded(
                  flex: 6,
                  child: RepaintBoundary(
                    child: SizedBox(
                        width: double.infinity,
                        child: Consumer<TopAdCarouselProvider>(
                            builder: (context, topAdProvider, child) {
                          return custom_carousel.CarouselWidget(
                            controller: topAdProvider.topCarouselController,
                            // autoPlayDuration is effectively managed by _startTopAdTimer
                            showIndicators: false,
                            allowManualSwipe: false,
                            onPageChanged: (index) {
                              if (topAdProvider.topAds.length > 1) {
                                topAdProvider.onPageChanged(index);
                              }
                              // setState(() {
                              //   _topCurrentIndex = index;
                              // });
                            },
                          );
                        })),
                  ),
                ),
                // 中部區域 - 14/24 比例
                Expanded(
                  flex: 14,
                  child: RepaintBoundary(
                    child: Container(
                      width: double.infinity,
                      color: Colors.grey.shade50,
                      child: Stack(
                        children: [
                          // 轮播内容 - 始终存在，不被销毁
                          Consumer<AnnouncementCarouselProvider>(
                            builder:
                                (context, announcementCarouselProvider, child) {
                              return custom_carousel.CarouselWidget(
                                controller: announcementCarouselProvider
                                    .midCarouselController,
                                showIndicators: false,
                                allowManualSwipe: false,
                                onPageChanged: (index) {
                                  announcementCarouselProvider
                                      .updateVisibleCarouselIndex(index);
                                },
                              );
                            },
                          ),
                          // 欠费查询覆盖层 - 已删除，功能整合到MainScreenWidget
                        ],
                      ),
                    ),
                  ),
                ),
                // 底部區域 - 4/24 比例 (天气和二维码轮播区域)
                Expanded(
                  flex: 4,
                  child: SizedBox(
                    width: double.infinity,
                    child: Column(
                      children: [
                        // 新闻跑马灯 - 1/8 比例
                        RepaintBoundary(
                          child: Container(
                            height: 40,
                            width: double.infinity,
                            margin: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return RthkNewsTickerWidget(
                                  height: 40,
                                  width: constraints.maxWidth,
                                );
                              },
                            ),
                          ),
                        ),
                        // 底部轮播 - 7/8 比例
                        const Expanded(
                          child: RepaintBoundary(
                            child: BottomDisplayWidget(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // 设备ID显示区域 - 1/24 比例
                Container(
                  width: double.infinity,
                  height: 20,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Center(
                    child: GestureDetector(
                      onTap: _handleDeviceIdClick,
                      child: Selector<AppDataProvider, String?>(
                        selector: (_, appDataProvider) =>
                            appDataProvider.deviceId,
                        builder: (context, deviceId, child) {
                          return Text(
                            deviceId != null ? '設備ID: $deviceId' : '設備ID: 未知',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AppStateListener extends StatelessWidget {
  const _AppStateListener();

  @override
  Widget build(BuildContext context) {
    return Selector<CarouselStateProvider, AppState>(
      selector: (_, provider) => provider.currentAppState,
      builder: (context, appState, child) {
        context
            .findAncestorStateOfType<AnnouncementPageState>()
            ?._handleAppStateChange(appState);
        return const SizedBox.shrink();
      },
    );
  }
}

class _AnnouncementDataListener extends StatelessWidget {
  const _AnnouncementDataListener();

  @override
  Widget build(BuildContext context) {
    return Selector<AnnouncementProvider, _AnnouncementListenerData>(
      selector: (_, provider) => _AnnouncementListenerData(
        carouselAnnouncements: provider.carouselAnnouncements,
        error: provider.error,
      ),
      builder: (context, data, child) {
        context
            .findAncestorStateOfType<AnnouncementPageState>()
            ?._handleAnnouncementDataChange(data);
        return const SizedBox.shrink();
      },
    );
  }
}

class _AdvertisementDataListener extends StatelessWidget {
  const _AdvertisementDataListener();

  @override
  Widget build(BuildContext context) {
    return Selector<AdvertisementProvider, _AdvertisementListenerData>(
      selector: (_, provider) => _AdvertisementListenerData(
        topAdvertisements: provider.topCarouselAdvertisements.isNotEmpty
            ? provider.topCarouselAdvertisements
            : provider.topAdvertisements,
        fullAdvertisements: provider.fullCarouselAdvertisements.isNotEmpty
            ? provider.fullCarouselAdvertisements
            : provider.fullAdvertisements,
        error: provider.error,
      ),
      builder: (context, data, child) {
        context
            .findAncestorStateOfType<AnnouncementPageState>()
            ?._handleAdvertisementDataChange(data);
        return const SizedBox.shrink();
      },
    );
  }
}

@immutable
class _AnnouncementListenerData {
  final List<AnnouncementModel> carouselAnnouncements;
  final String? error;
  final String signature;

  _AnnouncementListenerData({
    required List<AnnouncementModel> carouselAnnouncements,
    required this.error,
  })  : carouselAnnouncements = List.unmodifiable(carouselAnnouncements),
        signature = carouselAnnouncements.map(_announcementSignature).join('|');

  @override
  bool operator ==(Object other) {
    return other is _AnnouncementListenerData &&
        other.signature == signature &&
        other.error == error;
  }

  @override
  int get hashCode => Object.hash(signature, error);
}

@immutable
class _AdvertisementListenerData {
  final List<AdModel> topAdvertisements;
  final List<AdModel> fullAdvertisements;
  final String? error;
  final String signature;

  _AdvertisementListenerData({
    required List<AdModel> topAdvertisements,
    required List<AdModel> fullAdvertisements,
    required this.error,
  })  : topAdvertisements = List.unmodifiable(topAdvertisements),
        fullAdvertisements = List.unmodifiable(fullAdvertisements),
        signature = [
          topAdvertisements.map(_adSignature).join('|'),
          fullAdvertisements.map(_adSignature).join('|'),
        ].join('::');

  @override
  bool operator ==(Object other) {
    return other is _AdvertisementListenerData &&
        other.signature == signature &&
        other.error == error;
  }

  @override
  int get hashCode => Object.hash(signature, error);
}

String _announcementSignature(AnnouncementModel announcement) {
  return [
    announcement.id,
    announcement.title,
    announcement.description,
    announcement.file.url,
    announcement.file.localFilePath,
  ].join(':');
}

String _adSignature(AdModel ad) {
  return [
    ad.id,
    ad.title,
    ad.file.url,
    ad.file.localFilePath,
    ad.duration,
  ].join(':');
}
