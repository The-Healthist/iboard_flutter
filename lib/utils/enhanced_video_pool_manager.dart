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

/// 视频控制器元数据
class VideoControllerWrapper {
  final VideoPlayerController controller;
  final String filePath;
  final VideoType videoType;
  DateTime lastUsed;
  int useCount;
  bool _isInUse; // 私有属性

  // 构造函数
  VideoControllerWrapper({
    required this.controller,
    required this.filePath,
    required this.videoType,
    required this.lastUsed,
    this.useCount = 0,
    bool isInUse = false,
  }) : _isInUse = isInUse;

  // Getter
  bool get isInUse => _isInUse;

  // Setter
  set isInUse(bool value) {
    _isInUse = value;
  }
}

/// 增强型视频资源管理器
class EnhancedVideoPoolManager {
  static final Logger _logger = Logger();
  static EnhancedVideoPoolManager? _instance;

  // 视频控制器缓存
  final Map<String, VideoControllerWrapper> _controllerCache = {};
  static const int _maxCacheSize = 10;

  factory EnhancedVideoPoolManager() {
    _instance ??= EnhancedVideoPoolManager._internal();
    return _instance!;
  }

  EnhancedVideoPoolManager._internal();

  /// 获取视频控制器（优先使用缓存）
  Future<VideoPlayerController?> getController({
    required String filePath,
    required VideoType videoType,
    bool isNetwork = false,
    bool autoPlay = false,
    bool looping = false,
    VoidCallback? onError,
  }) async {
    // 生成唯一标识键
    final key = _generateControllerKey(filePath, videoType);

    // 检查是否已有缓存的控制器
    if (_controllerCache.containsKey(key)) {
      final wrapper = _controllerCache[key]!;
      final controller = wrapper.controller;

      try {
        // 检查控制器是否有效
        if (_isControllerValid(controller)) {
          // 重置控制器状态
          await _resetControllerSettings(controller, autoPlay, looping);

          // 更新使用信息
          wrapper.lastUsed = DateTime.now();
          wrapper.useCount++;

          _logger.i('🔄 复用视频控制器: $key (使用次数: ${wrapper.useCount})');
          return controller;
        } else {
          // 如果控制器无效，移除并重新创建
          _controllerCache.remove(key);
          await controller.dispose();
        }
      } catch (e) {
        _logger.w('控制器重用失败: $e');
        _controllerCache.remove(key);
      }
    }

    // 创建新的控制器
    final controller = await _createController(
      filePath: filePath,
      isNetwork: isNetwork,
      autoPlay: autoPlay,
      looping: looping,
      onError: onError,
    );

    // 缓存新创建的控制器
    if (controller != null) {
      _cacheController(controller, filePath, videoType);
    }

    return controller;
  }

  /// 缓存控制器，管理缓存大小
  void _cacheController(
      VideoPlayerController controller, String filePath, VideoType videoType) {
    final key = _generateControllerKey(filePath, videoType);

    // 如果缓存已满，移除最久未使用的控制器
    if (_controllerCache.length >= _maxCacheSize) {
      final oldestKey = _controllerCache.entries
          .reduce((a, b) => a.value.lastUsed.isBefore(b.value.lastUsed) ? a : b)
          .key;

      final oldestWrapper = _controllerCache.remove(oldestKey);
      oldestWrapper?.controller.dispose();
    }

    _controllerCache[key] = VideoControllerWrapper(
      controller: controller,
      filePath: filePath,
      videoType: videoType,
      lastUsed: DateTime.now(),
      useCount: 1,
    );
  }

  /// 创建视频控制器
  Future<VideoPlayerController?> _createController({
    required String filePath,
    bool isNetwork = false,
    bool autoPlay = false,
    bool looping = false,
    VoidCallback? onError,
  }) async {
    try {
      final controller = isNetwork
          ? VideoPlayerController.networkUrl(Uri.parse(filePath))
          : VideoPlayerController.file(File(filePath));

      await controller.initialize();

      // 设置循环和自动播放
      controller.setLooping(looping);

      if (autoPlay) {
        await controller.play();
      }

      _logger.i('🆕 创建新视频控制器: $filePath');
      return controller;
    } catch (e) {
      _logger.e('❌ 创建视频控制器失败: $e');
      onError?.call();
      return null;
    }
  }

  /// 重置控制器设置
  ///2, 重置控制器设置（增加播放失败的错误捕获）
  Future<void> _resetControllerSettings(
      VideoPlayerController controller, bool autoPlay, bool looping) async {
    if (!controller.value.isInitialized) return;

    try {
      // 重置到开头
      await controller.seekTo(Duration.zero);

      // 设置循环
      controller.setLooping(looping);

      // 根据需要播放或暂停，并捕获播放异常
      if (autoPlay) {
        try {
          await controller.play();
        } catch (e) {
          _logger.w('播放时出错: $e');
        }
      } else {
        if (controller.value.isPlaying) {
          await controller.pause();
        }
      }
    } catch (e) {
      _logger.w('重置控制器设置失败: $e');
      rethrow;
    }
  }

  /// 检查控制器是否有效
  ///1, 判断控制器是否有效（只判定初始化和是否有错误，不判断播放状态）
  bool _isControllerValid(VideoPlayerController controller) {
    return controller.value.isInitialized && !controller.value.hasError;
  }

  /// 生成控制器唯一标识（类型+文件路径作为唯一key，不会冲突）
  String _generateControllerKey(String filePath, VideoType type) {
    return '${type.toString()}::$filePath';
  }

  /// 根据广告类型生成多个控制器Key（处理topfull类型）
  List<String> generateControllerKeys(String filePath, String adType) {
    final keys = <String>[];

    if (adType == 'topfull') {
      // topfull类型需要创建两个独立的控制器
      keys.add('${VideoType.topAd.toString()}::$filePath');
      keys.add('${VideoType.fullAd.toString()}::$filePath');
    } else if (adType == 'top') {
      keys.add('${VideoType.topAd.toString()}::$filePath');
    } else if (adType == 'full') {
      keys.add('${VideoType.fullAd.toString()}::$filePath');
    }

    return keys;
  }

  /// 获取控制器缓存状态
  Map<String, dynamic> getPoolStatus() {
    return {
      'totalControllers': _controllerCache.length,
      'controllers': _controllerCache.keys.toList(),
      'usageDetails': _controllerCache.map((key, wrapper) => MapEntry(key, {
            'useCount': wrapper.useCount,
            'lastUsed': wrapper.lastUsed,
            'videoType': wrapper.videoType.toString(),
          })),
    };
  }

  /// 调试：打印控制器池状态
  void debugPrintPoolStatus() {
    _logger.i('📊 视频控制器池状态：');
    _controllerCache.forEach((key, wrapper) {
      _logger
          .i(' 🎬 $key - 使用次数: ${wrapper.useCount}, 类型: ${wrapper.videoType}');
    });
  }

  /// 强制释放所有控制器
  Future<void> disposeAllControllers() async {
    for (final wrapper in _controllerCache.values) {
      try {
        await wrapper.controller.dispose();
      } catch (e) {
        _logger.e('销毁控制器时出错: $e');
      }
    }
    _controllerCache.clear();
  }

  /// 释放控制器
  Future<void> releaseController({
    required String filePath,
    required VideoType videoType,
    bool isNetwork = false,
  }) async {
    final key = _generateControllerKey(filePath, videoType);

    if (_controllerCache.containsKey(key)) {
      final wrapper = _controllerCache[key]!;
      final controller = wrapper.controller;

      try {
        // 暂停播放并重置到开头
        if (controller.value.isInitialized) {
          await controller.pause();
          await controller.seekTo(Duration.zero);
        }

        // 标记为未使用
        wrapper.isInUse = false;
        wrapper.lastUsed = DateTime.now();

        _logger.i('🔓 控制器已释放: $key');
      } catch (e) {
        _logger.w('释放控制器时出错: $e');
      }
    }
  }

  /// 强制移除控制器
  Future<void> forceRemoveController({
    required String filePath,
    required VideoType videoType,
    bool isNetwork = false,
  }) async {
    final key = _generateControllerKey(filePath, videoType);

    if (_controllerCache.containsKey(key)) {
      final wrapper = _controllerCache.remove(key);

      try {
        await wrapper?.controller.dispose();
        _logger.i('🗑️ 强制移除控制器: $key');
      } catch (e) {
        _logger.w('强制移除控制器时出错: $e');
      }
    }
  }

  /// 更新视频列表
  Future<void> updateVideoList({
    required List<String> topAdVideos,
    required List<String> fullAdVideos,
    bool isNetwork = false,
  }) async {
    _logger.i('🔄 更新视频列表: 顶部${topAdVideos.length}个, 全屏${fullAdVideos.length}个');

    // 合并所有类型视频路径键
    final allTypePaths = <String>{};
    for (final path in topAdVideos) {
      allTypePaths.add(_generateControllerKey(path, VideoType.topAd));
    }
    for (final path in fullAdVideos) {
      allTypePaths.add(_generateControllerKey(path, VideoType.fullAd));
    }

    // 移除不再需要的控制器
    final keysToRemove = _controllerCache.keys
        .where((key) => !allTypePaths.contains(key))
        .toList();

    for (final key in keysToRemove) {
      try {
        final wrapper = _controllerCache.remove(key);
        await wrapper?.controller.dispose();
      } catch (e) {
        _logger.w('移除控制器时出错: $e');
      }
    }

    _logger.i('✅ 列表更新完成，当前池大小: ${_controllerCache.length}');
  }
}
