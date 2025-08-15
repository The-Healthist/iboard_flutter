import 'dart:io';
import 'package:flutter/material.dart';
import 'package:iboard_app/models/ad_model.dart'; // Assuming AdModel exists
import 'package:iboard_app/managers/file_manager.dart'; // Assuming FileManager exists
import 'package:iboard_app/providers/state_provider.dart';
import 'package:iboard_app/widgets/carousel_widget.dart'; // 导入通知类
import 'package:iboard_app/utils/video_resource_manager.dart';
import 'package:iboard_app/utils/enhanced_video_pool_manager.dart';
import 'package:iboard_app/providers/advertisement_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';

class TopAdWidget extends StatefulWidget {
  final AdModel ad;
  final FileManager fileManager;

  const TopAdWidget({
    Key? key,
    required this.ad,
    required this.fileManager,
  }) : super(key: key);

  @override
  _TopAdWidgetState createState() => _TopAdWidgetState();
}

class _TopAdWidgetState extends State<TopAdWidget> {
  final Logger _logger = Logger();
  VideoPlayerController? _videoController;
  bool _isLoading = true;
  String? _localFilePath;
  String? _error;
  bool _isManuallyPaused = false; // 添加手动暂停标记

  // 保存AdvertisementProvider引用，避免dispose时context访问问题
  AdvertisementProvider? _advertisementProvider;

  @override
  void initState() {
    super.initState();
    _loadFile();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 在组件依赖变化时保存Provider引用，确保dispose时可以安全使用
    _advertisementProvider ??= context.read<AdvertisementProvider>();
  }

  //1，加载广告文件
  Future<void> _loadFile() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    // Assuming AdModel has a 'file' property of type FileModel, similar to AnnouncementModel
    if (widget.ad.file.localFilePath != null &&
        await File(widget.ad.file.localFilePath!).exists()) {
      _localFilePath = widget.ad.file.localFilePath;
      // _logger.i('Using pre-cached ad file: $_localFilePath');
    } else {
      // _logger.i(
      //     'Ad file not pre-cached or path is invalid, attempting to download...');
      // Assuming FileModel is compatible with fileManager.getFile
      final File? downloadedFile =
          await widget.fileManager.getFile(widget.ad.file);
      if (downloadedFile != null) {
        _localFilePath = downloadedFile.path;
      } else {
        _error = 'Failed to load ad file.';
        _logger.e(
            'Failed to download file for ad: ${widget.ad.title}'); // Assuming AdModel has a title
      }
    }

    if (_localFilePath != null) {
      final mimeType = widget.ad.file.mimeType.toLowerCase();
      if (mimeType == 'video/mp4') {
        _initializeVideoPlayer();
      } else if (mimeType.startsWith('image/')) {
        // For images (jpeg, jpg, png, gif), no specific initialization needed here
        setState(() {
          _isLoading = false;
        });
      } else {
        _error = 'Unsupported ad file type: $mimeType';
        _logger.w(
            'Unsupported ad file type: $mimeType for ad: ${widget.ad.title}');
        setState(() {
          _isLoading = false;
        });
      }
    } else {
      // Error should have been set by now if download failed
      setState(() {
        _isLoading = false;
      });
    }
  }

  //2，初始化视频播放器 - 使用视频池管理器
  Future<void> _initializeVideoPlayer() async {
    if (_localFilePath == null || !mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    // 先释放之前的控制器到增强池中
    if (_videoController != null) {
      // 确保Provider引用可用
      _advertisementProvider ??= context.read<AdvertisementProvider>();
      await _advertisementProvider!.videoPoolManager.releaseController(
        filePath: _localFilePath!,
        videoType: VideoType.topAd,
        isNetwork: false,
      );
      _videoController = null;
    }

    try {
      _advertisementProvider ??= context.read<AdvertisementProvider>();
      _videoController =
          await _advertisementProvider!.videoPoolManager.getController(
        filePath: _localFilePath!,
        videoType: VideoType.topAd,
        isNetwork: false,
        autoPlay: true,
        looping: true,
        onError: () {
          if (mounted) {
            setState(() {
              _error = 'Video playback error occurred.';
              _isLoading = false;
            });
          }
        },
      );

      if (_videoController != null && mounted) {
        setState(() {
          _isLoading = false;
        });
        // _logger.i('✅ 顶部广告视频初始化成功（使用增强视频池）');
      } else if (mounted) {
        setState(() {
          _error = 'Could not initialize video player.';
          _isLoading = false;
        });
      }
    } catch (e) {
      _logger.e('Failed to initialize video controller', error: e);
      if (mounted) {
        setState(() {
          _error = 'Could not create video player.';
          _isLoading = false;
        });
      }
    }
  }

  //3，暂停视频播放 - 使用视频资源管理器
  Future<void> _pauseVideo() async {
    if (_videoController != null) {
      final success = await _videoController!.safePause();
      if (success) {
        _isManuallyPaused = true;
        // _logger.i('📱 手动暂停顶部广告视频播放 - ${widget.ad.title}');
      } else {
        _logger.w('⚠️ 暂停视频播放失败');
      }
    }
  }

  //4，恢复视频播放 - 使用视频资源管理器
  Future<void> _resumeVideo() async {
    if (_videoController != null) {
      // 检查视频是否处于暂停状态，无论是什么原因暂停的
      if (_videoController!.safeState == VideoControllerState.paused) {
        final success = await _videoController!.safePlay();
        if (success) {
          _isManuallyPaused = false;
          // _logger.i('📱 恢复顶部广告视频播放 - ${widget.ad.title}');
        } else {
          _logger.w('⚠️ 恢复视频播放失败');
        }
      }
    }
  }

  @override
  void dispose() {
    if (_videoController != null && _localFilePath != null) {
      // 释放控制器到增强池中，避免阻塞dispose
      try {
        // 使用保存的Provider引用，避免context访问问题
        if (_advertisementProvider != null) {
          _advertisementProvider!.videoPoolManager.releaseController(
            filePath: _localFilePath!,
            videoType: VideoType.topAd,
            isNetwork: false,
          );
        } else {
          _logger.w('⚠️ AdvertisementProvider引用为空，无法释放视频控制器');
        }
      } catch (e) {
        _logger.w('⚠️ 释放视频控制器时出错: $e');
      }
      _videoController = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 监听媒体暂停状态 - 仅监听顶部广告区域
    final carouselStateProvider = context.watch<CarouselStateProvider>();
    final isMediaPaused =
        carouselStateProvider.isMediaPausedForArea(AreaType.topAd);

    // 根据媒体状态控制视频播放 - 使用防抖动控制避免频繁调用
    if (_videoController != null) {
      final state = _videoController!.safeState;
      if (isMediaPaused && state == VideoControllerState.playing) {
        // 延迟100ms执行，避免频繁调用
        Future.delayed(Duration(milliseconds: 100), () {
          if (mounted &&
              _videoController != null &&
              _videoController!.safeState == VideoControllerState.playing) {
            _videoController!.safePause();
            // _logger.d('防抖动暂停顶部广告视频播放');
          }
        });
      } else if (!isMediaPaused && state == VideoControllerState.paused) {
        // 延迟100ms执行，避免频繁调用
        Future.delayed(Duration(milliseconds: 100), () {
          if (mounted &&
              _videoController != null &&
              _videoController!.safeState == VideoControllerState.paused) {
            _videoController!.safePlay();
            // _logger.d('防抖动恢复顶部广告视频播放');
          }
        });
      }
    }

    // 使用NotificationListener监听媒体暂停和恢复通知
    return NotificationListener<Notification>(
      onNotification: (notification) {
        if (notification is MediaPauseNotification) {
          // 防抖动执行，避免重复调用
          Future.delayed(Duration(milliseconds: 50), () {
            if (mounted &&
                _videoController != null &&
                _videoController!.safeState == VideoControllerState.playing) {
              _pauseVideo();
              // _logger.i('📱 防抖动暂停视频 - ${widget.ad.title}');
            }
          });
          return true; // 阻止通知继续传递
        } else if (notification is MediaResumeNotification) {
          // 防抖动执行，避免重复调用
          Future.delayed(Duration(milliseconds: 50), () {
            if (mounted &&
                _videoController != null &&
                _videoController!.safeState == VideoControllerState.paused) {
              _resumeVideo();
              // _logger.i('📱 防抖动恢复视频 - ${widget.ad.title}');
            }
          });
          return true; // 阻止通知继续传递
        }
        return false; // 其他通知继续传递
      },
      child: _buildContent(),
    );
  }

  //5，构建内容部分
  Widget _buildContent() {
    Widget contentWidget;

    if (_isLoading) {
      contentWidget = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      contentWidget = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 40),
            SizedBox(height: 8),
            Text(_error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red, fontSize: 16)),
            SizedBox(height: 8),
            ElevatedButton(onPressed: _loadFile, child: Text('Retry'))
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
              fit: BoxFit.cover,
              child: SizedBox(
                width: _videoController!.value.size.width,
                height: _videoController!.value.size.height,
                child: VideoPlayer(_videoController!),
              ),
            ),
          );
        } else {
          // Video is still initializing or failed (though _error should catch failure)
          contentWidget = const Center(child: CircularProgressIndicator());
        }
      } else if (mimeType == 'image/jpeg' ||
          mimeType == 'image/jpg' ||
          mimeType == 'image/png' ||
          mimeType == 'image/gif') {
        contentWidget = Image.file(
          File(_localFilePath!),
          fit: BoxFit.cover, // 改为 cover 让图片填满容器
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (context, error, stackTrace) {
            _logger.e('Error displaying ad image',
                error: error, stackTrace: stackTrace);
            // Attempt to show a more specific error if this happens after initial load
            // This might be redundant if _loadFile already set an error.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _error == null) {
                // Check if an error isn't already displayed
                setState(() {
                  _error = 'Could not display ad image.';
                });
              }
            });
            return Center(child: Text('Could not display ad image.'));
          },
        );
      } else {
        // This case should be caught by _loadFile and set _error.
        // If somehow reached, display the unsupported message.
        contentWidget =
            Center(child: Text('Unsupported ad file type: $mimeType'));
      }
    }

    return contentWidget;
  }
}
