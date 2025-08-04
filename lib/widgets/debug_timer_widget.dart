import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:iboard_app/providers/advertisement_provider.dart';
import 'package:iboard_app/providers/announcement_provider.dart';
import 'package:iboard_app/providers/weather_provider.dart';
import 'package:iboard_app/providers/arrear_provider.dart';
import 'package:iboard_app/providers/state_provider.dart';
import 'package:iboard_app/providers/announcement_carousel_provider.dart';
import 'package:iboard_app/providers/bottom_weather_qrcode_carousel_provider.dart';
import 'package:iboard_app/providers/app_data_provider.dart';
import 'package:logger/logger.dart';
import 'dart:async';

class TimerDebugWidget extends StatefulWidget {
  const TimerDebugWidget({Key? key}) : super(key: key);

  @override
  State<TimerDebugWidget> createState() => _TimerDebugWidgetState();
}

class _TimerDebugWidgetState extends State<TimerDebugWidget> {
  final Logger _logger = Logger();
  Timer? _updateTimer;
  List<Map<String, dynamic>> _debugInfo = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _generateDebugInfo();
    _startPeriodicUpdate();
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  ///1，启动定时更新调试信息
  void _startPeriodicUpdate() {
    _updateTimer?.cancel();
    _updateTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted) {
        _generateDebugInfo();
      } else {
        timer.cancel();
      }
    });
  }

  ///2，生成调试信息
  Future<void> _generateDebugInfo() async {
    setState(() {
      _isLoading = true;
      _debugInfo.clear();
    });

    try {
      // 获取所有Provider实例
      final advertisementProvider = context.read<AdvertisementProvider>();
      final announcementProvider = context.read<AnnouncementProvider>();
      final weatherProvider = context.read<WeatherProvider>();
      final arrearProvider = context.read<ArrearProvider>();
      final carouselStateProvider = context.read<CarouselStateProvider>();
      final announcementCarouselProvider =
          context.read<AnnouncementCarouselProvider>();
      final bottomCarouselProvider =
          context.read<BottomWeatherQrcodeCarouselProvider>();
      final appDataProvider = context.read<AppDataProvider>();

      // 基本信息
      _debugInfo.add({
        'title': '📊 定时更新基本信息',
        'content': [
          '当前时间: ${DateTime.now().toString().substring(0, 19)}',
          '设备ID: ${appDataProvider.deviceId ?? '未获取'}',
          '登录状态: ${appDataProvider.isLoggedIn ? '已登录' : '未登录'}',
          'Token状态: ${appDataProvider.token != null ? '有效' : '无效'}',
          '定时登录状态: ${appDataProvider.isPeriodicLoginActive ? '✅ 运行中' : '❌ 已停止'}',
          '定时登录间隔: 12小时',
        ]
      });

      // 广告定时更新状态
      await _checkAdvertisementTimer(advertisementProvider, appDataProvider);

      // 通告定时更新状态
      await _checkAnnouncementTimer(announcementProvider, appDataProvider);

      // 天气定时更新状态
      await _checkWeatherTimer(weatherProvider);

      // 欠费数据状态
      await _checkArrearStatus(arrearProvider, appDataProvider);

      // 轮播状态管理
      await _checkCarouselState(carouselStateProvider,
          announcementCarouselProvider, bottomCarouselProvider);

      // 设备设置信息
      await _checkDeviceSettings(appDataProvider);
    } catch (e) {
      _logger.e('生成调试信息时发生错误', error: e);
      _debugInfo.add({
        'title': '❌ 调试信息生成错误',
        'content': ['错误: $e'],
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  ///3，检查广告定时更新状态
  Future<void> _checkAdvertisementTimer(
      AdvertisementProvider provider, AppDataProvider appDataProvider) async {
    final deviceSettings = appDataProvider.deviceSettings;
    final updateInterval = deviceSettings?.advertisementUpdateDuration ?? 5;

    List<String> content = [];
    content
        .add('定时更新状态: ${provider.isPeriodicUpdateActive ? '✅ 运行中' : '❌ 已停止'}');
    content.add('更新间隔: ${updateInterval}分钟 (${updateInterval * 60}秒)');
    content.add('设备设置状态: ${deviceSettings != null ? '✅ 已加载' : '❌ 未加载'}');
    content.add('登录状态: ${appDataProvider.isLoggedIn ? '✅ 已登录' : '❌ 未登录'}');
    content.add('广告总数: ${provider.advertisements.length}');
    content.add('全屏广告数: ${provider.fullAdvertisements.length}');
    content.add('顶部广告数: ${provider.topAdvertisements.length}');

    if (provider.error != null) {
      content.add('错误信息: ${provider.error}');
    }

    _debugInfo.add({
      'title': '🎬 广告定时更新状态',
      'content': content,
    });
  }

  ///4，检查通告定时更新状态
  Future<void> _checkAnnouncementTimer(
      AnnouncementProvider provider, AppDataProvider appDataProvider) async {
    final deviceSettings = appDataProvider.deviceSettings;
    final updateInterval = deviceSettings?.noticeUpdateDuration ?? 5;

    List<String> content = [];
    content
        .add('定时更新状态: ${provider.isPeriodicUpdateActive ? '✅ 运行中' : '❌ 已停止'}');
    content.add('更新间隔: ${updateInterval}分钟 (${updateInterval * 60}秒)');
    content.add('设备设置状态: ${deviceSettings != null ? '✅ 已加载' : '❌ 未加载'}');
    content.add('登录状态: ${appDataProvider.isLoggedIn ? '✅ 已登录' : '❌ 未登录'}');
    content.add('通告总数: ${provider.announcements.length}');
    content.add('轮播通告数: ${provider.carouselAnnouncements.length}');
    content.add('播放时长: ${deviceSettings?.noticePlayDuration ?? 5}秒');
    content.add('停留时长: ${deviceSettings?.noticeStayDuration ?? 3}秒');

    if (provider.error != null) {
      content.add('错误信息: ${provider.error}');
    }

    _debugInfo.add({
      'title': '📢 通告定时更新状态',
      'content': content,
    });
  }

  ///5，检查天气定时更新状态
  Future<void> _checkWeatherTimer(WeatherProvider provider) async {
    List<String> content = [];
    content
        .add('定时更新状态: ${provider.isPeriodicUpdateActive ? '✅ 运行中' : '❌ 已停止'}');
    content.add('更新间隔: 2小时 (7200秒)');
    content.add('天气预报数据: ${provider.hasForecastData ? '✅ 有数据' : '❌ 无数据'}');
    content.add('当前天气数据: ${provider.hasCurrentData ? '✅ 有数据' : '❌ 无数据'}');
    content.add('天气警告数据: ${provider.hasWarningData ? '✅ 有数据' : '❌ 无数据'}');

    if (provider.forecastError != null) {
      content.add('预报错误: ${provider.forecastError}');
    }
    if (provider.currentError != null) {
      content.add('当前天气错误: ${provider.currentError}');
    }
    if (provider.warningError != null) {
      content.add('警告错误: ${provider.warningError}');
    }

    _debugInfo.add({
      'title': '🌤️ 天气定时更新状态',
      'content': content,
    });
  }

  ///6，检查欠费数据状态
  Future<void> _checkArrearStatus(
      ArrearProvider provider, AppDataProvider appDataProvider) async {
    final deviceSettings = appDataProvider.deviceSettings;
    final updateInterval = deviceSettings?.arrearageUpdateDuration ?? 1;

    List<String> content = [];
    content
        .add('定时更新状态: ${provider.isPeriodicUpdateActive ? '✅ 运行中' : '❌ 已停止'}');
    content.add('更新间隔: ${updateInterval}分钟 (${updateInterval * 60}秒)');
    content.add('数据状态: ${provider.hasData ? '✅ 有数据' : '❌ 无数据'}');
    content.add('记录总数: ${provider.rawArrearData.length}');
    content.add('楼宇数量: ${provider.buildings.length}');
    content.add('选中楼宇: ${provider.selectedBuildingId ?? '未选择'}');
    content.add('选中单元: ${provider.selectedUnit ?? '未选择'}');

    if (provider.error != null) {
      content.add('错误信息: ${provider.error}');
    }

    // 检查缓存状态
    final cacheStatus = await provider.getCacheStatus();
    content.add('缓存状态: ${cacheStatus['hasCache'] ? '✅ 有缓存' : '❌ 无缓存'}');
    if (cacheStatus['lastUpdate'] != null) {
      content.add('最后更新: ${cacheStatus['lastUpdate']}');
    }

    _debugInfo.add({
      'title': '💰 欠费数据状态',
      'content': content,
    });
  }

  ///7，检查轮播状态管理
  Future<void> _checkCarouselState(
    CarouselStateProvider carouselStateProvider,
    AnnouncementCarouselProvider announcementCarouselProvider,
    BottomWeatherQrcodeCarouselProvider bottomCarouselProvider,
  ) async {
    List<String> content = [];

    // 应用状态
    content.add('当前应用状态: ${carouselStateProvider.currentAppState.name}');
    content.add('全屏广告时长: ${carouselStateProvider.fullscreenAdDuration}秒');
    content.add('手动操作超时: ${carouselStateProvider.manualOperationTimeout}秒');
    content.add('空闲时长: ${carouselStateProvider.noActivityTimeout}秒');

    // 通告轮播状态
    content.add(
        '通告轮播状态: ${announcementCarouselProvider.isMidCarouselPaused ? '⏸️ 已暂停' : '▶️ 运行中'}');
    content.add(
        '通告轮播数量: ${announcementCarouselProvider.carouselAnnouncements.length}');
    content.add('当前通告索引: ${announcementCarouselProvider.currentNoticeIndex}');

    // 底部轮播状态
    content.add(
        '底部轮播状态: ${bottomCarouselProvider.isBottomCarouselPaused ? '⏸️ 已暂停' : '▶️ 运行中'}');
    content.add('当前显示: ${bottomCarouselProvider.showWeather ? '天气' : '二维码'}');

    _debugInfo.add({
      'title': '🔄 轮播状态管理',
      'content': content,
    });
  }

  ///8，检查设备设置信息
  Future<void> _checkDeviceSettings(AppDataProvider appDataProvider) async {
    final deviceSettings = appDataProvider.deviceSettings;

    if (deviceSettings == null) {
      _debugInfo.add({
        'title': '⚙️ 设备设置信息',
        'content': ['❌ 设备设置未加载'],
      });
      return;
    }

    List<String> content = [];
    content.add('欠费更新间隔: ${deviceSettings.arrearageUpdateDuration}分钟');
    content.add('通告更新间隔: ${deviceSettings.noticeUpdateDuration}分钟');
    content.add('广告更新间隔: ${deviceSettings.advertisementUpdateDuration}分钟');
    content.add('广告播放时长: ${deviceSettings.advertisementPlayDuration}秒');
    content.add('通告播放时长: ${deviceSettings.noticePlayDuration}秒');
    content.add('空闲时长: ${deviceSettings.spareDuration}秒');
    content.add('通告停留时长: ${deviceSettings.noticeStayDuration}秒');

    _debugInfo.add({
      'title': '⚙️ 设备设置信息',
      'content': content,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('定时更新调试信息'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _generateDebugInfo,
            tooltip: '刷新调试信息',
          ),
          IconButton(
            icon: const Icon(Icons.play_arrow),
            onPressed: () {
              final advertisementProvider =
                  context.read<AdvertisementProvider>();
              final announcementProvider = context.read<AnnouncementProvider>();
              final appDataProvider = context.read<AppDataProvider>();

              if (appDataProvider.isLoggedIn) {
                advertisementProvider.startPeriodicUpdate();
                announcementProvider.startPeriodicUpdate();
                _generateDebugInfo();
              }
            },
            tooltip: '手动启动定时更新',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _debugInfo.length,
              itemBuilder: (context, index) {
                final info = _debugInfo[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: ExpansionTile(
                    title: Text(
                      info['title'],
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: (info['content'] as List<String>)
                              .map((line) => Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: SelectableText(
                                      line,
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ))
                              .toList(),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
