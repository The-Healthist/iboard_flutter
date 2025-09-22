import 'dart:io';
import 'package:flutter/material.dart';
import 'package:iboard_app/models/ad_model.dart'; // Assuming AdModel exists
import 'package:iboard_app/managers/file_manager.dart'; // Assuming FileManager exists
import 'package:iboard_app/providers/state_provider.dart';
import 'package:iboard_app/widgets/carousel_widget.dart'; // 导入通知类
import 'package:iboard_app/utils/precise_video_pool_manager.dart' as precise;
import 'package:iboard_app/providers/ad_top_carousel_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:provider/provider.dart';

class TopAdWidget extends StatefulWidget {
  final AdModel ad;
  final FileManager fileManager;

  const TopAdWidget({
    super.key,
    required this.ad,
    required this.fileManager,
  });

  @override
  TopAdWidgetState createState() => TopAdWidgetState();
}

class TopAdWidgetState extends State<TopAdWidget> {
  VideoPlayerController? _videoController;
  bool _isLoading = true;
  String? _localFilePath;
  String? _currentVideoPath;
  String? _error;
  bool isManuallyPaused = false;
  bool _isDownloading = false;
  int _retryCount = 0;
  static const int _maxRetries = 3;
  TopAdCarouselProvider? _topAdCarouselProvider;

  @override
  void initState() {
    super.initState();
    _loadFile();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _topAdCarouselProvider ??= context.read<TopAdCarouselProvider>();
  }

  //1，加载广告文件
  Future<void> _loadFile([bool isRetry = false]) async {
    if (!isRetry) {
      _retryCount = 0;
    }

    setState(() {
      _isLoading = true;
      _isDownloading = false;
      _error = null;
    });

    if (widget.ad.file.localFilePath != null &&
        await File(widget.ad.file.localFilePath!).exists()) {
      _localFilePath = widget.ad.file.localFilePath;
    } else {
      setState(() {
        _isDownloading = true;
      });

      final File? downloadedFile =
          await widget.fileManager.getFile(widget.ad.file);

      setState(() {
        _isDownloading = false;
      });

      if (downloadedFile != null) {
        _localFilePath = downloadedFile.path;
      } else {
        if (_retryCount >= _maxRetries) {
          _error = 'Failed to load ad file after $_maxRetries attempts.';
        } else {
          _retryCount++;
          await Future.delayed(Duration(seconds: 2 * _retryCount));
          if (mounted) {
            return _loadFile(true);
          }
        }
      }
    }

    if (_localFilePath != null) {
      final mimeType = widget.ad.file.mimeType.toLowerCase();
      if (mimeType == 'video/mp4') {
        _initializeVideoPlayer();
      } else if (mimeType.startsWith('image/')) {
        setState(() {
          _isLoading = false;
        });
      } else {
        _error = 'Unsupported ad file type: $mimeType';
        setState(() {
          _isLoading = false;
        });
      }
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  ///2，初始化视频播放器 - 使用视频池管理器
  Future<void> _initializeVideoPlayer() async {
    if (_localFilePath == null || !mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    if (_videoController != null && _currentVideoPath != _localFilePath) {
      _topAdCarouselProvider ??= context.read<TopAdCarouselProvider>();
      await _topAdCarouselProvider!.preciseVideoPoolManager.releaseController(
        filePath: _currentVideoPath!,
        videoType: precise.VideoType.topAd,
        forceDispose: true,
      );
      _videoController = null;
      _currentVideoPath = null;
    }

    if (_videoController != null && _currentVideoPath == _localFilePath) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      if (!mounted) return;
      _topAdCarouselProvider ??= context.read<TopAdCarouselProvider>();

      _videoController = await _topAdCarouselProvider!.preciseVideoPoolManager
          .getInitializedController(
        filePath: _localFilePath!,
        videoType: precise.VideoType.topAd,
        autoPlay: true,
        looping: true,
        onError: () {
          if (mounted) {
            setState(() {
              _error = '视频控制器创建失败，将显示占位符';
              _isLoading = false;
            });
          }
        },
      );

      if (_videoController != null) {
        final carouselStateProvider = context.read<CarouselStateProvider>();
        final isFullscreenAd =
            carouselStateProvider.currentAppState == AppState.fullscreenAd;

        if (isFullscreenAd) {
          await _videoController!.setVolume(0.0);
        }
      }

      if (_videoController != null && mounted) {
        _currentVideoPath = _localFilePath;
        setState(() {
          _isLoading = false;
        });
      } else if (mounted) {
        setState(() {
          _error = null;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not create video player.';
          _isLoading = false;
        });
      }
    }
  }

  //3，暂停视频播放
  Future<void> _pauseVideo() async {
    if (_videoController != null) {
      try {
        if (_videoController!.value.isInitialized &&
            !_videoController!.value.hasError &&
            _videoController!.value.isPlaying) {
          await _videoController!.pause();
          isManuallyPaused = true;
        }
      } catch (e) {
        // 静默处理暂停失败
      }
    }
  }

  //4，恢复视频播放
  Future<void> _resumeVideo() async {
    if (_videoController != null) {
      try {
        if (_videoController!.value.isInitialized &&
            !_videoController!.value.hasError &&
            !_videoController!.value.isPlaying) {
          await _videoController!.play();
          isManuallyPaused = false;
        }
      } catch (e) {
        // 静默处理恢复播放失败
      }
    }
  }

  //5，处理轮播切换时的清理
  Future<void> _handleCarouselSwitch() async {
    if (_videoController != null) {
      await _releaseVideoController(forceDispose: true);
    }
  }

  @override
  void dispose() {
    _releaseVideoController();
    super.dispose();
  }

  ///释放视频控制器到池中
  Future<void> _releaseVideoController({bool forceDispose = false}) async {
    if (_videoController != null && _currentVideoPath != null) {
      try {
        _topAdCarouselProvider ??= context.read<TopAdCarouselProvider>();

        if (_topAdCarouselProvider != null) {
          if (_videoController!.value.isPlaying) {
            await _videoController!.pause();
          }

          await _topAdCarouselProvider!.preciseVideoPoolManager
              .releaseController(
            filePath: _currentVideoPath!,
            videoType: precise.VideoType.topAd,
            forceDispose: forceDispose,
          );
        }
      } catch (e) {
        // 静默处理释放控制器错误
      }

      _videoController = null;
      _currentVideoPath = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final carouselStateProvider = context.watch<CarouselStateProvider>();
    final isMediaPaused =
        carouselStateProvider.isMediaPausedForArea(AreaType.topAd);

    if (_videoController != null && _videoController!.value.isInitialized) {
      final isPlaying = _videoController!.value.isPlaying;
      final isFullscreenAd =
          carouselStateProvider.currentAppState == AppState.fullscreenAd;

      Future.delayed(const Duration(milliseconds: 50), () {
        if (mounted &&
            _videoController != null &&
            _videoController!.value.isInitialized) {
          if (isFullscreenAd) {
            _videoController!.setVolume(0.0);
          } else {
            _videoController!.setVolume(1.0);
          }
        }
      });

      if (isMediaPaused && isPlaying) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted &&
              _videoController != null &&
              _videoController!.value.isInitialized &&
              _videoController!.value.isPlaying) {
            _videoController!.pause();
          }
        });
      } else if (!isMediaPaused && !isPlaying) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted &&
              _videoController != null &&
              _videoController!.value.isInitialized &&
              !_videoController!.value.isPlaying) {
            _videoController!.play();
          }
        });
      }
    }

    return NotificationListener<Notification>(
      onNotification: (notification) {
        if (notification is MediaPauseNotification) {
          final carouselStateProvider = context.read<CarouselStateProvider>();
          final isFullscreenAd =
              carouselStateProvider.currentAppState == AppState.fullscreenAd;

          if (isFullscreenAd) {
            Future.delayed(const Duration(milliseconds: 50), () {
              if (mounted) {
                _handleCarouselSwitch();
              }
            });
          } else {
            Future.delayed(const Duration(milliseconds: 50), () {
              if (mounted &&
                  _videoController != null &&
                  _videoController!.value.isInitialized &&
                  _videoController!.value.isPlaying) {
                _pauseVideo();
              }
            });
          }
          return true;
        } else if (notification is MediaResumeNotification) {
          Future.delayed(const Duration(milliseconds: 50), () {
            if (mounted &&
                _videoController != null &&
                _videoController!.value.isInitialized &&
                !_videoController!.value.isPlaying) {
              _resumeVideo();
            }
          });
          return true;
        }
        return false;
      },
      child: _buildContent(),
    );
  }

  //5，构建内容部分
  Widget _buildContent() {
    Widget contentWidget;

    if (_isLoading) {
      // 根据是否在下载显示不同的加载状态
      if (_isDownloading) {
        contentWidget = Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text(
                '正在下載廣告內容... (${_retryCount > 0 ? '重試 $_retryCount/$_maxRetries' : ''})',
                style: const TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      } else {
        contentWidget = const Center(child: CircularProgressIndicator());
      }
    } else if (_error != null) {
      contentWidget = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.warning_amber_outlined,
                color: Colors.orange, size: 40),
            const SizedBox(height: 8),
            const Text(
              '廣告內容載入失敗',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
            const SizedBox(height: 4),
            const Text(
              '將在下個週期重新嘗試',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => _loadFile(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              ),
              child: const Text('立即重試', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      );
    } else if (_localFilePath == null) {
      // This case should ideally be covered by _error, but as a fallback:
      contentWidget = const Center(child: Text('Ad file not available.'));
    } else {
      final mimeType = widget.ad.file.mimeType.toLowerCase();

      if (mimeType == 'video/mp4') {
        if (_videoController != null && _videoController!.value.isInitialized) {
          contentWidget = SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.fill,
              child: SizedBox(
                width: _videoController!.value.size.width,
                height: _videoController!.value.size.height,
                child: VideoPlayer(_videoController!),
              ),
            ),
          );
        } else {
          // 视频控制器创建失败，显示优雅的占位符
          contentWidget = _buildVideoPlaceholder();
        }
      } else if (mimeType == 'image/jpeg' ||
          mimeType == 'image/jpg' ||
          mimeType == 'image/png' ||
          mimeType == 'image/gif') {
        contentWidget = SizedBox.expand(
          child: Image.file(
            File(_localFilePath!),
            fit: BoxFit.fill, // 忽略比例，彻底填满区域
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (context, error, stackTrace) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _error == null) {
                  setState(() {
                    _error = 'Could not display ad image.';
                  });
                }
              });
              return const Center(child: Text('Could not display ad image.'));
            },
          ),
        );
      } else {
        contentWidget =
            Center(child: Text('Unsupported ad file type: $mimeType'));
      }
    }

    return contentWidget;
  }

  /// 构建视频占位符
  Widget _buildVideoPlaceholder() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.blue.shade200,
            Colors.blue.shade400,
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.video_library_outlined,
              size: 40,
              color: Colors.white.withOpacity(0.8),
            ),
            const SizedBox(height: 8),
            Text(
              widget.ad.title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.white.withOpacity(0.9),
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
