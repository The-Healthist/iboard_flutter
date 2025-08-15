import 'package:flutter/material.dart';
import 'package:iboard_app/pages/time_settings_page.dart';
import 'package:iboard_app/providers/announcement_carousel_provider.dart';
import 'package:iboard_app/providers/fullscreen_ad_provider.dart';
import 'package:iboard_app/providers/state_provider.dart';
import 'package:iboard_app/providers/top_ad_carousel_provider.dart';
import 'package:iboard_app/providers/bottom_weather_qrcode_carousel_provider.dart';
import 'package:iboard_app/widgets/carousel_widget.dart'; // 导入通知类

import 'package:provider/provider.dart';

class SettingsPage extends StatefulWidget {
  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  ///1, 初始化状态 - 暂停所有轮播
  @override
  void initState() {
    super.initState();

    // 延迟执行，确保上下文已准备好
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pauseAllCarouselsForSettings();
    });
  }

  ///2, 销毁状态 - 确保资源清理
  @override
  void dispose() {
    // dispose方法中不再需要恢复逻辑，因为在_exitSettingsPage中已经处理
    // 这里只做必要的资源清理
    super.dispose();
  }

  ///3, 暂停所有轮播和计时器
  void _pauseAllCarouselsForSettings() {
    final topAdProvider = context.read<TopAdCarouselProvider>();
    final announcementCarouselProvider =
        context.read<AnnouncementCarouselProvider>();
    final fullAdCarouselProvider = context.read<FullscreenAdProvider>();
    final bottomProvider = context.read<BottomWeatherQrcodeCarouselProvider>();
    final carouselStateProvider = context.read<CarouselStateProvider>();

    // 1. 进入手动操作状态以防止自动切换到全屏广告
    carouselStateProvider.enterManualOperation();

    // 2. 暂停全屏广告轮播（如果活跃状态）
    if (fullAdCarouselProvider.isActive) {
      fullAdCarouselProvider.pauseCarousel();
      fullAdCarouselProvider.stopDebugTimer();
    }

    // 3. 暂停通告轮播
    announcementCarouselProvider.pauseAllTimersForSettings();

    // 4. 暂停顶部广告轮播
    topAdProvider.pauseAllTimersForSettings();

    // 5. 暂停底部天气二维码轮播
    bottomProvider.pauseAllTimersForSettings();

    // 6. 暂停其他定时器
    carouselStateProvider.pauseAllStateTimers();

    // 7. 强制发送媒体暂停通知，确保所有视频都暂停
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        MediaPauseNotification().dispatch(context);
      }
    });
  }

  ///4, 恢复所有轮播和计时器
  void _resumeAllCarouselsFromSettings() {
    final carouselStateProvider = context.read<CarouselStateProvider>();
    final topAdProvider = context.read<TopAdCarouselProvider>();
    final announcementCarouselProvider =
        context.read<AnnouncementCarouselProvider>();
    final fullAdCarouselProvider = context.read<FullscreenAdProvider>();
    final bottomProvider = context.read<BottomWeatherQrcodeCarouselProvider>();

    // 从设置页面强制重置到默认状态（绕过手动操作状态的转换限制）
    carouselStateProvider.resetToDefault();

    // 恢复顶部广告轮播
    topAdProvider.resumeAllTimersFromSettings();

    // 恢复通告轮播
    final apiNoticeStayDuration = carouselStateProvider.noticeStayDuration;
    announcementCarouselProvider
        .resumeAllTimersFromSettings(apiNoticeStayDuration);

    // 恢复底部天气二维码轮播
    bottomProvider.resumeAllTimersFromSettings();

    // 恢复全屏广告轮播（如果之前处于活跃状态）
    if (fullAdCarouselProvider.isActive && fullAdCarouselProvider.isPaused) {
      fullAdCarouselProvider.resumeCarousel();
      fullAdCarouselProvider.startDebugTimer();
    }

    // 强制发送媒体恢复通知，确保所有视频都恢复播放
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        MediaResumeNotification().dispatch(context);
      }
    });
  }

  ///5, 处理导航到子页面 - 不恢复轮播
  void _navigateToSubPage(Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => page),
    );
  }

  ///6, 处理导航到轮播设置页面 - 不恢复轮播
  void _navigateToCarouselSettings() {
    Navigator.pushNamed(context, '/carousel-settings');
  }

  ///7, 处理真正退出设置页面 - 恢复轮播
  void _exitSettingsPage() {
    // 立即恢复所有轮播和计时器
    _resumeAllCarouselsFromSettings();

    // 延迟发送媒体恢复通知，确保所有视频都恢复播放
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        MediaResumeNotification().dispatch(context);
      }
    });

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // 在返回前恢复所有轮播
        _resumeAllCarouselsFromSettings();

        // 延迟发送媒体恢复通知，确保所有视频都恢复播放
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            MediaResumeNotification().dispatch(context);
          }
        });

        return true; // 允许返回
      },
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.grey.shade50,
          child: SafeArea(
            child: Column(
              children: [
                // 頂部標題區域
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.1),
                        spreadRadius: 1,
                        blurRadius: 3,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: _exitSettingsPage, // 使用新的退出方法
                        icon: Icon(Icons.arrow_back, size: 28),
                      ),
                      SizedBox(width: 16),
                      Icon(
                        Icons.settings,
                        size: 32,
                        color: Colors.blue.shade600,
                      ),
                      SizedBox(width: 16),
                      Text(
                        '設置',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
                // 主要設置內容區域
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(20),
                    child: Column(
                      children: [
                        SizedBox(height: 40),
                        // 設置項目占位符
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.1),
                                spreadRadius: 1,
                                blurRadius: 6,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.tune,
                                size: 80,
                                color: Colors.blue.shade400,
                              ),
                              SizedBox(height: 20),
                              Text(
                                '設置內容區域',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              SizedBox(height: 16),
                              Text(
                                '這裡將顯示各種設置選項',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey.shade600,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 30),
                        // 示例設置選項
                        _buildSettingsItem(
                          icon: Icons.schedule,
                          title: '時間設定',
                          subtitle: '查看設備資訊和系統時間參數設置',
                          onTap: () => _navigateToSubPage(TimeSettingsPage()),
                        ),
                        SizedBox(height: 16),
                        _buildSettingsItem(
                          icon: Icons.display_settings,
                          title: '顯示設置',
                          subtitle: '調整螢幕顯示參數',
                          onTap: _navigateToCarouselSettings,
                        ),
                        SizedBox(height: 16),
                        _buildSettingsItem(
                          icon: Icons.network_wifi,
                          title: '網絡設置',
                          subtitle: '配置網絡連接',
                          onTap: () {},
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: ListTile(
        leading: Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: Colors.blue.shade600,
            size: 24,
          ),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
          ),
        ),
        trailing: Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: Colors.grey.shade400,
        ),
        onTap: onTap,
      ),
    );
  }
}
