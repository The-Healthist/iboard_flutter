import 'package:flutter/foundation.dart';
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
            // 优化网络错误处理：优先使用缓存数据，只有在完全没有数据时才显示错误
            final error = advertisementProvider.error!;
            if (fullAds.isNotEmpty) {
              // 有缓存数据时，无论什么错误都继续使用缓存数据
              _logger.i('🎯 [网络错误] 检测到错误但有缓存数据，继续使用: ${fullAds.length}个全屏广告');
            } else if (error.contains('网络连接失败') ||
                error.contains('请求超时') ||
                error.contains('无法连接到服务器') ||
                error.contains('🌐') ||
                error.contains('⏱️') ||
                error.contains('🔌') ||
                error.contains('📱')) {
              // 网络错误且没有缓存数据时，显示友好的离线界面而不是错误界面
              return _buildOfflineState();
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
                  // 调试时间组件 - 只在debug模式下显示
                  if (kDebugMode) const DebugFullAdTimeWidget(),
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
                // 调试时间组件 - 只在debug模式下显示
                if (kDebugMode) const DebugFullAdTimeWidget(),
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

  ///2a，构建离线状态界面
  Widget _buildOfflineState() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.grey.shade800,
            Colors.grey.shade600,
            Colors.grey.shade700,
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.wifi_off,
              size: 120,
              color: Colors.white70,
            ),
            SizedBox(height: 30),
            Text(
              '离线模式',
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 20),
            Text(
              '網絡連接中斷，正在使用離線數據\n廣告將在網絡恢復後自動更新',
              style: TextStyle(
                fontSize: 18,
                color: Colors.white70,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
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
          // 调试时间组件 - 只在debug模式下显示
          if (kDebugMode) const DebugFullAdTimeWidget(),
        ],
      ),
    );
  }
}
