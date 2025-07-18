import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:iboard_app/models/settings_model.dart';

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

  // 计时器相關
  Timer? _fullscreenAdTimer; // 全屏廣告計時器
  Timer? _manualOperationTimer; // 手動操作計時器
  Timer? _defaultStateTimer; // 默認狀態計時器(spareDuration)

  // 時間記錄
  DateTime? _lastUserInteractionTime; // 最後用戶操作時間
  DateTime? _lastFullscreenAdEndTime; // 最後全屏廣告結束時間

  // 回調函數
  VoidCallback? _onShowFullscreenAd; // 顯示全屏廣告的回調
  VoidCallback? _onCloseFullscreenAd; // 關閉全屏廣告的回調

  // 時間配置（從服務器獲取，帶默認值）
  Settings? _settings;

  // 默認時間配置（如果服務器配置不可用時使用）
  static const int _defaultFullscreenAdDuration = 10; // 默認全屏廣告播放時間（秒）
  static const int _defaultManualOperationTimeout = 20; // 默認手動操作超時時間（秒）
  static const int _defaultNoActivityTimeout = 20; // 默認無操作進入全屏廣告時間（秒）

  /// 更新時間配置
  void updateSettings(Settings? settings) {
    _settings = settings;
    if (kDebugMode) {
      print('CarouselStateProvider: Settings updated');
      if (settings != null) {
        print('✅ 動態時間設置成功！');
        print('- 全屏廣告播放時間: ${settings.advertisementPlayDuration}秒');
        print('- 公告輪播總時間: ${settings.noticePlayDuration}秒');
        print('- 每個公告停留時間: ${settings.noticeStayDuration}秒');
        print('- 無操作/手動操作超時時間: ${settings.spareDuration}秒');
        print('- 廣告更新間隔: ${settings.advertisementUpdateDuration}秒');
        print('- 公告更新間隔: ${settings.noticeUpdateDuration}秒');
      } else {
        print('⚠️ 使用默認時間配置');
      }
    }
  }

  /// 獲取全屏廣告播放時間（秒）
  int get fullscreenAdDuration =>
      _settings?.advertisementPlayDuration ?? _defaultFullscreenAdDuration;

  /// 獲取手動操作超時時間（秒） - 使用spareDuration
  int get manualOperationTimeout =>
      _settings?.spareDuration ?? _defaultManualOperationTimeout;

  /// 獲取無操作進入全屏廣告時間（秒） - 使用spareDuration
  int get noActivityTimeout =>
      _settings?.spareDuration ?? _defaultNoActivityTimeout;

  /// 獲取公告輪播總時間（秒） - 公告開啟輪播模式的時間總和
  int get noticePlayDuration => _settings?.noticePlayDuration ?? 20;

  /// 獲取每個公告停留時間（秒） - 每一個公告在輪播模式停留的時間
  int get noticeStayDuration => _settings?.noticeStayDuration ?? 5;

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
        print('✅ 進入全屏廣告狀態，啟動動態計時器: ${fullscreenAdDuration}秒');
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
        print('✅ 進入手動操作狀態，啟動動態計時器: ${manualOperationTimeout}秒');
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
        print('✅ 進入默認狀態，啟動動態計時器: ${noActivityTimeout}秒');
      }
    }
  }

  /// 用戶交互更新（重置手動操作計時器）
  void onUserInteraction() {
    if (_currentState.currentAppState == AppState.manualOperation) {
      _lastUserInteractionTime = DateTime.now();
      _resetManualOperationTimer();
      if (kDebugMode) {
        print('🔄 用戶交互檢測到，重置手動操作動態計時器: ${manualOperationTimeout}秒');
      }
    } else {
      // 如果不在手動狀態，切換到手動狀態
      enterManualOperation();
    }
  }

  /// 啟動全屏廣告計時器（使用配置的廣告播放時間）
  void _startFullscreenAdTimer() {
    _fullscreenAdTimer?.cancel();
    final duration = Duration(seconds: fullscreenAdDuration);
    _fullscreenAdTimer = Timer(duration, () {
      if (_currentState.currentAppState == AppState.fullscreenAd) {
        if (kDebugMode) {
          print('⏰ 全屏廣告動態計時器到期 (${fullscreenAdDuration}秒)，切換到默認狀態');
        }
        enterDefaultState();
      }
    });
  }

  /// 啟動手動操作計時器（使用配置的手動操作超時時間）
  void _startManualOperationTimer() {
    _manualOperationTimer?.cancel();
    final duration = Duration(seconds: manualOperationTimeout);
    _manualOperationTimer = Timer(duration, () {
      if (_currentState.currentAppState == AppState.manualOperation) {
        if (kDebugMode) {
          print('⏰ 手動操作動態計時器到期 (${manualOperationTimeout}秒)，切換到全屏廣告');
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

  /// 啟動默認狀態計時器（使用配置的無操作超時時間）
  void _startDefaultStateTimer() {
    _defaultStateTimer?.cancel();
    final duration = Duration(seconds: noActivityTimeout);
    _defaultStateTimer = Timer(duration, () {
      if (_currentState.currentAppState == AppState.defaultState) {
        if (kDebugMode) {
          print('⏰ 默認狀態動態計時器到期 (${noActivityTimeout}秒)，切換到全屏廣告');
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
      print('🔄 強制重置到默認狀態，啟動動態計時器: ${noActivityTimeout}秒');
    }
  }

  /// 獲取狀態描述（用於調試）
  String getStateDescription() {
    final now = DateTime.now();
    String timerInfo = '';

    switch (_currentState.currentAppState) {
      case AppState.fullscreenAd:
        timerInfo =
            'Fullscreen ad timer: active (${fullscreenAdDuration}s timeout)';
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

  /// 釋放資源
  @override
  void dispose() {
    _clearAllTimers();
    super.dispose();
  }
}
