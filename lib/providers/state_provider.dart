import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:iboard_app/models/settings_model.dart';
import 'package:iboard_app/providers/announcement_carousel_provider.dart';
import 'package:logger/logger.dart';

/// 播放狀態枚舉
enum PlaybackState {
  auto, // 自動播放
  paused, // 暫停播放
  manual, // 手動操作
}

/// 全局應用狀態枚舉
enum AppState {
  defaultState, // 默認播放狀態
  fullscreenAd, // 全屏廣告狀態
  manualOperation, // 手動操作狀態
}

/// 區域類型枚舉
enum AreaType {
  topAd, // 頂部廣告
  middleNotice, // 中間通告
  bottomArea, // 底部區域
  fullscreenAd, // 全屏廣告
}

/// 抽象狀態類，定義四個區域的狀態
abstract class CarouselState {
  PlaybackState get topAdState;
  PlaybackState get middleNoticeState;
  PlaybackState get bottomAreaState;
  PlaybackState get fullscreenAdState;

  AppState get currentAppState;

  /// 狀態轉換方法
  CarouselState toFullscreenAd();
  CarouselState toManualOperation();
  CarouselState toDefaultState();

  /// 檢查是否可以進行狀態轉換
  bool canTransitionTo(AppState targetState);

  /// 獲取指定區域的狀態
  PlaybackState getAreaState(AreaType area) {
    switch (area) {
      case AreaType.topAd:
        return topAdState;
      case AreaType.middleNotice:
        return middleNoticeState;
      case AreaType.bottomArea:
        return bottomAreaState;
      case AreaType.fullscreenAd:
        return fullscreenAdState;
    }
  }
}

///1， 默認播放狀態
class DefaultCarouselState extends CarouselState {
  @override
  PlaybackState get topAdState => PlaybackState.auto;

  @override
  PlaybackState get middleNoticeState => PlaybackState.auto;

  @override
  PlaybackState get bottomAreaState => PlaybackState.auto;

  @override
  PlaybackState get fullscreenAdState => PlaybackState.paused;

  @override
  AppState get currentAppState => AppState.defaultState;

  @override
  CarouselState toFullscreenAd() => FullscreenAdCarouselState();

  @override
  CarouselState toManualOperation() => ManualOperationCarouselState();

  @override
  CarouselState toDefaultState() => this;

  @override
  bool canTransitionTo(AppState targetState) {
    return targetState == AppState.fullscreenAd ||
        targetState == AppState.manualOperation ||
        targetState == AppState.defaultState;
  }
}

///2， 全屏廣告狀態
class FullscreenAdCarouselState extends CarouselState {
  @override
  PlaybackState get topAdState => PlaybackState.paused;

  @override
  PlaybackState get middleNoticeState => PlaybackState.paused;

  @override
  PlaybackState get bottomAreaState => PlaybackState.paused;

  @override
  PlaybackState get fullscreenAdState => PlaybackState.auto;

  @override
  AppState get currentAppState => AppState.fullscreenAd;

  @override
  CarouselState toFullscreenAd() => this;

  @override
  CarouselState toManualOperation() => ManualOperationCarouselState();

  @override
  CarouselState toDefaultState() => DefaultCarouselState();

  @override
  bool canTransitionTo(AppState targetState) {
    return targetState == AppState.manualOperation ||
        targetState == AppState.defaultState ||
        targetState == AppState.fullscreenAd;
  }
}

///3， 手動操作狀態
class ManualOperationCarouselState extends CarouselState {
  @override
  PlaybackState get topAdState => PlaybackState.auto;

  @override
  PlaybackState get middleNoticeState => PlaybackState.manual;

  @override
  PlaybackState get bottomAreaState => PlaybackState.auto;

  @override
  PlaybackState get fullscreenAdState => PlaybackState.paused;

  @override
  AppState get currentAppState => AppState.manualOperation;

  @override
  CarouselState toFullscreenAd() => FullscreenAdCarouselState();

  @override
  CarouselState toManualOperation() => this;

  @override
  CarouselState toDefaultState() {
    // 手動狀態不能直接轉換到默認狀態
    throw StateError(
        'Cannot transition from manual operation to default state directly');
  }

  @override
  bool canTransitionTo(AppState targetState) {
    return targetState == AppState.fullscreenAd ||
        targetState == AppState.manualOperation;
  }
}

/// 狀態提供者類
class CarouselStateProvider extends ChangeNotifier {
  final Logger _logger = Logger();
  CarouselState _currentState = DefaultCarouselState();

  // 计时器相關
  Timer? _fullscreenAdTimer; // 全屏廣告計時器
  Timer? _manualOperationTimer; // 手動操作計時器
  Timer? _defaultStateTimer; // 默認狀態計時器(spareDuration)

  // 通告轮播定时器相关
  Timer? _noticeCarouselTimer; // 通告轮播定时器
  Timer? _noticeLogTimer; // 通告log输出定时器
  bool _isNoticeCarouselActive = false; // 通告轮播是否激活
  bool _isNoticeCarouselPaused = false; // 通告轮播是否暂停
  DateTime? _noticeTimerStartTime; // 通告定时器开始时间
  Duration _noticeElapsedTime = Duration.zero; // 通告已经过时间
  VoidCallback? _onNoticeCarouselNext; // 通告轮播下一个回调

  // 時間記錄
  DateTime? _lastUserInteractionTime; // 最後用戶操作時間
  DateTime? _lastFullscreenAdEndTime; // 最後全屏廣告結束時間
  DateTime? _lastTimerResetTime; // 最後定時器重置時間（用於節流）

  // 回調函數
  VoidCallback? _onShowFullscreenAd; // 顯示全屏廣告的回調
  VoidCallback? _onCloseFullscreenAd; // 關閉全屏廣告的回調
  VoidCallback? _onEnterFullscreenAdMode; // 进入全屏广告模式的回调（通知FullAdProvider）
  VoidCallback? _onExitFullscreenAdMode; // 退出全屏广告模式的回调（通知FullAdProvider）

  // Provider引用
  AnnouncementCarouselProvider? _announcementCarouselProvider; // 通告轮播Provider引用

  // 媒體控制狀態 - 按區域分別控制
  bool _isTopMediaPaused = false; // 頂部廣告媒體暫停狀態
  bool _isMiddleMediaPaused = false; // 中部通告媒體暫停狀態
  bool _isBottomMediaPaused = false; // 底部區域媒體暫停狀態（包括天气和二维码轮播）

  // 時間配置（從服務器獲取，帶默認值）
  Settings? _settings;

  // 默認時間配置（如果服務器配置不可用時使用）
  static const int _defaultFullscreenAdDuration = 10; // 默認全屏廣告播放時間（秒）
  static const int _defaultManualOperationTimeout = 20; // 默認手動操作超時時間（秒）
  static const int _defaultNoActivityTimeout = 20; // 默認無操作進入全屏廣告時間（秒）

  /// 更新時間配置
  void updateSettings(Settings? settings) {
    _settings = settings;
  }

  /// 獲取全屏廣告状态总时间（秒）
  int get fullscreenAdDuration {
    final duration = _settings?.advertisementPlayDuration;
    return duration != null && duration > 0
        ? duration
        : _defaultFullscreenAdDuration;
  }

  /// 獲取手動操作超時時間（秒） - 使用normalToAnnouncementCarouselDuration
  int get manualOperationTimeout {
    final duration = _settings?.normalToAnnouncementCarouselDuration;
    return duration != null && duration > 0
        ? duration
        : _defaultManualOperationTimeout;
  }

  /// 獲取無操作進入全屏廣告時間（秒） - announcementCarouselToFullAdsCarouselDuration
  int get noActivityTimeout {
    final duration = _settings?.announcementCarouselToFullAdsCarouselDuration;
    return duration != null && duration > 0
        ? duration
        : _defaultNoActivityTimeout;
  }

  /// 獲取每個公告停留時間（秒） - 每一個公告在輪播模式停留的時間
  int get noticeStayDuration {
    final duration = _settings?.noticeStayDuration;
    final result = duration != null && duration > 0 ? duration : 5;
    // Notice stay duration debug info (always available)
    // print('🔍 [DEBUG] noticeStayDuration: API=${_settings?.noticeStayDuration}, 返回值=$result');
    return result;
  }

  /// 獲取通告輪播到全屏廣告輪播轉換時間（秒）
  int get announcementCarouselToFullAdsCarouselDuration {
    final duration = _settings?.announcementCarouselToFullAdsCarouselDuration;
    return duration != null && duration > 0 ? duration : 10;
  }

  /// 獲取正常到通告輪播轉換時間（秒）
  int get normalToAnnouncementCarouselDuration {
    final duration = _settings?.normalToAnnouncementCarouselDuration;
    return duration != null && duration > 0 ? duration : 10;
  }

  /// 設置全屏廣告顯示回調
  void setFullscreenAdCallback(VoidCallback? callback) {
    _onShowFullscreenAd = callback;
  }

  /// 設置全屏廣告關閉回調
  void setCloseFullscreenAdCallback(VoidCallback? callback) {
    _onCloseFullscreenAd = callback;
  }

  /// 设置进入全屏广告模式回调
  void setEnterFullscreenAdModeCallback(VoidCallback? callback) {
    _onEnterFullscreenAdMode = callback;
  }

  /// 设置退出全屏广告模式回调
  void setExitFullscreenAdModeCallback(VoidCallback? callback) {
    _onExitFullscreenAdMode = callback;
  }

  /// 設置通告轮播下一个回调
  void setNoticeCarouselNextCallback(VoidCallback? callback) {
    _onNoticeCarouselNext = callback;
  }

  /// 設置通告轮播Provider引用
  void setAnnouncementCarouselProvider(AnnouncementCarouselProvider? provider) {
    _announcementCarouselProvider = provider;
  }

  /// 獲取當前狀態
  CarouselState get currentState => _currentState;

  /// 獲取當前應用狀態
  AppState get currentAppState => _currentState.currentAppState;

  /// 獲取指定區域的播放狀態
  PlaybackState getAreaState(AreaType area) {
    return _currentState.getAreaState(area);
  }

  /// 獲取通告轮播是否激活
  bool get isNoticeCarouselActive => _isNoticeCarouselActive;

  /// 獲取通告轮播是否暂停
  bool get isNoticeCarouselPaused => _isNoticeCarouselPaused;

  /// 獲取媒體暫停狀態 - 按區域
  bool isMediaPausedForArea(AreaType area) {
    switch (area) {
      case AreaType.topAd:
        return _isTopMediaPaused;
      case AreaType.middleNotice:
        return _isMiddleMediaPaused;
      case AreaType.bottomArea:
        return _isBottomMediaPaused;
      case AreaType.fullscreenAd:
        return false; // 全屏廣告自己控制
    }
  }

  ///1， 更新媒體狀態基於當前應用狀態
  void _updateMediaStateBasedOnCurrentState() {
    switch (_currentState.currentAppState) {
      case AppState.defaultState:
        // 默認狀態：所有區域媒體都播放
        _isTopMediaPaused = false;
        _isMiddleMediaPaused = false;
        _isBottomMediaPaused = false;
        break;
      case AppState.fullscreenAd:
        // 全屏廣告狀態：所有區域媒體都暫停
        _isTopMediaPaused = true;
        _isMiddleMediaPaused = true;
        _isBottomMediaPaused = true;
        break;
      case AppState.manualOperation:
        _isTopMediaPaused = false; // 顶部广告继续播放
        _isMiddleMediaPaused = true; // 中部通告暂停
        _isBottomMediaPaused = false; // 底部天气二维码轮播继续播放
        break;
    }

    // Media state update log (always available)
    // print(
    // '🎵 媒體狀態更新[${_currentState.currentAppState.name}]: Top=${!_isTopMediaPaused ? "播放" : "暫停"}, Middle=${!_isMiddleMediaPaused ? "播放" : "暫停"}, Bottom=${!_isBottomMediaPaused ? "天气二维码轮播播放" : "天气二维码轮播暫停"}');
  }

  ///2， 暫停所有媒體 (向後兼容)
  void pauseAllMedia() {
    _isTopMediaPaused = true;
    _isMiddleMediaPaused = true;
    _isBottomMediaPaused = true;
    notifyListeners();
    // Pause all media log (always available)
    // print('🎵 暫停所有視頻播放');
  }

  ///3， 恢復所有媒體 (向後兼容)
  void resumeAllMedia() {
    _updateMediaStateBasedOnCurrentState();
    notifyListeners();
    // Resume all media log (always available)
    // print('▶️ 根據當前狀態更新視頻播放');
  }

  ///4， 切換到全屏廣告狀態
  void enterFullscreenAd() {
    if (_currentState.canTransitionTo(AppState.fullscreenAd)) {
      _clearAllTimers();

      // 暂停通告轮播定时器
      if (_isNoticeCarouselActive) {
        _pauseNoticeCarousel();
      }

      // 自动隐藏所有覆盖层（欠费查询和欠费总览）
      _announcementCarouselProvider?.autoHideAllOverlays();

      _currentState = _currentState.toFullscreenAd();

      // 更新媒體狀態
      _updateMediaStateBasedOnCurrentState();

      // 启动全屏广告状态总时长定时器
      _startFullscreenAdTimer();

      // 通知FullAdvertisementCarouselProvider进入全屏广告模式
      _onEnterFullscreenAdMode?.call();

      notifyListeners();

      // 調用顯示全屏廣告的回調
      _onShowFullscreenAd?.call();
    }
  }

  ///5， 切換到手動操作狀態
  void enterManualOperation() {
    if (_currentState.canTransitionTo(AppState.manualOperation)) {
      // 在状态切换前记录之前的状态
      bool wasInFullscreenAd =
          _currentState.currentAppState == AppState.fullscreenAd;

      _clearAllTimers();
      _currentState = _currentState.toManualOperation();
      _lastUserInteractionTime = DateTime.now();

      // 如果是从全屏广告状态切换过来，需要暂停全屏广告轮播
      if (wasInFullscreenAd) {
        // 通知FullAdvertisementCarouselProvider退出全屏广告模式
        _onExitFullscreenAdMode?.call();
      }

      // 更新媒體狀態
      _updateMediaStateBasedOnCurrentState();

      _startManualOperationTimer();
      notifyListeners();
    }
  }

  ///6， 切換到默認狀態
  void enterDefaultState() {
    if (_currentState.canTransitionTo(AppState.defaultState)) {
      _clearAllTimers();

      // 只有从全屏广告状态切换到默认状态时，才更新全屏广告结束时间
      bool wasInFullscreenAd =
          _currentState.currentAppState == AppState.fullscreenAd;
      _currentState = _currentState.toDefaultState();

      if (wasInFullscreenAd) {
        _lastFullscreenAdEndTime = DateTime.now();
      }

      // 通知FullAdvertisementCarouselProvider退出全屏广告模式
      _onExitFullscreenAdMode?.call();

      // 更新媒體狀態 - 在退出全屏广告后更新
      _updateMediaStateBasedOnCurrentState();

      _startDefaultStateTimer();
      notifyListeners();

      // 調用關閉全屏廣告的回調
      _onCloseFullscreenAd?.call();
    }
  }

  ///6a， 進入通告輪播模式（從手動操作狀態恢復）
  void _enterAnnouncementCarouselMode() {
    _clearAllTimers();

    _isTopMediaPaused = false;
    _isMiddleMediaPaused = false;
    _isBottomMediaPaused = false;

    // 通知通告轮播提供者恢复轮播（恢复之前暂停的状态，不跳转索引）
    if (_announcementCarouselProvider != null) {
      _announcementCarouselProvider!.updateCarouselPauseState(false);

      _announcementCarouselProvider!
          .resumeMidCarousel(noticeStayDuration, forceJumpToIndex: false);
    }

    // 启动通告轮播到全屏广告的计时器
    _startAnnouncementCarouselToFullscreenAdTimer();

    _currentState = DefaultCarouselState();

    notifyListeners();
  }

  ///7， 用戶交互更新（重置手動操作計時器）
  void onUserInteraction() {
    final now = DateTime.now();
    if (_currentState.currentAppState == AppState.manualOperation) {
      _lastUserInteractionTime = now;
      // 添加节流机制：只有在距离上次重置定时器1秒后才允许重置
      if (_lastTimerResetTime == null ||
          now.difference(_lastTimerResetTime!).inSeconds >= 1) {
        _lastTimerResetTime = now;
        _resetManualOperationTimer();
        // User interaction reset timer log (always available)
        // print('🔄 用戶交互檢測到，重置手動操作動態計時器: ${manualOperationTimeout}秒');
      } else {
        // User interaction throttle log (always available)
        // final remaining = 1 - now.difference(_lastTimerResetTime!).inSeconds;
        // print('⏸️ 用戶交互檢測到，但距離上次重置不足1秒，剩餘 ${remaining}秒');
      }
    } else {
      // 如果不在手動狀態，切換到手動狀態
      _lastTimerResetTime = now;
      enterManualOperation();
    }
  }

  ///8， 启动全屏广告状态定时器
  void _startFullscreenAdTimer() {
    _fullscreenAdTimer?.cancel();
    final duration = Duration(seconds: fullscreenAdDuration);
    _fullscreenAdTimer = Timer(duration, () {
      if (_currentState.currentAppState == AppState.fullscreenAd) {
        // Fullscreen ad timer expired log (always available)
        // print('⏰ 全屏廣告狀態定時器到期 (${fullscreenAdDuration}秒)，切換到默認狀態');
        enterDefaultState();
      }
    });
  }

  ///9， 啟動手動操作計時器（使用配置的手動操作超時時間）
  void _startManualOperationTimer() {
    _manualOperationTimer?.cancel();
    final duration = Duration(seconds: normalToAnnouncementCarouselDuration);
    _manualOperationTimer = Timer(duration, () {
      if (_currentState.currentAppState == AppState.manualOperation) {
        _enterAnnouncementCarouselMode();
      }
    });
  }

  ///10， 重置手動操作計時器
  void _resetManualOperationTimer() {
    if (_currentState.currentAppState == AppState.manualOperation) {
      _startManualOperationTimer();
    }
  }

  ///11， 啟動默認狀態計時器（使用配置的無操作超時時間）
  void _startDefaultStateTimer() {
    _defaultStateTimer?.cancel();
    final duration = Duration(seconds: noActivityTimeout);

    _defaultStateTimer = Timer(duration, () {
      if (_currentState.currentAppState == AppState.defaultState) {
        // Default state timer expired log (always available)
        // print('⏰ 默認狀態動態計時器到期 (${noActivityTimeout}秒)，切換到全屏廣告');
        enterFullscreenAd();
      }
    });
  }

  ///11a， 啟動通告輪播到全屏廣告的計時器
  void _startAnnouncementCarouselToFullscreenAdTimer() {
    _defaultStateTimer?.cancel();
    final duration =
        Duration(seconds: announcementCarouselToFullAdsCarouselDuration);

    _defaultStateTimer = Timer(duration, () {
      // 通告轮播模式对应默认状态，所以检查默认状态
      if (_currentState.currentAppState == AppState.defaultState) {
        // Announcement carousel timer expired log
        _logger.i(
            '⏰ 通告輪播計時器到期 ($announcementCarouselToFullAdsCarouselDuration秒)，切換到全屏廣告');
        enterFullscreenAd();
      }
    });
  }

  ///12， 清除所有計時器
  void _clearAllTimers() {
    _fullscreenAdTimer?.cancel();
    _fullscreenAdTimer = null;

    _manualOperationTimer?.cancel();
    _manualOperationTimer = null;

    _defaultStateTimer?.cancel();
    _defaultStateTimer = null;

    // 注意：这里不清除通告轮播定时器，因为它们有独立的生命周期
  }

  ///13， 檢查是否可以轉換到指定狀態
  bool canTransitionTo(AppState targetState) {
    return _currentState.canTransitionTo(targetState);
  }

  ///14， 嘗試狀態轉換，返回是否成功
  bool tryTransitionTo(AppState targetState) {
    try {
      switch (targetState) {
        case AppState.defaultState:
          enterDefaultState();
          return true;
        case AppState.fullscreenAd:
          enterFullscreenAd();
          return true;
        case AppState.manualOperation:
          enterManualOperation();
          return true;
      }
    } catch (e) {
      // State transition failed log (always available)
      _logger.e('State transition failed: $e');
      return false;
    }
  }

  ///15， 重置到默認狀態（強制重置，忽略轉換規則）
  void resetToDefault() {
    _clearAllTimers();
    _currentState = DefaultCarouselState();
    _lastFullscreenAdEndTime = DateTime.now();
    _lastTimerResetTime = null; // 重置節流計時器
    _startDefaultStateTimer();
    notifyListeners();
    // Force reset to default log (always available)
    // print('🔄 強制重置到默認狀態，啟動動態計時器: ${noActivityTimeout}秒');
  }

  ///16， 獲取狀態描述（用於調試）
  String getStateDescription() {
    final now = DateTime.now();
    String timerInfo = '';

    switch (_currentState.currentAppState) {
      case AppState.fullscreenAd:
        timerInfo =
            'Fullscreen ad state timer: active (${fullscreenAdDuration}s timeout)';
        break;
      case AppState.manualOperation:
        if (_lastUserInteractionTime != null) {
          final timeSinceInteraction =
              now.difference(_lastUserInteractionTime!).inSeconds;
          timerInfo =
              'Manual operation timer: ${manualOperationTimeout - timeSinceInteraction}s remaining';
        }
        break;
      case AppState.defaultState:
        if (_lastFullscreenAdEndTime != null) {
          final timeSinceAdEnd =
              now.difference(_lastFullscreenAdEndTime!).inSeconds;
          timerInfo =
              'Default state timer: ${noActivityTimeout - timeSinceAdEnd}s remaining';
        }
        break;
    }

    return '''
Current App State: ${currentAppState.name}
Top Ad: ${_currentState.topAdState.name}
Middle Notice: ${_currentState.middleNoticeState.name}
Bottom Area: ${_currentState.bottomAreaState.name}
Fullscreen Ad: ${_currentState.fullscreenAdState.name}
Timer Info: $timerInfo
''';
  }

  ///17， 釋放資源
  @override
  void dispose() {
    _clearAllTimers();
    _clearNoticeCarouselTimers();
    super.dispose();
  }

  ///26， 暂停所有状态定时器（用于设置页面等场景）
  void pauseAllStateTimers() {
    _clearAllTimers();
    _clearNoticeCarouselTimers();

    // 只重置用户交互时间和节流时间，保留全屏广告结束时间以维持正确的状态逻辑
    _lastUserInteractionTime = null;
    _lastTimerResetTime = null; // 重置節流計時器
    // 注意：不重置 _lastFullscreenAdEndTime，以保持状态转换逻辑的正确性

    // Pause all state timers log (always available)
    // print('⏸️ 已暂停所有状态定时器');
  }

  ///18， 清除通告轮播定时器
  void _clearNoticeCarouselTimers() {
    _noticeCarouselTimer?.cancel();
    _noticeCarouselTimer = null;

    _noticeLogTimer?.cancel();
    _noticeLogTimer = null;
  }

  ///19， 启动通告轮播
  void startNoticeCarousel() {
    if (_isNoticeCarouselActive) {
      // Notice carousel already running log (always available)
      // print('⚠️ 通告轮播已经在运行中');
      return;
    }

    _isNoticeCarouselActive = true;
    _isNoticeCarouselPaused = false;
    _noticeTimerStartTime = DateTime.now();
    _noticeElapsedTime = Duration.zero;

    _startNoticeCarouselTimer();
    _startNoticeLogTimer();

    // Start notice carousel log (always available)
    // print('✅ 启动通告轮播 - 停留时间: ${noticeStayDuration}秒');
    notifyListeners();
  }

  ///20， 停止通告轮播
  void stopNoticeCarousel() {
    if (!_isNoticeCarouselActive) return;

    _isNoticeCarouselActive = false;
    _isNoticeCarouselPaused = false;
    _clearNoticeCarouselTimers();

    // Stop notice carousel log (always available)
    // print('🛑 停止通告轮播');
    notifyListeners();
  }

  ///21， 暂停通告轮播
  void _pauseNoticeCarousel() {
    if (!_isNoticeCarouselActive || _isNoticeCarouselPaused) return;

    _isNoticeCarouselPaused = true;

    // 计算已过时间
    if (_noticeTimerStartTime != null) {
      _noticeElapsedTime = DateTime.now().difference(_noticeTimerStartTime!);
    }

    _clearNoticeCarouselTimers();

    // Pause notice carousel log (always available)
    // print('⏸️ 暂停通告轮播 - 已播放: ${_noticeElapsedTime.inSeconds}秒');
  }

  ///22， 恢复通告轮播
  ///23， 启动通告轮播定时器
  void _startNoticeCarouselTimer([Duration? customDuration]) {
    _noticeCarouselTimer?.cancel();

    final duration = customDuration ?? Duration(seconds: noticeStayDuration);

    _noticeCarouselTimer = Timer(duration, () {
      if (_isNoticeCarouselActive && !_isNoticeCarouselPaused) {
        _onNoticeCarouselNext?.call();
        _resetNoticeTimer();
      }
    });
  }

  ///24， 启动通告Log输出定时器
  void _startNoticeLogTimer() {
    _noticeLogTimer?.cancel();

    _noticeLogTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isNoticeCarouselActive || _isNoticeCarouselPaused) {
        timer.cancel();
        return;
      }

      if (_noticeTimerStartTime != null) {
        final elapsed = DateTime.now().difference(_noticeTimerStartTime!) +
            _noticeElapsedTime;
        final remaining = Duration(seconds: noticeStayDuration) - elapsed;
        final remainingSeconds = remaining.isNegative ? 0 : remaining.inSeconds;

        // Notice timer log (always available)
        // print('📢 通告: ${remainingSeconds}s/${noticeStayDuration}s');
        // Avoid unused variable warning
        remainingSeconds;
      }
    });
  }

  ///25， 重置通告定时器状态
  void _resetNoticeTimer() {
    _noticeTimerStartTime = DateTime.now();
    _noticeElapsedTime = Duration.zero;
    _startNoticeCarouselTimer();
  }
}
