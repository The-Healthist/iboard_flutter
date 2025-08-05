import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:logger/logger.dart';

/// 视频资源管理器 - 确保安全的视频控制器生命周期管理
class VideoResourceManager {
  static final Logger _logger = Logger();

  /// 等待视频控制器完全停止的最大时间
  static const Duration _maxWaitTime = Duration(seconds: 5);

  ///1，安全初始化视频控制器
  static Future<VideoPlayerController?> safeInitialize({
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
          _logger.e('🔴 视频播放错误: ${controller.value.errorDescription}');
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

      _logger.i('✅ 视频控制器初始化成功: $filePath');
      return controller;
    } catch (e) {
      _logger.e('❌ 视频控制器初始化失败: $e');
      onError?.call();
      return null;
    }
  }

  ///2，安全释放视频控制器 - 基于状态监听
  static Future<bool> safeDispose(VideoPlayerController controller) async {
    final completer = Completer<bool>();
    Timer? timeoutTimer;

    try {
      _logger.i('🔄 开始安全释放视频控制器');

      // 设置超时保护
      timeoutTimer = Timer(_maxWaitTime, () {
        if (!completer.isCompleted) {
          _logger.w('⚠️ 视频控制器释放超时，强制释放');
          completer.complete(false);
        }
      });

      // 如果控制器未初始化，直接释放
      if (!controller.value.isInitialized) {
        controller.dispose();
        completer.complete(true);
        return completer.future;
      }

      // 如果正在播放，先暂停
      if (controller.value.isPlaying) {
        await controller.pause();
        _logger.d('📱 视频已暂停');
      }

      // 监听视频状态变化，等待完全停止
      void stateListener() {
        if (!completer.isCompleted) {
          final value = controller.value;

          // 检查是否已完全停止
          if (!value.isPlaying && !value.isBuffering && value.isInitialized) {
            _logger.d('📱 视频已完全停止，开始释放资源');

            // 延迟一小段时间确保MediaCodec状态稳定
            Future.delayed(Duration(milliseconds: 50), () {
              try {
                controller.dispose();
                _logger.i('✅ 视频控制器已安全释放');
                if (!completer.isCompleted) {
                  completer.complete(true);
                }
              } catch (e) {
                _logger.e('❌ 释放视频控制器时出错: $e');
                if (!completer.isCompleted) {
                  completer.complete(false);
                }
              }
            });
          }
        }
      }

      controller.addListener(stateListener);

      // 如果视频已经停止，直接触发释放
      if (!controller.value.isPlaying && !controller.value.isBuffering) {
        Future.delayed(Duration(milliseconds: 10), () {
          if (!completer.isCompleted) {
            try {
              controller.dispose();
              _logger.i('✅ 视频控制器已安全释放（已停止状态）');
              completer.complete(true);
            } catch (e) {
              _logger.e('❌ 释放视频控制器时出错: $e');
              completer.complete(false);
            }
          }
        });
      }
    } catch (e) {
      _logger.e('❌ 安全释放过程中出错: $e');
      // 尝试强制释放
      try {
        controller.dispose();
      } catch (disposeError) {
        _logger.e('❌ 强制释放也失败: $disposeError');
      }
      completer.complete(false);
    }

    // 等待完成并清理资源
    final result = await completer.future;
    timeoutTimer?.cancel();

    return result;
  }

  ///3，安全暂停视频
  static Future<bool> safePause(VideoPlayerController controller) async {
    try {
      if (controller.value.isInitialized && controller.value.isPlaying) {
        await controller.pause();

        // 等待暂停状态确认
        int attempts = 0;
        while (controller.value.isPlaying && attempts < 10) {
          await Future.delayed(Duration(milliseconds: 50));
          attempts++;
        }

        final success = !controller.value.isPlaying;
        _logger.d(success ? '✅ 视频已安全暂停' : '⚠️ 视频暂停状态不确定');
        return success;
      }
      return true; // 已经暂停或未初始化
    } catch (e) {
      _logger.e('❌ 暂停视频时出错: $e');
      return false;
    }
  }

  ///4，安全播放视频
  static Future<bool> safePlay(VideoPlayerController controller) async {
    try {
      if (controller.value.isInitialized && !controller.value.isPlaying) {
        await controller.play();

        // 等待播放状态确认
        int attempts = 0;
        while (!controller.value.isPlaying && attempts < 10) {
          await Future.delayed(Duration(milliseconds: 50));
          attempts++;
        }

        final success = controller.value.isPlaying;
        _logger.d(success ? '✅ 视频已安全播放' : '⚠️ 视频播放状态不确定');
        return success;
      }
      return true; // 已经播放或未初始化
    } catch (e) {
      _logger.e('❌ 播放视频时出错: $e');
      return false;
    }
  }

  ///5，检查控制器状态
  static VideoControllerState getControllerState(
      VideoPlayerController controller) {
    try {
      if (!controller.value.isInitialized) {
        return VideoControllerState.uninitialized;
      }

      if (controller.value.hasError) {
        return VideoControllerState.error;
      }

      if (controller.value.isPlaying) {
        return VideoControllerState.playing;
      }

      if (controller.value.isBuffering) {
        return VideoControllerState.buffering;
      }

      return VideoControllerState.paused;
    } catch (e) {
      _logger.e('❌ 检查控制器状态时出错: $e');
      return VideoControllerState.error;
    }
  }
}

/// 视频控制器状态枚举
enum VideoControllerState {
  uninitialized,
  playing,
  paused,
  buffering,
  error,
}

/// 视频资源管理器扩展
extension VideoControllerExtension on VideoPlayerController {
  ///1，安全释放
  Future<bool> safeDispose() async {
    return VideoResourceManager.safeDispose(this);
  }

  ///2，安全暂停
  Future<bool> safePause() async {
    return VideoResourceManager.safePause(this);
  }

  ///3，安全播放
  Future<bool> safePlay() async {
    return VideoResourceManager.safePlay(this);
  }

  ///4，获取状态
  VideoControllerState get safeState {
    return VideoResourceManager.getControllerState(this);
  }
}
