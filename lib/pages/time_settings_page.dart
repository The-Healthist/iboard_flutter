import 'package:flutter/material.dart';
import 'package:iboard_app/providers/announcement_carousel_provider.dart';
import 'package:iboard_app/providers/app_data_provider.dart';
import 'package:iboard_app/providers/fullscreen_ad_provider.dart';
import 'package:iboard_app/providers/state_provider.dart';
import 'package:iboard_app/providers/top_ad_carousel_provider.dart';
import 'package:iboard_app/widgets/carousel_widget.dart';
import 'package:provider/provider.dart';

class TimeSettingsPage extends StatefulWidget {
  const TimeSettingsPage({Key? key}) : super(key: key);

  @override
  _TimeSettingsPageState createState() => _TimeSettingsPageState();
}

class _TimeSettingsPageState extends State<TimeSettingsPage> {
  /// 恢复所有轮播和计时器
  void _resumeAllCarouselsFromSettings() {
    final carouselStateProvider = context.read<CarouselStateProvider>();
    final topAdProvider = context.read<TopAdCarouselProvider>();
    final announcementCarouselProvider =
        context.read<AnnouncementCarouselProvider>();
    final fullAdCarouselProvider = context.read<FullscreenAdProvider>();

    // 确保保持在手动操作状态
    carouselStateProvider.enterManualOperation();

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

    // 强制发送媒体恢复通知，确保所有视频都恢复播放
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        MediaResumeNotification().dispatch(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // 在返回前恢复所有轮播
        _resumeAllCarouselsFromSettings();
        return true; // 允许返回
      },
      child: Consumer<AppDataProvider>(
        builder: (context, appDataProvider, child) {
          final hasDeviceId = appDataProvider.deviceId != null;
          final isLoggedIn = appDataProvider.isLoggedIn;
          final deviceId = appDataProvider.deviceId;
          final settingsModel = appDataProvider.settingsModel;
          final deviceSettings = appDataProvider.deviceSettings;
          final error = appDataProvider.error;

          return Scaffold(
            backgroundColor: Colors.grey.shade50,
            body: Container(
              width: double.infinity,
              height: double.infinity,
              child: SafeArea(
                child: Column(
                  children: [
                    // 顶部标题区域
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.05),
                            spreadRadius: 1,
                            blurRadius: 3,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () {
                              // 在返回前恢复所有轮播
                              _resumeAllCarouselsFromSettings();
                              Navigator.pop(context);
                            },
                            icon: Icon(Icons.arrow_back, size: 28),
                          ),
                          SizedBox(width: 16),
                          Icon(
                            Icons.schedule,
                            size: 32,
                            color: Colors.blue.shade600,
                          ),
                          SizedBox(width: 16),
                          Text(
                            '時間設定',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 主要内容区域
                    Expanded(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 设备基本信息卡片
                            Container(
                              width: double.infinity,
                              margin: EdgeInsets.only(top: 8),
                              padding: EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.grey.withOpacity(0.05),
                                    spreadRadius: 1,
                                    blurRadius: 3,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade50,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Icon(
                                          Icons.devices,
                                          color: Colors.blue.shade600,
                                          size: 24,
                                        ),
                                      ),
                                      SizedBox(width: 16),
                                      Text(
                                        '设备信息',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey.shade800,
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 24),
                                  _buildInfoRow('设备ID', deviceId ?? '未获取'),
                                  SizedBox(height: 12),
                                  _buildInfoRow(
                                    '登录状态',
                                    isLoggedIn ? '已登录' : '未登录',
                                    isLoggedIn
                                        ? Colors.green.shade700
                                        : Colors.red.shade700,
                                  ),
                                  if (error != null) ...[
                                    SizedBox(height: 12),
                                    _buildInfoRow(
                                        '错误信息', error, Colors.red.shade700),
                                  ],
                                ],
                              ),
                            ),

                            // 时间设置卡片
                            if (deviceSettings != null) ...[
                              SizedBox(height: 24),
                              Container(
                                width: double.infinity,
                                padding: EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.grey.withOpacity(0.05),
                                      spreadRadius: 1,
                                      blurRadius: 3,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: Colors.blue.shade50,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Icon(
                                            Icons.timer,
                                            color: Colors.blue.shade600,
                                            size: 24,
                                          ),
                                        ),
                                        SizedBox(width: 16),
                                        Text(
                                          '时间设置',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.grey.shade800,
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 24),
                                    _buildTimeSettingRow(
                                      '欠费更新间隔',
                                      '${deviceSettings.arrearageUpdateDuration}秒',
                                    ),
                                    SizedBox(height: 12),
                                    _buildTimeSettingRow(
                                      '通告更新间隔',
                                      '${deviceSettings.noticeUpdateDuration}秒',
                                    ),
                                    SizedBox(height: 12),
                                    _buildTimeSettingRow(
                                      '广告更新间隔',
                                      '${deviceSettings.advertisementUpdateDuration}秒',
                                    ),
                                    SizedBox(height: 12),
                                    _buildTimeSettingRow(
                                      '广告播放时长',
                                      '${deviceSettings.advertisementPlayDuration}秒',
                                    ),
                                    SizedBox(height: 12),
                                    _buildTimeSettingRow(
                                      '通告播放时长',
                                      '${deviceSettings.noticePlayDuration}秒',
                                    ),
                                    SizedBox(height: 12),
                                    _buildTimeSettingRow(
                                      '空闲时长',
                                      '${deviceSettings.spareDuration}秒',
                                    ),
                                    SizedBox(height: 12),
                                    _buildTimeSettingRow(
                                      '通告停留时长',
                                      '${deviceSettings.noticeStayDuration}秒',
                                    ),
                                  ],
                                ),
                              ),
                            ] else ...[
                              SizedBox(height: 24),
                              Container(
                                width: double.infinity,
                                padding: EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.grey.withOpacity(0.05),
                                      spreadRadius: 1,
                                      blurRadius: 3,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.schedule_outlined,
                                      size: 64,
                                      color: Colors.grey.shade400,
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      '請先登錄設備以查看時間設定',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, [Color? valueColor]) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 100,
          child: Text(
            '$label:',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: valueColor ?? Colors.grey.shade900,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimeSettingRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 140,
          child: Text(
            '$label:',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade900,
            ),
          ),
        ),
      ],
    );
  }
}
