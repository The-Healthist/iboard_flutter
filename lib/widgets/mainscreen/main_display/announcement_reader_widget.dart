import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:iboard_app/models/announcement_model.dart'; // Changed import
import 'package:iboard_app/managers/managers.dart';
import 'package:iboard_app/providers/state_provider.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:video_player/video_player.dart';
import 'package:provider/provider.dart';
import 'package:iboard_app/widgets/carousel/carousel_widget.dart'; // 添加輪播組件導入
import 'package:iboard_app/widgets/print/simple_print_dialog_enhanced.dart'; // 添加增強版打印對話框導入

class AnnouncementReaderWidget extends StatefulWidget {
  final AnnouncementModel announcement;
  final FileManager fileManager;
  final VoidCallback? onHomeButtonPressed;
  final bool isInCarouselMode; // 是否在轮播模式中

  // 新增：視頻播放進度回調
  final Function(Duration)? onVideoProgressChanged;
  final Duration? initialPlaybackPosition;

  // 新增：PDF多頁完成回調
  final VoidCallback? onPdfCompleted;

  // 新增：PDF多頁開始回調（用於延長停留時間）
  final Function(int totalPages)? onPdfPaginationStart;

  const AnnouncementReaderWidget({
    super.key,
    required this.announcement,
    required this.fileManager,
    this.onHomeButtonPressed,
    this.isInCarouselMode = false, // 默认不在轮播模式
    this.onVideoProgressChanged,
    this.initialPlaybackPosition,
    this.onPdfCompleted,
    this.onPdfPaginationStart,
  });

  @override
  AnnouncementReaderWidgetState createState() =>
      AnnouncementReaderWidgetState();
}

class AnnouncementReaderWidgetState extends State<AnnouncementReaderWidget> {
  VideoPlayerController? _videoController;
  PDFViewController? _pdfController;
  bool _isLoading = true;
  String? _localFilePath;
  String? _error;
  Duration? _savedPlaybackPosition;

  // PDF 控制相關
  int _totalPages = 0;
  int _currentPage = 0;
  Timer? _pdfPageTimer;
  bool _isPdfAutoPlaying = false;
  bool _isPdfPaginationPaused = false; // PDF分頁暂停状态

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

    // 清理PDF相關
    _stopPdfAutoPlay();
    _pdfController = null;

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final carouselStateProvider = context.watch<CarouselStateProvider>();
    final isMediaPaused =
        carouselStateProvider.isMediaPausedForArea(AreaType.middleNotice);

    // 視頻控制
    if (_videoController != null && _videoController!.value.isInitialized) {
      if (isMediaPaused && _videoController!.value.isPlaying) {
        _videoController!.pause();
      } else if (!isMediaPaused && !_videoController!.value.isPlaying) {
        _videoController!.play();
      }
    }

    // 监听媒體暂停状态 - 仅在轮播模式下且有多页时生效
    if (widget.isInCarouselMode && _totalPages > 1) {
      final carouselStateProvider = context.watch<CarouselStateProvider>();
      final currentAppState = carouselStateProvider.currentAppState;

      // 检查是否应该暂停PDF分頁（全屏广告或手动操作状态）
      final shouldPausePdfPagination =
          currentAppState == AppState.fullscreenAd ||
              currentAppState == AppState.manualOperation;
      if (shouldPausePdfPagination && !_isPdfPaginationPaused) {
        _pausePdfPagination();
      } else if (!shouldPausePdfPagination && _isPdfPaginationPaused) {
        _resumePdfPagination();
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
      contentWidget = Stack(
        children: [
          PDFView(
            filePath: _localFilePath!,
            fitPolicy: FitPolicy.HEIGHT, // 恢復原來的高度適配
            enableSwipe: true, // 啟用手動滑動
            swipeHorizontal: false, // 設定為垂直滑動
            autoSpacing: false,
            pageFling: true, // 啟用頁面彈性滑動
            pageSnap: true, // 啟用頁面對齊
            onViewCreated: (PDFViewController vc) {
              _pdfController = vc;
            },
            onRender: _onPdfRender,
            onPageChanged: (int? page, int? total) {
              if (page != null) {
                setState(() {
                  _currentPage = page;
                });
                // 用戶手動滑動時，重置自動翻頁計時器
                if (_isPdfAutoPlaying && widget.isInCarouselMode) {
                  _resetPdfAutoPlayTimer();
                }
              }
            },
            onError: (error) {
              if (mounted) {
                setState(() {
                  _error = 'Could not display PDF.';
                });
              }
            },
          ),
          // PDF頁數指示器（右下角）
          if (_totalPages > 1)
            Positioned(
              bottom: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_currentPage + 1}/$_totalPages',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
        ],
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
            if (mounted && widget.isInCarouselMode && _totalPages > 1) {
              _pausePdf();
            }
          });
          return true;
        } else if (notification is MediaResumeNotification) {
          Future.delayed(const Duration(milliseconds: 50), () {
            if (mounted && _videoController != null) {
              _resumeVideo();
            }
            if (mounted && widget.isInCarouselMode && _totalPages > 1) {
              _resumePdf();
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

  /// 12, 顯示列印對話框
  void _showPrintDialogWithAutoClose() {
    showDialog(
      context: context,
      barrierDismissible: true, // 允許點擊外部關閉，不影響後台打印
      builder: (context) => SimplePrintDialogEnhanced(
        announcement: widget.announcement,
        localFilePath: _localFilePath,
      ),
    );
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

  ///18, PDF渲染完成回調
  void _onPdfRender(int? pages) {
    // debugPrint(
    //     '[AnnouncementReader]  PDF渲染完成回调，页数: $pages，轮播模式: ${widget.isInCarouselMode}');

    if (pages != null && pages > 0) {
      setState(() {
        _totalPages = pages;
        _currentPage = 0; // 從第0頁開始
      });

      // debugPrint('[AnnouncementReader]  PDF总页数设置为: $_totalPages');

      // 如果PDF有多頁，啟動自動翻頁
      if (_totalPages > 1) {
        // debugPrint('[AnnouncementReader]  PDF多页，准备启动自动翻页');
        _startPdfAutoPlay();
      } else {
        // debugPrint('[AnnouncementReader]  PDF单页，不需要自动翻页');
      }
    } else {
      // debugPrint('[AnnouncementReader]  PDF渲染回调页数无效: $pages');
    }
  }

  ///19, 啟動PDF自動翻頁 - 仅在轮播模式下启动
  void _startPdfAutoPlay() {
    // debugPrint(
    //     '[AnnouncementReader]  尝试启动PDF自动翻页，当前状态: 已播放=$_isPdfAutoPlaying, 总页数=$_totalPages, 轮播模式=${widget.isInCarouselMode}');

    if (_isPdfAutoPlaying || _totalPages <= 1) {
      // debugPrint(
      //     '[AnnouncementReader]  PDF自动翻页跳过：已播放=$_isPdfAutoPlaying, 总页数=$_totalPages');
      return;
    }

    // 只在轮播模式下启动自动翻頁
    if (!widget.isInCarouselMode) {
      // debugPrint('[AnnouncementReader]  PDF自动翻页跳过：不在轮播模式');
      return;
    }

    //  修复：检查当前应用状态，如果在手动操作或全屏广告状态，则暂停PDF翻页
    final carouselStateProvider = context.read<CarouselStateProvider>();
    final currentAppState = carouselStateProvider.currentAppState;
    final shouldPausePdfPagination = currentAppState == AppState.fullscreenAd ||
        currentAppState == AppState.manualOperation;

    // debugPrint(
    //     '[AnnouncementReader]  当前应用状态: $currentAppState, 应该暂停翻页: $shouldPausePdfPagination');

    if (shouldPausePdfPagination) {
      // 如果当前应该暂停，标记为暂停状态，但仍然设置为自动播放模式
      _isPdfPaginationPaused = true;
      // debugPrint('[AnnouncementReader]  PDF启动时检测到应暂停状态: $currentAppState');
    }

    // 通知AnnouncementCarouselProvider開始PDF多頁翻頁，延長停留時間
    if (widget.onPdfPaginationStart != null) {
      // debugPrint('[AnnouncementReader]  通知轮播提供者PDF开始翻页，总页数: $_totalPages');
      widget.onPdfPaginationStart!(_totalPages);
    }

    _isPdfAutoPlaying = true;
    final pageStayDuration = carouselStateProvider.noticeStayDuration;

    // 只有在不应该暂停的情况下才启动翻页定时器
    if (!shouldPausePdfPagination) {
      _schedulePdfPageChange(pageStayDuration);
      // debugPrint(
      //     '[AnnouncementReader]  PDF自动翻页已启动，总页数: $_totalPages，翻页间隔: ${pageStayDuration}秒');
    } else {
      // debugPrint('[AnnouncementReader]  PDF自动翻页已准备，但当前暂停中，等待恢复');
    }
  }

  ///20, 調度PDF頁面切換 - 使用periodic timer並支持暂停
  void _schedulePdfPageChange(int pageStayDuration) {
    _pdfPageTimer?.cancel();

    _pdfPageTimer =
        Timer.periodic(Duration(seconds: pageStayDuration), (timer) async {
      if (!mounted || !_isPdfAutoPlaying) {
        timer.cancel();
        return;
      }

      // 如果PDF分頁被暂停，跳过这次执行
      if (_isPdfPaginationPaused) return;

      if (_currentPage < _totalPages - 1) {
        // 切換到下一頁
        final nextPage = _currentPage + 1;
        final success = await _pdfController?.setPage(nextPage);

        if (success == true) {
          setState(() {
            _currentPage = nextPage;
          });
        }
      } else {
        // 已到最後一頁，通知外部可以切換通告了
        timer.cancel();
        _isPdfAutoPlaying = false;
        if (widget.onPdfCompleted != null) {
          widget.onPdfCompleted!();
        }
      }
    });
  }

  ///21, 停止PDF自動播放
  void _stopPdfAutoPlay() {
    _isPdfAutoPlaying = false;
    _isPdfPaginationPaused = false;
    _pdfPageTimer?.cancel();
  }

  ///22, 暫停PDF分頁 - 参考表格逻辑
  void _pausePdfPagination() {
    if (!_isPdfPaginationPaused) {
      _isPdfPaginationPaused = true;
    }
  }

  ///23, 恢復PDF分頁 - 参考表格逻辑
  void _resumePdfPagination() {
    if (_isPdfPaginationPaused) {
      _isPdfPaginationPaused = false;

      //  修复：强制重新启动PDF翻页，确保从手动操作模式恢复后能正常翻页
      if (_totalPages > 1 && _isPdfAutoPlaying) {
        final carouselStateProvider = context.read<CarouselStateProvider>();
        final pageStayDuration = carouselStateProvider.noticeStayDuration;

        // 强制重新调度PDF翻页，无论定时器是否活跃
        _schedulePdfPageChange(pageStayDuration);

        // debugPrint(
        //     '[AnnouncementReader]  PDF翻页已恢复，当前页: $_currentPage/$_totalPages');
      }
    }
  }

  ///24, 暫停PDF播放（舊方法保持兼容性）
  void _pausePdf() {
    _pausePdfPagination();
  }

  ///25, 恢復PDF播放（舊方法保持兼容性）
  void _resumePdf() {
    _resumePdfPagination();
  }

  ///26, 獲取PDF總頁數
  int get totalPdfPages => _totalPages;

  ///27, 獲取當前PDF頁數
  int get currentPdfPage => _currentPage;

  ///28, 檢查PDF是否已完成播放
  bool get isPdfCompleted =>
      _totalPages <= 1 || _currentPage >= _totalPages - 1;

  ///29, 重置PDF自動翻頁計時器（用戶手動滑動時調用）
  void _resetPdfAutoPlayTimer() {
    if (!_isPdfAutoPlaying || _isPdfPaginationPaused) return;

    final carouselStateProvider = context.read<CarouselStateProvider>();
    final pageStayDuration = carouselStateProvider.noticeStayDuration;

    // 重新調度PDF翻頁計時器
    _schedulePdfPageChange(pageStayDuration);

    // debugPrint('[AnnouncementReader]  用戶手動滑動，重置PDF自動翻頁計時器');
  }
}
