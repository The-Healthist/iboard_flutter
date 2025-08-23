import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:iboard_app/managers/file_manager.dart';
import 'package:iboard_app/models/announcement_model.dart';
import 'package:iboard_app/widgets/carousel_widget.dart' as custom_carousel;
import 'package:iboard_app/widgets/mainscreen/main_display/announcement_reader_widget.dart';
import 'package:iboard_app/widgets/mainscreen/main_display/mainscreen_widget.dart';
import 'package:iboard_app/widgets/mainscreen/main_display/arrear_table_widget.dart';
// import 'package:shared_preferences/shared_preferences.dart'; // 已删除，不再使用
// import 'dart:convert';
import 'package:iboard_app/providers/app_data_provider.dart';
import 'package:iboard_app/providers/arrear_provider.dart'; // 新增

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
  // bool _isShowingArrearQue
  bool _isShowingArrearTable = false;

  // 时间记录相关 - 用于全屏广告暂停恢复
  DateTime? _currentNoticeStartTime; // 当前通告开始时间
  DateTime? _currentNoticePauseTime; // 当前通告暂停时间
  Duration _noticeElapsedTime = Duration.zero; // 通告已播放时间
  Duration _noticeDuration = const Duration(seconds: 5); // 通告总时长
  int _currentNoticeIndex = 0; // 当前通告索引

  // 新增：記錄視頻播放進度
  Map<int, Duration> _videoPlaybackPositions = {}; // 記錄每個索引的視頻播放進度

  // AppDataProvider引用 - 用于获取动态设置
  late AppDataProvider _appDataProvider; // AppDataProvider引用
  late VoidCallback _homeButtonCallback = () {}; // 初始化为空函数，避免late错误

  bool _isArrearPaginationActive = false;
  late ArrearProvider? _arrearProvider; // 新增

  // 緩存Widget實例和FileManager
  final Map<String, Widget> _widgetCache = {};
  final Map<String, FileManager> _fileManagerCache = {};

  // Getters
  custom_carousel.CarouselController get midCarouselController =>
      _midCarouselController;
  List<AnnouncementModel> get carouselAnnouncements => _carouselAnnouncements;
  bool get isMidCarouselPaused => _isMidCarouselPaused;

  bool get isShowingArrearTable => _isShowingArrearTable;
  Duration get noticeDuration => _noticeDuration;
  int get currentNoticeIndex => _currentNoticeIndex;
  DateTime? get currentNoticeStartTime => _currentNoticeStartTime;
  Duration get noticeElapsedTime => _noticeElapsedTime;

  /// 新增：验证轮播组件状态的方法
  bool get isCarouselReady {
    try {
      // 修复：确保即使没有通告也能正常工作（至少要有主屏幕和缴费表单）
      return _midCarouselController.widgetCount >= 2;
    } catch (e) {
      debugPrint('[AnnouncementCarousel] 状态验证失败: $e');
      return false;
    }
  }

  /// 新增：获取轮播组件状态信息
  String get carouselStatus {
    try {
      return 'Widget数量: ${_midCarouselController.widgetCount}, '
          '当前索引: $_currentNoticeIndex, '
          '通告数量: ${_carouselAnnouncements.length}, '
          '回调设置: true, '
          '轮播暂停: $_isMidCarouselPaused, '
          '支持无通告模式: $supportsNoAnnouncementMode';
    } catch (e) {
      return '状态获取失败: $e';
    }
  }

  /// 新增：检查轮播组件健康状态
  bool get isCarouselHealthy {
    try {
      // 修复：确保即使没有通告也能正常工作（至少要有主屏幕和缴费表单）
      return _midCarouselController.widgetCount >= 2 &&
          _currentNoticeIndex >= 0 &&
          _currentNoticeIndex < _midCarouselController.widgetCount;
    } catch (e) {
      debugPrint('[AnnouncementCarousel] 健康检查失败: $e');
      return false;
    }
  }

  AnnouncementCarouselProvider() {
    _midCarouselController = custom_carousel.CarouselController();
  }

  /// 设置AppDataProvider引用
  void setAppDataProvider(AppDataProvider appDataProvider) {
    _appDataProvider = appDataProvider;
  }

  /// 設置ArrearProvider引用
  void setArrearProvider(ArrearProvider arrearProvider) {
    _arrearProvider = arrearProvider;
  }

  ///1，更新轮播通告列表（由AnnouncementProvider调用）
  void updateCarouselList(List<AnnouncementModel> newCarouselAnnouncements) {
    // 使用智能增量更新
    _smartUpdateCarousel(newCarouselAnnouncements);
  }

  ///2a，智能更新轮播内容（增量更新，不破坏当前状态）
  void _smartUpdateCarousel(List<AnnouncementModel> newCarouselAnnouncements) {
    // 如果数据完全相同，不需要更新
    if (_isAnnouncementListEqual(
        _carouselAnnouncements, newCarouselAnnouncements)) {
      return;
    }

    _carouselAnnouncements =
        List<AnnouncementModel>.from(newCarouselAnnouncements);

    // 构建widget映射表
    final Map<String, Widget> widgetMap = {};
    final List<String> orderedKeys = [];
    final Set<String> usedKeys = {};

    // 1. 主屏幕widget（固定key）- 確保始終創建
    const mainScreenKey = 'main_screen';
    try {
      // 移除對_homeButtonCallback的null檢查，確保主屏幕widget始終被創建
      _widgetCache[mainScreenKey] =
          _createMainScreenWidget(_homeButtonCallback);
      widgetMap[mainScreenKey] = _widgetCache[mainScreenKey]!;
      orderedKeys.add(mainScreenKey);
      usedKeys.add(mainScreenKey);
      debugPrint('[AnnouncementCarousel] 主屏幕widget創建成功');
    } catch (e) {
      debugPrint('[AnnouncementCarousel] 主屏幕widget創建失敗: $e');
      // 創建一個簡單的備用主屏幕widget
      _widgetCache[mainScreenKey] = Container(
        child: const Center(
          child: Text('主屏幕載入中...', style: TextStyle(fontSize: 18)),
        ),
      );
      widgetMap[mainScreenKey] = _widgetCache[mainScreenKey]!;
      orderedKeys.add(mainScreenKey);
      usedKeys.add(mainScreenKey);
    }

    // 2. 通告widgets（使用通告ID作为key）- 智能緩存
    for (final announcement in _carouselAnnouncements) {
      final key = 'announcement_${announcement.id}';

      // 檢查是否需要更新Widget（新通告或內容變化）
      if (!_widgetCache.containsKey(key) ||
          _hasAnnouncementChanged(key, announcement)) {
        try {
          // 重用或創建FileManager
          if (!_fileManagerCache.containsKey(key)) {
            _fileManagerCache[key] = FileManager();
          }
          final fileManager = _fileManagerCache[key]!;
          fileManager.getFile(announcement.file);

          // 獲取該通告的初始播放進度
          final widgetIndex = orderedKeys.indexOf(key);
          final initialPosition =
              getVideoProgress(widgetIndex) ?? Duration.zero;

          // 創建新Widget並緩存
          _widgetCache[key] = Center(
            child: AnnouncementReaderWidget(
              key: ValueKey(key),
              announcement: announcement,
              fileManager: fileManager,
              onHomeButtonPressed: _homeButtonCallback,
              onVideoProgressChanged: (Duration position) {
                // 記錄視頻播放進度
                final widgetIndex = orderedKeys.indexOf(key);
                if (widgetIndex >= 0) {
                  recordVideoProgress(widgetIndex, position);
                }
              },
              initialPlaybackPosition: initialPosition,
            ),
          );
        } catch (e) {
          debugPrint('[AnnouncementCarousel] 通告widget創建失敗: $e');
          continue; // 跳過失敗的通告
        }
      }

      widgetMap[key] = _widgetCache[key]!;
      orderedKeys.add(key);
      usedKeys.add(key);
    }

    // 3. 欠费总览widget（使用数据版本作为key）- 確保創建
    final arrearDataVersion = _arrearProvider?.currentDataVersion ?? 'default';
    final arrearTableKey = 'arrear_table_$arrearDataVersion';

    try {
      if (!_widgetCache.containsKey(arrearTableKey) ||
          _arrearProvider?.hasPendingUpdate == true) {
        if (_arrearProvider != null) {
          _widgetCache[arrearTableKey] =
              _arrearProvider!.createArrearTableWidget(
            onHomeButtonPressed: () {
              jumpToAnnouncementIndex(0);
            },
            isInCarouselMode: true,
            onPaginationComplete: (int totalPages) {
              _isArrearPaginationActive = false;
              _goToNextCarouselItem();
            },
            onPaginationStart: (int totalPages) {
              _isArrearPaginationActive = true;
              _extendCurrentNoticeStayTime(totalPages);
            },
          );

          // 清理旧的欠费表单缓存
          _widgetCache.removeWhere((key, value) =>
              key.startsWith('arrear_table_') && key != arrearTableKey);

          // 标记更新已应用
          _arrearProvider!.markUpdateApplied();
        } else {
          // 如果没有ArrearProvider，創建一個簡單的備用widget
          _widgetCache[arrearTableKey] = Container(
            child: const Center(
              child: Text('欠費數據載入中...', style: TextStyle(fontSize: 18)),
            ),
          );
        }
      }

      widgetMap[arrearTableKey] = _widgetCache[arrearTableKey]!;
      orderedKeys.add(arrearTableKey);
      usedKeys.add(arrearTableKey);
      debugPrint('[AnnouncementCarousel] 欠費總覽widget創建成功');
    } catch (e) {
      debugPrint('[AnnouncementCarousel] 欠費總覽widget創建失敗: $e');
      // 創建一個簡單的備用widget
      _widgetCache[arrearTableKey] = Container(
        child: const Center(
          child: Text('欠費數據暫不可用', style: TextStyle(fontSize: 18)),
        ),
      );
      widgetMap[arrearTableKey] = _widgetCache[arrearTableKey]!;
      orderedKeys.add(arrearTableKey);
      usedKeys.add(arrearTableKey);
    }

    // 清理不再使用的緩存
    _cleanupUnusedCache(usedKeys);

    // 調試信息：檢查widget映射表
    debugPrint('[AnnouncementCarousel] 智能更新完成: ${widgetMap.length} widgets');
    debugPrint('[AnnouncementCarousel] Widget keys: $orderedKeys');

    // 確保至少有基本的widgets
    if (widgetMap.isEmpty || orderedKeys.isEmpty) {
      debugPrint('[AnnouncementCarousel] 警告: 沒有可用的widgets，創建緊急備用widget');
      const emergencyKey = 'emergency_main';
      widgetMap[emergencyKey] = Container(
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.home, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text('主屏幕',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('系統正在初始化...',
                  style: TextStyle(fontSize: 16, color: Colors.grey)),
            ],
          ),
        ),
      );
      orderedKeys.add(emergencyKey);
    }

    // 修复：确保在没有通告时也有缴费表单widget
    if (_carouselAnnouncements.isEmpty && widgetMap.length < 2) {
      debugPrint('[AnnouncementCarousel] 无通告数据，确保创建缴费表单widget');

      // 强制创建缴费表单widget
      final arrearDataVersion =
          _arrearProvider?.currentDataVersion ?? 'default';
      final arrearTableKey = 'arrear_table_$arrearDataVersion';

      if (!widgetMap.containsKey(arrearTableKey)) {
        try {
          if (_arrearProvider != null) {
            _widgetCache[arrearTableKey] =
                _arrearProvider!.createArrearTableWidget(
              onHomeButtonPressed: () {
                jumpToAnnouncementIndex(0);
              },
              isInCarouselMode: true,
              onPaginationComplete: (int totalPages) {
                _isArrearPaginationActive = false;
                _goToNextCarouselItem();
              },
              onPaginationStart: (int totalPages) {
                _isArrearPaginationActive = true;
                _extendCurrentNoticeStayTime(totalPages);
              },
            );
          } else {
            _widgetCache[arrearTableKey] = Container(
              child: const Center(
                child: Text('欠費數據載入中...', style: TextStyle(fontSize: 18)),
              ),
            );
          }

          widgetMap[arrearTableKey] = _widgetCache[arrearTableKey]!;
          orderedKeys.add(arrearTableKey);
          debugPrint('[AnnouncementCarousel] 强制创建缴费表单widget成功');
        } catch (e) {
          debugPrint('[AnnouncementCarousel] 强制创建缴费表单widget失败: $e');
        }
      }
    }

    // 使用智能更新，保持当前查看的内容不变
    _midCarouselController.smartUpdateCarousel(widgetMap, orderedKeys);

    // 確保轮播组件有内容
    if (_midCarouselController.widgetCount > 0) {
      // 如果當前索引無效，重置到主屏幕
      if (_currentNoticeIndex >= _midCarouselController.widgetCount) {
        _currentNoticeIndex = 0;
      }
      // 確保跳轉到正確的索引
      _midCarouselController.jumpToIndex(_currentNoticeIndex);
      debugPrint(
          '[AnnouncementCarousel] 跳轉到索引: $_currentNoticeIndex, 總數: ${_midCarouselController.widgetCount}');
    } else {
      debugPrint('[AnnouncementCarousel] 嚴重錯誤: 轮播组件仍然没有内容!');
    }

    notifyListeners();
  }

  ///2c，检查通告列表是否相同
  bool _isAnnouncementListEqual(
      List<AnnouncementModel> list1, List<AnnouncementModel> list2) {
    if (list1.length != list2.length) return false;
    for (int i = 0; i < list1.length; i++) {
      if (list1[i].id != list2[i].id) return false;
    }
    return true;
  }

  ///2d，檢查通告內容是否變化
  bool _hasAnnouncementChanged(String key, AnnouncementModel newAnnouncement) {
    // 這裡需要根據實際邏輯判斷通告內容是否變化
    // 暫時返回false，表示內容未變化
    return false;
  }

  /// 自动隐藏所有覆盖层（欠费查询和欠费总览）
  bool autoHideAllOverlays() {
    // 這裡可以添加更詳細的比較邏輯
    // 目前簡單比較ID和文件MD5
    // 由於此方法返回bool，需要確保所有路徑都有返回值
    // 這裡假設如果沒有找到相關的widget，則不需要隱藏，返回false
    return false;
  }

  ///2e，清理不再使用的緩存
  void _cleanupUnusedCache(Set<String> usedKeys) {
    // 清理Widget緩存
    _widgetCache.removeWhere((key, value) => !usedKeys.contains(key));

    // 清理FileManager緩存
    _fileManagerCache.removeWhere((key, value) => !usedKeys.contains(key));
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
    try {
      debugPrint('[AnnouncementCarousel] 开始初始化中部轮播...');

      // 保存主页回调
      _homeButtonCallback = onHomeButtonPressed;
      _noticeDuration = Duration(seconds: apiNoticeStayDuration);

      // 確保通告數據不為空，如果为空則使用空列表
      _carouselAnnouncements =
          List<AnnouncementModel>.from(carouselAnnouncements);

      // 強制清理緩存，確保重新創建所有widget
      _widgetCache.clear();
      _fileManagerCache.clear();

      // 重置暫停相關的狀態，確保初始化時狀態乾淨
      _currentNoticePauseTime = null;
      _noticeElapsedTime = Duration.zero;

      // 清空視頻播放進度記錄
      _videoPlaybackPositions.clear();

      // 初始化时使用智能更新 - 确保即使没有通告数据也能显示主屏幕
      _smartUpdateCarousel(_carouselAnnouncements);

      _midTimer?.cancel();
      _delayedNoticeTimer?.cancel();

      // 确保轮播组件有内容後，重置當前索引到主屏幕
      if (_midCarouselController.widgetCount > 0) {
        _currentNoticeIndex = 0;
        _midCarouselController.jumpToIndex(0);
        debugPrint('[AnnouncementCarousel] 初始化完成，跳轉到主屏幕');
      } else {
        debugPrint('[AnnouncementCarousel] 警告：初始化后轮播组件仍无内容');
        // 尝试恢复基本内容
        _ensureBasicContent();
      }

      // 修复：确保轮播组件至少有2个widget（主屏幕和缴费表单）
      if (_midCarouselController.widgetCount < 2) {
        debugPrint('[AnnouncementCarousel] 警告：轮播组件内容不足，尝试恢复基本内容');
        _ensureBasicContent();
      }

      // 初始化视频播放进度缓存
      _initializeVideoProgressCache();

      // 启动轮播定时器 - 无论是否有通告数据都要启动
      if (!_isMidCarouselPaused) {
        _delayedNoticeTimer = Timer(Duration(seconds: delayBeforeNotice), () {
          if (!_isMidCarouselPaused) {
            try {
              // 修复：无论是否有通告数据，都从索引1开始轮播
              // 索引0是主屏幕，索引1开始是内容（通告或缴费表单）
              _currentNoticeStartTime = DateTime.now();
              _currentNoticeIndex = 1;

              // 确保索引在有效范围内
              if (_currentNoticeIndex >= _midCarouselController.widgetCount) {
                _currentNoticeIndex = 1; // 如果只有一个widget（主屏幕），重置到1
              }

              _midCarouselController.jumpToIndex(_currentNoticeIndex);

              if (_carouselAnnouncements.isNotEmpty) {
                debugPrint('[AnnouncementCarousel] 通告轮播定时器启动成功 - 有通告数据');
              } else {
                debugPrint('[AnnouncementCarousel] 缴费表单轮播定时器启动成功 - 无通告数据');
              }

              // 使用统一的持续轮播方法
              _scheduleNextCarousel(apiNoticeStayDuration);
            } catch (e) {
              debugPrint('[AnnouncementCarousel] 轮播定时器启动失败: $e');
              // 如果启动失败，尝试恢复基本内容
              _ensureBasicContent();
            }
          }
        });
      }

      debugPrint(
          '[AnnouncementCarousel] 初始化完成，通告数量: ${_carouselAnnouncements.length}');
    } catch (e) {
      debugPrint('[AnnouncementCarousel] 初始化失败: $e');
      // 即使初始化失败，也要确保有基本内容
      _ensureBasicContent();
    }
  }

  ///2a，调度下一个轮播切换（智能定时器，自适应间隔减少系统调用）
  void _scheduleNextCarousel(int apiNoticeStayDuration) {
    try {
      _midTimer?.cancel();

      if (_isMidCarouselPaused) {
        debugPrint('[AnnouncementCarousel] 轮播已暂停，停止调度');
        return;
      }

      // 验证轮播组件状态
      if (!isCarouselHealthy) {
        debugPrint('[AnnouncementCarousel] 轮播组件状态异常，尝试恢复...');
        _ensureBasicContent();
        return;
      }

      // 修复：确保即使没有通告也能轮播（至少要有主屏幕和缴费表单）
      final currentWidgetCount = _midCarouselController.widgetCount;
      if (currentWidgetCount < 2) {
        debugPrint('[AnnouncementCarousel] 轮播组件内容不足，尝试恢复基本内容');
        _ensureBasicContent();
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

      debugPrint('[AnnouncementCarousel] 轮播调度成功，检查间隔: ${checkInterval}秒');
    } catch (e) {
      debugPrint('[AnnouncementCarousel] 轮播调度失败: $e');
      // 调度失败时，延迟重试
      Future.delayed(const Duration(seconds: 2), () {
        if (!_isMidCarouselPaused) {
          _scheduleNextCarousel(apiNoticeStayDuration);
        }
      });
    }
  }

  ///2c，启动欠费总览翻页逻辑
  void _startArrearTablePagination(int apiNoticeStayDuration) {
    try {
      debugPrint('[AnnouncementCarousel] 启动欠费总览翻页逻辑');

      // 标记欠费总览正在活跃
      _isArrearPaginationActive = true;

      // 欠费总览会通过回调继续轮播，这里不需要额外调度
      // 翻页完成后会调用 _goToNextCarouselItem 方法
    } catch (e) {
      debugPrint('[AnnouncementCarousel] 启动欠费总览翻页失败: $e');
      // 如果启动失败，延迟重试
      Future.delayed(const Duration(seconds: 2), () {
        if (!_isMidCarouselPaused) {
          _scheduleNextCarousel(apiNoticeStayDuration);
        }
      });
    }
  }

  ///2d，检查并推进轮播（减少定时器创建）
  void _checkAndAdvanceCarousel(int apiNoticeStayDuration) {
    try {
      if (_isMidCarouselPaused) {
        debugPrint('[AnnouncementCarousel] 轮播已暂停，稍后重新检查');
        // 暂停状态，稍后重新检查
        _scheduleNextCarousel(apiNoticeStayDuration);
        return;
      }

      // 验证轮播组件状态
      if (!isCarouselHealthy) {
        debugPrint('[AnnouncementCarousel] 轮播组件状态异常，尝试恢复...');
        _ensureBasicContent();
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
        // 在切换前记录当前内容的播放进度
        _recordCurrentVideoProgress();

        // 计算下一个索引，跳过主屏幕（索引0）
        _currentNoticeIndex++;
        if (_currentNoticeIndex >= _midCarouselController.widgetCount) {
          _currentNoticeIndex = 1; // 回到第一个内容，跳过主屏幕
        }

        // 检查是否切换到欠费总览（最后一个索引）
        final isArrearTable =
            _currentNoticeIndex == (_midCarouselController.widgetCount - 1);

        // 跳转到下一个内容
        _midCarouselController.jumpToIndex(_currentNoticeIndex);

        // 记录新内容开始时间
        _currentNoticeStartTime = DateTime.now();

        // 重置已播放时间
        _noticeElapsedTime = Duration.zero;

        // 确保新内容的播放进度缓存存在
        if (!_videoPlaybackPositions.containsKey(_currentNoticeIndex)) {
          _videoPlaybackPositions[_currentNoticeIndex] = Duration.zero;
        }

        debugPrint(
            '[AnnouncementCarousel] 轮播切换到索引: $_currentNoticeIndex, 是否欠费总览: $isArrearTable');

        // 如果切换到欠费总览，启动翻页逻辑
        if (isArrearTable) {
          // 欠费总览需要特殊处理，启动翻页定时器
          _startArrearTablePagination(apiNoticeStayDuration);
        } else {
          // 普通内容，继续轮播
          _scheduleNextCarousel(apiNoticeStayDuration);
        }
      } catch (e) {
        debugPrint('[AnnouncementCarousel] 轮播切换失败: $e');
        // 切换失败时，延迟重试
        Future.delayed(const Duration(seconds: 2), () {
          if (!_isMidCarouselPaused) {
            _scheduleNextCarousel(apiNoticeStayDuration);
          }
        });
      }
    } catch (e) {
      debugPrint('[AnnouncementCarousel] 轮播检查失败: $e');
      // 检查失败时，延迟重试
      Future.delayed(const Duration(seconds: 2), () {
        if (!_isMidCarouselPaused) {
          _scheduleNextCarousel(apiNoticeStayDuration);
        }
      });
    }
  }

  ///3，暂停通告轮播
  void pauseMidCarousel() {
    debugPrint('[AnnouncementCarousel] 🛑 暂停通告轮播 - 进入全屏广告状态');

    // 保存暂停状态
    _savePauseState();

    // 设置轮播为暂停状态
    _isMidCarouselPaused = true;

    // 暂停所有定时器 - 确保完全暂停
    _pauseAllTimers();

    // 暂停轮播中的媒体内容
    _midCarouselController.pauseAllMedia();

    // 使用 WidgetsBinding.instance.addPostFrameCallback 延迟通知
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (hasListeners) {
        notifyListeners();
      }
    });
  }

  /// 新增：暂停所有定时器的方法
  void _pauseAllTimers() {
    // 取消主轮播定时器
    _midTimer?.cancel();
    _midTimer = null;

    // 取消延迟启动定时器
    _delayedNoticeTimer?.cancel();
    _delayedNoticeTimer = null;

    // 取消调试定时器
    _debugTimer?.cancel();
    _debugTimer = null;

    debugPrint('[AnnouncementCarousel] 所有定时器已暂停');
  }

  ///4，恢复通告轮播
  void resumeMidCarousel(int apiNoticeStayDuration,
      {bool forceJumpToIndex = false}) {
    debugPrint('[AnnouncementCarousel] ▶️ 恢复通告轮播 - 退出全屏广告状态');

    // 显式取消旧的定时器，避免重复启动
    _pauseAllTimers();

    // 设置轮播为运行状态
    _isMidCarouselPaused = false;

    // 恢复暂停状态
    _restorePauseState();

    // 恢复轮播中的媒体内容
    _midCarouselController.resumeAllMedia();

    // 恢復通告輪播 - 使用視頻播放進度而不是時間
    if (_midCarouselController.widgetCount > 1 && !_isMidCarouselPaused) {
      _noticeDuration = Duration(seconds: apiNoticeStayDuration); // 更新当前时长配置

      // 重要修復：不要重置開始時間，保持暫停前的時間狀態
      // 這樣可以從暫停位置繼續，而不是重新開始
      if (_currentNoticeStartTime == null) {
        _currentNoticeStartTime = DateTime.now();
      }

      // 只有在强制跳转时才确保当前索引在通告范围内
      if (forceJumpToIndex && _currentNoticeIndex < 1) {
        _currentNoticeIndex = 1; // 从第一个内容开始（通告或缴费表单）
        _midCarouselController.jumpToIndex(_currentNoticeIndex);
        debugPrint(
            '[AnnouncementCarousel] 🔄 [恢复] 设置索引到第一个内容: $_currentNoticeIndex');
      }

      // 使用視頻播放進度來計算剩餘時間
      final remainingNoticeTime =
          _calculateSmartRemainingTime(apiNoticeStayDuration);

      if (remainingNoticeTime.inSeconds > 1) {
        // 剩余时间足够，先等待剩余时间再继续轮播
        debugPrint(
            '[AnnouncementCarousel] ⏰ [恢复] 等待剩余时间后继续无限轮播，剩余: ${remainingNoticeTime.inSeconds}秒');

        // 更新当前通告开始时间，使其能正确计算剩余时间
        _currentNoticeStartTime = DateTime.now();
        // 保持 _noticeElapsedTime 不变，这样能正确显示从暂停位置继续的时间

        _midTimer = Timer(remainingNoticeTime, () {
          if (!_isMidCarouselPaused) {
            // 检查当前是否在欠费总览页面
            final isCurrentlyOnArrearTable =
                _currentNoticeIndex == (_midCarouselController.widgetCount - 1);

            if (isCurrentlyOnArrearTable) {
              // 如果当前在欠费总览页面，不直接切换，让自动翻页完成
              // 重要修復：不要重置開始時間，保持暫停恢復的邏輯
              // _currentNoticeStartTime = DateTime.now();
            } else {
              // 不是欠费总览，正常切换到下一个内容
              _currentNoticeIndex++;
              if (_currentNoticeIndex >= _midCarouselController.widgetCount) {
                _currentNoticeIndex = 1; // 回到第一个内容，跳过主屏幕
              }
              _midCarouselController.jumpToIndex(_currentNoticeIndex);
              _scheduleNextCarousel(apiNoticeStayDuration);
            }
          }
        });
      } else {
        // 剩余时间不足的特殊处理
        debugPrint('[AnnouncementCarousel] ⚡ [恢复] 剩余时间不足，立即切换到下一个内容');

        // 检查当前是否在欠费总览页面（最后一个索引）
        final isCurrentlyOnArrearTable =
            _currentNoticeIndex == (_midCarouselController.widgetCount - 1);

        if (isCurrentlyOnArrearTable) {
          // 如果当前在欠费总览页面，不直接切换，继续展示欠费总览

          // 重置开始时间，给欠费总览足够时间完成翻页
          _currentNoticeStartTime = DateTime.now();

          // 不调用 _scheduleNextCarousel，让欠费总览的翻页完成回调来处理切换
        } else {
          // 不是欠费总览，正常处理：直接启动下一个内容并开始无限轮播

          // 如果当前不在内容上，跳转到第一个内容
          if (_currentNoticeIndex < 1) {
            _currentNoticeIndex = 1;
            _midCarouselController.jumpToIndex(_currentNoticeIndex);
          } else {
            // 切换到下一个内容
            _currentNoticeIndex++;
            if (_currentNoticeIndex >= _midCarouselController.widgetCount) {
              _currentNoticeIndex = 1; // 回到第一个内容，跳过主屏幕
            }
            _midCarouselController.jumpToIndex(_currentNoticeIndex);
          }

          _scheduleNextCarousel(apiNoticeStayDuration);
        }
      }
    }

    notifyListeners();
  }

  /// 新增：根據視頻播放進度計算剩餘時間
  Duration _calculateRemainingTimeFromVideoProgress(int apiNoticeStayDuration) {
    try {
      // 獲取當前視頻的播放進度
      final currentProgress = getVideoProgress(_currentNoticeIndex);
      if (currentProgress != null && currentProgress.inSeconds > 0) {
        // 根據播放進度計算剩餘時間
        // 這裡假設視頻總時長等於API配置的停留時間
        final totalDuration = Duration(seconds: apiNoticeStayDuration);
        final remaining = totalDuration - currentProgress;

        // 確保剩餘時間不為負數
        if (remaining.inSeconds > 0) {
          debugPrint(
              '[AnnouncementCarousel] 根據視頻進度計算剩餘時間: ${remaining.inSeconds}s (總時長: ${totalDuration.inSeconds}s, 已播放: ${currentProgress.inSeconds}s)');
          return remaining;
        } else {
          debugPrint('[AnnouncementCarousel] 視頻已播放完成，剩餘時間為0');
          return Duration.zero;
        }
      }
    } catch (e) {
      debugPrint('[AnnouncementCarousel] 計算視頻剩餘時間失敗: $e');
    }

    // 如果無法獲取視頻進度，使用已播放時間計算
    final remainingNoticeTime = _noticeDuration - _noticeElapsedTime;
    debugPrint(
        '[AnnouncementCarousel] 使用已播放時間計算，剩餘時間: ${remainingNoticeTime.inSeconds}s (總時長: ${_noticeDuration.inSeconds}s, 已播放: ${_noticeElapsedTime.inSeconds}s)');
    return remainingNoticeTime;
  }

  /// 新增：智能计算恢复后的剩余时间
  Duration _calculateSmartRemainingTime(int apiNoticeStayDuration) {
    try {
      // 优先使用视频播放进度
      final videoRemaining =
          _calculateRemainingTimeFromVideoProgress(apiNoticeStayDuration);
      if (videoRemaining.inSeconds > 0) {
        return videoRemaining;
      }

      // 如果视频进度不可用，使用时间记录
      if (_currentNoticeStartTime != null && _currentNoticePauseTime != null) {
        final totalElapsed =
            _currentNoticePauseTime!.difference(_currentNoticeStartTime!);
        final remaining =
            Duration(seconds: apiNoticeStayDuration) - totalElapsed;

        if (remaining.inSeconds > 0) {
          debugPrint(
              '[AnnouncementCarousel] 使用时间记录计算剩余时间: ${remaining.inSeconds}s');
          return remaining;
        }
      }

      // 最后使用已播放时间记录
      final remainingFromElapsed = _noticeDuration - _noticeElapsedTime;
      if (remainingFromElapsed.inSeconds > 0) {
        debugPrint(
            '[AnnouncementCarousel] 使用已播放时间记录计算剩余时间: ${remainingFromElapsed.inSeconds}s');
        return remainingFromElapsed;
      }

      // 如果所有方法都失败，返回默认值
      debugPrint('[AnnouncementCarousel] 无法计算剩余时间，使用默认值: 0s');
      return Duration.zero;
    } catch (e) {
      debugPrint('[AnnouncementCarousel] 智能计算剩余时间失败: $e');
      return Duration.zero;
    }
  }

  /// 新增：保存暂停状态
  void _savePauseState() {
    try {
      // 记录当前播放时间
      _currentNoticePauseTime = DateTime.now();

      // 计算已播放时间
      if (_currentNoticeStartTime != null) {
        final rawElapsed =
            _currentNoticePauseTime!.difference(_currentNoticeStartTime!);
        // 加上之前的已播放时间（如果有的话）
        final totalElapsed = rawElapsed + _noticeElapsedTime;

        // 确保已播放时间不超过通告总时长
        if (totalElapsed >= _noticeDuration) {
          // 通告已经播放完成，应该准备切换到下一个
          _noticeElapsedTime = _noticeDuration;
          debugPrint(
              '[AnnouncementCarousel] 📊 [暂停] 通告 - 已播放: ${_noticeElapsedTime.inSeconds}s/${_noticeDuration.inSeconds}s (通告已完成)');
        } else {
          // 通告还在播放中
          _noticeElapsedTime = totalElapsed;
          final remainingNotice = _noticeDuration - _noticeElapsedTime;
          debugPrint(
              '[AnnouncementCarousel] 📊 [暂停] 通告 - 已播放: ${_noticeElapsedTime.inSeconds}s/${_noticeDuration.inSeconds}s, 剩余: ${remainingNotice.inSeconds}s');
        }
      }

      // 记录当前视频的播放进度
      _recordCurrentVideoProgress();

      debugPrint(
          '[AnnouncementCarousel] 暂停状态已保存 - 索引: $_currentNoticeIndex, 已播放: ${_noticeElapsedTime.inSeconds}s');
    } catch (e) {
      debugPrint('[AnnouncementCarousel] 保存暂停状态失败: $e');
    }
  }

  /// 新增：恢复暂停状态
  void _restorePauseState() {
    try {
      // 清除暂停时间记录，准备重新开始计时
      _currentNoticePauseTime = null;

      // 保持已播放时间不变，这样能正确计算剩余时间
      debugPrint(
          '[AnnouncementCarousel] 暂停状态已恢复 - 索引: $_currentNoticeIndex, 已播放: ${_noticeElapsedTime.inSeconds}s');
    } catch (e) {
      debugPrint('[AnnouncementCarousel] 恢复暂停状态失败: $e');
    }
  }

  /// 新增：記錄當前視頻的播放進度
  void _recordCurrentVideoProgress() {
    try {
      // 記錄當前索引的播放進度
      if (_currentNoticeIndex >= 0) {
        // 使用已播放時間作為備用方案
        final currentProgress = _noticeElapsedTime;
        _videoPlaybackPositions[_currentNoticeIndex] = currentProgress;

        debugPrint(
            '[AnnouncementCarousel] 記錄視頻播放進度 - 索引: $_currentNoticeIndex, 進度: ${currentProgress.inSeconds}s');
      }
    } catch (e) {
      debugPrint('[AnnouncementCarousel] 記錄視頻播放進度失敗: $e');
    }
  }

  /// 新增：獲取當前通告組件（輔助方法）
  Widget? _getCurrentAnnouncementWidget() {
    try {
      if (_currentNoticeIndex >= 0 &&
          _currentNoticeIndex < _midCarouselController.widgetCount) {
        // 這裡需要通過輪播控制器獲取當前Widget
        // 由於技術限制，暫時返回null
        return null;
      }
    } catch (e) {
      debugPrint('[AnnouncementCarousel] 獲取當前通告組件失敗: $e');
    }
    return null;
  }

  /// 新增：記錄視頻播放進度
  void recordVideoProgress(int index, Duration position) {
    _videoPlaybackPositions[index] = position;
    debugPrint(
        '[AnnouncementCarousel] 記錄視頻播放進度 - 索引: $index, 位置: ${position.inMilliseconds}ms');
  }

  /// 新增：獲取視頻播放進度
  Duration? getVideoProgress(int index) {
    return _videoPlaybackPositions[index];
  }

  ///5，更新轮播暂停状态
  void updateCarouselPauseState(bool isPaused) {
    _isMidCarouselPaused = isPaused;
    // _logger.i('🎛️ 通告轮播状态更新: ${!_isMidCarouselPaused ? "运行" : "暂停"}'); // _logger is not defined
    notifyListeners();
  }

  ///6，检查并恢复轮播状态（监控定时器使用）
  void checkAndRestoreMidCarousel(int apiNoticeStayDuration) {
    //  _logger.i(
    // '🔍 检查通告轮播恢复条件: announcements=${_carouselAnnouncements.length}, paused=$_isMidCarouselPaused'); // _logger is not defined

    // 修复：确保即使没有通告也能轮播（至少要有主屏幕和缴费表单）
    if ((_midCarouselController.widgetCount - 1) > 0 && !_isMidCarouselPaused) {
      // 检查当前定时器是否活跃
      if (_midTimer == null || !_midTimer!.isActive) {
        // _logger.w('🔧 检测到通告轮播定时器已停止，尝试重新启动...'); // _logger is not defined

        // 确保当前索引在内容范围内
        if (_currentNoticeIndex < 1) {
          _currentNoticeIndex = 1;
          _midCarouselController.jumpToIndex(_currentNoticeIndex);
        }

        // _logger.i('🔄 恢复通告轮播，当前索引: $_currentNoticeIndex'); // _logger is not defined
        _scheduleNextCarousel(apiNoticeStayDuration);
      }
    } else {
      // 不满足通告轮播恢复条件
      debugPrint(
          '[AnnouncementCarousel] 轮播恢复条件不满足: widgetCount=${_midCarouselController.widgetCount}, paused=$_isMidCarouselPaused');
    }
  }

  ///7，启动调试定时器 - 每秒输出通告轮播的实时状态
  void startDebugTimer(int apiNoticeStayDuration, {bool enableLogging = true}) {
    _debugTimer?.cancel();
    // 完全禁用调试定时器以减少系统资源占用和日志输出
    return;
  }

  ///8，停止调试定时器
  void stopDebugTimer() {
    _debugTimer?.cancel();
  }

  ///9，暂停所有计时器（用于设置页面）
  void pauseAllTimersForSettings() {
    debugPrint('[AnnouncementCarousel] ⚙️ 通告轮播 - 暂停所有计时器（设置页面）');
    _pauseAllTimers();
    _midCarouselController.pauseAllMedia();
    _isMidCarouselPaused = true;
    notifyListeners();
  }

  ///10，从设置页面恢复所有计时器
  void resumeAllTimersFromSettings(int apiNoticeStayDuration) {
    debugPrint('[AnnouncementCarousel] ↩️ 通告轮播 - 从设置页面恢复所有计时器');
    _isMidCarouselPaused = false;
    _midCarouselController.resumeAllMedia();

    // 恢复通告轮播
    if (_midCarouselController.widgetCount > 1) {
      _currentNoticeStartTime = DateTime.now();

      // 确保当前索引在内容范围内
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
      // _logger.i('�� 跳转到通告索引: $index'); // _logger is not defined
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
    // 修复：确保主屏幕Widget的返回按钮回调能正确工作
    Widget mainScreenWidget = _createMainScreenWidget(onHomeButtonPressed ??
        () {
          // 如果外部没有提供回调，使用默认的返回主屏幕行为
          jumpToAnnouncementIndex(0);
        });

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
          // 显示独立通告 - 修复：使用_homeButtonCallback确保返回按钮能正确工作
          showIndependentAnnouncement(announcement, _homeButtonCallback);
        }
      },
      onArrearTableTap: () {
        // 显示欠费总览界面 - 修复：使用_homeButtonCallback确保返回按钮能正确工作
        showArrearTableWidget(_homeButtonCallback);
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
          // 欠費總覽翻頁完成
          _isArrearPaginationActive = false;
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
    // 标记欠费总览正在活跃，暂停应用任何待定更新
    _isArrearPaginationActive = true;

    // 计算需要延长的时间：从设置中获取每页翻页时间，默认为5秒
    final deviceSettings = _appDataProvider.deviceSettings;
    final durationPerPage = deviceSettings?.paymentTableOnePageDuration;
    final paginationDuration =
        (durationPerPage != null && durationPerPage > 0) ? durationPerPage : 5;

    final int extensionSeconds = totalPages * paginationDuration.toInt();

    // 取消现有的定时器，避免冲突
    _midTimer?.cancel();

    // 重新设置开始时间，相当于重新开始计时
    _currentNoticeStartTime = DateTime.now();

    // 使用延长后的时间重新调度轮播
    final extendedDuration = _noticeDuration.inSeconds + extensionSeconds;

    debugPrint(
        '[AnnouncementCarousel] 缴费表单翻页开始，延长停留时间: ${extensionSeconds}秒，总时长: ${extendedDuration}秒');

    // 使用延长后的时间调度下一次轮播
    _scheduleNextCarousel(extendedDuration);
  }

  ///18，切换到下一个轮播项（欠费总览翻页完成后调用）
  void _goToNextCarouselItem() {
    if (_isMidCarouselPaused) {
      return;
    }

    // 如果欠费总览仍在活跃，则不进行轮播切换，等待其完成
    if (_isArrearPaginationActive) {
      return;
    }

    try {
      // 切换到下一个内容
      _currentNoticeIndex++;
      if (_currentNoticeIndex >= _midCarouselController.widgetCount) {
        _currentNoticeIndex = 1; // 回到第一个内容，跳过主屏幕
      }

      // 跳转到下一个内容
      _midCarouselController.jumpToIndex(_currentNoticeIndex);

      // 记录新内容开始时间
      _currentNoticeStartTime = DateTime.now();

      debugPrint('[AnnouncementCarousel] 缴费表单翻页完成，切换到索引: $_currentNoticeIndex');

      // 重新启动轮播定时器，使用当前API配置的停留时间
      _scheduleNextCarousel(_noticeDuration.inSeconds);
    } catch (e) {
      debugPrint('[AnnouncementCarousel] 切换到下一个轮播项失败: $e');
      // 切换失败时，延迟重试
      Future.delayed(const Duration(seconds: 2), () {
        if (!_isMidCarouselPaused) {
          _goToNextCarouselItem();
        }
      });
    }
  }

  ///19，新增：强制恢复轮播组件
  void forceRecovery() {
    debugPrint('[AnnouncementCarousel] 强制恢复轮播组件...');

    try {
      // 清理所有定时器
      _pauseAllTimers();

      // 重置状态
      _isMidCarouselPaused = false;
      _currentNoticeIndex = 0;
      _currentNoticeStartTime = null;
      _noticeElapsedTime = Duration.zero;
      _currentNoticePauseTime = null;

      // 清空視頻播放進度記錄
      _videoPlaybackPositions.clear();

      // 重新创建基本内容
      _ensureBasicContent();

      // 重新初始化视频播放进度缓存
      _initializeVideoProgressCache();

      // 使用 WidgetsBinding.instance.addPostFrameCallback 延迟通知
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (hasListeners) {
          notifyListeners();
        }
      });

      debugPrint('[AnnouncementCarousel] 强制恢复完成');
    } catch (e) {
      debugPrint('[AnnouncementCarousel] 强制恢复失败: $e');
    }
  }

  ///20，新增：确保基本内容的方法
  void _ensureBasicContent() {
    try {
      debugPrint('[AnnouncementCarousel] 尝试恢复基本轮播内容...');

      // 强制创建主屏幕Widget
      const mainScreenKey = 'main_screen';

      _widgetCache[mainScreenKey] =
          _createMainScreenWidget(_homeButtonCallback);

      // 创建基本的轮播内容
      final Map<String, Widget> basicWidgetMap = {
        mainScreenKey: _widgetCache[mainScreenKey]!,
      };

      final List<String> basicOrderedKeys = [mainScreenKey];

      // 修复：強制創建缴費表單widget，確保至少有2個widget
      final arrearDataVersion =
          _arrearProvider?.currentDataVersion ?? 'default';
      final arrearTableKey = 'arrear_table_$arrearDataVersion';

      try {
        if (_arrearProvider != null) {
          _widgetCache[arrearTableKey] =
              _arrearProvider!.createArrearTableWidget(
            onHomeButtonPressed: () {
              jumpToAnnouncementIndex(0);
            },
            isInCarouselMode: true,
            onPaginationComplete: (int totalPages) {
              _isArrearPaginationActive = false;
              _goToNextCarouselItem();
            },
            onPaginationStart: (int totalPages) {
              _isArrearPaginationActive = true;
              _extendCurrentNoticeStayTime(totalPages);
            },
          );
        } else {
          _widgetCache[arrearTableKey] = Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.grey.shade50,
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.payment, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('繳費表單',
                      style:
                          TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text('暫無通告數據，顯示繳費表單',
                      style: TextStyle(fontSize: 16, color: Colors.grey)),
                ],
              ),
            ),
          );
        }

        basicWidgetMap[arrearTableKey] = _widgetCache[arrearTableKey]!;
        basicOrderedKeys.add(arrearTableKey);
        debugPrint('[AnnouncementCarousel] 基本內容創建：缴费表单widget創建成功');
      } catch (e) {
        debugPrint('[AnnouncementCarousel] 基本內容創建：缴费表单widget創建失败: $e');
        // 創建一個簡單的備用widget
        _widgetCache[arrearTableKey] = Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.grey.shade50,
          child: const Center(
            child: Text('缴費數據暫不可用', style: TextStyle(fontSize: 18)),
          ),
        );
        basicWidgetMap[arrearTableKey] = _widgetCache[arrearTableKey]!;
        basicOrderedKeys.add(arrearTableKey);
      }

      // 强制更新轮播组件
      _midCarouselController.smartUpdateCarousel(
          basicWidgetMap, basicOrderedKeys);

      // 确保跳转到主屏幕
      if (_midCarouselController.widgetCount > 0) {
        _currentNoticeIndex = 0;
        _midCarouselController.jumpToIndex(0);
        debugPrint(
            '[AnnouncementCarousel] 基本內容恢復完成：${_midCarouselController.widgetCount} widgets');
      }

      // 使用 WidgetsBinding.instance.addPostFrameCallback 延迟通知
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (hasListeners) {
          notifyListeners();
        }
      });
    } catch (e) {
      debugPrint('[AnnouncementCarousel] 严重错误：无法创建基本内容: $e');
    }
  }

  ///21，新增：诊断轮播组件问题
  void diagnoseCarouselIssues() {
    debugPrint('[AnnouncementCarousel] === 轮播组件诊断开始 ===');
    debugPrint('[AnnouncementCarousel] 状态: $carouselStatus');
    debugPrint('[AnnouncementCarousel] 是否就绪: $isCarouselReady');
    debugPrint('[AnnouncementCarousel] 是否健康: $isCarouselHealthy');
    debugPrint('[AnnouncementCarousel] 缓存Widget数量: ${_widgetCache.length}');
    debugPrint(
        '[AnnouncementCarousel] 缓存FileManager数量: ${_fileManagerCache.length}');
    debugPrint('[AnnouncementCarousel] 通告数量: ${_carouselAnnouncements.length}');
    debugPrint(
        '[AnnouncementCarousel] 轮播组件Widget总数: ${_midCarouselController.widgetCount}');
    debugPrint('[AnnouncementCarousel] 轮播模式: $carouselModeInfo');
    debugPrint('[AnnouncementCarousel] 支持无通告模式: $supportsNoAnnouncementMode');

    // 新增：视频播放进度诊断
    debugPrint('[AnnouncementCarousel] === 视频播放进度诊断 ===');
    debugPrint('[AnnouncementCarousel] 当前索引: $_currentNoticeIndex');
    debugPrint(
        '[AnnouncementCarousel] 已播放时间: ${_noticeElapsedTime.inSeconds}s');
    debugPrint('[AnnouncementCarousel] 总时长: ${_noticeDuration.inSeconds}s');
    debugPrint('[AnnouncementCarousel] 当前开始时间: $_currentNoticeStartTime');
    debugPrint('[AnnouncementCarousel] 暂停时间: $_currentNoticePauseTime');
    debugPrint('[AnnouncementCarousel] 视频播放进度缓存: $_videoPlaybackPositions');

    // 显示每个索引的播放进度
    _videoPlaybackPositions.forEach((index, progress) {
      debugPrint('[AnnouncementCarousel] 索引 $index: ${progress.inSeconds}s');
    });

    debugPrint('[AnnouncementCarousel] === 轮播组件诊断结束 ===');
  }

  ///22，新增：检查轮播组件是否支持无通告模式
  bool get supportsNoAnnouncementMode {
    // 修复：确保至少要有主屏幕和缴费表单才能支持无通告模式
    return _midCarouselController.widgetCount >= 2;
  }

  ///23，新增：获取轮播模式信息
  String get carouselModeInfo {
    if (_carouselAnnouncements.isNotEmpty) {
      return '通告轮播模式 - ${_carouselAnnouncements.length} 个通告';
    } else if (_midCarouselController.widgetCount >= 2) {
      return '缴费表单轮播模式 - 无通告数据，显示缴费表单';
    } else {
      return '基本模式 - 仅显示主屏幕';
    }
  }

  /// 新增：初始化视频播放进度缓存
  void _initializeVideoProgressCache() {
    // 确保缓存中包含所有当前轮播项的索引
    for (int i = 0; i < _midCarouselController.widgetCount; i++) {
      // 如果缓存中没有，则添加一个默认值
      if (!_videoPlaybackPositions.containsKey(i)) {
        _videoPlaybackPositions[i] = Duration.zero;
      }
    }
    debugPrint('[AnnouncementCarousel] 视频播放进度缓存已初始化');
  }

  @override
  void dispose() {
    _midTimer?.cancel();
    _midTimer = null;

    _debugTimer?.cancel();
    _debugTimer = null;

    _delayedNoticeTimer?.cancel();
    _delayedNoticeTimer = null;

    super.dispose(); // 调用父类的dispose方法

    // 清理所有緩存
    _widgetCache.clear();
    _fileManagerCache.clear();
  }
}
