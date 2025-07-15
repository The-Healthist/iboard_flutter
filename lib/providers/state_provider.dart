import 'dart:async';
import 'package:flutter/foundation.dart';

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
  middleNotice, // 中間公告
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

/// 默認播放狀態
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

/// 全屏廣告狀態
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

/// 手動操作狀態
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
  CarouselState _currentState = DefaultCarouselState();

  // 計時器相關
  Timer? _fullscreenAdTimer; // 全屏廣告計時器（5秒後自動退出）
  Timer? _manualOperationTimer; // 手動操作計時器（10秒後進入全屏廣告）
  Timer? _defaultStateTimer; // 默認狀態計時器（20秒後進入全屏廣告）

  // 時間記錄
  DateTime? _lastUserInteractionTime; // 最後用戶操作時間
  DateTime? _lastFullscreenAdEndTime; // 最後全屏廣告結束時間

  // 回調函數
  VoidCallback? _onShowFullscreenAd; // 顯示全屏廣告的回調
  VoidCallback? _onCloseFullscreenAd; // 關閉全屏廣告的回調

  /// 設置全屏廣告顯示回調
  void setFullscreenAdCallback(VoidCallback? callback) {
    _onShowFullscreenAd = callback;
  }

  /// 設置全屏廣告關閉回調
  void setCloseFullscreenAdCallback(VoidCallback? callback) {
    _onCloseFullscreenAd = callback;
  }

  /// 獲取當前狀態
  CarouselState get currentState => _currentState;

  /// 獲取當前應用狀態
  AppState get currentAppState => _currentState.currentAppState;

  /// 獲取指定區域的播放狀態
  PlaybackState getAreaState(AreaType area) {
    return _currentState.getAreaState(area);
  }

  /// 切換到全屏廣告狀態
  void enterFullscreenAd() {
    if (_currentState.canTransitionTo(AppState.fullscreenAd)) {
      _clearAllTimers();
      _currentState = _currentState.toFullscreenAd();
      _startFullscreenAdTimer();
      notifyListeners();

      // 調用顯示全屏廣告的回調
      _onShowFullscreenAd?.call();

      if (kDebugMode) {
        print('Entered fullscreen ad state, 5-second timer started');
      }
    }
  }

  /// 切換到手動操作狀態
  void enterManualOperation() {
    if (_currentState.canTransitionTo(AppState.manualOperation)) {
      _clearAllTimers();
      _currentState = _currentState.toManualOperation();
      _lastUserInteractionTime = DateTime.now();
      _startManualOperationTimer();
      notifyListeners();
      if (kDebugMode) {
        print('Entered manual operation state, 10-second timer started');
      }
    }
  }

  /// 切換到默認狀態
  void enterDefaultState() {
    if (_currentState.canTransitionTo(AppState.defaultState)) {
      _clearAllTimers();
      _currentState = _currentState.toDefaultState();
      _lastFullscreenAdEndTime = DateTime.now();
      _startDefaultStateTimer();
      notifyListeners();

      // 調用關閉全屏廣告的回調
      _onCloseFullscreenAd?.call();

      if (kDebugMode) {
        print('Entered default state, 20-second timer started');
      }
    }
  }

  /// 用戶交互更新（重置手動操作計時器）
  void onUserInteraction() {
    if (_currentState.currentAppState == AppState.manualOperation) {
      _lastUserInteractionTime = DateTime.now();
      _resetManualOperationTimer();
      if (kDebugMode) {
        print('User interaction detected, manual operation timer reset');
      }
    } else {
      // 如果不在手動狀態，切換到手動狀態
      enterManualOperation();
    }
  }

  /// 啟動全屏廣告計時器（5秒後自動退出）
  void _startFullscreenAdTimer() {
    _fullscreenAdTimer?.cancel();
    _fullscreenAdTimer = Timer(const Duration(seconds: 5), () {
      if (_currentState.currentAppState == AppState.fullscreenAd) {
        if (kDebugMode) {
          print('Fullscreen ad timer expired (5s), switching to default state');
        }
        enterDefaultState();
      }
    });
  }

  /// 啟動手動操作計時器（10秒後進入全屏廣告）
  void _startManualOperationTimer() {
    _manualOperationTimer?.cancel();
    _manualOperationTimer = Timer(const Duration(seconds: 10), () {
      if (_currentState.currentAppState == AppState.manualOperation) {
        if (kDebugMode) {
          print(
              'Manual operation timer expired (10s), switching to fullscreen ad');
        }
        enterFullscreenAd();
      }
    });
  }

  /// 重置手動操作計時器
  void _resetManualOperationTimer() {
    if (_currentState.currentAppState == AppState.manualOperation) {
      _startManualOperationTimer();
    }
  }

  /// 啟動默認狀態計時器（20秒後進入全屏廣告）
  void _startDefaultStateTimer() {
    _defaultStateTimer?.cancel();
    _defaultStateTimer = Timer(const Duration(seconds: 20), () {
      if (_currentState.currentAppState == AppState.defaultState) {
        if (kDebugMode) {
          print(
              'Default state timer expired (20s), switching to fullscreen ad');
        }
        enterFullscreenAd();
      }
    });
  }

  /// 清除所有計時器
  void _clearAllTimers() {
    _fullscreenAdTimer?.cancel();
    _manualOperationTimer?.cancel();
    _defaultStateTimer?.cancel();
  }

  /// 檢查是否可以轉換到指定狀態
  bool canTransitionTo(AppState targetState) {
    return _currentState.canTransitionTo(targetState);
  }

  /// 嘗試狀態轉換，返回是否成功
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
      if (kDebugMode) {
        print('State transition failed: $e');
      }
      return false;
    }
  }

  /// 重置到默認狀態（強制重置，忽略轉換規則）
  void resetToDefault() {
    _clearAllTimers();
    _currentState = DefaultCarouselState();
    _lastFullscreenAdEndTime = DateTime.now();
    _startDefaultStateTimer();
    notifyListeners();
    if (kDebugMode) {
      print('Force reset to default state');
    }
  }

  /// 獲取狀態描述（用於調試）
  String getStateDescription() {
    final now = DateTime.now();
    String timerInfo = '';

    switch (_currentState.currentAppState) {
      case AppState.fullscreenAd:
        timerInfo = 'Fullscreen ad timer: active (5s timeout)';
        break;
      case AppState.manualOperation:
        if (_lastUserInteractionTime != null) {
          final timeSinceInteraction =
              now.difference(_lastUserInteractionTime!).inSeconds;
          timerInfo =
              'Manual operation timer: ${10 - timeSinceInteraction}s remaining';
        }
        break;
      case AppState.defaultState:
        if (_lastFullscreenAdEndTime != null) {
          final timeSinceAdEnd =
              now.difference(_lastFullscreenAdEndTime!).inSeconds;
          timerInfo = 'Default state timer: ${20 - timeSinceAdEnd}s remaining';
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

  /// 釋放資源
  @override
  void dispose() {
    _clearAllTimers();
    super.dispose();
  }
}
