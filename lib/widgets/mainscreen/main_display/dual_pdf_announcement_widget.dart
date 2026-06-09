import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:iboard_app/managers/file_manager.dart';
import 'package:iboard_app/managers/pdf_page_cache_manager.dart';
import 'package:iboard_app/models/announcement_model.dart';
import 'package:iboard_app/providers/state_provider.dart';
import 'package:iboard_app/widgets/carousel/carousel_widget.dart';
import 'package:provider/provider.dart';

@visibleForTesting
const BoxFit debugDualAnnouncementPageFit = BoxFit.contain;

class DualPdfAnnouncementWidget extends StatefulWidget {
  final List<AnnouncementModel> announcements;
  final FileManager? fileManager;
  final VoidCallback? onHomeButtonPressed;
  final int? carouselIndex;
  final ValueListenable<int>? visibleCarouselIndexListenable;
  final ValueChanged<int>? onPaginationStart;
  final VoidCallback? onPaginationComplete;

  const DualPdfAnnouncementWidget({
    super.key,
    required this.announcements,
    this.fileManager,
    this.onHomeButtonPressed,
    this.carouselIndex,
    this.visibleCarouselIndexListenable,
    this.onPaginationStart,
    this.onPaginationComplete,
  });

  @override
  State<DualPdfAnnouncementWidget> createState() =>
      _DualPdfAnnouncementWidgetState();
}

class _DualPdfAnnouncementWidgetState extends State<DualPdfAnnouncementWidget> {
  late final FileManager _fileManager;
  Timer? _frameTimer;

  bool _isLoading = true;
  bool _isAutoPlaying = false;
  bool _isPaginationPaused = false;
  bool _paginationStartNotified = false;
  int _loadGeneration = 0;
  int _currentFrameIndex = 0;
  String? _error;

  List<List<DualAnnouncementPageEntry?>> _frames = const [];

  @override
  void initState() {
    super.initState();
    _fileManager = widget.fileManager ?? FileManager();
    widget.visibleCarouselIndexListenable?.addListener(_onVisibleIndexChanged);
    _loadPages();
  }

  @override
  void didUpdateWidget(covariant DualPdfAnnouncementWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.visibleCarouselIndexListenable !=
        widget.visibleCarouselIndexListenable) {
      oldWidget.visibleCarouselIndexListenable
          ?.removeListener(_onVisibleIndexChanged);
      widget.visibleCarouselIndexListenable
          ?.addListener(_onVisibleIndexChanged);
    }

    if (debugDualAnnouncementListSignature(oldWidget.announcements) !=
        debugDualAnnouncementListSignature(widget.announcements)) {
      _loadPages();
    } else {
      _startAutoPlayIfReady();
    }
  }

  @override
  void dispose() {
    widget.visibleCarouselIndexListenable
        ?.removeListener(_onVisibleIndexChanged);
    _frameTimer?.cancel();
    super.dispose();
  }

  void _onVisibleIndexChanged() {
    if (_isCurrentCarouselPage) {
      _startAutoPlayIfReady();
    } else {
      _stopAutoPlay();
    }
  }

  bool get _isCurrentCarouselPage {
    final carouselIndex = widget.carouselIndex;
    final visibleIndex = widget.visibleCarouselIndexListenable?.value;
    if (carouselIndex == null || visibleIndex == null) {
      return true;
    }
    return carouselIndex == visibleIndex;
  }

  Future<void> _loadPages() async {
    final generation = ++_loadGeneration;
    _frameTimer?.cancel();

    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _isAutoPlaying = false;
      _isPaginationPaused = false;
      _paginationStartNotified = false;
      _currentFrameIndex = 0;
      _error = null;
      _frames = const [];
    });

    try {
      final pages = <DualAnnouncementPageEntry>[];
      for (final announcement in widget.announcements) {
        final localFile = await _resolveLocalFile(announcement);
        if (generation != _loadGeneration || !mounted) {
          return;
        }
        if (localFile == null) {
          continue;
        }

        final mimeType = announcement.file.mimeType.toLowerCase();
        if (mimeType == 'application/pdf') {
          final result = await PdfPageCacheManager.instance.getPageImages(
            pdfFile: localFile,
            cacheKey: debugDualAnnouncementPdfCacheKey(announcement),
          );
          if (generation != _loadGeneration || !mounted) {
            return;
          }
          for (var pageIndex = 0;
              pageIndex < result.pagePaths.length;
              pageIndex++) {
            pages.add(
              DualAnnouncementPageEntry(
                announcement: announcement,
                pagePath: result.pagePaths[pageIndex],
                pageIndex: pageIndex,
                pageCount: result.pagePaths.length,
                isPdf: true,
              ),
            );
          }
        } else if (mimeType.startsWith('image/')) {
          pages.add(
            DualAnnouncementPageEntry(
              announcement: announcement,
              pagePath: localFile.path,
              pageIndex: 0,
              pageCount: 1,
              isPdf: false,
            ),
          );
        }
      }

      if (!mounted || generation != _loadGeneration) {
        return;
      }

      final frames = debugBuildDualAnnouncementFrames(pages);
      setState(() {
        _frames = frames;
        _isLoading = false;
        _error = pages.isEmpty ? '沒有可顯示的通告文件。' : null;
      });

      _startAutoPlayIfReady();
    } catch (error) {
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      setState(() {
        _isLoading = false;
        _error = '通告預覽準備失敗。';
      });
    }
  }

  Future<File?> _resolveLocalFile(AnnouncementModel announcement) async {
    final localPath = announcement.file.localFilePath;
    if (localPath != null && await File(localPath).exists()) {
      return File(localPath);
    }
    return _fileManager.getFile(announcement.file);
  }

  void _updatePauseState(bool shouldPause) {
    if (shouldPause == _isPaginationPaused) {
      return;
    }
    _isPaginationPaused = shouldPause;
    if (shouldPause) {
      _frameTimer?.cancel();
      _frameTimer = null;
    } else {
      _startAutoPlayIfReady();
    }
  }

  void _startAutoPlayIfReady() {
    if (!mounted ||
        _isLoading ||
        _frames.length <= 1 ||
        !_isCurrentCarouselPage ||
        _isPaginationPaused) {
      return;
    }

    _notifyPaginationStart();
    if (_isAutoPlaying && _frameTimer != null) {
      return;
    }

    _isAutoPlaying = true;
    final stayDuration =
        context.read<CarouselStateProvider>().noticeStayDuration;
    _frameTimer?.cancel();
    _frameTimer = Timer.periodic(Duration(seconds: stayDuration), (_) {
      if (!mounted || _isPaginationPaused || !_isCurrentCarouselPage) {
        return;
      }
      _showNextFrame();
    });
  }

  void _stopAutoPlay() {
    _frameTimer?.cancel();
    _frameTimer = null;
    _isAutoPlaying = false;
    _paginationStartNotified = false;
  }

  void _notifyPaginationStart() {
    if (_paginationStartNotified || _frames.length <= 1) {
      return;
    }
    _paginationStartNotified = true;
    widget.onPaginationStart?.call(_frames.length);
  }

  void _showNextFrame() {
    if (_frames.isEmpty) {
      return;
    }

    final nextIndex = _currentFrameIndex + 1;
    if (nextIndex < _frames.length) {
      setState(() {
        _currentFrameIndex = nextIndex;
      });
      return;
    }

    setState(() {
      _currentFrameIndex = 0;
    });

    _isAutoPlaying = false;
    _paginationStartNotified = false;
    widget.onPaginationComplete?.call();

    if (_isCurrentCarouselPage) {
      _startAutoPlayIfReady();
    } else {
      _stopAutoPlay();
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentAppState = context
        .select((CarouselStateProvider provider) => provider.currentAppState);
    final shouldPausePagination = currentAppState == AppState.fullscreenAd ||
        currentAppState == AppState.manualOperation ||
        !_isCurrentCarouselPage;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _updatePauseState(shouldPausePagination);
      }
    });

    Widget content;
    if (_isLoading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      content = Center(
        child: Text(
          _error!,
          style: const TextStyle(fontSize: 18, color: Colors.grey),
        ),
      );
    } else {
      final frame = _frames[_currentFrameIndex.clamp(0, _frames.length - 1)];
      content = Row(
        children: [
          Expanded(child: _buildPageSlot(frame[0])),
          const SizedBox(width: 10),
          Expanded(child: _buildPageSlot(frame[1])),
        ],
      );
    }

    return NotificationListener<Notification>(
      onNotification: (notification) {
        if (notification is MediaPauseNotification) {
          _updatePauseState(true);
          return true;
        }
        if (notification is MediaResumeNotification) {
          _updatePauseState(false);
          return true;
        }
        return false;
      },
      child: Stack(
        children: [
          Positioned.fill(child: content),
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
                      color: Colors.black.withValues(alpha: 0.6),
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

  Widget _buildPageSlot(DualAnnouncementPageEntry? entry) {
    if (entry == null) {
      return const ColoredBox(color: Colors.white);
    }

    return Container(
      color: Colors.white,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.file(
              File(entry.pagePath),
              fit: debugDualAnnouncementPageFit,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) {
                return const Center(child: Text('通告頁面暫不可用'));
              },
            ),
          ),
          if (entry.pageCount > 1)
            Positioned(
              bottom: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${entry.pageIndex + 1}/${entry.pageCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class DualAnnouncementPageEntry {
  final AnnouncementModel announcement;
  final String pagePath;
  final int pageIndex;
  final int pageCount;
  final bool isPdf;

  const DualAnnouncementPageEntry({
    required this.announcement,
    required this.pagePath,
    required this.pageIndex,
    required this.pageCount,
    required this.isPdf,
  });
}

@visibleForTesting
List<List<T?>> debugBuildDualAnnouncementFrames<T>(
  List<T> pages, {
  int slotsPerFrame = 2,
}) {
  if (slotsPerFrame <= 0) {
    throw ArgumentError.value(slotsPerFrame, 'slotsPerFrame');
  }

  final frames = <List<T?>>[];
  for (var index = 0; index < pages.length; index += slotsPerFrame) {
    final frame = <T?>[];
    for (var slot = 0; slot < slotsPerFrame; slot++) {
      final pageIndex = index + slot;
      frame.add(pageIndex < pages.length ? pages[pageIndex] : null);
    }
    frames.add(List<T?>.unmodifiable(frame));
  }
  return List<List<T?>>.unmodifiable(frames);
}

@visibleForTesting
String debugDualAnnouncementPdfCacheKey(AnnouncementModel announcement) {
  final file = announcement.file;
  if (file.md5.isNotEmpty) {
    return 'file_${file.id}_${file.md5}';
  }
  return 'file_${file.id}_${announcement.updatedAt.millisecondsSinceEpoch}';
}

String debugDualAnnouncementListSignature(
    List<AnnouncementModel> announcements) {
  return announcements.map((announcement) {
    final file = announcement.file;
    return [
      announcement.id,
      announcement.updatedAt.millisecondsSinceEpoch,
      announcement.title,
      announcement.description,
      announcement.status,
      announcement.startTime.millisecondsSinceEpoch,
      announcement.endTime.millisecondsSinceEpoch,
      announcement.fileType,
      file.id,
      file.mimeType,
      file.md5,
      file.url,
      file.fileSize,
      file.localFilePath ?? '',
    ].join('\u001f');
  }).join('\u001e');
}
