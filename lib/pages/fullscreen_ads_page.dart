import 'package:flutter/material.dart';
import 'package:iboard_app/providers/advertisement_provider.dart';
import 'package:iboard_app/providers/fullscreen_ad_provider.dart';
import 'package:iboard_app/widgets/debug_fullad_time_widget.dart';
import 'package:provider/provider.dart';
import 'package:logger/logger.dart';

class FullscreenAdsPage extends StatefulWidget {
  @override
  _FullscreenAdsPageState createState() => _FullscreenAdsPageState();
}

class _FullscreenAdsPageState extends State<FullscreenAdsPage> {
  final Logger _logger = Logger();

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer2<AdvertisementProvider, FullscreenAdProvider>(
        builder: (context, advertisementProvider, fullscreenAdProvider, child) {
          final fullAds = advertisementProvider.fullAdvertisements;

          // 检查是否有错误
          if (advertisementProvider.error != null) {
            // 检查是否是网络错误，如果是网络错误且有缓存数据，则继续使用缓存数据
            final error = advertisementProvider.error!;
            if ((error.contains('网络连接失败') ||
                    error.contains('请求超时') ||
                    error.contains('使用缓存的')) &&
                fullAds.isNotEmpty) {
              // 继续使用缓存的数据，不显示错误界面
            } else {
              return _buildErrorState(error);
            }
          }

          // 检查是否正在加载
          if (advertisementProvider.isLoading) {
            return _buildLoadingState();
          }

          // 检查是否有广告数据
          if (fullAds.isEmpty) {
            return _buildDefaultFullscreenAd();
          }

          // 确保Provider有最新的广告数据 - 延迟到构建完成后执行避免setState错误
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              fullscreenAdProvider.updateFullscreenAds(fullAds);
            }
          });

          // 如果Provider处于活跃状态并且有当前广告Widget，显示它
          if (fullscreenAdProvider.isActive) {
            final currentAdWidget = fullscreenAdProvider.getCurrentWidget();
            if (currentAdWidget != null) {
              return Stack(
                children: [
                  // 全屏广告内容
                  Container(
                    width: double.infinity,
                    height: double.infinity,
                    child: currentAdWidget,
                  ),
                  // 调试时间组件
                  const DebugFullAdTimeWidget(),
                ],
              );
            }
          }

          // 默认显示第一个广告（用于初始化时）
          if (fullscreenAdProvider.adWidgets.isNotEmpty) {
            return Stack(
              children: [
                // 全屏广告内容
                Container(
                  width: double.infinity,
                  height: double.infinity,
                  child: fullscreenAdProvider.adWidgets.first,
                ),
                // 调试时间组件
                const DebugFullAdTimeWidget(),
              ],
            );
          }

          return _buildDefaultFullscreenAd();
        },
      ),
    );
  }

  ///1，构建错误状态界面
  Widget _buildErrorState(String error) {
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
            SelectableText.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '廣告載入失敗\n',
                    style: TextStyle(
                      fontSize: 24,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextSpan(
                    text: error,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.red,
                    ),
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

  ///2，构建加载状态界面
  Widget _buildLoadingState() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black,
      child: Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );
  }

  ///3，构建默认全屏广告界面
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
          // 调试时间组件
          const DebugFullAdTimeWidget(),
        ],
      ),
    );
  }
}
