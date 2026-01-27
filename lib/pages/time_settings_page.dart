import 'package:flutter/material.dart';
import 'package:iboard_app/providers/app_data_provider.dart';
import 'package:iboard_app/providers/app_update_provider.dart'; // 导入更新Provider
import 'package:iboard_app/widgets/debug_timer_widget.dart';
import 'package:iboard_app/widgets/debug_update_time_widget.dart'; // 导入調試窗口

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

  @override
  void initState() {
    super.initState();
    // 🔧 優化：頁面初始化時嘗試加載緩存數據
    _loadCacheDataIfNeeded();
  }

  ///0，如果需要，加載緩存數據
  void _loadCacheDataIfNeeded() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final appDataProvider =
          Provider.of<AppDataProvider>(context, listen: false);

      // 如果當前沒有任何數據，嘗試從緩存加載
      if (appDataProvider.settingsModel == null &&
          appDataProvider.deviceSettings == null &&
          !appDataProvider.isLoading) {
        try {
          await appDataProvider.initializeFromCache();
        } catch (e) {
          // 靜默失敗，不影響用戶體驗
        }
      }
    });
  }

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

      // 🔧 優化：使用優化後的初始化方法，失敗時保持緩存數據
      await appDataProvider.initialize(deviceId: deviceId);

      if (!mounted) return;
      // 刷新成功提示
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('數據刷新成功'),
          backgroundColor: Colors.green.shade600,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      // 🔧 優化：刷新失敗時檢查是否有緩存數據可用
      if (!mounted) return;
      final appDataProvider =
          Provider.of<AppDataProvider>(context, listen: false);
      final hasCachedData = appDataProvider.settingsModel != null ||
          appDataProvider.deviceSettings != null;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(hasCachedData
              ? '網絡刷新失敗，當前顯示緩存數據: ${e.toString().length > 50 ? e.toString().substring(0, 50) + "..." : e.toString()}'
              : '刷新失敗: $e'),
          backgroundColor: hasCachedData
              ? Colors.orange.shade600 // 有緩存數據時用橙色
              : Colors.red.shade600, // 無緩存數據時用紅色
          duration: const Duration(seconds: 3),
        ),
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
        // 直接返回，不恢复轮播，因为这只是返回到設置頁面
        // PopScope handles the pop automatically
      },
      child: Consumer<AppDataProvider>(
        builder: (context, appDataProvider, child) {
          final isLoggedIn = appDataProvider.isLoggedIn;
          final deviceId = appDataProvider.deviceId;
          final settingsModel = appDataProvider.settingsModel;
          final deviceSettings = appDataProvider.deviceSettings;
          final error = appDataProvider.error;

          // 🔧 優化：檢查是否有緩存數據可用，即使登錄失敗
          final hasCachedData = settingsModel != null || deviceSettings != null;
          final shouldShowContent = isLoggedIn || hasCachedData;

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
                            tooltip: '手动刷新設備信息和設置',
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
                            tooltip: '定时更新調試',
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
                            // 設備基本信息卡片
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
                                      const Spacer(),
                                      // 🔧 新增：數據來源指示器
                                      _buildDataSourceIndicator(
                                          isLoggedIn, hasCachedData),
                                    ],
                                  ),
                                  const SizedBox(height: 24),
                                  _buildInfoRow('設備ID', deviceId ?? '未獲取'),
                                  const SizedBox(height: 12),
                                  _buildInfoRow(
                                    '登錄狀態',
                                    _getLoginStatusText(
                                        isLoggedIn, hasCachedData),
                                    _getLoginStatusColor(
                                        isLoggedIn, hasCachedData),
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

                            // 时间設置卡片 - 🔧 優化：基於緩存數據而非登錄狀態
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
                                      shouldShowContent
                                          ? '時間設定數據載入中...'
                                          : '無可用的設備配置數據\n請檢查網絡連接或聯系管理員',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.grey.shade600,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                    // 在debug模式下显示定时更新調試窗口
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
                                  '定时更新調試信息',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            // 調試窗口
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

  ///9, 獲取登錄狀態文本
  String _getLoginStatusText(bool isLoggedIn, bool hasCachedData) {
    if (isLoggedIn) {
      return '已登錄';
    } else if (hasCachedData) {
      return '離線模式（使用緩存數據）';
    } else {
      return '未登錄';
    }
  }

  ///10, 獲取登錄狀態顏色
  Color _getLoginStatusColor(bool isLoggedIn, bool hasCachedData) {
    if (isLoggedIn) {
      return Colors.green.shade700;
    } else if (hasCachedData) {
      return Colors.orange.shade600; // 橙色表示離線模式
    } else {
      return Colors.red.shade700;
    }
  }

  ///11, 構建數據來源指示器
  Widget _buildDataSourceIndicator(bool isLoggedIn, bool hasCachedData) {
    if (isLoggedIn) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.shade200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_done,
              size: 16,
              color: Colors.green.shade600,
            ),
            const SizedBox(width: 4),
            Text(
              '實時數據',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.green.shade700,
              ),
            ),
          ],
        ),
      );
    } else if (hasCachedData) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.offline_bolt,
              size: 16,
              color: Colors.orange.shade600,
            ),
            const SizedBox(width: 4),
            Text(
              '緩存數據',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.orange.shade700,
              ),
            ),
          ],
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off,
              size: 16,
              color: Colors.red.shade600,
            ),
            const SizedBox(width: 4),
            Text(
              '無數據',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.red.shade700,
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildInfoRow(String label, String value, [Color? valueColor]) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140, // 扩大宽度，与时间設置保持一致
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

  ///13. 构建版本信息卡片 - 参考設備信息样式
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
              // 标题行 - 与設備信息样式一致
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
                  // 檢查更新按钮
                  IconButton(
                    onPressed: updateProvider.canCheckUpdate
                        ? () async {
                            await updateProvider.checkForUpdate(
                                autoDownload: true);
                          }
                        : null, // 不满足条件时禁用按钮
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
                            color: updateProvider.canCheckUpdate
                                ? Colors.blue.shade600
                                : Colors.grey.shade400, // 禁用时显示灰色
                          ),
                    tooltip: updateProvider.canCheckUpdate
                        ? '檢查更新'
                        : '請稍後再試', // 禁用时显示不同提示
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
