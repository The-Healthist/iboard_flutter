import 'dart:async';
import 'package:flutter/material.dart';
import 'package:iboard_app/managers/file_manager.dart';
import 'package:iboard_app/models/ad_model.dart';
import 'package:iboard_app/widgets/ads/ad_full_widget.dart';

import 'package:iboard_app/providers/app_data_provider.dart';
import 'package:iboard_app/utils/ad_carousel_equality.dart';
import 'package:iboard_app/utils/precise_video_pool_manager.dart' as precise;

/// 轮播顺序由后台管理，此Provider不再处理自定义顺序
class FullscreenAdProvider extends ChangeNotifier {
  bool _isDisposed = false;

  // 定时器管理
  Timer? _fullscreenTimer;
  Timer? _debugTimer;

  // 广告数据 - 使用AdvertisementProvider的轮播数据
  List<AdModel> _fullscreenAds = [];
  List<Widget> _adWidgets = [];

  // Widget缓存机制 - 避免重建正在播放的Widget
  final Map<String, Widget> _widgetCache = {};
  final Map<String, FileManager> _fileManagerCache = {};

  // 状态管理
  bool _isPaused = false;
  bool _isActive = false;

  int _currentAdIndex = 0;

  // 时间记录
  DateTime? _currentAdStartTime;
  DateTime? _currentStateStartTime;
  DateTime? _currentAdPauseTime;
  //当前全屏广告状态下切换前的广告时间,用于记录该次状态下的广告播放完成的个人时间总和
  Duration _adElapsedTime = Duration.zero;
  Duration _expectedAdElapsedTime = Duration.zero; //预计已播放时间
  final Duration _expectendAdNeedAdd = Duration.zero; //
  Duration _adDuration = Duration.zero;

  // App数据提供者相关
  final AppDataProvider _appDataProvider;
  static const int _defaultFullscreenAdDuration = 10; // 默认全屏广告播放时间（秒）

  //  新增：精确视频池管理器实例
  final precise.PreciseVideoPoolManager _preciseVideoPoolManager =
      precise.PreciseVideoPoolManager();

  FullscreenAdProvider(this._appDataProvider) {
    // FullscreenAdProvider initialized with AppDataProvider, 轮播顺序由后台管理
  }

  // 视频播放进度记录
  final Map<String, Duration> _videoProgressMap = {};

  // 标记是否有待更新的Widget
  bool _pendingWidgetUpdate = false;

  // 新增：视频播放进度缓存
  final Map<String, Duration> _videoProgressCache = {};

  // Getters
  List<AdModel> get fullscreenAds => _fullscreenAds;
  List<Widget> get adWidgets => _adWidgets;
  bool get isPaused => _isPaused;
  bool get isActive => _isActive;
  int get currentAdIndex => _currentAdIndex;
  DateTime? get currentAdStartTime => _currentAdStartTime;
  DateTime? get currentStateStartTime => _currentStateStartTime;
  DateTime? get currentAdPauseTime => _currentAdPauseTime;
  Duration get adElapsedTime => _adElapsedTime;
  Duration get expectedAdElapsedTime => _expectedAdElapsedTime; //预计已播放时间
  Duration get expectendAdNeedAdd => _expectendAdNeedAdd; //预计需要添加的已播放时间
  Duration get adDuration => _adDuration;
  Map<String, Duration> get videoProgressMap => _videoProgressCache;

  /// 获取全屏广告播放时间（秒）
  int get fullscreenAdDuration =>
      _appDataProvider.deviceSettings?.advertisementPlayDuration ??
      _defaultFullscreenAdDuration;

  ////  获取精确视频池管理器实例
  precise.PreciseVideoPoolManager get preciseVideoPoolManager =>
      _preciseVideoPoolManager;

  ///0，更新轮播广告列表（由AdvertisementProvider调用）
  Future<void> updateCarouselList(List<AdModel> newFullscreenAds) async {
    // 检查数据是否真的发生了变化
    if (_areAdsListsEqual(_fullscreenAds, newFullscreenAds)) {
      return;
    }

    _fullscreenAds = List<AdModel>.from(newFullscreenAds);

    // 智能更新：如果正在播放，延迟更新Widget
    if (_isActive && !_isPaused) {
      // 标记需要更新，在下次切换时执行
      _pendingWidgetUpdate = true;
    } else {
      // 不在播放状态，可以安全更新
      await _smartCreateAdWidgets();
    }
    notifyListeners();
  }

  /// 設置BuildContext用於發送通知（已移除，不再需要）
  void setContext(BuildContext context) {
    //  移除：不再需要context发送MediaPauseNotification
  }

  ///1，清空轮播广告列表
  void clearCarouselList() {
    _fullscreenAds.clear();
    _adWidgets.clear();
    // 清空全屏广告轮播列表
    notifyListeners();
  }

  ///2, 更新全屏广告数据
  Future<void> updateFullscreenAds(List<AdModel> newAds) async {
    // 检查数据是否真的发生了变化
    if (_areAdsListsEqual(_fullscreenAds, newAds)) {
      return;
    }

    // 直接更新广告列表（不再使用自定义顺序）
    _fullscreenAds = List<AdModel>.from(newAds);

    //  使用智能缓存检查重新创建广告Widget
    await _ensureAdWidgets();
    notifyListeners();
  }

  ///3, 检查两个广告列表是否相等
  bool _areAdsListsEqual(List<AdModel> list1, List<AdModel> list2) {
    return areCarouselAdListsEqual(list1, list2);
  }

  ///4, 智能创建广告Widget（使用缓存）
  Future<void> _smartCreateAdWidgets() async {
    final List<Widget> newWidgets = [];
    final Set<String> usedKeys = {};

    for (int i = 0; i < fullscreenAds.length; i++) {
      final ad = fullscreenAds[i];
      final key = 'fullscreen_ad_${ad.id}_$i';
      usedKeys.add(key);

      // 检查缓存中是否已有此Widget
      if (_widgetCache.containsKey(key)) {
        // 使用缓存的Widget
        newWidgets.add(_widgetCache[key]!);
      } else {
        // 创建新Widget并缓存
        final widget = await _createCachedAdWidget(ad, i);
        _widgetCache[key] = widget;
        newWidgets.add(widget);
      }
    }

    // 清理不再使用的缓存
    _widgetCache.removeWhere((key, value) => !usedKeys.contains(key));
    _fileManagerCache.removeWhere((key, value) => !usedKeys.contains(key));

    _adWidgets = newWidgets;
    _pendingWidgetUpdate = false;
  }

  ///6, 创建缓存的广告Widget
  Future<Widget> _createCachedAdWidget(AdModel ad, int index) async {
    final key = 'fullscreen_ad_${ad.id}_$index';

    // 重用或创建FileManager
    if (!_fileManagerCache.containsKey(key)) {
      _fileManagerCache[key] = FileManager();
    }
    final fileManager = _fileManagerCache[key]!;
    // 确保文件已下载到本地
    await fileManager.getFile(ad.file);

    return FullAdWidget(
      key: ValueKey(key),
      ad: ad,
      fileManager: fileManager,
      // 始终从头开始播放
      initialPlaybackPosition: Duration.zero,
      onVideoProgressChanged: (adId, position) {
        saveVideoProgress(adId, position);
      },
    );
  }

  ///7, 进入全屏广告模式并开始轮播
  Future<void> enterFullscreenMode() async {
    if (_isActive) return;

    //  新增：進入全屏廣告模式前清理可能殘留的控制器
    await _cleanupPreviousControllers();

    _isActive = true;
    _isPaused = false;
    _currentAdPauseTime = null;

    if (fullscreenAds.isNotEmpty) {
      // 确保当前索引在有效范围内
      if (_currentAdIndex < 0 || _currentAdIndex >= fullscreenAds.length) {
        // 修正无效的广告索引: $_currentAdIndex → 0
        _currentAdIndex = 0;
      }
      // 确保是否有广告Widget
      await _ensureAdWidgets();

      startFullscreenAdTimer(_currentAdIndex);
      startDebugTimer();
      _currentStateStartTime = DateTime.now();
    }

    notifyListeners();
  }

  ///8, 确保广告Widget存在（智能缓存检查）
  Future<void> _ensureAdWidgets() async {
    final List<Widget> widgets = [];

    for (int i = 0; i < fullscreenAds.length; i++) {
      final ad = fullscreenAds[i];
      final key = 'fullscreen_ad_${ad.id}_$i';
      if (_widgetCache.containsKey(key)) {
        widgets.add(_widgetCache[key]!);
      } else {
        final widget = await _createCachedAdWidget(ad, i);
        _widgetCache[key] = widget;
        widgets.add(widget);
      }
    }

    _adWidgets = widgets;
  }

  ///9, 启动全屏广告计时（简化版本 - 只管理定时器）
  void startFullscreenAdTimer(int currentIndex) {
    //  强化清理：确保完全取消之前的计时器
    _fullscreenTimer?.cancel();
    _fullscreenTimer = null;

    //  强化边界检查：多重状态验证
    if (fullscreenAds.isEmpty) {
      return;
    }
    if (_isPaused) {
      return;
    }

    if (!_isActive) {
      return;
    }

    //  索引边界检查
    if (currentIndex < 0 || currentIndex >= fullscreenAds.length) {
      return;
    }

    final ad = fullscreenAds[currentIndex];
    _currentAdStartTime = DateTime.now();
    _adDuration = ad.durationObject;
    _currentAdIndex = currentIndex;

    //  简化：不在Provider中初始化视频控制器，让Widget自己处理

    //  强化定时器回调：在回调中再次检查状态
    if (_adDuration.inSeconds < fullscreenAdDuration) {
      _fullscreenTimer =
          Timer(Duration(seconds: _adDuration.inSeconds), () async {
        //  多重状态检查：防止退出状态后的延迟回调
        if (_isActive &&
            !_isPaused &&
            fullscreenAds.isNotEmpty &&
            _fullscreenTimer != null) {
          await _nextAd();
        } else {
          //  如果状态不满足，强制清理定时器
          _fullscreenTimer?.cancel();
          _fullscreenTimer = null;
        }
      });
    } else {
      _fullscreenTimer =
          Timer(Duration(seconds: fullscreenAdDuration), () async {
        //  多重状态检查：防止退出状态后的延迟回调
        if (_isActive &&
            !_isPaused &&
            fullscreenAds.isNotEmpty &&
            _fullscreenTimer != null) {
          await _nextAd();
        } else {
          //  如果状态不满足，强制清理定时器
          _fullscreenTimer?.cancel();
          _fullscreenTimer = null;
        }
      });
    }
  }

  ///10, 切换到下一个广告（私有方法）- 简化版本，移除通知机制避免冲突
  Future<void> _nextAd() async {
    //  首要检查：如果已经退出全屏广告模式，直接返回
    if (!_isActive) {
      return;
    }

    //  强化状态检查：确保在每次操作前都检查状态
    if (fullscreenAds.isEmpty || _isPaused) {
      return;
    }

    //  双重检查：防止异步操作中的状态变化
    if (fullscreenAds.isEmpty) {
      return;
    }

    // 切换到下一个广告索引
    _currentAdIndex = (_currentAdIndex + 1) % fullscreenAds.length;

    // 检查是否有待更新的Widget
    if (_pendingWidgetUpdate) {
      await _smartCreateAdWidgets();
    }

    // 重置时间记录
    _adElapsedTime = Duration.zero;
    _expectedAdElapsedTime = Duration.zero;
    _currentAdPauseTime = null;

    // 清除当前广告的视频进度
    clearVideoProgress(fullscreenAds[_currentAdIndex].id.toString());

    if (!_isDisposed) {
      notifyListeners();
    }

    //  强化状态检查：在启动新定时器前再次确认状态
    if (_isActive && !_isPaused && fullscreenAds.isNotEmpty) {
      startFullscreenAdTimer(_currentAdIndex);
    } else {
      //  如果状态不满足，强制清理所有定时器
      _fullscreenTimer?.cancel();
      _fullscreenTimer = null;
      _debugTimer?.cancel();
      _debugTimer = null;
    }
  }

  ///12, 公开的切换到下一个广告方法（供外部调用）
  void nextAd() {
    if (!_isActive || _isPaused) {
      return;
    }

    _nextAd();
  }

  ///13, 暂停轮播
  void pauseCarousel() {
    // 记录当前播放时间
    _currentAdPauseTime = DateTime.now();

    // 计算已播放时间
    if (_currentAdStartTime != null) {
      final rawElapsed = _currentAdPauseTime!.difference(_currentAdStartTime!);
      final totalElapsed = rawElapsed + _adElapsedTime;

      if (totalElapsed >= _adDuration) {
        _adElapsedTime = _adDuration;
      } else {
        _adElapsedTime = totalElapsed;
      }
      //累加预计已播放时间+= rawElapsed
      _expectedAdElapsedTime += rawElapsed;
      // 对于图片广告，保存显示时间
      // 视频广告不需要保存播放进度，每次进入全屏广告状态都从头播放
      final currentAd = getCurrentAd();
      if (currentAd != null && currentAd.file.mimeType.startsWith('image/')) {
        saveVideoProgress(currentAd.id.toString(), _adElapsedTime);
      }
    }

    _isPaused = true;
    _fullscreenTimer?.cancel();
    notifyListeners();
  }

  ///14, 恢复轮播
  void resumeCarousel() {
    _fullscreenTimer?.cancel(); // 显式取消旧的定时器，避免重复计时或意外行为
    _isPaused = false;

    // 获取当前广告的实际已播放时间
    // 对于视频广告，不需要恢复播放进度，始终从头开始播放
    final currentAd = getCurrentAd();
    if (currentAd != null && currentAd.file.mimeType.startsWith('image/')) {
      final progress = getVideoProgress(currentAd.id.toString());
      if (progress != null) {
        _adElapsedTime = progress;
      }
    } else if (currentAd != null &&
        currentAd.file.mimeType.startsWith('video/')) {
      // 对于视频广告，重置播放时间为0
      _adElapsedTime = Duration.zero;
    }

    // 计算剩余播放时间并恢复定时器
    if (fullscreenAds.isNotEmpty && _currentAdStartTime != null) {
      final currentAd = getCurrentAd();
      if (currentAd != null) {
        _adDuration = currentAd.durationObject;
      }

      // 根据新的逻辑，我们按照fullscreenAdDuration来设置定时器
      // 计算已经播放的时间
      Duration alreadyPlayed = _expectedAdElapsedTime;
      final remainingTime =
          Duration(seconds: fullscreenAdDuration) - alreadyPlayed;

      // 如果剩余时间 <= 0，应该立即切换到下一个广告
      if (remainingTime.inSeconds <= 0) {
        // 使用微小延迟确保状态正确设置
        Future.delayed(const Duration(milliseconds: 100), () async {
          if (_isActive && !_isPaused) {
            await _nextAd();
          }
        });
      } else {
        _fullscreenTimer = Timer(remainingTime, () async {
          if (_isActive && !_isPaused) {
            await _nextAd();
          }
        });
      }
    }

    notifyListeners();
  }

  ///15, 退出全屏广告模式
  Future<void> exitFullscreenMode() async {
    //  强制设置状态：无论当前状态如何，都强制退出
    _isActive = false;
    _isPaused = false;

    //  强化清理：确保完全取消所有定时器，添加多重保护
    if (_fullscreenTimer != null) {
      _fullscreenTimer!.cancel();
      _fullscreenTimer = null;
    }

    if (_debugTimer != null) {
      _debugTimer!.cancel();
      _debugTimer = null;
    }

    _currentAdStartTime = null;
    _currentAdPauseTime = null;
    _currentStateStartTime = null;

    // 清除所有视频进度记录
    _videoProgressMap.clear();

    //  关键修改：将索引更新放在notifyListeners前面
    // 为下次进入准备下一个广告（但不触发切换逻辑）
    if (fullscreenAds.isNotEmpty) {
      _currentAdIndex = (_currentAdIndex + 1) % fullscreenAds.length;
    }

    if (!_isDisposed) {
      notifyListeners();
    }

    Future.delayed(const Duration(milliseconds: 500), () async {
      if (_isDisposed) return;

      try {
        await _cleanupPreviousControllers();
      } catch (_) {
        _ignoreCleanupError();
      }

      _widgetCache.clear();
      _fileManagerCache.clear();
      _adWidgets.clear();
    });
  }

  ///16, 启动调试定时器 - 每秒输出全屏广告的实时状态（已禁用）
  void startDebugTimer() {
    _debugTimer?.cancel();
    // 禁用全屏广告调试定时器以减少日志输出
    return;
  }

  ///17, 停止调试定时器
  void stopDebugTimer() {
    _debugTimer?.cancel();
  }

  ///18, 暂停所有计时器（用于设置页面）
  void pauseAllTimersForSettings() {
    _fullscreenTimer?.cancel();
    _debugTimer?.cancel();
    _isPaused = true;
    notifyListeners();
  }

  ///19, 从设置页面恢复所有计时器
  void resumeAllTimersFromSettings() {
    _isPaused = false;

    // 如果处于活跃状态，恢复轮播
    if (_isActive) {
      // 重新启动调试定时器
      startDebugTimer();

      // 恢复轮播
      resumeCarousel();
    }

    notifyListeners();
  }

  ///20，记录视频播放进度
  void saveVideoProgress(String adId, Duration position) {
    _videoProgressCache[adId] = position;
  }

  ///21，获取视频播放进度
  Duration? getVideoProgress(String adId) {
    return _videoProgressCache[adId];
  }

  ///22，清除特定视频的播放进度
  void clearVideoProgress(String adId) {
    _videoProgressCache.remove(adId);
  }

  ///23, 获取当前播放的广告模型
  AdModel? getCurrentAd() {
    if (_currentAdIndex >= fullscreenAds.length) return null;
    return fullscreenAds[_currentAdIndex];
  }

  ///24, 获取当前播放的Widget（懶加載策略）
  Widget? getCurrentWidget() {
    //  重要修复：如果不在活跃状态，不返回任何Widget
    if (!_isActive) {
      return null;
    }

    if (_currentAdIndex >= fullscreenAds.length) return null;

    //  優化：使用懶加載策略，只為當前廣告創建Widget
    final currentAd = fullscreenAds[_currentAdIndex];
    final key = 'fullscreen_ad_${currentAd.id}_$_currentAdIndex';

    // 檢查緩存中是否已有Widget
    if (_widgetCache.containsKey(key)) {
      return _widgetCache[key]!;
    }

    // 為當前廣告創建新Widget並緩存
    final fileManager = FileManager();
    final widget = FullAdWidget(
      key: ValueKey(key),
      ad: currentAd,
      fileManager: fileManager,
      initialPlaybackPosition: Duration.zero,
      onVideoProgressChanged: (adId, position) {
        saveVideoProgress(adId, position);
      },
    );

    _widgetCache[key] = widget;
    _fileManagerCache[key] = fileManager;

    return widget;
  }

  ///25, 清理之前的控制器以避免重復初始化
  Future<void> _cleanupPreviousControllers() async {
    try {
      // 清理所有全屏廣告類型的控制器
      await _preciseVideoPoolManager
          .cleanupControllersByType(precise.VideoType.fullAd);
    } catch (_) {
      _ignoreCleanupError();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;

    // 取消所有定时器
    _fullscreenTimer?.cancel();
    _fullscreenTimer = null;

    _debugTimer?.cancel();
    _debugTimer = null;

    // 清理缓存 - 保留这些，因为需要清理内存引用
    _widgetCache.clear();
    _fileManagerCache.clear();

    // 控制器由 EnhancedVideoPoolManager 统一管理，无需在此处理
    _videoProgressCache.clear();

    super.dispose();
  }
}

void _ignoreCleanupError() {}
