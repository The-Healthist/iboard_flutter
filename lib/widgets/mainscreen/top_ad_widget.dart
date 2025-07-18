import 'dart:io';
import 'package:flutter/material.dart';
import 'package:iboard_app/models/ad_model.dart'; // Assuming AdModel exists
import 'package:iboard_app/managers/file_manager.dart'; // Assuming FileManager exists
import 'package:iboard_app/providers/state_provider.dart';
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

  @override
  void initState() {
    super.initState();
    _loadFile();
  }

  Future<void> _loadFile() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    // Assuming AdModel has a 'file' property of type FileModel, similar to AnnouncementModel
    if (widget.ad.file.localFilePath != null &&
        await File(widget.ad.file.localFilePath!).exists()) {
      _localFilePath = widget.ad.file.localFilePath;
      _logger.i('Using pre-cached ad file: $_localFilePath');
    } else {
      _logger.i(
          'Ad file not pre-cached or path is invalid, attempting to download...');
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

  void _initializeVideoPlayer() {
    if (_localFilePath == null) return;
    _videoController = VideoPlayerController.file(File(_localFilePath!))
      ..initialize().then((_) {
        setState(() {
          _isLoading = false;
        });
        _videoController?.play();
        _videoController?.setLooping(true); // Ads usually loop
      }).catchError((error, stackTrace) {
        _logger.e('Error initializing ad video player',
            error: error, stackTrace: stackTrace);
        setState(() {
          _error = 'Could not play ad video.';
          _isLoading = false;
        });
      });
  }

  @override
  void dispose() {
    _videoController?.dispose();
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
        _logger.d('暂停顶部广告视频播放');
      } else if (!isMediaPaused && !_videoController!.value.isPlaying) {
        _videoController!.play();
        _logger.d('恢复顶部广告视频播放');
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
    }

    if (_localFilePath == null) {
      // This case should ideally be covered by _error, but as a fallback:
      return const Center(child: Text('Ad file not available.'));
    }

    final mimeType = widget.ad.file.mimeType.toLowerCase();

    if (mimeType == 'video/mp4') {
      if (_videoController != null && _videoController!.value.isInitialized) {
        return SizedBox.expand(
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
        return const Center(child: CircularProgressIndicator());
      }
    } else if (mimeType == 'image/jpeg' ||
        mimeType == 'image/jpg' ||
        mimeType == 'image/png' ||
        mimeType == 'image/gif') {
      return Image.file(
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
      return Center(child: Text('Unsupported ad file type: $mimeType'));
    }
  }
}
