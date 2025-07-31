import 'dart:async';
import 'package:flutter/material.dart';
import 'package:iboard_app/managers/file_manager.dart';
import 'package:iboard_app/models/announcement_model.dart';
import 'package:iboard_app/widgets/carousel_widget.dart' as custom_carousel;
import 'package:iboard_app/widgets/mainscreen/main_display/announcement_reader_widget.dart';
import 'package:iboard_app/widgets/mainscreen/main_display/mainscreen_widget.dart';
import 'package:iboard_app/widgets/mainscreen/main_display/arrear_display_widget.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:iboard_app/providers/state_provider.dart'; // Added import for CarouselStateProvider
import 'package:provider/provider.dart'; // Added import for Provider

/// 通告轮播Provider
/// 负责管理通告轮播的逻辑、暂停恢复、定时器管理等
class AnnouncementCarouselProvider extends ChangeNotifier {
  final Logger _logger = Logger();

  // 轮播控制器
  late custom_carousel.CarouselController _midCarouselController;

  // 定时器管理
  Timer? _midTimer;
  Timer? _debugTimer;
  Timer? _delayedNoticeTimer; // 延迟启动通告轮播定时器

  // 通告数据
  List<AnnouncementModel> _carouselAnnouncements = [];
  List<AnnouncementModel> _customOrderCarouselAnnouncements = []; // 自定义顺序的轮播通告
  List<dynamic>? _cachedOrderData; // 缓存的顺序配置数据

  // 状态管理
  bool _isMidCarouselPaused = false;
  bool _isShowingArrearQuery = false; // 新增：是否显示欠费查询页面

  // 时间记录相关 - 用于全屏广告暂停恢复
  DateTime? _currentNoticeStartTime; // 当前通告开始时间
  DateTime? _currentNoticePauseTime; // 当前通告暂停时间
  Duration _noticeElapsedTime = Duration.zero; // 通告已播放时间
  Duration _noticeDuration = const Duration(seconds: 5); // 通告总时长
  int _currentNoticeIndex = 0; // 当前通告索引

  // Getters
  custom_carousel.CarouselController get midCarouselController =>
      _midCarouselController;
  List<AnnouncementModel> get carouselAnnouncements =>
      _customOrderCarouselAnnouncements.isNotEmpty
          ? _customOrderCarouselAnnouncements
          : _carouselAnnouncements;
  bool get isMidCarouselPaused => _isMidCarouselPaused;
  bool get isShowingArrearQuery => _isShowingArrearQuery; // 新增：获取欠费查询显示状态
  Duration get noticeDuration => _noticeDuration;
  int get currentNoticeIndex => _currentNoticeIndex;
  DateTime? get currentNoticeStartTime => _currentNoticeStartTime;
  Duration get noticeElapsedTime => _noticeElapsedTime;

  AnnouncementCarouselProvider() {
    _midCarouselController = custom_carousel.CarouselController();
    _loadCustomOrder(); // 加载自定义顺序
    // 添加调试日志
    Future.delayed(Duration(seconds: 2), () {
      _logger.i(
          '🔍 AnnouncementCarouselProvider 初始化完成，缓存数据: ${_cachedOrderData?.length ?? 0}个配置');
    });
  }

  ///1，设置自定义轮播通告顺序
  Future<void> setCarouselList(List<AnnouncementModel> customOrderList) async {
    _customOrderCarouselAnnouncements = List.from(customOrderList);
    await _saveCustomOrder();
    _logger
        .i('🔄 设置自定义通告轮播顺序: ${_customOrderCarouselAnnouncements.length} 个通告');
    notifyListeners();
  }

  ///2，保存自定义顺序到缓存
  Future<void> _saveCustomOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final orderData = _customOrderCarouselAnnouncements
          .map((announcement) => {
                'id': announcement.id,
                'title': announcement.title,
                'order':
                    _customOrderCarouselAnnouncements.indexOf(announcement),
              })
          .toList();
      await prefs.setString(
          'announcement_carousel_order', json.encode(orderData));
      // _logger.i('💾 通告轮播自定义顺序已保存到缓存');
    } catch (e) {
      _logger.e('保存通告轮播顺序失败', error: e);
    }
  }

  ///3，从缓存加载自定义顺序
  Future<void> _loadCustomOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final orderString = prefs.getString('announcement_carousel_order');
      if (orderString != null) {
        final orderData = json.decode(orderString) as List;
        // 保存顺序配置，等待API数据到达后再应用
        _cachedOrderData = orderData;
        _logger.i('📂 从缓存加载通告轮播自定义顺序: ${orderData.length} 个配置');
      }
    } catch (e) {
      _logger.e('加载通告轮播顺序失败', error: e);
    }
  }

  ///4，根据API数据更新自定义顺序（保持用户自定义的顺序）
  void updateCarouselAnnouncementsWithCustomOrder(
      List<AnnouncementModel> newAnnouncements) {
    _carouselAnnouncements = newAnnouncements;

    // 如果有缓存的顺序配置且自定义顺序为空，应用缓存的顺序
    if (_customOrderCarouselAnnouncements.isEmpty && _cachedOrderData != null) {
      _applyCachedOrder(newAnnouncements);
    } else if (_customOrderCarouselAnnouncements.isEmpty) {
      // 如果没有自定义顺序，使用默认顺序
      _customOrderCarouselAnnouncements = List.from(newAnnouncements);
    } else {
      // 有自定义顺序，需要智能更新
      _updateCustomOrderWithNewData(newAnnouncements);
    }

    _logger.i(
        '🔄 更新通告轮播数据: 原始${newAnnouncements.length}个，自定义顺序${_customOrderCarouselAnnouncements.length}个');
  }

  ///5，智能更新自定义顺序列表
  void _updateCustomOrderWithNewData(List<AnnouncementModel> newAnnouncements) {
    // 创建新数据的ID映射
    final newAnnouncementsMap = {
      for (var item in newAnnouncements) item.id: item
    };

    // 移除已删除的通告
    _customOrderCarouselAnnouncements
        .removeWhere((item) => !newAnnouncementsMap.containsKey(item.id));

    // 更新现有通告的数据
    for (int i = 0; i < _customOrderCarouselAnnouncements.length; i++) {
      final currentId = _customOrderCarouselAnnouncements[i].id;
      if (newAnnouncementsMap.containsKey(currentId)) {
        _customOrderCarouselAnnouncements[i] = newAnnouncementsMap[currentId]!;
      }
    }

    // 添加新增的通告到末尾
    final existingIds =
        _customOrderCarouselAnnouncements.map((item) => item.id).toSet();
    final newItems = newAnnouncements
        .where((item) => !existingIds.contains(item.id))
        .toList();
    _customOrderCarouselAnnouncements.addAll(newItems);

    // 保存更新后的顺序
    _saveCustomOrder();

    _logger.i(
        '📝 智能更新自定义顺序: 移除${newAnnouncements.length - newAnnouncementsMap.length}个, 新增${newItems.length}个');
  }

  ///6，应用缓存的顺序配置
  void _applyCachedOrder(List<AnnouncementModel> newAnnouncements) {
    try {
      if (_cachedOrderData == null) return;

      // 创建API数据的ID映射
      final Map<int, AnnouncementModel> newAnnouncementsMap = {
        for (AnnouncementModel announcement in newAnnouncements)
          announcement.id: announcement
      };

      // 按照缓存的顺序重新排列
      final List<AnnouncementModel> orderedAnnouncements = [];

      // 首先添加缓存顺序中存在的通告
      for (final orderItem in _cachedOrderData!) {
        final id = orderItem['id'] as int;
        if (newAnnouncementsMap.containsKey(id)) {
          orderedAnnouncements.add(newAnnouncementsMap[id]!);
          newAnnouncementsMap.remove(id); // 移除已处理的通告
        }
      }

      // 然后添加新增的通告（不在缓存顺序中的）
      orderedAnnouncements.addAll(newAnnouncementsMap.values);

      _customOrderCarouselAnnouncements = orderedAnnouncements;

      // 保存更新后的顺序
      _saveCustomOrder();

      _logger.i('📋 应用缓存的通告顺序: ${orderedAnnouncements.length}个通告');
    } catch (e) {
      _logger.e('应用缓存顺序失败，使用默认顺序', error: e);
      _customOrderCarouselAnnouncements = List.from(newAnnouncements);
    }
  }

  ///7，初始化中部轮播
  void initializeMidWidgets({
    required List<AnnouncementModel> carouselAnnouncements,
    required int apiNoticeStayDuration,
    required int delayBeforeNotice,
    required Function(AnnouncementModel?) onAnnouncementTap,
    required VoidCallback onHomeButtonPressed,
  }) {
    // 使用自定义顺序更新方法
    updateCarouselAnnouncementsWithCustomOrder(carouselAnnouncements);
    _noticeDuration = Duration(seconds: apiNoticeStayDuration);

    // 创建带回调的主屏幕部件
    Widget mainScreenWidget = MainScreenWidget(
      onAnnouncementTap: (AnnouncementModel? announcement) {
        if (announcement == null) {
          // 显示欠费查询界面 - 立即进入手动操作状态
          _logger.i(
              '🔵 [AnnouncementCarouselProvider] 接收到欠费查询请求 (announcement = null)');
          _logger.i('💰 用户点击欠费查询按钮，立即进入手动操作状态');
          showArrearQueryWidget(onHomeButtonPressed);
          _logger.i(
              '🔵 [AnnouncementCarouselProvider] showArrearQueryWidget 调用完成');
        } else {
          _logger.i(
              '📰 [AnnouncementCarouselProvider] 接收到通告点击请求: ${announcement.title}');
          // 查找announcement在轮播通告列表中的索引
          int announcementIndex = carouselAnnouncements.indexOf(announcement);
          if (announcementIndex != -1) {
            // 计算在carousel中的实际索引（主屏幕是索引0，所以announcement从索引1开始）
            int carouselIndex = announcementIndex + 1;
            _logger.i(
                '📰 [AnnouncementCarouselProvider] 准备跳转到轮播索引: $carouselIndex');
            // 跳转到对应的公告页面
            _midCarouselController.jumpToIndex(carouselIndex);
            _logger.i(
                '📰 [AnnouncementCarouselProvider] 已跳转到轮播通告: $carouselIndex (${announcement.title}) - 类型: ${announcement.uiType}');
          } else {
            // 如果点击的通告不在轮播列表中（不是緊急或一般通告），提示用户
            _logger.w(
                '⚠️ [AnnouncementCarouselProvider] 点击的通告不在轮播列表中: ${announcement.title} - 类型: ${announcement.uiType}');
          }
        }
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

    final midWidgets = [
      mainScreenWidget,
      ...announcementWidgets,
    ];
    _midCarouselController.setCarouselArray(midWidgets);

    _logger.i(
        '🎬 [初始化] 中部轮播初始化完成: 主屏幕 + ${this.carouselAnnouncements.length} 个轮播通告 (只包含緊急和一般通告)');
    // _logger.i('📋 [配置] 使用API配置的通告停留时间: ${apiNoticeStayDuration}秒');

    _midTimer?.cancel();
    _delayedNoticeTimer?.cancel(); // 取消之前的延迟定时器

    // 应用启动时先停留在主屏幕，等待 spareDuration 时间后才开始通告轮播
    _currentNoticeIndex = 0; // 初始停留在主屏幕
    _midCarouselController.jumpToIndex(0); // 确保显示主屏幕

    if (announcementWidgets.length > 0 && !_isMidCarouselPaused) {
      // _logger.i('⏳ [启动延迟] 应用启动，在主屏幕停留 ${delayBeforeNotice}秒后开始无限通告轮播');

      // 启动延迟定时器，等待 spareDuration 时间后开始通告轮播
      _delayedNoticeTimer = Timer(Duration(seconds: delayBeforeNotice), () {
        if (announcementWidgets.length > 0 && !_isMidCarouselPaused) {
          // 记录通告开始时间，从第一个通告开始（索引1）
          _currentNoticeStartTime = DateTime.now();
          _currentNoticeIndex = 1; // 从第一个通告开始，跳过主屏幕（索引0）

          // 跳转到第一个通告
          _midCarouselController.jumpToIndex(_currentNoticeIndex);

          _logger.i(
              '🚀 [延迟启动] 通告轮播开始: 开始时间=${_currentNoticeStartTime}, API配置时长=${apiNoticeStayDuration}s, 索引=${_currentNoticeIndex}');

          // 使用统一的持续轮播方法
          _startContinuousNoticeCarousel(apiNoticeStayDuration);
        }
      });
    } else {
      _logger.w(
          '⚠️ [通告轮播] 无法启动: 通告数量=${announcementWidgets.length}, 暂停状态=$_isMidCarouselPaused');
    }
  }

  ///2，启动持续通告轮播（独立方法以确保一致性）- 真正的无限循环
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
      // _logger.i('🔄 [初始化] 跳转到第一个通告，索引: $_currentNoticeIndex');
    }

    // 启动真正的无限循环定时器
    _midTimer =
        Timer.periodic(Duration(seconds: apiNoticeStayDuration), (timer) {
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
      } catch (e) {
        _logger.e('❌ [持续轮播] 切换失败: $e');
        // 发生错误时，尝试重新启动轮播
        Future.delayed(Duration(seconds: 1), () {
          if (!_isMidCarouselPaused) {
            // _logger.i('🔄 [恢复] 尝试重新启动通告轮播');
            _startContinuousNoticeCarousel(apiNoticeStayDuration);
          }
        });
      }
    });

    _logger.i(
        '🚀 [启动] 无限循环通告轮播定时器 (${apiNoticeStayDuration}s间隔) - 通告数量: $announcementCount (跳过主屏幕)');
  }

  ///3，暂停通告轮播
  void pauseMidCarousel() {
    // _logger.i('🛑 暂停通告轮播 - 进入全屏广告状态');

    // 记录当前播放时间
    _currentNoticePauseTime = DateTime.now();

    if (_currentNoticeStartTime != null) {
      _noticeElapsedTime =
          _currentNoticePauseTime!.difference(_currentNoticeStartTime!);
      final remainingNotice = _noticeDuration - _noticeElapsedTime;
      _logger.i(
          '📊 [暂停] 通告 - 已播放: ${_noticeElapsedTime.inSeconds}s/${_noticeDuration.inSeconds}s, 剩余: ${remainingNotice.inSeconds}s');
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
  void resumeMidCarousel(int apiNoticeStayDuration) {
    // _logger.i('▶️ 恢复通告轮播 - 退出全屏广告状态');

    // 设置轮播为运行状态
    _isMidCarouselPaused = false;

    // 恢复轮播中的媒体内容
    _midCarouselController.resumeAllMedia();

    // 恢复通告轮播 - 考虑剩余时间后启动无限循环轮播
    if (_midCarouselController.widgetCount > 1 && !_isMidCarouselPaused) {
      _noticeDuration = Duration(seconds: apiNoticeStayDuration); // 更新当前时长配置

      final remainingNoticeTime = _noticeDuration - _noticeElapsedTime;
      _logger.i(
          '🔄 [恢复] 通告轮播 - API配置=${apiNoticeStayDuration}s, 剩余时间：${remainingNoticeTime.inSeconds}s (已播放: ${_noticeElapsedTime.inSeconds}s)');

      // 重置通告开始时间
      _currentNoticeStartTime = DateTime.now();

      // 确保当前索引在通告范围内
      if (_currentNoticeIndex < 1) {
        _currentNoticeIndex = 1; // 从第一个通告开始
        _midCarouselController.jumpToIndex(_currentNoticeIndex);
        // _logger.i('🔄 [恢复] 设置索引到第一个通告: $_currentNoticeIndex');
      }

      if (remainingNoticeTime.inSeconds > 1) {
        // 剩余时间足够，先等待剩余时间再继续轮播
        _logger.i('⏰ [恢复] 等待剩余时间后继续无限轮播');
        _midTimer = Timer(remainingNoticeTime, () {
          if (!_isMidCarouselPaused) {
            // 时间到，切换到下一个通告并启动无限轮播
            _currentNoticeIndex++;
            if (_currentNoticeIndex >= _midCarouselController.widgetCount) {
              _currentNoticeIndex = 1; // 回到第一个通告
            }
            _midCarouselController.jumpToIndex(_currentNoticeIndex);

            _startContinuousNoticeCarousel(apiNoticeStayDuration);
          }
        });
      } else {
        // 剩余时间不足，直接启动下一个通告并开始无限轮播
        _logger.i('⚡ [恢复] 剩余时间不足，直接切换并启动无限轮播');

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

        _startContinuousNoticeCarousel(apiNoticeStayDuration);
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
    _logger.i(
        '🔍 检查通告轮播恢复条件: announcements=${_carouselAnnouncements.length}, paused=$_isMidCarouselPaused');

    if ((_midCarouselController.widgetCount - 1) > 0 && !_isMidCarouselPaused) {
      // 检查当前定时器是否活跃
      if (_midTimer == null || !_midTimer!.isActive) {
        _logger.w('🔧 检测到通告轮播定时器已停止，尝试重新启动...');

        // 确保当前索引在通告范围内
        if (_currentNoticeIndex < 1) {
          _currentNoticeIndex = 1;
          _midCarouselController.jumpToIndex(_currentNoticeIndex);
        }

        // _logger.i('🔄 恢复通告轮播，当前索引: $_currentNoticeIndex');
        _startContinuousNoticeCarousel(apiNoticeStayDuration);
      }
    } else {
      _logger.w(
          '❌ 不满足通告轮播恢复条件: announcements=${(_midCarouselController.widgetCount - 1)}, paused=$_isMidCarouselPaused');
    }
  }

  ///7，启动调试定时器 - 每秒输出通告轮播的实时状态
  void startDebugTimer(int apiNoticeStayDuration, {bool enableLogging = true}) {
    _debugTimer?.cancel();
    // 禁用通告轮播调试定时器以减少日志输出
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

      _startContinuousNoticeCarousel(apiNoticeStayDuration);
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

  ///12，显示欠费查询界面
  void showArrearQueryWidget(VoidCallback onHomeButtonPressed) {
    _logger.i('💰 [showArrearQueryWidget] 开始显示欠费查询界面');
    _logger.i(
        '💰 [showArrearQueryWidget] 当前状态 - isShowingArrearQuery: $_isShowingArrearQuery');

    // 设置显示欠费查询状态
    _isShowingArrearQuery = true;
    _logger.i('💰 [showArrearQueryWidget] 已设置 isShowingArrearQuery = true');

    _logger.i('💰 [showArrearQueryWidget] 准备调用 notifyListeners()');
    notifyListeners();
    _logger.i('💰 [showArrearQueryWidget] notifyListeners() 调用完成');
  }

  ///13，隐藏欠费查询覆盖层
  void hideArrearQueryWidget(VoidCallback onHomeButtonPressed,
      int apiNoticeStayDuration, int delayBeforeNotice) {
    _logger.i('🏠 [hideArrearQueryWidget] 隐藏欠费查询覆盖层');
    _logger.i(
        '🏠 [hideArrearQueryWidget] 当前状态 - isShowingArrearQuery: $_isShowingArrearQuery');

    // 重置显示欠费查询状态，隐藏覆盖层
    _isShowingArrearQuery = false;
    _logger.i(
        '🏠 [hideArrearQueryWidget] 已设置 isShowingArrearQuery = false，覆盖层将被隐藏');

    // 通知UI更新，隐藏覆盖层
    notifyListeners();
    _logger.i('🏠 [hideArrearQueryWidget] 覆盖层已隐藏，底层轮播内容保持不变');
  }

  @override
  void dispose() {
    _midTimer?.cancel();
    _debugTimer?.cancel();
    _delayedNoticeTimer?.cancel();
    super.dispose();
  }
}
