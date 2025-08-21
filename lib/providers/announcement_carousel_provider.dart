import 'dart:async';
import 'package:flutter/material.dart';
import 'package:iboard_app/managers/file_manager.dart';
import 'package:iboard_app/models/announcement_model.dart';
import 'package:iboard_app/widgets/carousel_widget.dart' as custom_carousel;
import 'package:iboard_app/widgets/mainscreen/main_display/announcement_reader_widget.dart';
import 'package:iboard_app/widgets/mainscreen/main_display/mainscreen_widget.dart';
import 'package:iboard_app/widgets/mainscreen/main_display/arrear_table_widget.dart';
// import 'package:shared_preferences/shared_preferences.dart'; // 已删除，不再使用
// import 'dart:convert'; // 已删除，不再使用
import 'package:iboard_app/providers/app_data_provider.dart';

/// 通告轮播Provider
/// 负责管理通告的轮播逻辑、暂停恢复、定时器管理等
/// 轮播顺序由后台管理，此Provider不再处理自定义顺序
class AnnouncementCarouselProvider extends ChangeNotifier {
  // 轮播控制器
  late custom_carousel.CarouselController _midCarouselController;

  // 定时器管理
  Timer? _midTimer;
  Timer? _debugTimer;
  Timer? _delayedNoticeTimer; // 延迟启动通告轮播定时器

  // 通告数据 - 使用AnnouncementProvider的轮播数据
  List<AnnouncementModel> _carouselAnnouncements = [];

  // 状态管理
  bool _isMidCarouselPaused = false;
  // bool _isShowingArrearQuery = false; // 已删除：ArrearDisplayWidget已不再使用
  bool _isShowingArrearTable = false; // 新增：是否显示欠费总览页面

  // 时间记录相关 - 用于全屏广告暂停恢复
  DateTime? _currentNoticeStartTime; // 当前通告开始时间
  DateTime? _currentNoticePauseTime; // 当前通告暂停时间
  Duration _noticeElapsedTime = Duration.zero; // 通告已播放时间
  Duration _noticeDuration = const Duration(seconds: 5); // 通告总时长
  int _currentNoticeIndex = 0; // 当前通告索引

  // AppDataProvider引用 - 用于获取动态设置
  AppDataProvider? _appDataProvider;

  // 新增：保存主页按钮回调
  late VoidCallback _homeButtonCallback;

  // 新增：延遲套用的輪播資料與欠費分頁狀態
  List<AnnouncementModel>? _pendingCarouselAnnouncements;
  bool _isArrearPaginationActive = false;

  // Getters
  custom_carousel.CarouselController get midCarouselController =>
      _midCarouselController;
  List<AnnouncementModel> get carouselAnnouncements => _carouselAnnouncements;
  bool get isMidCarouselPaused => _isMidCarouselPaused;
  // bool get isShowingArrearQuery => _isShowingArrearQuery; // 已删除：ArrearDisplayWidget已不再使用
  bool get isShowingArrearTable => _isShowingArrearTable; // 新增：获取欠费总览显示状态
  Duration get noticeDuration => _noticeDuration;
  int get currentNoticeIndex => _currentNoticeIndex;
  DateTime? get currentNoticeStartTime => _currentNoticeStartTime;
  Duration get noticeElapsedTime => _noticeElapsedTime;

  AnnouncementCarouselProvider() {
    _midCarouselController = custom_carousel.CarouselController();
  }

  /// 设置AppDataProvider引用
  void setAppDataProvider(AppDataProvider appDataProvider) {
    _appDataProvider = appDataProvider;
  }

  /// 获取AppDataProvider引用
  AppDataProvider? _getAppDataProvider() {
    return _appDataProvider;
  }

  ///1，更新轮播通告列表（由AnnouncementProvider调用）
  void updateCarouselList(List<AnnouncementModel> newCarouselAnnouncements) {
    // 欠費總覽顯示或其分頁進行時，延後套用，避免中斷當前顯示
    final bool isOnArrear = _midCarouselController.widgetCount > 0 &&
        _currentNoticeIndex == (_midCarouselController.widgetCount - 1);
    if (_isArrearPaginationActive || isOnArrear) {
      _pendingCarouselAnnouncements =
          List<AnnouncementModel>.from(newCarouselAnnouncements);
      return;
    }

    _applyCarouselUpdate(newCarouselAnnouncements);
  }

  ///2，實際套用輪播列表更新（不打斷當前播放）
  void _applyCarouselUpdate(List<AnnouncementModel> newCarouselAnnouncements) {
    final int oldWidgetCount = _midCarouselController.widgetCount;
    final int oldIndex = _currentNoticeIndex;

    int? currentAnnouncementId;
    final bool wasOnMain = oldIndex == 0;
    final bool wasOnArrear =
        oldWidgetCount > 0 && oldIndex == (oldWidgetCount - 1);

    if (oldIndex > 0 && oldIndex - 1 < _carouselAnnouncements.length) {
      currentAnnouncementId = _carouselAnnouncements[oldIndex - 1].id;
    }

    _carouselAnnouncements =
        List<AnnouncementModel>.from(newCarouselAnnouncements);

    final mainWidget = _createMainScreenWidget(_homeButtonCallback);
    final announcementWidgets = _carouselAnnouncements.map((announcement) {
      final fileManager = FileManager();
      fileManager.getFile(announcement.file);
      return Center(
        child: AnnouncementReaderWidget(
          announcement: announcement,
          fileManager: fileManager,
          onHomeButtonPressed: _homeButtonCallback,
        ),
      );
    }).toList();
    final arrearWidget = _createArrearTableCarouselWidget(_homeButtonCallback);
    final midWidgets = [mainWidget, ...announcementWidgets, arrearWidget];

    // 計算更新後應停留的索引，盡量保持當前展示的通告不變
    int desiredIndex;
    if (wasOnMain) {
      desiredIndex = 0;
    } else if (wasOnArrear) {
      desiredIndex = midWidgets.length - 1;
    } else if (currentAnnouncementId != null) {
      final idx = _carouselAnnouncements
          .indexWhere((a) => a.id == currentAnnouncementId);
      desiredIndex = idx >= 0
          ? idx + 1
          : (oldIndex.clamp(1, midWidgets.length - 1) as int);
    } else {
      desiredIndex = (oldIndex.clamp(0, midWidgets.length - 1) as int);
    }

    _midCarouselController.setCarouselArray(midWidgets);
    _currentNoticeIndex = desiredIndex;
    _midCarouselController.jumpToIndex(desiredIndex);

    // 不重置開始時間與定時器，避免立刻切換到下一條
    notifyListeners();
  }

  ///2，清空轮播通告列表
  void clearCarouselList() {
    _carouselAnnouncements.clear();
    notifyListeners();
  }

  ///3，初始化中部轮播
  void initializeMidWidgets({
    required List<AnnouncementModel> carouselAnnouncements,
    required int apiNoticeStayDuration,
    required int delayBeforeNotice,
    required Function(AnnouncementModel?) onAnnouncementTap,
    required VoidCallback onHomeButtonPressed,
  }) {
    // 保存主页回调
    _homeButtonCallback = onHomeButtonPressed;
    // 使用自定义顺序更新方法
    updateCarouselList(carouselAnnouncements);
    _noticeDuration = Duration(seconds: apiNoticeStayDuration);

    // 创建带回调的主屏幕部件
    Widget mainScreenWidget = MainScreenWidget(
      onAnnouncementTap: (AnnouncementModel? announcement) {
        if (announcement == null) {
          // 显示欠费查询界面 - 立即进入手动操作状态
          // 欠费查询功能已整合到MainScreenWidget中，不再需要单独的覆盖层
        } else {
          // 新逻辑：直接显示点击的通告，不依赖轮播列表查找

          // 直接显示独立通告
          showIndependentAnnouncement(announcement, onHomeButtonPressed);
        }
      },
      onArrearTableTap: () {
        // 显示欠费总览界面
        showArrearTableWidget(onHomeButtonPressed);
      },
    );

    // 只为轮播通告（緊急和一般）创建widget
    List<Widget> announcementWidgets =
        this.carouselAnnouncements.map((announcement) {
      FileManager fileManager = FileManager();
      fileManager.getFile(announcement.file);
      return Center(
          child: AnnouncementReaderWidget(
        announcement: announcement,
        fileManager: fileManager,
        onHomeButtonPressed: onHomeButtonPressed,
      ));
    }).toList();

    // 创建欠费总览轮播widget
    Widget arrearTableCarouselWidget =
        _createArrearTableCarouselWidget(onHomeButtonPressed);

    final midWidgets = [
      mainScreenWidget,
      ...announcementWidgets,
      arrearTableCarouselWidget, // 在轮播末尾添加欠费总览
    ];
    _midCarouselController.setCarouselArray(midWidgets);

    _midTimer?.cancel();
    _delayedNoticeTimer?.cancel();

    _currentNoticeIndex = 0;
    _midCarouselController.jumpToIndex(0);

    if (announcementWidgets.length > 0 && !_isMidCarouselPaused) {
      _delayedNoticeTimer = Timer(Duration(seconds: delayBeforeNotice), () {
        if (announcementWidgets.length > 0 && !_isMidCarouselPaused) {
          // 记录通告开始时间，从第一个通告开始（索引1）
          _currentNoticeStartTime = DateTime.now();
          _currentNoticeIndex = 1; // 从第一个通告开始，跳过主屏幕（索引0）

          // 跳转到第一个通告
          _midCarouselController.jumpToIndex(_currentNoticeIndex);

          // 使用统一的持续轮播方法
          _scheduleNextCarousel(apiNoticeStayDuration);
        }
      });
    } else {}
  }

  ///2，启动持续通告轮播
  void _startContinuousNoticeCarousel(int apiNoticeStayDuration) {
    _midTimer?.cancel();

    // 检查轮播条件
    final announcementCount = _midCarouselController.widgetCount - 1;
    if (announcementCount <= 0) {
      return;
    }

    if (_isMidCarouselPaused) {
      return;
    }

    // 确保当前索引在通告范围内（索引1开始）
    if (_currentNoticeIndex < 1) {
      _currentNoticeIndex = 1; // 从第一个通告开始
      _midCarouselController.jumpToIndex(_currentNoticeIndex);
      _currentNoticeStartTime = DateTime.now();
      // _logger.i('🔄 [初始化] 跳转到第一个通告，索引: $_currentNoticeIndex');
    }

    // 启动真正的无限循环定时器 - 使用单次定时器减少系统调用
    _scheduleNextCarousel(apiNoticeStayDuration);

    // _logger.i(
    //     '🚀 [启动] 无限循环通告轮播定时器 (${apiNoticeStayDuration}s间隔) - 通告数量: $announcementCount (跳过主屏幕)');
  }

  ///2a，调度下一个轮播切换（智能定时器，自适应间隔减少系统调用）
  void _scheduleNextCarousel(int apiNoticeStayDuration) {
    _midTimer?.cancel();

    if (_isMidCarouselPaused) {
      // _logger.w('⚠️ [调度轮播] 轮播已暂停，停止调度');
      return;
    }

    final currentAnnouncementCount = _midCarouselController.widgetCount - 1;
    if (currentAnnouncementCount <= 0) {
      return;
    }

    // 智能间隔策略：
    // - 短间隔(<=5秒): 使用原始间隔
    // - 中等间隔(6-10秒): 使用1秒检查间隔
    // - 长间隔(>10秒): 使用2秒检查间隔
    int checkInterval;
    if (apiNoticeStayDuration <= 5) {
      checkInterval = apiNoticeStayDuration;
    } else if (apiNoticeStayDuration <= 10) {
      checkInterval = 1;
    } else {
      checkInterval = 2;
    }

    // 使用检查间隔而不是实际停留时间，减少定时器创建频率
    _midTimer = Timer(Duration(seconds: checkInterval), () {
      _checkAndAdvanceCarousel(apiNoticeStayDuration);
    });
  }

  ///2b，检查并推进轮播（减少定时器创建）
  void _checkAndAdvanceCarousel(int apiNoticeStayDuration) {
    if (_isMidCarouselPaused) {
      // 暂停状态，稍后重新检查
      _scheduleNextCarousel(apiNoticeStayDuration);
      return;
    }

    // 检查是否到了切换时间
    if (_currentNoticeStartTime != null) {
      final elapsed = DateTime.now().difference(_currentNoticeStartTime!);
      final shouldAdvance = elapsed.inSeconds >= apiNoticeStayDuration;

      if (!shouldAdvance) {
        // 还没到时间，继续等待
        final remaining = apiNoticeStayDuration - elapsed.inSeconds;
        final nextCheck = remaining > 2 ? 2 : remaining;
        if (nextCheck > 0) {
          _midTimer = Timer(Duration(seconds: nextCheck), () {
            _checkAndAdvanceCarousel(apiNoticeStayDuration);
          });
        }
        return;
      }
    }

    // 时间到了，执行切换
    try {
      // 计算下一个通告索引，跳过主屏幕（索引0）
      _currentNoticeIndex++;
      if (_currentNoticeIndex >= _midCarouselController.widgetCount) {
        _currentNoticeIndex = 1; // 回到第一个通告，跳过主屏幕
      }

      // 检查是否切换到欠费总览（最后一个索引）
      final isArrearTable =
          _currentNoticeIndex == (_midCarouselController.widgetCount - 1);

      // 跳转到下一个通告或欠费总览
      _midCarouselController.jumpToIndex(_currentNoticeIndex);

      // 记录新通告开始时间
      _currentNoticeStartTime = DateTime.now();

      if (isArrearTable) {
        // 欠费总览会通过回调继续轮播，这里不再调度下一次
      } else {
        // 继续调度下一次轮播
        _scheduleNextCarousel(apiNoticeStayDuration);
      }
    } catch (e) {
      // 发生错误时，延迟重试
      Future.delayed(Duration(seconds: 2), () {
        if (!_isMidCarouselPaused) {
          _scheduleNextCarousel(apiNoticeStayDuration);
        }
      });
    }
  }

  ///3，暂停通告轮播
  void pauseMidCarousel() {
    // _logger.i('🛑 暂停通告轮播 - 进入全屏广告状态');

    // 记录当前播放时间
    _currentNoticePauseTime = DateTime.now();

    if (_currentNoticeStartTime != null) {
      _noticeElapsedTime =
          _currentNoticePauseTime!.difference(_currentNoticeStartTime!);
    }

    // 设置轮播为暂停状态
    _isMidCarouselPaused = true;

    // 暂停定时器
    _midTimer?.cancel();

    // 暂停轮播中的媒体内容
    _midCarouselController.pauseAllMedia();

    notifyListeners();
  }

  ///4，恢复通告轮播
  void resumeMidCarousel(int apiNoticeStayDuration,
      {bool forceJumpToIndex = false}) {
    // _logger.i('▶️ 恢复通告轮播 - 退出全屏广告状态');

    // 设置轮播为运行状态
    _isMidCarouselPaused = false;

    // 恢复轮播中的媒体内容
    _midCarouselController.resumeAllMedia();

    // 恢复通告轮播 - 考虑剩余时间后启动无限循环轮播
    if (_midCarouselController.widgetCount > 1 && !_isMidCarouselPaused) {
      _noticeDuration = Duration(seconds: apiNoticeStayDuration); // 更新当前时长配置

      // 移除特殊处理，现在通过动态延长时间来处理欠费总览

      final remainingNoticeTime = _noticeDuration - _noticeElapsedTime;
      // _logger.i(
      //     '🔄 [恢复] 通告轮播 - API配置=${apiNoticeStayDuration}s, 剩余时间：${remainingNoticeTime.inSeconds}s (已播放: ${_noticeElapsedTime.inSeconds}s)');

      // 重置通告开始时间
      _currentNoticeStartTime = DateTime.now();

      // 只有在强制跳转时才确保当前索引在通告范围内
      if (forceJumpToIndex && _currentNoticeIndex < 1) {
        _currentNoticeIndex = 1; // 从第一个通告开始
        _midCarouselController.jumpToIndex(_currentNoticeIndex);
        // _logger.i('🔄 [恢复] 设置索引到第一个通告: $_currentNoticeIndex');
      }

      if (remainingNoticeTime.inSeconds > 1) {
        // 剩余时间足够，先等待剩余时间再继续轮播
        // _logger.i('⏰ [恢复] 等待剩余时间后继续无限轮播');
        _midTimer = Timer(remainingNoticeTime, () {
          if (!_isMidCarouselPaused) {
            // 检查当前是否在欠费总览页面
            final isCurrentlyOnArrearTable =
                _currentNoticeIndex == (_midCarouselController.widgetCount - 1);

            if (isCurrentlyOnArrearTable) {
              // 如果当前在欠费总览页面，不直接切换，让自动翻页完成
              // 重置开始时间，等待欠费总览翻页完成
              _currentNoticeStartTime = DateTime.now();
            } else {
              // 不是欠费总览，正常切换到下一个通告
              _currentNoticeIndex++;
              if (_currentNoticeIndex >= _midCarouselController.widgetCount) {
                _currentNoticeIndex = 1; // 回到第一个通告
              }
              _midCarouselController.jumpToIndex(_currentNoticeIndex);
              _scheduleNextCarousel(apiNoticeStayDuration);
            }
          }
        });
      } else {
        // 剩余时间不足的特殊处理

        // 检查当前是否在欠费总览页面（最后一个索引）
        final isCurrentlyOnArrearTable =
            _currentNoticeIndex == (_midCarouselController.widgetCount - 1);

        if (isCurrentlyOnArrearTable) {
          // 如果当前在欠费总览页面，不直接切换，继续展示欠费总览

          // 重置开始时间，给欠费总览足够时间完成翻页
          _currentNoticeStartTime = DateTime.now();

          // 不调用 _scheduleNextCarousel，让欠费总览的翻页完成回调来处理切换
        } else {
          // 不是欠费总览，正常处理：直接启动下一个通告并开始无限轮播

          // 如果当前不在通告上，跳转到第一个通告
          if (_currentNoticeIndex < 1) {
            _currentNoticeIndex = 1;
            _midCarouselController.jumpToIndex(_currentNoticeIndex);
          } else {
            // 切换到下一个通告
            _currentNoticeIndex++;
            if (_currentNoticeIndex >= _midCarouselController.widgetCount) {
              _currentNoticeIndex = 1; // 回到第一个通告
            }
            _midCarouselController.jumpToIndex(_currentNoticeIndex);
          }

          _scheduleNextCarousel(apiNoticeStayDuration);
        }
      }
    }

    notifyListeners();
  }

  ///5，更新轮播暂停状态
  void updateCarouselPauseState(bool isPaused) {
    _isMidCarouselPaused = isPaused;
    // _logger.i('🎛️ 通告轮播状态更新: ${!_isMidCarouselPaused ? "运行" : "暂停"}');
    notifyListeners();
  }

  ///6，检查并恢复轮播状态（监控定时器使用）
  void checkAndRestoreMidCarousel(int apiNoticeStayDuration) {
    //  _logger.i(
    // '🔍 检查通告轮播恢复条件: announcements=${_carouselAnnouncements.length}, paused=$_isMidCarouselPaused');

    if ((_midCarouselController.widgetCount - 1) > 0 && !_isMidCarouselPaused) {
      // 检查当前定时器是否活跃
      if (_midTimer == null || !_midTimer!.isActive) {
        // _logger.w('🔧 检测到通告轮播定时器已停止，尝试重新启动...');

        // 确保当前索引在通告范围内
        if (_currentNoticeIndex < 1) {
          _currentNoticeIndex = 1;
          _midCarouselController.jumpToIndex(_currentNoticeIndex);
        }

        // _logger.i('🔄 恢复通告轮播，当前索引: $_currentNoticeIndex');
        _scheduleNextCarousel(apiNoticeStayDuration);
      }
    } else {
      // 不满足通告轮播恢复条件
    }
  }

  ///7，启动调试定时器 - 每秒输出通告轮播的实时状态
  void startDebugTimer(int apiNoticeStayDuration, {bool enableLogging = true}) {
    _debugTimer?.cancel();
    // 完全禁用调试定时器以减少系统资源占用和日志输出
    return;

    // _debugTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
    //   // 如果不启用日志，直接返回
    //   if (!enableLogging) return;

    //   // 计算通告剩余时间 - 使用实时API配置
    //   int noticeRemaining = 0;
    //   String statusInfo = '';

    //   if (_isMidCarouselPaused) {
    //     statusInfo = ' [暂停状态]';
    //   } else if (_currentNoticeStartTime != null) {
    //     final elapsed = DateTime.now().difference(_currentNoticeStartTime!);
    //     final remaining = Duration(seconds: apiNoticeStayDuration) - elapsed;
    //     noticeRemaining = remaining.isNegative ? 0 : remaining.inSeconds;
    //   } else {
    //     statusInfo = ' [未启动]';
    //   }

    //   // 获取当前通告信息
    //   String currentNoticeInfo = '';
    //   if (_currentNoticeIndex > 0 &&
    //       _currentNoticeIndex <= this.carouselAnnouncements.length) {
    //     final currentAnnouncement =
    //         this.carouselAnnouncements[_currentNoticeIndex - 1];
    //     currentNoticeInfo = ' - ${currentAnnouncement.title}';
    //   } else if (_currentNoticeIndex == 0) {
    //     currentNoticeInfo = ' - 主屏幕';
    //   }

    //   _logger.i(
    //       '🕐 [调试] 通告轮播: ${noticeRemaining}s/${apiNoticeStayDuration}s$statusInfo 索引:$_currentNoticeIndex$currentNoticeInfo');
    // });
  }

  ///8，停止调试定时器
  void stopDebugTimer() {
    _debugTimer?.cancel();
  }

  ///9，暂停所有计时器（用于设置页面）
  void pauseAllTimersForSettings() {
    // _logger.i('⚙️ 通告轮播 - 暂停所有计时器（设置页面）');
    _midTimer?.cancel();
    _debugTimer?.cancel();
    _delayedNoticeTimer?.cancel();
    _midCarouselController.pauseAllMedia();
    _isMidCarouselPaused = true;
    notifyListeners();
  }

  ///10，从设置页面恢复所有计时器
  void resumeAllTimersFromSettings(int apiNoticeStayDuration) {
    // _logger.i('↩️ 通告轮播 - 从设置页面恢复所有计时器');
    _isMidCarouselPaused = false;
    _midCarouselController.resumeAllMedia();

    // 恢复通告轮播
    if (_midCarouselController.widgetCount > 1) {
      _currentNoticeStartTime = DateTime.now();

      // 确保当前索引在通告范围内
      if (_currentNoticeIndex < 1) {
        _currentNoticeIndex = 1;
        _midCarouselController.jumpToIndex(_currentNoticeIndex);
      }

      _scheduleNextCarousel(apiNoticeStayDuration);
    }

    // 重新启动调试定时器
    startDebugTimer(apiNoticeStayDuration);

    notifyListeners();
  }

  ///11，跳转到指定通告索引
  void jumpToAnnouncementIndex(int index) {
    if (index >= 0 && index < _midCarouselController.widgetCount) {
      _currentNoticeIndex = index;
      _midCarouselController.jumpToIndex(index);
      _currentNoticeStartTime = DateTime.now();
      // _logger.i('🔄 跳转到通告索引: $index');
      notifyListeners();
    }
  }

  ///13a，显示欠费总览界面（手动操作模式 - 不启用自动翻页）
  void showArrearTableWidget(VoidCallback onHomeButtonPressed) {
    // 设置显示欠费总览状态
    _isShowingArrearTable = true;
    notifyListeners();
  }

  ///13b，隐藏欠费总览覆盖层
  void hideArrearTableWidget(VoidCallback onHomeButtonPressed,
      int apiNoticeStayDuration, int delayBeforeNotice) {
    // 重置显示欠费总览状态，隐藏覆盖层
    _isShowingArrearTable = false;

    // 通知UI更新，隐藏覆盖层
    notifyListeners();
  }

  ///14，直接显示独立通告（不依赖轮播逻辑）
  void showIndependentAnnouncement(
      AnnouncementModel announcement, VoidCallback? onHomeButtonPressed) {
    // 创建独立通告显示页面，直接根据通告的文件信息
    FileManager fileManager = FileManager();
    fileManager.getFile(announcement.file);

    Widget announcementWidget = Center(
      child: AnnouncementReaderWidget(
        announcement: announcement,
        fileManager: fileManager,
        onHomeButtonPressed: onHomeButtonPressed ??
            () {
              // 默认返回主页行为：跳转到主屏幕
              jumpToAnnouncementIndex(0);
            },
      ),
    );

    // 创建临时轮播内容：只保留主屏幕和当前选中的通告
    Widget mainScreenWidget =
        _createMainScreenWidget(onHomeButtonPressed ?? () {});

    List<Widget> tempWidgets = [
      mainScreenWidget, // 主屏幕保持在索引0
      announcementWidget, // 独立通告在索引1
    ];

    // 设置临时轮播内容
    _midCarouselController.setCarouselArray(tempWidgets);
    _midCarouselController.jumpToIndex(1); // 跳转到独立通告
  }

  ///15，创建主屏幕Widget（辅助方法）
  Widget _createMainScreenWidget(VoidCallback onHomeButtonPressed) {
    return MainScreenWidget(
      onAnnouncementTap: (AnnouncementModel? announcement) {
        if (announcement == null) {
          // 显示欠费查询界面 - 功能已整合到MainScreenWidget中
          // showArrearQueryWidget(onHomeButtonPressed);
        } else {
          // 显示独立通告
          showIndependentAnnouncement(announcement, onHomeButtonPressed);
        }
      },
      onArrearTableTap: () {
        // 显示欠费总览界面
        showArrearTableWidget(onHomeButtonPressed);
      },
    );
  }

  ///16，创建欠费总览轮播Widget（新增方法）
  Widget _createArrearTableCarouselWidget(VoidCallback onHomeButtonPressed) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.grey.shade50,
      child: ArrearTableWidget(
        isInCarouselMode: true, // 标记为轮播模式
        onHomeButtonPressed: () {
          // 点击主页按钮时，跳转回主屏幕（索引0）
          jumpToAnnouncementIndex(0);
        },
        onPaginationComplete: (int totalPages) {
          // 欠費總覽翻頁完成，若有延遲更新先套用
          _isArrearPaginationActive = false;
          if (_pendingCarouselAnnouncements != null) {
            final pending = _pendingCarouselAnnouncements!;
            _pendingCarouselAnnouncements = null;
            _applyCarouselUpdate(pending);
          }
          // 然後切換到下一個通告
          _goToNextCarouselItem();
        },
        onPaginationStart: (int totalPages) {
          // 欠費總覽開始翻頁，動態延長當前通告停留時間，並標記分頁中
          _isArrearPaginationActive = true;
          _extendCurrentNoticeStayTime(totalPages);
        },
      ),
    );
  }

  ///17，动态延长当前通告停留时间（欠费总览开始翻页时调用）
  void _extendCurrentNoticeStayTime(int totalPages) {
    // 计算需要延长的时间：从设置中获取每页翻页时间，默认为5秒
    final appDataProvider = _getAppDataProvider();
    final deviceSettings = appDataProvider?.deviceSettings;
    final durationPerPage = deviceSettings?.paymentTableOnePageDuration;
    final paginationDuration =
        (durationPerPage != null && durationPerPage > 0) ? durationPerPage : 5;

    final int extensionSeconds = totalPages * paginationDuration.toInt();

    // 取消现有的定时器
    _midTimer?.cancel();

    // 重新设置开始时间，相当于重新开始计时
    _currentNoticeStartTime = DateTime.now();

    // 使用延长后的时间重新调度轮播
    final extendedDuration = _noticeDuration.inSeconds + extensionSeconds;

    // 使用延长后的时间调度下一次轮播
    _scheduleNextCarousel(extendedDuration);
  }

  ///18，切换到下一个轮播项（欠费总览翻页完成后调用）
  void _goToNextCarouselItem() {
    if (_isMidCarouselPaused) {
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

      // 重新启动轮播定时器，使用当前API配置的停留时间
      _scheduleNextCarousel(_noticeDuration.inSeconds);
    } catch (e) {
      // 切换失败
    }
  }

  @override
  void dispose() {
    _midTimer?.cancel();
    _midTimer = null;

    _debugTimer?.cancel();
    _debugTimer = null;

    _delayedNoticeTimer?.cancel();
    _delayedNoticeTimer = null;

    super.dispose();
  }

  ///15，自动隐藏所有覆盖层（用于全屏广告状态）
  void autoHideAllOverlays() {
    bool needsNotify = false;

    // 如果欠费查询覆盖层正在显示，则隐藏它（已删除，功能整合到MainScreenWidget）
    // if (_isShowingArrearQuery) {
    //   _isShowingArrearQuery = false;
    //   needsNotify = true;
    // }

    // 如果欠费总览覆盖层正在显示，则隐藏它
    if (_isShowingArrearTable) {
      _isShowingArrearTable = false;
      needsNotify = true;
    }

    // 只有在确实需要隐藏覆盖层时才通知UI更新
    if (needsNotify) {
      notifyListeners();
    }
  }
}
