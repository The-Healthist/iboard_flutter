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
  Timer? _debugTimer; // 添加调试定时器
  Timer? _watchdogTimer; // 添加监控定时器
  Timer? _delayedNoticeTimer; // 延迟启动通告轮播定时器
  List<AdModel> _topAds = [];
  List<AnnouncementModel>?
      _previousAnnouncementsForBuild; // Added state variable
  List<AdModel>? _previousAdvertisementsForBuild; // Added for ad tracking

  // 轮播暂停状态管理 - 按区域分别控制
  bool _isTopCarouselPaused = false;
  bool _isMidCarouselPaused = false;
  bool _isBottomCarouselPaused = false;
  AppState? _previousAppState;

  // 时间记录相关 - 用于全屏广告暂停恢复
  DateTime? _currentTopAdStartTime; // 当前顶部广告开始时间
  DateTime? _currentNoticeStartTime; // 当前通告开始时间
  DateTime? _currentTopAdPauseTime; // 当前顶部广告暂停时间
  DateTime? _currentNoticePauseTime; // 当前通告暂停时间
  Duration _topAdElapsedTime = Duration.zero; // 顶部广告已播放时间
  Duration _noticeElapsedTime = Duration.zero; // 通告已播放时间
  Duration _topAdDuration = const Duration(seconds: 15); // 顶部广告总时长
  Duration _noticeDuration = const Duration(seconds: 5); // 通告总时长 - 使用API默认值
  int _currentTopAdIndex = 0; // 当前顶部广告索引
  int _currentNoticeIndex = 0; // 当前通告索引

  ///1， 根据当前应用状态更新轮播暂停状态
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

  ///2， 初始化状态
  void initState() {
    super.initState();
    _topCarouselController = custom_carousel.CarouselController();
    _midCarouselController = custom_carousel.CarouselController();
    _bottomCarouselController = custom_carousel.CarouselController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeMidWidgets();
      _initializeTopWidgets();
      _initializeBottomWidgets();
      _startDebugTimer(); // 启动调试定时器
      _startCarouselWatchdog(); // 启动轮播监控

      // Trigger data fetching
      final advertisementProvider =
          Provider.of<AdvertisementProvider>(context, listen: false);
      advertisementProvider.fetchAdvertisements();
    });
  }

  @override

  ///3， 释放资源
  void dispose() {
    _topTimer?.cancel();
    _midTimer?.cancel();
    _bottomTimer?.cancel();
    _debugTimer?.cancel(); // 取消调试定时器
    _watchdogTimer?.cancel(); // 取消监控定时器
    _delayedNoticeTimer?.cancel(); // 取消延迟启动定时器
    super.dispose();
  }

  ///4，启动调试定时器 - 每秒输出各区域的实时状态
  void _startDebugTimer() {
    _debugTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;

      final carouselStateProvider = context.read<CarouselStateProvider>();
      final currentAppState = carouselStateProvider.currentAppState;

      // 获取API配置的通告停留时间
      final apiNoticeStayDuration = carouselStateProvider.noticeStayDuration;

      // 计算顶部广告剩余时间
      int topAdRemaining = 0;
      if (_currentTopAdStartTime != null) {
        if (_isTopCarouselPaused) {
          // 暂停状态：使用暂停时的剩余时间
          final remaining = _topAdDuration - _topAdElapsedTime;
          topAdRemaining = remaining.isNegative ? 0 : remaining.inSeconds;
        } else {
          // 运行状态：计算当前剩余时间
          final elapsed = DateTime.now().difference(_currentTopAdStartTime!);

          // 如果有已播放时间记录（说明经历了暂停恢复），需要加上之前的播放时间
          final totalElapsed = elapsed + _topAdElapsedTime;

          final remaining = _topAdDuration - totalElapsed;
          topAdRemaining = remaining.isNegative ? 0 : remaining.inSeconds;
        }
      }

      // 计算通告剩余时间 - 使用实时API配置
      int noticeRemaining = 0;
      if (_currentNoticeStartTime != null && !_isMidCarouselPaused) {
        final elapsed = DateTime.now().difference(_currentNoticeStartTime!);
        final remaining = Duration(seconds: apiNoticeStayDuration) - elapsed;
        noticeRemaining = remaining.isNegative ? 0 : remaining.inSeconds;
      }

      // 输出调试信息
      String statusInfo = '';
      if (_isTopCarouselPaused || _isMidCarouselPaused) {
        statusInfo = ' [暂停状态]';
      }

      _logger.i(
          '🕐 [调试] 状态=${currentAppState.name} | 顶部广告: ${topAdRemaining}s/${_topAdDuration.inSeconds}s | 通告: ${noticeRemaining}s/${apiNoticeStayDuration}s (API配置)$statusInfo');
    });
  }

  ///5， 暂停所有轮播
  void _pauseAllCarousels() {
    _logger.i('🛑 暂停所有轮播 - 进入全屏广告状态');

    final carouselStateProvider = context.read<CarouselStateProvider>();
    final apiNoticeStayDuration = carouselStateProvider.noticeStayDuration;

    // 记录当前播放时间
    _currentTopAdPauseTime = DateTime.now();
    _currentNoticePauseTime = DateTime.now();

    // 计算已播放时间
    if (_currentTopAdStartTime != null) {
      _topAdElapsedTime =
          _currentTopAdPauseTime!.difference(_currentTopAdStartTime!);
      final remainingTop = _topAdDuration - _topAdElapsedTime;
      _logger.i(
          '📊 [暂停] 顶部广告 - 已播放: ${_topAdElapsedTime.inSeconds}s/${_topAdDuration.inSeconds}s, 剩余: ${remainingTop.inSeconds}s');
    }

    if (_currentNoticeStartTime != null) {
      _noticeElapsedTime =
          _currentNoticePauseTime!.difference(_currentNoticeStartTime!);
      final remainingNotice =
          Duration(seconds: apiNoticeStayDuration) - _noticeElapsedTime;
      _logger.i(
          '📊 [暂停] 通告 - 已播放: ${_noticeElapsedTime.inSeconds}s/${apiNoticeStayDuration}s, 剩余: ${remainingNotice.inSeconds}s');
    }

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

  ///5，正常退出全屏广告状态，恢复所有轮播
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

    // 计算剩余播放时间并恢复定时器

    // 恢复顶部广告轮播 - 继续播放剩余时间
    if (_topAds.isNotEmpty) {
      final remainingTopTime = _topAdDuration - _topAdElapsedTime;
      _logger.i(
          '🔄 [恢复] 顶部广告 - 继续播放剩余时间：${remainingTopTime.inSeconds}s (已播放: ${_topAdElapsedTime.inSeconds}s)');

      if (remainingTopTime.inSeconds > 0) {
        // 继续播放剩余时间
        _topTimer = Timer(remainingTopTime, () {
          if (mounted && !_isTopCarouselPaused) {
            _logger.i('⏰ [定时] 顶部广告时间到，切换到下一个');
            _topCarouselController.playNext();
            _startTopAdTimer(15); // 下一个广告正常播放
          }
        });
      } else {
        // 时间已到，直接切换到下一个
        _logger.i('⚡ [跳过] 顶部广告剩余时间为0，直接切换到下一个');
        _topCarouselController.playNext();
        _startTopAdTimer(15);
      }

      // 重置当前广告开始时间
      _currentTopAdStartTime = DateTime.now();
    }

    // 恢复中部通告轮播 - 考虑剩余时间后启动无限循环轮播
    if (_midCarouselController.widgetCount > 1 && !_isMidCarouselPaused) {
      final carouselStateProvider = context.read<CarouselStateProvider>();
      final apiNoticeStayDuration = carouselStateProvider.noticeStayDuration;
      _noticeDuration = Duration(seconds: apiNoticeStayDuration); // 更新当前时长配置

      final remainingNoticeTime = _noticeDuration - _noticeElapsedTime;
      _logger.i(
          '🔄 [恢复] 通告轮播 - API配置=${apiNoticeStayDuration}s, 剩余时间：${remainingNoticeTime.inSeconds}s (已播放: ${_noticeElapsedTime.inSeconds}s)');

      // 重置通告开始时间
      _currentNoticeStartTime = DateTime.now();

      // 确保当前索引在通告范围内（跳过主屏幕索引0）
      if (_currentNoticeIndex < 1) {
        _currentNoticeIndex = 1; // 从第一个通告开始
        _midCarouselController.jumpToIndex(_currentNoticeIndex);
        _logger.i('🔄 [恢复] 设置索引到第一个通告: $_currentNoticeIndex');
      }

      if (remainingNoticeTime.inSeconds <= 1) {
        // 如果剩余时间很少，直接切换到下一个通告并启动无限轮播
        _logger.i('⚡ [跳过] 通告剩余时间不足1秒，直接切换到下一个并启动无限轮播');
        // 计算下一个通告索引，跳过主屏幕
        _currentNoticeIndex++;
        if (_currentNoticeIndex >= _midCarouselController.widgetCount) {
          _currentNoticeIndex = 1; // 回到第一个通告
        }
        _midCarouselController.jumpToIndex(_currentNoticeIndex);
        _currentNoticeStartTime = DateTime.now(); // 重新记录新通告开始时间
        _startContinuousNoticeCarousel(apiNoticeStayDuration);
      } else {
        // 先等待当前通告剩余时间，然后启动无限轮播
        _logger.i('⏱️ [恢复] 等待当前通告剩余时间${remainingNoticeTime.inSeconds}s后启动无限轮播');
        _midTimer = Timer(remainingNoticeTime, () {
          if (mounted && !_isMidCarouselPaused) {
            _logger.i('🔄 [切换] 当前通告时间到，切换到下一个并启动无限轮播');
            // 计算下一个通告索引，跳过主屏幕
            _currentNoticeIndex++;
            if (_currentNoticeIndex >= _midCarouselController.widgetCount) {
              _currentNoticeIndex = 1; // 回到第一个通告
            }
            _midCarouselController.jumpToIndex(_currentNoticeIndex);
            _currentNoticeStartTime = DateTime.now(); // 记录新通告开始时间
            _startContinuousNoticeCarousel(apiNoticeStayDuration);
          }
        });
      }
      _logger.i('✅ [恢复] 通告轮播恢复流程已启动');
    } // 恢复底部轮播（如果有）
    if (_bottomCarouselController.widgetCount > 1 && !_isBottomCarouselPaused) {
      _bottomTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
        if (mounted &&
            _bottomCarouselController.widgetCount > 1 &&
            !_isBottomCarouselPaused) {
          _bottomCarouselController.playNext();
        }
      });
    }

    // 重置计时变量
    _topAdElapsedTime = Duration.zero;
    _noticeElapsedTime = Duration.zero;
  }

  ///6.1，启动持续通告轮播（独立方法以确保一致性）- 真正的无限循环
  void _startContinuousNoticeCarousel(int apiNoticeStayDuration) {
    _midTimer?.cancel(); // 取消之前的定时器

    // 检查轮播条件 - 需要至少有通告（除了主屏幕）
    final announcementCount = _midCarouselController.widgetCount - 1; // 减去主屏幕
    if (announcementCount <= 0) {
      _logger.w('⚠️ [持续轮播] 无法启动: 通告数量不足 ($announcementCount个通告)');
      return;
    }

    if (_isMidCarouselPaused) {
      _logger.w('⚠️ [持续轮播] 无法启动: 轮播已暂停');
      return;
    }

    // 确保当前索引在通告范围内（索引1开始）
    if (_currentNoticeIndex < 1) {
      _currentNoticeIndex = 1; // 从第一个通告开始
      _midCarouselController.jumpToIndex(_currentNoticeIndex);
      _currentNoticeStartTime = DateTime.now();
      _logger.i('🔄 [初始化] 跳转到第一个通告，索引: $_currentNoticeIndex');
    }

    // 启动真正的无限循环定时器
    _midTimer =
        Timer.periodic(Duration(seconds: apiNoticeStayDuration), (timer) {
      if (!mounted) {
        _logger.w('⚠️ [持续轮播] 定时器停止: widget已销毁');
        timer.cancel();
        return;
      }

      if (_isMidCarouselPaused) {
        _logger.w('⚠️ [持续轮播] 定时器暂停: 轮播状态为暂停');
        // 不取消定时器，只是跳过这次执行，等待恢复
        return;
      }

      final currentAnnouncementCount = _midCarouselController.widgetCount - 1;
      if (currentAnnouncementCount <= 0) {
        _logger.w('⚠️ [持续轮播] 跳过执行: 通告数量不足');
        return;
      }

      try {
        // 计算下一个通告索引，跳过主屏幕（索引0）
        _currentNoticeIndex++;
        if (_currentNoticeIndex >= _midCarouselController.widgetCount) {
          _currentNoticeIndex = 1; // 回到第一个通告，跳过主屏幕
        }

        // 跳转到下一个通告
        _midCarouselController.jumpToIndex(_currentNoticeIndex);

        // 记录新通告开始时间
        _currentNoticeStartTime = DateTime.now();

        _logger.i(
            '📝 [无限轮播] 切换通告(API=${apiNoticeStayDuration}s) 索引: $_currentNoticeIndex/${_midCarouselController.widgetCount} (跳过主屏幕)');
        _logger.i(
            '🔄 [无限轮播] 定时器状态: isActive=${timer.isActive}, 下次触发将在${apiNoticeStayDuration}秒后');
      } catch (e) {
        _logger.e('❌ [持续轮播] 切换失败: $e');
        // 发生错误时，尝试重新启动轮播
        Future.delayed(Duration(seconds: 1), () {
          if (mounted && !_isMidCarouselPaused) {
            _logger.i('🔄 [恢复] 尝试重新启动通告轮播');
            _startContinuousNoticeCarousel(apiNoticeStayDuration);
          }
        });
      }
    });
    _logger.i(
        '🚀 [启动] 无限循环通告轮播定时器 (${apiNoticeStayDuration}s间隔) - 通告数量: $announcementCount (跳过主屏幕)');
  }

  ///6.2，启动轮播监控定时器（检测并自动恢复中断的轮播）
  void _startCarouselWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final carouselStateProvider = context.read<CarouselStateProvider>();
      final currentAppState = carouselStateProvider.currentAppState;

      // 只在默认状态下检查通告轮播
      if (currentAppState == AppState.defaultState &&
          !_isMidCarouselPaused &&
          (_midCarouselController.widgetCount - 1) > 0) {
        // 减去主屏幕数量
        // 检查通告轮播是否还在运行
        if (_midTimer == null || !_midTimer!.isActive) {
          _logger.w('🔧 [监控] 检测到通告轮播定时器已停止，尝试重新启动无限循环');
          _logger.w(
              '🔧 [监控] 定时器状态: _midTimer=${_midTimer != null ? "存在" : "null"}, isActive=${_midTimer?.isActive ?? false}');

          try {
            final apiNoticeStayDuration =
                carouselStateProvider.noticeStayDuration;
            _currentNoticeStartTime = DateTime.now();
            // 确保索引在通告范围内
            if (_currentNoticeIndex < 1) {
              _currentNoticeIndex = 1;
              _midCarouselController.jumpToIndex(_currentNoticeIndex);
            }
            _startContinuousNoticeCarousel(apiNoticeStayDuration);
            _logger.i('✅ [监控] 成功重新启动无限循环通告轮播');
          } catch (e) {
            _logger.e('❌ [监控] 重新启动通告轮播失败: $e');
          }
        } else {
          _logger.d('✅ [监控] 无限循环通告轮播运行正常 - 定时器isActive=${_midTimer!.isActive}');
        }
      } else {
        final announcementCount = _midCarouselController.widgetCount - 1;
        _logger.d(
            '🔍 [监控] 跳过检查: 状态=${currentAppState.name}, 暂停=$_isMidCarouselPaused, 通告数=$announcementCount');
      }
    });
    _logger.i('🔍 [启动] 轮播监控定时器 (30s间隔检查) - 确保无限循环不中断');
  }

  ///6，进入手动操作模式
  void _handleManualOperationMode() {
    _logger.i('🖱️ 进入手动操作模式 - 暂停通告轮播，恢复顶部和底部轮播');

    // 暂停中部通告轮播，但记录暂停时间以便后续恢复
    if (_currentNoticeStartTime != null) {
      _noticeElapsedTime = DateTime.now().difference(_currentNoticeStartTime!);
      final carouselStateProvider = context.read<CarouselStateProvider>();
      final apiNoticeStayDuration = carouselStateProvider.noticeStayDuration;
      _logger.i(
          '📊 [手动模式] 暂停通告轮播: 已播放${_noticeElapsedTime.inSeconds}s/${apiNoticeStayDuration}s');
    }
    _midTimer?.cancel();
    _isMidCarouselPaused = true;

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

  ///7，初始化中部轮播
  void _initializeMidWidgets() {
    final announcementProvider =
        Provider.of<AnnouncementProvider>(context, listen: false);
    final carouselStateProvider = context.read<CarouselStateProvider>();

    // 使用轮播专用通告数组 - 只包含緊急和一般通告
    List<AnnouncementModel> carouselAnnouncements =
        announcementProvider.getCarouselAnnouncements();

    // 获取API配置的通告停留时间
    final apiNoticeStayDuration = carouselStateProvider.noticeStayDuration;
    _noticeDuration = Duration(seconds: apiNoticeStayDuration);

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
    _logger.i('使用API配置的通告停留时间: ${apiNoticeStayDuration}秒');

    _midTimer?.cancel();
    _delayedNoticeTimer?.cancel(); // 取消之前的延迟定时器

    // 应用启动时先停留在主屏幕，等待 spareDuration 时间后才开始通告轮播
    _currentNoticeIndex = 0; // 初始停留在主屏幕
    _midCarouselController.jumpToIndex(0); // 确保显示主屏幕

    if (announcementWidgets.length > 0 && !_isMidCarouselPaused) {
      final carouselStateProvider = context.read<CarouselStateProvider>();
      final delayBeforeNotice =
          carouselStateProvider.noActivityTimeout; // 使用 spareDuration

      _logger.i('⏳ [启动延迟] 应用启动，在主屏幕停留 ${delayBeforeNotice}秒后开始无限通告轮播');

      // 启动延迟定时器，等待 spareDuration 时间后开始通告轮播
      _delayedNoticeTimer = Timer(Duration(seconds: delayBeforeNotice), () {
        if (announcementWidgets.length > 0 && !_isMidCarouselPaused) {
          // 记录通告开始时间，从第一个通告开始（索引1）
          _currentNoticeStartTime = DateTime.now();
          _currentNoticeIndex = 1; // 从第一个通告开始，跳过主屏幕（索引0）

          // 跳转到第一个通告
          _midCarouselController.jumpToIndex(_currentNoticeIndex);

          _logger.i(
              '� [延迟启动] 通告轮播开始: 开始时间=${_currentNoticeStartTime}, API配置时长=${apiNoticeStayDuration}s, 索引=${_currentNoticeIndex}');

          // 使用统一的持续轮播方法
          _startContinuousNoticeCarousel(apiNoticeStayDuration);
        }
      });
    } else {
      _logger.w(
          '⚠️ [通告轮播] 无法启动: 通告数量=${announcementWidgets.length}, 暂停状态=$_isMidCarouselPaused');
    }
  }

  ///8，打开全屏广告对话框
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
    // 记录当前广告开始时间和总时长
    _currentTopAdStartTime = DateTime.now();
    _topAdDuration = ad.durationObject;
    _currentTopAdIndex = currentIndex;

    _logger.d('▶️ 启动顶部广告计时器: ${ad.title}, duration=${ad.durationObject}');
    _logger.i(
        '📝 记录顶部广告开始时间: ${_currentTopAdStartTime}, 索引: $_currentTopAdIndex, 时长: ${_topAdDuration.inSeconds}秒');

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

  ///9，初始化顶部轮播
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

  ///10，初始化底部轮播
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

  ///11，处理视频播放器的初始化和播放
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
        // 確保通告輪播在默認狀態下恢復
        _isMidCarouselPaused = false;
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
