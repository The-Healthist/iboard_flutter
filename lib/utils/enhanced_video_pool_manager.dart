import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:logger/logger.dart';

/// 视频类型枚举
enum VideoType {
  topAd, // 顶部广告视频
  fullAd, // 全屏广告视频
}

/// 增强版视频池管理器
/// 为每个视频文件+类型组合创建独立控制器，支持同一视频在不同场景下同时播放
class EnhancedVideoPoolManager {
  static final Logger _logger = Logger();
  static EnhancedVideoPoolManager? _instance;

  // 控制器池 - 按 "视频类型:文件路径" 为键
  final Map<String, VideoPlayerController> _controllerPool = {};
  final Map<String, DateTime> _lastUsed = {}; // 最后使用时间
  final Map<String, bool> _isInUse = {}; // 是否正在使用中

  // 池配置
  static const int _maxPoolSize = 10; // 最大池大小（你要求的10个以内）
  static const Duration _unusedCheckInterval = Duration(minutes: 5); // 检查间隔

  Timer? _cleanupTimer;

  EnhancedVideoPoolManager._internal() {
    // 启动定期检查任务（不是清理，而是维护）
    _startMaintenanceTimer();
  }

  factory EnhancedVideoPoolManager() {
    _instance ??= EnhancedVideoPoolManager._internal();
    return _instance!;
  }

  ///1，启动定期维护任务（检查池状态，但不强制清理）
  void _startMaintenanceTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(_unusedCheckInterval, (timer) {
      _performMaintenance();
    });
  }

  ///2，获取或创建视频控制器（为特定类型和文件）
  Future<VideoPlayerController?> getController({
    required String filePath,
    required VideoType videoType,
    bool isNetwork = false,
    bool autoPlay = true,
    bool looping = true,
    VoidCallback? onError,
  }) async {
    try {
      // 生成唯一键：类型 + 网络标识 + 文件路径
      final key = _generateKey(filePath, videoType, isNetwork);

      // 检查池中是否已有该控制器
      if (_controllerPool.containsKey(key)) {
        final controller = _controllerPool[key]!;

        // 验证控制器状态
        if (_isControllerValid(controller)) {
          // _logger.i(
          //     '🔄 [增强视频池] 复用现有控制器: ${_getDisplayKey(videoType, filePath)} (池大小: ${_controllerPool.length}/${_maxPoolSize})');
          _isInUse[key] = true;
          _lastUsed[key] = DateTime.now();

          // 重置播放设置
          await _resetControllerSettings(controller, autoPlay, looping);
          return controller;
        } else {
          // 控制器无效，重新创建
          // _logger.w(
          //     '⚠️ [增强视频池] 控制器无效，重新创建: ${_getDisplayKey(videoType, filePath)}');
          await _removeFromPool(key);
        }
      }

      // 检查池大小，如果接近上限则清理最老的未使用控制器
      if (_controllerPool.length >= _maxPoolSize) {
        await _evictOldestUnusedController();
      }

      // 创建新的控制器
      final controller = await _createNewController(
        filePath: filePath,
        isNetwork: isNetwork,
        autoPlay: autoPlay,
        looping: looping,
        onError: onError,
      );

      if (controller != null) {
        _controllerPool[key] = controller;
        _isInUse[key] = true;
        _lastUsed[key] = DateTime.now();
        // _logger.i(
        //     '✅ [增强视频池] 创建新控制器: ${_getDisplayKey(videoType, filePath)} (池大小: ${_controllerPool.length}/${_maxPoolSize})');

        // 定期打印池状态（每5个控制器打印一次）
        if (_controllerPool.length % 5 == 0) {
          debugPrintPoolStatus();
        }
      }

      return controller;
    } catch (e) {
      // _logger.e('❌ [增强视频池] 获取控制器失败: $e');
      return null;
    }
  }

  ///3，释放控制器（标记为未使用，但不销毁）
  Future<void> releaseController({
    required String filePath,
    required VideoType videoType,
    bool isNetwork = false,
  }) async {
    final key = _generateKey(filePath, videoType, isNetwork);

    if (_controllerPool.containsKey(key)) {
      _isInUse[key] = false;
      _lastUsed[key] = DateTime.now();

      // _logger.d(
      //     '📤 [增强视频池] 释放控制器: ${_getDisplayKey(videoType, filePath)} (保留在池中)');

      // 暂停播放但保留控制器
      final controller = _controllerPool[key];
      if (controller != null) {
        try {
          if (controller.value.isInitialized && controller.value.isPlaying) {
            await controller.pause();
          }
        } catch (e) {
          // _logger.w('⚠️ [增强视频池] 暂停控制器失败: $e');
        }
      }
    }
  }

  ///4，更新视频列表（根据广告列表动态管理控制器）
  Future<void> updateVideoList({
    required List<String> topAdVideos,
    required List<String> fullAdVideos,
    bool isNetwork = false,
  }) async {
    // _logger.i(
    //     '🔄 [增强视频池] 更新视频列表: 顶部${topAdVideos.length}个, 全屏${fullAdVideos.length}个');

    // 构建需要的控制器键集合
    final neededKeys = <String>{};

    // 为顶部广告视频添加键
    for (final videoPath in topAdVideos) {
      neededKeys.add(_generateKey(videoPath, VideoType.topAd, isNetwork));
    }

    // 为全屏广告视频添加键
    for (final videoPath in fullAdVideos) {
      neededKeys.add(_generateKey(videoPath, VideoType.fullAd, isNetwork));
    }

    // 移除不再需要的控制器
    final keysToRemove = <String>[];
    for (final key in _controllerPool.keys) {
      if (!neededKeys.contains(key) && !(_isInUse[key] ?? false)) {
        keysToRemove.add(key);
      }
    }

    for (final key in keysToRemove) {
      await _removeFromPool(key);
      // _logger.i('🗑️ [增强视频池] 移除不需要的控制器: $key');
    }

    // _logger.i('✅ [增强视频池] 列表更新完成，当前池大小: ${_controllerPool.length}');
  }

  ///5，创建新的视频控制器
  Future<VideoPlayerController?> _createNewController({
    required String filePath,
    bool isNetwork = false,
    bool autoPlay = true,
    bool looping = true,
    VoidCallback? onError,
  }) async {
    try {
      VideoPlayerController controller;

      if (isNetwork) {
        controller = VideoPlayerController.networkUrl(Uri.parse(filePath));
      } else {
        controller = VideoPlayerController.file(File(filePath));
      }

      // 添加错误监听
      controller.addListener(() {
        if (controller.value.hasError) {
          // _logger.e('🔴 [增强视频池] 播放错误: ${controller.value.errorDescription}');
          onError?.call();
        }
      });

      await controller.initialize();

      if (looping) {
        controller.setLooping(looping);
      }

      if (autoPlay) {
        await controller.play();
      }

      return controller;
    } catch (e) {
      // _logger.e('❌ [增强视频池] 创建控制器失败: $e');
      onError?.call();
      return null;
    }
  }

  ///6，重置控制器设置
  Future<void> _resetControllerSettings(
    VideoPlayerController controller,
    bool autoPlay,
    bool looping,
  ) async {
    try {
      if (controller.value.isInitialized) {

        // 重置到开头
        await controller.seekTo(Duration.zero);

        // 设置循环
        controller.setLooping(looping);

        // 根据需要播放或暂停
        if (autoPlay && !controller.value.isPlaying) {
          await controller.play();
          // _logger.d('🎬 [增强视频池] 开始播放复用的控制器');
        } else if (!autoPlay && controller.value.isPlaying) {
          await controller.pause();
          // _logger.d('⏸️ [增强视频池] 暂停复用的控制器');
        }
      } else {
        // _logger.w('⚠️ [增强视频池] 控制器未初始化，无法重置设置');
      }
    } catch (e) {
      // _logger.w('⚠️ [增强视频池] 重置控制器设置失败: $e');
    }
  }

  ///7，检查控制器是否有效
  bool _isControllerValid(VideoPlayerController controller) {
    try {
      // 只要控制器初始化过且没有错误就认为有效
      // 不管当前是否在播放状态
      bool isValid =
          controller.value.isInitialized && !controller.value.hasError;

      if (!isValid) {
        // _logger.w(
        //     '⚠️ [增强视频池] 控制器验证失败 - 已初始化: ${controller.value.isInitialized}, 有错误: ${controller.value.hasError}');
      }

      return isValid;
    } catch (e) {
      // _logger.w('⚠️ [增强视频池] 控制器验证异常: $e');
      return false;
    }
  }

  ///8，生成控制器唯一键
  String _generateKey(String filePath, VideoType videoType, bool isNetwork) {
    final typePrefix = videoType == VideoType.topAd ? 'top' : 'full';
    final networkPrefix = isNetwork ? 'net' : 'file';
    return '${typePrefix}_$networkPrefix:$filePath';
  }

  ///9，获取显示用的键（用于日志）
  String _getDisplayKey(VideoType videoType, String filePath) {
    final typeStr = videoType == VideoType.topAd ? '顶部' : '全屏';
    final fileName = filePath.split('/').last;
    return '$typeStr:$fileName';
  }

  ///10，执行定期维护（检查状态，不强制清理）
  void _performMaintenance() {
    int unusedCount = 0;

    for (final entry in _isInUse.entries) {
      if (!entry.value) {
        unusedCount++;
      }
    }

    // _logger
    //     .d('🔧 [增强视频池] 维护检查: 总数${_controllerPool.length}, 未使用${unusedCount}');

    // 只有在池满且有很多未使用的控制器时才考虑清理
    if (_controllerPool.length >= _maxPoolSize &&
        unusedCount > _maxPoolSize ~/ 2) {
      // _logger.i('💡 [增强视频池] 池接近满载，可能需要清理一些长期未使用的控制器');
    }
  }

  ///11，淘汰最老的未使用控制器（仅在必要时）
  Future<void> _evictOldestUnusedController() async {
    String? oldestKey;
    DateTime? oldestTime;

    for (final entry in _lastUsed.entries) {
      final key = entry.key;
      final lastUsed = entry.value;
      final inUse = _isInUse[key] ?? false;

      if (!inUse && (oldestTime == null || lastUsed.isBefore(oldestTime))) {
        oldestTime = lastUsed;
        oldestKey = key;
      }
    }

    if (oldestKey != null) {
      // _logger.i('🗑️ [增强视频池] 池满，淘汰最老的未使用控制器: $oldestKey');
      await _removeFromPool(oldestKey);
    }
  }

  ///12，从池中移除控制器
  Future<void> _removeFromPool(String key) async {
    final controller = _controllerPool.remove(key);
    _isInUse.remove(key);
    _lastUsed.remove(key);

    if (controller != null) {
      try {
        // 停止播放
        if (controller.value.isInitialized && controller.value.isPlaying) {
          await controller.pause();
        }

        // 等待一小段时间确保状态稳定
        await Future.delayed(const Duration(milliseconds: 100));

        // 释放资源
        controller.dispose();
        // _logger.d('🗑️ [增强视频池] 控制器已释放: $key');
      } catch (e) {
        // _logger.e('❌ [增强视频池] 释放控制器失败: $e');
      }
    }
  }

  ///13，获取池状态信息
  Map<String, dynamic> getPoolStatus() {
    final inUseCount = _isInUse.values.where((inUse) => inUse).length;
    final availableCount = _controllerPool.length - inUseCount;

    return {
      'totalSize': _controllerPool.length,
      'maxSize': _maxPoolSize,
      'inUse': inUseCount,
      'available': availableCount,
      'controllers': _controllerPool.keys.toList(),
      'usageStatus': Map.from(_isInUse),
    };
  }

  ///14，强制清理指定控制器
  Future<void> forceRemoveController({
    required String filePath,
    required VideoType videoType,
    bool isNetwork = false,
  }) async {
    final key = _generateKey(filePath, videoType, isNetwork);
    if (_controllerPool.containsKey(key)) {
      // _logger.i('🗑️ [增强视频池] 强制移除控制器: ${_getDisplayKey(videoType, filePath)}');
      await _removeFromPool(key);
    }
  }

  ///15，清空整个池
  Future<void> clearPool() async {
    // _logger.i('🧹 [增强视频池] 开始清空整个控制器池');

    final keys = List.from(_controllerPool.keys);
    for (final key in keys) {
      await _removeFromPool(key);
    }

    // _logger.i('✅ [增强视频池] 控制器池已完全清空');
  }

  ///16，销毁管理器
  Future<void> dispose() async {
    _cleanupTimer?.cancel();
    await clearPool();
    _instance = null;
    // _logger.i('🗑️ [增强视频池] 管理器已销毁');
  }

  ///17，打印当前池的详细状态（调试用）
  void debugPrintPoolStatus() {
    // _logger.i('🔍 [增强视频池] 当前池状态:');
    _logger.i('📊 池大小: ${_controllerPool.length}/$_maxPoolSize');

    if (_controllerPool.isEmpty) {
      _logger.i('📂 池为空');
      return;
    }

    for (final entry in _controllerPool.entries) {
      final key = entry.key;
      final controller = entry.value;
      final isInUse = _isInUse[key] ?? false;
      final lastUsed = _lastUsed[key] ?? DateTime.now();
      // 从key中解析出videoType和filePath
      final parts = key.split(':');
      final typePrefix = parts[0]; // 'top_file' 或 'full_file' 等
      final filePath = parts[1];
      final videoType =
          typePrefix.startsWith('top') ? VideoType.topAd : VideoType.fullAd;
      final displayKey = _getDisplayKey(videoType, filePath);

      final status = isInUse ? '使用中' : '空闲';
      final valid = _isControllerValid(controller) ? '有效' : '无效';
      final timeDiff = DateTime.now().difference(lastUsed).inSeconds;

      _logger.i('📱 $displayKey: $status, $valid, $timeDiff秒前使用');
    }
  }
}
