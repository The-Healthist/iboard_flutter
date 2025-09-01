import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:iboard_app/managers/file_manager.dart';
import 'package:iboard_app/models/ad_model.dart';
import 'package:iboard_app/utils/precise_video_pool_manager.dart' as precise;
import 'package:iboard_app/providers/ad_full_carousel_provider.dart';

import 'package:provider/provider.dart';
import 'package:logger/logger.dart';
import 'dart:io';

class FullAdWidget extends StatefulWidget {
  final AdModel ad;
  final FileManager fileManager;
  final Function(String adId, Duration position)?
      onVideoProgressChanged; // 视频进度变化回掉
  final VoidCallback? onVideoDisposed; // 视频资源释放完成回掉
  final Duration? initialPlaybackPosition; // 初始播放位置

  const FullAdWidget({
    super.key,
    required this.ad,
    required this.fileManager,
    this.onVideoProgressChanged,
    this.onVideoDisposed,
    this.initialPlaybackPosition,
  });

  @override
  State<FullAdWidget> createState() => _FullAdWidgetState();
}

class _FullAdWidgetState extends State<FullAdWidget> {
  static final Logger _logger = Logger();
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  bool _isLoadingVideo = false;
  String? _errorMessage;
  String? _currentFilePath; // 当前视频文件路径
  bool _isReleasing = false; // 防重入釋放

  // 保存FullscreenAdProvider引用，避免dispose时context访问问题
  FullscreenAdProvider? _fullscreenAdProvider;
  @override
  void initState() {
    super.initState();
    // 在 initState 中尝试获取 FullscreenAdProvider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _fullscreenAdProvider = context.read<FullscreenAdProvider>();
      } catch (e) {
        _logger.e('[ad_full_widget] ❌ 获取 FullscreenAdProvider 失败: $e');
      }
    });

    // 仅在视频类型时初始化
    if (widget.ad.file.mimeType.startsWith('video/')) {
      // 延迟初始化，避免阻塞构建
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _initializeVideoPlayer();
        }
      });
    }
  }

  /// 初始化视频播放器
  Future<void> _initializeVideoPlayer() async {
    if (_videoController != null || !mounted) return;

    setState(() {
      _isLoadingVideo = true;
      _errorMessage = null;
    });

    try {
      // 详细日志：文件获取过程
      // 开始初始化视频: ${widget.ad.file.url}

      // 尝试从FileManager获取本地缓存的视频文件
      final File? localFile = await widget.fileManager.getFile(widget.ad.file);
      if (!mounted) return;

      if (localFile == null || !await localFile.exists()) {
        _logger.e('[ad_full_widget] ❌ 视频文件未缓存: ${widget.ad.file.url}');
        throw Exception('视频文件未缓存');
      }

      // 记录当前文件信息
      _currentFilePath = localFile.path;

      // 🎯 核心改进：通過 FullscreenAdProvider 的精確視頻池管理器取得已初始化控制器
      _fullscreenAdProvider ??= context.read<FullscreenAdProvider>();

      // 🎯 核心改进：使用精确解码器管理器，自動dispose邏輯已內建
      _videoController = await _fullscreenAdProvider!.preciseVideoPoolManager
          .getInitializedController(
        filePath: _currentFilePath!,
        videoType: precise.VideoType.fullAd, // 使用fullAd類型
        autoPlay: true,
        looping: true,
        onError: () {
          debugPrint('[ad_full_widget] ❌ 全屏广告控制器获取失败: $_currentFilePath');
          if (mounted) {
            setState(() {
              _errorMessage = '视频控制器创建失败，显示默认广告';
              _isLoadingVideo = false;
            });
          }
        },
      );

      // 详细的控制器初始化诊断
      if (_videoController != null) {
        debugPrint('[ad_full_widget] ✅ 全屏广告控制器获取成功: ${widget.ad.title}');

        // 添加进度监听器
        _videoController!.addListener(_onVideoProgressChanged);

        if (_videoController!.value.isInitialized) {
          debugPrint(
              '[ad_full_widget] 🎬 全屏广告视频控制器已初始化，開始播放: ${widget.ad.title}');

          try {
            // 🎯 优化：由于autoPlay=true，视频应该已经在播放
            // 只需要确认播放状态，不需要重复设置参数
            if (!_videoController!.value.isPlaying) {
              await _videoController!.play();
              debugPrint('[ad_full_widget] ▶️ 视频开始播放: ${widget.ad.title}');
            } else {
              debugPrint('[ad_full_widget] ▶️ 视频已在播放: ${widget.ad.title}');
            }
          } catch (playError) {
            _logger.e('[ad_full_widget] ❌ 视频播放失败',
                error: playError, stackTrace: StackTrace.current);
            // 不抛出异常，显示默认广告
            setState(() {
              _isVideoInitialized = false;
              _isLoadingVideo = false;
              _errorMessage = null; // 显示默认广告而不是错误
            });
            return;
          }

          setState(() {
            _isVideoInitialized = true;
            _isLoadingVideo = false;
          });
        } else {
          // 如果控制器未初始化，等待初始化完成
          debugPrint('[ad_full_widget] ⏳ 視頻控制器正在初始化，等待完成: ${widget.ad.title}');

          int loadAttempts = 0;
          const maxLoadAttempts = 10;

          while (!_videoController!.value.isInitialized &&
              loadAttempts < maxLoadAttempts &&
              mounted) {
            await Future.delayed(const Duration(milliseconds: 100));
            loadAttempts++;
          }

          if (!_videoController!.value.isInitialized) {
            throw Exception('视频加载超时，无法初始化');
          }

          // 初始化完成后立即播放
          if (!_videoController!.value.isPlaying) {
            await _videoController!.play();
          }

          setState(() {
            _isVideoInitialized = true;
            _isLoadingVideo = false;
          });
        }
      } else {
        // 控制器为null，显示默认广告而不是错误
        debugPrint(
            '[ad_full_widget] ⚠️ 全屏广告控制器为null，显示默认广告: ${widget.ad.title}');
        setState(() {
          _isVideoInitialized = false;
          _isLoadingVideo = false;
          _errorMessage = null; // 清除错误，让它显示默认广告
        });
      }
    } catch (e, stackTrace) {
      _logger.e('[ad_full_widget] ❌ 視頻初始化失败', error: e, stackTrace: stackTrace);

      if (mounted) {
        setState(() {
          _isLoadingVideo = false;
          _errorMessage = '[ad_full_widget] 視頻加載失败: $e';
          _isVideoInitialized = false;
        });
      }
    }
  }

  @override
  void dispose() {
    // 参考顶部广告实现：Widget自己负责释放控制器
    if (_isReleasing) {
      super.dispose();
      return;
    }

    _isReleasing = true;
    // FullAdWidget dispose 开始: ${widget.ad.title}

    if (_videoController != null && _currentFilePath != null) {
      try {
        // 安全地移除监听器 - 这个总是需要的
        _videoController!.removeListener(_onVideoProgressChanged);
      } catch (e) {
        _logger.w('[ad_full_widget] 移除監聽器時出錯: $e');
      }

      // 🎯 关键改进：参考顶部广告，Widget自己释放控制器到池中
      _releaseVideoControllerToPool().then((_) {
        _logger
            .d('[ad_full_widget] ✅ FullAdWidget dispose完成: ${widget.ad.title}');
      }).catchError((error) {
        _logger.e('❌ FullAdWidget dispose释放控制器出错: $error');
      });

      _videoController = null;
      _currentFilePath = null;
    } else {
      _logger.d('[ad_full_widget] ✅ 无需释放控制器 - 控制器为空或路径为空');
    }

    super.dispose();
  }

  ///0，视频播放进度变化监听器
  void _onVideoProgressChanged() {
    try {
      if (_videoController != null &&
          _videoController!.value.isInitialized &&
          widget.onVideoProgressChanged != null &&
          mounted) {
        widget.onVideoProgressChanged!(widget.ad.id.toString(), Duration.zero);
      }
    } catch (e) {
      debugPrint('[ad_full_widget] ⚠️ 视频进度监听器出错: $e');
    }
  }

  ///1，处理轮播切换时的清理 - 参考顶部广告实现
  Future<void> _handleCarouselSwitch() async {
    if (_videoController != null) {
      // 全屏广告处理轮播切换，释放控制器: ${widget.ad.title}
      // 直接释放控制器（释放方法内部已包含暂停逻辑）
      await _releaseVideoControllerToPool();
    }
  }

  ///2，暂停视频播放 - 参考顶部广告实现
  Future<void> _pauseVideo() async {
    if (_videoController != null) {
      try {
        if (_videoController!.value.isInitialized &&
            !_videoController!.value.hasError &&
            _videoController!.value.isPlaying) {
          await _videoController!.pause();
          // 暂停全屏广告视频播放: ${widget.ad.title}
        }
      } catch (e) {
        _logger.w('[ad_full_widget] ⚠️ 暂停视频播放失败: $e');
      }
    }
  }

  ///3，恢复视频播放 - 参考顶部广告实现
  Future<void> _resumeVideo() async {
    if (_videoController != null) {
      try {
        // 检查视频是否处于暂停状态
        if (_videoController!.value.isInitialized &&
            !_videoController!.value.hasError &&
            !_videoController!.value.isPlaying) {
          await _videoController!.play();
          // 恢复全屏广告视频播放: ${widget.ad.title}
        }
      } catch (e) {
        _logger.w('[ad_full_widget] ⚠️ 恢复视频播放失败: $e');
      }
    }
  }

  ///4，释放视频控制器到池中 - 参考顶部广告实现
  Future<void> _releaseVideoControllerToPool() async {
    if (_videoController != null && _currentFilePath != null) {
      try {
        // 开始释放全屏广告控制器到池中: $_currentFilePath

        // 先暂停视频播放
        if (_videoController!.value.isPlaying) {
          await _videoController!.pause();
        }

        // 确保FullscreenAdProvider引用可用
        _fullscreenAdProvider ??= context.read<FullscreenAdProvider>();

        if (_fullscreenAdProvider != null) {
          // 🎯 使用精確視頻池管理器释放控制器
          await _fullscreenAdProvider!.preciseVideoPoolManager
              .releaseController(
            filePath: _currentFilePath!,
            videoType: precise.VideoType.fullAd,
            forceDispose: true, // 全屏广告切换时强制释放解码器资源
          );

          _logger.d('[ad_full_widget] ✅ 全屏广告视频控制器已释放到池中: ${widget.ad.title}');

          // 调用回调
          if (widget.onVideoDisposed != null) {
            widget.onVideoDisposed!();
          }
        } else {
          _logger
              .w('[ad_full_widget] ⚠️ FullscreenAdProvider引用为空，无法释放全屏广告视频控制器');
        }
      } catch (e) {
        _logger.w('[ad_full_widget] ⚠️ 释放全屏广告视频控制器时出错: $e');
      }

      _videoController = null;
      _currentFilePath = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: Stack(
        children: [
          // 广告内容显示
          _buildAdContent(),
        ],
      ),
    );
  }

  ///5，構建廣告內容
  Widget _buildAdContent() {
    // 根據文件類型顯示不同的內容
    if (widget.ad.file.mimeType.startsWith('image/')) {
      return _buildImageAd();
    } else if (widget.ad.file.mimeType.startsWith('video/')) {
      return _buildVideoAd();
    } else {
      return _buildDefaultAd();
    }
  }

  ///6，構建圖片廣告
  Widget _buildImageAd() {
    return FutureBuilder<File?>(
      future: widget.fileManager.getFile(widget.ad.file),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.black,
            child: const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          );
        }

        if (snapshot.hasData && snapshot.data != null) {
          final localFile = snapshot.data!;
          return SizedBox(
            width: double.infinity,
            height: double.infinity,
            child: Image.file(
              localFile,
              fit: BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (context, error, stackTrace) {
                debugPrint('[ad_full_widget] 本地圖片加載失敗: $error');
                return _buildNetworkImage();
              },
            ),
          );
        }

        // 如果本地文件不存在，顯示默認廣告而不是嘗試網絡加載
        // _logger.w('本地圖片文件不存在，顯示默認廣告: ${widget.ad.file.url}');
        return _buildDefaultAd();
      },
    );
  }

  ///7，構建網絡圖片
  Widget _buildNetworkImage() {
    return Image.network(
      widget.ad.file.url,
      fit: BoxFit.contain,
      width: double.infinity,
      height: double.infinity,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          color: Colors.black,
          child: Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded /
                      loadingProgress.expectedTotalBytes!
                  : null,
              color: Colors.white,
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return _buildDefaultAd();
      },
    );
  }

  ///8，構建視頻廣告
  Widget _buildVideoAd() {
    if (_isLoadingVideo) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 20),
              SelectableText(
                '正在加載視頻...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 如果有错误信息或控制器为null，显示默认广告
    if (_errorMessage != null ||
        !_isVideoInitialized ||
        _videoController == null) {
      return _buildDefaultAd();
    }

    // 確保視頻控制器已初始化並可播放
    if (_videoController != null && _videoController!.value.isInitialized) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black, // 添加黑色背景，避免视频周围空白
        child: Center(
          child: AspectRatio(
            aspectRatio: _videoController!.value.aspectRatio,
            child: VideoPlayer(_videoController!),
          ),
        ),
      );
    }

    // 其他情况也显示默认广告
    return _buildDefaultAd();
  }

  ///9，構建默認廣告
  Widget _buildDefaultAd() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF2196F3).withOpacity(0.8),
            const Color(0xFF1976D2).withOpacity(0.9),
          ],
        ),
      ),
      child: Stack(
        children: [
          // 背景图案
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                image: null, // AdModel没有imageUrls属性，使用纯色背景
              ),
            ),
          ),
          // 内容区域
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 广告图标
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.play_circle_outline,
                    size: 50,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),
                // 广告标题
                Text(
                  widget.ad.title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        offset: Offset(0, 2),
                        blurRadius: 4,
                        color: Colors.black54,
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                // 广告描述
                if (widget.ad.description.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      widget.ad.description,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            offset: Offset(0, 1),
                            blurRadius: 2,
                            color: Colors.black54,
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                const SizedBox(height: 30),
                // 提示文本
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    '📺 静态广告展示',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
