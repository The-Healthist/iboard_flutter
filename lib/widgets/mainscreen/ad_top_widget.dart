import 'dart:io';
import 'package:flutter/material.dart';
import 'package:iboard_app/models/ad_model.dart'; // Assuming AdModel exists
import 'package:iboard_app/managers/file_manager.dart'; // Assuming FileManager exists
import 'package:iboard_app/providers/state_provider.dart';
import 'package:iboard_app/widgets/carousel/carousel_widget.dart'; // 导入通知类
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

class TopAdWidgetState extends State<TopAdWidget> with WidgetsBindingObserver {
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
  bool _isDisposed = false;
  bool _isReleasingVideo = false;
  int _loadGeneration = 0;
  int _mediaCommandGeneration = 0;
  bool? _lastAppliedMediaPaused;
  bool? _lastAppliedFullscreenAd;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadFile();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _topAdCarouselProvider ??= context.read<TopAdCarouselProvider>();
  }

  //1，加载广告文件
  Future<void> _loadFile([bool isRetry = false]) async {
    if (!mounted || _isDisposed) return;
    final int generation = ++_loadGeneration;

    if (!isRetry) {
      _retryCount = 0;
    }

    _setStateIfActive(generation, () {
      _isLoading = true;
      _isDownloading = false;
      _error = null;
    });

    if (widget.ad.file.localFilePath != null &&
        await File(widget.ad.file.localFilePath!).exists()) {
      _localFilePath = widget.ad.file.localFilePath;
    } else {
      _setStateIfActive(generation, () {
        _isDownloading = true;
      });

      final File? downloadedFile =
          await widget.fileManager.getFile(widget.ad.file);

      if (!_isActiveGeneration(generation)) return;

      _setStateIfActive(generation, () {
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
          if (_isActiveGeneration(generation)) {
            return _loadFile(true);
          }
        }
      }
    }

    if (!_isActiveGeneration(generation)) return;

    if (_localFilePath != null) {
      final mimeType = widget.ad.file.mimeType.toLowerCase();
      if (mimeType == 'video/mp4') {
        _initializeVideoPlayer(generation);
      } else if (mimeType.startsWith('image/')) {
        _setStateIfActive(generation, () {
          _isLoading = false;
        });
      } else {
        _error = 'Unsupported ad file type: $mimeType';
        _setStateIfActive(generation, () {
          _isLoading = false;
        });
      }
    } else {
      _setStateIfActive(generation, () {
        _isLoading = false;
      });
    }
  }

  ///2，初始化视频播放器 - 使用视频池管理器
  Future<void> _initializeVideoPlayer(int generation) async {
    if (_localFilePath == null || !_isActiveGeneration(generation)) return;
    final topAdCarouselProvider =
        _topAdCarouselProvider ?? context.read<TopAdCarouselProvider>();
    _topAdCarouselProvider = topAdCarouselProvider;
    final shouldMuteOnInit =
        context.read<CarouselStateProvider>().currentAppState ==
            AppState.fullscreenAd;

    _setStateIfActive(generation, () {
      _isLoading = true;
      _error = null;
    });

    if (_videoController != null && _currentVideoPath != _localFilePath) {
      final oldPath = _currentVideoPath!;
      _videoController = null;
      _currentVideoPath = null;
      _mediaCommandGeneration++;

      await topAdCarouselProvider.preciseVideoPoolManager.releaseController(
        filePath: oldPath,
        videoType: precise.VideoType.topAd,
        forceDispose: true,
      );
      if (!_isActiveGeneration(generation)) return;
    }

    if (_videoController != null && _currentVideoPath == _localFilePath) {
      _setStateIfActive(generation, () {
        _isLoading = false;
      });
      return;
    }

    try {
      if (!_isActiveGeneration(generation)) return;

      final controller = await topAdCarouselProvider.preciseVideoPoolManager
          .getInitializedController(
        filePath: _localFilePath!,
        videoType: precise.VideoType.topAd,
        autoPlay: true,
        looping: true,
        onError: () {
          if (_isActiveGeneration(generation)) {
            setState(() {
              _error = '视频控制器创建失败，将显示占位符';
              _isLoading = false;
            });
          }
        },
      );

      if (!_isActiveGeneration(generation)) {
        if (controller != null && _localFilePath != null) {
          await topAdCarouselProvider.preciseVideoPoolManager.releaseController(
            filePath: _localFilePath!,
            videoType: precise.VideoType.topAd,
            forceDispose: true,
          );
        }
        return;
      }

      _videoController = controller;

      if (_videoController != null) {
        if (shouldMuteOnInit) {
          await _setControllerVolume(_videoController!, 0.0);
        }
      }

      if (_videoController != null && _isActiveGeneration(generation)) {
        _currentVideoPath = _localFilePath;
        _setStateIfActive(generation, () {
          _isLoading = false;
        });
        _syncMediaStateFromContext();
      } else if (_isActiveGeneration(generation)) {
        _setStateIfActive(generation, () {
          _error = null;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (_isActiveGeneration(generation)) {
        _setStateIfActive(generation, () {
          _error = 'Could not create video player.';
          _isLoading = false;
        });
      }
    }
  }

  //3，暂停视频播放
  Future<void> _pauseVideo() async {
    final controller = _videoController;
    if (_isControllerActive(controller)) {
      await _pauseController(controller!);
      isManuallyPaused = true;
    }
  }

  //4，恢复视频播放
  Future<void> _resumeVideo() async {
    final controller = _videoController;
    if (_isControllerActive(controller)) {
      await _playController(controller!);
      isManuallyPaused = false;
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
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _loadGeneration++;
    _mediaCommandGeneration++;
    _releaseVideoController();
    super.dispose();
  }

  @override
  void didHaveMemoryPressure() {
    _releaseVideoController(forceDispose: true);
    super.didHaveMemoryPressure();
  }

  ///释放视频控制器到池中
  Future<void> _releaseVideoController({bool forceDispose = false}) async {
    if (_isReleasingVideo) return;

    final controller = _videoController;
    final videoPath = _currentVideoPath;

    _videoController = null;
    _currentVideoPath = null;
    _loadGeneration++;
    _mediaCommandGeneration++;
    _lastAppliedMediaPaused = null;
    _lastAppliedFullscreenAd = null;

    if (controller != null && videoPath != null) {
      _isReleasingVideo = true;
      try {
        if (mounted && !_isDisposed) {
          _topAdCarouselProvider ??= context.read<TopAdCarouselProvider>();
        }

        if (_topAdCarouselProvider != null) {
          await _pauseController(controller);

          await _topAdCarouselProvider!.preciseVideoPoolManager
              .releaseController(
            filePath: videoPath,
            videoType: precise.VideoType.topAd,
            forceDispose: forceDispose,
          );
        }
      } catch (e) {
        // 静默处理释放控制器错误
      } finally {
        _isReleasingVideo = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final carouselStateProvider = context.watch<CarouselStateProvider>();
    final isMediaPaused =
        carouselStateProvider.isMediaPausedForArea(AreaType.topAd);
    final isFullscreenAd =
        carouselStateProvider.currentAppState == AppState.fullscreenAd;
    _syncMediaState(
        isMediaPaused: isMediaPaused, isFullscreenAd: isFullscreenAd);

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
              if (_isControllerActive(_videoController) &&
                  _videoController!.value.isPlaying) {
                _pauseVideo();
              }
            });
          }
          return true;
        } else if (notification is MediaResumeNotification) {
          Future.delayed(const Duration(milliseconds: 50), () {
            if (_isControllerActive(_videoController) &&
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
        if (_isControllerActive(_videoController)) {
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
              color: Colors.white.withValues(alpha: 0.8),
            ),
            const SizedBox(height: 8),
            Text(
              widget.ad.title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.9),
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

  bool _isActiveGeneration(int generation) {
    return mounted && !_isDisposed && generation == _loadGeneration;
  }

  void _setStateIfActive(int generation, VoidCallback update) {
    if (_isActiveGeneration(generation)) {
      setState(update);
    }
  }

  bool _isControllerActive(VideoPlayerController? controller) {
    return mounted &&
        !_isDisposed &&
        controller != null &&
        identical(controller, _videoController) &&
        controller.value.isInitialized &&
        !controller.value.hasError;
  }

  void _syncMediaStateFromContext() {
    if (!mounted || _isDisposed) return;
    final carouselStateProvider = context.read<CarouselStateProvider>();
    _syncMediaState(
      isMediaPaused: carouselStateProvider.isMediaPausedForArea(AreaType.topAd),
      isFullscreenAd:
          carouselStateProvider.currentAppState == AppState.fullscreenAd,
    );
  }

  void _syncMediaState({
    required bool isMediaPaused,
    required bool isFullscreenAd,
  }) {
    final controller = _videoController;
    if (!_isControllerActive(controller)) return;
    final hasChanged = _lastAppliedMediaPaused != isMediaPaused ||
        _lastAppliedFullscreenAd != isFullscreenAd;
    if (!hasChanged) return;

    _lastAppliedMediaPaused = isMediaPaused;
    _lastAppliedFullscreenAd = isFullscreenAd;

    _scheduleMediaCommand(
      controller!,
      Duration.zero,
      () => _setControllerVolume(controller, isFullscreenAd ? 0.0 : 1.0),
    );

    if (isMediaPaused && controller.value.isPlaying) {
      _scheduleMediaCommand(
        controller,
        Duration.zero,
        () => _pauseController(controller),
      );
    } else if (!isMediaPaused && !controller.value.isPlaying) {
      _scheduleMediaCommand(
        controller,
        Duration.zero,
        () => _playController(controller),
      );
    }
  }

  void _scheduleMediaCommand(
    VideoPlayerController controller,
    Duration delay,
    Future<void> Function() command,
  ) {
    final int commandGeneration = ++_mediaCommandGeneration;
    Future.delayed(delay, () async {
      if (commandGeneration != _mediaCommandGeneration ||
          !_isControllerActive(controller)) {
        return;
      }

      try {
        await command();
      } catch (e) {
        // 静默处理视频控制器已被释放或平台状态变化导致的失败
      }
    });
  }

  Future<void> _setControllerVolume(
      VideoPlayerController controller, double volume) async {
    if (!_isControllerActive(controller)) return;
    try {
      await controller.setVolume(volume);
    } catch (e) {
      // 静默处理音量设置失败
    }
  }

  Future<void> _pauseController(VideoPlayerController controller) async {
    if (!_isControllerActive(controller)) return;
    try {
      if (controller.value.isPlaying) {
        await controller.pause();
      }
    } catch (e) {
      // 静默处理暂停失败
    }
  }

  Future<void> _playController(VideoPlayerController controller) async {
    if (!_isControllerActive(controller)) return;
    try {
      if (!controller.value.isPlaying) {
        await controller.play();
      }
    } catch (e) {
      // 静默处理恢复播放失败
    }
  }
}
