import 'package:flutter/material.dart';
import 'package:iboard_app/providers/announcement_carousel_provider.dart';
import 'package:iboard_app/providers/app_data_provider.dart';
import 'package:iboard_app/providers/fullscreen_ad_provider.dart';
import 'package:iboard_app/providers/state_provider.dart';
import 'package:iboard_app/providers/top_ad_carousel_provider.dart';
import 'package:iboard_app/widgets/carousel_widget.dart';
import 'package:iboard_app/widgets/debug_timer_widget.dart';
import 'package:iboard_app/widgets/debug_update_time_widget.dart'; // 导入调试窗口
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart'; // 导入kDebugMode

class TimeSettingsPage extends StatefulWidget {
  const TimeSettingsPage({Key? key}) : super(key: key);

  @override
  _TimeSettingsPageState createState() => _TimeSettingsPageState();
}

class _TimeSettingsPageState extends State<TimeSettingsPage> {
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // 直接返回，不恢复轮播，因为这只是返回到设置页面
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
                              // 直接返回，不恢复轮播
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
                          Spacer(),
                          IconButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const TimerDebugWidget(),
                                ),
                              );
                            },
                            icon: Icon(
                              Icons.bug_report,
                              color: Colors.orange.shade600,
                              size: 28,
                            ),
                            tooltip: '定时更新调试',
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
                                  if (settingsModel?.building != null) ...[
                                    SizedBox(height: 12),
                                    _buildInfoRow(
                                        '地区', settingsModel!.building.location),
                                    SizedBox(height: 12),
                                    _buildInfoRow(
                                        '建筑物', settingsModel!.building.name),
                                    SizedBox(height: 12),
                                    _buildInfoRow('iSmart ID',
                                        settingsModel!.building.ismartId),
                                    SizedBox(height: 12),
                                    _buildInfoRow('位置信息',
                                        settingsModel!.building.location),
                                  ],
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
                                      '${deviceSettings.arrearageUpdateDuration}分钟',
                                    ),
                                    SizedBox(height: 12),
                                    _buildTimeSettingRow(
                                      '通告更新间隔',
                                      '${deviceSettings.noticeUpdateDuration}分钟',
                                    ),
                                    SizedBox(height: 12),
                                    _buildTimeSettingRow(
                                      '广告更新间隔',
                                      '${deviceSettings.advertisementUpdateDuration}分钟',
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
                                    SizedBox(height: 12),
                                    _buildTimeSettingRow(
                                      '应用更新时间',
                                      '${deviceSettings.appUpdateDuration}秒',
                                    ),
                                    SizedBox(height: 12),
                                    _buildTimeSettingRow(
                                      '底部轮播时间',
                                      '${deviceSettings.bottomCarouselDuration}秒',
                                    ),
                                    SizedBox(height: 12),
                                    _buildTimeSettingRow(
                                      '付款表格一页显示时间',
                                      '${deviceSettings.paymentTableOnePageDuration}秒',
                                    ),
                                    SizedBox(height: 12),
                                    _buildTimeSettingRow(
                                      '正常到通告轮播转换时间',
                                      '${deviceSettings.normalToAnnouncementCarouselDuration}秒',
                                    ),
                                    SizedBox(height: 12),
                                    _buildTimeSettingRow(
                                      '通告轮播到全屏广告转换时间',
                                      '${deviceSettings.announcementCarouselToFullAdsCarouselDuration}秒',
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

                    // 在debug模式下显示定时更新调试窗口
                    if (kDebugMode) ...[
                      SizedBox(height: 24),
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.bug_report,
                                  color: Colors.blue.shade600,
                                  size: 24,
                                ),
                                SizedBox(width: 16),
                                Text(
                                  '定时更新调试信息',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 16),
                            // 调试窗口
                            const DebugUpdateTimeWidget(),
                          ],
                        ),
                      ),
                    ],
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
