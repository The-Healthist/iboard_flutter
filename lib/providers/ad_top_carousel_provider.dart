import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:iboard_app/managers/file_manager.dart';
import 'package:iboard_app/models/ad_model.dart';
import 'package:iboard_app/widgets/carousel_widget.dart' as custom_carousel;
import 'package:iboard_app/widgets/mainscreen/ad_top_widget.dart';
import 'package:logger/logger.dart';

/// 頂部廣告輪播Provider
/// 負責管理頂部廣告的輪播邏輯、暫停恢復、定時器管理等
/// 輪播順序由後台管理，此Provider不再處理自定義順序
class TopAdCarouselProvider extends ChangeNotifier {
  final Logger _logger = Logger();
  bool _mounted = true;

  // 輪播控制器
  late custom_carousel.CarouselController _topCarouselController;

  // 定時器
  Timer? _topTimer;
  Timer? _debugTimer;

  // 廣告數據
  List<AdModel> _topAds = [];

  // Widget緩存機制
  final Map<String, Widget> _widgetCache = {};
  final Map<String, FileManager> _fileManagerCache = {};
  bool _pendingWidgetUpdate = false;

  // 狀態管理
  bool _isTopCarouselPaused = false;

  // 時間記錄相關 - 用於全屏廣告暫停恢復
  DateTime? _currentTopAdStartTime; // 當前頂部廣告開始時間
  DateTime? _currentTopAdPauseTime; // 當前頂部廣告暫停時間
  Duration _topAdElapsedTime = Duration.zero; // 頂部廣告已播放時間
  Duration _topAdDuration = const Duration(seconds: 15); // 頂部廣告總時長
  int _currentTopAdIndex = 0; // 當前頂部廣告索引

  // Getters
  custom_carousel.CarouselController get topCarouselController =>
      _topCarouselController;
  List<AdModel> get topAds => _topAds;
  bool get isTopCarouselPaused => _isTopCarouselPaused;
  Duration get topAdDuration => _topAdDuration;
  int get currentTopAdIndex => _currentTopAdIndex;
  DateTime? get currentTopAdStartTime => _currentTopAdStartTime;
  Duration get topAdElapsedTime => _topAdElapsedTime;

  TopAdCarouselProvider() {
    _topCarouselController = custom_carousel.CarouselController();
    _logger.i('🔍 TopAdCarouselProvider 初始化完成，輪播順序由後台管理');
  }

  ///1，更新輪播廣告列表（由AdvertisementProvider調用）
  void updateCarouselList(List<AdModel> newTopAds) {
    // 檢查數據是否真的發生了變化
    if (_areAdsListsEqual(_topAds, newTopAds)) {
      _logger.d('頂部廣告數據無變化，跳過更新');
      return;
    }

    _topAds = List<AdModel>.from(newTopAds);
    _logger.i('🔄 更新頂部廣告輪播列表: ${newTopAds.length} 個廣告');

    // 智能更新：如果正在播放，延遲更新Widget；如果是恢復操作，不更新Widget
    if (!_isTopCarouselPaused && _topTimer != null && _topTimer!.isActive) {
      _pendingWidgetUpdate = true;
      _logger.i('🎬 檢測到正在播放頂部廣告，延遲更新Widget直到下次切換');
    } else if (_widgetCache.isNotEmpty) {
      // 如果已有Widget緩存且處於暫停狀態，不重建Widget以保持播放狀態
      _logger.i('🔄 保持現有Widget緩存，避免重建');
    } else {
      _smartUpdateWidgets();
    }

    // 使用 WidgetsBinding.instance.addPostFrameCallback 延迟通知
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (hasListeners) {
        notifyListeners();
      }
    });
  }

  ///1a，檢查兩個廣告列表是否相等
  bool _areAdsListsEqual(List<AdModel> list1, List<AdModel> list2) {
    if (list1.length != list2.length) return false;
    for (int i = 0; i < list1.length; i++) {
      if (list1[i].id != list2[i].id) return false;
    }
    return true;
  }

  ///1b，檢查緩存狀態並驗證數據完整性
  bool validateCacheData() {
    if (_topAds.isEmpty) {
      _logger.w('⚠️ 頂部廣告數據為空');
      return false;
    }

    // 檢查每個廣告的文件是否有效
    for (final ad in _topAds) {
      if (ad.file.url.isEmpty) {
        _logger.w('⚠️ 發現無效的廣告文件: ${ad.title}');
        return false;
      }
    }

    _logger.i('✅ 緩存數據驗證通過: ${_topAds.length} 個廣告');
    return true;
  }

  ///2，清空輪播廣告列表
  void clearCarouselList() {
    _topAds.clear();
    notifyListeners();
  }

  ///3，初始化頂部輪播
  void initializeTopWidgets(List<AdModel> topAds) {
    if (topAds.isEmpty) {
      _logger.w('No top advertisements available');
      return;
    }

    // 使用自定義順序更新方法
    updateCarouselList(topAds);

    // 使用智能更新方法創建Widget - 只在首次初始化時創建
    if (_widgetCache.isEmpty) {
      _smartUpdateWidgets();
    }

    if (this.topAds.length > 1) {
      startTopAdTimer(0); // Start timer for the first ad
    }
  }

  ///3a，智能更新Widget（避免重建正在播放的Widget）
  void _smartUpdateWidgets() {
    if (topAds.isEmpty) {
      return;
    }

    final Map<String, Widget> widgetMap = {};
    final List<String> orderedKeys = [];
    final Set<String> usedKeys = {};
    final currentIndex = _topCarouselController.currentIndex;

    for (int i = 0; i < topAds.length; i++) {
      final ad = topAds[i];
      final key = 'top_ad_${ad.id}';
      usedKeys.add(key);
      orderedKeys.add(key);

      // 如果是當前播放的廣告且Widget已存在，保持不變
      if (i == currentIndex && _widgetCache.containsKey(key)) {
        widgetMap[key] = _widgetCache[key]!;
        _logger.d('🔄 保持當前播放廣告Widget: ${ad.title}');
      } else if (_widgetCache.containsKey(key)) {
        // 其他已緩存的Widget也保持不變
        widgetMap[key] = _widgetCache[key]!;
      } else {
        // 只為新廣告創建Widget
        final widget = _createCachedAdWidget(ad);
        _widgetCache[key] = widget;
        widgetMap[key] = widget;
        _logger.d('🆕 創建新廣告Widget: ${ad.title}');
      }
    }

    // 清理不再使用的緩存
    _widgetCache.removeWhere((key, value) => !usedKeys.contains(key));
    _fileManagerCache.removeWhere((key, value) => !usedKeys.contains(key));

    _topCarouselController.smartUpdateCarousel(widgetMap, orderedKeys);
  }

  ///3b，創建緩存的廣告Widget
  Widget _createCachedAdWidget(AdModel ad) {
    final key = 'top_ad_${ad.id}';

    // 重用或創建FileManager
    if (!_fileManagerCache.containsKey(key)) {
      _fileManagerCache[key] = FileManager();
    }
    final fileManager = _fileManagerCache[key]!;
    fileManager.getFile(ad.file);

    return SizedBox.expand(
      child: TopAdWidget(
        key: ValueKey(key),
        ad: ad,
        fileManager: fileManager,
      ),
    );
  }

  ///7，啟動頂部廣告計時器
  void startTopAdTimer(int currentIndex) {
    _topTimer?.cancel();
    if (topAds.length <= 1 ||
        currentIndex < 0 ||
        currentIndex >= topAds.length ||
        _isTopCarouselPaused) {
      return;
    }

    final ad = topAds[currentIndex];
    Duration timerDuration; // 計算實際需要的定時器時長

    // 重要修复：只有在没有开始时间或索引变化时才重置时间
    if (_currentTopAdStartTime == null || _currentTopAdIndex != currentIndex) {
      _currentTopAdStartTime = DateTime.now();
      _topAdDuration = ad.durationObject;
      _currentTopAdIndex = currentIndex;
      _topAdElapsedTime = Duration.zero;
      timerDuration = _topAdDuration; // 新廣告使用完整時長
    } else {
      // 如果是恢复状态，保持现有的时间设置
      _topAdDuration = ad.durationObject;
      _currentTopAdIndex = currentIndex;
      final remainingTime = _topAdDuration - _topAdElapsedTime;
      timerDuration = remainingTime.isNegative
          ? Duration.zero
          : remainingTime; // 恢復狀態使用剩餘時長
    }

    // 關鍵修復：使用計算出的定時器時長而不是廣告總時長
    _topTimer = Timer(timerDuration, () {
      if (_topCarouselController.widgetCount > 1 && !_isTopCarouselPaused) {
        // 在播放下一個廣告之前檢查是否有待處理的更新
        if (_pendingWidgetUpdate) {
          _logger.i('🔄 執行延遲的Widget更新');
          _smartUpdateWidgets();
          _pendingWidgetUpdate = false;
        }

        _topCarouselController.playNext();
        // onPageChanged will then call startTopAdTimer for the new page
      }
    });
  }

  /// 暫停頂部輪播
  void pauseTopCarousel() {
    // 记录当前播放时间
    _currentTopAdPauseTime = DateTime.now();

    // 计算已播放时间 - 修复时间累积问题
    if (_currentTopAdStartTime != null) {
      final rawElapsed =
          _currentTopAdPauseTime!.difference(_currentTopAdStartTime!);

      // 關鍵修復：確保時間累積正確，避免多次暫停恢復時時間計算錯誤
      _topAdElapsedTime = rawElapsed;

      // 确保已播放时间不超过广告总时长
      if (_topAdElapsedTime >= _topAdDuration) {
        _topAdElapsedTime = _topAdDuration;
      }

      // 添加額外的狀態一致性檢查
      if (_topAdElapsedTime > _topAdDuration) {
        _logger.w('⚠️ 異常：已播放時間超過廣告總時長');
        _topAdElapsedTime = _topAdDuration;
      }
    }

    // 設置頂部輪播為暫停狀態
    _isTopCarouselPaused = true;

    // 暫停定時器
    _topTimer?.cancel();

    // 暫停輪播中的媒體內容
    _topCarouselController.pauseAllMedia();

    // 直接切換到下一個廣告
    if (_topCarouselController.widgetCount > 1) {
      _topCarouselController.playNext();
    }

    // 使用 WidgetsBinding.instance.addPostFrameCallback 延迟通知
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (hasListeners) {
        notifyListeners();
      }
    });
  }

  /// 恢復頂部輪播
  void resumeTopCarousel() {
    _topTimer?.cancel(); // 顯式取消舊的定時器，避免重複計時或意外行為

    // 設置頂部輪播為運行狀態
    _isTopCarouselPaused = false;

    // 關鍵修復：不要重建Widget，直接恢復媒體播放
    _topCarouselController.resumeAllMedia();

    // 如果有廣告，重新開始計時器
    if (topAds.isNotEmpty) {
      int currentIndex = _topCarouselController.currentIndex;
      startTopAdTimer(currentIndex);
    }

    // 使用 WidgetsBinding.instance.addPostFrameCallback 延迟通知
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (hasListeners) {
        notifyListeners();
      }
    });
  }

  /// 更新輪播暫停狀態
  void updateCarouselPauseState(bool isPaused) {
    _isTopCarouselPaused = isPaused;

    // 使用 WidgetsBinding.instance.addPostFrameCallback 延迟通知
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (hasListeners) {
        notifyListeners();
      }
    });
  }

  /// 從全屏廣告狀態退出後恢復頂部廣告
  void resumeFromFullscreenAdExit() {
    _logger.i('🔄 开始恢复顶部广告轮播');

    // 重置暂停状态
    _isTopCarouselPaused = false;

    // 恢复媒体播放
    _topCarouselController.resumeAllMedia();

    // 如果有广告，从当前广告重新开始
    if (topAds.isNotEmpty) {
      // 重置时间相关状态
      _currentTopAdStartTime = DateTime.now();
      _topAdElapsedTime = Duration.zero;
      final currentIndex = _topCarouselController.currentIndex;

      // 确保索引有效
      final validIndex =
          currentIndex >= 0 && currentIndex < topAds.length ? currentIndex : 0;

      _topAdDuration = topAds[validIndex].durationObject;

      // 启动新的定时器
      startTopAdTimer(validIndex);

      _logger.i('✅ 顶部广告恢复完成，当前索引: $validIndex');
    } else {
      _logger.w('⚠️ 顶部广告列表为空，无法恢复');
    }

    // 使用 WidgetsBinding.instance.addPostFrameCallback 延迟通知
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (hasListeners) {
        notifyListeners();
      }
    });
  }

  /// 檢查並恢復輪播狀態（監控定時器使用）
  void checkAndRestoreTopCarousel() {
    if (topAds.isNotEmpty && !_isTopCarouselPaused) {
      // 檢查當前定時器是否活躍
      if (_topTimer == null || !_topTimer!.isActive) {
        final currentIndex = _topCarouselController.currentIndex;

        // 恢復視頻播放
        _topCarouselController.resumeAllMedia();

        // 恢復定時器
        startTopAdTimer(currentIndex);
      }
    }
  }

  ///9，處理頁面變化事件
  void onPageChanged(int index) {
    if (!_isTopCarouselPaused && topAds.isNotEmpty) {
      startTopAdTimer(index);
    }
  }

  /// 暫停所有計時器（用於設置頁面）
  void pauseAllTimersForSettings() {
    _topTimer?.cancel();
    _debugTimer?.cancel();
    _topCarouselController.pauseAllMedia();
    _isTopCarouselPaused = true;

    // 使用 WidgetsBinding.instance.addPostFrameCallback 延迟通知
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (hasListeners) {
        notifyListeners();
      }
    });
  }

  /// 從設置頁面恢復所有計時器
  void resumeAllTimersFromSettings() {
    _isTopCarouselPaused = false;
    _topCarouselController.resumeAllMedia();

    // 恢復頂部廣告輪播
    if (topAds.isNotEmpty) {
      int currentIndex = _topCarouselController.currentIndex;
      startTopAdTimer(currentIndex);
    }
    // 使用 WidgetsBinding.instance.addPostFrameCallback 延迟通知
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (hasListeners) {
        notifyListeners();
      }
    });
  }

  bool get mounted => _mounted;

  @override
  void dispose() {
    _mounted = false;
    _topTimer?.cancel();
    _topTimer = null;
    _debugTimer?.cancel();
    _debugTimer = null;
    _widgetCache.clear();
    _fileManagerCache.clear();
    super.dispose();
  }
}
