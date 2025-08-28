import 'dart:async'; // Added import for Timer

import 'package:flutter/foundation.dart'
    show listEquals; // Added import for listEquals
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
import 'package:iboard_app/widgets/carousel_widget.dart' as custom_carousel;
import 'package:iboard_app/widgets/mainscreen/bottom_display/bottom_display_widget.dart';
import 'package:iboard_app/widgets/rthk_news_ticker_widget.dart';
import 'package:iboard_app/pages/settings_page.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import 'package:iboard_app/providers/arrear_provider.dart';

class AnnouncementPage extends StatefulWidget {
  const AnnouncementPage({super.key});

  @override
  AnnouncementPageState createState() => AnnouncementPageState();
}

class AnnouncementPageState extends State<AnnouncementPage> {
  final Logger _logger = Logger();
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

        // 🔧 修复：只有从全屏广告切换到手动操作状态时才跳转到主屏幕
        // 从全屏广告直接切换到默认状态时，应该保持当前轮播位置
        if (_previousAppState == AppState.fullscreenAd &&
            appState == AppState.manualOperation) {
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

      // _logger.i(
      //     '🎛️ 轮播状态更新[${appState.name}]: Top=${!topAdProvider.isTopCarouselPaused ? "运行" : "暂停"}, Mid=${!announcementCarouselProvider.isMidCarouselPaused ? "运行" : "暂停"}, Bottom=${!bottomProvider.isBottomCarouselPaused ? "运行" : "暂停"}');
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
      // 🔧 修复：初始化时强制确保应用进入默认状态
      final carouselStateProvider = context.read<CarouselStateProvider>();
      carouselStateProvider.enterDefaultState();
      _logger.i('🚀 应用初始化，强制进入默认轮播状态');

      _setupProviderReferences();

      _initializeMidWidgets();
      _initializeTopWidgets();
      _initializeBottomWidgets();
      _initializeNewsAnnouncements();
      _startDebugTimer();
      _startCarouselWatchdog();

      // 🔧 修复：初始化时主动获取费用数据，确保轮播内容完整
      _arrearProvider.initGetFeeData().then((_) {
        _logger.i('✅ 费用数据初始化完成');
        // 费用数据加载完成后，重新初始化中部轮播以包含费用表格
        _initializeMidWidgets();
      }).catchError((error) {
        _logger.e('❌ 费用数据初始化失败: $error');
      });

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

    _logger.i('📰 RTHK新闻初始化完成');
  }

  ///2.3，设置Provider引用
  void _setupProviderReferences() {
    final stateProvider = context.read<CarouselStateProvider>();
    final topAdProvider = context.read<TopAdCarouselProvider>();

    // 设置顶部广告轮播Provider引用（修复音视频不同步问题）
    stateProvider.setTopCarouselProvider(topAdProvider);

    _logger.i('🔗 Provider引用设置完成');
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
        // _logger.i(
        //     '🕐 [调试] 应用状态变化: ${_lastLoggedAppState?.name ?? "初始"} -> ${currentAppState.name}');
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
    // _logger.i('⚙️ 进入设置页面 - 暂停所有轮播和计时器');

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

    // _logger.i('⚙️ 设置页面模式 - 所有轮播已暂停');
  }

  ///6，正常退出全屏广告状态，恢复所有轮播
  void _resumeAllCarousels() {
    final fullAdCarouselProvider =
        Provider.of<FullscreenAdProvider>(context, listen: false);
    final topAdCarouselProvider =
        Provider.of<TopAdCarouselProvider>(context, listen: false);
    final announcementCarouselProvider =
        Provider.of<AnnouncementCarouselProvider>(context, listen: false);
    final stateProvider =
        Provider.of<CarouselStateProvider>(context, listen: false);

    // 退出全屏广告模式
    fullAdCarouselProvider.exitFullscreenMode();

    // 恢复顶部广告轮播
    topAdCarouselProvider.resumeTopCarousel();

    // 恢复通告轮播 - 🔧 修复：不强制跳转索引，保持之前的轮播位置
    announcementCarouselProvider
        .resumeMidCarousel(stateProvider.noticeStayDuration);

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
    // _logger.i('🔍 [启动] 轮播监控定时器 (30s间隔检查) - 确保轮播不中断');
  }

  ///6，进入手动操作模式
  void _handleManualOperationMode() {
    // _logger.i('🖱️ 进入手动操作模式 - 暂停通告轮播，恢复顶部和底部轮播');

    final announcementCarouselProvider =
        context.read<AnnouncementCarouselProvider>();

    // 暂停中部通告轮播
    announcementCarouselProvider.pauseMidCarousel();

    // 恢复顶部广告轮播（如果被暂停了）
    final topAdProvider = context.read<TopAdCarouselProvider>();
    // 确保顶部广告能够立即恢复视频播放和轮播
    if (topAdProvider.isTopCarouselPaused) {
      topAdProvider.resumeTopCarousel();
    } else {
      topAdProvider.checkAndRestoreTopCarousel();
    }

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
    final delayBeforeNotice = carouselStateProvider.noActivityTimeout;

    // 即使没有通告数据也要初始化轮播组件，确保主屏幕能正常显示
    if (carouselAnnouncements.isEmpty) {
      _logger.w('⚠️ 通告数据为空，初始化费用表格轮播模式');
    } else {
      _logger.i('✅ 通告轮播数据初始化: ${carouselAnnouncements.length} 个通告');
    }

    // 🔧 修复：无论是否有通告，都确保应用保持在默认轮播状态
    // 不要让应用进入手动操作模式，而是保持轮播状态
    carouselStateProvider.enterDefaultState();

    // 初始化通告轮播
    announcementCarouselProvider.initializeMidWidgets(
      carouselAnnouncements: carouselAnnouncements,
      apiNoticeStayDuration: apiNoticeStayDuration,
      delayBeforeNotice: delayBeforeNotice,
      onAnnouncementTap: (AnnouncementModel? announcement) {
        // 🔧 修复：点击通告时保持默认状态，不进入手动操作模式
        if (announcement == null) {
          // 点击主屏幕时，不改变应用状态，保持轮播继续
          _logger.d('🏠 点击主屏幕，保持轮播状态');
        } else {
          announcementCarouselProvider.showIndependentAnnouncement(announcement,
              () {
            announcementCarouselProvider.jumpToAnnouncementIndex(0);
          });
          // 显示独立通告时也不进入手动模式，让轮播继续
          _logger.d('📢 显示独立通告，保持轮播状态');
        }
      },
      onHomeButtonPressed: () {
        announcementCarouselProvider.jumpToAnnouncementIndex(0);
      },
    );

    _logger.i('✅ 中部轮播初始化完成，应用状态: ${carouselStateProvider.currentAppState}');
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
      _logger.w('⚠️ 輪播專用數據為空，使用舊廣告數據作為後備: ${topAds.length} 個廣告');
    } else {
      _logger.i('✅ 使用輪播專用數據: ${topAds.length} 個廣告');
    }

    if (topAds.isNotEmpty) {
      topAdProvider.initializeTopWidgets(topAds);
      _logger.i('✅ 頂部廣告輪播初始化完成: ${topAds.length} 個廣告');
    } else {
      _logger.w('⚠️ 沒有可用的頂部廣告數據');
    }
  }

  ///10，初始化底部轮播
  void _initializeBottomWidgets() {
    // 底部轮播现在由BottomWeatherQrcodeNewsCarouselProvider管理
    final bottomProvider = context.read<WeatherProvider>();
    bottomProvider.initializeBottomCarousel();
    // _logger.i('🌤️ [初始化] 底部天气二维码轮播初始化完成');
  }

  ///11，处理设备ID点击事件
  void _handleDeviceIdClick() {
    _deviceIdClickCount++;
    // _logger.i('📱 设备ID点击次数: $_deviceIdClickCount/8');

    // 取消之前的重置定时器
    _clickResetTimer?.cancel();

    if (_deviceIdClickCount >= 8) {
      // 达到8次点击，进入设置页面
      // _logger.i('🔧 连续点击8次，进入设置页面');
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
        // _logger.i('⏰ 点击计数器已重置');
      });
    }
  }

  @override

  ///12，处理视频播放器的初始化和播放
  Widget build(BuildContext context) {
    // Listen to AnnouncementProvider for changes
    final announcementProvider = context.watch<AnnouncementProvider>();
    final currentCarouselAnnouncements =
        announcementProvider.carouselAnnouncements; // 监听轮播专用通告数组

    // Listen to AdvertisementProvider for changes
    final advertisementProvider = context.watch<AdvertisementProvider>();
    final currentAdvertisements = advertisementProvider.topAdvertisements;

    // Listen to AppDataProvider for device ID
    final appDataProvider = context.watch<AppDataProvider>();
    final deviceId = appDataProvider.deviceId;

    // Listen to CarouselStateProvider for fullscreen ad state changes
    final carouselStateProvider = context.watch<CarouselStateProvider>();
    final currentAppState = carouselStateProvider.currentAppState;

    // Handle state changes for carousel and media control
    if (_previousAppState != currentAppState) {
      // _logger.i(
      //     '🔄 应用状态变化: ${_previousAppState?.name ?? "初始"} -> ${currentAppState.name}');

      // 使用 addPostFrameCallback 延迟执行所有状态更新操作，避免 setState during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        // 更新轮播状态基于当前应用状态
        _updateCarouselStateBasedOnAppState(currentAppState);

        if (currentAppState == AppState.fullscreenAd) {
          // _logger.i('📺 进入全屏广告状态');
          _pauseAllCarousels();
        } else if (currentAppState == AppState.manualOperation) {
          // _logger.i('🖱️ 进入手动操作状态');
          _handleManualOperationMode();
        } else if (currentAppState == AppState.defaultState) {
          // _logger.i('🏠 进入默认状态');
          // 確保通告輪播在默認狀態下恢復
          _resumeAllCarousels();
        }
      });

      _previousAppState = currentAppState;
    }

    // If carousel announcements have changed, re-initialize the mid widgets
    // 现在监听轮播通告数组的变化而不是所有通告的变化
    if (_previousAnnouncementsForBuild == null ||
        !listEquals(
            _previousAnnouncementsForBuild, currentCarouselAnnouncements)) {
      // 使用 addPostFrameCallback 延迟执行状态更新，避免 setState during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        // 检查新的通告数据是否有效，或者是否从有数据变为无数据
        final bool shouldUpdate = currentCarouselAnnouncements.isNotEmpty ||
            _previousAnnouncementsForBuild == null ||
            (_previousAnnouncementsForBuild != null &&
                _previousAnnouncementsForBuild!.isNotEmpty &&
                currentCarouselAnnouncements.isEmpty);

        if (shouldUpdate) {
          try {
            _initializeMidWidgets();
            _previousAnnouncementsForBuild =
                List.from(currentCarouselAnnouncements); // 更新存储的轮播通告列表
            _logger.i('通告轮播更新成功: ${currentCarouselAnnouncements.length} 个通告');
          } catch (e) {
            _logger.e('初始化中部轮播失败，保持现有状态', error: e);
            // 不更新 _previousAnnouncementsForBuild，保持现有状态
          }
        } else {
          // 新数据为空但有旧数据，记录警告但不更新（保持现有轮播继续工作）
          _logger.w('收到空的通告数据，保持现有轮播继续工作。'
              '当前轮播: ${_previousAnnouncementsForBuild?.length ?? 0} 个通告');

          // 检查是否有网络错误信息
          if (announcementProvider.error != null) {
            _logger.w('通告获取错误: ${announcementProvider.error}');
          }
        }
      });
    }

    // If advertisements have changed, re-initialize the top widgets
    if (_previousAdvertisementsForBuild == null ||
        !listEquals(_previousAdvertisementsForBuild, currentAdvertisements)) {
      // 使用 addPostFrameCallback 延迟执行状态更新，避免 setState during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        // 检查新的广告数据是否有效
        if (currentAdvertisements.isNotEmpty ||
            _previousAdvertisementsForBuild == null) {
          // 只有当新数据非空或首次初始化时才更新
          try {
            _initializeTopWidgets();

            // 同时更新全屏广告数据
            final fullAdCarouselProvider = context.read<FullscreenAdProvider>();
            final fullAds = advertisementProvider.fullAdvertisements;
            fullAdCarouselProvider.updateFullscreenAds(fullAds);
            // _logger.i('全屏广告数据已更新: ${fullAds.length} 个全屏广告');

            _previousAdvertisementsForBuild =
                List.from(currentAdvertisements); // Update the stored list
            // _logger.i('广告轮播更新成功: ${currentAdvertisements.length} 个广告');
          } catch (e) {
            _logger.e('初始化顶部轮播失败，保持现有状态', error: e);
            // 不更新 _previousAdvertisementsForBuild，保持现有状态
          }
        } else {
          // 新数据为空但有旧数据，记录警告但不更新
          _logger.w('收到空的广告数据，保持现有轮播继续工作。'
              '当前轮播: ${_previousAdvertisementsForBuild?.length ?? 0} 个广告');

          // 检查是否有网络错误信息
          if (advertisementProvider.error != null) {
            _logger.w('广告获取错误: ${advertisementProvider.error}');
          }
        }
      });
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 上部區域 - 6/24 比例
            Expanded(
              flex: 6,
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
            // 中部區域 - 14/24 比例
            Expanded(
              flex: 14,
              child: Container(
                width: double.infinity,
                color: Colors.grey.shade50, // Background for the carousel area
                child: Stack(
                  children: [
                    // 轮播内容 - 始终存在，不被销毁
                    Consumer<AnnouncementCarouselProvider>(
                      builder: (context, announcementCarouselProvider, child) {
                        // _logger.i('🎬 [MainScreenPage] 轮播组件构建中');
                        return custom_carousel.CarouselWidget(
                          controller: announcementCarouselProvider
                              .midCarouselController,
                          showIndicators: false,
                          allowManualSwipe: false,
                          onPageChanged: (index) {},
                        );
                      },
                    ),
                    // 欠费查询覆盖层 - 已删除，功能整合到MainScreenWidget
                    // Consumer<AnnouncementCarouselProvider>(
                    //   builder: (context, announcementCarouselProvider, child) {
                    //     '🔄 [MainScreenPage Overlay] 检查覆盖层 - isShowingArrearQuery: ${announcementCarouselProvider.isShowingArrearQuery}');

                    //     if (announcementCarouselProvider.isShowingArrearQuery) {
                    //       '💰 [MainScreenPage Overlay] 显示欠费查询覆盖层');
                    //       return Container(
                    //         width: double.infinity,
                    //         height: double.infinity,
                    //         // ArrearDisplayWidget已删除，功能整合到MainScreenWidget的右側展示
                    //         child: const SizedBox.shrink(),
                    //       );
                    //     }

                    //     // 不显示欠费查询时返回空容器
                    //     return const SizedBox.shrink();
                    //   },
                    // ),
                  ],
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
                    Container(
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
                    // 底部轮播 - 7/8 比例
                    const Expanded(
                      child: BottomDisplayWidget(),
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
                  child: Text(
                    deviceId != null ? '設備ID: $deviceId' : '設備ID: 未知',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
