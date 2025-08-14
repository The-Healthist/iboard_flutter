import 'dart:async';
import 'package:flutter/material.dart';
import 'package:iboard_app/managers/file_manager.dart';
import 'package:iboard_app/models/ad_model.dart';
import 'package:iboard_app/widgets/carousel_widget.dart' as custom_carousel;
import 'package:iboard_app/widgets/mainscreen/top_ad_widget.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

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
  List<AdModel> _customOrderTopAds = []; // 自定义顺序的顶部广告
  List<dynamic>? _cachedOrderData; // 缓存的顺序配置数据

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
  List<AdModel> get topAds =>
      _customOrderTopAds.isNotEmpty ? _customOrderTopAds : _topAds;
  bool get isTopCarouselPaused => _isTopCarouselPaused;
  Duration get topAdDuration => _topAdDuration;
  int get currentTopAdIndex => _currentTopAdIndex;
  DateTime? get currentTopAdStartTime => _currentTopAdStartTime;
  Duration get topAdElapsedTime => _topAdElapsedTime;

  TopAdCarouselProvider() {
    _topCarouselController = custom_carousel.CarouselController();
    _loadCustomOrder(); // 加载自定义顺序
    // 添加调试日志
    Future.delayed(Duration(seconds: 2), () {
      _logger.i(
          '🔍 TopAdCarouselProvider 初始化完成，缓存数据: ${_cachedOrderData?.length ?? 0}个配置');
    });
  }

  ///1，设置自定义轮播顶部广告顺序
  Future<void> setCarouselList(List<AdModel> customOrderList) async {
    _customOrderTopAds = List.from(customOrderList);
    await _saveCustomOrder();
    // _logger.i('🔄 设置自定义顶部广告轮播顺序: ${_customOrderTopAds.length} 个广告');
    notifyListeners();
  }

  ///2，保存自定义顺序到缓存
  Future<void> _saveCustomOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final orderData = _customOrderTopAds
          .map((ad) => {
                'id': ad.id,
                'title': ad.title,
                'order': _customOrderTopAds.indexOf(ad),
              })
          .toList();
      await prefs.setString('top_ad_carousel_order', json.encode(orderData));
      // _logger.i('💾 顶部广告轮播自定义顺序已保存到缓存');
    } catch (e) {
      _logger.e('保存顶部广告轮播顺序失败', error: e);
    }
  }

  ///3，从缓存加载自定义顺序
  Future<void> _loadCustomOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final orderString = prefs.getString('top_ad_carousel_order');
      if (orderString != null) {
        final orderData = json.decode(orderString) as List;
        // 保存顺序配置，等待API数据到达后再应用
        _cachedOrderData = orderData;
        _logger.i('📂 从缓存加载顶部广告轮播自定义顺序: ${orderData.length} 个配置');
      }
    } catch (e) {
      _logger.e('加载顶部广告轮播顺序失败', error: e);
    }
  }

  ///4，根据API数据更新自定义顺序（保持用户自定义的顺序）
  void updateTopAdsWithCustomOrder(List<AdModel> newTopAds) {
    _topAds = newTopAds;

    _logger.i(
        '🔄 开始更新顶部广告轮播数据: API数据${newTopAds.length}个，当前自定义顺序${_customOrderTopAds.length}个，缓存配置${_cachedOrderData?.length ?? 0}个');

    // 如果有缓存的顺序配置且自定义顺序为空，应用缓存的顺序
    if (_customOrderTopAds.isEmpty && _cachedOrderData != null) {
      _logger.i('📋 应用缓存的顶部广告顺序配置');
      _applyCachedOrder(newTopAds);
    } else if (_customOrderTopAds.isEmpty) {
      // 如果没有自定义顺序，使用默认顺序
      _logger.i('📋 使用默认的顶部广告顺序');
      _customOrderTopAds = List.from(newTopAds);
    } else {
      // 有自定义顺序，需要智能更新
      _logger.i('📋 智能更新顶部广告自定义顺序');
      _updateCustomOrderWithNewData(newTopAds);
    }

    _logger.i(
        '🔄 更新顶部广告轮播数据完成: 原始${newTopAds.length}个，自定义顺序${_customOrderTopAds.length}个');
  }

  ///5，智能更新自定义顺序列表
  void _updateCustomOrderWithNewData(List<AdModel> newTopAds) {
    // 创建新数据的ID映射
    final newAdsMap = {for (var item in newTopAds) item.id: item};

    // 移除已删除的广告
    _customOrderTopAds.removeWhere((item) => !newAdsMap.containsKey(item.id));

    // 更新现有广告的数据
    for (int i = 0; i < _customOrderTopAds.length; i++) {
      final currentId = _customOrderTopAds[i].id;
      if (newAdsMap.containsKey(currentId)) {
        _customOrderTopAds[i] = newAdsMap[currentId]!;
      }
    }

    // 添加新增的广告到末尾
    final existingIds = _customOrderTopAds.map((item) => item.id).toSet();
    final newItems =
        newTopAds.where((item) => !existingIds.contains(item.id)).toList();
    _customOrderTopAds.addAll(newItems);

    // 保存更新后的顺序
    _saveCustomOrder();

    _logger.i(
        '📝 智能更新自定义顺序: 移除${newTopAds.length - newAdsMap.length}个, 新增${newItems.length}个');
  }

  ///6，应用缓存的顺序配置
  void _applyCachedOrder(List<AdModel> newTopAds) {
    try {
      if (_cachedOrderData == null) return;

      // 创建API数据的ID映射
      final Map<int, AdModel> newAdsMap = {
        for (AdModel ad in newTopAds) ad.id: ad
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

      _customOrderTopAds = orderedAds;

      // 保存更新后的顺序
      _saveCustomOrder();

      _logger.i('📋 应用缓存的顶部广告顺序: ${orderedAds.length}个广告');
    } catch (e) {
      _logger.e('应用缓存顺序失败，使用默认顺序', error: e);
      _customOrderTopAds = List.from(newTopAds);
    }
  }

  ///7，初始化顶部轮播
  void initializeTopWidgets(List<AdModel> topAds) {
    if (topAds.isEmpty) {
      _logger.w('No top advertisements available');
      return;
    }

    // 使用自定义顺序更新方法
    updateTopAdsWithCustomOrder(topAds);

    // Create ad widgets from the API AdModel instances
    List<Widget> adWidgets = this.topAds.map((ad) {
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

    if (this.topAds.length > 1) {
      startTopAdTimer(0); // Start timer for the first ad
    }

    // _logger.i('🎬 [初始化] 顶部广告轮播初始化完成，广告数量: ${this.topAds.length}');
  }

  ///7，启动顶部广告计时器
  void startTopAdTimer(int currentIndex) {
    _logger.d(
        '🎬 开始顶部广告计时器: index=$currentIndex, ads=${this.topAds.length}, paused=$_isTopCarouselPaused');
    _topTimer?.cancel();
    if (this.topAds.length <= 1 ||
        currentIndex < 0 ||
        currentIndex >= this.topAds.length ||
        _isTopCarouselPaused) {
      _logger.w(
          '⚠️ 顶部广告计时器条件不满足: ads=${this.topAds.length}, index=$currentIndex, paused=$_isTopCarouselPaused');
      return;
    }

    final ad = this.topAds[currentIndex];
    // 记录当前广告开始时间和总时长
    _currentTopAdStartTime = DateTime.now();
    _topAdDuration = ad.durationObject;
    _currentTopAdIndex = currentIndex;

    // 只有当切换到新广告时才重置已播放时间
    _topAdElapsedTime = Duration.zero;

    // _logger.d('▶️ 启动顶部广告计时器: ${ad.title}, duration=${ad.durationObject}');
    // _logger.i(
    //     '📝 记录顶部广告开始时间: $_currentTopAdStartTime, 索引: $_currentTopAdIndex, 时长: ${_topAdDuration.inSeconds}秒');

    _topTimer = Timer(ad.durationObject, () {
      if (_topCarouselController.widgetCount > 1 && !_isTopCarouselPaused) {
        // _logger.d('⏭️ 顶部广告计时器到期，切换到下一个');
        _topCarouselController.playNext();
        // onPageChanged will then call startTopAdTimer for the new page
      }
    });
  }

  /// 暂停顶部轮播
  void pauseTopCarousel() {
    // _logger.i('🛑 暂停顶部轮播 - 进入全屏广告状态');

    // 记录当前播放时间
    _currentTopAdPauseTime = DateTime.now();

    // 计算已播放时间
    if (_currentTopAdStartTime != null) {
      final rawElapsed =
          _currentTopAdPauseTime!.difference(_currentTopAdStartTime!);
      // 加上之前的已播放时间（如果有的话）
      final totalElapsed = rawElapsed + _topAdElapsedTime;

      // 确保已播放时间不超过广告总时长
      if (totalElapsed >= _topAdDuration) {
        // 广告已经播放完成，应该准备切换到下一个
        _topAdElapsedTime = _topAdDuration;
        final remainingTop = Duration.zero;
        // _logger.i(
        //     '📊 [暂停] 顶部广告 - 已播放: ${_topAdElapsedTime.inSeconds}s/${_topAdDuration.inSeconds}s, 剩余: ${remainingTop.inSeconds}s (广告已完成)');
      } else {
        // 广告还在播放中
        _topAdElapsedTime = totalElapsed;
        final remainingTop = _topAdDuration - _topAdElapsedTime;
        // _logger.i(
        //     '📊 [暂停] 顶部广告 - 已播放: ${_topAdElapsedTime.inSeconds}s/${_topAdDuration.inSeconds}s, 剩余: ${remainingTop.inSeconds}s');
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
    // _logger.i('▶️ 恢复顶部轮播 - 退出全屏广告状态');

    // 设置顶部轮播为运行状态
    _isTopCarouselPaused = false;

    // 恢复轮播中的媒体内容
    _topCarouselController.resumeAllMedia();

    // 计算剩余播放时间并恢复定时器
    if (_topAds.isNotEmpty) {
      // 如果 _currentTopAdStartTime 为空，说明需要重新初始化
      if (_currentTopAdStartTime == null) {
        // 重新初始化当前广告的开始时间和时长
        final currentIndex = _topCarouselController.currentIndex;
        if (currentIndex < _topAds.length) {
          _currentTopAdStartTime = DateTime.now();
          _topAdDuration = _topAds[currentIndex].durationObject;
          _currentTopAdIndex = currentIndex;
          _topAdElapsedTime = Duration.zero;

          // 启动新的定时器
          _topTimer = Timer(_topAdDuration, () {
            if (!_isTopCarouselPaused) {
              // _logger.i('⏰ [定时] 顶部广告时间到，切换到下一个');
              _topCarouselController.playNext();
              // Note: onPageChanged will handle calling startTopAdTimer for the new page
            }
          });

          _logger.i('✅ 顶部广告轮播已恢复：重新初始化定时器，当前索引: $currentIndex');
        }
      } else {
        // 原有的恢复逻辑
        final remainingTopTime = _topAdDuration - _topAdElapsedTime;
        // _logger.i(
        //     '🔄 [恢复] 顶部广告 - 继续播放剩余时间：${remainingTopTime.inSeconds}s (已播放: ${_topAdElapsedTime.inSeconds}s)');

        if (remainingTopTime.inSeconds > 0) {
          // 更新当前广告开始时间，使其能正确计算剩余时间
          _currentTopAdStartTime = DateTime.now();
          // 保持 _topAdElapsedTime 不变，这样调试定时器能正确显示从暂停位置继续的时间

          // 继续播放剩余时间
          _topTimer = Timer(remainingTopTime, () {
            if (!_isTopCarouselPaused) {
              // _logger.i('⏰ [定时] 顶部广告时间到，切换到下一个');
              _topCarouselController.playNext();
              // Note: onPageChanged will handle calling startTopAdTimer for the new page
            }
          });

          _logger.i('✅ 顶部广告轮播已恢复：继续播放剩余时间 ${remainingTopTime.inSeconds}s');
        } else {
          // 时间已到，直接切换到下一个
          // _logger.i('⚡ [跳过] 顶部广告剩余时间为0，直接切换到下一个');
          _topCarouselController.playNext();
          // Note: onPageChanged will handle calling startTopAdTimer for the new page

          _logger.i('✅ 顶部广告轮播已恢复：时间已到，切换到下一个广告');
        }
      }
    }

    notifyListeners();
  }

  /// 更新轮播暂停状态
  void updateCarouselPauseState(bool isPaused) {
    _isTopCarouselPaused = isPaused;
    // _logger.i('🎛️ 顶部轮播状态更新: ${!_isTopCarouselPaused ? "运行" : "暂停"}');
    notifyListeners();
  }

  ///8，检查并恢复轮播状态（监控定时器使用）
  void checkAndRestoreTopCarousel() {
    _logger.i(
        '🔍 检查顶部广告恢复条件: ads=${this.topAds.length}, paused=$_isTopCarouselPaused');
    if (this.topAds.isNotEmpty && !_isTopCarouselPaused) {
      // 检查当前定时器是否活跃
      if (_topTimer == null || !_topTimer!.isActive) {
        _logger.w('🔧 检测到顶部广告轮播中断，尝试恢复...');
        final currentIndex = _topCarouselController.currentIndex;
        // _logger.i('🔄 恢复顶部广告轮播，当前索引: $currentIndex');

        // 恢复视频播放
        _topCarouselController.resumeAllMedia();

        // 恢复定时器
        startTopAdTimer(currentIndex);

        _logger.i('✅ 顶部广告轮播已恢复：视频播放 + 定时器');
      }
    } else {
      _logger.w(
          '❌ 不满足恢复条件: ads=${this.topAds.length}, paused=$_isTopCarouselPaused');
    }
  }

  /// 启动调试定时器 - 每秒输出顶部广告的实时状态（已禁用）
  void startDebugTimer() {
    _debugTimer?.cancel();
    // 禁用顶部广告调试定时器以减少日志输出
    return;

    // _debugTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
    //   // 计算顶部广告剩余时间
    //   int topAdRemaining = 0;
    //   if (_currentTopAdStartTime != null) {
    //     if (_isTopCarouselPaused) {
    //       // 暂停状态：使用暂停时的剩余时间
    //       final remaining = _topAdDuration - _topAdElapsedTime;
    //       topAdRemaining = remaining.isNegative ? 0 : remaining.inSeconds;
    //     } else {
    //       // 运行状态：计算当前剩余时间
    //       final currentElapsed =
    //           DateTime.now().difference(_currentTopAdStartTime!);

    //       // 如果有已播放时间记录（说明经历了暂停恢复），需要加上之前的播放时间
    //       final totalElapsed = currentElapsed + _topAdElapsedTime;

    //       final remaining = _topAdDuration - totalElapsed;
    //       topAdRemaining = remaining.isNegative ? 0 : remaining.inSeconds;
    //     }
    //   }

    //   // 输出调试信息
    //   String statusInfo = '';
    //   if (_isTopCarouselPaused) {
    //     statusInfo = ' [暂停状态]';
    //   }

    //   _logger.i(
    //       '🕐 [调试] 顶部广告: ${topAdRemaining}s/${_topAdDuration.inSeconds}s$statusInfo');
    // });
  }

  /// 停止调试定时器
  void stopDebugTimer() {
    _debugTimer?.cancel();
  }

  ///9，处理页面变化事件
  void onPageChanged(int index) {
    if (!_isTopCarouselPaused && this.topAds.isNotEmpty) {
      startTopAdTimer(index);
    }
  }

  /// 暂停所有计时器（用于设置页面）
  void pauseAllTimersForSettings() {
    // _logger.i('⚙️ 顶部广告 - 暂停所有计时器（设置页面）');
    _topTimer?.cancel();
    _debugTimer?.cancel();
    _topCarouselController.pauseAllMedia();
    _isTopCarouselPaused = true;
    notifyListeners();
  }

  /// 从设置页面恢复所有计时器
  void resumeAllTimersFromSettings() {
    // _logger.i('↩️ 顶部广告 - 从设置页面恢复所有计时器');
    _isTopCarouselPaused = false;
    _topCarouselController.resumeAllMedia();

    // 恢复顶部广告轮播
    if (this.topAds.isNotEmpty) {
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
    _topTimer = null;

    _debugTimer?.cancel();
    _debugTimer = null;

    super.dispose();
  }
}
