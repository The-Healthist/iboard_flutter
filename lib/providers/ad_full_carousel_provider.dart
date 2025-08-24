import 'dart:async';
import 'package:flutter/material.dart';
import 'package:iboard_app/managers/file_manager.dart';
import 'package:iboard_app/models/ad_model.dart';
import 'package:iboard_app/widgets/full_ad_widget.dart';
import 'package:logger/logger.dart';
import 'package:iboard_app/providers/app_data_provider.dart';
import 'package:iboard_app/utils/enhanced_video_pool_manager.dart';
import 'package:video_player/video_player.dart';

/// 简化版全屏广告Provider
/// 参考顶部广告轮播逻辑实现
/// 轮播顺序由后台管理，此Provider不再处理自定义顺序
class FullscreenAdProvider extends ChangeNotifier {
  final Logger _logger = Logger();

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

  FullscreenAdProvider(this._appDataProvider) {
    _logger
        .i('FullscreenAdProvider initialized with AppDataProvider, 轮播顺序由后台管理');
  }

  // 视频播放进度记录
  final Map<String, Duration> _videoProgressMap = {};

  // 标记是否有待更新的Widget
  bool _pendingWidgetUpdate = false;

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
  Map<String, Duration> get videoProgressMap => _videoProgressMap;

  /// 获取全屏广告播放时间（秒）
  int get fullscreenAdDuration =>
      _appDataProvider.deviceSettings?.advertisementPlayDuration ??
      _defaultFullscreenAdDuration;

  ///1，更新轮播广告列表（由AdvertisementProvider调用）
  void updateCarouselList(List<AdModel> newFullscreenAds) {
    // 检查数据是否真的发生了变化
    if (_areAdsListsEqual(_fullscreenAds, newFullscreenAds)) {
      _logger.d('🔄 全屏广告轮播列表没有变化，跳过更新');
      return;
    }

    _fullscreenAds = List<AdModel>.from(newFullscreenAds);
    _logger.i('🔄 更新全屏广告轮播列表: ${_fullscreenAds.length} 个广告');

    // 智能更新：如果正在播放，延迟更新Widget
    if (_isActive && !_isPaused) {
      _logger.i('🎬 检测到正在播放全屏广告，延迟更新Widget直到下次切换');
      // 标记需要更新，在下次切换时执行
      _pendingWidgetUpdate = true;
    } else {
      // 不在播放状态，可以安全更新
      _smartCreateAdWidgets();
    }
    notifyListeners();
  }

  ///2，清空轮播广告列表
  void clearCarouselList() {
    _fullscreenAds.clear();
    _adWidgets.clear();
    _logger.i('🗑️ 清空全屏广告轮播列表');
    notifyListeners();
  }

  ///6, 更新全屏广告数据
  void updateFullscreenAds(List<AdModel> newAds) {
    // 检查数据是否真的发生了变化
    if (_areAdsListsEqual(_fullscreenAds, newAds)) {
      _logger.d('🔄 全屏广告数据没有变化，跳过更新');
      return;
    }

    // 直接更新广告列表（不再使用自定义顺序）
    _fullscreenAds = List<AdModel>.from(newAds);
    _logger.i('🔄 更新全屏广告数据: ${_fullscreenAds.length}个广告');

    // 重新创建广告Widget
    _createAdWidgets();
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
  void _createAdWidgets() {
    _adWidgets = fullscreenAds.asMap().entries.map((entry) {
      return _createSingleAdWidget(entry.value, entry.key);
    }).toList();
    // _logger.i('📺 创建了 ${_adWidgets.length} 个广告Widget');
  }

  ///7a, 智能创建广告Widget（使用缓存）
  void _smartCreateAdWidgets() {
    final List<Widget> newWidgets = [];
    final Set<String> usedKeys = {};

    for (int i = 0; i < fullscreenAds.length; i++) {
      final ad = fullscreenAds[i];
      final key = 'fullscreen_ad_${ad.id}';
      usedKeys.add(key);

      // 检查缓存中是否已有此Widget
      if (_widgetCache.containsKey(key)) {
        // 使用缓存的Widget
        newWidgets.add(_widgetCache[key]!);
      } else {
        // 创建新Widget并缓存
        final widget = _createCachedAdWidget(ad, i);
        _widgetCache[key] = widget;
        newWidgets.add(widget);
      }
    }

    // 清理不再使用的缓存
    _widgetCache.removeWhere((key, value) => !usedKeys.contains(key));
    _fileManagerCache.removeWhere((key, value) => !usedKeys.contains(key));

    _adWidgets = newWidgets;
    _pendingWidgetUpdate = false;

    // 注意：全屏广告不使用CarouselWidget，所以不需要调用smartUpdateCarousel
    // 它直接管理_adWidgets列表，通过getCurrentWidget()获取当前显示的Widget
  }

  ///7b, 创建缓存的广告Widget
  Widget _createCachedAdWidget(AdModel ad, int index) {
    final key = 'fullscreen_ad_${ad.id}';

    // 重用或创建FileManager
    if (!_fileManagerCache.containsKey(key)) {
      _fileManagerCache[key] = FileManager();
    }
    final fileManager = _fileManagerCache[key]!;
    fileManager.getFile(ad.file);

    // 使用 EnhancedVideoPoolManager 获取控制器
    Future<VideoPlayerController?> controllerFuture = Future.value(null);
    if (ad.file.mimeType.startsWith('video/')) {
      controllerFuture = EnhancedVideoPoolManager().getController(
        filePath: ad.file.url,
        videoType: VideoType.fullAd,
        isNetwork: ad.file.url.startsWith('http'),
        autoPlay: false,
        looping: false,
      );
    }

    return FullAdWidget(
      key: ValueKey(key),
      ad: ad,
      fileManager: fileManager,
      controllerFuture: controllerFuture, // 传入异步控制器
      initialVideoPosition: null,
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

  ///8, 创建单个广告Widget
  Widget _createSingleAdWidget(AdModel ad, int index) {
    final key = 'fullscreen_ad_${ad.id}_$index';

    // 重用或创建FileManager
    if (!_fileManagerCache.containsKey(key)) {
      _fileManagerCache[key] = FileManager();
    }
    final fileManager = _fileManagerCache[key]!;
    fileManager.getFile(ad.file);

    // 使用 EnhancedVideoPoolManager 获取控制器
    Future<VideoPlayerController?> controllerFuture = Future.value(null);
    if (ad.file.mimeType.startsWith('video/')) {
      controllerFuture = EnhancedVideoPoolManager().getController(
        filePath: ad.file.url,
        videoType: VideoType.fullAd,
        isNetwork: ad.file.url.startsWith('http'),
        autoPlay: false,
        looping: false,
      );
    }

    return FullAdWidget(
      key: ValueKey(key),
      ad: ad,
      fileManager: fileManager,
      controllerFuture: controllerFuture, // 传入异步控制器
      initialVideoPosition: null,
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
  void enterFullscreenMode() {
    if (_isActive) return;

    _isActive = true;
    _isPaused = false;
    _currentAdPauseTime = null;

    if (fullscreenAds.isNotEmpty) {
      // 确保当前索引在有效范围内
      if (_currentAdIndex < 0 || _currentAdIndex >= fullscreenAds.length) {
        _logger.w('⚠️ 修正无效的广告索引: $_currentAdIndex → 0');
        _currentAdIndex = 0;
      }

      _createAdWidgets();

      // 尝试强制播放当前广告
      final currentWidget = getCurrentWidget();
      if (currentWidget is FullAdWidget) {
        _logger.i('🎬 强制尝试播放当前全屏广告');
        // 可以在这里添加额外的播放逻辑，例如通过 Provider 强制刷新
        notifyListeners();
      }

      startFullscreenAdTimer(_currentAdIndex);
      startDebugTimer();
      _currentStateStartTime = DateTime.now();
    }

    notifyListeners();
  }

  ///10, 启动全屏广告计时器 - 添加视频切换延迟
  void startFullscreenAdTimer(int currentIndex) {
    // _logger.d(
    //     '🎬 开始全屏广告计时器: index=$currentIndex, ads=${this.fullscreenAds.length}, paused=$_isPaused');
    _fullscreenTimer?.cancel(); // 取消之前的计时器

    // 改进的边界检查逻辑
    if (fullscreenAds.isEmpty) {
      _logger.w('⚠️ 全屏广告列表为空，无法启动计时器');
      return;
    }

    if (currentIndex < 0 || currentIndex >= fullscreenAds.length) {
      _logger
          .w('⚠️ 广告索引越界: $currentIndex (有效范围: 0-${fullscreenAds.length - 1})');
      return;
    }

    if (_isPaused) {
      _logger.w('⚠️ 广告已暂停，跳过计时器启动');
      return;
    }

    if (!_isActive) {
      _logger.w('⚠️ 广告未激活，跳过计时器启动');
      return;
    }

    final ad = fullscreenAds[currentIndex];
    _currentAdStartTime = DateTime.now();
    _adDuration = ad.durationObject;
    _currentAdIndex = currentIndex;

    // 检查当前广告的duration是否小于fullscreenAdDuration
    // 如果小于，设置定时器 = duration 然后切换
    if (_adDuration.inSeconds < fullscreenAdDuration) {
      // _logger.i(
      //     '⏰ 启动短时广告计时器: ${_adDuration.inSeconds}秒 (索引: $_currentAdIndex/${this.fullscreenAds.length})');
      _fullscreenTimer = Timer(Duration(seconds: _adDuration.inSeconds), () {
        if (_isActive && !_isPaused) {
          // _logger.d('⏭️ 短时广告计时器到期，切换到下一个');
          _nextAd();
        } else {
          _logger.w('⚠️ 计时器到期但条件不满足: active=$_isActive, paused=$_isPaused');
        }
      });
    } else {
      // _logger.i(
      //     '⏰ 启动标准广告计时器: ${fullscreenAdDuration}秒 (索引: $_currentAdIndex/${this.fullscreenAds.length})');
      _fullscreenTimer = Timer(Duration(seconds: fullscreenAdDuration), () {
        if (_isActive && !_isPaused) {
          _logger.d('⏭️ 标准广告计时器到期，切换到下一个');
          _nextAd();
        } else {
          _logger.w('⚠️ 计时器到期但条件不满足: active=$_isActive, paused=$_isPaused');
        }
      });
    }
  }

  ///11, 切换到下一个广告（私有方法） - 添加视频切换延迟
  void _nextAd() {
    if (fullscreenAds.isEmpty || _isPaused || !_isActive) {
      _logger.w(
          '⚠️ _nextAd被阻止: isEmpty=${fullscreenAds.isEmpty}, paused=$_isPaused, active=$_isActive');
      return;
    }

    // 切换到下一个广告 - 使用模运算确保循环
    _currentAdIndex = (_currentAdIndex + 1) % fullscreenAds.length;

    // 额外的安全检查
    _validateAndFixIndex();

    // 检查是否有待更新的Widget
    if (_pendingWidgetUpdate) {
      _logger.i('🔄 执行延迟的Widget更新');
      _smartCreateAdWidgets();
    }

    // 重置时间记录
    _adElapsedTime = Duration.zero;
    _expectedAdElapsedTime = Duration.zero;
    _currentAdPauseTime = null;

    notifyListeners();

    // 添加小延迟，让前一个视频有时间完全释放资源
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_isActive && !_isPaused) {
        startFullscreenAdTimer(_currentAdIndex);
      }
    });
  }

  ///25, 验证并修正广告索引
  void _validateAndFixIndex() {
    if (fullscreenAds.isEmpty) {
      _currentAdIndex = 0;
      return;
    }

    if (_currentAdIndex < 0) {
      _logger.w('⚠️ 索引小于0，修正为0: $_currentAdIndex → 0');
      _currentAdIndex = 0;
    } else if (_currentAdIndex >= fullscreenAds.length) {
      _logger.w(
          '⚠️ 索引越界，修正为0: $_currentAdIndex → 0 (总数: ${fullscreenAds.length})');
      _currentAdIndex = 0;
    }
  }

  ///24, 公开的切换到下一个广告方法（供外部调用）
  void nextAd() {
    if (!_isActive || _isPaused) {
      _logger.w('⚠️ 全屏广告未激活或已暂停，无法切换');
      return;
    }

    // _logger.d('🔄 外部触发全屏广告切换');
    _nextAd();
  }

  ///12, 暂停轮播
  void pauseCarousel() {
    // _logger.i('🛑 暂停全屏广告轮播');

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
      _logger.i(
          '📊 [暂停] 全屏广告 - 已播放: ${_adElapsedTime.inSeconds}s/${_adDuration.inSeconds}s, 剩余: ${remaining.inSeconds}s');
    }

    _isPaused = true;
    _fullscreenTimer?.cancel();
    notifyListeners();
  }

  ///13, 恢复轮播
  void resumeCarousel() {
    _fullscreenTimer?.cancel(); // 显式取消旧的定时器，避免重复计时或意外行为
    // _logger.i('▶️ 恢复全屏广告轮播');

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

      _logger.i(
          '🔄 [恢复] 全屏广告 - 继续播放剩余时间：${remainingTime.inSeconds}s (已播放: ${alreadyPlayed.inSeconds}s, 广告总时长: ${_adDuration.inSeconds}s)');

      // 如果剩余时间 <= 0，应该立即切换到下一个广告
      if (remainingTime.inSeconds <= 0) {
        _logger.i('🔄 [恢复] 剩余时间已到0，立即切换到下一个广告');
        // 使用微小延迟确保状态正确设置
        Future.delayed(const Duration(milliseconds: 100), () {
          if (_isActive && !_isPaused) {
            _nextAd();
          }
        });
      } else {
        _fullscreenTimer = Timer(remainingTime, () {
          if (_isActive && !_isPaused) {
            // _logger.i('⏰ [定时] 全屏广告时间到，切换到下一个');
            _nextAd();
          }
        });
      }
    }

    notifyListeners();
  }

  ///14, 退出全屏广告模式
  void exitFullscreenMode() {
    if (!_isActive) return;

    // _logger.i('🚪 退出全屏广告模式');

    // 为下次进入准备下一个广告（但不触发切换逻辑）
    if (fullscreenAds.isNotEmpty) {
      _currentAdIndex = (_currentAdIndex + 1) % fullscreenAds.length;
      // _logger.i(' 3 3   33 3 🔄 广告索引更新为下一个: $_currentAdIndex');
    }

    // 确保取消所有定时器
    _isActive = false;
    _fullscreenTimer?.cancel();
    _debugTimer?.cancel();

    _currentAdStartTime = null;
    _currentAdPauseTime = null;
    _currentStateStartTime = null;

    // 清除所有视频进度记录
    _videoProgressMap.clear();

    notifyListeners();
  }

  ///15, 启动调试定时器 - 每秒输出全屏广告的实时状态（已禁用）
  void startDebugTimer() {
    _debugTimer?.cancel();
    // 禁用全屏广告调试定时器以减少日志输出
    return;

    // _debugTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
    //   if (!_isActive) return;

    //   String statusText = _isPaused ? '⏸️ 暂停' : '▶️ 播放';
    //   String timeInfo = '';

    //   if (_currentAdStartTime != null &&
    //       _currentAdIndex < this.fullscreenAds.length) {
    //     // 确保预计已播放时间不会超过广告总时长
    //     Duration safeExpectedElapsed = _expectedAdElapsedTime > _adDuration
    //         ? _adDuration
    //         : _expectedAdElapsedTime;

    //     Duration remaining = _adDuration - _adElapsedTime;

    //     if (_isPaused) {
    //       timeInfo =
    //           '剩余: ${remaining.inSeconds}s/${_adDuration.inSeconds}s | 实际已播放: ${_adElapsedTime.inSeconds}s | 预计已播放: ${safeExpectedElapsed.inSeconds}s';
    //     } else {
    //       final currentElapsed =
    //           DateTime.now().difference(_currentAdStartTime!);
    //       final totalElapsed = currentElapsed + _adElapsedTime;
    //       remaining = _adDuration - totalElapsed;
    //       timeInfo =
    //           '剩余: ${remaining.inSeconds.clamp(0, _adDuration.inSeconds)}s/${_adDuration.inSeconds}s | 实际已播放: ${_adElapsedTime.inSeconds}s | 预计已播放: ${safeExpectedElapsed.inSeconds}s';
    //     }
    //   }

    //   final currentAd = this.fullscreenAds.isNotEmpty
    //       ? this.fullscreenAds[_currentAdIndex]
    //       : null;
    //   final adTitle = currentAd?.title ?? '无广告';
    //   final timerActive = _fullscreenTimer?.isActive ?? false;

    //   _logger.i(
    //       '🎬 [全屏广告] $statusText | [${_currentAdIndex + 1}/${this.fullscreenAds.length}] $adTitle | $timeInfo | Timer活跃: $timerActive');
    // });
  }

  ///16, 停止调试定时器
  void stopDebugTimer() {
    _debugTimer?.cancel();
  }

  ///17, 暂停所有计时器（用于设置页面）
  void pauseAllTimersForSettings() {
    // _logger.i('⚙️ 全屏广告 - 暂停所有计时器（设置页面）');
    _fullscreenTimer?.cancel();
    _debugTimer?.cancel();
    _isPaused = true;
    notifyListeners();
  }

  ///18, 从设置页面恢复所有计时器
  void resumeAllTimersFromSettings() {
    // _logger.i('↩️ 全屏广告 - 从设置页面恢复所有计时器');
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

  ///19, 记录视频播放进度
  void saveVideoProgress(String adId, Duration position) {
    _videoProgressMap[adId] = position;
  }

  ///20, 获取视频播放进度
  Duration? getVideoProgress(String adId) {
    return _videoProgressMap[adId];
  }

  ///21, 清除特定视频的播放进度
  void clearVideoProgress(String adId) {
    _videoProgressMap.remove(adId);
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
    _fullscreenTimer?.cancel();
    _fullscreenTimer = null;

    _debugTimer?.cancel();
    _debugTimer = null;

    // 清理缓存
    _widgetCache.clear();
    _fileManagerCache.clear();

    super.dispose();
  }
}
