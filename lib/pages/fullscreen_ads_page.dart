import 'package:flutter/material.dart';
import 'package:iboard_app/managers/file_manager.dart';
import 'package:iboard_app/providers/advertisement_provider.dart';
import 'package:iboard_app/widgets/full_ad_widget.dart';
import 'package:provider/provider.dart';

class FullscreenAdsPage extends StatefulWidget {
  @override
  _FullscreenAdsPageState createState() => _FullscreenAdsPageState();
}

class _FullscreenAdsPageState extends State<FullscreenAdsPage> {
  int _currentAdIndex = 0;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<AdvertisementProvider>(
        builder: (context, advertisementProvider, child) {
          final fullAds = advertisementProvider.fullAdvertisements;

          if (advertisementProvider.isLoading) {
            return Container(
              width: double.infinity,
              height: double.infinity,
              color: Colors.black,
              child: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            );
          }

          if (advertisementProvider.error != null) {
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
                      '廣告載入失敗',
                      style: TextStyle(
                        fontSize: 24,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 10),
                    Text(
                      advertisementProvider.error!,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white70,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          if (fullAds.isEmpty) {
            return _buildDefaultFullscreenAd();
          }

          // 显示全屏广告
          final currentAd = fullAds[_currentAdIndex % fullAds.length];
          FileManager fileManager = FileManager();
          fileManager.getFile(currentAd.file);

          return FullAdWidget(
            ad: currentAd,
            fileManager: fileManager,
          );
        },
      ),
    );
  }

  Widget _buildDefaultFullscreenAd() {
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
      child: Stack(
        children: [
          // 全屏廣告內容
          Center(
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
                  '全屏廣告展示區域',
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
                  '暫無全屏廣告內容',
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
        ],
      ),
    );
  }
}
