import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:iboard_app/managers/file_manager.dart';
import 'package:iboard_app/models/ad_model.dart';
import 'package:iboard_app/widgets/carousel_widget.dart' as custom_carousel;
import 'package:iboard_app/widgets/mainscreen/ad_top_widget.dart';
import 'package:iboard_app/utils/precise_video_pool_manager.dart' as precise;

/// 頂部廣告輪播Provider
/// 負責管理頂部廣告的輪播邏輯、暫停恢復、定時器管理等
class TopAdCarouselProvider extends ChangeNotifier {
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

  // 🎯 新增：精确视频池管理器实例
  final precise.PreciseVideoPoolManager _preciseVideoPoolManager =
      precise.PreciseVideoPoolManager();

  // 時間記錄相關 - 简化版本（暂停即切换，不需要复杂的时间管理）
  DateTime? _currentTopAdStartTime; // 當前頂部廣告開始時間
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

  /// 🎯 获取精确视频池管理器实例
  precise.PreciseVideoPoolManager get preciseVideoPoolManager =>
      _preciseVideoPoolManager;

  TopAdCarouselProvider() {
    _topCarouselController = custom_carousel.CarouselController();
  }

  ///1，更新輪播廣告列表（由AdvertisementProvider調用）
  void updateCarouselList(List<AdModel> newTopAds) {
    if (_areAdsListsEqual(_topAds, newTopAds)) {
      return;
    }

    _topAds = List<AdModel>.from(newTopAds);

    // 智能更新：如果正在播放，延遲更新Widget；如果是恢復操作，不更新Widget
    if (!_isTopCarouselPaused && _topTimer != null && _topTimer!.isActive) {
      _pendingWidgetUpdate = true;
    } else if (_widgetCache.isNotEmpty) {
      // 如果已有Widget緩存且處於暫停狀態，不重建Widget以保持播放狀態
      // 保持現有Widget緩存，避免重建
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
      return false;
    }

    // 檢查每個廣告的文件是否有效
    for (final ad in _topAds) {
      if (ad.file.url.isEmpty) {
        return false;
      }
    }

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
      // No top advertisements available
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
        // 保持當前播放廣告Widget
      } else if (_widgetCache.containsKey(key)) {
        // 其他已緩存的Widget也保持不變
        widgetMap[key] = _widgetCache[key]!;
      } else {
        // 只為新廣告創建Widget
        final widget = _createCachedAdWidget(ad);
        _widgetCache[key] = widget;
        widgetMap[key] = widget;
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

  ///4，啟動頂部廣告計時器（简化版本 - 每次都是新广告）
  void startTopAdTimer(int currentIndex) {
    _topTimer?.cancel();
    if (topAds.length <= 1 ||
        currentIndex < 0 ||
        currentIndex >= topAds.length ||
        _isTopCarouselPaused) {
      return;
    }

    final ad = topAds[currentIndex];

    // 简化逻辑：每次启动都是新广告，使用完整时长
    _currentTopAdStartTime = DateTime.now();
    _topAdDuration = ad.durationObject;
    _currentTopAdIndex = currentIndex;
    _topAdElapsedTime = Duration.zero;

    _topTimer = Timer(_topAdDuration, () {
      if (_topCarouselController.widgetCount > 1 && !_isTopCarouselPaused) {
        // 在播放下一個廣告之前檢查是否有待處理的更新
        if (_pendingWidgetUpdate) {
          _smartUpdateWidgets();
          _pendingWidgetUpdate = false;
        }

        _topCarouselController.playNext();
        // onPageChanged will then call startTopAdTimer for the new page
      }
    });
  }

  ///5，暂停頂部輪播（进入全屏广告时 - 只暂停不切换）
  void pauseTopCarousel() {
    // 设置頂部輪播为暂停状态
    _isTopCarouselPaused = true;

    // 取消当前定时器
    _topTimer?.cancel();

    // 暂停当前视频并通知Widget释放控制器
    _pauseCurrentVideo();

    // 🎯 关键修复：进入全屏广告时只暂停，不切换广告，避免时序冲突

    // 通知UI更新暂停状态，但不切换广告索引
    if (hasListeners) {
      notifyListeners();
    }
  }

  ///5a，暂停当前视频并触发控制器释放
  void _pauseCurrentVideo() {
    // 发送暂停通知给当前的TopAdWidget
    _topCarouselController.pauseAllMedia();

    // 延迟一小段时间确保Widget有时间处理暂停和释放
    Future.delayed(const Duration(milliseconds: 100), () {});
  }

  ///6，恢復頂部輪播
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

  ///7，更新輪播暫停狀態
  void updateCarouselPauseState(bool isPaused) {
    _isTopCarouselPaused = isPaused;

    // 使用 WidgetsBinding.instance.addPostFrameCallback 延迟通知
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (hasListeners) {
        notifyListeners();
      }
    });
  }

  ///8，從全屏廣告狀態退出後恢復頂部廣告（改为切换并初始化）
  void resumeFromFullscreenAdExit() {
    // 开始恢复顶部广告轮播

    // 重置暂停状态
    _isTopCarouselPaused = false;

    // 🎯 关键修复：退出全屏广告时才切换到下一个广告并初始化
    if (topAds.isNotEmpty && _topCarouselController.widgetCount > 1) {
      _topCarouselController.playNext();

      // 重置时间状态（因为切换了广告）
      _currentTopAdStartTime = null;
      _topAdElapsedTime = Duration.zero;

      // 立即通知UI更新，触发新广告的初始化
      if (hasListeners) {
        notifyListeners();
      }

      // 延迟一小段时间让新广告初始化完成，然后恢复播放
      Future.delayed(const Duration(milliseconds: 200), () {
        if (!_isTopCarouselPaused && topAds.isNotEmpty) {
          _resumePlaybackAfterSwitch();
        }
      });
    } else {
      // 没有多个广告或列表为空，直接恢复当前广告
      _resumePlaybackAfterSwitch();
    }
  }

  ///8a，切换广告后恢复播放的辅助方法
  void _resumePlaybackAfterSwitch() {
    // 恢复媒体播放
    _topCarouselController.resumeAllMedia();

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
    }

    // 使用 WidgetsBinding.instance.addPostFrameCallback 延迟通知
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (hasListeners) {
        notifyListeners();
      }
    });
  }

  /// 9，檢查並恢復輪播狀態（監控定時器使用）
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

  ///10，處理頁面變化事件
  void onPageChanged(int index) {
    if (!_isTopCarouselPaused && topAds.isNotEmpty) {
      startTopAdTimer(index);
    }
  }

  ///11，暫停所有計時器（用於設置頁面）
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

  ///12，從設置頁面恢復所有計時器
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
