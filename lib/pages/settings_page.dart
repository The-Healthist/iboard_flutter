import 'package:flutter/material.dart';
import 'package:iboard_app/pages/time_settings_page.dart';
import 'package:iboard_app/pages/print_device_list_page.dart'; // 添加打印機頁面導入
import 'package:iboard_app/providers/announcement_carousel_provider.dart';
import 'package:iboard_app/providers/ad_full_carousel_provider.dart';
import 'package:iboard_app/providers/state_provider.dart';
import 'package:iboard_app/providers/ad_top_carousel_provider.dart';
import 'package:iboard_app/providers/app_update_provider.dart'; // 导入更新Provider
import 'package:iboard_app/widgets/carousel_widget.dart'; // 导入通知类

import 'package:provider/provider.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  SettingsPageState createState() => SettingsPageState();
}

class SettingsPageState extends State<SettingsPage> {
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

    // 5. 暂停其他定时器
    carouselStateProvider.pauseAllStateTimers();

    // 6. 强制发送媒體暂停通知，确保所有视频都暂停
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

    // 从设置頁面强制重置到默认状态（绕过手动操作状态的转换限制）
    carouselStateProvider.resetToDefault();

    // 恢复顶部广告轮播
    topAdProvider.resumeAllTimersFromSettings();

    // 恢复通告轮播
    final apiNoticeStayDuration = carouselStateProvider.noticeStayDuration;
    announcementCarouselProvider
        .resumeAllTimersFromSettings(apiNoticeStayDuration);

    // 恢复全屏广告轮播（如果之前处于活跃状态）
    if (fullAdCarouselProvider.isActive && fullAdCarouselProvider.isPaused) {
      fullAdCarouselProvider.resumeCarousel();
      fullAdCarouselProvider.startDebugTimer();
    }

    // 强制发送媒體恢复通知，确保所有视频都恢复播放
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        MediaResumeNotification().dispatch(context);
      }
    });
  }

  ///5, 处理导航到子頁面 - 不恢复轮播
  void _navigateToSubPage(Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => page),
    );
  }

  ///6, 处理导航到轮播设置頁面 - 不恢复轮播
  void _navigateToCarouselSettings() {
    Navigator.pushNamed(context, '/carousel-settings');
  }

  ///7, 处理真正退出设置頁面 - 恢复轮播
  void _exitSettingsPage() {
    // 立即恢复所有轮播和计时器
    _resumeAllCarouselsFromSettings();

    // 延迟发送媒體恢复通知，确保所有视频都恢复播放
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        MediaResumeNotification().dispatch(context);
      }
    });

    Navigator.pop(context);
  }

  ///8, 构建版本更新项目

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvoked: (didPop) {
        if (didPop) {
          // 在返回前恢复所有轮播
          _resumeAllCarouselsFromSettings();

          // 延迟发送媒體恢复通知，确保所有视频都恢复播放
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              MediaResumeNotification().dispatch(context);
            }
          });
        }
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
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.1),
                        spreadRadius: 1,
                        blurRadius: 3,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: _exitSettingsPage, // 使用新的退出方法
                        icon: const Icon(Icons.arrow_back, size: 28),
                      ),
                      const SizedBox(width: 16),
                      Icon(
                        Icons.settings,
                        size: 32,
                        color: Colors.blue.shade600,
                      ),
                      const SizedBox(width: 16),
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
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        const SizedBox(height: 40),
                        // 設置項目占位符
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.1),
                                spreadRadius: 1,
                                blurRadius: 6,
                                offset: const Offset(0, 2),
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
                              const SizedBox(height: 20),
                              Text(
                                '設置內容區域',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              const SizedBox(height: 16),
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
                        const SizedBox(height: 30),
                        // 示例設置選項
                        _buildSettingsItem(
                          icon: Icons.schedule,
                          title: '時間設定',
                          subtitle: '查看設備資訊和系統時間參數設置',
                          onTap: () =>
                              _navigateToSubPage(const TimeSettingsPage()),
                        ),
                        const SizedBox(height: 16),
                        _buildSettingsItem(
                          icon: Icons.display_settings,
                          title: '顯示設置',
                          subtitle: '調整螢幕顯示參數',
                          onTap: _navigateToCarouselSettings,
                        ),
                        const SizedBox(height: 16),
                        _buildSettingsItem(
                          icon: Icons.network_wifi,
                          title: '網絡設置',
                          subtitle: '配置網絡連接',
                          onTap: () {},
                        ),
                        const SizedBox(height: 16),
                        _buildSettingsItem(
                          icon: Icons.print,
                          title: '打印機設置',
                          subtitle: '管理WiFi打印機設備',
                          onTap: () =>
                              _navigateToSubPage(const PrintDeviceListPage()),
                        ),
                        const SizedBox(height: 16),
                        _buildSettingsItem(
                          icon: Icons.videocam_outlined,
                          title: '實時監控頁面',
                          subtitle: '全屏查看實時視頻流',
                          onTap: () => Navigator.pushNamed(
                              context, '/live-monitor-webview'),
                        ),
                        const SizedBox(height: 16),
                        _buildVersionUpdateItem(),
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
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
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
          style: const TextStyle(
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

  ///8. 构建版本更新项目
  Widget _buildVersionUpdateItem() {
    return Consumer<AppUpdateProvider>(
      builder: (context, updateProvider, child) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                spreadRadius: 1,
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.system_update,
                color: Colors.blue.shade600,
                size: 24,
              ),
            ),
            title: const Text(
              '版本更新',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              '檢查應用程序版本更新',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
            trailing: updateProvider.hasLocalApk
                ? ElevatedButton(
                    onPressed: updateProvider.canInstall
                        ? () async {
                            await updateProvider.installApk();
                          }
                        : null, // 不满足条件时禁用按钮
                    style: ElevatedButton.styleFrom(
                      backgroundColor: updateProvider.canInstall
                          ? Colors.blue.shade600
                          : Colors.grey.shade400, // 禁用时使用灰色背景
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      minimumSize: const Size(80, 32), // 稍微增加按钮宽度以容纳loading
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: updateProvider.isInstalling
                        ? const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              ),
                              SizedBox(width: 6),
                              Text(
                                '安装中',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            updateProvider.canInstall ? '更新' : '請稍候',
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w500),
                          ),
                  )
                : Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Text(
                      '已是最新版本',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
            onTap: updateProvider.hasLocalApk
                ? null // 有更新时不允许整行点击，只能点击按钮
                : () => _navigateToSubPage(const TimeSettingsPage()),
          ),
        );
      },
    );
  }
}
