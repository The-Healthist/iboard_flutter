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
  final FileManager
      fileManager; // Pass FileManager if needed for direct file operations, or rely on pre-fetched path
  final VoidCallback? onHomeButtonPressed; // 添加主頁按鈕回調

  const AnnouncementReaderWidget({
    super.key,
    required this.announcement,
    required this.fileManager, // Or get it from a provider
    this.onHomeButtonPressed, // 可選的主頁按鈕回調
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
      _logger.i('Using pre-cached file: $_localFilePath');
    } else {
      _logger.i(
          'File not pre-cached or path is invalid, attempting to download...');
      final File? downloadedFile =
          await widget.fileManager.getFile(widget.announcement.file);
      if (!mounted) return; // Added mounted check

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
        // For PDF and images, we might not need specific initialization here
        // as they are handled by their respective widgets directly with the file path.
        if (mounted) {
          // Added mounted check
          setState(() {
            _isLoading = false;
          });
        }
      }
    } else {
      if (mounted) {
        // Added mounted check
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _initializeVideoPlayer() {
    if (_localFilePath == null) return;
    // If called when widget is not mounted, do nothing.
    if (!mounted) return;

    // Clean up previous controller if any and nullify the reference.
    _videoController?.dispose();
    _videoController = null;

    final newVideoController =
        VideoPlayerController.file(File(_localFilePath!));
    // Store the new controller instance.
    // It's important to use newVideoController in the async callbacks
    // to ensure operations are on the correct instance.
    _videoController = newVideoController;

    newVideoController.initialize().then((_) {
      // Check mounted *again* because this is an async callback.
      // Also check if the controller (_videoController) is still this newVideoController.
      // This handles cases where dispose() might have been called or another
      // initialization might have started.
      if (!mounted || _videoController != newVideoController) {
        // If not mounted, or if this callback is for an old/stale controller,
        // dispose the controller this callback was working on and do nothing further.
        newVideoController.dispose();
        return;
      }

      // Now it's safe to call setState and use the controller.
      setState(() {
        _isLoading = false;
      });
      // These operations should be on newVideoController which is confirmed to be current.
      newVideoController.play();
      newVideoController.setLooping(true);
    }).catchError((error, stackTrace) {
      _logger.e('Error initializing video player',
          error: error, stackTrace: stackTrace);
      // Check mounted and controller validity again.
      if (!mounted || _videoController != newVideoController) {
        newVideoController
            .dispose(); // Dispose the controller this callback was for.
        return;
      }

      setState(() {
        _error = 'Could not play video.';
        _isLoading = false;
      });
      // The newVideoController failed to initialize or play properly.
      // It will be disposed if another initialization occurs or in the main dispose() method.
      // Alternatively, could explicitly dispose newVideoController here too.
      // newVideoController.dispose();
    });
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _videoController = null; // Explicitly nullify the controller
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 监听媒体暂停状态
    final carouselStateProvider = context.watch<CarouselStateProvider>();
    final isMediaPaused = carouselStateProvider.isMediaPaused;

    // 根据媒体状态控制视频播放
    if (_videoController != null && _videoController!.value.isInitialized) {
      if (isMediaPaused && _videoController!.value.isPlaying) {
        _videoController!.pause();
        _logger.d('暂停通告视频播放');
      } else if (!isMediaPaused && !_videoController!.value.isPlaying) {
        _videoController!.play();
        _logger.d('恢复通告视频播放');
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
            Icon(Icons.error_outline, color: Colors.red, size: 60),
            SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: Colors.red, fontSize: 18)),
            SizedBox(height: 16),
            ElevatedButton(onPressed: _loadFile, child: Text('Retry'))
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
            // Added mounted check
            setState(() {
              _error = 'Could not display PDF.';
            });
          }
        },
      );
    } else if (mimeType.startsWith('image/')) {
      // For local files, Image.file is better. CachedNetworkImage is for network URLs with caching.
      // Since we ensure the file is local via FileManager, we use Image.file.
      contentWidget = InteractiveViewer(
        child: Image.file(
          File(_localFilePath!),
          fit: BoxFit.cover, // 改为 cover 让图片填满容器
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (context, error, stackTrace) {
            _logger.e('Error displaying image',
                error: error, stackTrace: stackTrace);
            return Center(child: Text('Could not display image.'));
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
        // Video is still initializing or failed
        contentWidget = const Center(child: CircularProgressIndicator());
      }
    } else {
      contentWidget = Center(child: Text('Unsupported file type: $mimeType'));
    }

    // 添加主頁按鈕覆蓋層
    return Stack(
      children: [
        // 主要內容
        contentWidget,
        // 主頁按鈕 - 位於右上角
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
