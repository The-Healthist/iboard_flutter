import 'dart:io';
import 'package:flutter/material.dart';
import 'package:iboard_app/models/announcement_model.dart'; // Changed import
import 'package:iboard_app/managers/managers.dart';
import 'package:iboard_app/providers/state_provider.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:video_player/video_player.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';

class AnnouncementReaderWidget extends StatefulWidget {
  final AnnouncementModel announcement;
  final FileManager fileManager;
  final VoidCallback? onHomeButtonPressed;

  const AnnouncementReaderWidget({
    super.key,
    required this.announcement,
    required this.fileManager,
    this.onHomeButtonPressed,
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

  @override
  void initState() {
    super.initState();
    _loadFile();
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

      setState(() {
        _isLoading = false;
      });
      newVideoController.play();
      newVideoController.setLooping(true);
    }).catchError((error, stackTrace) {
      _logger.e('Error initializing video player',
          error: error, stackTrace: stackTrace);
      if (!mounted || _videoController != newVideoController) {
        newVideoController.dispose();
        return;
      }

      setState(() {
        _error = 'Could not play video.';
        _isLoading = false;
      });

    });
  }

  @override
  void dispose() {
    if (_videoController != null) {
      try {
        // 暂停播放
        if (_videoController!.value.isInitialized &&
            _videoController!.value.isPlaying) {
          _videoController!.pause();
        }
        // 释放资源
        _videoController!.dispose();
      } finally {
        _videoController = null;
      }
    }
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
            Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 18)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadFile, child: const Text('Retry'))
          ],
        ),
      );
    }

    if (_localFilePath == null) {
      return const Center(child: Text('File not available.'));
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

    return Stack(
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
    );
  }
}
