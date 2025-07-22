import 'package:flutter/material.dart';
import 'package:iboard_app/providers/app_data_provider.dart';
import 'package:iboard_app/providers/state_provider.dart';
import 'package:provider/provider.dart';

class TimeSettingsPage extends StatelessWidget {
  const TimeSettingsPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<AppDataProvider>(
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
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        Icons.devices,
                                        size: 30,
                                        color: Colors.blue.shade600,
                                      ),
                                    ),
                                    SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '設備基本資訊',
                                            style: TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.grey.shade800,
                                            ),
                                          ),
                                          SizedBox(height: 4),
                                          Text(
                                            hasDeviceId ? '已初始化' : '未初始化',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: hasDeviceId
                                                  ? Colors.green.shade700
                                                  : Colors.orange.shade700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 20),
                                Divider(height: 1, color: Colors.grey.shade200),
                                SizedBox(height: 20),
                                if (hasDeviceId) ...[
                                  _buildInfoRow('設備ID', deviceId!),
                                  SizedBox(height: 16),
                                  _buildInfoRow(
                                    '登錄狀態',
                                    isLoggedIn ? '已登錄' : '未登錄',
                                    isLoggedIn ? Colors.green : Colors.orange,
                                  ),
                                  if (isLoggedIn && settingsModel != null) ...[
                                    SizedBox(height: 16),
                                    _buildInfoRow(
                                        '建築名稱', settingsModel.building.name),
                                    SizedBox(height: 16),
                                    _buildInfoRow('建築ID',
                                        settingsModel.building.ismartId),
                                    SizedBox(height: 16),
                                    _buildInfoRow(
                                        '位置', settingsModel.building.location),
                                  ],
                                ] else ...[
                                  Text(
                                    '設備尚未初始化',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],

                                // 错误信息显示（如果有）
                                if (error != null) ...[
                                  SizedBox(height: 20),
                                  Container(
                                    padding: EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: Colors.red.shade200),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.error_outline,
                                          color: Colors.red.shade700,
                                          size: 20,
                                        ),
                                        SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            error,
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.red.shade700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),

                          SizedBox(height: 20),

                          // 时间设置信息卡片
                          if (isLoggedIn && deviceSettings != null)
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
                                              BorderRadius.circular(12),
                                        ),
                                        child: Icon(
                                          Icons.schedule,
                                          size: 30,
                                          color: Colors.blue.shade600,
                                        ),
                                      ),
                                      SizedBox(width: 16),
                                      Expanded(
                                        child: Text(
                                          '時間參數設定',
                                          style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.grey.shade800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 20),
                                  Divider(
                                      height: 1, color: Colors.grey.shade200),
                                  SizedBox(height: 20),

                                  // 参数说明
                                  Container(
                                    padding: EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.info_outline,
                                          color: Colors.blue.shade700,
                                        ),
                                        SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            '這些參數由管理員設置，不可在此修改',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.blue.shade700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  SizedBox(height: 20),

                                  // 时间参数列表
                                  _buildTimeSettingRow('拖欠數據更新時間',
                                      '${deviceSettings.arrearageUpdateDuration} 秒'),
                                  SizedBox(height: 16),
                                  _buildTimeSettingRow('通知更新時間',
                                      '${deviceSettings.noticeUpdateDuration} 秒'),
                                  SizedBox(height: 16),
                                  _buildTimeSettingRow('廣告更新時間',
                                      '${deviceSettings.advertisementUpdateDuration} 秒'),
                                  SizedBox(height: 16),
                                  _buildTimeSettingRow('廣告播放時間',
                                      '${deviceSettings.advertisementPlayDuration} 秒'),
                                  SizedBox(height: 16),
                                  _buildTimeSettingRow('通知播放時間',
                                      '${deviceSettings.noticePlayDuration} 秒'),
                                  SizedBox(height: 16),
                                  _buildTimeSettingRow('備用時間（手動操作超時）',
                                      '${deviceSettings.spareDuration} 秒'),
                                  SizedBox(height: 16),
                                  _buildTimeSettingRow('通知停留時間（無操作超時）',
                                      '${deviceSettings.noticeStayDuration} 秒'),

                                  // 显示实际应用的计时器配置
                                  SizedBox(height: 20),
                                  Divider(
                                      height: 1, color: Colors.grey.shade200),
                                  SizedBox(height: 20),
                                  Consumer<CarouselStateProvider>(
                                    builder:
                                        (context, carouselProvider, child) {
                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '實際應用的計時器配置',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.blue.shade700,
                                            ),
                                          ),
                                          SizedBox(height: 12),
                                          _buildTimeSettingRow('全屏廣告播放時間',
                                              '${carouselProvider.fullscreenAdDuration} 秒'),
                                          SizedBox(height: 12),
                                          _buildTimeSettingRow('手動操作超時時間',
                                              '${carouselProvider.manualOperationTimeout} 秒'),
                                          SizedBox(height: 12),
                                          _buildTimeSettingRow('無操作進入廣告時間',
                                              '${carouselProvider.noActivityTimeout} 秒'),
                                          SizedBox(height: 12),
                                          _buildTimeSettingRow('公告播放時間',
                                              '${carouselProvider.noticeStayDuration} 秒'),
                                        ],
                                      );
                                    },
                                  ),
                                ],
                              ),
                            )
                          else
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
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
