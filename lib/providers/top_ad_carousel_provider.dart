import 'dart:async';
import 'package:flutter/material.dart';
import 'package:iboard_app/managers/file_manager.dart';
import 'package:iboard_app/models/ad_model.dart';
import 'package:iboard_app/widgets/carousel_widget.dart' as custom_carousel;
import 'package:iboard_app/widgets/mainscreen/top_ad_widget.dart';
import 'package:logger/logger.dart';

/// 顶部广告轮播Provider
/// 负责管理顶部广告的轮播逻辑、暂停恢复、定时器管理等
class TopAdCarouselProvider extends ChangeNotifier {
  final Logger _logger = Logger();

  // 轮播控制器
  late custom_carousel.CarouselController _topCarouselController;

  // 定时器管理
  Timer? _topTimer;
  Timer? _debugTimer;

  // 广告数据
  List<AdModel> _topAds = [];

  // 状态管理
  bool _isTopCarouselPaused = false;

  // 时间记录相关 - 用于全屏广告暂停恢复
  DateTime? _currentTopAdStartTime; // 当前顶部广告开始时间
  DateTime? _currentTopAdPauseTime; // 当前顶部广告暂停时间
  Duration _topAdElapsedTime = Duration.zero; // 顶部广告已播放时间
  Duration _topAdDuration = const Duration(seconds: 15); // 顶部广告总时长
  int _currentTopAdIndex = 0; // 当前顶部广告索引

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
  }

  /// 初始化顶部轮播
  void initializeTopWidgets(List<AdModel> topAds) {
    if (topAds.isEmpty) {
      _logger.w('No top advertisements available');
      return;
    }

    _topAds = topAds; // Store ads for timer logic

    // Create ad widgets from the API AdModel instances
    List<Widget> adWidgets = _topAds.map((ad) {
      FileManager fileManager = FileManager();
      fileManager.getFile(ad.file);
      return Center(
        child: TopAdWidget(
          ad: ad,
          fileManager: fileManager,
        ),
      );
    }).toList();
    _topCarouselController.setCarouselArray(adWidgets);

    if (_topAds.length > 1) {
      startTopAdTimer(0); // Start timer for the first ad
    }

    _logger.i('🎬 [初始化] 顶部广告轮播初始化完成，广告数量: ${_topAds.length}');
  }

  /// 启动顶部广告计时器
  void startTopAdTimer(int currentIndex) {
    _logger.d(
        '🎬 开始顶部广告计时器: index=$currentIndex, ads=${_topAds.length}, paused=$_isTopCarouselPaused');
    _topTimer?.cancel();
    if (_topAds.length <= 1 ||
        currentIndex < 0 ||
        currentIndex >= _topAds.length ||
        _isTopCarouselPaused) {
      _logger.w(
          '⚠️ 顶部广告计时器条件不满足: ads=${_topAds.length}, index=$currentIndex, paused=$_isTopCarouselPaused');
      return;
    }

    final ad = _topAds[currentIndex];
    // 记录当前广告开始时间和总时长
    _currentTopAdStartTime = DateTime.now();
    _topAdDuration = ad.durationObject;
    _currentTopAdIndex = currentIndex;
    
    // 只有当切换到新广告时才重置已播放时间
    _topAdElapsedTime = Duration.zero;

    _logger.d('▶️ 启动顶部广告计时器: ${ad.title}, duration=${ad.durationObject}');
    _logger.i(
        '📝 记录顶部广告开始时间: $_currentTopAdStartTime, 索引: $_currentTopAdIndex, 时长: ${_topAdDuration.inSeconds}秒');

    _topTimer = Timer(ad.durationObject, () {
      if (_topCarouselController.widgetCount > 1 && !_isTopCarouselPaused) {
        _logger.d('⏭️ 顶部广告计时器到期，切换到下一个');
        _topCarouselController.playNext();
        // onPageChanged will then call startTopAdTimer for the new page
      }
    });
  }

  /// 暂停顶部轮播
  void pauseTopCarousel() {
    _logger.i('🛑 暂停顶部轮播 - 进入全屏广告状态');

    // 记录当前播放时间
    _currentTopAdPauseTime = DateTime.now();

    // 计算已播放时间
    if (_currentTopAdStartTime != null) {
      final rawElapsed = _currentTopAdPauseTime!.difference(_currentTopAdStartTime!);
      // 加上之前的已播放时间（如果有的话）
      final totalElapsed = rawElapsed + _topAdElapsedTime;
      
      // 确保已播放时间不超过广告总时长
      if (totalElapsed >= _topAdDuration) {
        // 广告已经播放完成，应该准备切换到下一个
        _topAdElapsedTime = _topAdDuration;
        final remainingTop = Duration.zero;
        _logger.i(
            '📊 [暂停] 顶部广告 - 已播放: ${_topAdElapsedTime.inSeconds}s/${_topAdDuration.inSeconds}s, 剩余: ${remainingTop.inSeconds}s (广告已完成)');
      } else {
        // 广告还在播放中
        _topAdElapsedTime = totalElapsed;
        final remainingTop = _topAdDuration - _topAdElapsedTime;
        _logger.i(
            '📊 [暂停] 顶部广告 - 已播放: ${_topAdElapsedTime.inSeconds}s/${_topAdDuration.inSeconds}s, 剩余: ${remainingTop.inSeconds}s');
      }
    }

    // 设置顶部轮播为暂停状态
    _isTopCarouselPaused = true;

    // 暂停定时器
    _topTimer?.cancel();

    // 暂停轮播中的媒体内容
    _topCarouselController.pauseAllMedia();

    notifyListeners();
  }

  /// 恢复顶部轮播
  void resumeTopCarousel() {
    _logger.i('▶️ 恢复顶部轮播 - 退出全屏广告状态');

    // 设置顶部轮播为运行状态
    _isTopCarouselPaused = false;

    // 恢复轮播中的媒体内容
    _topCarouselController.resumeAllMedia();

    // 计算剩余播放时间并恢复定时器
    if (_topAds.isNotEmpty && _currentTopAdStartTime != null) {
      final remainingTopTime = _topAdDuration - _topAdElapsedTime;
      _logger.i(
          '🔄 [恢复] 顶部广告 - 继续播放剩余时间：${remainingTopTime.inSeconds}s (已播放: ${_topAdElapsedTime.inSeconds}s)');

      if (remainingTopTime.inSeconds > 0) {
        // 更新当前广告开始时间，使其能正确计算剩余时间
        _currentTopAdStartTime = DateTime.now();
        // 保持 _topAdElapsedTime 不变，这样调试定时器能正确显示从暂停位置继续的时间

        // 继续播放剩余时间
        _topTimer = Timer(remainingTopTime, () {
          if (!_isTopCarouselPaused) {
            _logger.i('⏰ [定时] 顶部广告时间到，切换到下一个');
            _topCarouselController.playNext();
            // Note: onPageChanged will handle calling startTopAdTimer for the new page
          }
        });
      } else {
        // 时间已到，直接切换到下一个
        _logger.i('⚡ [跳过] 顶部广告剩余时间为0，直接切换到下一个');
        _topCarouselController.playNext();
        // Note: onPageChanged will handle calling startTopAdTimer for the new page
      }
    }

    notifyListeners();
  }

  /// 更新轮播暂停状态
  void updateCarouselPauseState(bool isPaused) {
    _isTopCarouselPaused = isPaused;
    _logger.i('🎛️ 顶部轮播状态更新: ${!_isTopCarouselPaused ? "运行" : "暂停"}');
    notifyListeners();
  }

  /// 检查并恢复轮播状态（监控定时器使用）
  void checkAndRestoreTopCarousel() {
    _logger.i(
        '🔍 检查顶部广告恢复条件: ads=${_topAds.length}, paused=$_isTopCarouselPaused');
    if (_topAds.isNotEmpty && !_isTopCarouselPaused) {
      // 检查当前定时器是否活跃
      if (_topTimer == null || !_topTimer!.isActive) {
        _logger.w('🔧 检测到顶部广告轮播中断，尝试恢复...');
        final currentIndex = _topCarouselController.currentIndex;
        _logger.i('🔄 恢复顶部广告轮播，当前索引: $currentIndex');

        startTopAdTimer(currentIndex);
      }
    } else {
      _logger
          .w('❌ 不满足恢复条件: ads=${_topAds.length}, paused=$_isTopCarouselPaused');
    }
  }

  /// 启动调试定时器 - 每秒输出顶部广告的实时状态
  void startDebugTimer() {
    _debugTimer?.cancel();
    _debugTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      // 计算顶部广告剩余时间
      int topAdRemaining = 0;
      if (_currentTopAdStartTime != null) {
        if (_isTopCarouselPaused) {
          // 暂停状态：使用暂停时的剩余时间
          final remaining = _topAdDuration - _topAdElapsedTime;
          topAdRemaining = remaining.isNegative ? 0 : remaining.inSeconds;
        } else {
          // 运行状态：计算当前剩余时间
          final currentElapsed = DateTime.now().difference(_currentTopAdStartTime!);

          // 如果有已播放时间记录（说明经历了暂停恢复），需要加上之前的播放时间
          final totalElapsed = currentElapsed + _topAdElapsedTime;

          final remaining = _topAdDuration - totalElapsed;
          topAdRemaining = remaining.isNegative ? 0 : remaining.inSeconds;
        }
      }

      // 输出调试信息
      String statusInfo = '';
      if (_isTopCarouselPaused) {
        statusInfo = ' [暂停状态]';
      }

      _logger.i(
          '🕐 [调试] 顶部广告: ${topAdRemaining}s/${_topAdDuration.inSeconds}s$statusInfo');
    });
  }

  /// 停止调试定时器
  void stopDebugTimer() {
    _debugTimer?.cancel();
  }

  /// 处理页面变化事件
  void onPageChanged(int index) {
    if (!_isTopCarouselPaused && _topAds.isNotEmpty) {
      startTopAdTimer(index);
    }
  }

  /// 暂停所有计时器（用于设置页面）
  void pauseAllTimersForSettings() {
    _logger.i('⚙️ 顶部广告 - 暂停所有计时器（设置页面）');
    _topTimer?.cancel();
    _debugTimer?.cancel();
    _topCarouselController.pauseAllMedia();
    _isTopCarouselPaused = true;
    notifyListeners();
  }

  /// 从设置页面恢复所有计时器
  void resumeAllTimersFromSettings() {
    _logger.i('↩️ 顶部广告 - 从设置页面恢复所有计时器');
    _isTopCarouselPaused = false;
    _topCarouselController.resumeAllMedia();

    // 恢复顶部广告轮播
    if (_topAds.isNotEmpty) {
      int currentIndex = _topCarouselController.currentIndex;
      startTopAdTimer(currentIndex);
    }

    // 重新启动调试定时器
    startDebugTimer();

    notifyListeners();
  }

  @override
  void dispose() {
    _topTimer?.cancel();
    _debugTimer?.cancel();
    super.dispose();
  }
}
