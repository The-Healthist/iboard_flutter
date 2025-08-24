import 'dart:io';
import 'package:flutter/material.dart';
import 'package:iboard_app/models/announcement_model.dart'; // Changed import
import 'package:iboard_app/managers/managers.dart';
import 'package:iboard_app/providers/state_provider.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:video_player/video_player.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import 'package:iboard_app/widgets/carousel_widget.dart'; // 添加輪播組件導入

class AnnouncementReaderWidget extends StatefulWidget {
  final AnnouncementModel announcement;
  final FileManager fileManager;
  final VoidCallback? onHomeButtonPressed;

  // 新增：視頻播放進度回調
  final Function(Duration)? onVideoProgressChanged;
  final Duration? initialPlaybackPosition;

  const AnnouncementReaderWidget({
    super.key,
    required this.announcement,
    required this.fileManager,
    this.onHomeButtonPressed,
    this.onVideoProgressChanged,
    this.initialPlaybackPosition,
  });

  @override
  AnnouncementReaderWidgetState createState() =>
      AnnouncementReaderWidgetState();
}

class AnnouncementReaderWidgetState extends State<AnnouncementReaderWidget> {
  final Logger _logger = Logger();
  VideoPlayerController? _videoController;
  bool _isLoading = true;
  String? _localFilePath;
  String? _error;

  // 新增：記錄視頻播放進度
  Duration? _savedPlaybackPosition;

  @override
  void initState() {
    super.initState();
    _loadFile();

    // 如果有初始播放位置，設置它
    if (widget.initialPlaybackPosition != null) {
      _savedPlaybackPosition = widget.initialPlaybackPosition;
    }
  }

  Future<void> _loadFile() async {
    if (!mounted) return; // Added mounted check
    setState(() {
      _isLoading = true;
      _error = null;
    });

    if (widget.announcement.file.localFilePath != null &&
        await File(widget.announcement.file.localFilePath!).exists()) {
      _localFilePath = widget.announcement.file.localFilePath;
    } else {
      final File? downloadedFile =
          await widget.fileManager.getFile(widget.announcement.file);
      if (!mounted) return;

      if (downloadedFile != null) {
        _localFilePath = downloadedFile.path;
      } else {
        _error = 'Failed to load file.';
        _logger.e(
            'Failed to download file for announcement: ${widget.announcement.title}');
      }
    }

    if (!mounted) return; // Added mounted check

    if (_localFilePath != null) {
      final mimeType = widget.announcement.file.mimeType.toLowerCase();
      if (mimeType == 'video/mp4') {
        _initializeVideoPlayer();
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _initializeVideoPlayer() {
    if (_localFilePath == null) return;
    if (!mounted) return;

    _videoController?.dispose();
    _videoController = null;

    final newVideoController =
        VideoPlayerController.file(File(_localFilePath!));
    _videoController = newVideoController;

    newVideoController.initialize().then((_) {
      if (!mounted || _videoController != newVideoController) {
        newVideoController.dispose();
        return;
      }

      // 如果有保存的播放位置，設置它
      if (_savedPlaybackPosition != null) {
        newVideoController.seekTo(_savedPlaybackPosition!);
      }

      // 設置播放進度監聽器
      newVideoController.addListener(_onVideoProgressChanged);

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }).catchError((error) {
      if (mounted) {
        setState(() {
          _error = 'Video initialization failed: $error';
          _isLoading = false;
        });
      }
    });
  }

  /// 新增：視頻播放進度變化監聽器
  void _onVideoProgressChanged() {
    if (_videoController != null &&
        _videoController!.value.isInitialized &&
        widget.onVideoProgressChanged != null) {
      try {
        final position = _videoController!.value.position;
        widget.onVideoProgressChanged!(position);
      } catch (e) {
        // debugPrint('[AnnouncementReader] 報告播放進度失敗: $e');
      }
    }
  }

  @override
  void dispose() {
    // 清理視頻控制器
    _videoController?.removeListener(_onVideoProgressChanged);
    _videoController?.dispose();
    _videoController = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 监听媒体暂停状态 - 仅监听中部通告区域
    final carouselStateProvider = context.watch<CarouselStateProvider>();
    final isMediaPaused =
        carouselStateProvider.isMediaPausedForArea(AreaType.middleNotice);

    // 根据媒体状态控制视频播放
    if (_videoController != null && _videoController!.value.isInitialized) {
      if (isMediaPaused && _videoController!.value.isPlaying) {
        _videoController!.pause();
      } else if (!isMediaPaused && !_videoController!.value.isPlaying) {
        _videoController!.play();
      }
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 60),
            const SizedBox(height: 16),
            Text(_error!,
                style: const TextStyle(color: Colors.red, fontSize: 18)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadFile, child: const Text('Retry'))
          ],
        ),
      );
    }

    if (_localFilePath == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.file_download_outlined, color: Colors.grey, size: 48),
            SizedBox(height: 16),
            Text(
              '文件暫不可用',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '正在嘗試下載...',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    final mimeType = widget.announcement.file.mimeType.toLowerCase();

    // 主要內容區域
    Widget contentWidget;

    if (mimeType == 'application/pdf') {
      contentWidget = PDFView(
        filePath: _localFilePath!,
        fitPolicy: FitPolicy.HEIGHT, // Add this line
        onError: (error) {
          _logger.e('Error displaying PDF', error: error);
          if (mounted) {
            setState(() {
              _error = 'Could not display PDF.';
            });
          }
        },
      );
    } else if (mimeType.startsWith('image/')) {
      contentWidget = InteractiveViewer(
        child: Image.file(
          File(_localFilePath!),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (context, error, stackTrace) {
            _logger.e('Error displaying image',
                error: error, stackTrace: stackTrace);
            return const Center(child: Text('Could not display image.'));
          },
        ),
      );
    } else if (mimeType == 'video/mp4') {
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
        contentWidget = const Center(child: CircularProgressIndicator());
      }
    } else {
      contentWidget = Center(child: Text('Unsupported file type: $mimeType'));
    }

    // 使用NotificationListener監聽媒體暫停和恢復通知
    return NotificationListener<Notification>(
      onNotification: (notification) {
        if (notification is MediaPauseNotification) {
          // 防抖動執行，避免重複調用
          Future.delayed(const Duration(milliseconds: 50), () {
            if (mounted && _videoController != null) {
              _pauseVideo();
            }
          });
          return true; // 阻止通知繼續傳遞
        } else if (notification is MediaResumeNotification) {
          // 防抖動執行，避免重複調用
          Future.delayed(const Duration(milliseconds: 50), () {
            if (mounted && _videoController != null) {
              _resumeVideo();
            }
          });
          return true; // 阻止通知繼續傳遞
        }
        return false; // 其他通知繼續傳遞
      },
      child: Stack(
        children: [
          contentWidget,
          if (widget.onHomeButtonPressed != null)
            Positioned(
              top: 16,
              right: 16,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.onHomeButtonPressed,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.home,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 暫停視頻播放
  void _pauseVideo() {
    if (_videoController != null && _videoController!.value.isInitialized) {
      try {
        if (_videoController!.value.isPlaying) {
          // 記錄當前播放位置
          _savedPlaybackPosition = _videoController!.value.position;

          // 通過回調報告播放進度
          if (widget.onVideoProgressChanged != null) {
            widget.onVideoProgressChanged!(_savedPlaybackPosition!);
          }

          _videoController!.pause();
          _logger.d(
              '📱 通告視頻已暫停，保存播放位置: ${_savedPlaybackPosition?.inMilliseconds}ms - ${widget.announcement.title}');
        }
      } catch (e) {
        _logger.e('暫停視頻失敗: $e');
      }
    }
  }

  /// 恢復視頻播放
  void _resumeVideo() {
    if (_videoController != null && _videoController!.value.isInitialized) {
      try {
        if (!_videoController!.value.isPlaying) {
          // 如果有保存的播放位置，先跳轉到該位置
          if (_savedPlaybackPosition != null) {
            _videoController!.seekTo(_savedPlaybackPosition!);
            _logger.d(
                '📱 通告視頻恢復，跳轉到保存位置: ${_savedPlaybackPosition?.inMilliseconds}ms - ${widget.announcement.title}');
          }
          _videoController!.play();
          _logger.d('📱 通告視頻已恢復播放 - ${widget.announcement.title}');
        }
      } catch (e) {
        _logger.e('恢復視頻失敗: $e');
      }
    }
  }

  /// 獲取當前視頻播放進度（用於外部記錄）
  Duration? get currentPlaybackPosition {
    if (_videoController != null && _videoController!.value.isInitialized) {
      return _videoController!.value.position;
    }
    return _savedPlaybackPosition;
  }

  /// 設置視頻播放進度（用於外部恢復）
  void setPlaybackPosition(Duration position) {
    if (_videoController != null && _videoController!.value.isInitialized) {
      try {
        _videoController!.seekTo(position);
        _savedPlaybackPosition = position;
        _logger.d(
            '📱 通告視頻設置播放位置: ${position.inMilliseconds}ms - ${widget.announcement.title}');
      } catch (e) {
        _logger.e('設置視頻播放位置失敗: $e');
      }
    } else {
      // 如果視頻控制器還沒準備好，先保存位置
      _savedPlaybackPosition = position;
    }
  }
}
