import 'dart:async';
import 'package:flutter/material.dart';
import 'package:iboard_app/managers/file_manager.dart';
import 'package:iboard_app/models/ad_model.dart';
import 'package:iboard_app/widgets/ad_full_widget.dart';

import 'package:iboard_app/providers/app_data_provider.dart';
import 'package:iboard_app/utils/precise_video_pool_manager.dart' as precise;

/// 轮播顺序由后台管理，此Provider不再处理自定义顺序
class FullscreenAdProvider extends ChangeNotifier {
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

  // 🎯 新增：精确视频池管理器实例
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

  /// 🎯 获取精确视频池管理器实例
  precise.PreciseVideoPoolManager get preciseVideoPoolManager =>
      _preciseVideoPoolManager;

  ///0，更新轮播广告列表（由AdvertisementProvider调用）
  Future<void> updateCarouselList(List<AdModel> newFullscreenAds) async {
    // 检查数据是否真的发生了变化
    if (_areAdsListsEqual(_fullscreenAds, newFullscreenAds)) {
      debugPrint('[fullscreen_ad_carousel_provider] 🔄 全屏广告轮播列表没有变化，跳过更新');
      return;
    }

    _fullscreenAds = List<AdModel>.from(newFullscreenAds);
    debugPrint(
        '[fullscreen_ad_carousel_provider] 🔄 更新全屏广告轮播列表: ${_fullscreenAds.length} 个广告');

    // 智能更新：如果正在播放，延迟更新Widget
    if (_isActive && !_isPaused) {
      debugPrint(
          '[fullscreen_ad_carousel_provider] 🎬 检测到正在播放全屏广告，延迟更新Widget直到下次切换');
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
    // 🎯 移除：不再需要context发送MediaPauseNotification
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
      debugPrint('[fullscreen_ad_carousel_provider] 🔄 全屏广告数据没有变化，跳过更新');
      return;
    }

    // 直接更新广告列表（不再使用自定义顺序）
    _fullscreenAds = List<AdModel>.from(newAds);
    debugPrint(
        '[fullscreen_ad_carousel_provider] 🔄 更新全屏广告数据: ${_fullscreenAds.length}个广告');

    // 🎯 使用智能缓存检查重新创建广告Widget
    await _ensureAdWidgets();
    notifyListeners();
  }

  ///3, 检查两个广告列表是否相等
  bool _areAdsListsEqual(List<AdModel> list1, List<AdModel> list2) {
    if (list1.length != list2.length) return false;
    for (int i = 0; i < list1.length; i++) {
      if (list1[i].id != list2[i].id) return false;
    }
    return true;
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

    debugPrint('[fullscreen_ad_carousel_provider] 1, 进入全屏广告模式，开始轮播');

    // 🎯 新增：進入全屏廣告模式前清理可能殘留的控制器
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
      debugPrint(
          '[fullscreen_ad_carousel_provider] 1.1 currentAdIndex: $_currentAdIndex, 进入全屏广告模式，开始轮播');
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
    // 🔧 强化清理：确保完全取消之前的计时器
    _fullscreenTimer?.cancel();
    _fullscreenTimer = null;

    // 🔧 强化边界检查：多重状态验证
    if (fullscreenAds.isEmpty) {
      debugPrint('[fullscreen_ad_carousel_provider] ⚠️ 全屏广告列表为空，无法启动计时器');
      return;
    }
    if (_isPaused) {
      debugPrint('[fullscreen_ad_carousel_provider] ⚠️ 广告已暂停，跳过计时器启动');
      return;
    }

    if (!_isActive) {
      debugPrint('[fullscreen_ad_carousel_provider] ⚠️ 广告未激活，跳过计时器启动');
      return;
    }

    // 🔧 索引边界检查
    if (currentIndex < 0 || currentIndex >= fullscreenAds.length) {
      debugPrint(
          '[fullscreen_ad_carousel_provider] ⚠️ 广告索引超出范围: $currentIndex/${fullscreenAds.length}');
      return;
    }

    final ad = fullscreenAds[currentIndex];
    _currentAdStartTime = DateTime.now();
    _adDuration = ad.durationObject;
    _currentAdIndex = currentIndex;

    // 🎯 简化：不在Provider中初始化视频控制器，让Widget自己处理

    // 🔧 强化定时器回调：在回调中再次检查状态
    if (_adDuration.inSeconds < fullscreenAdDuration) {
      _fullscreenTimer =
          Timer(Duration(seconds: _adDuration.inSeconds), () async {
        // 🔧 多重状态检查：防止退出状态后的延迟回调
        if (_isActive &&
            !_isPaused &&
            fullscreenAds.isNotEmpty &&
            _fullscreenTimer != null) {
          debugPrint('[fullscreen_ad_carousel_provider] ⏰ 广告时长计时器到期，切换到下一个');
          await _nextAd();
        } else {
          debugPrint(
              '[fullscreen_ad_carousel_provider] ⚠️ 广告时长计时器到期但条件不满足或已退出: active=$_isActive, paused=$_isPaused, adsCount=${fullscreenAds.length}, timer=${_fullscreenTimer != null}');
          // 🔧 如果状态不满足，强制清理定时器
          _fullscreenTimer?.cancel();
          _fullscreenTimer = null;
        }
      });
    } else {
      _fullscreenTimer =
          Timer(Duration(seconds: fullscreenAdDuration), () async {
        // 🔧 多重状态检查：防止退出状态后的延迟回调
        if (_isActive &&
            !_isPaused &&
            fullscreenAds.isNotEmpty &&
            _fullscreenTimer != null) {
          debugPrint('[fullscreen_ad_carousel_provider] ⏰ 标准广告计时器到期，切换到下一个');
          await _nextAd();
        } else {
          debugPrint(
              '[fullscreen_ad_carousel_provider] ⚠️ 标准广告计时器到期但条件不满足或已退出: active=$_isActive, paused=$_isPaused, adsCount=${fullscreenAds.length}, timer=${_fullscreenTimer != null}');
          // 🔧 如果状态不满足，强制清理定时器
          _fullscreenTimer?.cancel();
          _fullscreenTimer = null;
        }
      });
    }
  }

  ///10, 切换到下一个广告（私有方法）- 简化版本，移除通知机制避免冲突
  Future<void> _nextAd() async {
    // 🔧 首要检查：如果已经退出全屏广告模式，直接返回
    if (!_isActive) {
      debugPrint('[fullscreen_ad_carousel_provider] ⚠️ 全屏广告已退出，停止切换');
      return;
    }

    // 🔧 强化状态检查：确保在每次操作前都检查状态
    if (fullscreenAds.isEmpty || _isPaused) {
      debugPrint(
          '[fullscreen_ad_carousel_provider] ⚠️ _nextAd被阻止: isEmpty=${fullscreenAds.isEmpty}, paused=$_isPaused, active=$_isActive');
      return;
    }

    // 🔧 双重检查：防止异步操作中的状态变化
    if (fullscreenAds.isEmpty) {
      debugPrint('[fullscreen_ad_carousel_provider] ⚠️ 全屏广告列表为空，无法切换广告');
      return;
    }

    // 🎯 重要修復：在切換前明確釋放當前廣告的控制器，避免重複初始化
    final currentAd = getCurrentAd();
    if (currentAd != null && currentAd.file.localFilePath != null) {
      try {
        // 🎯 關鍵優化：直接釋放控制器，避免重複清理
        await _preciseVideoPoolManager.releaseController(
          filePath: currentAd.file.localFilePath!, // 使用本地文件路徑
          videoType: precise.VideoType.fullAd,
          forceDispose: true, // 強制釋放解碼器資源
        );
        debugPrint(
            '[fullscreen_ad_carousel_provider] ✅ 成功釋放上一個廣告控制器: ${currentAd.title}');
      } catch (e) {
        debugPrint('[fullscreen_ad_carousel_provider] ⚠️ 釋放上一個廣告控制器失敗: $e');
      }
    }

    // 切换到下一个广告索引
    _currentAdIndex = (_currentAdIndex + 1) % fullscreenAds.length;

    debugPrint(
        '[fullscreen_ad_carousel_provider] 🔄 全屏广告切换: 索引 ${_currentAdIndex}/${fullscreenAds.length} - ${fullscreenAds[_currentAdIndex].title}');

    // 检查是否有待更新的Widget
    if (_pendingWidgetUpdate) {
      debugPrint('[fullscreen_ad_carousel_provider] 🔄 执行延迟的Widget更新');
      await _smartCreateAdWidgets();
    }

    // 重置时间记录
    _adElapsedTime = Duration.zero;
    _expectedAdElapsedTime = Duration.zero;
    _currentAdPauseTime = null;

    // 清除当前广告的视频进度
    clearVideoProgress(fullscreenAds[_currentAdIndex].id.toString());

    notifyListeners();

    // 🔧 强化状态检查：在启动新定时器前再次确认状态
    if (_isActive && !_isPaused && fullscreenAds.isNotEmpty) {
      debugPrint('[fullscreen_ad_carousel_provider] ✅ 状态检查通过，启动新广告定时器');
      startFullscreenAdTimer(_currentAdIndex);
    } else {
      debugPrint(
          '[fullscreen_ad_carousel_provider] ⚠️ 状态检查失败，跳过定时器启动: active=$_isActive, paused=$_isPaused, adsCount=${fullscreenAds.length}');
      // 🔧 如果状态不满足，强制清理所有定时器
      _fullscreenTimer?.cancel();
      _fullscreenTimer = null;
      _debugTimer?.cancel();
      _debugTimer = null;
    }
  }

  ///12, 公开的切换到下一个广告方法（供外部调用）
  void nextAd() {
    if (!_isActive || _isPaused) {
      debugPrint('[fullscreen_ad_carousel_provider] ⚠️ 全屏广告未激活或已暂停，无法切换');
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

      final remaining = _adDuration - _adElapsedTime;
      debugPrint(
          '[fullscreen_ad_carousel_provider] 📊 [暂停] 全屏广告 - 已播放: ${_adElapsedTime.inSeconds}s/${_adDuration.inSeconds}s, 剩余: ${remaining.inSeconds}s');
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

      debugPrint(
          '[fullscreen_ad_carousel_provider] 🔄 [恢复] 全屏广告 - 继续播放剩余时间：${remainingTime.inSeconds}s (已播放: ${alreadyPlayed.inSeconds}s, 广告总时长: ${_adDuration.inSeconds}s)');

      // 如果剩余时间 <= 0，应该立即切换到下一个广告
      if (remainingTime.inSeconds <= 0) {
        debugPrint(
            '[fullscreen_ad_carousel_provider] 🔄 [恢复] 剩余时间已到0，立即切换到下一个广告');
        // 使用微小延迟确保状态正确设置
        Future.delayed(const Duration(milliseconds: 100), () async {
          if (_isActive && !_isPaused) {
            await _nextAd();
          }
        });
      } else {
        _fullscreenTimer = Timer(remainingTime, () async {
          if (_isActive && !_isPaused) {
            // debugPrint('[fullscreen_ad_carousel_provider] ⏰ [定时] 全屏广告时间到，切换到下一个');
            await _nextAd();
          }
        });
      }
    }

    notifyListeners();
  }

  ///15, 退出全屏广告模式
  void exitFullscreenMode() {
    debugPrint(
        '[fullscreen_ad_carousel_provider] 🚪 开始退出全屏广告模式 - 当前状态: active=$_isActive, paused=$_isPaused');

    // 🔧 强制设置状态：无论当前状态如何，都强制退出
    _isActive = false;
    _isPaused = false;

    // 🔧 强化清理：确保完全取消所有定时器，添加多重保护
    if (_fullscreenTimer != null) {
      _fullscreenTimer!.cancel();
      _fullscreenTimer = null;
      debugPrint('[fullscreen_ad_carousel_provider] ✅ 全屏广告定时器已取消');
    }

    if (_debugTimer != null) {
      _debugTimer!.cancel();
      _debugTimer = null;
      debugPrint('[fullscreen_ad_carousel_provider] ✅ 调试定时器已取消');
    }

    _currentAdStartTime = null;
    _currentAdPauseTime = null;
    _currentStateStartTime = null;

    // 清除所有视频进度记录
    _videoProgressMap.clear();

    // 🎯 关键修改：将索引更新放在notifyListeners前面
    // 为下次进入准备下一个广告（但不触发切换逻辑）
    if (fullscreenAds.isNotEmpty) {
      _currentAdIndex = (_currentAdIndex + 1) % fullscreenAds.length;
    }

    debugPrint(
        '[fullscreen_ad_carousel_provider] ✅ 全屏广告模式退出完成，下次进入索引: $_currentAdIndex');

    // 🔧 立即通知状态变化，不使用延迟
    notifyListeners();
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
    if (_currentAdIndex >= fullscreenAds.length) return null;

    // 🎯 優化：使用懶加載策略，只為當前廣告創建Widget
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

    debugPrint(
        '[fullscreen_ad_carousel_provider] 🎯 懶加載創建Widget: ${currentAd.title}');
    return widget;
  }

  ///25, 清理之前的控制器以避免重復初始化
  Future<void> _cleanupPreviousControllers() async {
    try {
      // 清理所有全屏廣告類型的控制器
      await _preciseVideoPoolManager
          .cleanupControllersByType(precise.VideoType.fullAd);
      debugPrint('[fullscreen_ad_carousel_provider] ✅ 已清理所有之前的全屏廣告控制器');
    } catch (e) {
      debugPrint('[fullscreen_ad_carousel_provider] ⚠️ 清理之前的控制器時出錯: $e');
    }
  }

  @override
  void dispose() {
    debugPrint(
        '[fullscreen_ad_carousel_provider] 🗑️ FullscreenAdProvider dispose 开始');

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

    debugPrint(
        '[fullscreen_ad_carousel_provider] ✅ FullscreenAdProvider dispose 完成');
    super.dispose();
  }
}
