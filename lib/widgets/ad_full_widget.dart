import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:iboard_app/managers/file_manager.dart';
import 'package:iboard_app/models/ad_model.dart';
import 'package:iboard_app/utils/enhanced_video_pool_manager.dart';
import 'package:iboard_app/providers/advertisement_provider.dart';
import 'package:iboard_app/widgets/carousel_widget.dart'; // 导入通知类
import 'package:provider/provider.dart';
import 'package:logger/logger.dart';
import 'dart:io';

class FullAdWidget extends StatefulWidget {
  final AdModel ad;
  final FileManager fileManager;
  final Function(String adId, Duration position)?
      onVideoProgressChanged; // 视频进度变化回掉
  final VoidCallback? onVideoDisposed; // 视频资源释放完成回掉
  final Future<VideoPlayerController?> controllerFuture; // 异步控制器
  final Duration? initialPlaybackPosition; // 初始播放位置

  const FullAdWidget({
    super.key,
    required this.ad,
    required this.fileManager,
    required this.controllerFuture,
    this.onVideoProgressChanged,
    this.onVideoDisposed,
    this.initialPlaybackPosition,
  });

  @override
  State<FullAdWidget> createState() => _FullAdWidgetState();
}

class _FullAdWidgetState extends State<FullAdWidget> {
  static final Logger _logger = Logger();
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  bool _isLoadingVideo = false;
  String? _errorMessage;
  String? _currentFilePath; // 当前视频文件路径
  bool _isReleasing = false; // 防重入釋放

  // 保存AdvertisementProvider引用，避免dispose时context访问问题
  AdvertisementProvider? _advertisementProvider;
  @override
  void initState() {
    super.initState();
    // 在 initState 中尝试获取 AdvertisementProvider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _advertisementProvider = context.read<AdvertisementProvider>();
      } catch (e) {
        _logger.e('❌ 获取 AdvertisementProvider 失败: $e');
      }
    });

    // 仅在视频类型时初始化
    if (widget.ad.file.mimeType.startsWith('video/')) {
      // 延迟初始化，避免阻塞构建
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _initializeVideoPlayer();
        }
      });
    }
  }

  /// 初始化视频播放器
  Future<void> _initializeVideoPlayer() async {
    if (_videoController != null || !mounted) return;

    setState(() {
      _isLoadingVideo = true;
      _errorMessage = null;
    });

    try {
      // 详细日志：文件获取过程
      _logger.i('🔍 开始初始化视频: ${widget.ad.file.url}');

      // 尝试从FileManager获取本地缓存的视频文件
      final File? localFile = await widget.fileManager.getFile(widget.ad.file);
      if (!mounted) return;

      if (localFile == null || !await localFile.exists()) {
        _logger.e('❌ 视频文件未缓存: ${widget.ad.file.url}');
        throw Exception('视频文件未缓存');
      }

      // 记录当前文件信息
      _currentFilePath = localFile.path;

      _logger.i('📁 视频文件路径: $_currentFilePath');

      // 與頂部一致：通過 AdvertisementProvider 的 videoPoolManager 取得控制器
      _advertisementProvider ??= context.read<AdvertisementProvider>();
      _videoController =
          await _advertisementProvider!.videoPoolManager.getController(
        filePath: _currentFilePath!,
        videoType: VideoType.fullAd,
        autoPlay: true,
        looping: true,
        onError: () {
          if (mounted) {
            setState(() {
              _errorMessage = '視頻播放錯誤';
              _isLoadingVideo = false;
            });
          }
        },
      );

      // 详细的控制器初始化诊断
      if (_videoController != null) {
        _logger.i('🎬 控制器初始化详情：'
            'isInitialized=${_videoController!.value.isInitialized}, '
            'hasError=${_videoController!.value.hasError}, '
            'isPlaying=${_videoController!.value.isPlaying}, '
            'position=${_videoController!.value.position}, '
            'duration=${_videoController!.value.duration}');

        // 添加进度监听器
        _videoController!.addListener(_onVideoProgressChanged);

        // 等待视频完全加载
        int loadAttempts = 0;
        const maxLoadAttempts = 10;

        while (!_videoController!.value.isInitialized &&
            loadAttempts < maxLoadAttempts &&
            mounted) {
          await Future.delayed(const Duration(milliseconds: 100));
          loadAttempts++;
        }

        if (!_videoController!.value.isInitialized) {
          throw Exception('视频加载超时，无法初始化');
        }

        _logger.i('✅ 视频加载完成，开始播放流程');

        // 确保控制器已初始化
        if (_videoController!.value.isInitialized) {
          try {
            // 明确设置循环與首播參數
            await _videoController!.setLooping(true);
            await _videoController!.setVolume(1.0); // 修复：设置音量为1.0，恢复声音
            await _videoController!.setPlaybackSpeed(1.0);

            // 重置到开头
            await _videoController!.seekTo(Duration.zero);

            // 等待视频準備更充分（避免首次播放失敗）
            await Future.delayed(const Duration(milliseconds: 350));

            // 开始播放
            await _videoController!.play();

            debugPrint('▶️ 视频开始播放: ${widget.ad.title}');
            // 保留一次狀態觀察，不自動重播
            await Future.delayed(const Duration(milliseconds: 100));
            // final playingNow = _videoController!.value.isPlaying;
            // _logger.i('🎬 视频播放状态: isPlaying=$playingNow');
          } catch (playError) {
            _logger.e('❌ 视频播放失败',
                error: playError, stackTrace: StackTrace.current);
            throw Exception('视频播放初始化失败: $playError');
          }
        } else {
          _logger.w('⚠️ 控制器未初始化，无法播放');
          throw Exception('视频控制器未初始化');
        }

        setState(() {
          _isVideoInitialized = true;
          _isLoadingVideo = false;
        });
      } else {
        throw Exception('无法获取视频控制器');
      }
    } catch (e, stackTrace) {
      _logger.e('❌ 視頻初始化失败', error: e, stackTrace: stackTrace);

      if (mounted) {
        setState(() {
          _isLoadingVideo = false;
          _errorMessage = '視頻加載失败: $e';
          _isVideoInitialized = false;
        });
      }
    }
  }

  @override
  void dispose() {
    // 参考顶部广告实现：Widget自己负责释放控制器
    if (_isReleasing) {
      super.dispose();
      return;
    }

    _isReleasing = true;
    _logger.i('🗑️ FullAdWidget dispose 开始: ${widget.ad.title}');

    if (_videoController != null && _currentFilePath != null) {
      try {
        // 安全地移除监听器 - 这个总是需要的
        _videoController!.removeListener(_onVideoProgressChanged);
      } catch (e) {
        _logger.w('移除監聽器時出錯: $e');
      }

      // 🎯 关键改进：参考顶部广告，Widget自己释放控制器到池中
      _releaseVideoControllerToPool().then((_) {
        _logger.d('✅ FullAdWidget dispose完成: ${widget.ad.title}');
      }).catchError((error) {
        _logger.e('❌ FullAdWidget dispose释放控制器出错: $error');
      });

      _videoController = null;
      _currentFilePath = null;
    } else {
      _logger.d('✅ 无需释放控制器 - 控制器为空或路径为空');
    }

    super.dispose();
  }

  ///1，视频播放进度变化监听器
  void _onVideoProgressChanged() {
    try {
      if (_videoController != null &&
          _videoController!.value.isInitialized &&
          widget.onVideoProgressChanged != null &&
          mounted) {
        widget.onVideoProgressChanged!(widget.ad.id.toString(), Duration.zero);
      }
    } catch (e) {
      debugPrint('⚠️ 视频进度监听器出错: $e');
    }
  }

  ///2，处理轮播切换时的清理 - 参考顶部广告实现
  Future<void> _handleCarouselSwitch() async {
    if (_videoController != null) {
      _logger.i('🔄 全屏广告处理轮播切换，释放控制器: ${widget.ad.title}');
      // 直接释放控制器（释放方法内部已包含暂停逻辑）
      await _releaseVideoControllerToPool();
    }
  }

  ///3，暂停视频播放 - 参考顶部广告实现
  Future<void> _pauseVideo() async {
    if (_videoController != null) {
      try {
        if (_videoController!.value.isInitialized &&
            !_videoController!.value.hasError &&
            _videoController!.value.isPlaying) {
          await _videoController!.pause();
          _logger.i('📱 暂停全屏广告视频播放: ${widget.ad.title}');
        }
      } catch (e) {
        _logger.w('⚠️ 暂停视频播放失败: $e');
      }
    }
  }

  ///4，恢复视频播放 - 参考顶部广告实现
  Future<void> _resumeVideo() async {
    if (_videoController != null) {
      try {
        // 检查视频是否处于暂停状态
        if (_videoController!.value.isInitialized &&
            !_videoController!.value.hasError &&
            !_videoController!.value.isPlaying) {
          await _videoController!.play();
          _logger.i('📱 恢复全屏广告视频播放: ${widget.ad.title}');
        }
      } catch (e) {
        _logger.w('⚠️ 恢复视频播放失败: $e');
      }
    }
  }

  ///5，释放视频控制器到池中 - 参考顶部广告实现
  Future<void> _releaseVideoControllerToPool() async {
    if (_videoController != null && _currentFilePath != null) {
      try {
        _logger.i('🔓 开始释放全屏广告控制器到池中: $_currentFilePath');

        // 先暂停视频播放
        if (_videoController!.value.isPlaying) {
          await _videoController!.pause();
        }

        // 确保AdvertisementProvider引用可用
        _advertisementProvider ??= context.read<AdvertisementProvider>();

        if (_advertisementProvider != null) {
          // 释放控制器到池中
          await _advertisementProvider!.videoPoolManager.releaseController(
            filePath: _currentFilePath!,
            videoType: VideoType.fullAd,
          );

          _logger.d('✅ 全屏广告视频控制器已释放到池中: ${widget.ad.title}');

          // 调用回调
          if (widget.onVideoDisposed != null) {
            widget.onVideoDisposed!();
          }
        } else {
          _logger.w('⚠️ AdvertisementProvider引用为空，无法释放全屏广告视频控制器');
        }
      } catch (e) {
        _logger.w('⚠️ 释放全屏广告视频控制器时出错: $e');
      }

      _videoController = null;
      _currentFilePath = null;
    }
  }

  // 移除 _releaseExistingController 方法，不再需要频繁释放和重新创建控制器

  @override
  Widget build(BuildContext context) {
    // 参考顶部广告实现：使用NotificationListener监听媒体暂停和恢复通知
    return NotificationListener<Notification>(
      onNotification: (notification) {
        if (notification is MediaPauseNotification) {
          // 全屏广告状态：处理轮播切换，需要释放控制器
          debugPrint(
              '📢 FullAdWidget收到MediaPauseNotification: ${widget.ad.title}');
          Future.delayed(const Duration(milliseconds: 50), () {
            if (mounted) {
              _handleCarouselSwitch();
            }
          });
          return true; // 阻止通知继续传递
        } else if (notification is MediaResumeNotification) {
          // 防抖动执行，避免重复调用
          debugPrint(
              '📢 FullAdWidget收到MediaResumeNotification: ${widget.ad.title}');
          Future.delayed(const Duration(milliseconds: 50), () {
            if (mounted &&
                _videoController != null &&
                _videoController!.value.isInitialized) {
              _resumeVideo();
            }
          });
          return true; // 阻止通知继续传递
        }
        return false; // 其他通知继续传递
      },
      child: SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: Stack(
          children: [
            // 广告内容显示
            _buildAdContent(),

            // 可选：添加一个关闭按钮 (如果需要的話)
            // Positioned(
            //   top: 40,
            //   right: 20,
            //   child: IconButton(
            //     onPressed: () => Navigator.pop(context),
            //     icon: Icon(Icons.close, color: Colors.white, size: 30),
            //   ),
            // ),
          ],
        ),
      ),
    );
  }

  ///3，構建廣告內容
  Widget _buildAdContent() {
    // 根據文件類型顯示不同的內容
    if (widget.ad.file.mimeType.startsWith('image/')) {
      return _buildImageAd();
    } else if (widget.ad.file.mimeType.startsWith('video/')) {
      return _buildVideoAd();
    } else {
      return _buildDefaultAd();
    }
  }

  ///4，構建圖片廣告
  Widget _buildImageAd() {
    return FutureBuilder<File?>(
      future: widget.fileManager.getFile(widget.ad.file),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.black,
            child: const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          );
        }

        if (snapshot.hasData && snapshot.data != null) {
          final localFile = snapshot.data!;
          return SizedBox(
            width: double.infinity,
            height: double.infinity,
            child: Image.file(
              localFile,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (context, error, stackTrace) {
                debugPrint('本地圖片加載失敗: $error');
                return _buildNetworkImage();
              },
            ),
          );
        }

        // 如果本地文件不存在，顯示默認廣告而不是嘗試網絡加載
        // _logger.w('本地圖片文件不存在，顯示默認廣告: ${widget.ad.file.url}');
        return _buildDefaultAd();
      },
    );
  }

  ///5，構建網絡圖片
  Widget _buildNetworkImage() {
    return Image.network(
      widget.ad.file.url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          color: Colors.black,
          child: Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded /
                      loadingProgress.expectedTotalBytes!
                  : null,
              color: Colors.white,
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return _buildDefaultAd();
      },
    );
  }

  ///6，構建視頻廣告
  Widget _buildVideoAd() {
    if (_isLoadingVideo) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 20),
              SelectableText(
                '正在加載視頻...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 80,
                color: Colors.red,
              ),
              const SizedBox(height: 20),
              const SelectableText(
                '視頻加載失敗',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              SelectableText(
                _errorMessage!,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _initializeVideoPlayer,
                child: const SelectableText('重試'),
              ),
            ],
          ),
        ),
      );
    }

    if (_isVideoInitialized && _videoController != null) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black,
        child: FittedBox(
          fit: BoxFit.contain, // 修改为 contain 以完整显示视频内容
          child: SizedBox(
            width: _videoController!.value.size.width,
            height: _videoController!.value.size.height,
            child: VideoPlayer(_videoController!),
          ),
        ),
      );
    }

    // 显示视频预览或占位符
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.play_circle_outline,
              size: 100,
              color: Colors.white,
            ),
            const SizedBox(height: 20),
            const SelectableText(
              '視頻廣告',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            SelectableText(
              widget.ad.title,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  ///7，構建默認廣告
  Widget _buildDefaultAd() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.purple.shade400,
            Colors.blue.shade600,
            Colors.teal.shade500,
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.ads_click,
              size: 120,
              color: Colors.white,
            ),
            const SizedBox(height: 30),
            Text(
              widget.ad.title,
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                shadows: [
                  Shadow(
                    offset: const Offset(2, 2),
                    blurRadius: 4,
                    color: Colors.black.withOpacity(0.3),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Text(
              widget.ad.description,
              style: TextStyle(
                fontSize: 18,
                color: Colors.white.withOpacity(0.9),
                shadows: [
                  Shadow(
                    offset: const Offset(1, 1),
                    blurRadius: 2,
                    color: Colors.black.withOpacity(0.3),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
