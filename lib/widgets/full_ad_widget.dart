import 'package:flutter/material.dart';
import 'package:iboard_app/managers/file_manager.dart';
import 'package:iboard_app/models/ad_model.dart';

class FullAdWidget extends StatelessWidget {
  final AdModel ad;
  final FileManager fileManager;

  const FullAdWidget({
    Key? key,
    required this.ad,
    required this.fileManager,
  }) : super(key: key);

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
    if (ad.file.mimeType.startsWith('image/')) {
      return _buildImageAd();
    } else if (ad.file.mimeType.startsWith('video/')) {
      return _buildVideoAd();
    } else {
      return _buildDefaultAd();
    }
  }

  Widget _buildImageAd() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      child: ad.file.localFilePath != null
          ? Image.asset(
              ad.file.localFilePath!,
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
      ad.file.url,
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
    // TODO: 实现视频播放组件
    // 这里可以使用 video_player 包来播放视频
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
              ad.title,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 20),
            // 显示网络图片作为视频预览
            Container(
              width: 300,
              height: 200,
              child: _buildNetworkImage(),
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
              ad.title,
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
              ad.description,
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
