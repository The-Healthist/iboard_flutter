import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:iboard_app/managers/file_manager.dart';
import 'package:iboard_app/models/ad_model.dart';
import 'package:logger/logger.dart';
import 'dart:io';

class FullAdWidget extends StatefulWidget {
  final AdModel ad;
  final FileManager fileManager;

  const FullAdWidget({
    Key? key,
    required this.ad,
    required this.fileManager,
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
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _initializeVideo() async {
    if (_isLoadingVideo) return;

    _logger.i('🎥 开始初始化视频: ${widget.ad.file.url}');

    setState(() {
      _isLoadingVideo = true;
      _errorMessage = null;
    });

    try {
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

      await _videoController!.initialize();

      if (mounted) {
        setState(() {
          _isVideoInitialized = true;
          _isLoadingVideo = false;
        });

        // 自动播放视频并循环
        _videoController!.setLooping(true);
        _videoController!.play();
        _logger.i('🎬 视频初始化成功并开始播放');
      }
    } catch (e) {
      _logger.e('❌ 视频初始化失败: $e');
      if (mounted) {
        setState(() {
          _isLoadingVideo = false;
          _errorMessage = '视频加载失败: $e';
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
    return Container(
      width: double.infinity,
      height: double.infinity,
      child: widget.ad.file.localFilePath != null
          ? Image.asset(
              widget.ad.file.localFilePath!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return _buildNetworkImage();
              },
            )
          : _buildNetworkImage(),
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
        child: Center(
          child: AspectRatio(
            aspectRatio: _videoController!.value.aspectRatio,
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
