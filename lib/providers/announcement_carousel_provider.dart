import 'dart:async';
import 'package:flutter/material.dart';
import 'package:iboard_app/managers/file_manager.dart';
import 'package:iboard_app/models/announcement_model.dart';
import 'package:iboard_app/widgets/carousel_widget.dart' as custom_carousel;
import 'package:iboard_app/widgets/mainscreen/main_display/announcement_reader_widget.dart';
import 'package:iboard_app/widgets/mainscreen/main_display/mainscreen_widget.dart';
import 'package:iboard_app/widgets/mainscreen/main_display/arrear_manage_table_widget.dart';
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
  // bool _isShowingArrearQue
  bool _isShowingArrearTable = false;

  // 时间记录相关 - 用于全屏广告暂停恢复
  DateTime? _currentNoticeStartTime; // 当前通告开始时间
  DateTime? _currentNoticePauseTime; // 当前通告暂停时间
  Duration _noticeElapsedTime = Duration.zero; // 通告已播放时间
  Duration _noticeDuration = const Duration(seconds: 5); // 通告总时长
  int _currentNoticeIndex = 0; // 当前通告索引

  // 無影片場景：不再追蹤視頻播放進度，只依賴時間邏輯

  // AppDataProvider引用 - 用于获取动态设置
  late AppDataProvider _appDataProvider; // AppDataProvider引用
  late VoidCallback _homeButtonCallback = () {
    // 默认的安全回调，避免应用崩溃
    debugPrint('[AnnouncementCarousel] ⚠️ 使用默认回调，可能还未设置正确的回调');
    // 尝试跳转到主屏幕（如果轮播组件已初始化）
    try {
      if (_midCarouselController.widgetCount > 0) {
        jumpToAnnouncementIndex(0);
      }
    } catch (e) {
      debugPrint('[AnnouncementCarousel] ❌ 默认回调执行失败: $e');
    }
  };

  late ArrearProvider? _arrearProvider;

  // 新增：跟踪当前费用表單的轮播状态
  bool _isOtherTablePaginationActive = false; // 其他费用表單是否在翻頁中
  bool _isManagementTablePaginationActive = false; // 管理费用表單是否在翻頁中

  // 緩存Widget實例和FileManager - 优化内存管理
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

  /// 获取轮播组件状态信息
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

  /// 检查轮播组件健康状态
  bool get isCarouselHealthy {
    try {
      // 确保即使没有通告也能正常工作（至少要有主屏幕和缴费表單）
      return _midCarouselController.widgetCount >= 2 &&
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

    debugPrint(
        '[AnnouncementCarousel] 🔍 检查轮播内容: widgetCount=$widgetCount, 通告=$hasAnnouncements, 管理费用=$hasManagementData, 其他费用=$hasOtherData');

    // 至少需要主屏幕 + 任意一种内容（通告或费用表格）
    return widgetCount >= 2 &&
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

  ///1.1，设置返回主屏幕按钮回调（新增方法）
  void setHomeButtonCallback(VoidCallback homeButtonCallback) {
    _homeButtonCallback = homeButtonCallback;

    // 🔧 修复：回调设置后，清除缓存的Widget以强制重新创建，确保使用新的回调
    _clearWidgetCacheForHomeButton();

    debugPrint('[AnnouncementCarousel] 🏠 已设置主屏幕按钮回调并清除相关缓存');
  }

  ///1.1a，清除涉及返回按钮的Widget缓存（私有辅助方法）
  void _clearWidgetCacheForHomeButton() {
    // 清除主屏幕Widget缓存，强制重新创建以使用新回调
    _widgetCache.removeWhere((key, value) => key == 'main_screen');

    // 清除费用表格Widget缓存，强制重新创建以使用新回调
    _widgetCache.removeWhere((key, value) =>
        key.startsWith('management_fee_table_') ||
        key.startsWith('other_fee_table_'));

    debugPrint('[AnnouncementCarousel] 🔄 已清除返回按钮相关Widget缓存');
  }

  ///1，更新轮播通告列表（由AnnouncementProvider调用）
  void updateCarouselList(List<AnnouncementModel> newCarouselAnnouncements) {
    try {
      debugPrint(
          '[AnnouncementCarousel] 🔔 收到更新請求：傳入通告數=${newCarouselAnnouncements.length}');
    } catch (_) {}
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
      try {
        debugPrint('[AnnouncementCarousel] ℹ️ 資料無變更（通告未變且欠費無待更新），跳過重建');
      } catch (_) {}
      return;
    }

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
      _widgetCache[mainScreenKey] = Container(
        child: const Center(
          child: Text('主屏幕載入中...', style: TextStyle(fontSize: 18)),
        ),
      );
      widgetMap[mainScreenKey] = _widgetCache[mainScreenKey]!;
      orderedKeys.add(mainScreenKey);
      usedKeys.add(mainScreenKey);
    }

    // 2.6 通告 widgets（優先放在表單之前，滿足：通告們 → 其他 → 管理）
    for (final announcement in _carouselAnnouncements) {
      final key = 'announcement_${announcement.id}';

      if (!_widgetCache.containsKey(key) ||
          _hasAnnouncementChanged(key, announcement)) {
        try {
          if (!_fileManagerCache.containsKey(key)) {
            _fileManagerCache[key] = FileManager();
          }
          final fileManager = _fileManagerCache[key]!;
          fileManager.getFile(announcement.file);

          _widgetCache[key] = Center(
            child: AnnouncementReaderWidget(
              key: ValueKey(key),
              announcement: announcement,
              fileManager: fileManager,
              onHomeButtonPressed: _homeButtonCallback,
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
      _widgetCache[arrearTableKey] = Container(
        child: const Center(
          child: Text('其他費用數據暫不可用', style: TextStyle(fontSize: 18)),
        ),
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
      _widgetCache[mgmtTableKey] = Container(
        child: const Center(
          child: Text('繳費數據暫不可用', style: TextStyle(fontSize: 18)),
        ),
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

    // 2.11 確保在沒有通告時也掛載繳費表單
    if (_carouselAnnouncements.isEmpty && widgetMap.length < 2) {
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
            _widgetCache[arrearTableKey] = Container(
              child: const Center(
                child: Text('欠費數據載入中...', style: TextStyle(fontSize: 18)),
              ),
            );
          }

          widgetMap[arrearTableKey] = _widgetCache[arrearTableKey]!;
          orderedKeys.add(arrearTableKey);
        } catch (e) {}
      }
    }

    // 2.12 使用智能更新，保持当前查看的内容不变
    _midCarouselController.smartUpdateCarousel(widgetMap, orderedKeys);

    // 2.13 確保輪播有內容並校正當前索引
    if (_midCarouselController.widgetCount > 0) {
      // 智能确定初始索引
      int initialIndex = _determineInitialCarouselIndex();

      if (_currentNoticeIndex >= _midCarouselController.widgetCount ||
          _currentNoticeIndex <= 0) {
        _currentNoticeIndex = initialIndex; // 校正到合适的初始索引
        debugPrint('[AnnouncementCarousel] 📍 校正初始索引到: $_currentNoticeIndex');
      }

      // 確保跳轉到正確的索引
      _midCarouselController.jumpToIndex(_currentNoticeIndex);
      debugPrint('[AnnouncementCarousel] 🎯 初始化完成，跳转到索引: $_currentNoticeIndex');
    } else {
      debugPrint('[AnnouncementCarousel] ⚠️ 没有轮播内容');
    }

    notifyListeners();
  }

  ///2f，确定初始轮播索引
  int _determineInitialCarouselIndex() {
    final bool hasAnnouncements = _carouselAnnouncements.isNotEmpty;
    final bool hasOtherData = _arrearProvider?.hasAnyOtherFeeRecords == true;
    final bool hasManagementData =
        _arrearProvider?.hasManagementFeeData == true;

    debugPrint(
        '[AnnouncementCarousel] 🎯 确定初始索引: 通告=$hasAnnouncements, 其他费用=$hasOtherData, 管理费用=$hasManagementData');

    if (hasAnnouncements) {
      // 有通告的情况，从第一个通告开始
      debugPrint('[AnnouncementCarousel] 📢 从第一个通告开始: 索引1');
      return 1;
    } else if (hasOtherData && hasManagementData) {
      // 无通告但有两种费用表單，从其他费用表單开始
      final otherIndex = _getFirstArrearTableIndex();
      debugPrint('[AnnouncementCarousel] 📊 双表模式，从其他费用表單开始: 索引$otherIndex');
      return otherIndex != -1 ? otherIndex : 1;
    } else if (hasManagementData) {
      // 只有管理费用表單，从管理费用表單开始
      final mgmtIndex = _findManagementTableIndex();
      debugPrint('[AnnouncementCarousel] 📊 只有管理费用表單，从管理表單开始: 索引$mgmtIndex');
      return mgmtIndex != -1 ? mgmtIndex : 1;
    } else {
      // 没有任何内容，从主屏幕开始
      debugPrint('[AnnouncementCarousel] 🏠 没有轮播内容，从主屏幕开始: 索引0');
      return 0;
    }
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
      // 保存主頁回调
      _homeButtonCallback = onHomeButtonPressed;
      _noticeDuration = Duration(seconds: apiNoticeStayDuration);
      // 重置暫停相關的狀態，確保初始化時狀態乾淨
      _currentNoticePauseTime = null;
      _noticeElapsedTime = Duration.zero;

      _midTimer?.cancel();
      _delayedNoticeTimer?.cancel();
      _ensureBasicContent();

      // 智能启动轮播 - 费用表格无需延时，通告才需要延时
      if (!_isMidCarouselPaused) {
        final bool hasAnnouncements = carouselAnnouncements.isNotEmpty;

        if (hasAnnouncements) {
          // 有通告时，使用正常延时后开始通告轮播
          debugPrint(
              '[AnnouncementCarousel] 🚀 有通告，延时${delayBeforeNotice}秒后开始轮播');
          _delayedNoticeTimer = Timer(Duration(seconds: delayBeforeNotice), () {
            if (!_isMidCarouselPaused) {
              _startCarouselFromAnnouncements(apiNoticeStayDuration);
            }
          });
        } else {
          // 无通告时，立即开始费用表格轮播（无延时）
          debugPrint('[AnnouncementCarousel] 🚀 无通告，立即开始费用表格轮播');
          _startCarouselFromFeeTables();
        }
      }
    } catch (e) {
      debugPrint('[AnnouncementCarousel] ❌ 初始化失败: $e');
    }
  }

  ///3.1，从通告开始轮播
  void _startCarouselFromAnnouncements(int apiNoticeStayDuration) {
    try {
      _currentNoticeStartTime = DateTime.now();
      _currentNoticeIndex = 1; // 从第一个通告开始

      // 确保索引在有效范围内
      if (_currentNoticeIndex >= _midCarouselController.widgetCount) {
        _currentNoticeIndex = _midCarouselController.widgetCount > 1 ? 1 : 0;
      }

      debugPrint(
          '[AnnouncementCarousel] 🎯 从通告开始轮播，跳转到索引: $_currentNoticeIndex');
      _midCarouselController.jumpToIndex(_currentNoticeIndex);
      _scheduleNextCarousel(apiNoticeStayDuration);
    } catch (e) {
      debugPrint('[AnnouncementCarousel] ❌ 通告轮播启动失败: $e');
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

      debugPrint(
          '[AnnouncementCarousel] 🎯 从费用表格开始轮播，跳转到索引: $_currentNoticeIndex');
      _midCarouselController.jumpToIndex(_currentNoticeIndex);

      // 费用表格不需要定时切换，它们通过翻頁完成自动切换
      // 所以这里不调用 _scheduleNextCarousel
      debugPrint('[AnnouncementCarousel] 📊 费用表格轮播已启动，等待翻頁完成触发切换');
    } catch (e) {
      debugPrint('[AnnouncementCarousel] ❌ 费用表格轮播启动失败: $e');
    }
  }

  ///2a，调度下一个轮播切换（智能定时器，自适应间隔减少系统调用）
  void _scheduleNextCarousel(int apiNoticeStayDuration) {
    try {
      _midTimer?.cancel();

      if (_isMidCarouselPaused) {
        return;
      }

      // 验证轮播组件状态
      if (!isCarouselHealthy) {
        _ensureBasicContent();
        return;
      }

      // 修复：确保即使没有通告也能轮播（至少要有主屏幕和缴费表單）
      final currentWidgetCount = _midCarouselController.widgetCount;
      if (currentWidgetCount < 2) {
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
        // 暂停状态，稍后重新检查
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

      // 3.3.1 內容範圍（不包含主屏）
      final int contentStart = 1;
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

        // 3.5.1 僅在內容索引範圍 [1..N] 之間循環（永不回到0）
        if (contentCount <= 1) {
          // 只有一個內容：交由表內自行處理
          _scheduleNextCarousel(apiNoticeStayDuration);
          return;
        }
        _currentNoticeIndex++;
        if (_currentNoticeIndex < contentStart ||
            _currentNoticeIndex > contentEnd) {
          _currentNoticeIndex = contentStart;
        }

        // 3.6 判斷是否切到欠費總覽頁（最後一頁）
        final isArrearTable = _currentNoticeIndex == contentEnd;

        // 3.7 跳轉到目標索引
        _midCarouselController.jumpToIndex(_currentNoticeIndex);

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

  ///4，恢复通告轮播
  void resumeMidCarousel(int apiNoticeStayDuration,
      {bool forceJumpToIndex = false}) {
    final widgetCount = _midCarouselController.widgetCount;
    debugPrint(
        '[AnnouncementCarousel] 🔄 恢复通告轮播 - Widget数量: $widgetCount, 是否暂停: $_isMidCarouselPaused');

    // 显式取消旧的定时器，避免重复启动
    _pauseAllTimers();

    // 设置轮播为运行状态
    _isMidCarouselPaused = false;

    // 恢复暂停状态
    _restorePauseState();

    // 恢复轮播中的媒體内容
    _midCarouselController.resumeAllMedia();

    // 恢復通告輪播 - 使用視頻播放進度而不是時間
    // 修复：即使只有管理费用表格（widgetCount = 2：主屏幕+管理费用）也要进入轮播模式
    if (_midCarouselController.widgetCount >= 2 && !_isMidCarouselPaused) {
      debugPrint(
          '[AnnouncementCarousel] ✅ 满足轮播条件，开始轮播 (widgetCount: ${_midCarouselController.widgetCount})');

      _noticeDuration = Duration(seconds: apiNoticeStayDuration); // 更新当前时长配置

      // 重要修復：不要重置開始時間，保持暫停前的時間狀態
      // 這樣可以從暫停位置繼續，而不是重新開始
      if (_currentNoticeStartTime == null) {
        _currentNoticeStartTime = DateTime.now();
      }

      // 只有在强制跳转时才确保当前索引在通告范围内
      if (forceJumpToIndex && _currentNoticeIndex < 1) {
        _currentNoticeIndex = 1; // 从第一个内容开始（通告或缴费表單）
        _midCarouselController.jumpToIndex(_currentNoticeIndex);
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
            // 检查当前是否在欠费总览頁面
            final isCurrentlyOnArrearTable =
                _currentNoticeIndex == (_midCarouselController.widgetCount - 1);

            if (isCurrentlyOnArrearTable) {
              // 如果当前在欠费总览頁面，不直接切换，让自动翻頁完成
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

        // 检查当前是否在欠费总览頁面（最后一个索引）
        final isCurrentlyOnArrearTable =
            _currentNoticeIndex == (_midCarouselController.widgetCount - 1);

        if (isCurrentlyOnArrearTable) {
          // 如果当前在欠费总览頁面，不直接切换，继续展示欠费总览

          // 重置开始时间，给欠费总览足够时间完成翻頁
          _currentNoticeStartTime = DateTime.now();

          // 不调用 _scheduleNextCarousel，让欠费总览的翻頁完成回调来处理切换
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
    } else {
      // 条件不满足的情况
      debugPrint(
          '[AnnouncementCarousel] ❌ 不满足轮播条件 - widgetCount: ${_midCarouselController.widgetCount}, 暂停状态: $_isMidCarouselPaused');

      // 即使不能轮播，也要确保当前显示正确的内容
      if (_midCarouselController.widgetCount >= 2 && _currentNoticeIndex < 1) {
        debugPrint('[AnnouncementCarousel] 🔧 修正当前索引到管理费用表格');
        _currentNoticeIndex = 1; // 跳转到第一个内容（管理费用表格）
        _midCarouselController.jumpToIndex(_currentNoticeIndex);
      }
    }

    notifyListeners();
  }

  /// 智能計算恢復後的剩餘時間（純時間版）
  Duration _calculateSmartRemainingTime(int apiNoticeStayDuration) {
    try {
      if (_currentNoticeStartTime != null && _currentNoticePauseTime != null) {
        final totalElapsed =
            _currentNoticePauseTime!.difference(_currentNoticeStartTime!);
        final remaining =
            Duration(seconds: apiNoticeStayDuration) - totalElapsed;
        if (remaining.inSeconds > 0) return remaining;
      }
      final remainingFromElapsed = _noticeDuration - _noticeElapsedTime;
      if (remainingFromElapsed.inSeconds > 0) return remainingFromElapsed;
    } catch (e) {}
    return Duration.zero;
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
    } catch (e) {}
  }

  /// 恢复暂停状态
  void _restorePauseState() {
    try {
      // 清除暂停时间记录，准备重新开始计时
      _currentNoticePauseTime = null;

      // 保持已播放时间不变，这样能正确计算剩余时间
    } catch (e) {}
  }

  /// 獲取當前通告組件（輔助方法）
  Widget? _getCurrentAnnouncementWidget() {
    try {
      if (_currentNoticeIndex >= 0 &&
          _currentNoticeIndex < _midCarouselController.widgetCount) {
        // 這裡需要通過輪播控制器獲取當前Widget
        // 由於技術限制，暫時返回null
        return null;
      }
    } catch (e) {}
    return null;
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

    // 修复：确保即使没有通告也能轮播（至少要有主屏幕和缴费表單）
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
    debugPrint('[AnnouncementCarousel] ⚙️ 通告轮播 - 暂停所有计时器（设置頁面）');
    _pauseAllTimers();
    _midCarouselController.pauseAllMedia();
    _isMidCarouselPaused = true;
    notifyListeners();
  }

  ///10，从设置頁面恢复所有计时器
  void resumeAllTimersFromSettings(int apiNoticeStayDuration) {
    debugPrint('[AnnouncementCarousel] ↩️ 通告轮播 - 从设置頁面恢复所有计时器');
    _isMidCarouselPaused = false;
    _midCarouselController.resumeAllMedia();

    // 恢复通告轮播
    // 修复：即使只有管理费用表格也要进入轮播模式
    if (_midCarouselController.widgetCount >= 2) {
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

  ///13a，显示管理費用表單界面（手动操作模式 - 不启用自动翻頁）
  void showArrearTableWidget(VoidCallback onHomeButtonPressed) {
    // 设置显示欠费总览状态
    _isShowingArrearTable = true;
    notifyListeners();
  }

  ///14，直接显示独立通告（不依赖轮播逻辑）
  void showIndependentAnnouncement(
      AnnouncementModel announcement, VoidCallback? onHomeButtonPressed) {
    // 创建独立通告显示頁面，直接根据通告的文件信息
    FileManager fileManager = FileManager();
    fileManager.getFile(announcement.file);

    Widget announcementWidget = Center(
      child: AnnouncementReaderWidget(
        announcement: announcement,
        fileManager: fileManager,
        onHomeButtonPressed: onHomeButtonPressed ??
            () {
              // 默认返回主頁行为：跳转到主屏幕
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

  ///16，创建管理費用表單輪播Widget（新增方法）
  Widget _createArrearTableCarouselWidget(VoidCallback onHomeButtonPressed) {
    debugPrint('[AnnouncementCarousel] 🏗️ 创建管理费用表單 Widget');

    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.grey.shade50,
      child: ArrearManagementTableWidget(
        isInCarouselMode: true, // 标记为轮播模式
        onHomeButtonPressed: () {
          // 点击主頁按钮时，跳转回主屏幕（索引0）
          jumpToAnnouncementIndex(0);
        },
        onPaginationComplete: (int totalPages) {
          debugPrint('[AnnouncementCarousel] 📊 管理费用表單翻頁完成，总頁数: $totalPages');

          // 标记分頁结束
          _isManagementTablePaginationActive = false;
          debugPrint('[AnnouncementCarousel] 🏁 管理费用表單分頁结束');

          // 然后切换到下一个通告
          _goToNextCarouselItem();
        },
        onPaginationStart: (int totalPages) {
          // 管理費用表單開始翻頁，動態延長當前通告停留時間，並標記分頁中
          _isManagementTablePaginationActive = true;
          debugPrint('[AnnouncementCarousel] 🚦 管理费用表單开始翻頁，总頁数: $totalPages');
          _extendCurrentNoticeStayTime(totalPages);
        },
      ),
    );
  }

  ///17，动态延长当前通告停留时间（管理費用表單開始翻頁時調用）
  void _extendCurrentNoticeStayTime(int totalPages) {
    // 该方法现在主要用于动态延长轮播时间
    debugPrint('[AnnouncementCarousel] 🕒 延长停留时间，总頁数: $totalPages');

    // 计算需要延长的时间：从设置中获取每頁翻頁时间，默认为5秒
    final deviceSettings = _appDataProvider.deviceSettings;
    final durationPerPage = deviceSettings?.paymentTableOnePageDuration;
    final paginationDuration =
        (durationPerPage != null && durationPerPage > 0) ? durationPerPage : 5;

    final int extensionSeconds = totalPages * paginationDuration;

    // 取消现有的定时器，避免冲突
    _midTimer?.cancel();

    // 重新设置开始时间，相当于重新开始计时
    _currentNoticeStartTime = DateTime.now();

    // 使用延长后的时间重新调度轮播
    final extendedDuration = _noticeDuration.inSeconds + extensionSeconds;

    debugPrint(
        '[AnnouncementCarousel] 费用表單翻頁开始，延长停留时间: ${extensionSeconds}秒，总时长: ${extendedDuration}秒');

    // 使用延长后的时间调度下一次轮播
    _scheduleNextCarousel(extendedDuration);
  }

  ///17.1，其他费用表單翻頁完成处理
  void _onOtherTablePaginationComplete() {
    debugPrint('[AnnouncementCarousel] 📊 其他费用表單翻頁完成');

    // 检查当前轮播模式
    final bool hasAnnouncements = _carouselAnnouncements.isNotEmpty;
    final bool hasManagementData =
        _arrearProvider?.hasManagementFeeData == true;

    debugPrint(
        '[AnnouncementCarousel] 📊 当前数据状态: 通告=$hasAnnouncements, 管理费用=$hasManagementData');

    if (hasManagementData) {
      // 如果有管理费用数据，跳转到管理费用表單
      debugPrint('[AnnouncementCarousel] 🔄 跳转到管理费用表單');
      _jumpToManagementTable();
    } else if (hasAnnouncements) {
      // 如果没有管理费用数据但有通告，跳转到通告
      debugPrint('[AnnouncementCarousel] 🔄 跳转到通告');
      _goToNextCarouselItem();
    } else {
      // 这种情况不应该出现，但为了安全起见
      debugPrint('[AnnouncementCarousel] ⚠️ 异常状态：其他费用表單完成但没有后续内容');
    }
  }

  ///17.2，管理费用表單翻頁完成处理
  void _onManagementTablePaginationComplete() {
    debugPrint('[AnnouncementCarousel] 📊 管理费用表單翻頁完成');

    // 检查当前轮播模式
    final bool hasAnnouncements = _carouselAnnouncements.isNotEmpty;
    final bool hasOtherData = _arrearProvider?.hasAnyOtherFeeRecords == true;
    final bool hasManagementData =
        _arrearProvider?.hasManagementFeeData == true;

    debugPrint(
        '[AnnouncementCarousel] 📊 当前数据状态: 通告=$hasAnnouncements, 其他费用=$hasOtherData, 管理费用=$hasManagementData');

    if (!hasAnnouncements && !hasOtherData && hasManagementData) {
      // 情况4：只有管理费用表單，应该在表單内部循环，不切换轮播
      debugPrint('[AnnouncementCarousel] 🔄 只有管理费用表單模式，不切换轮播');
      return;
    } else if (!hasAnnouncements && hasOtherData && hasManagementData) {
      // 情况3：无通告+两种table，跳转到其他费用表單
      debugPrint('[AnnouncementCarousel] 🔄 无通告双表模式，跳转到其他费用表單');
      _jumpToOtherTable();
    } else if (hasAnnouncements) {
      // 情况1和2：有通告的情况，跳转到通告
      debugPrint('[AnnouncementCarousel] 🔄 有通告模式，跳转到通告');
      _goToNextCarouselItem();
    } else {
      // 其他异常情况
      debugPrint('[AnnouncementCarousel] ⚠️ 未知的轮播状态');
      _goToNextCarouselItem();
    }
  }

  ///17.3.1，跳转到其他费用表單
  void _jumpToOtherTable() {
    debugPrint('[AnnouncementCarousel] 🔄 跳转到其他费用表單');

    try {
      // 查找其他费用表單的索引
      final otherTableIndex = _findOtherTableIndex();

      if (otherTableIndex != -1) {
        _currentNoticeIndex = otherTableIndex;
        _midCarouselController.jumpToIndex(_currentNoticeIndex);

        debugPrint(
            '[AnnouncementCarousel] ✅ 已跳转到其他费用表單，索引: $_currentNoticeIndex');

        // 重置开始时间
        _currentNoticeStartTime = DateTime.now();
      } else {
        debugPrint('[AnnouncementCarousel] ⚠️ 未找到其他费用表單，保持当前状态');
        // 如果找不到其他费用表單，可能数据有问题，保持当前状态
      }
    } catch (e) {
      debugPrint('[AnnouncementCarousel] ❌ 跳转到其他费用表單失败: $e');
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
        debugPrint('[AnnouncementCarousel] ⚠️ 其他费用表單不存在');
        return -1;
      }

      final otherKey = otherKeys.first;
      debugPrint('[AnnouncementCarousel] 🔍 查找其他费用表單key: $otherKey');

      // 计算其他费用表單的索引：主屏幕(0) → 通告们 → 其他费用表
      int index = 1; // 从索引1开始（跳过主屏幕）

      // 跳过通告
      index += _carouselAnnouncements.length;

      // 现在index应该指向其他费用表單
      debugPrint('[AnnouncementCarousel] 🎯 计算出的其他费用表單索引: $index');

      // 验证索引是否在有效范围内
      if (index < _midCarouselController.widgetCount) {
        return index;
      } else {
        debugPrint(
            '[AnnouncementCarousel] ❌ 计算的索引超出范围: $index >= ${_midCarouselController.widgetCount}');
        return -1;
      }
    } catch (e) {
      debugPrint('[AnnouncementCarousel] ❌ 查找其他费用表單索引失败: $e');
      return -1;
    }
  }

  ///17.3，跳转到管理费用表單
  void _jumpToManagementTable() {
    debugPrint('[AnnouncementCarousel] 🔄 跳转到管理费用表單');

    try {
      // 查找管理费用表單的索引
      final managementTableIndex = _findManagementTableIndex();

      if (managementTableIndex != -1) {
        _currentNoticeIndex = managementTableIndex;
        _midCarouselController.jumpToIndex(_currentNoticeIndex);

        debugPrint(
            '[AnnouncementCarousel] ✅ 已跳转到管理费用表單，索引: $_currentNoticeIndex');

        // 重置开始时间
        _currentNoticeStartTime = DateTime.now();
      } else {
        debugPrint('[AnnouncementCarousel] ⚠️ 未找到管理费用表單，跳转到通告');
        _goToNextCarouselItem();
      }
    } catch (e) {
      debugPrint('[AnnouncementCarousel] ❌ 跳转到管理费用表單失败: $e');
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
        debugPrint('[AnnouncementCarousel] ⚠️ 管理费用表單不存在');
        return -1;
      }

      final managementKey = managementKeys.first;
      debugPrint('[AnnouncementCarousel] 🔍 查找管理费用表單key: $managementKey');

      // 在轮播控制器中查找该key对应的索引
      // 这里需要根据实际的轮播组件顺序来确定索引
      // 由于我们知道顺序是：主屏幕(0) → 通告们 → 其他费用表 → 管理费用表
      int index = 1; // 从索引1开始（跳过主屏幕）

      // 跳过通告
      index += _carouselAnnouncements.length;

      // 跳过其他费用表（如果存在）
      final hasOtherData = _arrearProvider?.hasAnyOtherFeeRecords == true;
      if (hasOtherData) {
        index += 1;
      }

      // 现在index应该指向管理费用表單
      debugPrint('[AnnouncementCarousel] 🎯 计算出的管理费用表單索引: $index');

      // 验证索引是否在有效范围内
      if (index < _midCarouselController.widgetCount) {
        return index;
      } else {
        debugPrint(
            '[AnnouncementCarousel] ❌ 计算的索引超出范围: $index >= ${_midCarouselController.widgetCount}');
        return -1;
      }
    } catch (e) {
      debugPrint('[AnnouncementCarousel] ❌ 查找管理费用表單索引失败: $e');
      return -1;
    }
  }

  ///17.5，确定下一个轮播索引
  int _determineNextCarouselIndex() {
    debugPrint(
        '[AnnouncementCarousel] 🔍 确定下一个轮播索引，当前索引: $_currentNoticeIndex');

    final bool hasAnnouncements = _carouselAnnouncements.isNotEmpty;
    final bool hasOtherData = _arrearProvider?.hasAnyOtherFeeRecords == true;
    final bool hasManagementData =
        _arrearProvider?.hasManagementFeeData == true;

    debugPrint(
        '[AnnouncementCarousel] 📊 数据状态: 通告=$hasAnnouncements, 其他费用=$hasOtherData, 管理费用=$hasManagementData');

    // 情况1：有通告的各种组合
    if (hasAnnouncements) {
      // 确定通告的开始索引：主屏幕(0) + 通告们
      final int announcementStartIndex = 1;
      final int announcementEndIndex = _carouselAnnouncements.length;

      // 如果当前在费用表單，跳转到第一个通告
      if (_isCurrentIndexInArrearTables()) {
        debugPrint(
            '[AnnouncementCarousel] 📊 当前在费用表單，跳转到第一个通告: $announcementStartIndex');
        return announcementStartIndex;
      }

      // 如果当前在通告中，循环到下一个通告
      if (_currentNoticeIndex >= announcementStartIndex &&
          _currentNoticeIndex <= announcementEndIndex) {
        int nextIndex = _currentNoticeIndex + 1;
        if (nextIndex > announcementEndIndex) {
          // 通告循环结束，跳转到费用表單（如果有）
          final nextArrearIndex = _getFirstArrearTableIndex();
          if (nextArrearIndex != -1) {
            debugPrint(
                '[AnnouncementCarousel] 📢 通告循环完成，跳转到费用表單: $nextArrearIndex');
            return nextArrearIndex;
          } else {
            // 没有费用表單，回到第一个通告
            debugPrint(
                '[AnnouncementCarousel] 📢 通告循环完成，回到第一个通告: $announcementStartIndex');
            return announcementStartIndex;
          }
        } else {
          debugPrint('[AnnouncementCarousel] 📢 跳转到下一个通告: $nextIndex');
          return nextIndex;
        }
      }

      // 默认跳转到第一个通告
      debugPrint(
          '[AnnouncementCarousel] 🎯 默认跳转到第一个通告: $announcementStartIndex');
      return announcementStartIndex;
    }

    // 情况2：无通告，只有费用表單
    else {
      // 无通告的情况下，在费用表單之间循环
      if (hasOtherData && hasManagementData) {
        // 双表模式：其他费用 ↔ 管理费用
        if (_isCurrentIndexOtherTable()) {
          // 当前在其他费用表單，应该已经通过回调跳转到管理费用表單
          // 这里不应该被调用，但为了安全返回管理费用表單索引
          final mgmtIndex = _findManagementTableIndex();
          debugPrint('[AnnouncementCarousel] 🔄 双表模式，从其他表單跳转到管理表單: $mgmtIndex');
          return mgmtIndex != -1 ? mgmtIndex : 1;
        } else if (_isCurrentIndexManagementTable()) {
          // 当前在管理费用表單，应该已经通过回调跳转到其他费用表單
          // 这里不应该被调用，但为了安全返回其他费用表單索引
          final otherIndex = _findOtherTableIndex();
          debugPrint(
              '[AnnouncementCarousel] 🔄 双表模式，从管理表單跳转到其他表單: $otherIndex');
          return otherIndex != -1 ? otherIndex : 1;
        } else {
          // 不在任何费用表單，跳转到第一个费用表單（其他费用）
          final firstArrearIndex = _getFirstArrearTableIndex();
          debugPrint('[AnnouncementCarousel] 🎯 跳转到第一个费用表單: $firstArrearIndex');
          return firstArrearIndex != -1 ? firstArrearIndex : 1;
        }
      } else if (hasManagementData) {
        // 只有管理费用表單，应该由表單内部循环，这里不应该被调用
        debugPrint('[AnnouncementCarousel] ⚠️ 只有管理费用表單，不应该进入此方法');
        return _currentNoticeIndex; // 保持当前索引
      } else {
        // 没有任何费用数据，返回主屏幕
        debugPrint('[AnnouncementCarousel] ⚠️ 没有任何轮播内容，返回主屏幕');
        return 0;
      }
    }
  }

  ///17.6，检查当前索引是否在费用表單中
  bool _isCurrentIndexInArrearTables() {
    // 计算费用表單的索引范围
    int arrearStartIndex = 1 + _carouselAnnouncements.length; // 主屏幕 + 通告们

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
    debugPrint(
        '[AnnouncementCarousel] 🔍 检查是否在费用表單: 当前索引=$_currentNoticeIndex, 费用表單范围=[$arrearStartIndex, $arrearEndIndex], 结果=$isInArrear');

    return isInArrear;
  }

  ///17.6.1，检查当前索引是否在其他费用表單中
  bool _isCurrentIndexOtherTable() {
    final otherTableIndex = _findOtherTableIndex();
    bool isInOtherTable =
        otherTableIndex != -1 && _currentNoticeIndex == otherTableIndex;
    debugPrint(
        '[AnnouncementCarousel] 🔍 检查是否在其他费用表單: 当前索引=$_currentNoticeIndex, 其他表單索引=$otherTableIndex, 结果=$isInOtherTable');
    return isInOtherTable;
  }

  ///17.6.2，检查当前索引是否在管理费用表單中
  bool _isCurrentIndexManagementTable() {
    final managementTableIndex = _findManagementTableIndex();
    bool isInManagementTable = managementTableIndex != -1 &&
        _currentNoticeIndex == managementTableIndex;
    debugPrint(
        '[AnnouncementCarousel] 🔍 检查是否在管理费用表單: 当前索引=$_currentNoticeIndex, 管理表單索引=$managementTableIndex, 结果=$isInManagementTable');
    return isInManagementTable;
  }

  ///17.7，获取第一个费用表單的索引
  int _getFirstArrearTableIndex() {
    int arrearStartIndex = 1 + _carouselAnnouncements.length; // 主屏幕 + 通告们

    final bool hasOtherData = _arrearProvider?.hasAnyOtherFeeRecords == true;
    final bool hasManagementData =
        _arrearProvider?.hasManagementFeeData == true;

    if (hasOtherData) {
      debugPrint('[AnnouncementCarousel] 🎯 返回其他费用表單索引: $arrearStartIndex');
      return arrearStartIndex; // 其他费用表單在前
    } else if (hasManagementData) {
      debugPrint('[AnnouncementCarousel] 🎯 返回管理费用表單索引: $arrearStartIndex');
      return arrearStartIndex; // 只有管理费用表單
    }

    debugPrint('[AnnouncementCarousel] ⚠️ 没有费用表單数据');
    return -1; // 没有费用表單
  }

  ///18，切换到下一个轮播项（管理費用表單翻頁完成後調用）
  void _goToNextCarouselItem() {
    debugPrint('[AnnouncementCarousel] 🔍 进入 _goToNextCarouselItem 方法');
    debugPrint('[AnnouncementCarousel] 当前状态: '
        'isPaused=$_isMidCarouselPaused, '
        'isOtherTablePaginationActive=$_isOtherTablePaginationActive, '
        'isManagementTablePaginationActive=$_isManagementTablePaginationActive, '
        'onlyManagementTableMode=$_onlyManagementTableMode');

    if (_isMidCarouselPaused) {
      debugPrint('[AnnouncementCarousel] ⏸️ 轮播已暂停，跳过切换');
      return;
    }

    // 僅管理費用模式：不切換輪播，由表內自行首末頁循環
    if (_onlyManagementTableMode) {
      debugPrint('[AnnouncementCarousel] 🧭 僅管理費用模式，跳过切换');
      return;
    }

    // 如果任何费用表單仍在翻頁，则不进行轮播切换
    if (_isOtherTablePaginationActive || _isManagementTablePaginationActive) {
      debugPrint('[AnnouncementCarousel] 🔄 仍有费用表單在活跃翻頁，跳过切换');
      return;
    }

    try {
      debugPrint('[AnnouncementCarousel] 🔍 开始切换到下一个轮播项');
      debugPrint(
          '[AnnouncementCarousel] 当前索引: $_currentNoticeIndex, 总widget数: ${_midCarouselController.widgetCount}');
      debugPrint(
          '[AnnouncementCarousel] 轮播控制器状态: isAttached=${_midCarouselController.isAttached}, currentIndex=${_midCarouselController.currentIndex}');

      // 确定下一个目标索引 - 从费用表單跳转到通告
      int targetIndex = _determineNextCarouselIndex();

      if (targetIndex == -1) {
        debugPrint('[AnnouncementCarousel] ⚠️ 无法确定下一个轮播索引');
        return;
      }

      _currentNoticeIndex = targetIndex;
      debugPrint('[AnnouncementCarousel] 🎯 目标索引: $_currentNoticeIndex');

      _midCarouselController.jumpToIndex(_currentNoticeIndex);

      Future.delayed(const Duration(milliseconds: 100), () {
        final actualIndex = _midCarouselController.currentIndex;
        debugPrint(
            '[AnnouncementCarousel] ✅ 跳转完成，目标索引: $_currentNoticeIndex, 实际索引: $actualIndex');

        if (actualIndex != _currentNoticeIndex) {
          debugPrint('[AnnouncementCarousel] ⚠️ 跳转失败，强制重新跳转');
          _midCarouselController.jumpToIndex(_currentNoticeIndex);
        }
      });

      _currentNoticeStartTime = DateTime.now();

      debugPrint('[AnnouncementCarousel] 缴费表單翻頁完成，切换到索引: $_currentNoticeIndex');

      _scheduleNextCarousel(_noticeDuration.inSeconds);
    } catch (e) {
      debugPrint('[AnnouncementCarousel] ❌ 切换失败: $e');
      Future.delayed(const Duration(seconds: 2), () {
        if (!_isMidCarouselPaused) {
          _goToNextCarouselItem();
        }
      });
    }
  }

  ///19，强制恢复轮播组件
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

      // 重新创建基本内容
      _ensureBasicContent();

      // 使用 WidgetsBinding.instance.addPostFrameCallback 延迟通知
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (hasListeners) {
          notifyListeners();
        }
      });

      debugPrint('[AnnouncementCarousel] 强制恢复完成');
    } catch (e) {}
  }

  ///20，确保widget和我的数据同步(通告,主屏幕,管理费用表單,其他费用表單)
  void _ensureBasicContent() {
    try {
      debugPrint('[AnnouncementCarousel] 尝试恢复基本轮播内容...');
      // 0. 如果已有通告，直接走智能更新，通告與費用表格會一併處理
      if (_carouselAnnouncements.isNotEmpty) {
        _smartUpdateCarousel(_carouselAnnouncements);
        return;
      }

      // 1. 主屏幕（固定加入）- 如已有則復用
      const mainScreenKey = 'main_screen';
      if (!_widgetCache.containsKey(mainScreenKey)) {
        _widgetCache[mainScreenKey] =
            _createMainScreenWidget(_homeButtonCallback);
      }

      final Map<String, Widget> widgetMap = {
        mainScreenKey: _widgetCache[mainScreenKey]!,
      };
      final List<String> orderedKeys = [mainScreenKey];

      // 2. 明確按數據加入「其他費用表」
      try {
        final otherDataVersion =
            _arrearProvider?.currentDataVersion ?? 'default';
        final otherKey = 'other_fee_table_$otherDataVersion';
        final includeOther = _arrearProvider?.hasAnyOtherFeeRecords == true;

        if (includeOther) {
          if (_arrearProvider != null &&
              (!_widgetCache.containsKey(otherKey) ||
                  _arrearProvider?.hasPendingUpdate == true)) {
            _widgetCache[otherKey] =
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
                key.startsWith('other_fee_table_') && key != otherKey);
            _arrearProvider!.markUpdateApplied();
          }

          if (_widgetCache.containsKey(otherKey)) {
            widgetMap[otherKey] = _widgetCache[otherKey]!;
            orderedKeys.add(otherKey);
          }
        }
      } catch (_) {}

      // 3. 明確按數據加入「管理費用表」
      try {
        final mgmtDataVersion =
            _arrearProvider?.currentDataVersion ?? 'default';
        final mgmtKey = 'management_fee_table_$mgmtDataVersion';
        final includeMgmt = _arrearProvider?.hasManagementFeeData == true;

        if (includeMgmt) {
          if (_arrearProvider != null &&
              (!_widgetCache.containsKey(mgmtKey) ||
                  _arrearProvider?.hasPendingUpdate == true)) {
            _widgetCache[mgmtKey] =
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
                key.startsWith('management_fee_table_') && key != mgmtKey);
            _arrearProvider!.markUpdateApplied();
          }

          if (_widgetCache.containsKey(mgmtKey)) {
            widgetMap[mgmtKey] = _widgetCache[mgmtKey]!;
            orderedKeys.add(mgmtKey);
          }
        }
      } catch (_) {}

      // 4. 更新輪播
      _midCarouselController.smartUpdateCarousel(widgetMap, orderedKeys);

      // 5. 跳轉到主屏幕
      if (_midCarouselController.widgetCount > 0) {
        _currentNoticeIndex = 0;
        _midCarouselController.jumpToIndex(0);
        try {
          debugPrint(
              '[AnnouncementCarousel] 基本內容恢復完成：${_midCarouselController.widgetCount} widgets');
        } catch (_) {}
      }

      // 6. 通知
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (hasListeners) {
          notifyListeners();
        }
      });
    } catch (e) {}
  }

  ///21，诊断轮播组件问题
  void diagnoseCarouselIssues() {
    debugPrint('[AnnouncementCarousel] === 轮播组件诊断开始 ===');
    debugPrint('[AnnouncementCarousel] 状态: $carouselStatus');
    debugPrint('[AnnouncementCarousel] 是否健康: $isCarouselHealthy');
    debugPrint('[AnnouncementCarousel] 缓存Widget数量: ${_widgetCache.length}');
    debugPrint(
        '[AnnouncementCarousel] 缓存FileManager数量: ${_fileManagerCache.length}');
    debugPrint('[AnnouncementCarousel] 通告数量: ${_carouselAnnouncements.length}');
    debugPrint(
        '[AnnouncementCarousel] 轮播组件Widget总数: ${_midCarouselController.widgetCount}');
    debugPrint('[AnnouncementCarousel] 轮播模式: $carouselModeInfo');
    debugPrint('[AnnouncementCarousel] 支持无通告模式: $supportsNoAnnouncementMode');

    // 診斷：基於時間的輪播狀態
    debugPrint('[AnnouncementCarousel] 當前索引: $_currentNoticeIndex');
    debugPrint(
        '[AnnouncementCarousel] 已播放時間: ${_noticeElapsedTime.inSeconds}s');
    debugPrint('[AnnouncementCarousel] 總時長: ${_noticeDuration.inSeconds}s');
    debugPrint('[AnnouncementCarousel] 當前開始時間: $_currentNoticeStartTime');
    debugPrint('[AnnouncementCarousel] 暫停時間: $_currentNoticePauseTime');

    debugPrint('[AnnouncementCarousel] === 轮播组件诊断结束 ===');
  }

  ///22，检查轮播组件是否支持无通告模式
  bool get supportsNoAnnouncementMode {
    // 修复：确保至少要有主屏幕和缴费表單才能支持无通告模式
    return _midCarouselController.widgetCount >= 2;
  }

  ///23，获取轮播模式信息
  String get carouselModeInfo {
    if (_carouselAnnouncements.isNotEmpty) {
      return '通告轮播模式 - ${_carouselAnnouncements.length} 个通告';
    } else if (_midCarouselController.widgetCount >= 2) {
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
  }
}
