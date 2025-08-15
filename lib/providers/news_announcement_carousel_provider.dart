import 'dart:async';
import 'package:flutter/material.dart';
import 'package:iboard_app/models/news_announcement_model.dart';
import 'package:iboard_app/providers/news_announcement_provider.dart';
import 'package:logger/logger.dart';

/// 新闻公报轮播Provider
/// 负责管理新闻公报的轮播逻辑、暂停恢复、定时器管理等
/// 参考顶部广告轮播的逻辑实现
class NewsAnnouncementCarouselProvider extends ChangeNotifier {
  final Logger _logger = Logger();

  // 定时器管理
  Timer? _newsTimer;
  Timer? _debugTimer;

  // 新闻数据提供者引用
  NewsAnnouncementProvider? _newsProvider;

  // 状态管理
  bool _isNewsCarouselPaused = false;

  // 时间记录相关 - 用于全屏广告暂停恢复
  DateTime? _currentNewsStartTime; // 当前新闻开始时间
  DateTime? _currentNewsPauseTime; // 当前新闻暂停时间
  Duration _newsElapsedTime = Duration.zero; // 新闻已播放时间
  Duration _newsDuration = const Duration(seconds: 15); // 新闻总时长
  int _currentNewsIndex = 0; // 当前新闻索引

  // Getters
  bool get isNewsCarouselPaused => _isNewsCarouselPaused;
  Duration get newsDuration => _newsDuration;
  int get currentNewsIndex => _currentNewsIndex;
  DateTime? get currentNewsStartTime => _currentNewsStartTime;
  Duration get newsElapsedTime => _newsElapsedTime;

  NewsAnnouncementCarouselProvider() {
    _logger.i('🔍 NewsAnnouncementCarouselProvider 初始化完成');
  }

  ///1，设置新闻提供者引用
  void setNewsProvider(NewsAnnouncementProvider newsProvider) {
    _newsProvider = newsProvider;
    _logger.i('🔗 新闻公报轮播Provider已连接到NewsAnnouncementProvider');
  }

  ///2，启动新闻轮播计时器
  void startNewsTimer(int currentIndex) {
    _logger
        .d('🎬 开始新闻轮播计时器: index=$currentIndex, paused=$_isNewsCarouselPaused');
    _newsTimer?.cancel();

    if (_newsProvider == null ||
        _newsProvider!.newsList.isEmpty ||
        currentIndex < 0 ||
        currentIndex >= _newsProvider!.newsList.length ||
        _isNewsCarouselPaused) {
      _logger.w(
          '⚠️ 新闻轮播计时器条件不满足: provider=${_newsProvider != null}, newsCount=${_newsProvider?.newsList.length ?? 0}, index=$currentIndex, paused=$_isNewsCarouselPaused');
      return;
    }

    // 记录当前新闻开始时间和总时长
    _currentNewsStartTime = DateTime.now();
    _newsDuration = const Duration(seconds: 15); // 固定15秒显示时间
    _currentNewsIndex = currentIndex;

    // 只有当切换到新新闻时才重置已播放时间
    _newsElapsedTime = Duration.zero;

    _logger
        .d('▶️ 启动新闻轮播计时器: 索引: $currentIndex, 时长: ${_newsDuration.inSeconds}秒');

    _newsTimer = Timer(_newsDuration, () {
      if (!_isNewsCarouselPaused) {
        _logger.d('⏭️ 新闻轮播计时器到期，切换到下一条新闻');
        _switchToNextNews();
      }
    });
  }

  ///3，切换到下一条新闻
  void _switchToNextNews() {
    if (_newsProvider == null || _newsProvider!.newsList.isEmpty) {
      _logger.w('⚠️ 无法切换新闻：新闻提供者为空或新闻列表为空');
      return;
    }

    final nextIndex = (_currentNewsIndex + 1) % _newsProvider!.newsList.length;
    _currentNewsIndex = nextIndex;

    _logger.i(
        '🔄 新闻轮播切换到下一条: ${_currentNewsIndex + 1}/${_newsProvider!.newsList.length}');

    // 启动新新闻的计时器
    startNewsTimer(_currentNewsIndex);

    notifyListeners();
  }

  ///4，暂停新闻轮播
  void pauseNewsCarousel() {
    _logger.i('🛑 暂停新闻轮播 - 进入全屏广告状态');

    // 记录当前播放时间
    _currentNewsPauseTime = DateTime.now();

    // 计算已播放时间
    if (_currentNewsStartTime != null) {
      final rawElapsed =
          _currentNewsPauseTime!.difference(_currentNewsStartTime!);
      // 加上之前的已播放时间（如果有的话）
      final totalElapsed = rawElapsed + _newsElapsedTime;

      // 确保已播放时间不超过新闻总时长
      if (totalElapsed >= _newsDuration) {
        // 新闻已经播放完成，应该准备切换到下一个
        _newsElapsedTime = _newsDuration;
        final remaining = Duration.zero;
        _logger.i(
            '📊 [暂停] 新闻轮播 - 已播放: ${_newsElapsedTime.inSeconds}s/${_newsDuration.inSeconds}s, 剩余: ${remaining.inSeconds}s (新闻已完成)');
      } else {
        // 新闻还在播放中
        _newsElapsedTime = totalElapsed;
        final remaining = _newsDuration - _newsElapsedTime;
        _logger.i(
            '📊 [暂停] 新闻轮播 - 已播放: ${_newsElapsedTime.inSeconds}s/${_newsDuration.inSeconds}s, 剩余: ${remaining.inSeconds}s');
      }
    }

    // 设置新闻轮播为暂停状态
    _isNewsCarouselPaused = true;

    // 暂停定时器
    _newsTimer?.cancel();

    notifyListeners();
  }

  ///5，恢复新闻轮播
  void resumeNewsCarousel() {
    _logger.i('▶️ 恢复新闻轮播 - 退出全屏广告状态');

    // 设置新闻轮播为运行状态
    _isNewsCarouselPaused = false;

    // 计算剩余播放时间并恢复定时器
    if (_newsProvider != null && _newsProvider!.newsList.isNotEmpty) {
      // 如果 _currentNewsStartTime 为空，说明需要重新初始化
      if (_currentNewsStartTime == null) {
        // 重新初始化当前新闻的开始时间和时长
        if (_currentNewsIndex < _newsProvider!.newsList.length) {
          _currentNewsStartTime = DateTime.now();
          _newsDuration = const Duration(seconds: 15);
          _newsElapsedTime = Duration.zero;

          // 启动新的定时器
          _newsTimer = Timer(_newsDuration, () {
            if (!_isNewsCarouselPaused) {
              _logger.i('⏰ [定时] 新闻轮播时间到，切换到下一条');
              _switchToNextNews();
            }
          });

          _logger.i('✅ 新闻轮播已恢复：重新初始化定时器，当前索引: $_currentNewsIndex');
        }
      } else {
        // 原有的恢复逻辑
        final remainingTime = _newsDuration - _newsElapsedTime;
        _logger.i(
            '🔄 [恢复] 新闻轮播 - 继续播放剩余时间：${remainingTime.inSeconds}s (已播放: ${_newsElapsedTime.inSeconds}s)');

        if (remainingTime.inSeconds > 0) {
          // 更新当前新闻开始时间，使其能正确计算剩余时间
          _currentNewsStartTime = DateTime.now();
          // 保持 _newsElapsedTime 不变，这样调试定时器能正确显示从暂停位置继续的时间

          // 继续播放剩余时间
          _newsTimer = Timer(remainingTime, () {
            if (!_isNewsCarouselPaused) {
              _logger.i('⏰ [定时] 新闻轮播时间到，切换到下一条');
              _switchToNextNews();
            }
          });

          _logger.i('✅ 新闻轮播已恢复：继续播放剩余时间 ${remainingTime.inSeconds}s');
        } else {
          // 时间已到，直接切换到下一个
          _logger.i('⚡ [跳过] 新闻轮播剩余时间为0，直接切换到下一条');
          _switchToNextNews();

          _logger.i('✅ 新闻轮播已恢复：时间已到，切换到下一条新闻');
        }
      }
    }

    notifyListeners();
  }

  ///6，更新轮播暂停状态
  void updateCarouselPauseState(bool isPaused) {
    _isNewsCarouselPaused = isPaused;
    _logger.i('🎛️ 新闻轮播状态更新: ${!_isNewsCarouselPaused ? "运行" : "暂停"}');
    notifyListeners();
  }

  ///7，检查并恢复轮播状态（监控定时器使用）
  void checkAndRestoreNewsCarousel() {
    _logger.i(
        '🔍 检查新闻轮播恢复条件: provider=${_newsProvider != null}, newsCount=${_newsProvider?.newsList.length ?? 0}, paused=$_isNewsCarouselPaused');

    if (_newsProvider != null &&
        _newsProvider!.newsList.isNotEmpty &&
        !_isNewsCarouselPaused) {
      // 检查当前定时器是否活跃
      if (_newsTimer == null || !_newsTimer!.isActive) {
        _logger.w('🔧 检测到新闻轮播中断，尝试恢复...');
        _logger.i('🔄 恢复新闻轮播，当前索引: $_currentNewsIndex');

        // 恢复定时器
        startNewsTimer(_currentNewsIndex);

        _logger.i('✅ 新闻轮播已恢复：定时器');
      }
    } else {
      _logger.w(
          '❌ 不满足恢复条件: provider=${_newsProvider != null}, newsCount=${_newsProvider?.newsList.length ?? 0}, paused=$_isNewsCarouselPaused');
    }
  }

  ///8，启动调试定时器 - 每秒输出新闻轮播的实时状态
  void startDebugTimer() {
    _debugTimer?.cancel();
    _debugTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      // 计算新闻轮播剩余时间
      int newsRemaining = 0;
      if (_currentNewsStartTime != null) {
        if (_isNewsCarouselPaused) {
          // 暂停状态：使用暂停时的剩余时间
          final remaining = _newsDuration - _newsElapsedTime;
          newsRemaining = remaining.isNegative ? 0 : remaining.inSeconds;
        } else {
          // 运行状态：计算当前剩余时间
          final currentElapsed =
              DateTime.now().difference(_currentNewsStartTime!);

          // 如果有已播放时间记录（说明经历了暂停恢复），需要加上之前的播放时间
          final totalElapsed = currentElapsed + _newsElapsedTime;

          final remaining = _newsDuration - totalElapsed;
          newsRemaining = remaining.isNegative ? 0 : remaining.inSeconds;
        }
      }

      // 输出调试信息
      String statusInfo = '';
      if (_isNewsCarouselPaused) {
        statusInfo = ' [暂停状态]';
      }

      _logger.i(
          '🕐 [调试] 新闻轮播: ${newsRemaining}s/${_newsDuration.inSeconds}s$statusInfo');
    });
  }

  ///9，停止调试定时器
  void stopDebugTimer() {
    _debugTimer?.cancel();
  }

  ///10，暂停所有计时器（用于设置页面）
  void pauseAllTimersForSettings() {
    _logger.i('⚙️ 新闻轮播 - 暂停所有计时器（设置页面）');
    _newsTimer?.cancel();
    _debugTimer?.cancel();
    _isNewsCarouselPaused = true;
    notifyListeners();
  }

  ///11，从设置页面恢复所有计时器
  void resumeAllTimersFromSettings() {
    _logger.i('↩️ 新闻轮播 - 从设置页面恢复所有计时器');
    _isNewsCarouselPaused = false;

    // 恢复新闻轮播
    if (_newsProvider != null && _newsProvider!.newsList.isNotEmpty) {
      startNewsTimer(_currentNewsIndex);
    }

    // 重新启动调试定时器
    startDebugTimer();

    notifyListeners();
  }

  ///12，获取当前新闻
  NewsAnnouncementModel? getCurrentNews() {
    if (_newsProvider != null &&
        _newsProvider!.newsList.isNotEmpty &&
        _currentNewsIndex < _newsProvider!.newsList.length) {
      return _newsProvider!.newsList[_currentNewsIndex];
    }
    return null;
  }

  @override
  void dispose() {
    _newsTimer?.cancel();
    _newsTimer = null;

    _debugTimer?.cancel();
    _debugTimer = null;

    super.dispose();
  }
}
