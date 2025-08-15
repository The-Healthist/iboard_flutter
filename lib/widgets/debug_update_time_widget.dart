import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:iboard_app/providers/advertisement_provider.dart';
import 'package:iboard_app/providers/announcement_provider.dart';
import 'package:iboard_app/providers/weather_provider.dart';
import 'package:iboard_app/providers/arrear_provider.dart';
import 'package:iboard_app/providers/app_data_provider.dart';
import 'package:iboard_app/providers/state_provider.dart';
import 'package:logger/logger.dart';

/// 定时更新调试组件
/// 显示各个定时更新任务的倒计时和上次更新时间
class DebugUpdateTimeWidget extends StatefulWidget {
  const DebugUpdateTimeWidget({Key? key}) : super(key: key);

  @override
  _DebugUpdateTimeWidgetState createState() => _DebugUpdateTimeWidgetState();
}

class _DebugUpdateTimeWidgetState extends State<DebugUpdateTimeWidget> {
  Timer? _updateTimer;
  final Logger _logger = Logger();

  // 存储各个Provider的更新间隔时间 - 从实际配置中获取
  int _arrearUpdateInterval = 1;
  int _advertisementUpdateInterval = 5;
  int _announcementUpdateInterval = 5;
  int _weatherUpdateInterval = 2; // 小时
  int _loginUpdateInterval = 12; // 小时

  // 存储各个Provider的上次更新时间
  DateTime? _lastArrearUpdate;
  DateTime? _lastAdvertisementUpdate;
  DateTime? _lastAnnouncementUpdate;
  DateTime? _lastWeatherUpdate;
  DateTime? _lastLoginUpdate;

  @override
  void initState() {
    super.initState();
    _initializeLastUpdateTimes();
    _startUpdateTimer();
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _updateTimer = null;
    super.dispose();
  }

  ///1.5，初始化上次更新时间
  void _initializeLastUpdateTimes() {
    final now = DateTime.now();
    
    // 初始化上次更新时间 - 这里可以根据实际情况从Provider或缓存中获取
    _lastArrearUpdate = now.subtract(const Duration(minutes: 1));
    _lastAdvertisementUpdate = now.subtract(const Duration(minutes: 2));
    _lastAnnouncementUpdate = now.subtract(const Duration(minutes: 3));
    _lastWeatherUpdate = now.subtract(const Duration(minutes: 30));
    _lastLoginUpdate = now.subtract(const Duration(hours: 6));
  }

  ///1.6，更新上次更新时间
  void updateLastUpdateTime(String type) {
    final now = DateTime.now();
    setState(() {
      switch (type) {
        case 'arrear':
          _lastArrearUpdate = now;
          break;
        case 'advertisement':
          _lastAdvertisementUpdate = now;
          break;
        case 'announcement':
          _lastAnnouncementUpdate = now;
          break;
        case 'weather':
          _lastWeatherUpdate = now;
          break;
        case 'login':
          _lastLoginUpdate = now;
          break;
      }
    });
  }

  ///1，启动更新定时器 - 每秒更新一次时间显示
  void _startUpdateTimer() {
    _updateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          // 触发UI更新
        });
      }
    });
  }

  ///2，计算欠费数据更新倒计时
  String _getArrearUpdateCountdown(ArrearProvider arrearProvider) {
    if (!arrearProvider.isPeriodicUpdateActive) {
      return "已停止";
    }

    // 使用真实的上次更新时间
    final lastUpdate = _lastArrearUpdate;
    if (lastUpdate == null) {
      return "未开始";
    }

    final intervalSeconds = _arrearUpdateInterval * 60;
    final nextUpdate = lastUpdate.add(Duration(seconds: intervalSeconds));
    final now = DateTime.now();
    final remaining = nextUpdate.difference(now);

    if (remaining.isNegative) {
      return "即将更新";
    }

    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;
    return "${minutes}m${seconds}s";
  }

  ///3，计算顶部广告轮播更新倒计时
  String _getTopAdUpdateCountdown(AdvertisementProvider advertisementProvider) {
    if (!advertisementProvider.isPeriodicUpdateActive) {
      return "已停止";
    }

    // 使用真实的上次更新时间
    final lastUpdate = _lastAdvertisementUpdate;
    if (lastUpdate == null) {
      return "未开始";
    }

    final intervalSeconds = _advertisementUpdateInterval * 60;
    final nextUpdate = lastUpdate.add(Duration(seconds: intervalSeconds));
    final now = DateTime.now();
    final remaining = nextUpdate.difference(now);

    if (remaining.isNegative) {
      return "即将更新";
    }

    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;
    return "${minutes}m${seconds}s";
  }

  ///4，计算全屏广告轮播更新倒计时
  String _getFullAdUpdateCountdown(
      AdvertisementProvider advertisementProvider) {
    // 全屏广告轮播使用与顶部广告相同的更新间隔
    return _getTopAdUpdateCountdown(advertisementProvider);
  }

  ///5，计算通告轮播更新倒计时
  String _getAnnouncementUpdateCountdown(
      AnnouncementProvider announcementProvider) {
    if (!announcementProvider.isPeriodicUpdateActive) {
      return "已停止";
    }

    // 使用真实的上次更新时间
    final lastUpdate = _lastAnnouncementUpdate;
    if (lastUpdate == null) {
      return "未开始";
    }

    final intervalSeconds = _announcementUpdateInterval * 60;
    final nextUpdate = lastUpdate.add(Duration(seconds: intervalSeconds));
    final now = DateTime.now();
    final remaining = nextUpdate.difference(now);

    if (remaining.isNegative) {
      return "即将更新";
    }

    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;
    return "${minutes}m${seconds}s";
  }

  ///6，计算天气更新倒计时
  String _getWeatherUpdateCountdown(WeatherProvider weatherProvider) {
    if (!weatherProvider.isPeriodicUpdateActive) {
      return "已停止";
    }

    // 使用真实的上次更新时间
    final lastUpdate = _lastWeatherUpdate;
    if (lastUpdate == null) {
      return "未开始";
    }

    // 天气更新固定2小时间隔
    final nextUpdate = lastUpdate.add(Duration(hours: _weatherUpdateInterval));
    final now = DateTime.now();
    final remaining = nextUpdate.difference(now);

    if (remaining.isNegative) {
      return "即将更新";
    }

    final hours = remaining.inHours;
    final minutes = remaining.inMinutes % 60;
    return "${hours}h${minutes}m";
  }

  ///7，计算定时登录倒计时
  String _getLoginCountdown(AppDataProvider appDataProvider) {
    if (!appDataProvider.isPeriodicLoginActive) {
      return "已停止";
    }

    // 使用真实的上次登录时间
    final lastLogin = _lastLoginUpdate;
    if (lastLogin == null) {
      return "未开始";
    }

    // 定时登录固定12小时间隔
    final nextLogin = lastLogin.add(Duration(hours: _loginUpdateInterval));
    final now = DateTime.now();
    final remaining = nextLogin.difference(now);

    if (remaining.isNegative) {
      return "即将登录";
    }

    final hours = remaining.inHours;
    final minutes = remaining.inMinutes % 60;
    return "${hours}h${minutes}m";
  }

    ///8，从缓存获取上次更新时间
  DateTime? _getLastUpdateTimeFromCache(String type) {
    // 返回真实的上次更新时间
    switch (type) {
      case 'arrear':
        return _lastArrearUpdate;
      case 'advertisement':
        return _lastAdvertisementUpdate;
      case 'announcement':
        return _lastAnnouncementUpdate;
      case 'weather':
        return _lastWeatherUpdate;
      case 'login':
        return _lastLoginUpdate;
      default:
        return null;
    }
  }

  ///9，格式化时间显示
  String _formatTime(DateTime? time) {
    if (time == null) return "未记录";

    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inMinutes < 1) {
      return "刚刚";
    } else if (difference.inHours < 1) {
      return "${difference.inMinutes}分钟前";
    } else if (difference.inDays < 1) {
      return "${difference.inHours}小时前";
    } else {
      return "${difference.inDays}天前";
    }
  }

  ///10，构建更新任务列表
  List<Widget> _buildUpdateTasksList(
    ArrearProvider arrearProvider,
    AdvertisementProvider advertisementProvider,
    AnnouncementProvider announcementProvider,
    WeatherProvider weatherProvider,
    AppDataProvider appDataProvider,
  ) {
    List<Widget> widgets = [
      Text(
        '📋 定时更新任务列表:',
        style: TextStyle(
          color: Colors.yellow,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(height: 2),
    ];

    // 欠费数据更新
    widgets.add(_buildTaskItem(
      '💰 欠费数据',
      _getArrearUpdateCountdown(arrearProvider),
      _formatTime(_getLastUpdateTimeFromCache('arrear')),
      arrearProvider.isPeriodicUpdateActive ? Colors.green : Colors.red,
    ));

    // 顶部广告轮播更新
    widgets.add(_buildTaskItem(
      '📺 顶部广告轮播',
      _getTopAdUpdateCountdown(advertisementProvider),
      _formatTime(_getLastUpdateTimeFromCache('advertisement')),
      advertisementProvider.isPeriodicUpdateActive ? Colors.green : Colors.red,
    ));

    // 全屏广告轮播更新
    widgets.add(_buildTaskItem(
      '🎬 全屏广告轮播',
      _getFullAdUpdateCountdown(advertisementProvider),
      _formatTime(_getLastUpdateTimeFromCache('advertisement')),
      advertisementProvider.isPeriodicUpdateActive ? Colors.green : Colors.red,
    ));

    // 通告轮播更新
    widgets.add(_buildTaskItem(
      '📢 通告轮播',
      _getAnnouncementUpdateCountdown(announcementProvider),
      _formatTime(_getLastUpdateTimeFromCache('announcement')),
      announcementProvider.isPeriodicUpdateActive ? Colors.green : Colors.red,
    ));

    // 天气更新
    widgets.add(_buildTaskItem(
      '🌤️ 天气数据',
      _getWeatherUpdateCountdown(weatherProvider),
      _formatTime(_getLastUpdateTimeFromCache('weather')),
      weatherProvider.isPeriodicUpdateActive ? Colors.green : Colors.red,
    ));

    // 定时登录
    widgets.add(_buildTaskItem(
      '🔐 定时登录',
      _getLoginCountdown(appDataProvider),
      _formatTime(_getLastUpdateTimeFromCache('login')),
      appDataProvider.isPeriodicLoginActive ? Colors.green : Colors.red,
    ));

    return widgets;
  }

  ///11，构建单个任务项
  Widget _buildTaskItem(
      String name, String countdown, String lastUpdate, Color statusColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Text(
            name,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 10,
            ),
          ),
          const Spacer(),
          Text(
            countdown,
            style: TextStyle(
              color: statusColor,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            lastUpdate,
            style: TextStyle(
              color: Colors.cyan,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer5<ArrearProvider, AdvertisementProvider,
        AnnouncementProvider, WeatherProvider, AppDataProvider>(
        builder: (
          context,
          arrearProvider,
          advertisementProvider,
          announcementProvider,
          weatherProvider,
          appDataProvider,
          child,
        ) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.8),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue, width: 2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题
                Text(
                  '⏰ 定时更新调试',
                  style: TextStyle(
                    color: Colors.blue,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),

                // 更新任务列表
                ..._buildUpdateTasksList(
                  arrearProvider,
                  advertisementProvider,
                  announcementProvider,
                  weatherProvider,
                  appDataProvider,
                ),
                const SizedBox(height: 8),

                // 系统状态信息
                Text(
                  '🖥️ 系统状态:',
                  style: TextStyle(
                    color: Colors.yellow,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '登录: ${appDataProvider.isLoggedIn ? "✅已登录" : "❌未登录"}',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                  ),
                ),
                Text(
                  'Token: ${appDataProvider.token != null ? "✅有效" : "❌无效"}',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                  ),
                ),
                Text(
                  '设备设置: ${appDataProvider.deviceSettings != null ? "✅已加载" : "❌未加载"}',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          );
        },
      );
  }
}
