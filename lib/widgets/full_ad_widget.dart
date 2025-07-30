import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:iboard_app/managers/file_manager.dart';
import 'package:iboard_app/models/ad_model.dart';
import 'package:logger/logger.dart';
import 'dart:io';

class FullAdWidget extends StatefulWidget {
  final AdModel ad;
  final FileManager fileManager;
  final Duration? initialVideoPosition; // 初始视频播放位置
  final Function(String adId, Duration position)?
      onVideoProgressChanged; // 视频进度变化回调
  final VoidCallback? onVideoDisposed; // 视频资源释放完成回调

  const FullAdWidget({
    Key? key,
    required this.ad,
    required this.fileManager,
    this.initialVideoPosition,
    this.onVideoProgressChanged,
    this.onVideoDisposed,
  }) : super(key: key);

  @override
  State<FullAdWidget> createState() => _FullAdWidgetState();
}

class _FullAdWidgetState extends State<FullAdWidget> {
  static final Logger _logger = Logger();
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  bool _isLoadingVideo = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _logger
        .i('🎬 初始化全屏广告: "${widget.ad.title}" - 类型: ${widget.ad.file.mimeType}');
    if (widget.ad.file.mimeType.startsWith('video/')) {
      _initializeVideo();
    }
  }

  @override
  void dispose() {
    // _logger.i('🔄 开始释放全屏广告Widget资源');

    // 安全释放视频控制器
    if (_videoController != null) {
      try {
        // 移除监听器
        _videoController!.removeListener(_onVideoProgressChanged);

        // 暂停播放
        if (_videoController!.value.isInitialized &&
            _videoController!.value.isPlaying) {
          _videoController!.pause();
        }

        // 释放资源
        _videoController!.dispose();
        _logger.i('✅ 视频控制器已安全释放');
      } catch (e) {
        _logger.w('⚠️ 释放视频控制器时出错: $e');
      } finally {
        _videoController = null;
        // 通知视频资源已释放
        if (widget.onVideoDisposed != null) {
          widget.onVideoDisposed!();
        }
      }
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
      _logger.w('⚠️ 视频进度监听器出错: $e');
    }
  }

  Future<void> _initializeVideo() async {
    if (_isLoadingVideo) return;

    _logger.i('🎥 开始初始化视频: ${widget.ad.file.url}');

    setState(() {
      _isLoadingVideo = true;
      _errorMessage = null;
    });

    try {
      // 释放之前的视频控制器
      if (_videoController != null) {
        try {
          _videoController!.removeListener(_onVideoProgressChanged);
          _videoController!.dispose();
        } catch (e) {
          _logger.w('⚠️ 释放旧视频控制器时出错: $e');
        }
        _videoController = null;
      }

      // 尝试从FileManager获取本地缓存的视频文件
      final File? localFile = await widget.fileManager.getFile(widget.ad.file);

      if (localFile != null && await localFile.exists()) {
        // 使用本地文件
        _logger.i('✅ 使用本地缓存视频文件: ${localFile.path}');
        _videoController = VideoPlayerController.file(localFile);
      } else {
        // 使用网络URL
        _logger.i('🌐 使用网络视频URL: ${widget.ad.file.url}');
        _videoController = VideoPlayerController.networkUrl(
          Uri.parse(widget.ad.file.url),
        );
      }

      // 初始化视频控制器
      await _videoController!.initialize();

      // 检查widget是否仍然挂载
      if (!mounted) {
        _logger.w('⚠️ Widget已卸载，停止视频初始化');
        _videoController?.dispose();
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
        _logger.i('⏩ 视频跳转到指定位置: ${widget.initialVideoPosition!.inSeconds}秒');
      }

      // 添加进度监听器
      _videoController!.addListener(_onVideoProgressChanged);

      // 自动播放视频（不循环，让Provider控制播放）
      _videoController!.setLooping(false);
      await _videoController!.play();
      // _logger.i('🎬 视频初始化成功并开始播放');
    } catch (e) {
      _logger.e('❌ 视频初始化失败: $e');

      // 清理资源
      if (_videoController != null) {
        try {
          _videoController!.dispose();
        } catch (disposeError) {
          _logger.w('⚠️ 清理失败的视频控制器时出错: $disposeError');
        }
        _videoController = null;
      }

      if (mounted) {
        setState(() {
          _isLoadingVideo = false;
          _errorMessage = '视频加载失败: $e';
          _isVideoInitialized = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      child: Stack(
        children: [
          // 广告内容显示
          _buildAdContent(),

          // 可选：添加一个关闭按钮 (如果需要的话)
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

  Widget _buildAdContent() {
    // 根据文件类型显示不同的内容
    if (widget.ad.file.mimeType.startsWith('image/')) {
      return _buildImageAd();
    } else if (widget.ad.file.mimeType.startsWith('video/')) {
      return _buildVideoAd();
    } else {
      return _buildDefaultAd();
    }
  }

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
          return Container(
            width: double.infinity,
            height: double.infinity,
            child: Image.file(
              localFile,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (context, error, stackTrace) {
                _logger.e('本地图片加载失败: ${localFile.path}', error: error);
                return _buildNetworkImage();
              },
            ),
          );
        }

        // 如果本地文件不存在，使用网络图片
        _logger.w('本地图片文件不存在，使用网络图片: ${widget.ad.file.url}');
        return _buildNetworkImage();
      },
    );
  }

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

  Widget _buildVideoAd() {
    if (_isLoadingVideo) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 20),
              Text(
                '正在加载视频...',
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
              Icon(
                Icons.error_outline,
                size: 80,
                color: Colors.red,
              ),
              SizedBox(height: 20),
              Text(
                '视频加载失败',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 10),
              Text(
                _errorMessage!,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: _initializeVideo,
                child: Text('重试'),
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
            Icon(
              Icons.play_circle_outline,
              size: 100,
              color: Colors.white,
            ),
            SizedBox(height: 20),
            Text(
              '視頻廣告',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 10),
            Text(
              widget.ad.title,
              style: TextStyle(
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
            Icon(
              Icons.ads_click,
              size: 120,
              color: Colors.white,
            ),
            SizedBox(height: 30),
            Text(
              widget.ad.title,
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                shadows: [
                  Shadow(
                    offset: Offset(2, 2),
                    blurRadius: 4,
                    color: Colors.black.withOpacity(0.3),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 20),
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
