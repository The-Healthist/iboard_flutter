import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:iboard_app/managers/file_manager.dart';
import 'package:iboard_app/models/ad_model.dart';
import 'package:iboard_app/utils/precise_video_pool_manager.dart' as precise;
import 'package:iboard_app/providers/ad_full_carousel_provider.dart';

import 'package:provider/provider.dart';
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
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  bool _isLoadingVideo = false;
  String? _errorMessage;
  String? _currentFilePath;
  bool _isReleasing = false;
  FullscreenAdProvider? _fullscreenAdProvider;
  @override
  void initState() {
    super.initState();
    // 在 initState 中尝试获取 FullscreenAdProvider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _fullscreenAdProvider = context.read<FullscreenAdProvider>();
      } catch (e) {
        // 静默处理获取 Provider 失败
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
      final File? localFile = await widget.fileManager.getFile(widget.ad.file);
      if (!mounted) return;

      if (localFile == null || !await localFile.exists()) {
        throw Exception('视频文件未缓存');
      }

      _currentFilePath = localFile.path;

      _fullscreenAdProvider ??= context.read<FullscreenAdProvider>();

      _videoController = await _fullscreenAdProvider!.preciseVideoPoolManager
          .getInitializedController(
        filePath: _currentFilePath!,
        videoType: precise.VideoType.fullAd,
        autoPlay: true,
        looping: true,
        onError: () {
          if (mounted) {
            setState(() {
              _errorMessage = '视频控制器创建失败，显示默认广告';
              _isLoadingVideo = false;
            });
          }
        },
      );

      if (_videoController != null) {
        _videoController!.addListener(_onVideoProgressChanged);

        if (_videoController!.value.isInitialized) {
          try {
            if (!_videoController!.value.isPlaying) {
              await _videoController!.play();
            }
          } catch (playError) {
            setState(() {
              _isVideoInitialized = false;
              _isLoadingVideo = false;
              _errorMessage = null;
            });
            return;
          }

          setState(() {
            _isVideoInitialized = true;
            _isLoadingVideo = false;
          });
        } else {
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

          if (!_videoController!.value.isPlaying) {
            await _videoController!.play();
          }

          setState(() {
            _isVideoInitialized = true;
            _isLoadingVideo = false;
          });
        }
      } else {
        setState(() {
          _isVideoInitialized = false;
          _isLoadingVideo = false;
          _errorMessage = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingVideo = false;
          _errorMessage = '視頻加載失败';
          _isVideoInitialized = false;
        });
      }
    }
  }

  @override
  void dispose() {
    if (_isReleasing) {
      super.dispose();
      return;
    }

    _isReleasing = true;

    if (_videoController != null && _currentFilePath != null) {
      try {
        _videoController!.removeListener(_onVideoProgressChanged);
      } catch (e) {
        // 静默处理移除监听器错误
      }

      _releaseVideoControllerToPool();
      _videoController = null;
      _currentFilePath = null;
    }

    super.dispose();
  }

  ///1，视频播放进度变化监听器
  void _onVideoProgressChanged() {
    try {
      if (_videoController != null &&
          _videoController!.value.isInitialized &&
          widget.onVideoProgressChanged != null &&
          mounted) {
        widget.onVideoProgressChanged!(widget.ad.id.toString(), Duration.zero);
      }
    } catch (e) {
      // 静默处理进度监听器错误
    }
  }

  ///2，处理轮播切换时的清理
  Future<void> _handleCarouselSwitch() async {
    if (_videoController != null) {
      await _releaseVideoControllerToPool();
    }
  }

  ///3，暂停视频播放
  Future<void> _pauseVideo() async {
    if (_videoController != null) {
      try {
        if (_videoController!.value.isInitialized &&
            !_videoController!.value.hasError &&
            _videoController!.value.isPlaying) {
          await _videoController!.pause();
        }
      } catch (e) {
        // 静默处理暂停失败
      }
    }
  }

  ///4，恢复视频播放
  Future<void> _resumeVideo() async {
    if (_videoController != null) {
      try {
        if (_videoController!.value.isInitialized &&
            !_videoController!.value.hasError &&
            !_videoController!.value.isPlaying) {
          await _videoController!.play();
        }
      } catch (e) {
        // 静默处理恢复播放失败
      }
    }
  }

  ///5，释放视频控制器到池中
  Future<void> _releaseVideoControllerToPool() async {
    if (_videoController != null && _currentFilePath != null) {
      try {
        if (_videoController!.value.isPlaying) {
          await _videoController!.pause();
        }

        _fullscreenAdProvider ??= context.read<FullscreenAdProvider>();

        if (_fullscreenAdProvider != null) {
          await _fullscreenAdProvider!.preciseVideoPoolManager
              .releaseController(
            filePath: _currentFilePath!,
            videoType: precise.VideoType.fullAd,
            forceDispose: true,
          );

          if (widget.onVideoDisposed != null) {
            widget.onVideoDisposed!();
          }
        }
      } catch (e) {
        // 静默处理释放控制器错误
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

  ///6，構建廣告內容
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

  ///7，構建圖片廣告
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
              fit: BoxFit.fill,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (context, error, stackTrace) {
                return _buildNetworkImage();
              },
            ),
          );
        }

        return _buildDefaultAd();
      },
    );
  }

  ///8，構建網絡圖片
  Widget _buildNetworkImage() {
    return Image.network(
      widget.ad.file.url,
      fit: BoxFit.fill,
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

  ///9，構建視頻廣告
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

    if (_errorMessage != null ||
        !_isVideoInitialized ||
        _videoController == null) {
      return _buildDefaultAd();
    }

    if (_videoController != null && _videoController!.value.isInitialized) {
      final videoSize = _videoController!.value.size;
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black,
        child: FittedBox(
          fit: BoxFit.fill,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: videoSize.width == 0 ? 1 : videoSize.width,
            height: videoSize.height == 0 ? 1 : videoSize.height,
            child: VideoPlayer(_videoController!),
          ),
        ),
      );
    }

    return _buildDefaultAd();
  }

  ///10，構建默認廣告
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
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(),
            ),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
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
