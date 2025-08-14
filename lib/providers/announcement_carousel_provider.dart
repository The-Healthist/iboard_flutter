import 'dart:async';
import 'package:flutter/material.dart';
import 'package:iboard_app/managers/file_manager.dart';
import 'package:iboard_app/models/announcement_model.dart';
import 'package:iboard_app/widgets/carousel_widget.dart' as custom_carousel;
import 'package:iboard_app/widgets/mainscreen/main_display/announcement_reader_widget.dart';
import 'package:iboard_app/widgets/mainscreen/main_display/mainscreen_widget.dart';
import 'package:iboard_app/widgets/mainscreen/main_display/arrear_table_widget.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:iboard_app/providers/app_data_provider.dart';

class AnnouncementCarouselProvider extends ChangeNotifier {
  final Logger _logger = Logger();
  // 通告轮播自定义顺序缓存key
  static const String _announcementsCarouselOrderKey =
      'announcements_carousel_order';

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
  bool _isShowingArrearTable = false; // 新增：是否显示欠费总览页面

  // 时间记录相关 - 用于全屏广告暂停恢复
  DateTime? _currentNoticeStartTime; // 当前通告开始时间
  DateTime? _currentNoticePauseTime; // 当前通告暂停时间
  Duration _noticeElapsedTime = Duration.zero; // 通告已播放时间
  Duration _noticeDuration = const Duration(seconds: 5); // 通告总时长
  int _currentNoticeIndex = 0; // 当前通告索引

  // AppDataProvider引用 - 用于获取动态设置
  AppDataProvider? _appDataProvider;

  // Getters
  custom_carousel.CarouselController get midCarouselController =>
      _midCarouselController;
  List<AnnouncementModel> get carouselAnnouncements =>
      _customOrderCarouselAnnouncements.isNotEmpty
          ? _customOrderCarouselAnnouncements
          : _carouselAnnouncements;
  bool get isMidCarouselPaused => _isMidCarouselPaused;
  bool get isShowingArrearQuery => _isShowingArrearQuery; // 新增：获取欠费查询显示状态
  bool get isShowingArrearTable => _isShowingArrearTable; // 新增：获取欠费总览显示状态
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

  /// 设置AppDataProvider引用
  void setAppDataProvider(AppDataProvider appDataProvider) {
    _appDataProvider = appDataProvider;
  }

  /// 获取AppDataProvider引用
  AppDataProvider? _getAppDataProvider() {
    return _appDataProvider;
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
          _announcementsCarouselOrderKey, json.encode(orderData));
      // _logger.i('💾 通告轮播自定义顺序已保存到缓存');
    } catch (e) {
      _logger.e('保存通告轮播顺序失败', error: e);
    }
  }

  ///3，从缓存加载自定义顺序
  Future<void> _loadCustomOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final orderString = prefs.getString('announcem  ent_carousel_order');
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
              '📰 [AnnouncementCarouselProvider] 接收到通告点击请求: ${announcement.title} (ID: ${announcement.id})');

          // 新逻辑：直接显示点击的通告，不依赖轮播列表查找
          _logger.i(
              '📰 [AnnouncementCarouselProvider] 直接显示点击的通告，根据文件MD5: ${announcement.file.md5}');

          // 直接显示独立通告
          showIndependentAnnouncement(announcement, onHomeButtonPressed);
        }
      },
      onArrearTableTap: () {
        // 显示欠费总览界面
        _logger.i('📊 [AnnouncementCarouselProvider] 接收到欠费总览请求');
        showArrearTableWidget(onHomeButtonPressed);
        _logger
            .i('📊 [AnnouncementCarouselProvider] showArrearTableWidget 调用完成');
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

    _logger.i(
        '🎬 [初始化] 中部轮播初始化完成: 主屏幕 + ${this.carouselAnnouncements.length} 个轮播通告 + 1个欠费总览 (只包含緊急和一般通告)');
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
          _scheduleNextCarousel(apiNoticeStayDuration);
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
      _logger.w('⚠️ [调度轮播] 跳过调度: 通告数量不足');
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
        _logger.i('📊 [轮播控制] 已切换到欠费总览，等待自动翻页完成');
        // 欠费总览会通过回调继续轮播，这里不再调度下一次
      } else {
        // 继续调度下一次轮播
        _scheduleNextCarousel(apiNoticeStayDuration);
        // _logger.i(
        //     '📝 [轮播切换] 切换通告(API=${apiNoticeStayDuration}s) 索引: $_currentNoticeIndex/${_midCarouselController.widgetCount}');
      }
    } catch (e) {
      _logger.e('❌ [轮播执行] 切换失败: $e');
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

      // 移除特殊处理，现在通过动态延长时间来处理欠费总览

      final remainingNoticeTime = _noticeDuration - _noticeElapsedTime;
      // _logger.i(
      //     '🔄 [恢复] 通告轮播 - API配置=${apiNoticeStayDuration}s, 剩余时间：${remainingNoticeTime.inSeconds}s (已播放: ${_noticeElapsedTime.inSeconds}s)');

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
        // _logger.i('⏰ [恢复] 等待剩余时间后继续无限轮播');
        _midTimer = Timer(remainingNoticeTime, () {
          if (!_isMidCarouselPaused) {
            // 检查当前是否在欠费总览页面
            final isCurrentlyOnArrearTable =
                _currentNoticeIndex == (_midCarouselController.widgetCount - 1);

            if (isCurrentlyOnArrearTable) {
              // 如果当前在欠费总览页面，不直接切换，让自动翻页完成
              _logger.i('📊 [定时切换] 当前在欠费总览页面，等待自动翻页完成');
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
        _logger.i('⚡ [恢复] 剩余时间不足，检查是否为欠费总览');

        // 检查当前是否在欠费总览页面（最后一个索引）
        final isCurrentlyOnArrearTable =
            _currentNoticeIndex == (_midCarouselController.widgetCount - 1);

        if (isCurrentlyOnArrearTable) {
          // 如果当前在欠费总览页面，不直接切换，继续展示欠费总览
          _logger.i('📊 [恢复] 当前在欠费总览页面，继续展示并恢复自动翻页');

          // 重置开始时间，给欠费总览足够时间完成翻页
          _currentNoticeStartTime = DateTime.now();

          // 不调用 _scheduleNextCarousel，让欠费总览的翻页完成回调来处理切换
          _logger.i('📊 [恢复] 等待欠费总览自动翻页完成后再切换通告');
        } else {
          // 不是欠费总览，正常处理：直接启动下一个通告并开始无限轮播
          _logger.i('⚡ [恢复] 非欠费总览页面，直接切换并启动无限轮播');

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
      _logger.w(
          '❌ 不满足通告轮播恢复条件: announcements=${(_midCarouselController.widgetCount - 1)}, paused=$_isMidCarouselPaused');
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

  ///13a，显示欠费总览界面（手动操作模式 - 不启用自动翻页）
  void showArrearTableWidget(VoidCallback onHomeButtonPressed) {
    _logger.i('📊 [showArrearTableWidget] 开始显示欠费总览界面（手动操作模式）');
    _logger.i(
        '📊 [showArrearTableWidget] 当前状态 - isShowingArrearTable: $_isShowingArrearTable');

    // 设置显示欠费总览状态
    _isShowingArrearTable = true;
    _logger.i(
        '📊 [showArrearTableWidget] 已设置 isShowingArrearTable = true（手动模式，无自动翻页）');

    _logger.i('📊 [showArrearTableWidget] 准备调用 notifyListeners()');
    notifyListeners();
    _logger.i('📊 [showArrearTableWidget] notifyListeners() 调用完成');
  }

  ///13b，隐藏欠费总览覆盖层
  void hideArrearTableWidget(VoidCallback onHomeButtonPressed,
      int apiNoticeStayDuration, int delayBeforeNotice) {
    _logger.i('🏠 [hideArrearTableWidget] 隐藏欠费总览覆盖层');
    _logger.i(
        '🏠 [hideArrearTableWidget] 当前状态 - isShowingArrearTable: $_isShowingArrearTable');

    // 重置显示欠费总览状态，隐藏覆盖层
    _isShowingArrearTable = false;
    _logger.i(
        '🏠 [hideArrearTableWidget] 已设置 isShowingArrearTable = false，覆盖层将被隐藏');

    // 通知UI更新，隐藏覆盖层
    notifyListeners();
    _logger.i('🏠 [hideArrearTableWidget] 覆盖层已隐藏，底层轮播内容保持不变');
  }

  ///14，直接显示独立通告（不依赖轮播逻辑）
  void showIndependentAnnouncement(
      AnnouncementModel announcement, VoidCallback? onHomeButtonPressed) {
    _logger.i(
        '📰 [独立通告] 直接显示通告: ${announcement.title} (ID: ${announcement.id}, MD5: ${announcement.file.md5})');

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
              _logger.i('📰 [独立通告] 用户点击返回主页，已跳转到主屏幕');
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

    _logger.i('📰 [独立通告] 已显示独立通告: ${announcement.title}，索引1，用户可通过返回按钮回到主屏幕');
  }

  ///15，创建主屏幕Widget（辅助方法）
  Widget _createMainScreenWidget(VoidCallback onHomeButtonPressed) {
    return MainScreenWidget(
      onAnnouncementTap: (AnnouncementModel? announcement) {
        if (announcement == null) {
          // 显示欠费查询界面
          showArrearQueryWidget(onHomeButtonPressed);
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
    _logger.i('📊 [创建欠费总览] 创建欠费总览轮播widget');

    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.grey.shade50,
      child: ArrearTableWidget(
        isInCarouselMode: true, // 标记为轮播模式
        onHomeButtonPressed: () {
          // 点击主页按钮时，跳转回主屏幕（索引0）
          _logger.i('🏠 [欠费总览轮播] 用户点击主页按钮，返回主屏幕');
          jumpToAnnouncementIndex(0);
        },
        onPaginationComplete: (int totalPages) {
          // 欠费总览翻页完成，切换到下一个通告
          _logger.i('📄 [欠费总览轮播] 翻页完成（共$totalPages页），切换到下一个通告');
          _goToNextCarouselItem();
        },
        onPaginationStart: (int totalPages) {
          // 欠费总览开始翻页，动态延长当前通告停留时间
          _logger.i('📄 [欠费总览轮播] 开始翻页（共$totalPages页），动态延长停留时间');
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
    final paginationDuration = deviceSettings?.paymentTableOnePageDuration ?? 5;

    final int extensionSeconds = totalPages * paginationDuration.toInt();
    _logger.i(
        '⏰ [动态延长] 延长当前通告停留时间: ${extensionSeconds}秒（共${totalPages}页，每页${paginationDuration}秒）');

    // 取消现有的定时器
    _midTimer?.cancel();

    // 重新设置开始时间，相当于重新开始计时
    _currentNoticeStartTime = DateTime.now();

    // 使用延长后的时间重新调度轮播
    final extendedDuration = _noticeDuration.inSeconds + extensionSeconds;
    _logger.i(
        '⏰ [动态延长] 原始时长: ${_noticeDuration.inSeconds}秒, 延长后: ${extendedDuration}秒');

    // 使用延长后的时间调度下一次轮播
    _scheduleNextCarousel(extendedDuration);
  }

  ///18，切换到下一个轮播项（欠费总览翻页完成后调用）
  void _goToNextCarouselItem() {
    if (_isMidCarouselPaused) {
      _logger.w('⚠️ [切换轮播] 轮播已暂停，跳过切换');
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
          '🔄 [欠费总览完成] 切换到下一个轮播项，索引: $_currentNoticeIndex/${_midCarouselController.widgetCount}');

      // 重新启动轮播定时器，使用当前API配置的停留时间
      _scheduleNextCarousel(_noticeDuration.inSeconds);
    } catch (e) {
      _logger.e('❌ [切换轮播] 切换失败: $e');
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
    _logger.i('🎬 [autoHideAllOverlays] 全屏广告状态触发，自动隐藏所有覆盖层');

    bool needsNotify = false;

    // 如果欠费查询覆盖层正在显示，则隐藏它
    if (_isShowingArrearQuery) {
      _logger.i('🎬 [autoHideAllOverlays] 自动隐藏欠费查询覆盖层');
      _isShowingArrearQuery = false;
      needsNotify = true;
    }

    // 如果欠费总览覆盖层正在显示，则隐藏它
    if (_isShowingArrearTable) {
      _logger.i('🎬 [autoHideAllOverlays] 自动隐藏欠费总览覆盖层');
      _isShowingArrearTable = false;
      needsNotify = true;
    }

    // 只有在确实需要隐藏覆盖层时才通知UI更新
    if (needsNotify) {
      notifyListeners();
      _logger.i('🎬 [autoHideAllOverlays] 所有覆盖层已自动隐藏，通告轮播现在可见');
    } else {
      _logger.i('🎬 [autoHideAllOverlays] 没有需要隐藏的覆盖层');
    }
  }
}
