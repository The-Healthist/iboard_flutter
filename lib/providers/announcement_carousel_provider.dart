import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:iboard_app/managers/file_manager.dart';
import 'package:iboard_app/models/announcement_model.dart';
import 'package:iboard_app/widgets/carousel/carousel_widget.dart'
    as custom_carousel;
import 'package:iboard_app/widgets/mainscreen/main_display/announcement_reader_widget.dart';
import 'package:iboard_app/widgets/mainscreen/main_display/mainscreen_widget.dart';
import 'package:iboard_app/providers/app_data_provider.dart';
import 'package:iboard_app/providers/arrear_provider.dart'; // 新增

/// 费用表單类型枚举
enum ArrearTableType { other, management }

class AnnouncementCarouselProvider extends ChangeNotifier {
  // 轮播控制器
  late custom_carousel.CarouselController _midCarouselController;

  // 定时器管理
  Timer? _midTimer;
  Timer? _debugTimer;
  Timer? _delayedNoticeTimer;

  // 通告数据 - 使用AnnouncementProvider的轮播数据
  List<AnnouncementModel> _carouselAnnouncements = [];

  // 状态管理
  bool _isMidCarouselPaused = false;
  bool _isShowingArrearTable = false;

  // 时间记录相关 - 用于全屏广告暂停恢复
  DateTime? _currentNoticeStartTime; // 当前通告开始时间
  DateTime? _currentNoticePauseTime; // 当前通告暂停时间
  Duration _noticeElapsedTime = Duration.zero; // 通告已播放时间
  Duration _noticeDuration = const Duration(seconds: 5); // 通告总时长
  int _currentNoticeIndex = 0; // 当前通告索引

  int? _savedCarouselIndex; // 保存進入手動模式前的輪播索引
  int? _lastValidCarouselIndex; // 最后有效的轮播索引（不包括主屏幕索引0）
  final ValueNotifier<int> _visibleCarouselIndexNotifier =
      ValueNotifier<int>(0);

  // AppDataProvider引用 - 用于获取动态设置
  late AppDataProvider _appDataProvider;
  late VoidCallback _homeButtonCallback = () {
    // 默认的安全回调，避免应用崩溃
    try {
      if (_midCarouselController.widgetCount > 0) {
        jumpToAnnouncementIndex(0);
      }
    } catch (e) {
      // debugPrint('[AnnouncementCarousel]  默认安全回调失败: $e');
    }
  };

  late ArrearProvider? _arrearProvider;

  // 新增：跟踪当前费用表單和PDF的轮播状态
  bool _isOtherTablePaginationActive = false; // 其他费用表單是否在翻頁中
  bool _isManagementTablePaginationActive = false; // 管理费用表單是否在翻頁中
  bool _isPdfPaginationActive = false; // PDF多頁是否在翻頁中

  // 緩存Widget實例和FileManager - 优化内存管理
  final Map<String, Widget> _widgetCache = {};
  final Map<String, FileManager> _fileManagerCache = {};
  final Map<String, String> _announcementSignatures = {};

  // 防重复初始化标志位
  bool _isInitializing = false;

  // Getters
  custom_carousel.CarouselController get midCarouselController =>
      _midCarouselController;
  List<AnnouncementModel> get carouselAnnouncements => _carouselAnnouncements;
  bool get isMidCarouselPaused => _isMidCarouselPaused;

  bool get isShowingArrearTable => _isShowingArrearTable;
  Duration get noticeDuration => _noticeDuration;
  int get currentNoticeIndex => _currentNoticeIndex;
  ValueListenable<int> get visibleCarouselIndexListenable =>
      _visibleCarouselIndexNotifier;
  DateTime? get currentNoticeStartTime => _currentNoticeStartTime;
  Duration get noticeElapsedTime => _noticeElapsedTime;
  bool get isInitializing => _isInitializing;

  /// 获取轮播组件状态信息
  String get carouselStatus {
    try {
      return 'Widget数量: ${_midCarouselController.widgetCount}, '
          '当前索引: $_currentNoticeIndex, '
          '通告数量: ${_carouselAnnouncements.length}, '
          '回调设置: true, '
          '轮播暂停: $_isMidCarouselPaused, '
          '正在初始化: $_isInitializing, '
          '支持无通告模式: $supportsNoAnnouncementMode';
    } catch (e) {
      return '状态获取失败: $e';
    }
  }

  /// 检查轮播组件健康状态
  bool get isCarouselHealthy {
    try {
      // 确保至少有3个Widget（主屏幕+占位符+内容）
      return _midCarouselController.widgetCount >= 3 &&
          _currentNoticeIndex >= 0 &&
          _currentNoticeIndex < _midCarouselController.widgetCount;
    } catch (e) {
      return false;
    }
  }

  /// 检查是否有可轮播的内容（包括只有管理费用表格的情况）
  bool get hasCarouselContent {
    final widgetCount = _midCarouselController.widgetCount;
    final hasAnnouncements = _carouselAnnouncements.isNotEmpty;
    final hasManagementData = _arrearProvider?.hasManagementFeeData == true;
    final hasOtherData = _arrearProvider?.hasAnyOtherFeeRecords == true;

    // 至少需要主屏幕 + 占位符 + 任意一种内容（通告或费用表格）
    return widgetCount >= 3 &&
        (hasAnnouncements || hasManagementData || hasOtherData);
  }

  /// 确认轮播模式
  bool get _onlyManagementTableMode =>
      _carouselAnnouncements.isEmpty &&
      (_arrearProvider?.hasManagementFeeData == true) &&
      !(_arrearProvider?.hasAnyOtherFeeRecords == true);

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

  ///设置返回主屏幕按钮回调（新增方法）
  void setHomeButtonCallback(VoidCallback homeButtonCallback) {
    _homeButtonCallback = homeButtonCallback;

    //  修复：回调设置后，清除缓存的Widget以强制重新创建，确保使用新的回调
    _clearWidgetCacheForHomeButton();
  }

  ///0，清除涉及返回按钮的Widget缓存（私有辅助方法）
  void _clearWidgetCacheForHomeButton() {
    // 清除主屏幕Widget缓存，强制重新创建以使用新回调
    _widgetCache.removeWhere((key, value) => key == 'main_screen');

    // 清除费用表格Widget缓存，强制重新创建以使用新回调
    _widgetCache.removeWhere((key, value) =>
        key.startsWith('management_fee_table_') ||
        key.startsWith('other_fee_table_'));
  }

  ///0a，清除通告Widget缓存，强制重新创建（修复PDF初始化问题）
  void _clearAnnouncementWidgetCache() {
    // debugPrint('[AnnouncementCarousel]  清除通告Widget缓存，强制重新创建');

    // 清除所有通告相关的Widget缓存
    _widgetCache.removeWhere((key, value) => key.startsWith('announcement_'));

    // 清除对应的FileManager缓存
    _fileManagerCache
        .removeWhere((key, value) => key.startsWith('announcement_'));
    _announcementSignatures
        .removeWhere((key, value) => key.startsWith('announcement_'));

    // debugPrint('[AnnouncementCarousel]  通告Widget缓存已清除');
  }

  ///1，更新轮播通告列表（由AnnouncementProvider调用）
  void updateCarouselList(List<AnnouncementModel> newCarouselAnnouncements) {
    // 如果正在初始化，延迟处理更新请求
    if (_isInitializing) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (!_isInitializing) {
          updateCarouselList(newCarouselAnnouncements);
        }
      });
      return;
    }

    // 使用智能增量更新
    _smartUpdateCarousel(newCarouselAnnouncements);
  }

  ///2，智能更新轮播内容（增量更新，不破坏当前状态）
  void _smartUpdateCarousel(List<AnnouncementModel> newCarouselAnnouncements) {
    // 2.1 判斷通告或欠費是否需要更新
    final bool annEqual = _isAnnouncementListEqual(
        _carouselAnnouncements, newCarouselAnnouncements);
    final bool arrearPending = _arrearProvider?.hasPendingUpdate == true;
    if (annEqual && !arrearPending) {
      return;
    }

    _updateCarouselContent(newCarouselAnnouncements);
  }

  ///2a，强制更新轮播内容（跳过相等性检查，强制重新创建）
  void _forceUpdateCarousel(List<AnnouncementModel> newCarouselAnnouncements) {
    // debugPrint('[AnnouncementCarousel]  强制更新轮播内容，跳过相等性检查');
    _updateCarouselContent(newCarouselAnnouncements);
  }

  ///2b，更新轮播内容的核心逻辑
  void _updateCarouselContent(
      List<AnnouncementModel> newCarouselAnnouncements) {
    // 2.2 覆蓋本地的通告列表
    _carouselAnnouncements =
        List<AnnouncementModel>.from(newCarouselAnnouncements);

    // 2.3 構建 widget 映射與順序
    final Map<String, Widget> widgetMap = {};
    final List<String> orderedKeys = [];
    final Set<String> usedKeys = {};

    // 2.4 主屏幕 widget（固定key)
    const mainScreenKey = 'main_screen';
    try {
      if (!_widgetCache.containsKey(mainScreenKey)) {
        _widgetCache[mainScreenKey] =
            _createMainScreenWidget(_homeButtonCallback);
      }
      widgetMap[mainScreenKey] = _widgetCache[mainScreenKey]!;
      orderedKeys.add(mainScreenKey);
      usedKeys.add(mainScreenKey);
    } catch (e) {
      // 2.4.1 創建備用主屏幕
      _widgetCache[mainScreenKey] = const Center(
        child: Text('主屏幕載入中...', style: TextStyle(fontSize: 18)),
      );
      widgetMap[mainScreenKey] = _widgetCache[mainScreenKey]!;
      orderedKeys.add(mainScreenKey);
      usedKeys.add(mainScreenKey);
    }

    // 2.5 为独立通告预留索引1的占位符（正常轮播时不可见，仅保持索引一致性）
    const independentAnnouncementKey = 'independent_announcement_placeholder';
    _widgetCache[independentAnnouncementKey] =
        const SizedBox.shrink(); //  修复：使用不可见Widget作为占位符
    widgetMap[independentAnnouncementKey] =
        _widgetCache[independentAnnouncementKey]!;
    orderedKeys.add(independentAnnouncementKey);
    usedKeys.add(independentAnnouncementKey);

    // 2.6 通告 widgets（从索引2开始，为独立通告预留索引1）
    for (int i = 0; i < _carouselAnnouncements.length; i++) {
      final announcement = _carouselAnnouncements[i];
      final key = 'announcement_${announcement.id}';

      if (!_widgetCache.containsKey(key) ||
          _hasAnnouncementChanged(key, announcement)) {
        try {
          _announcementSignatures[key] = _announcementSignature(announcement);
          if (!_fileManagerCache.containsKey(key)) {
            _fileManagerCache[key] = FileManager();
          }
          final fileManager = _fileManagerCache[key]!;

          _widgetCache[key] = Center(
            child: AnnouncementReaderWidget(
              key: ValueKey(key),
              announcement: announcement,
              fileManager: fileManager,
              isInCarouselMode: true, // 轮播模式
              carouselIndex: i + 2,
              visibleCarouselIndexListenable: _visibleCarouselIndexNotifier,
              onHomeButtonPressed: _homeButtonCallback,
              onPdfCompleted: () {
                // PDF多頁播放完成回調
                _onPdfPaginationComplete();
              },
              onPdfPaginationStart: (int totalPages) {
                // PDF多頁開始回調，延長停留時間
                _onPdfPaginationStart(totalPages);
              },
            ),
          );
        } catch (e) {
          continue;
        }
      }

      widgetMap[key] = _widgetCache[key]!;
      orderedKeys.add(key);
      usedKeys.add(key);
    }

    // 2.7 其他費用表 widget（根據數據版本）
    final arrearDataVersion = _arrearProvider?.currentDataVersion ?? 'default';
    final arrearTableKey = 'other_fee_table_$arrearDataVersion';

    try {
      final includeOther = _arrearProvider?.hasAnyOtherFeeRecords == true;
      if (includeOther &&
          (!_widgetCache.containsKey(arrearTableKey) ||
              _arrearProvider?.hasPendingUpdate == true)) {
        if (_arrearProvider != null) {
          _widgetCache[arrearTableKey] =
              _arrearProvider!.createArrearOtherTableWidget(
            onHomeButtonPressed: _homeButtonCallback, // 使用统一的回调
            isInCarouselMode: true,
            onPaginationComplete: (int totalPages) {
              _isOtherTablePaginationActive = false;
              _onOtherTablePaginationComplete();
            },
            onPaginationStart: (int totalPages) {
              _isOtherTablePaginationActive = true;
              _extendCurrentNoticeStayTime(totalPages);
            },
          );
          _widgetCache.removeWhere((key, value) =>
              key.startsWith('other_fee_table_') && key != arrearTableKey);

          _arrearProvider!.markUpdateApplied();
        }
      }

      if (includeOther && _widgetCache.containsKey(arrearTableKey)) {
        widgetMap[arrearTableKey] = _widgetCache[arrearTableKey]!;
        orderedKeys.add(arrearTableKey);
        usedKeys.add(arrearTableKey);
      }
    } catch (e) {
      _widgetCache[arrearTableKey] = const Center(
        child: Text('其他費用數據暫不可用', style: TextStyle(fontSize: 18)),
      );
      widgetMap[arrearTableKey] = _widgetCache[arrearTableKey]!;
      orderedKeys.add(arrearTableKey);
      usedKeys.add(arrearTableKey);
    }

    // 2.8 管理費用表 widget（根據數據版本）
    final mgmtDataVersion = _arrearProvider?.currentDataVersion ?? 'default';
    final mgmtTableKey = 'management_fee_table_$mgmtDataVersion';
    try {
      final includeMgmt = _arrearProvider?.hasManagementFeeData == true;
      if (includeMgmt &&
          (!_widgetCache.containsKey(mgmtTableKey) ||
              _arrearProvider?.hasPendingUpdate == true)) {
        if (_arrearProvider != null) {
          _widgetCache[mgmtTableKey] =
              _arrearProvider!.createArrearManagementTableWidget(
            onHomeButtonPressed: _homeButtonCallback, // 使用统一的回调
            isInCarouselMode: true,
            onPaginationComplete: (int totalPages) {
              _isManagementTablePaginationActive = false;
              _onManagementTablePaginationComplete();
            },
            onPaginationStart: (int totalPages) {
              _isManagementTablePaginationActive = true;
              _extendCurrentNoticeStayTime(totalPages);
            },
          );
          _widgetCache.removeWhere((key, value) =>
              key.startsWith('management_fee_table_') && key != mgmtTableKey);

          _arrearProvider!.markUpdateApplied();
        }
      }

      if (includeMgmt && _widgetCache.containsKey(mgmtTableKey)) {
        widgetMap[mgmtTableKey] = _widgetCache[mgmtTableKey]!;
        orderedKeys.add(mgmtTableKey);
        usedKeys.add(mgmtTableKey);
      }
    } catch (e) {
      _widgetCache[mgmtTableKey] = const Center(
        child: Text('繳費數據暫不可用', style: TextStyle(fontSize: 18)),
      );
      widgetMap[mgmtTableKey] = _widgetCache[mgmtTableKey]!;
      usedKeys.add(mgmtTableKey);
      orderedKeys.add(mgmtTableKey);
    }

    // 2.9 清理不再使用的緩存
    _cleanupUnusedCache(usedKeys);

    // 2.10 確保至少有基本的widgets
    if (widgetMap.isEmpty || orderedKeys.isEmpty) {
      const emergencyKey = 'emergency_main';
      widgetMap[emergencyKey] = const Center(
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
      );
      orderedKeys.add(emergencyKey);
    }

    // 2.11 確保在沒有通告時也掛載繳費表單
    if (_carouselAnnouncements.isEmpty && widgetMap.length < 3) {
      //  修复：至少需要3个Widget（主屏幕+占位符+费用表）
      // 强制创建缴费表單widget
      final arrearDataVersion =
          _arrearProvider?.currentDataVersion ?? 'default';
      final arrearTableKey = 'management_fee_table_$arrearDataVersion';

      if (!widgetMap.containsKey(arrearTableKey)) {
        try {
          if (_arrearProvider != null) {
            _widgetCache[arrearTableKey] =
                _arrearProvider!.createArrearManagementTableWidget(
              onHomeButtonPressed: _homeButtonCallback, // 使用统一的回调
              isInCarouselMode: true,
              onPaginationComplete: (int totalPages) {
                _isManagementTablePaginationActive = false;
                _onManagementTablePaginationComplete();
              },
              onPaginationStart: (int totalPages) {
                _isManagementTablePaginationActive = true;
                _extendCurrentNoticeStayTime(totalPages);
              },
            );
          } else {
            _widgetCache[arrearTableKey] = const Center(
              child: Text('欠費數據載入中...', style: TextStyle(fontSize: 18)),
            );
          }

          widgetMap[arrearTableKey] = _widgetCache[arrearTableKey]!;
          orderedKeys.add(arrearTableKey);
        } catch (e) {
          // debugPrint('[AnnouncementCarousel]  强制创建缴费表單widget失败: $e');
        }
      }
    }

    // 2.12 使用智能更新，保持当前查看的内容不变
    _midCarouselController.smartUpdateCarousel(widgetMap, orderedKeys);

    // 2.13 確保輪播有內容並校正當前索引
    if (_midCarouselController.widgetCount > 0) {
      //  修复：保持当前轮播位置，不强制跳转到初始索引
      // 只有在当前索引无效时才进行校正
      if (_currentNoticeIndex >= _midCarouselController.widgetCount ||
          _currentNoticeIndex < 0) {
        // 当前索引无效，需要校正
        int initialIndex = _determineInitialCarouselIndex();
        _currentNoticeIndex = initialIndex;

        // 跳转到校正后的索引
        _jumpToVisibleIndex(_currentNoticeIndex);
      } else {
        // 当前索引有效，保持不变
        // 不进行跳转，保持当前位置
      }
    } else {}

    notifyListeners();
  }

  void _jumpToVisibleIndex(int index) {
    _midCarouselController.jumpToIndex(index);
    updateVisibleCarouselIndex(index);
  }

  void updateVisibleCarouselIndex(int index) {
    if (_visibleCarouselIndexNotifier.value == index) {
      return;
    }
    _visibleCarouselIndexNotifier.value = index;
  }

  ///3，确定初始轮播索引
  int _determineInitialCarouselIndex() {
    final bool hasAnnouncements = _carouselAnnouncements.isNotEmpty;
    final bool hasOtherData = _arrearProvider?.hasAnyOtherFeeRecords == true;
    final bool hasManagementData =
        _arrearProvider?.hasManagementFeeData == true;

    if (hasAnnouncements) {
      return 2; //  修复：正常通告从索引2开始，索引1预留给独立通告
    } else if (hasOtherData && hasManagementData) {
      // 无通告但有两种费用表單，从其他费用表單开始
      final otherIndex = _getFirstArrearTableIndex();
      return otherIndex != -1 ? otherIndex : 2;
    } else if (hasManagementData) {
      // 只有管理费用表單，从管理费用表單开始
      final mgmtIndex = _findManagementTableIndex();
      return mgmtIndex != -1 ? mgmtIndex : 2;
    } else {
      // 没有任何内容，从主屏幕开始
      return 0;
    }
  }

  ///4，检查通告列表是否相同
  bool _isAnnouncementListEqual(
      List<AnnouncementModel> list1, List<AnnouncementModel> list2) {
    if (list1.length != list2.length) return false;
    for (int i = 0; i < list1.length; i++) {
      if (_announcementSignature(list1[i]) !=
          _announcementSignature(list2[i])) {
        return false;
      }
    }
    return true;
  }

  ///5，檢查通告內容是否變化
  bool _hasAnnouncementChanged(String key, AnnouncementModel newAnnouncement) {
    return _announcementSignatures[key] !=
        _announcementSignature(newAnnouncement);
  }

  ///6，清理不再使用的緩存
  void _cleanupUnusedCache(Set<String> usedKeys) {
    // 清理Widget緩存（保留独立通告占位符）
    _widgetCache.removeWhere((key, value) =>
        !usedKeys.contains(key) &&
        key != 'independent_announcement_placeholder');

    // 清理FileManager緩存
    _fileManagerCache.removeWhere((key, value) => !usedKeys.contains(key));
    _announcementSignatures
        .removeWhere((key, value) => !usedKeys.contains(key));
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
    // 防止重复初始化
    if (_isInitializing) {
      return;
    }

    _isInitializing = true;

    try {
      // 保存主頁回调
      _homeButtonCallback = onHomeButtonPressed;
      _noticeDuration = Duration(seconds: apiNoticeStayDuration);
      // 重置暫停相關的狀態，確保初始化時狀態乾淨
      _currentNoticePauseTime = null;
      _noticeElapsedTime = Duration.zero;

      _midTimer?.cancel();
      _delayedNoticeTimer?.cancel();
      _ensureBasicContent();

      if (!_isMidCarouselPaused) {
        final bool hasAnnouncements = carouselAnnouncements.isNotEmpty;
        // 无延时
        if (hasAnnouncements) {
          if (!_isMidCarouselPaused) {
            _startCarouselFromAnnouncements(apiNoticeStayDuration);
          }
        } else {
          _startCarouselFromFeeTables();
        }
      }
    } catch (e) {
      _ensureBasicContent();
    } finally {
      // 确保在任何情况下都能重置初始化标志位
      _isInitializing = false;
    }
  }

  ///3.1，从通告开始轮播
  void _startCarouselFromAnnouncements(int apiNoticeStayDuration) {
    try {
      _currentNoticeStartTime = DateTime.now();
      _currentNoticeIndex = 2; //  修复：从第一个正常通告开始（索引2）

      // 确保索引在有效范围内
      if (_currentNoticeIndex >= _midCarouselController.widgetCount) {
        _currentNoticeIndex = _midCarouselController.widgetCount > 2 ? 2 : 0;
      }

      _recordValidCarouselIndex(_currentNoticeIndex); // 记录有效索引

      _jumpToVisibleIndex(_currentNoticeIndex);
      _scheduleNextCarousel(apiNoticeStayDuration);
    } catch (e) {
      // debugPrint('[AnnouncementCarousel]  从通告开始轮播失败: $e');
    }
  }

  ///3.2，从费用表格开始轮播（无延时）
  void _startCarouselFromFeeTables() {
    try {
      _currentNoticeStartTime = DateTime.now();
      _currentNoticeIndex = _determineInitialCarouselIndex();

      // 确保索引在有效范围内
      if (_currentNoticeIndex >= _midCarouselController.widgetCount) {
        _currentNoticeIndex = _midCarouselController.widgetCount > 1 ? 1 : 0;
      }

      _recordValidCarouselIndex(_currentNoticeIndex); // 记录有效索引

      _jumpToVisibleIndex(_currentNoticeIndex);
    } catch (e) {
      // debugPrint('[AnnouncementCarousel]  从费用表格开始轮播失败: $e');
    }
  }

  ///2a，调度下一个轮播切换（智能定时器，自适应间隔减少系统调用）
  void _scheduleNextCarousel(int apiNoticeStayDuration) {
    try {
      _midTimer?.cancel();

      if (_isMidCarouselPaused) {
        return;
      }

      // 验证轮播组件状态 不需要验证
      if (!isCarouselHealthy) {
        _ensureBasicContent();
        return;
      }

      // 修复：确保即使没有通告也能轮播（至少要有主屏幕+占位符+缴费表單）
      final currentWidgetCount = _midCarouselController.widgetCount;
      if (currentWidgetCount < 3) {
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
    } catch (e) {
      // 调度失败时，延迟重试
      Future.delayed(const Duration(seconds: 2), () {
        if (!_isMidCarouselPaused) {
          _scheduleNextCarousel(apiNoticeStayDuration);
        }
      });
    }
  }

  ///3，检查并推进轮播（减少定时器创建）
  void _checkAndAdvanceCarousel(int apiNoticeStayDuration) {
    // 3.1 暫停狀態處理
    try {
      if (_isMidCarouselPaused) {
        // 34, 暂停状态下，确保停留在当前索引，不要切换
        debugPrint('[AnnouncementCarousel]  轮播已暂停，停留在索引=$_currentNoticeIndex');
        _scheduleNextCarousel(apiNoticeStayDuration);
        return;
      }

      // 3.2 僅管理費用模式時不切換，由表內循環
      if (_onlyManagementTableMode) {
        _scheduleNextCarousel(apiNoticeStayDuration);
        return;
      }

      // 3.3 驗證輪播健壯性
      if (!isCarouselHealthy) {
        _ensureBasicContent();
        return;
      }

      // 3.3.1 內容範圍（不包含主屏和独立通告占位符）
      const int contentStart = 2; //  修复：从第一个正常通告开始（跳过索引0主屏幕和索引1占位符）
      final int contentEnd = _midCarouselController.widgetCount - 1;
      final int contentCount = contentEnd - contentStart + 1;

      // 3.4 檢查是否到達切換時間
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

      // 3.5 到達切換時間，執行切換
      try {
        // 無影片：不需要記錄播放進度

        //  修复关键问题：检查是否有费用表格或PDF正在翻页
        if (_isOtherTablePaginationActive ||
            _isManagementTablePaginationActive ||
            _isPdfPaginationActive) {
          // 重新调度，等待费用表格或PDF翻页完成
          _scheduleNextCarousel(apiNoticeStayDuration);
          return;
        }

        //  修复关键问题：当前在费用表格时，不应该由时间触发切换
        // 费用表格有自己的翻页机制，翻页完成后会通过回调触发切换
        if (_isCurrentIndexInArrearTables()) {
          // 重新调度，等待费用表格翻页完成
          _scheduleNextCarousel(apiNoticeStayDuration);
          return;
        }

        // 3.5.1 僅在內容索引範圍 [1..N] 之間循環（永不回到0）
        if (contentCount <= 1) {
          // 只有一個內容：交由表內自行處理
          _scheduleNextCarousel(apiNoticeStayDuration);
          return;
        }

        //  修复：使用智能索引确定逻辑，正确处理通告到费用表格的切换
        final nextIndex = _determineNextCarouselIndex();
        if (nextIndex != -1 && nextIndex != _currentNoticeIndex) {
          _currentNoticeIndex = nextIndex;
          _recordValidCarouselIndex(_currentNoticeIndex); // 记录有效索引
        } else {
          // 后备方案：简单递增
          _currentNoticeIndex++;
          if (_currentNoticeIndex < contentStart ||
              _currentNoticeIndex > contentEnd) {
            _currentNoticeIndex = contentStart;
          }
          _recordValidCarouselIndex(_currentNoticeIndex); // 记录有效索引
        }

        // 3.6 判斷是否切到欠費總覽頁（最後一頁）
        final isArrearTable = _isCurrentIndexInArrearTables();

        // 3.7 跳轉到目標索引
        _jumpToVisibleIndex(_currentNoticeIndex);

        // 3.8 重置時間計數
        _currentNoticeStartTime = DateTime.now();

        // 3.9 重置已播放時間
        _noticeElapsedTime = Duration.zero;

        // 無影片：不需要初始化播放進度緩存

        // 3.11 费用表單和其他内容：统一使用轮播调度
        if (isArrearTable) {
          // 费用表單会通过自己的翻頁回调来控制轮播，这里只调度基础时间
          _scheduleNextCarousel(apiNoticeStayDuration);
        } else {
          // 普通内容，继续轮播
          _scheduleNextCarousel(apiNoticeStayDuration);
        }
      } catch (e) {
        // 切换失败时，延迟重试
        Future.delayed(const Duration(seconds: 2), () {
          if (!_isMidCarouselPaused) {
            _scheduleNextCarousel(apiNoticeStayDuration);
          }
        });
      }
    } catch (e) {
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
    //  如果是因為手動操作而暫停，保存當前狀態
    saveManualOperationState();

    // 保存暂停状态
    _savePauseState();

    // 设置轮播为暂停状态
    _isMidCarouselPaused = true;

    // 暂停所有定时器 - 确保完全暂停
    _pauseAllTimers();

    // 暂停轮播中的媒體内容
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
  }

  ///4，恢复通告轮播 - 修复时间计算逻辑
  void resumeMidCarousel(int apiNoticeStayDuration,
      {bool forceJumpToIndex = false, bool isFromManualOperation = false}) {
    // 显式取消旧的定时器，避免重复启动
    _pauseAllTimers();

    // 设置轮播为运行状态
    _isMidCarouselPaused = false;

    // 恢复暂停状态
    _currentNoticePauseTime = null;

    // 通告轮播恢复时，发送恢复通知而不是暂停通知
    _midCarouselController.resumeAllMedia();

    // 修复核心问题：从全屏广告恢复时的时间计算
    if (_midCarouselController.widgetCount >= 3 && !_isMidCarouselPaused) {
      _noticeDuration = Duration(seconds: apiNoticeStayDuration);

      // 修复关键问题：从全屏广告恢复时，重新开始时间计算
      _currentNoticeStartTime = DateTime.now();
      _noticeElapsedTime = Duration.zero;

      //  统一恢复逻辑：优先使用保存的索引，无论是手动操作还是默认状态恢复

      // 1. 优先尝试恢复保存的索引
      if (_savedCarouselIndex != null) {
        restoreManualOperationState();
      }
      // 2. 如果没有保存的索引，使用最后有效索引
      else if (_lastValidCarouselIndex != null &&
          _lastValidCarouselIndex! > 0 &&
          _lastValidCarouselIndex! < _midCarouselController.widgetCount) {
        _currentNoticeIndex = _lastValidCarouselIndex!;
        _jumpToVisibleIndex(_currentNoticeIndex);
      }
      // 3. 如果是从全屏广告恢复且当前在通告中，尝试切换到下一个通告
      else if (!isFromManualOperation && _isCurrentIndexInAnnouncements()) {
        final nextIndex = _getNextAnnouncementIndexFromFullscreen();
        if (nextIndex != -1) {
          _currentNoticeIndex = nextIndex;
          _recordValidCarouselIndex(_currentNoticeIndex);
          _jumpToVisibleIndex(_currentNoticeIndex);
        }
      }
      // 4. 兜底逻辑：检查当前索引是否有效
      else {
        if (_currentNoticeIndex < 2 ||
            _currentNoticeIndex >= _midCarouselController.widgetCount) {
          _currentNoticeIndex = _determineInitialCarouselIndex();
          if (_currentNoticeIndex < 2) {
            _currentNoticeIndex = 2; //  修复：确保从第一个正常通告开始，跳过占位符
          }
          _jumpToVisibleIndex(_currentNoticeIndex);
        }
      }

      // 开始正常的轮播调度，给当前内容完整的展示时间

      _scheduleNextCarousel(apiNoticeStayDuration);
    } else {
      // 条件不满足的情况

      // 即使不能轮播，也要确保当前显示正确的内容（跳过占位符）
      if (_midCarouselController.widgetCount >= 3 && _currentNoticeIndex < 2) {
        _currentNoticeIndex = 2; //  修复：跳转到第一个正常内容，跳过占位符
        _jumpToVisibleIndex(_currentNoticeIndex);
      }
    }

    notifyListeners();
  }

  /// 保存暂停状态
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
        } else {
          // 通告还在播放中
          _noticeElapsedTime = totalElapsed;
        }
      }

      // 無影片：不需要記錄視頻進度
    } catch (e) {
      // debugPrint('[AnnouncementCarousel]  保存暂停状态失败: $e');
    }
  }

  ///  记录有效的轮播索引（不包括主屏幕索引0和独立通告索引1）
  void _recordValidCarouselIndex(int index) {
    if (index > 1) {
      //  修复：只记录正常轮播的索引（2及以上），排除主屏幕和独立通告
      _lastValidCarouselIndex = index;
    }
  }

  ///  保存手動操作模式前的狀態（优化版）
  void saveManualOperationState() {
    try {
      //  关键修复：如果当前在独立通告模式，保存进入独立模式前的轮播索引
      if (_isInIndependentAnnouncementMode) {
        // debugPrint('[AnnouncementCarousel]  当前在独立通告模式，保存进入独立模式前的索引');

        //  新增：如果已经有保存的索引（进入独立模式前保存的），直接使用它
        if (_savedCarouselIndex != null && _savedCarouselIndex! >= 2) {
          // debugPrint(
          //     '[AnnouncementCarousel]  使用已保存的进入独立模式前索引: $_savedCarouselIndex');
          return; // 不要覆盖已保存的索引
        }

        // 否则使用最后有效的轮播索引
        if (_lastValidCarouselIndex != null && _lastValidCarouselIndex! >= 2) {
          _savedCarouselIndex = _lastValidCarouselIndex!;
          // debugPrint(
          //     '[AnnouncementCarousel]  保存最后有效轮播索引: $_lastValidCarouselIndex');
        } else {
          // 如果没有最后有效索引，使用默认值2（第一个正常通告）
          _savedCarouselIndex = 2;
          // debugPrint('[AnnouncementCarousel]  使用默认轮播索引: 2（第一个正常通告）');
        }
        return;
      }

      // 正常情况：保存当前轮播索引
      if (_currentNoticeIndex > 0 &&
          _currentNoticeIndex < _midCarouselController.widgetCount) {
        // 当前索引有效且不是主屏幕，直接保存
        _savedCarouselIndex = _currentNoticeIndex;
        // debugPrint('[AnnouncementCarousel]  保存当前轮播索引: $_currentNoticeIndex');
      } else if (_lastValidCarouselIndex != null &&
          _lastValidCarouselIndex! > 0) {
        // 当前索引无效，使用最后有效的轮播索引
        _savedCarouselIndex = _lastValidCarouselIndex!;
        // debugPrint(
        //     '[AnnouncementCarousel]  保存最后有效轮播索引: $_lastValidCarouselIndex');
      } else {
        // debugPrint(
        //     '[AnnouncementCarousel]  没有有效的轮播索引可保存，当前索引: $_currentNoticeIndex');
      }
    } catch (e) {
      // debugPrint('[AnnouncementCarousel]  保存手动操作前有效轮播索引失败: $e');
    }
  }

  ///  恢復手動操作模式前的狀態
  void restoreManualOperationState() {
    if (_savedCarouselIndex != null) {
      // 验证保存的索引是否有效
      final totalWidgets = _midCarouselController.widgetCount;
      if (_savedCarouselIndex! >= 2 && _savedCarouselIndex! < totalWidgets) {
        //  修复：确保不会恢复到索引0或1
        // 恢复到之前的轮播索引
        _currentNoticeIndex = _savedCarouselIndex!;
        _recordValidCarouselIndex(_currentNoticeIndex); // 记录有效索引

        //  重点：从头开始展示当前内容（重置时间）
        _noticeElapsedTime = Duration.zero;
        _currentNoticeStartTime = DateTime.now();
        _currentNoticePauseTime = null;

        // 跳转到保存的索引
        _jumpToVisibleIndex(_currentNoticeIndex);

        // debugPrint(
        //     '[AnnouncementCarousel]  成功恢复到手动操作前的索引: $_currentNoticeIndex');

        //  关键：如果是表单，用户之前停留在某一页，现在恢复后会继续从那一页开始
        // 不需要特殊处理，表单Widget内部会保持其页码状态
      } else {
        // debugPrint(
        //     '[AnnouncementCarousel]  保存的索引无效或指向占位符: $_savedCarouselIndex，总Widget数: $totalWidgets');
        _currentNoticeIndex = totalWidgets > 2 ? 2 : 0; //  修复：确保跳转到有效内容，不是占位符
        _recordValidCarouselIndex(_currentNoticeIndex); // 记录有效索引
        _jumpToVisibleIndex(_currentNoticeIndex);
      }

      // 清除保存的状态
      _savedCarouselIndex = null;
      return;
    } else {
      // debugPrint('[AnnouncementCarousel]  没有保存的轮播索引，无法恢复');
    }
  }

  ///5，更新轮播暂停状态
  void updateCarouselPauseState(bool isPaused) {
    _isMidCarouselPaused = isPaused;

    // 使用 addPostFrameCallback 延迟通知，避免 setState during build 错误
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (hasListeners) {
        notifyListeners();
      }
    });
  }

  ///6，检查并恢复轮播状态（监控定时器使用）
  void checkAndRestoreMidCarousel(int apiNoticeStayDuration) {
    // 修复：确保即使没有通告也能轮播（至少要有主屏幕和缴费表單）
    if ((_midCarouselController.widgetCount - 1) > 0 && !_isMidCarouselPaused) {
      // 检查当前定时器是否活跃
      if (_midTimer == null || !_midTimer!.isActive) {
        // 确保当前索引在内容范围内（跳过占位符）
        if (_currentNoticeIndex < 2) {
          _currentNoticeIndex = 2; //  修复：确保从第一个正常通告开始，跳过占位符
          _jumpToVisibleIndex(_currentNoticeIndex);
        }

        _scheduleNextCarousel(apiNoticeStayDuration);
      }
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

  ///9，暂停所有计时器（用于设置頁面）
  void pauseAllTimersForSettings() {
    _pauseAllTimers();
    _midCarouselController.pauseAllMedia();
    _isMidCarouselPaused = true;
    notifyListeners();
  }

  ///10，从设置頁面恢复所有计时器
  void resumeAllTimersFromSettings(int apiNoticeStayDuration) {
    _isMidCarouselPaused = false;
    _midCarouselController.resumeAllMedia();

    // 恢复通告轮播
    // 修复：即使只有管理费用表格也要进入轮播模式
    if (_midCarouselController.widgetCount >= 3) {
      _currentNoticeStartTime = DateTime.now();

      // 确保当前索引在内容范围内（跳过占位符）
      if (_currentNoticeIndex < 2) {
        _currentNoticeIndex = 2; //  修复：确保从第一个正常通告开始，跳过占位符
        _jumpToVisibleIndex(_currentNoticeIndex);
      }

      _scheduleNextCarousel(apiNoticeStayDuration);
    }

    // 重新启动调试定时器
    startDebugTimer(apiNoticeStayDuration);

    notifyListeners();
  }

  ///11，跳转到指定通告索引
  void jumpToAnnouncementIndex(int index) {
    debugPrint(
        '[AnnouncementCarousel]  跳转请求: 目标索引=$index, 当前索引=$_currentNoticeIndex, 暂停状态=$_isMidCarouselPaused');

    if (index >= 0 && index < _midCarouselController.widgetCount) {
      //  修复：如果在独立通告模式，任何跳转都应该先退出独立模式
      if (_isInIndependentAnnouncementMode) {
        // debugPrint('[AnnouncementCarousel]  在独立模式中跳转，先退出独立模式');
        exitIndependentAnnouncementMode(targetIndex: index);
        return;
      }

      _currentNoticeIndex = index;
      _recordValidCarouselIndex(_currentNoticeIndex); // 记录有效索引
      _jumpToVisibleIndex(index);
      _currentNoticeStartTime = DateTime.now();
      // _logger.i('�� 跳转到通告索引: $index'); // _logger is not defined
      // //debugPrint('[AnnouncementCarousel]  跳转到通告索引: $index'); // _logger is not defined
      notifyListeners();
    }
  }

  ///13a，显示管理費用表單界面（手动操作模式 - 不启用自动翻頁）
  void showArrearTableWidget(VoidCallback onHomeButtonPressed) {
    // 设置显示欠费总览状态
    _isShowingArrearTable = true;
    notifyListeners();
  }

  // 标记当前是否在独立通告模式
  bool _isInIndependentAnnouncementMode = false;

  ///14，直接显示独立通告（不依赖轮播逻辑）
  void showIndependentAnnouncement(
      AnnouncementModel announcement, VoidCallback? onHomeButtonPressed) {
    // debugPrint('[AnnouncementCarousel]  开始显示独立通告: ${announcement.title}');

    //  关键修复：在进入独立模式前保存当前轮播状态
    if (!_isInIndependentAnnouncementMode && _currentNoticeIndex >= 2) {
      _savedCarouselIndex = _currentNoticeIndex;
      // debugPrint(
      //     '[AnnouncementCarousel]  进入独立模式前保存轮播索引: $_currentNoticeIndex');
    }

    // 标记进入独立通告模式
    _isInIndependentAnnouncementMode = true;
    // debugPrint(
    //     '[AnnouncementCarousel]  已设置独立通告模式标志: $_isInIndependentAnnouncementMode');

    //  关键修复：暂停当前轮播，避免冲突
    _pauseAllTimers();
    _isMidCarouselPaused = true;

    // 创建独立通告显示頁面，直接根据通告的文件信息
    FileManager fileManager = FileManager();

    Widget announcementWidget = Center(
      child: AnnouncementReaderWidget(
        announcement: announcement,
        fileManager: fileManager,
        isInCarouselMode: false, // 独立显示模式 - 不会自动翻页
        onHomeButtonPressed: onHomeButtonPressed ??
            () {
              // 默认返回主頁行为：退出独立模式
              exitIndependentAnnouncementMode();
            },
        onPdfCompleted: () {
          // 独立模式下PDF完成不需要特殊处理
          // debugPrint('[AnnouncementCarousel]  独立模式PDF播放完成');
        },
        onPdfPaginationStart: (int totalPages) {
          // 独立模式下不需要延长时间
          // debugPrint('[AnnouncementCarousel]  独立模式PDF开始翻页: $totalPages页');
        },
      ),
    );

    // 创建临时轮播内容：只保留主屏幕和当前选中的通告
    //  修复：使用专门的退出回调
    Widget mainScreenWidget = _createMainScreenWidget(() {
      // 点击主屏幕时退出独立模式
      exitIndependentAnnouncementMode();
    });

    //  优雅的解决方案：使用简洁的独立轮播结构，避免索引冲突
    List<Widget> tempWidgets = [
      mainScreenWidget, // 索引 0: 主屏幕
      announcementWidget, // 索引 1: 独立通告（临时使用，不会与正常轮播冲突）
    ];

    // 设置临时轮播内容
    _midCarouselController.setCarouselArray(tempWidgets);
    _jumpToVisibleIndex(1); // 跳转到独立通告

    // debugPrint('[AnnouncementCarousel]  进入独立通告模式，已暂停轮播，独立通告索引: 1（临时轮播）');
  }

  ///14a，退出独立通告模式，恢复正常轮播内容
  void exitIndependentAnnouncementMode({int? targetIndex}) {
    if (!_isInIndependentAnnouncementMode) {
      // debugPrint('[AnnouncementCarousel]  当前不在独立通告模式，无需退出');
      return;
    }

    // debugPrint('[AnnouncementCarousel]  退出独立通告模式，恢复正常轮播内容');

    // 标记退出独立通告模式
    _isInIndependentAnnouncementMode = false;

    //  关键修复：清除通告Widget缓存，强制重新创建以确保PDF能正确初始化
    _clearAnnouncementWidgetCache();

    //  关键修复：强制清除所有Widget缓存，确保完全重新创建
    _widgetCache.clear();
    _fileManagerCache.clear();
    // debugPrint('[AnnouncementCarousel]  已清除所有Widget缓存，强制重新创建');

    //  关键修复：强制重新构建轮播内容，恢复正常的通告+费用表格轮播
    // debugPrint(
    //     '[AnnouncementCarousel]  开始重新构建轮播内容，通告数量: ${_carouselAnnouncements.length}');
    _forceUpdateCarousel(_carouselAnnouncements);
    // debugPrint(
    //     '[AnnouncementCarousel]  轮播内容重新构建完成，Widget数量: ${_midCarouselController.widgetCount}');

    //  修复：强制立即通知UI更新，确保新Widget生效
    notifyListeners();

    //  修复：延迟一小段时间确保Widget完全重新创建后再跳转
    Future.delayed(const Duration(milliseconds: 100), () {
      final resolvedTargetIndex =
          AnnouncementCarouselExitPolicy.resolveTargetIndex(
        requestedTargetIndex: targetIndex,
        savedCarouselIndex: _savedCarouselIndex,
        widgetCount: _midCarouselController.widgetCount,
        initialCarouselIndex: _determineInitialCarouselIndex(),
      );

      _currentNoticeIndex = resolvedTargetIndex;
      _recordValidCarouselIndex(_currentNoticeIndex);

      // debugPrint(
      //     '[AnnouncementCarousel]  准备跳转到目标索引: $resolvedTargetIndex，当前Widget数量: ${_midCarouselController.widgetCount}');

      // 跳转到目标索引
      if (_midCarouselController.widgetCount > resolvedTargetIndex) {
        _jumpToVisibleIndex(_currentNoticeIndex);
        // debugPrint(
        //     '[AnnouncementCarousel]  已恢复到正常轮播，当前索引: $_currentNoticeIndex');

        //  关键修复：恢复后立即启动轮播调度，确保PDF等内容能正常工作
        final bool hasContent = hasCarouselContent;
        if (hasContent && !_isMidCarouselPaused) {
          // 重置时间状态并启动轮播
          _currentNoticeStartTime = DateTime.now();
          _noticeElapsedTime = Duration.zero;

          // 启动轮播调度
          _scheduleNextCarousel(_noticeDuration.inSeconds);
          // debugPrint(
          //     '[AnnouncementCarousel]  已启动轮播调度，停留时间: ${_noticeDuration.inSeconds}秒');
        } else {
          // debugPrint(
          //     '[AnnouncementCarousel]  轮播调度未启动 - hasContent: $hasContent, paused: $_isMidCarouselPaused');
        }

        //  修复：强制再次通知UI，确保新创建的Widget能够正确渲染
        WidgetsBinding.instance.addPostFrameCallback((_) {
          notifyListeners();
          // debugPrint('[AnnouncementCarousel]  PostFrame回调完成，确保Widget完全渲染');
        });
      } else {
        // 如果目标索引无效，至少跳转到主屏幕
        _currentNoticeIndex = 0;
        _jumpToVisibleIndex(0);
        // debugPrint('[AnnouncementCarousel]  目标索引无效，跳转到主屏幕');
      }

      //  修复：清除在独立模式前保存的索引，避免与手动操作的索引冲突
      // 注意：这里不清除_savedCarouselIndex，因为它可能是手动操作模式保存的

      // 再次通知UI更新，确保所有状态同步
      notifyListeners();
    });
  }

  ///14b，检查是否在独立通告模式
  bool get isInIndependentAnnouncementMode {
    // debugPrint(
    //     '[AnnouncementCarousel]  检查独立通告模式标志: $_isInIndependentAnnouncementMode');
    return _isInIndependentAnnouncementMode;
  }

  ///15，创建主屏幕Widget（辅助方法）
  Widget _createMainScreenWidget(VoidCallback onHomeButtonPressed) {
    return MainScreenWidget(
      onAnnouncementTap: (AnnouncementModel? announcement) {
        if (announcement == null) {
        } else {
          // 显示独立通告 - 使用_homeButtonCallback确保返回按钮能正确工作
          showIndependentAnnouncement(announcement, _homeButtonCallback);
        }
      },
      onArrearTableTap: () {
        // 显示欠费总览界面 - 修复：使用_homeButtonCallback确保返回按钮能正确工作
        showArrearTableWidget(_homeButtonCallback);
      },
    );
  }

  ///17，动态延长当前通告停留时间（费用表單和PDF開始翻頁時調用）
  void _extendCurrentNoticeStayTime(int totalPages) {
    // 檢查是否在費用表格或PDF翻頁狀態
    final isInArrearTables = _isCurrentIndexInArrearTables();
    final isInPdfPagination = _isPdfPaginationActive;
    final isInAnnouncements = _isCurrentIndexInAnnouncements();

    // 允許通告中的PDF翻頁或費用表格翻頁
    if (!isInArrearTables && !isInPdfPagination && !isInAnnouncements) {
      // debugPrint('[AnnouncementCarousel]  当前不在费用表单、PDF翻页或通告状态，不延长停留时间');
      return;
    }

    // 该方法现在主要用于动态延长轮播时间
    // debugPrint('[AnnouncementCarousel]  延长停留时间，总頁数: $totalPages');

    // 计算需要延长的时间：根据当前类型使用不同的翻页间隔
    final deviceSettings = _appDataProvider.deviceSettings;

    int paginationDuration;

    if (isInPdfPagination) {
      // PDF翻頁：使用通告停留時間 (noticeStayDuration)
      paginationDuration = deviceSettings?.noticeStayDuration ?? 5;
      // debugPrint(
      //     '[AnnouncementCarousel]  PDF翻页，翻页间隔: ${paginationDuration}秒');
    } else {
      // 費用表格翻頁：使用費用表格時間間隔
      final baseDuration = deviceSettings?.paymentTableOnePageDuration ?? 3;
      // 判断当前是哪种费用表格
      final currentIndex = _currentNoticeIndex;
      final otherTableIndex = _findOtherTableIndex();
      final managementTableIndex = _findManagementTableIndex();

      if (currentIndex == otherTableIndex) {
        // 其他费用表格，翻页较慢（乘以2）
        paginationDuration = baseDuration * 2;
        // debugPrint(
        //     '[AnnouncementCarousel]  其他费用表格，翻页间隔: ${paginationDuration}秒');
      } else if (currentIndex == managementTableIndex) {
        // 管理费用表格，翻页较快（乘以1）
        paginationDuration = baseDuration * 1;
        // debugPrint(
        //     '[AnnouncementCarousel]  管理费用表格，翻页间隔: ${paginationDuration}秒');
      } else {
        // 默认情况
        paginationDuration = baseDuration;
        // debugPrint(
        //     '[AnnouncementCarousel]  默认费用表格，翻页间隔: ${paginationDuration}秒');
      }
    }

    //  修复：增加额外的缓冲时间，确保能完成所有页面翻页
    double bufferTime;
    if (isInPdfPagination) {
      bufferTime = 0.5; // PDF多頁緩衝時間設為0.5秒
    } else {
      bufferTime = 3; // 費用表格保持3秒緩衝時間
    }

    final int extensionSeconds =
        (totalPages * paginationDuration + bufferTime).round();

    // 取消现有的定时器，避免冲突
    _midTimer?.cancel();

    // 重新设置开始时间，相当于重新开始计时
    _currentNoticeStartTime = DateTime.now();

    // 使用延长后的时间重新调度轮播
    final extendedDuration = _noticeDuration.inSeconds + extensionSeconds;

    // if (isInPdfPagination) {
    //   debugPrint(
    //       '[AnnouncementCarousel] PDF翻頁开始，延长停留时间: ${extensionSeconds}秒（含${bufferTime}秒缓冲），总时长: ${extendedDuration}秒');
    // } else {
    //   debugPrint(
    //       '[AnnouncementCarousel] 费用表單翻頁开始，延长停留时间: ${extensionSeconds}秒（含${bufferTime.round()}秒缓冲），总时长: ${extendedDuration}秒');
    // }

    // 使用延长后的时间调度下一次轮播
    _scheduleNextCarousel(extendedDuration);
  }

  ///17.1，其他费用表單翻頁完成处理
  void _onOtherTablePaginationComplete() {
    //debugPrint('[AnnouncementCarousel]  其他费用表單翻頁完成');

    // 检查当前轮播模式
    final bool hasAnnouncements = _carouselAnnouncements.isNotEmpty;
    final bool hasManagementData =
        _arrearProvider?.hasManagementFeeData == true;

    // debugPrint(
    //     '[AnnouncementCarousel]  当前数据状态: 通告=$hasAnnouncements, 管理费用=$hasManagementData');

    if (hasManagementData) {
      // 如果有管理费用数据，跳转到管理费用表單
      //debugPrint('[AnnouncementCarousel]  跳转到管理费用表單');
      _jumpToManagementTable();
    } else if (hasAnnouncements) {
      //  修复：如果没有管理费用数据但有通告，应该使用智能切换
      //debugPrint('[AnnouncementCarousel]  没有管理费用，使用智能切换到通告');
      final nextIndex = _determineNextCarouselIndex();
      if (nextIndex != -1) {
        _currentNoticeIndex = nextIndex;
        _jumpToVisibleIndex(_currentNoticeIndex);
        _currentNoticeStartTime = DateTime.now();
        debugPrint(
            '[AnnouncementCarousel]  其他费用表單完成，切换到索引: $_currentNoticeIndex');
        _scheduleNextCarousel(_noticeDuration.inSeconds);
      } else {
        //debugPrint('[AnnouncementCarousel]  无法确定下一个索引，使用默认切换');
        _goToNextCarouselItem();
      }
    } else {
      // 这种情况不应该出现，但为了安全起见
      //debugPrint('[AnnouncementCarousel]  异常状态：其他费用表單完成但没有后续内容');
    }
  }

  ///17.1.1，PDF多頁翻頁開始處理
  void _onPdfPaginationStart(int totalPages) {
    _isPdfPaginationActive = true;
    // debugPrint('[AnnouncementCarousel]  PDF多頁翻頁開始，總頁數: $totalPages');

    // 使用與費用表格相同的延長時間邏輯
    _extendCurrentNoticeStayTime(totalPages);
  }

  ///17.1.2，PDF多頁翻頁完成處理
  void _onPdfPaginationComplete() {
    _isPdfPaginationActive = false;
    // debugPrint('[AnnouncementCarousel]  PDF多頁翻頁完成');

    // PDF播放完成，强制切換到下一個通告（不受表格翻页状态影响）
    _forceGoToNextCarouselItem();
  }

  ///17.1.3，强制切換到下一個轮播项（PDF完成专用）
  void _forceGoToNextCarouselItem() {
    // debugPrint('[AnnouncementCarousel] 当前状态: '
    //     'isPaused=$_isMidCarouselPaused, '
    //     'isOtherTablePaginationActive=$_isOtherTablePaginationActive, '
    //     'isManagementTablePaginationActive=$_isManagementTablePaginationActive, '
    //     'onlyManagementTableMode=$_onlyManagementTableMode');

    if (_isMidCarouselPaused) {
      return;
    }

    // 僅管理費用模式：不切換輪播
    if (_onlyManagementTableMode) {
      return;
    }

    try {
      // debugPrint(
      //     '[AnnouncementCarousel] 当前索引: $_currentNoticeIndex, 总widget数: ${_midCarouselController.widgetCount}');
      // debugPrint(
      //     '[AnnouncementCarousel] 轮播控制器状态: isAttached=${_midCarouselController.isAttached}, currentIndex=${_midCarouselController.currentIndex}');

      // 确定下一个目标索引 - 从通告跳转到费用表單或下一个通告
      int targetIndex = _determineNextCarouselIndex();

      if (targetIndex == -1) {
        return;
      }

      _currentNoticeIndex = targetIndex;

      _jumpToVisibleIndex(_currentNoticeIndex);

      Future.delayed(const Duration(milliseconds: 100), () {
        // 重新调度轮播，使用标准时间
        _currentNoticeStartTime = DateTime.now();
        _scheduleNextCarousel(_noticeDuration.inSeconds);
      });
    } catch (e) {
      // debugPrint('[AnnouncementCarousel]  PDF完成后强制切换失败: $e');
    }
  }

  ///17.2，管理费用表單翻頁完成处理
  void _onManagementTablePaginationComplete() {
    //debugPrint('[AnnouncementCarousel]  管理费用表單翻頁完成');

    // 检查当前轮播模式
    final bool hasAnnouncements = _carouselAnnouncements.isNotEmpty;
    final bool hasOtherData = _arrearProvider?.hasAnyOtherFeeRecords == true;
    final bool hasManagementData =
        _arrearProvider?.hasManagementFeeData == true;

    // debugPrint(
    //     '[AnnouncementCarousel]  当前数据状态: 通告=$hasAnnouncements, 其他费用=$hasOtherData, 管理费用=$hasManagementData');

    if (!hasAnnouncements && !hasOtherData && hasManagementData) {
      // 情况4：只有管理费用表單，应该在表單内部循环，不切换轮播
      //debugPrint('[AnnouncementCarousel]  只有管理费用表單模式，不切换轮播');
      return;
    } else if (!hasAnnouncements && hasOtherData && hasManagementData) {
      // 情况3：无通告+两种table，跳转到其他费用表單
      //debugPrint('[AnnouncementCarousel]  无通告双表模式，跳转到其他费用表單');
      _jumpToOtherTable();
    } else if (hasAnnouncements) {
      //  修复：有通告的情况，管理费用表格已经完成所有页面翻页，现在切换到下一个通告
      //debugPrint('[AnnouncementCarousel]  有通告模式，管理费用表格翻页完成，切换到下一个通告');
      final nextIndex = _determineNextCarouselIndex();
      if (nextIndex != -1) {
        _currentNoticeIndex = nextIndex;
        _recordValidCarouselIndex(_currentNoticeIndex); // 记录有效索引
        _jumpToVisibleIndex(_currentNoticeIndex);
        _currentNoticeStartTime = DateTime.now();
        // debugPrint(
        //     '[AnnouncementCarousel]  管理费用表單完成，切换到索引: $_currentNoticeIndex');
        _scheduleNextCarousel(_noticeDuration.inSeconds);
      } else {
        //debugPrint('[AnnouncementCarousel]  无法确定下一个索引，使用默认切换');
        _goToNextCarouselItem();
      }
    } else {
      // 其他异常情况
      //debugPrint('[AnnouncementCarousel]  未知的轮播状态');
      _goToNextCarouselItem();
    }
  }

  ///17.3.1，跳转到其他费用表單
  void _jumpToOtherTable() {
    //debugPrint('[AnnouncementCarousel]  跳转到其他费用表單');

    try {
      // 查找其他费用表單的索引
      final otherTableIndex = _findOtherTableIndex();

      if (otherTableIndex != -1) {
        _currentNoticeIndex = otherTableIndex;
        _recordValidCarouselIndex(_currentNoticeIndex); // 记录有效索引
        _jumpToVisibleIndex(_currentNoticeIndex);

        // debugPrint(
        //     '[AnnouncementCarousel]  已跳转到其他费用表單，索引: $_currentNoticeIndex');

        // 重置开始时间
        _currentNoticeStartTime = DateTime.now();
      } else {
        //debugPrint('[AnnouncementCarousel]  未找到其他费用表單，保持当前状态');
        // 如果找不到其他费用表單，可能数据有问题，保持当前状态
      }
    } catch (e) {
      // debugPrint('[AnnouncementCarousel]  跳转到其他费用表單失败: $e');
    }
  }

  ///17.3.2，查找其他费用表單的索引
  int _findOtherTableIndex() {
    try {
      // 从widget缓存中查找其他费用表單
      final otherKeys = _widgetCache.keys
          .where((key) => key.startsWith('other_fee_table_'))
          .toList();

      if (otherKeys.isEmpty) {
        //debugPrint('[AnnouncementCarousel]  其他费用表單不存在');
        return -1;
      }

      // 计算其他费用表單的索引：主屏幕(0) → 独立通告(1) → 正常通告们(2~n) → 其他费用表
      int index = 2; // 从索引2开始（跳过主屏幕和独立通告）

      // 跳过正常通告
      index += _carouselAnnouncements.length;

      // 现在index应该指向其他费用表單
      //debugPrint('[AnnouncementCarousel]  计算出的其他费用表單索引: $index');

      // 验证索引是否在有效范围内
      if (index < _midCarouselController.widgetCount) {
        return index;
      } else {
        // debugPrint(
        //     '[AnnouncementCarousel]  计算的索引超出范围: $index >= ${_midCarouselController.widgetCount}');
        return -1;
      }
    } catch (e) {
      // debugPrint('[AnnouncementCarousel]  查找其他费用表單索引失败: $e');
      return -1;
    }
  }

  ///17.3，跳转到管理费用表單
  void _jumpToManagementTable() {
    //debugPrint('[AnnouncementCarousel]  跳转到管理费用表單');

    try {
      // 查找管理费用表單的索引
      final managementTableIndex = _findManagementTableIndex();

      if (managementTableIndex != -1) {
        _currentNoticeIndex = managementTableIndex;
        _recordValidCarouselIndex(_currentNoticeIndex); // 记录有效索引
        _jumpToVisibleIndex(_currentNoticeIndex);

        // debugPrint(
        //     '[AnnouncementCarousel]  已跳转到管理费用表單，索引: $_currentNoticeIndex');

        // 重置开始时间
        _currentNoticeStartTime = DateTime.now();
      } else {
        //debugPrint('[AnnouncementCarousel]  未找到管理费用表單，跳转到通告');
        _goToNextCarouselItem();
      }
    } catch (e) {
      // debugPrint('[AnnouncementCarousel]  跳转到管理费用表單失败: $e');
      _goToNextCarouselItem();
    }
  }

  ///17.4，查找管理费用表單的索引
  int _findManagementTableIndex() {
    try {
      // 从widget缓存中查找管理费用表單
      final managementKeys = _widgetCache.keys
          .where((key) => key.startsWith('management_fee_table_'))
          .toList();

      if (managementKeys.isEmpty) {
        //debugPrint('[AnnouncementCarousel]  管理费用表單不存在');
        return -1;
      }

      // 在轮播控制器中查找该key对应的索引
      // 这里需要根据实际的轮播组件顺序来确定索引
      // 由于我们知道顺序是：主屏幕(0) → 独立通告(1) → 正常通告们(2~n) → 其他费用表 → 管理费用表
      int index = 2; // 从索引2开始（跳过主屏幕和独立通告）

      // 跳过正常通告
      index += _carouselAnnouncements.length;

      // 跳过其他费用表（如果存在）
      final hasOtherData = _arrearProvider?.hasAnyOtherFeeRecords == true;
      if (hasOtherData) {
        index += 1;
      }

      // 现在index应该指向管理费用表單
      //debugPrint('[AnnouncementCarousel]  计算出的管理费用表單索引: $index');

      // 验证索引是否在有效范围内
      if (index < _midCarouselController.widgetCount) {
        return index;
      } else {
        // debugPrint(
        //     '[AnnouncementCarousel]  计算的索引超出范围: $index >= ${_midCarouselController.widgetCount}');
        return -1;
      }
    } catch (e) {
      // debugPrint('[AnnouncementCarousel]  查找管理费用表單索引失败: $e');
      return -1;
    }
  }

  ///17.5，确定下一个轮播索引
  int _determineNextCarouselIndex() {
    return AnnouncementCarouselIndexPolicy.nextIndex(
      currentIndex: _currentNoticeIndex,
      announcementCount: _carouselAnnouncements.length,
      hasOtherTable: _arrearProvider?.hasAnyOtherFeeRecords == true,
      hasManagementTable: _arrearProvider?.hasManagementFeeData == true,
      firstArrearTableIndex: _getFirstArrearTableIndex(),
      otherTableIndex: _findOtherTableIndex(),
      managementTableIndex: _findManagementTableIndex(),
    );
  }

  ///17.6，检查当前索引是否在费用表單中
  bool _isCurrentIndexInArrearTables() {
    // 计算费用表單的索引范围
    int arrearStartIndex =
        2 + _carouselAnnouncements.length; //  修复：主屏幕(0) + 独立通告(1) + 正常通告们(2~n)

    final bool hasOtherData = _arrearProvider?.hasAnyOtherFeeRecords == true;
    final bool hasManagementData =
        _arrearProvider?.hasManagementFeeData == true;

    int arrearEndIndex = arrearStartIndex - 1; // 如果没有费用表單，范围为空

    if (hasOtherData) {
      arrearEndIndex++;
    }
    if (hasManagementData) {
      arrearEndIndex++;
    }

    bool isInArrear = _currentNoticeIndex >= arrearStartIndex &&
        _currentNoticeIndex <= arrearEndIndex;
    // debugPrint(
    //     '[AnnouncementCarousel]  检查是否在费用表單: 当前索引=$_currentNoticeIndex, 费用表單范围=[$arrearStartIndex, $arrearEndIndex], 结果=$isInArrear');

    return isInArrear;
  }

  ///24，检查当前索引是否在通告中
  bool _isCurrentIndexInAnnouncements() {
    if (_carouselAnnouncements.isEmpty) {
      return false;
    }

    const int announcementStartIndex = 2; //  修复：正常通告从索引2开始
    final int announcementEndIndex =
        1 + _carouselAnnouncements.length; //  修复：通告结束索引（1 + 通告数量）

    final isInAnnouncement = _currentNoticeIndex >= announcementStartIndex &&
        _currentNoticeIndex <= announcementEndIndex;

    // debugPrint(
    //     '[AnnouncementCarousel]  检查是否在通告中: 当前索引=$_currentNoticeIndex, 通告范围=[$announcementStartIndex, $announcementEndIndex], 结果=$isInAnnouncement');

    return isInAnnouncement;
  }

  ///25，从全屏广告恢复时的通告切换逻辑
  int _getNextAnnouncementIndexFromFullscreen() {
    if (_carouselAnnouncements.isEmpty) {
      //debugPrint('[AnnouncementCarousel]  没有通告，无法切换');
      return -1;
    }

    const int announcementStartIndex = 2; //  修复：正常通告从索引2开始
    final int announcementEndIndex =
        1 + _carouselAnnouncements.length; //  修复：通告结束索引

    debugPrint(
        '[AnnouncementCarousel]  全屏广告恢复：当前索引=$_currentNoticeIndex, 通告范围=[$announcementStartIndex, $announcementEndIndex]');

    // 如果当前在通告中
    if (_isCurrentIndexInAnnouncements()) {
      int nextIndex = _currentNoticeIndex + 1;

      // 如果下一个索引仍在通告范围内，切换到下一个通告
      if (nextIndex <= announcementEndIndex) {
        //debugPrint('[AnnouncementCarousel]  切换到下一个通告: $nextIndex');
        return nextIndex;
      } else {
        // 如果是最后一个通告，切换到费用表格
        final firstArrearIndex = _getFirstArrearTableIndex();
        if (firstArrearIndex != -1) {
          debugPrint('[AnnouncementCarousel]  通告结束，切换到费用表格: $firstArrearIndex');
          return firstArrearIndex;
        } else {
          // 如果没有费用表格，循环回到第一个通告
          debugPrint(
              '[AnnouncementCarousel]  通告结束且无费用表格，回到第一个通告: $announcementStartIndex');
          return announcementStartIndex;
        }
      }
    }

    // 如果当前不在通告中，默认跳转到第一个通告
    debugPrint(
        '[AnnouncementCarousel]  非通告状态，跳转到第一个通告: $announcementStartIndex');
    return announcementStartIndex;
  }

  ///17.7，获取第一个费用表單的索引
  int _getFirstArrearTableIndex() {
    int arrearStartIndex =
        2 + _carouselAnnouncements.length; //  修复：主屏幕(0) + 独立通告(1) + 正常通告们(2~n)

    final bool hasOtherData = _arrearProvider?.hasAnyOtherFeeRecords == true;
    final bool hasManagementData =
        _arrearProvider?.hasManagementFeeData == true;

    // debugPrint(
    //     '[AnnouncementCarousel]  查找第一个费用表單: 通告数=${_carouselAnnouncements.length}, 计算起始索引=$arrearStartIndex');
    // debugPrint(
    //     '[AnnouncementCarousel]  费用表單数据状态: 其他费用=$hasOtherData, 管理费用=$hasManagementData');

    if (hasOtherData) {
      //debugPrint('[AnnouncementCarousel]  返回其他费用表單索引: $arrearStartIndex');
      return arrearStartIndex; // 其他费用表單在前
    } else if (hasManagementData) {
      //debugPrint('[AnnouncementCarousel]  返回管理费用表單索引: $arrearStartIndex');
      return arrearStartIndex; // 只有管理费用表單
    }

    //debugPrint('[AnnouncementCarousel]  没有费用表單数据');
    return -1; // 没有费用表單
  }

  ///18，切换到下一个轮播项（管理費用表單翻頁完成後調用）
  void _goToNextCarouselItem() {
    //debugPrint('[AnnouncementCarousel]  进入 _goToNextCarouselItem 方法');
    // debugPrint('[AnnouncementCarousel] 当前状态: '
    //     'isPaused=$_isMidCarouselPaused, '
    //     'isOtherTablePaginationActive=$_isOtherTablePaginationActive, '
    //     'isManagementTablePaginationActive=$_isManagementTablePaginationActive, '
    //     'onlyManagementTableMode=$_onlyManagementTableMode');

    if (_isMidCarouselPaused) {
      //debugPrint('[AnnouncementCarousel]  轮播已暂停，跳过切换');
      return;
    }

    // 僅管理費用模式：不切換輪播，由表內自行首末頁循環
    if (_onlyManagementTableMode) {
      //debugPrint('[AnnouncementCarousel]  僅管理費用模式，跳过切换');
      return;
    }

    // 如果任何费用表單仍在翻頁，则不进行轮播切换
    if (_isOtherTablePaginationActive || _isManagementTablePaginationActive) {
      //debugPrint('[AnnouncementCarousel]  仍有费用表單在活跃翻頁，跳过切换');
      return;
    }

    try {
      //debugPrint('[AnnouncementCarousel]  开始切换到下一个轮播项');
      // debugPrint(
      //     '[AnnouncementCarousel] 当前索引: $_currentNoticeIndex, 总widget数: ${_midCarouselController.widgetCount}');
      // debugPrint(
      //     '[AnnouncementCarousel] 轮播控制器状态: isAttached=${_midCarouselController.isAttached}, currentIndex=${_midCarouselController.currentIndex}');

      // 确定下一个目标索引 - 从费用表單跳转到通告
      int targetIndex = _determineNextCarouselIndex();

      if (targetIndex == -1) {
        //debugPrint('[AnnouncementCarousel]  无法确定下一个轮播索引');
        return;
      }

      _currentNoticeIndex = targetIndex;
      //debugPrint('[AnnouncementCarousel]  目标索引: $_currentNoticeIndex');

      _jumpToVisibleIndex(_currentNoticeIndex);

      Future.delayed(const Duration(milliseconds: 100), () {
        final actualIndex = _midCarouselController.currentIndex;
        // debugPrint(
        //     '[AnnouncementCarousel]  跳转完成，目标索引: $_currentNoticeIndex, 实际索引: $actualIndex');

        if (actualIndex != _currentNoticeIndex) {
          //debugPrint('[AnnouncementCarousel]  跳转失败，强制重新跳转');
          _jumpToVisibleIndex(_currentNoticeIndex);
        }
      });

      _currentNoticeStartTime = DateTime.now();

      //debugPrint('[AnnouncementCarousel] 缴费表單翻頁完成，切换到索引: $_currentNoticeIndex');

      _scheduleNextCarousel(_noticeDuration.inSeconds);
    } catch (e) {
      // debugPrint('[AnnouncementCarousel]  切换失败: $e');
      Future.delayed(const Duration(seconds: 2), () {
        if (!_isMidCarouselPaused) {
          _goToNextCarouselItem();
        }
      });
    }
  }

  ///19，强制恢复轮播组件
  void forceRecovery() {
    //debugPrint('[AnnouncementCarousel] 强制恢复轮播组件...');

    try {
      // 清理所有定时器
      _pauseAllTimers();

      // 重置状态
      _isMidCarouselPaused = false;
      _currentNoticeIndex = 0;
      _currentNoticeStartTime = null;
      _noticeElapsedTime = Duration.zero;
      _currentNoticePauseTime = null;

      // 重新创建基本内容
      _ensureBasicContent();

      // 使用 WidgetsBinding.instance.addPostFrameCallback 延迟通知
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (hasListeners) {
          notifyListeners();
        }
      });

      //debugPrint('[AnnouncementCarousel] 强制恢复完成');
    } catch (e) {
      // debugPrint('[AnnouncementCarousel]  强制恢复失败: $e');
    }
  }

  ///20，确保widget和我的数据同步(通告,主屏幕,管理费用表單,其他费用表單)
  void _ensureBasicContent() {
    try {
      //debugPrint('[AnnouncementCarousel]  確保基本輪播內容可用（包括無通告的情況）...');

      // 如果正在初始化过程中，避免递归调用
      if (_isInitializing) {
        //debugPrint('[AnnouncementCarousel]  初始化过程中，跳过基本内容恢复');
        return;
      }

      //debugPrint('[AnnouncementCarousel]  強制觸發智能更新以確保基本內容');
      _smartUpdateCarousel(_carouselAnnouncements);

      // 智能更新已經處理了所有必要的內容，直接返回
      //debugPrint('[AnnouncementCarousel]  基本内容确保完成');
      return;
    } catch (e) {
      // debugPrint('[AnnouncementCarousel]  确保基本内容失败: $e');
    }
  }

  ///21，诊断轮播组件问题
  void diagnoseCarouselIssues() {
    //debugPrint('[AnnouncementCarousel] === 轮播组件诊断开始 ===');
    //debugPrint('[AnnouncementCarousel] 状态: $carouselStatus');
    //debugPrint('[AnnouncementCarousel] 是否健康: $isCarouselHealthy');
    //debugPrint('[AnnouncementCarousel] 缓存Widget数量: ${_widgetCache.length}');
    // debugPrint(
    //     '[AnnouncementCarousel] 缓存FileManager数量: ${_fileManagerCache.length}');
    //debugPrint('[AnnouncementCarousel] 通告数量: ${_carouselAnnouncements.length}');
    // debugPrint(
    //     '[AnnouncementCarousel] 轮播组件Widget总数: ${_midCarouselController.widgetCount}');
    //debugPrint('[AnnouncementCarousel] 轮播模式: $carouselModeInfo');
    //debugPrint('[AnnouncementCarousel] 支持无通告模式: $supportsNoAnnouncementMode');

    // 診斷：基於時間的輪播狀態
    //debugPrint('[AnnouncementCarousel] 當前索引: $_currentNoticeIndex');
    // debugPrint(
    //     '[AnnouncementCarousel] 已播放時間: ${_noticeElapsedTime.inSeconds}s');
    //debugPrint('[AnnouncementCarousel] 總時長: ${_noticeDuration.inSeconds}s');
    //debugPrint('[AnnouncementCarousel] 當前開始時間: $_currentNoticeStartTime');
    //debugPrint('[AnnouncementCarousel] 暫停時間: $_currentNoticePauseTime');

    //debugPrint('[AnnouncementCarousel] === 轮播组件诊断结束 ===');
  }

  ///22，检查轮播组件是否支持无通告模式
  bool get supportsNoAnnouncementMode {
    // 修复：确保至少要有主屏幕+占位符+缴费表單才能支持无通告模式
    return _midCarouselController.widgetCount >= 3;
  }

  ///23，获取轮播模式信息
  String get carouselModeInfo {
    if (_carouselAnnouncements.isNotEmpty) {
      return '通告轮播模式 - ${_carouselAnnouncements.length} 个通告';
    } else if (_midCarouselController.widgetCount >= 3) {
      return '缴费表單轮播模式 - 无通告数据，显示缴费表單';
    } else {
      return '基本模式 - 仅显示主屏幕';
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

    super.dispose(); // 调用父类的dispose方法

    // 清理所有緩存
    _widgetCache.clear();
    _fileManagerCache.clear();
    _announcementSignatures.clear();
  }
}

@visibleForTesting
String debugAnnouncementCarouselSignature(AnnouncementModel announcement) {
  return _announcementSignature(announcement);
}

String _announcementSignature(AnnouncementModel announcement) {
  final file = announcement.file;
  return [
    announcement.id,
    announcement.updatedAt.toIso8601String(),
    announcement.title,
    announcement.description,
    announcement.apiType,
    announcement.isPublic,
    announcement.isIsmartNotice,
    announcement.priority,
    announcement.status,
    announcement.startTime.toIso8601String(),
    announcement.endTime.toIso8601String(),
    announcement.fileId,
    announcement.fileType,
    file.id,
    file.mimeType,
    file.md5,
    file.url,
    file.fileSize,
    file.localFilePath ?? '',
  ].join('\u001f');
}

@visibleForTesting
class AnnouncementCarouselIndexPolicy {
  static int nextIndex({
    required int currentIndex,
    required int announcementCount,
    required bool hasOtherTable,
    required bool hasManagementTable,
    required int firstArrearTableIndex,
    required int otherTableIndex,
    required int managementTableIndex,
  }) {
    final hasAnnouncements = announcementCount > 0;
    if (hasAnnouncements) {
      const announcementStartIndex = 2;
      final announcementEndIndex = 1 + announcementCount;
      final isInAnnouncements = currentIndex >= announcementStartIndex &&
          currentIndex <= announcementEndIndex;
      final isInArrearTables = _isArrearIndex(
        currentIndex: currentIndex,
        announcementCount: announcementCount,
        hasOtherTable: hasOtherTable,
        hasManagementTable: hasManagementTable,
      );

      if (isInArrearTables) {
        return announcementStartIndex;
      }

      if (!isInAnnouncements) {
        return announcementStartIndex;
      }

      final nextAnnouncementIndex = currentIndex + 1;
      if (nextAnnouncementIndex <= announcementEndIndex) {
        return nextAnnouncementIndex;
      }

      return firstArrearTableIndex != -1
          ? firstArrearTableIndex
          : announcementStartIndex;
    }

    if (hasOtherTable && hasManagementTable) {
      if (currentIndex == otherTableIndex) {
        return managementTableIndex != -1 ? managementTableIndex : currentIndex;
      }
      if (currentIndex == managementTableIndex) {
        return otherTableIndex != -1 ? otherTableIndex : currentIndex;
      }
      return firstArrearTableIndex != -1 ? firstArrearTableIndex : currentIndex;
    }

    if (hasManagementTable) {
      return currentIndex;
    }

    if (hasOtherTable) {
      return otherTableIndex != -1 ? otherTableIndex : currentIndex;
    }

    return 0;
  }

  static bool _isArrearIndex({
    required int currentIndex,
    required int announcementCount,
    required bool hasOtherTable,
    required bool hasManagementTable,
  }) {
    final arrearStartIndex = 2 + announcementCount;
    var arrearEndIndex = arrearStartIndex - 1;
    if (hasOtherTable) {
      arrearEndIndex++;
    }
    if (hasManagementTable) {
      arrearEndIndex++;
    }
    return currentIndex >= arrearStartIndex && currentIndex <= arrearEndIndex;
  }
}

@visibleForTesting
class AnnouncementCarouselExitPolicy {
  static int resolveTargetIndex({
    required int? requestedTargetIndex,
    required int? savedCarouselIndex,
    required int widgetCount,
    required int initialCarouselIndex,
  }) {
    if (_isValidIndex(requestedTargetIndex, widgetCount)) {
      return requestedTargetIndex!;
    }

    if (_isValidContentIndex(savedCarouselIndex, widgetCount)) {
      return savedCarouselIndex!;
    }

    if (_isValidIndex(initialCarouselIndex, widgetCount)) {
      return initialCarouselIndex < 2 && widgetCount > 2
          ? 2
          : initialCarouselIndex;
    }

    return widgetCount > 2 ? 2 : 0;
  }

  static bool _isValidIndex(int? index, int widgetCount) {
    return index != null && index >= 0 && index < widgetCount;
  }

  static bool _isValidContentIndex(int? index, int widgetCount) {
    return index != null && index >= 2 && index < widgetCount;
  }
}
