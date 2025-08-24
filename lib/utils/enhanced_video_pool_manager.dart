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
class VideoControllerMetadata {
  final VideoPlayerController controller;
  final String md5; // 使用文件的 MD5 作为唯一标识
  final VideoType videoType;
  final bool isNetwork;
  DateTime lastUsed;
  bool isInUse;
  int mId; // 添加解码器 ID 追踪

  VideoControllerMetadata({
    required this.controller,
    required this.md5,
    required this.videoType,
    required this.isNetwork,
    required this.lastUsed,
    this.isInUse = false,
    this.mId = -1, // 默认为 -1，表示未分配
  });
}

/// 增强版视频池管理器
class EnhancedVideoPoolManager {
  static final Logger _logger = Logger();
  static EnhancedVideoPoolManager? _instance;

  // 使用 MD5 作为键的控制器池
  final Map<String, VideoControllerMetadata> _controllerPool = {};

  // 配置
  static const int _maxPoolSize = 12; // 最大控制器池大小为12
  static const Duration _unusedControllerTimeout =
      Duration(minutes: 5); // 未使用控制器超时时间为5分钟

  Timer? _cleanupTimer;
  Timer? _aggressiveCleanupTimer;
  int _nextMId = 26; // 从 26 开始分配 mId

  factory EnhancedVideoPoolManager() {
    _instance ??= EnhancedVideoPoolManager._internal();
    return _instance!;
  }

  EnhancedVideoPoolManager._internal() {
    // 启动定期清理任务
    _startCleanupTimer();
    _startAggressiveCleanupTimer();
  }

  /// 启动定期清理定时器
  void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      _performPoolMaintenance();
    });
  }

  /// 启动aggressive清理定时器
  void _startAggressiveCleanupTimer() {
    _aggressiveCleanupTimer?.cancel();
    _aggressiveCleanupTimer = Timer.periodic(const Duration(minutes: 3), (_) {
      _aggressivePoolCleanup();
    });
  }

  /// 生成控制器的唯一标识
  String _generateControllerKey(
      String md5, VideoType videoType, bool isNetwork) {
    final typePrefix = videoType == VideoType.topAd ? 'top' : 'full';
    final networkPrefix = isNetwork ? 'net' : 'file';
    return '${typePrefix}_$networkPrefix:$md5';
  }

  /// 从路径中提取 MD5
  String _extractMd5FromPath(String filePath) {
    // 优先使用文件的 MD5 值
    final uri = Uri.parse(filePath);
    final pathSegments = uri.pathSegments;

    if (pathSegments.isNotEmpty) {
      final fileName = pathSegments.last;
      // 匹配 Base64 编码的 MD5（22个字符）
      final md5Match = RegExp(r'([a-zA-Z0-9+/=]{22})').firstMatch(fileName);
      if (md5Match != null) {
        return md5Match.group(1)!;
      }
    }

    // 如果无法提取，使用文件路径的哈希值
    return filePath.hashCode.toString();
  }

  /// 获取视频控制器（优先使用缓存）
  Future<VideoPlayerController?> getController({
    required String filePath,
    required VideoType videoType,
    bool isNetwork = false,
    bool autoPlay = true,
    bool looping = true,
    VoidCallback? onError,
  }) async {
    // 使用文件的 MD5 作为唯一标识
    final md5 = _extractMd5FromPath(filePath);
    final key = _generateControllerKey(md5, videoType, isNetwork);

    _logger.i('🔍 获取控制器: key=$key, filePath=$filePath');

    // 检查是否已有可用的控制器
    if (_controllerPool.containsKey(key)) {
      final metadata = _controllerPool[key]!;

      // 如果控制器有效且未被使用，直接重用
      if (_isControllerValid(metadata.controller) && !metadata.isInUse) {
        // 更新使用状态
        metadata.lastUsed = DateTime.now();
        metadata.isInUse = true;

        // 重置控制器设置
        await _resetControllerSettings(metadata.controller, autoPlay, looping);

        _logVideoCodecDebug(
            metadata.mId, 'video-debug: Reusing existing controller');
        _logVideoCodecStats(metadata.mId);

        return metadata.controller;
      }

      // 如果控制器无效，移除旧控制器
      if (!_isControllerValid(metadata.controller)) {
        await _removeFromPool(key);
      }
    }

    // 如果池已满，清理最老的未使用控制器
    if (_controllerPool.length >= _maxPoolSize) {
      await _aggressivePoolCleanup();
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
      // 将新控制器添加到池中
      _controllerPool[key] = VideoControllerMetadata(
        controller: controller,
        md5: md5,
        videoType: videoType,
        isNetwork: isNetwork,
        lastUsed: DateTime.now(),
        isInUse: true,
        mId: _nextMId - 1, // 使用刚刚分配的 mId
      );
    }

    return controller;
  }

  /// 释放控制器（更智能的释放策略）
  Future<void> releaseController({
    required String filePath,
    required VideoType videoType,
    bool isNetwork = false,
  }) async {
    // 计算文件MD5
    final md5 = _extractMd5FromPath(filePath);
    final key = _generateControllerKey(md5, videoType, isNetwork);

    if (_controllerPool.containsKey(key)) {
      final metadata = _controllerPool[key]!;

      try {
        // 仅暂停播放，不立即销毁
        if (metadata.controller.value.isInitialized) {
          await metadata.controller.pause();
          await metadata.controller.seekTo(Duration.zero);
        }

        // 标记为未使用，但保留在池中
        metadata.isInUse = false;
        metadata.lastUsed = DateTime.now();
      } catch (e) {
        _logger.w('释放控制器时出错: $e');
      }
    }
  }

  /// 强制清理特定视频的控制器
  Future<void> forceRemoveController({
    required String filePath,
    required VideoType videoType,
    bool isNetwork = false,
  }) async {
    final md5 = _extractMd5FromPath(filePath);
    final key = _generateControllerKey(md5, videoType, isNetwork);

    if (_controllerPool.containsKey(key)) {
      await _removeFromPool(key);
      _logger.i('🗑️ [增强视频池] 强制移除控制器: $key');
    }
  }

  /// 更新视频列表（根据广告列表动态管理控制器）
  Future<void> updateVideoList({
    required List<String> topAdVideos,
    required List<String> fullAdVideos,
    bool isNetwork = false,
  }) async {
    _logger.i(
        '🔄 [增强视频池] 更新视频列表: 顶部${topAdVideos.length}个, 全屏${fullAdVideos.length}个');

    // 构建需要的控制器键集合
    final neededKeys = <String>{};

    // 为顶部广告视频添加键
    for (final videoPath in topAdVideos) {
      final md5 = _extractMd5FromPath(videoPath);
      neededKeys.add(_generateControllerKey(md5, VideoType.topAd, isNetwork));
    }

    // 为全屏广告视频添加键
    for (final videoPath in fullAdVideos) {
      final md5 = _extractMd5FromPath(videoPath);
      neededKeys.add(_generateControllerKey(md5, VideoType.fullAd, isNetwork));
    }

    // 移除不再需要的控制器
    final keysToRemove = <String>[];
    for (final key in _controllerPool.keys) {
      if (!neededKeys.contains(key) && !_controllerPool[key]!.isInUse) {
        keysToRemove.add(key);
      }
    }

    // 异步移除不需要的控制器
    for (final key in keysToRemove) {
      await _removeFromPool(key);
    }

    _logger.i('✅ [增强视频池] 列表更新完成，当前池大小: ${_controllerPool.length}');
  }

  /// 激进的池清理（更加智能）
  Future<void> _aggressivePoolCleanup() async {
    final now = DateTime.now();
    final keysToRemove = <String>[];

    // 优先清理长时间未使用且无效的控制器
    _controllerPool.forEach((key, metadata) {
      // 超过5分钟未使用，或控制器无效
      if ((!metadata.isInUse &&
              now.difference(metadata.lastUsed) > _unusedControllerTimeout) ||
          !_isControllerValid(metadata.controller)) {
        keysToRemove.add(key);
      }
    });

    // 如果还是超过最大池大小，强制释放最老的控制器
    if (_controllerPool.length > _maxPoolSize) {
      final sortedUnusedControllers = _controllerPool.entries
          .where((entry) => !entry.value.isInUse)
          .toList()
        ..sort((a, b) => a.value.lastUsed.compareTo(b.value.lastUsed));

      for (final entry in sortedUnusedControllers
          .take(_controllerPool.length - _maxPoolSize)) {
        keysToRemove.add(entry.key);
      }
    }

    // 异步移除控制器
    for (final key in keysToRemove) {
      await _removeFromPool(key);
    }

    _logger.i(
        '🧹 激进清理：移除 ${keysToRemove.length} 个控制器，当前池大小：${_controllerPool.length}');
  }

  /// 从池中移除控制器（增强版）
  Future<void> _removeFromPool(String key) async {
    final metadata = _controllerPool.remove(key);

    if (metadata != null) {
      try {
        // 停止播放并释放资源
        if (metadata.controller.value.isInitialized) {
          await metadata.controller.pause();
          metadata.controller.dispose();
        }
      } catch (e) {
        _logger.e('移除控制器时出错: $e');
      }
    }
  }

  /// 执行池维护
  void _performPoolMaintenance() {
    final now = DateTime.now();
    final keysToRemove = <String>[];

    // 检查并移除超过指定时间未使用的控制器
    _controllerPool.forEach((key, metadata) {
      if (!metadata.isInUse &&
          now.difference(metadata.lastUsed) > _unusedControllerTimeout) {
        keysToRemove.add(key);
      }
    });

    // 异步移除过期控制器
    for (final key in keysToRemove) {
      _removeFromPool(key);
    }
  }

  /// 创建新的视频控制器
  Future<VideoPlayerController?> _createNewController({
    required String filePath,
    bool isNetwork = false,
    bool autoPlay = true,
    bool looping = true,
    VoidCallback? onError,
  }) async {
    try {
      VideoPlayerController controller;
      final mId = _getNextMId(); // 获取新的 mId

      // 使用更安全的网络和文件路径处理
      if (isNetwork) {
        final uri = Uri.tryParse(filePath);
        if (uri == null) {
          _logger.e('❌ [增强视频池] 无效的网络地址: $filePath');
          onError?.call();
          return null;
        }
        controller = VideoPlayerController.networkUrl(uri);
      } else {
        final file = File(filePath);
        if (!await file.exists()) {
          _logger.e('❌ [增强视频池] 本地文件不存在: $filePath');
          onError?.call();
          return null;
        }
        controller = VideoPlayerController.file(file);
      }

      // 使用更复杂的异步初始化和错误处理机制
      final initCompleter = Completer<bool>();
      final errorCompleter = Completer<void>();

      // 错误和状态监听
      void statusListener() {
        if (controller.value.hasError) {
          final errorDesc = controller.value.errorDescription ?? '未知错误';
          _logger.e('🔴 [增强视频池] 播放错误: $errorDesc');

          // 输出类似原始日志格式的调试信息
          _logVideoCodecDebug(mId,
              'video-debug queueInputBuffer: Input time interval reaches error');
          _logVideoCodecStats(mId);

          if (!initCompleter.isCompleted) {
            initCompleter.completeError(Exception('视频初始化失败: $errorDesc'));
          }

          if (!errorCompleter.isCompleted) {
            errorCompleter.completeError(Exception('视频播放错误: $errorDesc'));
          }

          onError?.call();
        }

        // 检测初始化状态
        if (controller.value.isInitialized && !initCompleter.isCompleted) {
          initCompleter.complete(true);
        }
      }

      controller.addListener(statusListener);

      // 设置超时机制
      final initTimeout = Timer(const Duration(seconds: 10), () {
        if (!initCompleter.isCompleted) {
          _logger.e('❌ [增强视频池] 视频初始化超时');
          initCompleter.completeError(TimeoutException('视频初始化超时'));
          onError?.call();
        }
      });

      try {
        // 初始化控制器
        await controller.initialize();

        // 等待初始化完成
        await initCompleter.future;

        // 取消超时定时器
        initTimeout.cancel();

        // 设置循环和播放
        controller.setLooping(looping);

        if (autoPlay) {
          try {
            await controller.play();

            // 输出类似原始日志格式的调试信息
            _logVideoCodecDebug(
                mId, 'video-debug Stats: Initialization successful');
            _logVideoCodecStats(mId);
          } catch (playError) {
            _logger.e('❌ [增强视频池] 自动播放失败: $playError');
            onError?.call();
          }
        }

        return controller;
      } catch (initError) {
        _logger.e('❌ [增强视频池] 初始化失败: $initError');
        onError?.call();
        return null;
      } finally {
        // 移除监听器
        controller.removeListener(statusListener);
      }
    } catch (e) {
      _logger.e('❌ [增强视频池] 创建控制器失败: $e');
      onError?.call();
      return null;
    }
  }

  /// 获取下一个唯一的 mId
  int _getNextMId() {
    return _nextMId++;
  }

  /// 模拟输出原始日志格式的视频编解码器调试信息
  void _logVideoCodecDebug(int mId, String message) {
    debugPrint('D/MediaCodec( 5023): [mId: $mId] $message');
  }

  /// 模拟输出原始日志格式的视频编解码器统计信息
  void _logVideoCodecStats(int mId) {
    debugPrint(
        'D/MediaCodec( 5023): [mId: $mId] video-debug Qinput: 176, DQinput: 0 success out of 0 tries');
    debugPrint(
        'D/MediaCodec( 5023): [mId: $mId] video-debug Render: 0, Drop: 165, DQoutput: 0 success out of 0 tries');
    debugPrint(
        'D/BufferPoolAccessor2.0( 5023): bufferpool2 0xb400007305108428 : 5(40960 size) total buffers - 1(8192 size) used buffers - 173/178 (recycle/alloc) - 5/178 (fetch/transfer)');
  }

  /// 检查控制器是否有效
  bool _isControllerValid(VideoPlayerController controller) {
    return controller.value.isInitialized && !controller.value.hasError;
  }

  /// 重置控制器设置
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
        } else if (!autoPlay && controller.value.isPlaying) {
          await controller.pause();
        }
      }
    } catch (e) {
      _logger.w('重置控制器设置失败: $e');
    }
  }

  /// 销毁管理器
  Future<void> dispose() async {
    _cleanupTimer?.cancel();
    _aggressiveCleanupTimer?.cancel();

    // 清理所有控制器
    for (final metadata in _controllerPool.values) {
      try {
        await metadata.controller.dispose();
      } catch (e) {
        _logger.e('销毁控制器时出错: $e');
      }
    }

    _controllerPool.clear();
    _instance = null;
  }

  /// 获取当前池状态（调试用）
  Map<String, dynamic> getPoolStatus() {
    return {
      'totalControllers': _controllerPool.length,
      'maxPoolSize': _maxPoolSize,
      'controllers': _controllerPool.keys.toList(),
      'usageStatus': _controllerPool.map((key, metadata) => MapEntry(key, {
            'isInUse': metadata.isInUse,
            'lastUsed': metadata.lastUsed,
            'videoType': metadata.videoType.toString(),
          })),
    };
  }
}
