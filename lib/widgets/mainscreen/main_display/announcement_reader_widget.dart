import 'dart:io';
import 'package:flutter/material.dart';
import 'package:iboard_app/models/announcement_model.dart'; // Changed import
import 'package:iboard_app/managers/managers.dart';
import 'package:iboard_app/providers/state_provider.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:video_player/video_player.dart';
import 'package:provider/provider.dart';
import 'package:iboard_app/widgets/carousel_widget.dart'; // 添加輪播組件導入
import 'package:iboard_app/widgets/simple_print_dialog.dart'; // 添加簡化版打印對話框導入

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
  VideoPlayerController? _videoController;
  bool _isLoading = true;
  String? _localFilePath;
  String? _error;
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

  /// 視頻播放進度變化監聽器
  void _onVideoProgressChanged() {
    if (_videoController != null &&
        _videoController!.value.isInitialized &&
        widget.onVideoProgressChanged != null) {
      try {
        final position = _videoController!.value.position;
        widget.onVideoProgressChanged!(position);
      } catch (e) {
        // 靜默處理播放進度報告失敗
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
    final carouselStateProvider = context.watch<CarouselStateProvider>();
    final isMediaPaused =
        carouselStateProvider.isMediaPausedForArea(AreaType.middleNotice);
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

    return NotificationListener<Notification>(
      onNotification: (notification) {
        if (notification is MediaPauseNotification) {
          Future.delayed(const Duration(milliseconds: 50), () {
            if (mounted && _videoController != null) {
              _pauseVideo();
            }
          });
          return true;
        } else if (notification is MediaResumeNotification) {
          Future.delayed(const Duration(milliseconds: 50), () {
            if (mounted && _videoController != null) {
              _resumeVideo();
            }
          });
          return true;
        }
        return false;
      },
      child: Stack(
        children: [
          contentWidget,

          // 列印按鈕（左上角）
          Positioned(
            top: 16,
            left: 16,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _showPrintDialog,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.print,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),

          // 主頁按鈕（右上角，統一樣式）
          if (widget.onHomeButtonPressed != null)
            Positioned(
              top: 16,
              right: 16,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.onHomeButtonPressed,
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.home,
                      color: Colors.white,
                      size: 22,
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
          _savedPlaybackPosition = _videoController!.value.position;

          if (widget.onVideoProgressChanged != null) {
            widget.onVideoProgressChanged!(_savedPlaybackPosition!);
          }

          _videoController!.pause();
        }
      } catch (e) {
        // 靜默處理暫停視頻失敗
      }
    }
  }

  /// 恢復視頻播放
  void _resumeVideo() {
    if (_videoController != null && _videoController!.value.isInitialized) {
      try {
        if (!_videoController!.value.isPlaying) {
          if (_savedPlaybackPosition != null) {
            _videoController!.seekTo(_savedPlaybackPosition!);
          }
          _videoController!.play();
        }
      } catch (e) {
        // 靜默處理恢復視頻失敗
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
      } catch (e) {
        // 靜默處理設置視頻播放位置失敗
      }
    } else {
      _savedPlaybackPosition = position;
    }
  }

  /// 11, 顯示列印對話框
  void _showPrintDialog() {
    // 只有PDF和圖片文件支持列印
    final mimeType = widget.announcement.file.mimeType.toLowerCase();
    if (!mimeType.startsWith('image/') && mimeType != 'application/pdf') {
      _showUnsupportedFileDialog();
      return;
    }

    if (_localFilePath == null) {
      _showFileNotAvailableDialog();
      return;
    }

    // 直接顯示簡化版列印對話框
    _showPrintDialogWithAutoClose();
  }

  /// 12, 顯示列印對話框並自動關閉
  void _showPrintDialogWithAutoClose() {
    showDialog(
      context: context,
      builder: (context) => SimplePrintDialog(
        announcement: widget.announcement,
        localFilePath: _localFilePath,
      ),
    );

    // 10秒後自動關閉對話框
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
  }

  /// 16, 顯示不支持文件類型對話框
  void _showUnsupportedFileDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('無法列印'),
        content: Text(
            '文件類型 "${widget.announcement.file.mimeType}" 不支持列印。\n\n僅支持列印 PDF 和圖片文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('確定'),
          ),
        ],
      ),
    );
  }

  /// 17, 顯示文件不可用對話框
  void _showFileNotAvailableDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('無法列印'),
        content: const Text('文件尚未下載完成或不可用，請稍後再試。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('確定'),
          ),
        ],
      ),
    );
  }
}
