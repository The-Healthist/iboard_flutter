import 'dart:async';
import 'package:flutter/material.dart';
import 'package:iboard_app/managers/file_manager.dart';
import 'package:iboard_app/models/ad_model.dart';
import 'package:iboard_app/widgets/ad_full_widget.dart';
import 'package:iboard_app/widgets/carousel_widget.dart';

import 'package:iboard_app/providers/app_data_provider.dart';
import 'package:iboard_app/utils/enhanced_video_pool_manager.dart';
import 'package:video_player/video_player.dart';

/// 简化版全屏广告Provider
/// 参考顶部广告轮播逻辑实现
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

  // 添加：BuildContext 引用用於發送通知
  BuildContext? _currentContext;

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

  ///1，更新轮播广告列表（由AdvertisementProvider调用）
  Future<void> updateCarouselList(List<AdModel> newFullscreenAds) async {
    // 检查数据是否真的发生了变化
    if (_areAdsListsEqual(_fullscreenAds, newFullscreenAds)) {
      debugPrint('🔄 全屏广告轮播列表没有变化，跳过更新');
      return;
    }

    _fullscreenAds = List<AdModel>.from(newFullscreenAds);
    debugPrint('🔄 更新全屏广告轮播列表: ${_fullscreenAds.length} 个广告');

    // 智能更新：如果正在播放，延迟更新Widget
    if (_isActive && !_isPaused) {
      debugPrint('🎬 检测到正在播放全屏广告，延迟更新Widget直到下次切换');
      // 标记需要更新，在下次切换时执行
      _pendingWidgetUpdate = true;
    } else {
      // 不在播放状态，可以安全更新
      await _smartCreateAdWidgets();
    }
    notifyListeners();
  }

  /// 設置BuildContext用於發送通知
  void setContext(BuildContext context) {
    _currentContext = context;
  }

  ///2，清空轮播广告列表
  void clearCarouselList() {
    _fullscreenAds.clear();
    _adWidgets.clear();
    // 清空全屏广告轮播列表
    notifyListeners();
  }

  ///6, 更新全屏广告数据
  Future<void> updateFullscreenAds(List<AdModel> newAds) async {
    // 检查数据是否真的发生了变化
    if (_areAdsListsEqual(_fullscreenAds, newAds)) {
      debugPrint('🔄 全屏广告数据没有变化，跳过更新');
      return;
    }

    // 直接更新广告列表（不再使用自定义顺序）
    _fullscreenAds = List<AdModel>.from(newAds);
    debugPrint('🔄 更新全屏广告数据: ${_fullscreenAds.length}个广告');

    // 🎯 使用智能缓存检查重新创建广告Widget
    await _ensureAdWidgets();
    notifyListeners();
  }

  ///7, 检查两个广告列表是否相等
  bool _areAdsListsEqual(List<AdModel> list1, List<AdModel> list2) {
    if (list1.length != list2.length) return false;

    for (int i = 0; i < list1.length; i++) {
      if (list1[i].id != list2[i].id) return false;
    }

    return true;
  }

  ///7, 创建广告Widget组件列表
  Future<void> _createAdWidgets() async {
    final List<Widget> widgets = [];
    for (int i = 0; i < fullscreenAds.length; i++) {
      final widget = await _createCachedAdWidget(fullscreenAds[i], i);
      widgets.add(widget);
    }
    _adWidgets = widgets;
    // 创建了 ${_adWidgets.length} 个广告Widget
  }

  ///7a, 智能创建广告Widget（使用缓存）
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

  ///6，获取视频控制器Future（私有方法）
  Future<VideoPlayerController?> _getVideoControllerFuture(
      AdModel ad, String key) async {
    try {
      // 先通过FileManager获取本地文件
      final fileManager = _fileManagerCache[key] ?? FileManager();
      final localFile = await fileManager.getFile(ad.file);

      if (localFile == null || !await localFile.exists()) {
        debugPrint('❌ 无法获取本地视频文件: ${ad.title}');
        return null;
      }

      // 根据广告类型确定视频类型
      VideoType videoType;
      if (ad.display == AdDisplayType.topfull) {
        videoType = VideoType.fullAd; // topfull类型在全屏广告中使用fullAd类型
      } else {
        videoType = VideoType.fullAd;
      }

      // 使用本地文件路径创建控制器
      return await EnhancedVideoPoolManager().getController(
        filePath: localFile.path,
        videoType: videoType,
        autoPlay: true,
        looping: true,
        onError: () {
          debugPrint('全屏广告视频控制器初始化失败: ${ad.title}');
        },
      );
    } catch (e) {
      debugPrint('❌ 获取视频控制器Future失败: ${ad.title}');
      return null;
    }
  }

  ///7b, 创建缓存的广告Widget
  Future<Widget> _createCachedAdWidget(AdModel ad, int index) async {
    final key = 'fullscreen_ad_${ad.id}_$index';

    // 重用或创建FileManager
    if (!_fileManagerCache.containsKey(key)) {
      _fileManagerCache[key] = FileManager();
    }
    final fileManager = _fileManagerCache[key]!;
    // 确保文件已下载到本地
    await fileManager.getFile(ad.file);

    // 簡化控制器獲取：直接使用 EnhancedVideoPoolManager，移除本地緩存
    Future<VideoPlayerController?> controllerFuture = Future.value(null);
    if (ad.file.mimeType.startsWith('video/')) {
      controllerFuture = _getVideoControllerFuture(ad, key);
    }

    return FullAdWidget(
      key: ValueKey(key),
      ad: ad,
      fileManager: fileManager,
      controllerFuture: controllerFuture,
      // 始终从头开始播放
      initialPlaybackPosition: Duration.zero,
      onVideoProgressChanged: (adId, position) {
        saveVideoProgress(adId, position);
      },
    );
  }

  ///8, 创建单个广告Widget
  Future<Widget> _createSingleAdWidget(AdModel ad, int index) async {
    final key = 'fullscreen_ad_${ad.id}_$index';

    // 重用或创建FileManager
    if (!_fileManagerCache.containsKey(key)) {
      _fileManagerCache[key] = FileManager();
    }
    final fileManager = _fileManagerCache[key]!;
    // 确保文件已下载到本地
    await fileManager.getFile(ad.file);

    // 使用 EnhancedVideoPoolManager 获取控制器
    Future<VideoPlayerController?> controllerFuture = Future.value(null);
    if (ad.file.mimeType.startsWith('video/')) {
      controllerFuture = _getVideoControllerFuture(ad, key);
    }

    return FullAdWidget(
      key: ValueKey(key),
      ad: ad,
      fileManager: fileManager,
      controllerFuture: controllerFuture, // 传入异步控制器
      onVideoProgressChanged: (adId, position) {
        if (_currentAdIndex < fullscreenAds.length &&
            fullscreenAds[_currentAdIndex].id.toString() == adId) {
          final currentAd = getCurrentAd();
          if (currentAd != null &&
              currentAd.file.mimeType.startsWith('image/')) {
            saveVideoProgress(adId, position);
          }
        }
      },
    );
  }

  ///9, 进入全屏广告模式并开始轮播
  Future<void> enterFullscreenMode() async {
    if (_isActive) return;

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

  ///9a, 确保广告Widget存在（智能缓存检查）
  Future<void> _ensureAdWidgets() async {
    final List<Widget> widgets = [];

    for (int i = 0; i < fullscreenAds.length; i++) {
      final ad = fullscreenAds[i];
      final key = 'fullscreen_ad_${ad.id}_$i';
      if (_widgetCache.containsKey(key)) {
        // 使用缓存的Widget
        widgets.add(_widgetCache[key]!);
        // 使用缓存Widget: ${ad.title}
      } else {
        // 创建新Widget并加入缓存
        // 创建新Widget: ${ad.title}
        final widget = await _createCachedAdWidget(ad, i);
        _widgetCache[key] = widget;
        widgets.add(widget);
      }
    }

    _adWidgets = widgets;
    // 广告Widget准备完成: ${_adWidgets.length}个 (缓存命中: ${_widgetCache.length}个)
  }

  ///10, 启动全屏广告计时
  void startFullscreenAdTimer(int currentIndex) {
    _fullscreenTimer?.cancel(); // 取消之前的计时器

    // 改进的边界检查逻辑
    if (fullscreenAds.isEmpty) {
      debugPrint('⚠️ 全屏广告列表为空，无法启动计时器');
      return;
    }
    if (_isPaused) {
      debugPrint('⚠️ 广告已暂停，跳过计时器启动');
      return;
    }

    if (!_isActive) {
      debugPrint('⚠️ 广告未激活，跳过计时器启动');
      return;
    }

    final ad = fullscreenAds[currentIndex];
    _currentAdStartTime = DateTime.now();
    _adDuration = ad.durationObject;
    _currentAdIndex = currentIndex;

    // 检查当前广告的duration是否小于fullscreenAdDuration
    // 如果小于，设置定时器 = duration 然后切换
    if (_adDuration.inSeconds < fullscreenAdDuration) {
      _fullscreenTimer =
          Timer(Duration(seconds: _adDuration.inSeconds), () async {
        if (_isActive && !_isPaused) {
          await _nextAd();
        } else {
          debugPrint('⚠️ 计时器到期但条件不满足: active=$_isActive, paused=$_isPaused');
        }
      });
    } else {
      _fullscreenTimer =
          Timer(Duration(seconds: fullscreenAdDuration), () async {
        if (_isActive && !_isPaused) {
          // 标准广告计时器到期，切换到下一个
          await _nextAd();
        } else {
          // 计时器到期但条件不满足: active=$_isActive, paused=$_isPaused
        }
      });
    }
  }

  ///10, 切换到下一个广告（私有方法）- 优化版本，参考顶部广告的优雅实现
  Future<void> _nextAd() async {
    if (fullscreenAds.isEmpty || _isPaused || !_isActive) {
      // _nextAd被阻止: isEmpty=${fullscreenAds.isEmpty}, paused=$_isPaused, active=$_isActive
      return;
    }

    if (fullscreenAds.isEmpty) {
      // 全屏广告列表为空，无法切换广告
      return;
    }

    // 🎯 关键改进1: 在切换之前先暂停和重置当前广告
    await _pauseAndResetCurrentAd();

    // 切换到下一个广告索引
    _currentAdIndex = (_currentAdIndex + 1) % fullscreenAds.length;

    // 全屏广告切换: 索引 ${_currentAdIndex}/${fullscreenAds.length} - ${fullscreenAds[_currentAdIndex].title}

    // 检查是否有待更新的Widget
    if (_pendingWidgetUpdate) {
      debugPrint('🔄 执行延迟的Widget更新');
      await _smartCreateAdWidgets();
    }

    // 重置时间记录
    _adElapsedTime = Duration.zero;
    _expectedAdElapsedTime = Duration.zero;
    _currentAdPauseTime = null;

    // 清除当前广告的视频进度
    clearVideoProgress(fullscreenAds[_currentAdIndex].id.toString());

    notifyListeners();

    // 添加小延迟，让前一个视频有时间完全释放资源
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_isActive && !_isPaused) {
        startFullscreenAdTimer(_currentAdIndex);
      }
    });
  }

  ///10a, 暂停和重置当前广告（参考顶部广告的实现）- 优化版本：让Widget自己释放
  Future<void> _pauseAndResetCurrentAd() async {
    debugPrint('⏸️ 开始暂停当前全屏广告 - 让Widget自己处理释放');

    // 获取当前广告的控制器信息
    final currentAd = getCurrentAd();
    if (currentAd == null) return;

    debugPrint('� 准备切换广告，让Widget自己处理暂停和释放: ${currentAd.title}');

    // 延迟确保Widget有时间处理 - 这很重要！
    await Future.delayed(const Duration(milliseconds: 150));
    debugPrint('✅ 全屏广告Widget处理时间预留完成');
  }

  ///24, 公开的切换到下一个广告方法（供外部调用）
  void nextAd() {
    if (!_isActive || _isPaused) {
      debugPrint('⚠️ 全屏广告未激活或已暂停，无法切换');
      return;
    }

    _nextAd();
  }

  ///12, 暂停轮播
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
          '📊 [暂停] 全屏广告 - 已播放: ${_adElapsedTime.inSeconds}s/${_adDuration.inSeconds}s, 剩余: ${remaining.inSeconds}s');
    }

    _isPaused = true;
    _fullscreenTimer?.cancel();
    notifyListeners();
  }

  ///13, 恢复轮播
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
          '🔄 [恢复] 全屏广告 - 继续播放剩余时间：${remainingTime.inSeconds}s (已播放: ${alreadyPlayed.inSeconds}s, 广告总时长: ${_adDuration.inSeconds}s)');

      // 如果剩余时间 <= 0，应该立即切换到下一个广告
      if (remainingTime.inSeconds <= 0) {
        debugPrint('🔄 [恢复] 剩余时间已到0，立即切换到下一个广告');
        // 使用微小延迟确保状态正确设置
        Future.delayed(const Duration(milliseconds: 100), () async {
          if (_isActive && !_isPaused) {
            await _nextAd();
          }
        });
      } else {
        _fullscreenTimer = Timer(remainingTime, () async {
          if (_isActive && !_isPaused) {
            // debugPrint('⏰ [定时] 全屏广告时间到，切换到下一个');
            await _nextAd();
          }
        });
      }
    }

    notifyListeners();
  }

  ///14, 退出全屏广告模式
  void exitFullscreenMode() {
    if (!_isActive) return;

    // 确保取消所有定时器
    _isActive = false;
    _fullscreenTimer?.cancel();
    _debugTimer?.cancel();

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

    // 🎯 延迟通知，避免Dialog关闭前显示下一个广告的闪现
    Future.delayed(const Duration(milliseconds: 500), () {
      if (hasListeners) {
        notifyListeners();
      }
    });
  }

  ///15, 启动调试定时器 - 每秒输出全屏广告的实时状态（已禁用）
  void startDebugTimer() {
    _debugTimer?.cancel();
    // 禁用全屏广告调试定时器以减少日志输出
    return;
  }

  ///16, 停止调试定时器
  void stopDebugTimer() {
    _debugTimer?.cancel();
  }

  ///17, 暂停所有计时器（用于设置页面）
  void pauseAllTimersForSettings() {
    _fullscreenTimer?.cancel();
    _debugTimer?.cancel();
    _isPaused = true;
    notifyListeners();
  }

  ///18, 从设置页面恢复所有计时器
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

  ///24，记录视频播放进度
  void saveVideoProgress(String adId, Duration position) {
    _videoProgressCache[adId] = position;
  }

  ///25，获取视频播放进度
  Duration? getVideoProgress(String adId) {
    return _videoProgressCache[adId];
  }

  ///26，清除特定视频的播放进度
  void clearVideoProgress(String adId) {
    _videoProgressCache.remove(adId);
  }

  ///22, 获取当前播放的广告模型
  AdModel? getCurrentAd() {
    if (_currentAdIndex >= fullscreenAds.length) return null;
    return fullscreenAds[_currentAdIndex];
  }

  ///23, 获取当前播放的Widget
  Widget? getCurrentWidget() {
    if (_currentAdIndex >= _adWidgets.length) return null;
    return _adWidgets[_currentAdIndex];
  }

  @override
  void dispose() {
    debugPrint('🗑️ FullscreenAdProvider dispose 开始');

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

    debugPrint('✅ FullscreenAdProvider dispose 完成');
    super.dispose();
  }
}
