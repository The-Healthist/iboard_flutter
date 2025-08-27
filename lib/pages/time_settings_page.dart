import 'package:flutter/material.dart';
import 'package:iboard_app/providers/app_data_provider.dart';
import 'package:iboard_app/providers/app_update_provider.dart'; // 导入更新Provider
import 'package:iboard_app/widgets/debug_timer_widget.dart';
import 'package:iboard_app/widgets/debug_update_time_widget.dart'; // 导入调试窗口

import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart'; // 导入kDebugMode
import 'package:shared_preferences/shared_preferences.dart';

class TimeSettingsPage extends StatefulWidget {
  const TimeSettingsPage({super.key});

  @override
  TimeSettingsPageState createState() => TimeSettingsPageState();
}

class TimeSettingsPageState extends State<TimeSettingsPage> {
  bool _isLoading = false;

  Future<void> _refreshData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      if (!mounted) return;
      final appDataProvider =
          Provider.of<AppDataProvider>(context, listen: false);
      final prefs = await SharedPreferences.getInstance();
      final deviceId = prefs.getString('deviceId');
      await appDataProvider.initialize(deviceId: deviceId);
    } catch (e) {
      // 處理錯誤，例如顯示SnackBar
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('刷新失敗: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvoked: (didPop) {
        // 直接返回，不恢复轮播，因为这只是返回到设置页面
        // PopScope handles the pop automatically
      },
      child: Consumer<AppDataProvider>(
        builder: (context, appDataProvider, child) {
          final isLoggedIn = appDataProvider.isLoggedIn;
          final deviceId = appDataProvider.deviceId;
          final settingsModel = appDataProvider.settingsModel;
          final deviceSettings = appDataProvider.deviceSettings;
          final error = appDataProvider.error;

          return Scaffold(
            backgroundColor: Colors.grey.shade50,
            body: SizedBox(
              width: double.infinity,
              height: double.infinity,
              child: SafeArea(
                child: Column(
                  children: [
                    // 顶部标题区域
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.05),
                            spreadRadius: 1,
                            blurRadius: 3,
                            offset: const Offset(0, 2),
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
                            icon: const Icon(Icons.arrow_back, size: 28),
                          ),
                          const SizedBox(width: 16),
                          Icon(
                            Icons.schedule,
                            size: 32,
                            color: Colors.blue.shade600,
                          ),
                          const SizedBox(width: 16),
                          Text(
                            '時間設定',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade800,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: _isLoading ? null : _refreshData,
                            icon: _isLoading
                                ? SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.blue.shade600,
                                    ),
                                  )
                                : Icon(
                                    Icons.refresh,
                                    color: Colors.blue.shade600,
                                    size: 28,
                                  ),
                            tooltip: '手动刷新设备信息和设置',
                          ),
                          const SizedBox(width: 8), // 添加间距
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
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 设备基本信息卡片
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(top: 8),
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.grey.withOpacity(0.05),
                                    spreadRadius: 1,
                                    blurRadius: 3,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
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
                                      const SizedBox(width: 16),
                                      Text(
                                        '設備信息',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey.shade800,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 24),
                                  _buildInfoRow('設備ID', deviceId ?? '未获取'),
                                  const SizedBox(height: 12),
                                  _buildInfoRow(
                                    '登錄狀態',
                                    isLoggedIn ? '已登錄' : '未登錄',
                                    isLoggedIn
                                        ? Colors.green.shade700
                                        : Colors.red.shade700,
                                  ),
                                  if (settingsModel?.building != null) ...[
                                    const SizedBox(height: 12),
                                    _buildInfoRow(
                                        '地區', settingsModel!.building.location),
                                    const SizedBox(height: 12),
                                    _buildInfoRow(
                                        '建築物', settingsModel.building.name),
                                    const SizedBox(height: 12),
                                    _buildInfoRow('iSmart ID',
                                        settingsModel.building.ismartId),
                                    const SizedBox(height: 12),
                                    _buildInfoRow('位置信息',
                                        settingsModel.building.location),
                                  ],
                                  if (error != null) ...[
                                    const SizedBox(height: 12),
                                    _buildInfoRow(
                                        '錯誤信息', error, Colors.red.shade700),
                                  ],
                                ],
                              ),
                            ),

                            // 版本信息卡片
                            const SizedBox(height: 24),
                            _buildVersionInfoCard(context),

                            // 时间设置卡片
                            if (deviceSettings != null) ...[
                              const SizedBox(height: 24),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.grey.withOpacity(0.05),
                                      spreadRadius: 1,
                                      blurRadius: 3,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(10),
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
                                        const SizedBox(width: 16),
                                        Text(
                                          '時間設置',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.grey.shade800,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 24),
                                    _buildTimeSettingRow(
                                      '欠費更新間隔',
                                      '${deviceSettings.arrearageUpdateDuration}分鐘',
                                    ),
                                    const SizedBox(height: 12),
                                    _buildTimeSettingRow(
                                      '通告更新間隔',
                                      '${deviceSettings.noticeUpdateDuration}分鐘',
                                    ),
                                    const SizedBox(height: 12),
                                    _buildTimeSettingRow(
                                      '廣告更新間隔',
                                      '${deviceSettings.advertisementUpdateDuration}分鐘',
                                    ),
                                    const SizedBox(height: 12),
                                    _buildTimeSettingRow(
                                      '廣告播放時長',
                                      '${deviceSettings.advertisementPlayDuration}秒',
                                    ),
                                    const SizedBox(height: 12),
                                    _buildTimeSettingRow(
                                      '通告播放時長',
                                      '${deviceSettings.noticePlayDuration}秒',
                                    ),
                                    const SizedBox(height: 12),
                                    _buildTimeSettingRow(
                                      '空閒時長',
                                      '${deviceSettings.spareDuration}秒',
                                    ),
                                    const SizedBox(height: 12),
                                    _buildTimeSettingRow(
                                      '通告停留時長',
                                      '${deviceSettings.noticeStayDuration}秒',
                                    ),
                                    const SizedBox(height: 12),
                                    _buildTimeSettingRow(
                                      '應用更新時間',
                                      '${deviceSettings.appUpdateDuration}秒',
                                    ),
                                    const SizedBox(height: 12),
                                    _buildTimeSettingRow(
                                      '底部輪播時間',
                                      '${deviceSettings.bottomCarouselDuration}秒',
                                    ),
                                    const SizedBox(height: 12),
                                    _buildTimeSettingRow(
                                      '付款表格一頁顯示',
                                      '${deviceSettings.paymentTableOnePageDuration}秒',
                                    ),
                                    const SizedBox(height: 12),
                                    _buildTimeSettingRow(
                                      '正常到通告轉換',
                                      '${deviceSettings.normalToAnnouncementCarouselDuration}秒',
                                    ),
                                    const SizedBox(height: 12),
                                    _buildTimeSettingRow(
                                      '通告到廣告轉換',
                                      '${deviceSettings.announcementCarouselToFullAdsCarouselDuration}秒',
                                    ),
                                  ],
                                ),
                              ),
                            ] else ...[
                              const SizedBox(height: 24),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.grey.withOpacity(0.05),
                                      spreadRadius: 1,
                                      blurRadius: 3,
                                      offset: const Offset(0, 2),
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
                                    const SizedBox(height: 16),
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
                      const SizedBox(height: 24),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
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
                                const SizedBox(width: 16),
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
                            const SizedBox(height: 16),
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
        SizedBox(
          width: 140, // 扩大宽度，与时间设置保持一致
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
        SizedBox(
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

  ///13. 构建版本信息卡片 - 参考设备信息样式
  Widget _buildVersionInfoCard(BuildContext context) {
    return Consumer<AppUpdateProvider>(
      builder: (context, updateProvider, child) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.05),
                spreadRadius: 1,
                blurRadius: 3,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题行 - 与设备信息样式一致
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.system_update,
                      color: Colors.green.shade600,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      '版本信息',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ),
                  // 检查更新按钮
                  IconButton(
                    onPressed: updateProvider.isCheckingUpdate
                        ? null
                        : () async {
                            await updateProvider.checkForUpdate(
                                autoDownload: true);
                          },
                    icon: updateProvider.isCheckingUpdate
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.blue.shade600),
                            ),
                          )
                        : Icon(
                            Icons.refresh,
                            color: Colors.blue.shade600,
                          ),
                    tooltip: '檢查更新',
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // 当前版本信息 - 使用统一的行样式
              _buildInfoRow('當前版本', updateProvider.currentVersion ?? '獲取中...'),

              // 最新版本信息
              if (updateProvider.hasUpdate) ...[
                const SizedBox(height: 12),
                _buildInfoRow('最新版本', updateProvider.remoteVersion ?? '未知',
                    Colors.green.shade700),
              ],

              // APK下载状态
              if (updateProvider.hasUpdate) ...[
                const SizedBox(height: 12),
                _buildInfoRow(
                    'APK狀態',
                    updateProvider.hasLocalApk ? '下載成功' : '未下載',
                    updateProvider.hasLocalApk
                        ? Colors.green.shade700
                        : Colors.orange.shade600),
              ],

              // 更新描述
              if (updateProvider.updateDescription != null) ...[
                const SizedBox(height: 12),
                _buildInfoRow('更新內容', updateProvider.updateDescription!),
              ],

              // 错误信息
              if (updateProvider.error != null) ...[
                const SizedBox(height: 12),
                _buildInfoRow(
                    '錯誤信息', updateProvider.error!, Colors.red.shade700),
              ],

              // 状态提示
              if (updateProvider.currentVersion != null) ...[
                const SizedBox(height: 20),
                if (updateProvider.hasUpdate && updateProvider.hasLocalApk) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.download_done,
                          color: Colors.blue.shade600,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '新版本已下載到應用緩存，請到設置頁面進行更新',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.blue.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (!updateProvider.hasUpdate) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: Colors.green.shade600,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '當前已是最新版本',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}
