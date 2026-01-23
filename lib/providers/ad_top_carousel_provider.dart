import 'dart:async';
import 'package:flutter/material.dart';
import 'package:iboard_app/managers/file_manager.dart';
import 'package:iboard_app/models/ad_model.dart';
import 'package:iboard_app/models/live_monitor_ad_model.dart';
import 'package:iboard_app/models/monitor_models.dart';
import 'package:iboard_app/widgets/carousel_widget.dart' as custom_carousel;
import 'package:iboard_app/widgets/mainscreen/ad_top_widget.dart';
import 'package:iboard_app/widgets/mainscreen/live_monitor_widget.dart';
import 'package:iboard_app/utils/precise_video_pool_manager.dart' as precise;
import 'package:shared_preferences/shared_preferences.dart';

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
  final Map<String, GlobalKey<LiveMonitorWidgetState>> _liveMonitorKeys = {};
  bool _pendingWidgetUpdate = false;

  // 狀態管理
  bool _isTopCarouselPaused = false;

  // 🎯 新增：精确视频池管理器实例
  final precise.PreciseVideoPoolManager _preciseVideoPoolManager =
      precise.PreciseVideoPoolManager();

  // 時間記錄相關
  DateTime? _currentTopAdStartTime; // 當前頂部廣告開始時間
  Duration _topAdElapsedTime = Duration.zero; // 頂部廣告已播放時間
  Duration _topAdDuration = const Duration(seconds: 15); // 頂部廣告總時長
  int _currentTopAdIndex = 0; // 當前頂部廣告索引
  DateTime? _pauseStartTime; // 暫停開始時間

  // 實時監控優化：不使用預加載（避免資源浪費），使用快速初始化策略

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

  ///1a，刷新所有监控画面配置（设置页修改后立即生效）
  Future<void> refreshAllMonitorWidgets() async {
    if (!_mounted) return;

    debugPrint('[TopAdCarousel] 🔄 刷新所有监控画面配置...');
    debugPrint('[TopAdCarousel] 📊 当前有 ${_liveMonitorKeys.length} 个监控Widget缓存');
    debugPrint('[TopAdCarousel] 📍 当前广告索引: $_currentTopAdIndex / ${topAds.length}');

    int refreshCount = 0;
    for (final entry in _liveMonitorKeys.entries) {
      final key = entry.value;
      debugPrint('[TopAdCarousel] 🔍 检查监控Widget: ${entry.key}');
      
      if (key.currentState != null) {
        try {
          final state = key.currentState!;
          debugPrint('[TopAdCarousel]   - State存在，mounted: ${state.mounted}, isDisposed: ${state.isDisposed}, isInitialized: ${state.isInitialized}');
          
          // 检查配置是否有变化
          final hasChanged = await state.hasConfigChanged();
          debugPrint('[TopAdCarousel]   - 配置是否变化: $hasChanged');
          
          if (hasChanged) {
            debugPrint('[TopAdCarousel] ✅ 监控配置有变化，重新加载: ${entry.key}');
            await state.reloadMonitorConfig();
            refreshCount++;
            debugPrint('[TopAdCarousel]   - 刷新完成');
          } else {
            debugPrint('[TopAdCarousel] ℹ️ 监控配置无变化，跳过: ${entry.key}');
          }
        } catch (e) {
          debugPrint('[TopAdCarousel] ⚠️ 刷新监控失败 ${entry.key}: $e');
        }
      } else {
        debugPrint('[TopAdCarousel]   - State为空，跳过');
      }
    }

    debugPrint('[TopAdCarousel] ✅ 监控刷新完成，共刷新 $refreshCount 个监控画面');
  }

  ///1，更新輪播廣告列表（由AdvertisementProvider調用）
  Future<void> updateCarouselList(List<AdModel> newTopAds) async {
    final List<AdModel> completeAdList = List<AdModel>.from(newTopAds);

    // 讀取監控配置，決定是否添加實時監控
    final prefs = await SharedPreferences.getInstance();
    final savedLayout = prefs.getString('monitor_layout_type');
    final savedChannels = prefs.getStringList('monitor_selected_channels');
    final layoutType = MonitorLayoutType.fromString(savedLayout ?? 'grid4');
    final hasChannels = savedChannels != null && savedChannels.isNotEmpty;

    if (layoutType != MonitorLayoutType.hidden && hasChannels) {
      completeAdList.add(LiveMonitorAdModel());
      debugPrint('[TopAdCarousel] 📋 更新輪播: ${newTopAds.length}個廣告 + 實時監控');
    } else {
      debugPrint('[TopAdCarousel] 📋 更新輪播: ${newTopAds.length}個廣告 (無實時監控)');
    }

    if (_areAdsListsEqual(_topAds, completeAdList)) {
      return;
    }

    _topAds = completeAdList;

    // 强制更新 Widget，确保轮播列表变化时立即生效
    _smartUpdateWidgets();

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
  Future<void> initializeTopWidgets(List<AdModel> topAds) async {
    if (topAds.isEmpty) {
      return;
    }

    await updateCarouselList(topAds);

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

    // 檢查是否為實時監控
    if (LiveMonitorAdModel.isLiveMonitor(ad)) {
      // 為實時監控創建或復用GlobalKey
      if (!_liveMonitorKeys.containsKey(key)) {
        _liveMonitorKeys[key] = GlobalKey<LiveMonitorWidgetState>();
      }

      return SizedBox.expand(
        child: LiveMonitorWidget(
          key: _liveMonitorKeys[key],
          disableAutoInit: false, // 🔧 启用自动初始化，快速显示
          onInitialized: () {
            debugPrint('[TopAdCarousel] ✅ 實時監控初始化完成');
          },
        ),
      );
    }

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

  ///4，啟動頂部廣告計時器
  void startTopAdTimer(int currentIndex, {Duration? remainingTime}) {
    _topTimer?.cancel();

    // 🔧 修复：移除 topAds.length <= 1 的检查，允许单个广告（包括实时监控）也能正常计时
    if (topAds.isEmpty ||
        currentIndex < 0 ||
        currentIndex >= topAds.length ||
        _isTopCarouselPaused) {
      return;
    }

    final ad = topAds[currentIndex];

    // 判斷是恢復播放還是新廣告
    final Duration timerDuration;
    if (remainingTime != null && remainingTime > Duration.zero) {
      // 恢復播放,使用剩餘時間
      timerDuration = remainingTime;
      debugPrint('[TopAdCarousel] ⏯️ 恢復播放,剩餘時間: ${remainingTime.inSeconds}秒');
    } else {
      // 新廣告,使用完整時長
      timerDuration = ad.durationObject;
      _topAdElapsedTime = Duration.zero;
      debugPrint('[TopAdCarousel] ▶️ 開始新廣告,總時長: ${timerDuration.inSeconds}秒');
    }

    _currentTopAdStartTime = DateTime.now();
    _topAdDuration = ad.durationObject;
    _currentTopAdIndex = currentIndex;

    _topTimer = Timer(timerDuration, () {
      // 🔧 修复：即使只有一个广告也要允许切换（例如实时监控到普通广告的循环）
      if (!_isTopCarouselPaused && _topCarouselController.widgetCount > 0) {
        // 在播放下一個廣告之前檢查是否有待處理的更新
        if (_pendingWidgetUpdate) {
          _smartUpdateWidgets();
          _pendingWidgetUpdate = false;
        }

        // 重置已播放時間
        _topAdElapsedTime = Duration.zero;
        _pauseStartTime = null; // 🔧 重置暫停時間

        // 如果有多个广告，切换到下一个；如果只有一个，重新开始
        if (_topCarouselController.widgetCount > 1) {
          _topCarouselController.playNext();
        } else {
          // 单个广告循环，重新开始计时
          startTopAdTimer(currentIndex);
        }
        // onPageChanged will then call startTopAdTimer for the new page
      }
    });
  }

  ///5，暂停頂部輪播（进入全屏广告时 - 只暂停不切换）
  void pauseTopCarousel() {
    // 设置頂部輪播为暂停状态
    _isTopCarouselPaused = true;

    // 🔧 修复：只在首次暂停时计算已播放时间，避免重复累加
    if (_pauseStartTime == null && _currentTopAdStartTime != null) {
      _pauseStartTime = DateTime.now();
      final elapsed = _pauseStartTime!.difference(_currentTopAdStartTime!);
      _topAdElapsedTime += elapsed;
      debugPrint(
          '[TopAdCarousel] ⏸️ 暂停时已播放: ${_topAdElapsedTime.inSeconds}秒/${_topAdDuration.inSeconds}秒');
    }

    // 取消当前定时器
    _topTimer?.cancel();

    // 檢查當前是否為實時監控
    final currentAd = _getCurrentAd();
    final isLiveMonitor =
        currentAd != null && LiveMonitorAdModel.isLiveMonitor(currentAd);

    // 實時監控不需要暂停視頻
    if (!isLiveMonitor) {
      // 暂停当前视频并通知Widget释放控制器
      _pauseCurrentVideo();
    }

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

  ///6，恢復頂部輪播(從暂停恢復,繼續剩餘時間)
  void resumeTopCarousel() {
    _topTimer?.cancel();

    // 設置頂部輪播為運行狀態
    _isTopCarouselPaused = false;

    // 檢查當前是否為實時監控
    final currentAd = _getCurrentAd();
    final isLiveMonitor =
        currentAd != null && LiveMonitorAdModel.isLiveMonitor(currentAd);

    // 計算剩餘時間
    Duration? remainingTime;
    if (_topAdElapsedTime < _topAdDuration) {
      remainingTime = _topAdDuration - _topAdElapsedTime;
      debugPrint('[TopAdCarousel] ⏯️ 恢復播放,剩餘時間: ${remainingTime.inSeconds}秒');
    }

    // 實時監控不需要發送恢復通知
    if (!isLiveMonitor) {
      // 關鍵修復：不要重建Widget，直接恢復媒體播放
      _topCarouselController.resumeAllMedia();
    }

    // 如果有廣告，使用剩餘時間重新開始計時器
    if (topAds.isNotEmpty) {
      int currentIndex = _topCarouselController.currentIndex;
      startTopAdTimer(currentIndex, remainingTime: remainingTime);
    }

    // 清空暫停時間
    _pauseStartTime = null;

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

  ///8，從全屏廣告狀態退出後恢復頂部廣告
  void resumeFromFullscreenAdExit() {
    // 重置暂停状态
    _isTopCarouselPaused = false;

    // 檢查當前廣告是否為實時監控
    final currentAd = _getCurrentAd();
    final isLiveMonitor =
        currentAd != null && LiveMonitorAdModel.isLiveMonitor(currentAd);

    if (isLiveMonitor) {
      // ⭐ 實時監控: 繼續播放剩餘時間,不切換
      debugPrint('[TopAdCarousel] 📺 恢復實時監控,繼續播放剩餘時間');

      // 計算剩餘時間
      Duration? remainingTime;
      if (_topAdElapsedTime < _topAdDuration) {
        remainingTime = _topAdDuration - _topAdElapsedTime;
      }

      // 立即通知UI更新
      if (hasListeners) {
        notifyListeners();
      }

      // 使用剩餘時間重啟定時器
      if (topAds.isNotEmpty) {
        int currentIndex = _topCarouselController.currentIndex;
        startTopAdTimer(currentIndex, remainingTime: remainingTime);
      }

      // 清空暫停時間
      _pauseStartTime = null;
    } else {
      // 🎯 普通廣告: 切換到下一個廣告
      debugPrint('[TopAdCarousel] 📹 恢復普通廣告,切換到下一個');

      if (topAds.isNotEmpty && _topCarouselController.widgetCount > 1) {
        // 重置时间状态（因为切换了广告）
        _topAdElapsedTime = Duration.zero;
        _pauseStartTime = null;

        // 🔧 修复：playNext会触发onPageChanged，onPageChanged会调用startTopAdTimer
        // 所以这里不需要再调用startTopAdTimer，避免重复
        _topCarouselController.playNext();

        // 立即通知UI更新
        if (hasListeners) {
          notifyListeners();
        }

        // 🔧 修复：延迟恢复媒体播放即可，不再重复调用startTopAdTimer
        Future.delayed(const Duration(milliseconds: 200), () {
          if (!_isTopCarouselPaused) {
            final currentAd = _getCurrentAd();
            final isLiveMonitor = currentAd != null &&
                LiveMonitorAdModel.isLiveMonitor(currentAd);
            if (!isLiveMonitor) {
              _topCarouselController.resumeAllMedia();
            }
          }
        });
      } else {
        // 没有多个广告或列表为空，直接恢复当前广告
        _resumePlaybackAfterSwitch();
      }
    }
  }

  ///8a，切换广告后恢复播放的辅助方法
  void _resumePlaybackAfterSwitch() {
    // 檢查當前廣告類型
    final currentAd = _getCurrentAd();
    final isLiveMonitor =
        currentAd != null && LiveMonitorAdModel.isLiveMonitor(currentAd);

    // 實時監控不需要發送恢復通知
    if (!isLiveMonitor) {
      // 恢复媒体播放
      _topCarouselController.resumeAllMedia();
    }

    if (topAds.isNotEmpty) {
      // 重置时间相关状态(新廣告)
      _currentTopAdStartTime = DateTime.now();
      _topAdElapsedTime = Duration.zero;
      _pauseStartTime = null;
      final currentIndex = _topCarouselController.currentIndex;

      // 确保索引有效
      final validIndex =
          currentIndex >= 0 && currentIndex < topAds.length ? currentIndex : 0;

      _topAdDuration = topAds[validIndex].durationObject;

      // 启动新的定时器(完整時長)
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
    // 🔧 防重複：只在索引真正變化時才處理
    if (index == _currentTopAdIndex &&
        _topTimer != null &&
        _topTimer!.isActive) {
      debugPrint('[TopAdCarousel] ℹ️ 頁面索引未變化 ($index)，跳過重複處理');
      return;
    }

    // 處理頁面切換時的資源管理
    _handlePageChangeResourceManagement(index);

    if (!_isTopCarouselPaused && topAds.isNotEmpty) {
      startTopAdTimer(index);
    }
  }

  ///10a，處理頁面切換的資源管理
  void _handlePageChangeResourceManagement(int newIndex) {
    if (topAds.isEmpty) return;

    // 🔧 優化策略：保持實時監控在後台，不釋放資源
    // 切換時只確保已初始化即可
    for (int i = 0; i < topAds.length; i++) {
      final ad = topAds[i];
      final isLiveMonitor = LiveMonitorAdModel.isLiveMonitor(ad);

      if (isLiveMonitor && i == newIndex) {
        // 只處理當前切換到的實時監控
        final key = 'top_ad_${ad.id}';
        final liveMonitorKey = _liveMonitorKeys[key];

        if (liveMonitorKey != null && liveMonitorKey.currentState != null) {
          final state = liveMonitorKey.currentState!;

          if (state.isInitialized) {
            debugPrint('[TopAdCarousel] ✅ 實時監控已就緒 (索引: $i)');
            // 切換到實時監控時，檢查配置是否變化並刷新
            state.checkConfigAndRefresh();
          } else if (!state.isDisposed) {
            debugPrint('[TopAdCarousel] 📺 切換到實時監控，快速初始化 (索引: $i)');
          }
        }
      }
    }
  }

  ///11，暫停所有計時器（用於設置頁面）
  void pauseAllTimersForSettings() {
    // ⭐ 保存已播放时间
    if (_currentTopAdStartTime != null) {
      final now = DateTime.now();
      final currentElapsed = now.difference(_currentTopAdStartTime!);
      _topAdElapsedTime = _topAdElapsedTime + currentElapsed;
      debugPrint(
          '[TopAdCarousel] ⏸️ 進入設置頁面,已播放: ${_topAdElapsedTime.inSeconds}秒');
    }

    _topTimer?.cancel();
    _debugTimer?.cancel();

    // 檢查當前是否為實時監控
    final currentAd = _getCurrentAd();
    final isLiveMonitor =
        currentAd != null && LiveMonitorAdModel.isLiveMonitor(currentAd);

    // 實時監控不需要暫停通知
    if (!isLiveMonitor) {
      _topCarouselController.pauseAllMedia();
    }

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

    // 檢查當前廣告類型
    final currentAd = _getCurrentAd();
    final isLiveMonitor =
        currentAd != null && LiveMonitorAdModel.isLiveMonitor(currentAd);

    // ⭐ 計算剩餘時間
    Duration? remainingTime;
    if (_topAdElapsedTime < _topAdDuration) {
      remainingTime = _topAdDuration - _topAdElapsedTime;
      debugPrint('[TopAdCarousel] ⏯️ 從設置恢復,剩餘時間: ${remainingTime.inSeconds}秒');
    }

    // 實時監控不需要發送恢復通知
    if (!isLiveMonitor) {
      _topCarouselController.resumeAllMedia();
    }

    // 恢復頂部廣告輪播,使用剩餘時間
    if (topAds.isNotEmpty) {
      int currentIndex = _topCarouselController.currentIndex;
      startTopAdTimer(currentIndex, remainingTime: remainingTime);
    }

    // 使用 WidgetsBinding.instance.addPostFrameCallback 延迟通知
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (hasListeners) {
        notifyListeners();
      }
    });
  }

  ///13，獲取當前廣告
  AdModel? _getCurrentAd() {
    final currentIndex = _topCarouselController.currentIndex;
    if (currentIndex >= 0 && currentIndex < _topAds.length) {
      return _topAds[currentIndex];
    }
    return null;
  }

  bool get mounted => _mounted;

  @override
  void dispose() {
    _mounted = false;
    _topTimer?.cancel();
    _topTimer = null;
    _debugTimer?.cancel();
    _debugTimer = null;

    // 釋放所有實時監控資源
    for (var key in _liveMonitorKeys.keys) {
      final state = _liveMonitorKeys[key]?.currentState;
      if (state != null) {
        state.releaseResources();
      }
    }

    _widgetCache.clear();
    _fileManagerCache.clear();
    _liveMonitorKeys.clear();
    super.dispose();
  }
}
