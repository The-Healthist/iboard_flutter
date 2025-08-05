import 'dart:async';
import 'package:flutter/material.dart';
import 'package:iboard_app/managers/file_manager.dart';
import 'package:iboard_app/models/ad_model.dart';
import 'package:iboard_app/widgets/full_ad_widget.dart';
import 'package:logger/logger.dart';
import 'package:iboard_app/providers/app_data_provider.dart';
// import 'package:video_player/video_player.dart'; // 未使用的导入
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// 简化版全屏广告Provider
/// 参考顶部广告轮播逻辑实现
class FullscreenAdProvider extends ChangeNotifier {
  final Logger _logger = Logger();

  // 定时器管理
  Timer? _fullscreenTimer;
  Timer? _debugTimer;

  // 广告数据
  List<AdModel> _fullscreenAds = [];
  List<AdModel> _customOrderFullscreenAds = []; // 自定义顺序的全屏广告
  List<Widget> _adWidgets = [];
  List<dynamic>? _cachedOrderData; // 缓存的顺序配置数据

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
  Duration _expectendAdNeedAdd = Duration.zero; //
  Duration _adDuration = Duration.zero;

  // App数据提供者相关
  final AppDataProvider _appDataProvider;
  static const int _defaultFullscreenAdDuration = 10; // 默认全屏广告播放时间（秒）

  FullscreenAdProvider(this._appDataProvider) {
    _logger.i('FullscreenAdProvider initialized with AppDataProvider');
    _loadCustomOrder(); // 加载自定义顺序
  }

  // 视频播放进度记录
  Map<String, Duration> _videoProgressMap = {};

  // Getters
  List<AdModel> get fullscreenAds => _customOrderFullscreenAds.isNotEmpty
      ? _customOrderFullscreenAds
      : _fullscreenAds;
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

  ///1，设置自定义轮播全屏广告顺序
  Future<void> setCarouselList(List<AdModel> customOrderList) async {
    _customOrderFullscreenAds = List.from(customOrderList);
    await _saveCustomOrder();
    // _logger.i('🔄 设置自定义全屏广告轮播顺序: ${_customOrderFullscreenAds.length} 个广告');

    // 重新创建广告Widget
    _createAdWidgets();
    notifyListeners();
  }

  ///2，保存自定义顺序到缓存
  Future<void> _saveCustomOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final orderData = _customOrderFullscreenAds
          .map((ad) => {
                'id': ad.id,
                'title': ad.title,
                'order': _customOrderFullscreenAds.indexOf(ad),
              })
          .toList();
      await prefs.setString(
          'fullscreen_ad_carousel_order', json.encode(orderData));
      // _logger.i('💾 全屏广告轮播自定义顺序已保存到缓存');
    } catch (e) {
      _logger.e('保存全屏广告轮播顺序失败', error: e);
    }
  }

  ///3，从缓存加载自定义顺序
  Future<void> _loadCustomOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final orderString = prefs.getString('fullscreen_ad_carousel_order');
      if (orderString != null) {
        final orderData = json.decode(orderString) as List;
        // 保存顺序配置，等待API数据到达后再应用
        _cachedOrderData = orderData;
        _logger.i('📂 从缓存加载全屏广告轮播自定义顺序: ${orderData.length} 个配置');
      }
    } catch (e) {
      _logger.e('加载全屏广告轮播顺序失败', error: e);
    }
  }

  ///4，根据API数据更新自定义顺序（保持用户自定义的顺序）
  void updateFullscreenAdsWithCustomOrder(List<AdModel> newAds) {
    // 检查数据是否真的发生了变化，避免不必要的更新
    if (_areAdsListsEqual(_fullscreenAds, newAds)) {
      // _logger.d('📋 全屏广告数据未变化，跳过更新');
      return;
    }

    _fullscreenAds = newAds;

    // 如果有缓存的顺序配置且自定义顺序为空，应用缓存的顺序
    if (_customOrderFullscreenAds.isEmpty && _cachedOrderData != null) {
      _applyCachedOrder(newAds);
    } else if (_customOrderFullscreenAds.isEmpty) {
      // 如果没有自定义顺序，使用默认顺序
      _customOrderFullscreenAds = List.from(newAds);
    } else {
      // 有自定义顺序，需要智能更新
      _updateCustomOrderWithNewData(newAds);
    }

    _createAdWidgets();

    if (this.fullscreenAds.isNotEmpty &&
        _currentAdIndex >= this.fullscreenAds.length) {
      _currentAdIndex = 0;
    }

    _logger.i(
        '🔄 更新全屏广告轮播数据: 原始${newAds.length}个，自定义顺序${_customOrderFullscreenAds.length}个');
    notifyListeners();
  }

  ///5，智能更新自定义顺序列表
  void _updateCustomOrderWithNewData(List<AdModel> newAds) {
    // 创建新数据的ID映射
    final newAdsMap = {for (var item in newAds) item.id: item};

    // 移除已删除的广告
    _customOrderFullscreenAds
        .removeWhere((item) => !newAdsMap.containsKey(item.id));

    // 更新现有广告的数据
    for (int i = 0; i < _customOrderFullscreenAds.length; i++) {
      final currentId = _customOrderFullscreenAds[i].id;
      if (newAdsMap.containsKey(currentId)) {
        _customOrderFullscreenAds[i] = newAdsMap[currentId]!;
      }
    }

    // 添加新增的广告到末尾
    final existingIds =
        _customOrderFullscreenAds.map((item) => item.id).toSet();
    final newItems =
        newAds.where((item) => !existingIds.contains(item.id)).toList();
    _customOrderFullscreenAds.addAll(newItems);

    // 保存更新后的顺序
    _saveCustomOrder();

    _logger.i(
        '📝 智能更新自定义顺序: 移除${newAds.length - newAdsMap.length}个, 新增${newItems.length}个');
  }

  ///6，应用缓存的顺序配置
  void _applyCachedOrder(List<AdModel> newAds) {
    try {
      if (_cachedOrderData == null) return;

      // 创建API数据的ID映射
      final Map<int, AdModel> newAdsMap = {
        for (AdModel ad in newAds) ad.id: ad
      };

      // 按照缓存的顺序重新排列
      final List<AdModel> orderedAds = [];

      // 首先添加缓存顺序中存在的广告
      for (final orderItem in _cachedOrderData!) {
        final id = orderItem['id'] as int;
        if (newAdsMap.containsKey(id)) {
          orderedAds.add(newAdsMap[id]!);
          newAdsMap.remove(id); // 移除已处理的广告
        }
      }

      // 然后添加新增的广告（不在缓存顺序中的）
      orderedAds.addAll(newAdsMap.values);

      _customOrderFullscreenAds = orderedAds;

      // 保存更新后的顺序
      _saveCustomOrder();

      _logger.i('📋 应用缓存的全屏广告顺序: ${orderedAds.length}个广告');
    } catch (e) {
      _logger.e('应用缓存顺序失败，使用默认顺序', error: e);
      _customOrderFullscreenAds = List.from(newAds);
    }
  }

  ///6, 更新全屏广告数据
  void updateFullscreenAds(List<AdModel> newAds) {
    // 使用自定义顺序更新方法
    updateFullscreenAdsWithCustomOrder(newAds);
  }

  ///7, 创建广告Widget组件列表
  void _createAdWidgets() {
    _adWidgets = this.fullscreenAds.asMap().entries.map((entry) {
      return _createSingleAdWidget(entry.value, entry.key);
    }).toList();
    // _logger.i('📺 创建了 ${_adWidgets.length} 个广告Widget');
  }

  ///8, 创建单个广告Widget
  Widget _createSingleAdWidget(AdModel ad, int index) {
    final FileManager fileManager = FileManager();
    fileManager.getFile(ad.file);

    // 对于全屏广告，视频始终从头开始播放，不使用保存的进度
    Duration? initialPosition;

    return FullAdWidget(
      key: ValueKey('fullscreen_ad_${ad.id}_$index'),
      ad: ad,
      fileManager: fileManager,
      initialVideoPosition: initialPosition,
      onVideoProgressChanged: (adId, position) {
        // 对于全屏广告，不需要保存视频进度
        // 只在需要时保存图片广告的显示时间
        if (_currentAdIndex < this.fullscreenAds.length &&
            this.fullscreenAds[_currentAdIndex].id.toString() == adId) {
          final currentAd = getCurrentAd();
          if (currentAd != null &&
              currentAd.file.mimeType.startsWith('image/')) {
            saveVideoProgress(adId, position);
          }
        }
      },
      // onVideoDisposed: () => _logger.i('🎬 全屏广告 ${ad.id} 资源已释放'),
    );
  }

  ///9, 进入全屏广告模式并开始轮播
  void enterFullscreenMode() {
    if (_isActive) return;

    _isActive = true;
    _isPaused = false;
    _currentAdPauseTime = null;

    if (this.fullscreenAds.isNotEmpty) {
      // 确保当前索引在有效范围内
      if (_currentAdIndex < 0 || _currentAdIndex >= this.fullscreenAds.length) {
        _logger.w('⚠️ 修正无效的广告索引: $_currentAdIndex → 0');
        _currentAdIndex = 0;
      }

      _createAdWidgets();
      startFullscreenAdTimer(_currentAdIndex);
      startDebugTimer();
      _currentStateStartTime = DateTime.now();
      _logger.i(
          '🚀 进入全屏广告模式: 索引=$_currentAdIndex, 总数=${this.fullscreenAds.length}');
    }

    notifyListeners();
  }

  ///10, 启动全屏广告计时器 - 添加视频切换延迟
  void startFullscreenAdTimer(int currentIndex) {
    // _logger.d(
    //     '🎬 开始全屏广告计时器: index=$currentIndex, ads=${this.fullscreenAds.length}, paused=$_isPaused');
    _fullscreenTimer?.cancel(); // 取消之前的计时器

    // 改进的边界检查逻辑
    if (this.fullscreenAds.isEmpty) {
      _logger.w('⚠️ 全屏广告列表为空，无法启动计时器');
      return;
    }

    if (currentIndex < 0 || currentIndex >= this.fullscreenAds.length) {
      _logger.w(
          '⚠️ 广告索引越界: $currentIndex (有效范围: 0-${this.fullscreenAds.length - 1})');
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

    final ad = this.fullscreenAds[currentIndex];
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
      _logger.i(
          '⏰ 启动标准广告计时器: ${fullscreenAdDuration}秒 (索引: $_currentAdIndex/${this.fullscreenAds.length})');
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
    if (this.fullscreenAds.isEmpty || _isPaused || !_isActive) {
      _logger.w(
          '⚠️ _nextAd被阻止: isEmpty=${this.fullscreenAds.isEmpty}, paused=$_isPaused, active=$_isActive');
      return;
    }

    // final oldIndex = _currentAdIndex; // 注释掉因为日志被注释了
    // 切换到下一个广告 - 使用模运算确保循环
    _currentAdIndex = (_currentAdIndex + 1) % this.fullscreenAds.length;

    // 额外的安全检查
    _validateAndFixIndex();

    // _logger.i(
    //     '🔄 全屏广告切换: $oldIndex → $_currentAdIndex (总数: ${this.fullscreenAds.length})');

    // 重置时间记录
    _adElapsedTime = Duration.zero;
    _expectedAdElapsedTime = Duration.zero;
    _currentAdPauseTime = null;

    notifyListeners();

    // 添加小延迟，让前一个视频有时间完全释放资源
    Future.delayed(Duration(milliseconds: 300), () {
      if (_isActive && !_isPaused) {
        startFullscreenAdTimer(_currentAdIndex);
      }
    });
  }

  ///25, 验证并修正广告索引
  void _validateAndFixIndex() {
    if (this.fullscreenAds.isEmpty) {
      _currentAdIndex = 0;
      return;
    }

    if (_currentAdIndex < 0) {
      _logger.w('⚠️ 索引小于0，修正为0: $_currentAdIndex → 0');
      _currentAdIndex = 0;
    } else if (_currentAdIndex >= this.fullscreenAds.length) {
      _logger.w(
          '⚠️ 索引越界，修正为0: $_currentAdIndex → 0 (总数: ${this.fullscreenAds.length})');
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
    if (this.fullscreenAds.isNotEmpty && _currentAdStartTime != null) {
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
        Future.delayed(Duration(milliseconds: 100), () {
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
    if (this.fullscreenAds.isNotEmpty) {
      _currentAdIndex = (_currentAdIndex + 1) % this.fullscreenAds.length;
      // _logger.i('🔄 广告索引更新为下一个: $_currentAdIndex');
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
    if (_currentAdIndex >= this.fullscreenAds.length) return null;
    return this.fullscreenAds[_currentAdIndex];
  }

  ///23, 获取当前播放的Widget
  Widget? getCurrentWidget() {
    if (_currentAdIndex >= _adWidgets.length) return null;
    return _adWidgets[_currentAdIndex];
  }

  ///26，比较两个广告列表是否相等
  bool _areAdsListsEqual(List<AdModel> list1, List<AdModel> list2) {
    if (list1.length != list2.length) return false;

    for (int i = 0; i < list1.length; i++) {
      if (list1[i].id != list2[i].id ||
          list1[i].title != list2[i].title ||
          list1[i].updatedAt != list2[i].updatedAt) {
        return false;
      }
    }
    return true;
  }

  @override
  void dispose() {
    _fullscreenTimer?.cancel();
    _fullscreenTimer = null;

    _debugTimer?.cancel();
    _debugTimer = null;

    super.dispose();
  }
}
