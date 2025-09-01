import 'dart:io';
import 'package:flutter/material.dart';
import 'package:iboard_app/models/ad_model.dart'; // Assuming AdModel exists
import 'package:iboard_app/managers/file_manager.dart'; // Assuming FileManager exists
import 'package:iboard_app/providers/state_provider.dart';
import 'package:iboard_app/widgets/carousel_widget.dart'; // 导入通知类
import 'package:iboard_app/utils/precise_video_pool_manager.dart' as precise;
import 'package:iboard_app/providers/ad_top_carousel_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:logger/logger.dart';
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
  final Logger _logger = Logger();
  VideoPlayerController? _videoController;
  bool _isLoading = true;
  String? _localFilePath;
  String? _currentVideoPath; // 添加：當前視頻路徑跟蹤
  String? _error;
  bool isManuallyPaused = false; // 添加手动暂停标记
  bool _isDownloading = false; // 添加下载状态标记
  int _retryCount = 0; // 添加重试计数
  static const int _maxRetries = 3; // 最大重试次数

  // 保存TopAdCarouselProvider引用，避免dispose时context访问问题
  TopAdCarouselProvider? _topAdCarouselProvider;

  @override
  void initState() {
    super.initState();
    _loadFile();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 在组件依赖变化时保存Provider引用，确保dispose时可以安全使用
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

    // Assuming AdModel has a 'file' property of type FileModel, similar to AnnouncementModel
    if (widget.ad.file.localFilePath != null &&
        await File(widget.ad.file.localFilePath!).exists()) {
      _localFilePath = widget.ad.file.localFilePath;
      // _logger.i('Using pre-cached ad file: $_localFilePath');
    } else {
      // _logger.i(
      //     'Ad file not pre-cached or path is invalid, attempting to download...');
      setState(() {
        _isDownloading = true;
      });

      // Assuming FileModel is compatible with fileManager.getFile
      final File? downloadedFile =
          await widget.fileManager.getFile(widget.ad.file);

      setState(() {
        _isDownloading = false;
      });

      if (downloadedFile != null) {
        _localFilePath = downloadedFile.path;
      } else {
        // 只有在超过最大重试次数时才显示错误
        if (_retryCount >= _maxRetries) {
          _error = 'Failed to load ad file after $_maxRetries attempts.';
          _logger.e(
              'Failed to download file for ad after $_maxRetries attempts: ${widget.ad.title}');
        } else {
          // 否则保持加载状态，等待重试
          _logger.w(
              'Failed to download file for ad (attempt ${_retryCount + 1}/$_maxRetries): ${widget.ad.title}');
          _retryCount++;
          // 延迟重试
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

  ///2，初始化视频播放器 - 使用视频池管理器
  Future<void> _initializeVideoPlayer() async {
    if (_localFilePath == null || !mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    // 🔧 修復：只有在切換到不同視頻時才釋放舊控制器
    if (_videoController != null && _currentVideoPath != _localFilePath) {
      // 确保Provider引用可用
      _topAdCarouselProvider ??= context.read<TopAdCarouselProvider>();
      await _topAdCarouselProvider!.preciseVideoPoolManager.releaseController(
        filePath: _currentVideoPath!, // 釋放舊路徑的控制器
        videoType: precise.VideoType.topAd,
        forceDispose: true, // 顶部广告切换时释放解码器
      );
      _videoController = null;
      _currentVideoPath = null;
    }

    // 如果已經有相同路徑的控制器，直接復用不需要重新初始化
    if (_videoController != null && _currentVideoPath == _localFilePath) {
      debugPrint('🔄 頂部廣告控制器已存在，直接復用: $_localFilePath');
      setState(() {
        _isLoading = false;
      });
      return;
    }

    // 檢查池中是否已有可用的控制器 - 精确管理器不需要此检查
    // 精确管理器会自动处理控制器复用和初始化

    try {
      if (!mounted) return;
      _topAdCarouselProvider ??= context.read<TopAdCarouselProvider>();

      // 🎯 核心改进：使用精确解码器管理器，直接获取已初始化的控制器
      // 自動dispose邏輯已內建在getInitializedController中
      _videoController = await _topAdCarouselProvider!.preciseVideoPoolManager
          .getInitializedController(
        filePath: _localFilePath!,
        videoType: precise.VideoType.topAd, // 顶部广告统一使用 topAd 类型
        autoPlay: true,
        looping: true,
        onError: () {
          debugPrint('❌ 顶部广告控制器获取失败: $_localFilePath');
          if (mounted) {
            setState(() {
              _error = '视频控制器创建失败，将显示占位符';
              _isLoading = false;
            });
          }
        },
      );

      // 🎯 关键修复：检查是否有全屏广告在播放相同文件，如果是则将顶部广告静音
      if (_videoController != null) {
        final carouselStateProvider = context.read<CarouselStateProvider>();
        final isFullscreenAd =
            carouselStateProvider.currentAppState == AppState.fullscreenAd;

        if (isFullscreenAd) {
          // 全屏广告状态下，顶部广告静音播放，避免音频冲突
          await _videoController!.setVolume(0.0);
          debugPrint('🔇 顶部广告已静音播放，避免与全屏广告冲突: ${widget.ad.title}');
        }
      }

      if (_videoController != null && mounted) {
        // 更新當前視頻路徑
        _currentVideoPath = _localFilePath;
        setState(() {
          _isLoading = false;
        });
        debugPrint('✅ 顶部广告视频初始化成功: ${widget.ad.title}');
      } else if (mounted) {
        // 控制器为null，显示优雅的占位符而不是错误
        setState(() {
          _error = null; // 清除错误，显示占位符
          _isLoading = false;
        });
        debugPrint('⚠️ 顶部广告控制器为null，显示占位符: ${widget.ad.title}');
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

  //3，暂停视频播放 - 使用标准VideoPlayerController
  Future<void> _pauseVideo() async {
    if (_videoController != null) {
      try {
        if (_videoController!.value.isInitialized &&
            !_videoController!.value.hasError &&
            _videoController!.value.isPlaying) {
          await _videoController!.pause();
          isManuallyPaused = true;
          // _logger.i('📱 手动暂停顶部广告视频播放 - ${widget.ad.title}');
        }
      } catch (e) {
        _logger.w('⚠️ 暂停视频播放失败: $e');
      }
    }
  }

  //4，恢复视频播放 - 使用标准VideoPlayerController
  Future<void> _resumeVideo() async {
    if (_videoController != null) {
      try {
        // 检查视频是否处于暂停状态
        if (_videoController!.value.isInitialized &&
            !_videoController!.value.hasError &&
            !_videoController!.value.isPlaying) {
          await _videoController!.play();
          isManuallyPaused = false;
          // _logger.i('📱 恢复顶部广告视频播放 - ${widget.ad.title}');
        }
      } catch (e) {
        _logger.w('⚠️ 恢复视频播放失败: $e');
      }
    }
  }

  //5，处理轮播切换时的清理
  Future<void> _handleCarouselSwitch() async {
    if (_videoController != null) {
      // 轮播切换时强制释放控制器，避免资源积累
      await _releaseVideoController(forceDispose: true);
      // 处理轮播切换，强制释放控制器: ${widget.ad.title}
    }
  }

  @override
  void dispose() {
    _releaseVideoController();
    super.dispose();
  }

  ///释放视频控制器到增强池中（优化版本）
  Future<void> _releaseVideoController({bool forceDispose = false}) async {
    if (_videoController != null && _currentVideoPath != null) {
      try {
        // 确保Provider引用可用
        _topAdCarouselProvider ??= context.read<TopAdCarouselProvider>();

        if (_topAdCarouselProvider != null) {
          // 先暂停视频播放
          if (_videoController!.value.isPlaying) {
            await _videoController!.pause();
          }

          // 释放控制器 - 使用精确解码器管理器
          await _topAdCarouselProvider!.preciseVideoPoolManager
              .releaseController(
            filePath: _currentVideoPath!,
            videoType: precise.VideoType.topAd,
            forceDispose: forceDispose, // 根据参数决定是否强制释放
          );

          // 顶部广告视频控制器已释放到池中: ${widget.ad.title}
        } else {
          _logger.w('⚠️ TopAdCarouselProvider引用为空，无法释放视频控制器');
        }
      } catch (e) {
        _logger.w('⚠️ 释放视频控制器时出错: $e');
      }

      _videoController = null;
      _currentVideoPath = null; // 清空當前路徑
    }
  }

  @override
  Widget build(BuildContext context) {
    // 监听媒体暂停状态 - 仅监听顶部广告区域
    final carouselStateProvider = context.watch<CarouselStateProvider>();
    final isMediaPaused =
        carouselStateProvider.isMediaPausedForArea(AreaType.topAd);

    // 根据媒体状态控制视频播放 - 使用防抖动控制避免频繁调用
    if (_videoController != null && _videoController!.value.isInitialized) {
      final isPlaying = _videoController!.value.isPlaying;
      final isFullscreenAd =
          carouselStateProvider.currentAppState == AppState.fullscreenAd;

      // 🎯 关键修复：根据应用状态动态调整音量，避免音频冲突
      Future.delayed(const Duration(milliseconds: 50), () {
        if (mounted &&
            _videoController != null &&
            _videoController!.value.isInitialized) {
          if (isFullscreenAd) {
            // 全屏广告状态：顶部广告静音播放
            _videoController!.setVolume(0.0);
          } else {
            // 非全屏广告状态：恢复顶部广告音量
            _videoController!.setVolume(1.0);
          }
        }
      });

      if (isMediaPaused && isPlaying) {
        // 延迟100ms执行，避免频繁调用
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted &&
              _videoController != null &&
              _videoController!.value.isInitialized &&
              _videoController!.value.isPlaying) {
            _videoController!.pause();
            // _logger.d('防抖动暂停顶部广告视频播放');
          }
        });
      } else if (!isMediaPaused && !isPlaying) {
        // 延迟100ms执行，避免频繁调用
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted &&
              _videoController != null &&
              _videoController!.value.isInitialized &&
              !_videoController!.value.isPlaying) {
            _videoController!.play();
            // _logger.d('防抖动恢复顶部广告视频播放');
          }
        });
      }
    }

    // 使用NotificationListener监听媒体暂停和恢复通知
    return NotificationListener<Notification>(
      onNotification: (notification) {
        if (notification is MediaPauseNotification) {
          // 检查是否是轮播切换触发的暂停（通过Provider状态判断）
          final carouselStateProvider = context.read<CarouselStateProvider>();
          final isFullscreenAd =
              carouselStateProvider.currentAppState == AppState.fullscreenAd;

          if (isFullscreenAd) {
            // 全屏广告状态：处理轮播切换，需要释放控制器
            Future.delayed(const Duration(milliseconds: 50), () {
              if (mounted) {
                _handleCarouselSwitch();
              }
            });
          } else {
            // 普通暂停：只暂停视频，不释放控制器
            Future.delayed(const Duration(milliseconds: 50), () {
              if (mounted &&
                  _videoController != null &&
                  _videoController!.value.isInitialized &&
                  _videoController!.value.isPlaying) {
                _pauseVideo();
                // _logger.i('📱 防抖动暂停视频 - ${widget.ad.title}');
              }
            });
          }
          return true; // 阻止通知继续传递
        } else if (notification is MediaResumeNotification) {
          // 防抖动执行，避免重复调用
          Future.delayed(const Duration(milliseconds: 50), () {
            if (mounted &&
                _videoController != null &&
                _videoController!.value.isInitialized &&
                !_videoController!.value.isPlaying) {
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
              return const Center(child: Text('Could not display ad image.'));
            },
          ),
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

  /// 构建视频占位符（当视频控制器创建失败时显示）
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
