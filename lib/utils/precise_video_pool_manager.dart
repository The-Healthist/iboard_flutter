import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

//控制器池(分为已初始化和未初始化)
class PreciseVideoPoolManager {
  static PreciseVideoPoolManager? _instance;

  final Map<String, _PreciseVideoWrapper> _controllerPool = {};
  static const int _maxControllerPool = 20; // 控制器缓存上限

  /// 已初始化的控制器（占用解码器）
  final Set<String> _initializedControllers = {};
  final Set<String> _playingControllers = {}; // 正在播放
  static const int _maxInitializedDecoders = 6; // 🎯 修复：增加到6个解码器，提供缓冲空间
  static const int _maxConcurrentPlaying = 4; // 🎯 修复：支持顶部+全屏+预热，最多4个同时播放

  /// 预初始化策略：当前播放
  String? _currentTopAdKey; // 当前顶部广告
  String? _currentFullAdKey; // 当前全屏广告
  String? _lastTopAdKey; // 前一个顶部广告
  String? _lastFullAdKey; // 前一个全屏广告

  /// 状态管理
  final Set<String> _releasingKeys = {};
  final Set<String> _failedFiles = {};
  final Map<String, DateTime> _lastUsed = {};
  final Set<String> _initializingKeys = {};

  factory PreciseVideoPoolManager() {
    _instance ??= PreciseVideoPoolManager._internal();
    return _instance!;
  }

  PreciseVideoPoolManager._internal();

  /// 0.获取未初始化的视频控制器（不占用解码器资源）
  Future<VideoPlayerController?> getUninitializedController({
    required String filePath,
    required VideoType videoType,
    VoidCallback? onError,
  }) async {
    final key = _generateControllerKey(filePath, videoType);

    try {
      // 1. 检查是否已有控制器
      if (_controllerPool.containsKey(key)) {
        final wrapper = _controllerPool[key]!;
        wrapper.useCount++;
        _lastUsed[key] = DateTime.now();
        // debugPrint('✅ 复用未初始化控制器: $key');
        return wrapper.controller;
      }

      // 2. 检查池容量
      if (_controllerPool.length >= _maxControllerPool) {
        await _removeOldestUnusedController();
      }

      // 3. 检查文件是否存在
      final file = File(filePath);
      if (!await file.exists()) {
        // debugPrint('❌ 视频文件不存在: $filePath');
        _failedFiles.add(filePath);
        onError?.call();
        return null;
      }

      // 4. 创建新的未初始化控制器
      final controller = VideoPlayerController.file(file);
      final wrapper = _PreciseVideoWrapper(
        controller: controller,
        filePath: filePath,
        videoType: videoType,
        createdAt: DateTime.now(),
        useCount: 1, // 直接设置为1，因为这次调用就算一次使用
      );

      _controllerPool[key] = wrapper;
      _lastUsed[key] = DateTime.now();

      // debugPrint('[controllerpool_manager] 🆕 创建未初始化控制器: $key');
      return controller;
    } catch (e) {
      // debugPrint('[controllerpool_manager] ❌ 获取未初始化控制器失败: $key, 错误: $e');
      _failedFiles.add(filePath);
      onError?.call();
      return null;
    }
  }

  /// 1.获取视频控制器（确保初始化完毕）
  Future<VideoPlayerController?> getInitializedController({
    required String filePath,
    required VideoType videoType,
    bool autoPlay = false,
    bool looping = false,
    VoidCallback? onError,
  }) async {
    //1.1 获取key并且释放上一个控制器(确保)
    final key = _generateControllerKey(filePath, videoType);

    // 🎯 優雅的自動清理邏輯：根據視頻類型自動dispose上一個控制器
    if (videoType == VideoType.topAd) {
      if (key != _lastTopAdKey && _lastTopAdKey != null) {
        await _autoDisposeController(_lastTopAdKey!, '頂部廣告');
      }
      _lastTopAdKey = key; // 更新當前頂部廣告key
    } else if (videoType == VideoType.fullAd) {
      if (key != _lastFullAdKey && _lastFullAdKey != null) {
        await _autoDisposeController(_lastFullAdKey!, '全屏廣告');
      }
      _lastFullAdKey = key; // 更新當前全屏廣告key
    }

    // 🎯 新增：檢查是否有相同文件路徑但不同類型的控制器正在播放
    await _checkAndHandleFilePathConflict(filePath, videoType, key);

    _printDecoderStatus();

    try {
      // 1. 检查是否已有初始化的控制器
      if (_controllerPool.containsKey(key) &&
          _initializedControllers.contains(key)) {
        final wrapper = _controllerPool[key]!;
        if (wrapper.controller.value.isInitialized) {
          _lastUsed[key] = DateTime.now();
          wrapper.useCount++;

          // debugPrint('✅ 复用已初始化控制器: $key');

          if (autoPlay) {
            await _startPlay(wrapper.controller, key);
          }

          return wrapper.controller;
        }
      }

      // 2. 检查是否正在初始化（防止并发）
      if (_initializingKeys.contains(key)) {
        // 简单等待策略，生产环境应该用 Completer
        await Future.delayed(const Duration(milliseconds: 100));
        return getInitializedController(
          filePath: filePath,
          videoType: videoType,
          autoPlay: autoPlay,
          looping: looping,
          onError: onError,
        );
      }

      // 3. 🎯 改进的资源检查：检查当前广告key是否在初始化池中
      final totalPendingInit =
          _initializedControllers.length + _initializingKeys.length;
      if (totalPendingInit >= _maxInitializedDecoders) {
        // 🎯 关键检查：当前广告key是否在初始化池中
        bool currentKeyInPool = _initializedControllers.contains(key);

        if (!currentKeyInPool) {
          // 清理该类型的所有控制器
          await cleanupControllersByType(videoType);

          // 清理后再次检查资源
          final afterCleanupTotal =
              _initializedControllers.length + _initializingKeys.length;
          if (afterCleanupTotal >= _maxInitializedDecoders) {
            onError?.call();
            return null;
          }
        } else {
          // 当前key在池中，尝试释放其他类型的最旧解码器
          await _releaseOldestDecoder();

          // 再次检查释放后是否有足够空间
          final newTotalPendingInit =
              _initializedControllers.length + _initializingKeys.length;
          if (newTotalPendingInit >= _maxInitializedDecoders) {
            onError?.call();
            return null;
          }
        }
      }

      // 4. 获取或创建未初始化的控制器
      _PreciseVideoWrapper? wrapper;

      if (_controllerPool.containsKey(key)) {
        wrapper = _controllerPool[key]!;
      } else {
        // 检查池容量
        if (_controllerPool.length >= _maxControllerPool) {
          await _removeOldestUnusedController();
        }

        // 检查文件是否存在
        final file = File(filePath);
        if (!await file.exists()) {
          _failedFiles.add(filePath);
          onError?.call();
          return null;
        }

        // 创建新控制器（但不初始化）
        final controller = VideoPlayerController.file(file);
        wrapper = _PreciseVideoWrapper(
          controller: controller,
          filePath: filePath,
          videoType: videoType,
          createdAt: DateTime.now(),
          useCount: 0,
        );
        _controllerPool[key] = wrapper;
      }

      // 5.  关键步骤：初始化控制器，占用解码器资源
      if (!wrapper.controller.value.isInitialized) {
        // 🔒 再次检查初始化限制（防止竞态条件）
        final currentTotalInit =
            _initializedControllers.length + _initializingKeys.length;
        if (currentTotalInit >= _maxInitializedDecoders) {
          onError?.call();
          return null;
        }

        _initializingKeys.add(key);

        try {
          await wrapper.controller.initialize();

          // ✅ 初始化成功，添加到已初始化列表
          _initializedControllers.add(key);
          _lastUsed[key] = DateTime.now();
        } catch (e) {
          // debugPrint('[controllerpool_manager] ❌ 控制器初始化失败: $key, 错误: $e');
          onError?.call();
          return null;
        } finally {
          // 🔒 无论成功失败都要移除初始化标记
          _initializingKeys.remove(key);
        }
      }

      wrapper.useCount++;

      // 6. 如果需要自动播放
      if (autoPlay) {
        await _startPlay(wrapper.controller, key);
      } else {}

      // 7. 更新当前播放状态（仅在实际播放时更新）
      if (autoPlay) {
        _updateCurrentPlayingState(key, videoType);
      }

      _printDecoderStatus();
      return wrapper.controller;
    } catch (e) {
      _failedFiles.add(filePath);
      onError?.call();
      return null;
    }
  }

  /// 2.释放控制器（精确控制解码器释放）
  Future<void> releaseController({
    required String filePath,
    required VideoType videoType,
    bool forceDispose = false, // 是否强制dispose
  }) async {
    final key = _generateControllerKey(filePath, videoType);

    if (_releasingKeys.contains(key)) return;
    _releasingKeys.add(key);

    try {
      if (_controllerPool.containsKey(key)) {
        final wrapper = _controllerPool[key]!;
        final controller = wrapper.controller;

        // 1. 停止播放
        if (controller.value.isPlaying) {
          await controller.pause();
          _playingControllers.remove(key);
        }

        if (forceDispose) {
          _controllerPool.remove(key);
          _initializedControllers.remove(key);
          _playingControllers.remove(key);
          _lastUsed.remove(key);

          // 关键：调用dispose()会释放textureId，从而释放解码器资源
          await _safeDisposeController(controller, key);
        } else {
          // 如果控制器已初始化，dispose它以释放解码器资源
          if (controller.value.isInitialized) {
            // 从初始化列表中移除
            _initializedControllers.remove(key);
            _playingControllers.remove(key);

            // dispose控制器释放解码器资源
            await _safeDisposeController(controller, key);

            _controllerPool.remove(key);
            _lastUsed.remove(key);
          } else {
            // 控制器未初始化，只需要重置播放状态
            _playingControllers.remove(key);
          }
        }

        // 更新当前播放状态
        _updateCurrentPlayingState(null, videoType);
      }
    } catch (e) {
    } finally {
      _releasingKeys.remove(key);
      _printDecoderStatus();
    }
  }

  /// 3. ▶️ 开始播放（严格控制并发播放）
  Future<void> _startPlay(VideoPlayerController controller, String key) async {
    try {
      // 🧹 首先清理不一致的播放状态
      await _cleanupInconsistentPlayingState();

      // 🎯 优化播放状态管理
      optimizePlayingStates();

      // 🔒 严格限制并发播放数量（带重试机制）
      int retryCount = 0;
      const maxRetries = 3;

      while (_playingControllers.length >= _maxConcurrentPlaying &&
          retryCount < maxRetries) {
        final beforeCount = _playingControllers.length;
        await _pauseOldestPlaying();
        final afterCount = _playingControllers.length;

        // 检查暂停是否有效
        if (beforeCount == afterCount) {
          await Future.delayed(const Duration(milliseconds: 100));
          // 再次尝试清理不一致状态
          await _cleanupInconsistentPlayingState();
        }

        retryCount++;
      }

      // 📊 最终检查：确保绝对不会超过限制
      if (_playingControllers.length >= _maxConcurrentPlaying) {
        // 强制清理一个播放状态
        if (_playingControllers.isNotEmpty) {
          final oldestKey = _playingControllers.first;
          _playingControllers.remove(oldestKey);
        }
      }

      // 再次检查该控制器是否已在播放列表中
      if (_playingControllers.contains(key)) {
        return;
      }

      // 🎯 优化：最终检查并发播放限制，如果达到限制则尝试释放最旧的非关键控制器
      if (_playingControllers.length >= _maxConcurrentPlaying) {
        // 尝试释放最旧的非关键播放控制器
        bool releasedOldest = false;
        final sortedByUsage = _playingControllers.toList();

        for (final oldKey in sortedByUsage) {
          // 不要释放当前正在请求的同类型控制器
          if (!oldKey.startsWith(key.split('_')[0])) {
            try {
              // 直接暂停并从播放列表移除
              final wrapper = _controllerPool[oldKey];
              if (wrapper != null && wrapper.controller.value.isPlaying) {
                await wrapper.controller.pause();
                _playingControllers.remove(oldKey);

                releasedOldest = true;
                break;
              }
            } catch (e) {}
          }
        }

        if (!releasedOldest) {
          return;
        }
      }

      // 设置播放参数
      await controller.setLooping(true);
      await controller.setVolume(1.0);
      await controller.setPlaybackSpeed(1.0);
      await controller.seekTo(Duration.zero);

      // 等待准备完成
      await Future.delayed(const Duration(milliseconds: 350));

      await controller.play();
      _playingControllers.add(key);

      // 📊 播放后状态检查
      if (_playingControllers.length > _maxConcurrentPlaying) {}
    } catch (e) {
      // 播放失败时确保从播放列表中移除
      _playingControllers.remove(key);
    }
  }

  /// 4. 📊 更新当前播放状态
  void _updateCurrentPlayingState(String? key, VideoType videoType) {
    if (videoType == VideoType.topAd) {
      _currentTopAdKey = key;
    } else if (videoType == VideoType.fullAd) {
      _currentFullAdKey = key;
    }
  }

  /// 5. 🔄 释放最旧的解码器
  Future<void> _releaseOldestDecoder() async {
    if (_initializedControllers.isEmpty) {
      // debugPrint('[controllerpool_manager] ⚠️ 没有已初始化的控制器可以释放');
      return;
    }

    // 找到最少使用且非当前播放的初始化控制器
    String? targetKey;
    DateTime? oldestTime;
    int leastUsageCount = -1;

    for (final key in _initializedControllers) {
      // 不释放当前正在播放的
      if (_playingControllers.contains(key)) {
        continue;
      }

      // 不释放当前显示的主要视频
      if (key == _currentTopAdKey || key == _currentFullAdKey) {
        continue;
      }

      final wrapper = _controllerPool[key];
      if (wrapper == null) continue;

      final lastUsedTime = _lastUsed[key] ?? DateTime.now();
      final usageCount = wrapper.useCount;

      // 优先选择使用次数少且最旧的控制器
      bool shouldSelect = false;
      if (targetKey == null) {
        shouldSelect = true;
      } else if (usageCount < leastUsageCount) {
        shouldSelect = true;
      } else if (usageCount == leastUsageCount &&
          lastUsedTime.isBefore(oldestTime!)) {
        shouldSelect = true;
      }

      if (shouldSelect) {
        oldestTime = lastUsedTime;
        targetKey = key;
        leastUsageCount = usageCount;
      }
    }

    if (targetKey != null && _controllerPool.containsKey(targetKey)) {
      final wrapper = _controllerPool[targetKey]!;

      // 🔑 关键：dispose控制器以释放解码器资源
      _controllerPool.remove(targetKey);
      _initializedControllers.remove(targetKey);
      _playingControllers.remove(targetKey); // 🔧 确保同时清理播放状态
      _lastUsed.remove(targetKey);

      try {
        await _safeDisposeController(wrapper.controller, targetKey);
      } catch (e) {}
    } else {}
  }

  /// 5a. 🧹 清理不一致的播放状态
  Future<void> _cleanupInconsistentPlayingState() async {
    final toRemove = <String>[];

    for (final key in _playingControllers) {
      final wrapper = _controllerPool[key];

      // 🎯 修复：只清理明确无效的状态，不清理瞬时的播放状态变化
      if (wrapper == null || !_initializedControllers.contains(key)) {
        // 只有当控制器已被移除或未初始化时才清理
        toRemove.add(key);
      }
      // 🎯 移除：不再检查 isPlaying 状态，因为这会导致正常播放的视频被误判
    }

    for (final key in toRemove) {
      _playingControllers.remove(key);
    }

    if (toRemove.isNotEmpty) {}
  }

  /// 6. ⏸️ 暂停最旧的播放（增强版 - 确保严格限制）
  Future<void> _pauseOldestPlaying() async {
    if (_playingControllers.isEmpty) {
      return;
    }

    // 🔧 修复：先清理状态不一致的控制器（减少误判）
    final toRemove = <String>[];
    for (final key in _playingControllers) {
      final wrapper = _controllerPool[key];
      // 🎯 修复：只清理已被移除的控制器，不检查isPlaying状态
      if (wrapper == null) {
        toRemove.add(key);
      }
    }

    for (final key in toRemove) {
      _playingControllers.remove(key);
    }

    // 如果清理后没有播放控制器了，直接返回
    if (_playingControllers.isEmpty) {
      return;
    }

    // 找到最旧的播放控制器（优先暂停使用次数多的）
    String? targetKey;
    DateTime? oldestTime;
    int mostUsageCount = -1;

    for (final key in _playingControllers) {
      final wrapper = _controllerPool[key];
      if (wrapper == null) continue;

      final lastUsedTime = _lastUsed[key] ?? DateTime.now();
      final usageCount = wrapper.useCount;

      bool shouldSelect = false;
      if (targetKey == null) {
        shouldSelect = true;
      } else if (usageCount > mostUsageCount) {
        // 优先暂停使用次数多的（说明不太重要）
        shouldSelect = true;
      } else if (usageCount == mostUsageCount &&
          lastUsedTime.isBefore(oldestTime!)) {
        shouldSelect = true;
      }

      if (shouldSelect) {
        oldestTime = lastUsedTime;
        targetKey = key;
        mostUsageCount = usageCount;
      }
    }

    if (targetKey != null && _controllerPool.containsKey(targetKey)) {
      final wrapper = _controllerPool[targetKey]!;

      try {
        if (wrapper.controller.value.isPlaying) {
          await wrapper.controller.pause();
        }

        _playingControllers.remove(targetKey);
      } catch (e) {
        // 即使暂停失败也要从播放列表中移除，避免状态不一致
        _playingControllers.remove(targetKey);
      }
    } else {}
  }

  /// 7. 🗑️ 移除最少使用的未初始化控制器
  Future<void> _removeOldestUnusedController() async {
    if (_controllerPool.isEmpty) return;

    String? targetKey;
    _PreciseVideoWrapper? targetWrapper;

    // 优先移除未初始化的控制器
    for (final entry in _controllerPool.entries) {
      if (!_initializedControllers.contains(entry.key) &&
          !_playingControllers.contains(entry.key)) {
        if (targetWrapper == null ||
            entry.value.useCount < targetWrapper.useCount) {
          targetKey = entry.key;
          targetWrapper = entry.value;
        }
      }
    }

    if (targetKey != null && targetWrapper != null) {
      _controllerPool.remove(targetKey);
      await _safeDisposeController(targetWrapper.controller, targetKey);
    }
  }

  /// 8. 📊 打印解码器状态（增强版 - 包含完整性验证）
  void _printDecoderStatus() {
    // 🔍 验证状态一致性
    _validateStateConsistency();

    debugPrint('[controllerpool_manager] 📊 解码器状态: '
        '控制器池 ${_controllerPool.length}/$_maxControllerPool, '
        '已初始化 ${_initializedControllers.length}/$_maxInitializedDecoders, '
        '正在初始化 ${_initializingKeys.length}, '
        '播放中 ${_playingControllers.length}/$_maxConcurrentPlaying');
  }

  /// 8a. 🔍 验证状态一致性
  void _validateStateConsistency() {
    try {
      // 验证初始化控制器数量不超过限制
      if (_initializedControllers.length > _maxInitializedDecoders) {}

      // 验证播放控制器数量不超过限制
      if (_playingControllers.length > _maxConcurrentPlaying) {}

      // 验证所有播放中的控制器都已初始化
      for (final playingKey in _playingControllers) {
        if (!_initializedControllers.contains(playingKey)) {}
      }

      // 验证所有已初始化的控制器都在控制器池中
      for (final initializedKey in _initializedControllers) {
        if (!_controllerPool.containsKey(initializedKey)) {}
      }
    } catch (e) {}
  }

  /// 9. 🔑 检查控制器是否已初始化
  bool isControllerInitialized(String filePath, VideoType videoType) {
    final key = _generateControllerKey(filePath, videoType);
    return _initializedControllers.contains(key);
  }

  /// 9a. 🎯 优化播放状态管理
  void optimizePlayingStates() {
    // 清理不一致的播放状态
    final toRemove = <String>[];
    for (final key in _playingControllers) {
      final wrapper = _controllerPool[key];
      if (wrapper == null) {
        // 控制器已被移除但还在播放列表中
        toRemove.add(key);
      } else if (!_initializedControllers.contains(key)) {
        // 控制器未在初始化列表中但在播放列表中
        toRemove.add(key);
      } else if (!wrapper.controller.value.isInitialized) {
        // 控制器未初始化但在播放列表中
        toRemove.add(key);
      }
      // 🎯 修复：移除对 isPlaying 的检查，避免误判正常播放的视频
      // 因为 isPlaying 状态可能因为帧同步、状态更新延迟等原因瞬间为false
    }

    for (final key in toRemove) {
      _playingControllers.remove(key);
    }

    // 🎯 额外检查：确保播放中的控制器都在初始化列表中
    for (final key in _playingControllers) {
      if (!_initializedControllers.contains(key)) {}
    }
  }

  /// 9b. 🎯 清理指定类型的所有控制器（新增方法）
  Future<void> cleanupControllersByType(VideoType videoType) async {
    final keysToRemove = <String>[];

    // 1. 找到所有该类型的控制器
    for (final entry in _controllerPool.entries) {
      final key = entry.key;
      final wrapper = entry.value;

      if (wrapper.videoType == videoType) {
        keysToRemove.add(key);
      }
    }

    // debugPrint(

    // 2. 逐个清理控制器
    for (final key in keysToRemove) {
      try {
        final wrapper = _controllerPool[key];
        if (wrapper != null) {
          // 先暂停播放
          if (wrapper.controller.value.isPlaying) {
            await wrapper.controller.pause();
          }

          // 从所有状态列表中移除
          _playingControllers.remove(key);
          _initializedControllers.remove(key);
          _initializingKeys.remove(key);
          _releasingKeys.remove(key);
          _lastUsed.remove(key);

          // 确保控制器正确dispose
          await _safeDisposeController(wrapper.controller, key);

          // 从控制器池中移除
          _controllerPool.remove(key);
        }
      } catch (e) {
        // 即使出错也要清理状态
        _playingControllers.remove(key);
        _initializedControllers.remove(key);
        _initializingKeys.remove(key);
        _releasingKeys.remove(key);
        _lastUsed.remove(key);
        _controllerPool.remove(key);
      }
    }

    // debugPrint('[controllerpool_manager] 🎯 ${videoType.name}类型控制器清理完成');
    _printDecoderStatus();
  }

  /// 9b. 🎯 自動dispose控制器（優雅版本）
  Future<void> _autoDisposeController(
      String keyToDispose, String videoTypeName) async {
    if (!_controllerPool.containsKey(keyToDispose)) {
      debugPrint(
          '[controllerpool_manager] ℹ️ $videoTypeName控制器不存在，無需清理: $keyToDispose');
      return;
    }

    // 🎯 關鍵保護：檢查是否為正在播放的重要控制器
    if (_playingControllers.contains(keyToDispose)) {
      debugPrint(
          '[controllerpool_manager] ⚠️ $videoTypeName控制器正在播放，跳過自動清理: $keyToDispose');

      // 特別保護全屏廣告
      if (keyToDispose.startsWith('fullAd_')) {
        // debugPrint(
        //'[controllerpool_manager] 🛡️ 全屏廣告正在播放，絕對不能清理: $keyToDispose');
        return;
      }
    }

    // 🎯 修復：允許全屏廣告在切換時清理上一個控制器，但要確保不是當前正在播放的
    if (keyToDispose.startsWith('fullAd_')) {
      // 只有當前正在播放的全屏廣告才需要保護，上一個全屏廣告應該被清理
      if (_playingControllers.contains(keyToDispose)) {
        return;
      }
    }
    final wrapper = _controllerPool[keyToDispose]!;

    try {
      // 1. 先暫停播放並從播放列表移除
      if (wrapper.controller.value.isPlaying) {
        await wrapper.controller.pause();
      }
      _playingControllers.remove(keyToDispose);

      // 2. 從所有狀態列表中移除
      _initializedControllers.remove(keyToDispose);
      _initializingKeys.remove(keyToDispose);
      _releasingKeys.remove(keyToDispose);
      _controllerPool.remove(keyToDispose);
      _lastUsed.remove(keyToDispose);

      // 3. 安全dispose控制器
      await _safeDisposeController(wrapper.controller, keyToDispose);
    } catch (e) {
      _playingControllers.remove(keyToDispose);
      _initializedControllers.remove(keyToDispose);
      _initializingKeys.remove(keyToDispose);
      _releasingKeys.remove(keyToDispose);
      _controllerPool.remove(keyToDispose);
      _lastUsed.remove(keyToDispose);
    }
  }

  /// 9bb. 🎯 檢查並處理相同文件路徑的衝突
  Future<void> _checkAndHandleFilePathConflict(
      String filePath, VideoType videoType, String currentKey) async {
    // 查找所有使用相同文件路徑但不同VideoType的控制器
    final conflictingKeys = <String>[];

    for (final existingKey in _controllerPool.keys) {
      if (existingKey != currentKey) {
        // 檢查是否為相同文件但不同類型（通過key比較）
        final existingFileId = _extractFileIdFromKey(existingKey);
        final currentFileId = _extractFileIdFromKey(currentKey);
        if (existingFileId == currentFileId) {
          conflictingKeys.add(existingKey);
        }
      }
    }

    if (conflictingKeys.isNotEmpty) {
      // 根據優先級決定處理策略
      for (final conflictingKey in conflictingKeys) {
        final isConflictingPlaying =
            _playingControllers.contains(conflictingKey);

        if (isConflictingPlaying) {
          // 如果是全屏廣告正在播放，頂部廣告應該等待或跳過
          if (conflictingKey.startsWith('fullAd_') &&
              currentKey.startsWith('topAd_')) {
          }
          // 如果是頂部廣告正在播放，可以讓全屏廣告接管
          else if (conflictingKey.startsWith('topAd_') &&
              currentKey.startsWith('fullAd_')) {
            await _autoDisposeController(conflictingKey, '頂部廣告（被全屏廣告接管）');
          }
          // 🚨 重要：不要自动清理全屏广告，即使有冲突
          else if (conflictingKey.startsWith('fullAd_')) {}
        }
      }
    }
  }

  /// 9cc. 🔧 從控制器key中提取文件ID用於比較
  String _extractFileIdFromKey(String key) {
    // key格式: "videoType_fileId" (例如: "fullAd_20745029", "topAd_20745029")
    // 提取文件ID部分用於比較
    final parts = key.split('_');
    if (parts.length >= 2) {
      return parts.sublist(1).join('_'); // 返回除了videoType之外的部分
    }
    return key;
  }

  /// 9c. 🛡️ 安全dispose控制器（新增方法）
  Future<void> _safeDisposeController(
      VideoPlayerController controller, String key) async {
    try {
      // 检查控制器是否已经dispose或出现错误
      if (controller.value.errorDescription != null) {
        // 如果已经有错误描述，可能已经dispose或出现其他问题
        // debugPrint(
        //'[controllerpool_manager] ⚠️ 控制器有错误描述，可能已dispose: $key, 错误: ${controller.value.errorDescription}');
      }

      // 检查控制器是否已初始化
      if (!controller.value.isInitialized) {
        // debugPrint('[controllerpool_manager] ⚠️ 控制器未初始化，谨慎dispose: $key');
      }

      // 🎯 关键：使用try-catch包围dispose，参考video_player.dart的dispose实现
      // video_player.dart中的dispose方法会检查_isDisposed标志
      await controller.dispose();
      debugPrint('[controllerpool_manager] ✅ 控制器已安全dispose: $key');
    } catch (e) {
      // 捕获所有可能的dispose错误
      final errorMsg = e.toString();
      if (errorMsg.contains('disposed') || errorMsg.contains('Disposed')) {
        // debugPrint('[controllerpool_manager] ℹ️ 控制器已被dispose，跳过: $key');
      } else {
        // debugPrint('[controllerpool_manager] ⚠️ dispose控制器时出错: $key, 错误: $e');
      }
      // 即使dispose失败，也认为已经释放，避免资源泄漏
    }
  }

  /// 9d. 🛠️ 强制检查和修复资源限制（紧急修复方法）
  Future<void> enforceResourceLimits() async {
    // debugPrint('🛠️ 开始强制检查和修复资源限制...');

    // 1. 强制修复初始化控制器数量超限
    while (_initializedControllers.length > _maxInitializedDecoders) {
      // debugPrint(
      //'🚨 强制修复：已初始化控制器超限 (${_initializedControllers.length}/$_maxInitializedDecoders)');
      await _releaseOldestDecoder();

      // 防止无限循环
      await Future.delayed(const Duration(milliseconds: 50));
    }

    // 2. 强制修复播放控制器数量超限
    while (_playingControllers.length > _maxConcurrentPlaying) {
      // debugPrint(
      //          '🚨 强制修复：正在播放控制器超限 (${_playingControllers.length}/$_maxConcurrentPlaying)');
      await _pauseOldestPlaying();

      // 防止无限循环
      await Future.delayed(const Duration(milliseconds: 50));
    }

    // 3. 清理不一致的状态
    final toRemoveFromPlaying = <String>[];
    for (final playingKey in _playingControllers) {
      final wrapper = _controllerPool[playingKey];
      // 检查多种不一致状态
      if (!_initializedControllers.contains(playingKey)) {
        toRemoveFromPlaying.add(playingKey);
        // debugPrint('🧹 清理不一致状态：从播放列表移除未初始化的控制器 $playingKey');
      } else if (wrapper == null) {
        toRemoveFromPlaying.add(playingKey);
        // debugPrint('🧹 清理不一致状态：从播放列表移除不存在的控制器 $playingKey');
      } else if (!wrapper.controller.value.isPlaying) {
        toRemoveFromPlaying.add(playingKey);
        // debugPrint('🧹 清理不一致状态：从播放列表移除已停止的控制器 $playingKey');
      }
    }

    for (final key in toRemoveFromPlaying) {
      _playingControllers.remove(key);
    }

    // debugPrint('✅ 资源限制修复完成');
    _printDecoderStatus();
  }

  /// 10. 生成控制器键
  String _generateControllerKey(String filePath, VideoType videoType) {
    return '${videoType.name}_${filePath.hashCode}';
  }

  /// 10a. 公开的生成控制器键方法（供外部调用）
  String generateControllerKey(String filePath, VideoType videoType) {
    return _generateControllerKey(filePath, videoType);
  }

  /// 11. 释放所有控制器
  Future<void> disposeAll() async {
    // debugPrint('🗑️ 开始释放所有控制器...');

    final keys = List<String>.from(_controllerPool.keys);
    for (final key in keys) {
      await releaseController(
        filePath: _controllerPool[key]!.filePath,
        videoType: _controllerPool[key]!.videoType,
        forceDispose: true,
      );
    }

    _initializedControllers.clear();
    _playingControllers.clear();
    _lastUsed.clear();
    _releasingKeys.clear();
    _currentTopAdKey = null;
    _currentFullAdKey = null;

    // debugPrint('✅ 所有控制器已释放');
  }
}

/// 精确视频控制器包装类
class _PreciseVideoWrapper {
  final VideoPlayerController controller;
  final String filePath;
  final VideoType videoType;
  final DateTime createdAt;
  int useCount;

  _PreciseVideoWrapper({
    required this.controller,
    required this.filePath,
    required this.videoType,
    required this.createdAt,
    this.useCount = 0,
  });
}

/// 视频类型枚举
enum VideoType {
  topAd,
  fullAd,
  announcement,
  other,
}

extension VideoTypeExtension on VideoType {
  String get name => toString().split('.').last;
}

/// 🎯 解码器占用详细说明类
class DecoderResourceExplanation {
  /// 📋 不占用解码器资源的函数方法
  static const List<String> nonDecoderMethods = [
    'VideoPlayerController.file()', // 仅创建对象
    'VideoPlayerController.network()', // 仅创建对象
    'VideoPlayerController.asset()', // 仅创建对象
    'controller.setVolume()', // 设置参数
    'controller.setLooping()', // 设置参数
    'controller.setPlaybackSpeed()', // 设置参数
    'controller.seekTo()', // 设置位置（已初始化后）
    'controller.pause()', // 暂停（不释放解码器）
  ];

  /// 🔥 占用解码器资源的函数方法
  static const List<String> decoderMethods = [
    'controller.initialize()', // 🔑 关键：创建textureId，占用解码器
    'controller.play()', // 开始解码工作（需要已初始化）
  ];

  /// 💥 释放解码器资源的函数方法
  static const List<String> releaseDecoderMethods = [
    'controller.dispose()', // 🔑 关键：释放textureId，释放解码器
  ];

  /// 📖 详细解释
  static String getExplanation() {
    return '''
🔍 解码器资源管理详解：

1. 📱 创建阶段（不占解码器）：
   - VideoPlayerController.file(File file) 
   ↓ 仅创建Dart对象，内存中只有文件路径等元数据
   ↓ textureId = kUninitializedTextureId (-1)
   ↓ 📊 解码器占用：0

2. 🎮 初始化阶段（占用解码器）：
   - controller.initialize()
   ↓ 调用 _videoPlayerPlatform.create(dataSourceDescription)
   ↓ 平台层创建解码器实例和texture
   ↓ textureId = 分配的真实ID (非-1)
   ↓ 📊 解码器占用：+1 ⚠️

3. ▶️ 播放阶段（解码工作）：
   - controller.play()
   ↓ 解码器开始工作，解码视频帧到texture
   ↓ CPU/GPU资源消耗开始
   ↓ 📊 解码器占用：维持+1，但工作负载增加

4. ⏸️ 暂停阶段（保持解码器）：
   - controller.pause()
   ↓ 停止解码工作，但保持textureId
   ↓ 解码器资源仍被占用
   ↓ 📊 解码器占用：维持+1

5. 🗑️ 释放阶段（释放解码器）：
   - controller.dispose()
   ↓ 调用 _videoPlayerPlatform.dispose(textureId)
   ↓ 平台层销毁解码器实例和texture
   ↓ textureId = kUninitializedTextureId (-1)
   ↓ 📊 解码器占用：-1 ✅

💡 关键理解：
- 解码器 = textureId ≠ VideoPlayerController对象
- 可以有20个Controller对象，但只有4个textureId
- 只有initialize()和dispose()会改变解码器占用数量
- 其他所有操作都不影响解码器资源占用
    ''';
  }
}
