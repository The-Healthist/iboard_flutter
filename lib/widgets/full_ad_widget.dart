import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:iboard_app/managers/file_manager.dart';
import 'package:iboard_app/models/ad_model.dart';
import 'package:iboard_app/utils/video_resource_manager.dart';
import 'package:iboard_app/utils/enhanced_video_pool_manager.dart';
import 'package:iboard_app/providers/advertisement_provider.dart';
import 'package:provider/provider.dart';
import 'package:logger/logger.dart';
import 'dart:io';

class FullAdWidget extends StatefulWidget {
  final AdModel ad;
  final FileManager fileManager;
  final Duration? initialVideoPosition; // 初始视频播放位置
  final Function(String adId, Duration position)?
      onVideoProgressChanged; // 视频进度变化回掉
  final VoidCallback? onVideoDisposed; // 视频资源释放完成回掉

  const FullAdWidget({
    super.key,
    required this.ad,
    required this.fileManager,
    this.initialVideoPosition,
    this.onVideoProgressChanged,
    this.onVideoDisposed,
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
  bool _isNetworkVideo = false; // 是否为网络视频

  // 保存AdvertisementProvider引用，避免dispose时context访问问题
  AdvertisementProvider? _advertisementProvider;

  @override
  void initState() {
    super.initState();
    // _logger
    //     .i('🎬 初始化全屏广告: "${widget.ad.title}" - 类型: ${widget.ad.file.mimeType}');
    if (widget.ad.file.mimeType.startsWith('video/')) {
      _initializeVideo();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 在组件依赖变化时保存Provider引用，确保dispose时可以安全使用
    _advertisementProvider ??= context.read<AdvertisementProvider>();
  }

  @override
  void dispose() {
    // _logger.i('🔄 开始释放全屏广告Widget资源');

    // 释放视频控制器到池中
    if (_videoController != null && _currentFilePath != null) {
      // 移除监听器
      _videoController!.removeListener(_onVideoProgressChanged);

      // 释放到增强池中，避免阻塞dispose
      try {
        // 使用保存的Provider引用，避免context访问问题
        if (_advertisementProvider != null) {
          _advertisementProvider!.videoPoolManager
              .releaseController(
            filePath: _currentFilePath!,
            videoType: VideoType.fullAd,
            isNetwork: _isNetworkVideo,
          )
              .then((_) {
            // 通知视频资源已释放
            if (widget.onVideoDisposed != null) {
              widget.onVideoDisposed!();
            }
            // _logger.i('✅ 全屏广告视频控制器已释放到增強池中');
          });
        } else {
          _logger.w('⚠️ AdvertisementProvider引用为空，无法释放视频控制器');
        }
      } catch (e) {
        _logger.w('⚠️ 释放全屏视频控制器时出错: $e');
      }
      _videoController = null;
    }

    super.dispose();
    // _logger.i('✅ 全屏广告Widget资源释放完成');
  }

  ///1，视频播放进度变化监听器
  void _onVideoProgressChanged() {
    try {
      if (_videoController != null &&
          _videoController!.value.isInitialized &&
          widget.onVideoProgressChanged != null &&
          mounted) {
        final position = _videoController!.value.position;
        // 每秒回调一次进度，避免过于频繁的回调
        widget.onVideoProgressChanged!(widget.ad.id.toString(), position);
      }
    } catch (e) {
      // _logger.w('⚠️ 视频进度监听器出错: $e');
    }
  }

  ///2，初始化视频
  Future<void> _initializeVideo() async {
    if (_isLoadingVideo || !mounted) return;

    // _logger.i('🎥 开始初始化视频: ${widget.ad.file.url}');

    setState(() {
      _isLoadingVideo = true;
      _errorMessage = null;
    });

    try {
      // 释放之前的视频控制器到增强池中
      if (_videoController != null && _currentFilePath != null) {
        _videoController!.removeListener(_onVideoProgressChanged);
        // 确保Provider引用可用
        if (!mounted) return;
        _advertisementProvider ??= context.read<AdvertisementProvider>();
        await _advertisementProvider!.videoPoolManager.releaseController(
          filePath: _currentFilePath!,
          videoType: VideoType.fullAd,
          isNetwork: _isNetworkVideo,
        );
        _videoController = null;
      }

      // 尝试从FileManager获取本地缓存的视频文件
      final File? localFile = await widget.fileManager.getFile(widget.ad.file);
      if (!mounted) return;

      String filePath;
      bool isNetwork = false;

      if (localFile != null && await localFile.exists()) {
        // 使用本地文件
        // _logger.i('✅ 使用本地缓存视频文件: ${localFile.path}');
        filePath = localFile.path;
        isNetwork = false;
      } else {
        // 本地文件不存在时，检查网络连接状态
        // _logger.w('⚠️ 本地视频文件不存在: ${widget.ad.file.url}');
        // 如果没有本地文件，显示错误而不是尝试网络加载（避免网络依赖）
        if (mounted) {
          setState(() {
            _errorMessage = '视频文件未缓存，无法离线播放';
            _isLoadingVideo = false;
            _isVideoInitialized = false;
          });
        }
        return;
      }

      // 记录当前文件信息
      _currentFilePath = filePath;
      _isNetworkVideo = isNetwork;

      // 使用增强视频池管理器初始化
      if (!mounted) return;
      _advertisementProvider ??= context.read<AdvertisementProvider>();
      _videoController =
          await _advertisementProvider!.videoPoolManager.getController(
        filePath: filePath,
        videoType: VideoType.fullAd,
        isNetwork: isNetwork,
        autoPlay: false, // 先不自动播放，等设置完成后再播放
        looping: false,
        onError: () {
          if (mounted) {
            setState(() {
              _errorMessage = '视频播放出现错误';
              _isLoadingVideo = false;
              _isVideoInitialized = false;
            });
          }
        },
      );

      if (_videoController == null) {
        throw Exception('视频控制器初始化失败');
      }

      // 检查widget是否仍然挂载
      if (!mounted) {
        // _logger.w('⚠️ Widget已卸载，停止视频初始化');
        await _advertisementProvider!.videoPoolManager.releaseController(
          filePath: _currentFilePath!,
          videoType: VideoType.fullAd,
          isNetwork: _isNetworkVideo,
        );
        _videoController = null;
        return;
      }

      setState(() {
        _isVideoInitialized = true;
        _isLoadingVideo = false;
      });

      // 如果有初始播放位置，跳转到该位置
      if (widget.initialVideoPosition != null &&
          widget.initialVideoPosition!.inMilliseconds > 0) {
        await _videoController!.seekTo(widget.initialVideoPosition!);
        // _logger.i('⏩ 视频跳转到指定位置: ${widget.initialVideoPosition!.inSeconds}秒');
      }

      // 添加进度监听器
      _videoController!.addListener(_onVideoProgressChanged);

      // 自動播放视頻（不循環，讓Provider控制播放）
      _videoController!.setLooping(false);
      await _videoController!.safePlay();
      // _logger.i('🎬 視頻初始化成功並開始播放');
    } catch (e) {
      _logger.e('❌ 視頻初始化失敗: $e');

      // 清理資源
      if (_videoController != null && _currentFilePath != null) {
        if (!mounted) return;
        _advertisementProvider ??= context.read<AdvertisementProvider>();
        await _advertisementProvider!.videoPoolManager.releaseController(
          filePath: _currentFilePath!,
          videoType: VideoType.fullAd,
          isNetwork: _isNetworkVideo,
        );
        _videoController = null;
      }

      if (mounted) {
        setState(() {
          _isLoadingVideo = false;
          _errorMessage = '視頻加載失敗: $e';
          _isVideoInitialized = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
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
                _logger.e('本地圖片加載失敗: ${localFile.path}', error: error);
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
                onPressed: _initializeVideo,
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
