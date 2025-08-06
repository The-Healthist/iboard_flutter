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
  Map<String, Map<String, dynamic>> _manualUpdateResults = {}; // 存储手动更新结果
  Set<String> _updatingTasks = {}; // 跟踪正在更新的任务

  @override
  void initState() {
    super.initState();
    _generateDebugInfo();
    _startPeriodicUpdate();
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _updateTimer = null;
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
      List<String> basicContent = [
        '当前时间: ${DateTime.now().toString().substring(0, 19)}',
        '设备ID: ${appDataProvider.deviceId ?? '未获取'}',
        '登录状态: ${appDataProvider.isLoggedIn ? '已登录' : '未登录'}',
        'Token状态: ${appDataProvider.token != null ? '有效' : '无效'}',
        '定时登录状态: ${appDataProvider.isPeriodicLoginActive ? '✅ 运行中' : '❌ 已停止'}',
        '定时登录间隔: 12小时',
        '健康检查状态: ${appDataProvider.isPeriodicHealthCheckActive ? '✅ 运行中' : '❌ 已停止'}',
        '健康检查间隔: 30分钟',
      ];

      // 添加最后一次健康检查信息
      if (appDataProvider.lastHealthCheckTime != null) {
        basicContent.addAll([
          '',
          '--- 最近一次健康检查结果 ---',
          '结果: ${appDataProvider.lastHealthCheckResult ?? '未知'}',
          '时间: ${appDataProvider.lastHealthCheckTime.toString().substring(11, 19)}',
        ]);
      }

      // 如果有手动登录的结果，添加到基本信息中
      final manualLoginResult = _manualUpdateResults['manual_login'];
      if (manualLoginResult != null) {
        basicContent.addAll([
          '',
          '--- 最近一次手动登录结果 ---',
          '状态: ${manualLoginResult['success'] ? '✅ 成功' : '❌ 失败'}',
          '信息: ${manualLoginResult['message']}',
          '耗时: ${manualLoginResult['duration']}ms',
          '时间: ${manualLoginResult['timestamp'].toString().substring(11, 19)}',
        ]);
        if (manualLoginResult['error'] != null) {
          basicContent.add('错误: ${manualLoginResult['error']}');
        }
      }

      _debugInfo.add({
        'title': '📊 定时更新基本信息',
        'content': basicContent,
        'manualUpdateButton': Column(
          children: [
            _buildManualUpdateButton('manual_login', '手动登录', _manualLogin),
            SizedBox(height: 8),
            _buildManualUpdateButton(
                'health_check', '健康检查', _manualHealthCheck),
          ],
        ),
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
      'manualUpdateButton': _buildManualUpdateButton(
          'advertisements', '广告', _manualUpdateAdvertisements),
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
      'manualUpdateButton': _buildManualUpdateButton(
          'announcements', '通告', _manualUpdateAnnouncements),
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
      'manualUpdateButton':
          _buildManualUpdateButton('weather', '天气', _manualUpdateWeather),
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
      'manualUpdateButton':
          _buildManualUpdateButton('arrears', '欠费', _manualUpdateArrears),
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
      'manualUpdateButton': _buildManualUpdateButton(
          'device_settings', '设备设置', _manualUpdateDeviceSettings),
    });
  }

  ///9，手动更新广告数据
  Future<void> _manualUpdateAdvertisements() async {
    if (_updatingTasks.contains('advertisements')) return;

    setState(() {
      _updatingTasks.add('advertisements');
    });

    // _logger.i('🎬 [手动更新] 开始手动更新广告数据');
    final startTime = DateTime.now();

    try {
      final advertisementProvider = context.read<AdvertisementProvider>();
      await advertisementProvider.fetchAdvertisements();

      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);

      _manualUpdateResults['advertisements'] = {
        'success': true,
        'message': '广告数据更新成功',
        'duration': duration.inMilliseconds,
        'timestamp': endTime,
        'data': {
          '广告总数': advertisementProvider.advertisements.length,
          '全屏广告数': advertisementProvider.fullAdvertisements.length,
          '顶部广告数': advertisementProvider.topAdvertisements.length,
        }
      };

      // _logger.i('🎬 [手动更新] 广告数据更新成功，耗时: ${duration.inMilliseconds}ms');
    } catch (e) {
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);

      _manualUpdateResults['advertisements'] = {
        'success': false,
        'message': '广告数据更新失败: $e',
        'duration': duration.inMilliseconds,
        'timestamp': endTime,
        'error': e.toString(),
      };

      _logger.e('🎬 [手动更新] 广告数据更新失败', error: e);
    } finally {
      setState(() {
        _updatingTasks.remove('advertisements');
      });
      _generateDebugInfo();
    }
  }

  ///10，手动更新通告数据
  Future<void> _manualUpdateAnnouncements() async {
    if (_updatingTasks.contains('announcements')) return;

    setState(() {
      _updatingTasks.add('announcements');
    });

    // _logger.i('📢 [手动更新] 开始手动更新通告数据');
    final startTime = DateTime.now();

    try {
      final announcementProvider = context.read<AnnouncementProvider>();
      await announcementProvider.fetchNotices();

      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);

      _manualUpdateResults['announcements'] = {
        'success': true,
        'message': '通告数据更新成功',
        'duration': duration.inMilliseconds,
        'timestamp': endTime,
        'data': {
          '通告总数': announcementProvider.announcements.length,
          '轮播通告数': announcementProvider.carouselAnnouncements.length,
        }
      };

      // _logger.i('📢 [手动更新] 通告数据更新成功，耗时: ${duration.inMilliseconds}ms');
    } catch (e) {
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);

      _manualUpdateResults['announcements'] = {
        'success': false,
        'message': '通告数据更新失败: $e',
        'duration': duration.inMilliseconds,
        'timestamp': endTime,
        'error': e.toString(),
      };

      _logger.e('📢 [手动更新] 通告数据更新失败', error: e);
    } finally {
      setState(() {
        _updatingTasks.remove('announcements');
      });
      _generateDebugInfo();
    }
  }

  ///11，手动更新天气数据
  Future<void> _manualUpdateWeather() async {
    if (_updatingTasks.contains('weather')) return;

    setState(() {
      _updatingTasks.add('weather');
    });

    // _logger.i('🌤️ [手动更新] 开始手动更新天气数据');
    final startTime = DateTime.now();

    try {
      final weatherProvider = context.read<WeatherProvider>();
      await Future.wait([
        weatherProvider.fetchWeatherForecast(),
        weatherProvider.fetchCurrentWeather(),
        weatherProvider.fetchWeatherWarnings(),
      ]);

      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);

      _manualUpdateResults['weather'] = {
        'success': true,
        'message': '天气数据更新成功',
        'duration': duration.inMilliseconds,
        'timestamp': endTime,
        'data': {
          '预报数据': weatherProvider.hasForecastData ? '✅' : '❌',
          '当前天气': weatherProvider.hasCurrentData ? '✅' : '❌',
          '天气警告': weatherProvider.hasWarningData ? '✅' : '❌',
        }
      };

      // _logger.i('🌤️ [手动更新] 天气数据更新成功，耗时: ${duration.inMilliseconds}ms');
    } catch (e) {
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);

      _manualUpdateResults['weather'] = {
        'success': false,
        'message': '天气数据更新失败: $e',
        'duration': duration.inMilliseconds,
        'timestamp': endTime,
        'error': e.toString(),
      };

      _logger.e('🌤️ [手动更新] 天气数据更新失败', error: e);
    } finally {
      setState(() {
        _updatingTasks.remove('weather');
      });
      _generateDebugInfo();
    }
  }

  ///12，手动更新欠费数据
  Future<void> _manualUpdateArrears() async {
    if (_updatingTasks.contains('arrears')) return;

    setState(() {
      _updatingTasks.add('arrears');
    });

    // _logger.i('💰 [手动更新] 开始手动更新欠费数据');
    final startTime = DateTime.now();

    try {
      final arrearProvider = context.read<ArrearProvider>();
      await arrearProvider.fetchArrears();

      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);

      _manualUpdateResults['arrears'] = {
        'success': true,
        'message': '欠费数据更新成功',
        'duration': duration.inMilliseconds,
        'timestamp': endTime,
        'data': {
          '记录总数': arrearProvider.rawArrearData.length,
          '楼宇数量': arrearProvider.buildings.length,
        }
      };

      // _logger.i('💰 [手动更新] 欠费数据更新成功，耗时: ${duration.inMilliseconds}ms');
    } catch (e) {
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);

      _manualUpdateResults['arrears'] = {
        'success': false,
        'message': '欠费数据更新失败: $e',
        'duration': duration.inMilliseconds,
        'timestamp': endTime,
        'error': e.toString(),
      };

      _logger.e('💰 [手动更新] 欠费数据更新失败', error: e);
    } finally {
      setState(() {
        _updatingTasks.remove('arrears');
      });
      _generateDebugInfo();
    }
  }

  ///13，手动更新设备设置
  Future<void> _manualUpdateDeviceSettings() async {
    if (_updatingTasks.contains('device_settings')) return;

    setState(() {
      _updatingTasks.add('device_settings');
    });

    // _logger.i('⚙️ [手动更新] 开始手动更新设备设置');
    final startTime = DateTime.now();

    try {
      final appDataProvider = context.read<AppDataProvider>();
      // 通过重新登录来更新设备设置
      await appDataProvider.initializeAndLogin();

      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);

      _manualUpdateResults['device_settings'] = {
        'success': true,
        'message': '设备设置更新成功',
        'duration': duration.inMilliseconds,
        'timestamp': endTime,
        'data': {
          '设置状态': appDataProvider.deviceSettings != null ? '✅ 已加载' : '❌ 未加载',
        }
      };

      // _logger.i('⚙️ [手动更新] 设备设置更新成功，耗时: ${duration.inMilliseconds}ms');
    } catch (e) {
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);

      _manualUpdateResults['device_settings'] = {
        'success': false,
        'message': '设备设置更新失败: $e',
        'duration': duration.inMilliseconds,
        'timestamp': endTime,
        'error': e.toString(),
      };

      _logger.e('⚙️ [手动更新] 设备设置更新失败', error: e);
    } finally {
      setState(() {
        _updatingTasks.remove('device_settings');
      });
      _generateDebugInfo();
    }
  }

  ///14，手动登录
  Future<void> _manualLogin() async {
    if (_updatingTasks.contains('manual_login')) return;

    setState(() {
      _updatingTasks.add('manual_login');
    });

    // _logger.i('🔑 [手动登录] 开始手动登录');
    final startTime = DateTime.now();

    try {
      final appDataProvider = context.read<AppDataProvider>();

      // 使用新的manualLogin方法，不会清除现有缓存数据
      await appDataProvider.manualLogin();

      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);

      _manualUpdateResults['manual_login'] = {
        'success': true,
        'message': '手动登录成功',
        'duration': duration.inMilliseconds,
        'timestamp': endTime,
        'data': {
          '登录状态': appDataProvider.isLoggedIn ? '✅ 已登录' : '❌ 未登录',
          'Token状态': appDataProvider.token != null ? '✅ 有效' : '❌ 无效',
          '设备设置': appDataProvider.deviceSettings != null ? '✅ 已加载' : '❌ 未加载',
          '设备ID': appDataProvider.deviceId ?? '未获取',
        }
      };

      // _logger.i('🔑 [手动登录] 手动登录成功，耗时: ${duration.inMilliseconds}ms');
    } catch (e) {
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);

      final appDataProvider = context.read<AppDataProvider>();
      _manualUpdateResults['manual_login'] = {
        'success': false,
        'message': '手动登录失败: $e',
        'duration': duration.inMilliseconds,
        'timestamp': endTime,
        'error': e.toString(),
        'data': {
          '登录状态': appDataProvider.isLoggedIn ? '✅ 已登录' : '❌ 未登录',
          'Token状态': appDataProvider.token != null ? '✅ 有效' : '❌ 无效',
          '设备设置': appDataProvider.deviceSettings != null ? '✅ 已加载' : '❌ 未加载',
          '设备ID': appDataProvider.deviceId ?? '未获取',
        }
      };

      _logger.e('🔑 [手动登录] 手动登录失败', error: e);
    } finally {
      setState(() {
        _updatingTasks.remove('manual_login');
      });
      _generateDebugInfo();
    }
  }

  ///15，手动执行健康检查
  Future<void> _manualHealthCheck() async {
    if (_updatingTasks.contains('health_check')) return;

    setState(() {
      _updatingTasks.add('health_check');
    });

    // _logger.i('🏥 [手动健康检查] 开始手动执行健康检查');
    final startTime = DateTime.now();

    try {
      final appDataProvider = context.read<AppDataProvider>();
      await appDataProvider.performHealthCheck();

      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);

      _manualUpdateResults['health_check'] = {
        'success': true,
        'message': '健康检查执行成功',
        'duration': duration.inMilliseconds,
        'timestamp': endTime,
        'data': {
          '检查结果': appDataProvider.lastHealthCheckResult ?? '未知',
        }
      };

      // _logger.i('🏥 [手动健康检查] 健康检查执行成功，耗时: ${duration.inMilliseconds}ms');
    } catch (e) {
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);

      _manualUpdateResults['health_check'] = {
        'success': false,
        'message': '健康检查执行失败: $e',
        'duration': duration.inMilliseconds,
        'timestamp': endTime,
        'error': e.toString(),
      };

      _logger.e('🏥 [手动健康检查] 健康检查执行失败', error: e);
    } finally {
      setState(() {
        _updatingTasks.remove('health_check');
      });
      _generateDebugInfo();
    }
  }

  ///16，构建手动更新按钮
  Widget _buildManualUpdateButton(
      String taskKey, String label, VoidCallback onPressed) {
    final isUpdating = _updatingTasks.contains(taskKey);
    final result = _manualUpdateResults[taskKey];

    return Container(
      margin: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ElevatedButton.icon(
            onPressed: isUpdating ? null : onPressed,
            icon: isUpdating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh, size: 16),
            label: Text(isUpdating ? '更新中...' : '手动更新$label'),
            style: ElevatedButton.styleFrom(
              backgroundColor: isUpdating
                  ? Colors.grey.shade300
                  : (result?['success'] == true ? Colors.green : Colors.blue),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              textStyle: const TextStyle(fontSize: 12),
            ),
          ),
          if (result != null) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: result['success']
                    ? Colors.green.shade50
                    : Colors.red.shade50,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: result['success']
                      ? Colors.green.shade300
                      : Colors.red.shade300,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result['message'],
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: result['success']
                          ? Colors.green.shade800
                          : Colors.red.shade800,
                    ),
                  ),
                  Text(
                    '耗时: ${result['duration']}ms | ${result['timestamp'].toString().substring(11, 19)}',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  if (result['data'] != null) ...[
                    const SizedBox(height: 4),
                    ...((result['data'] as Map<String, dynamic>).entries.map(
                          (entry) => Text(
                            '${entry.key}: ${entry.value}',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        )),
                  ],
                  if (result['error'] != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '错误详情: ${result['error']}',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.red.shade600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
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
          IconButton(
            icon: _updatingTasks.contains('manual_login')
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.login),
            onPressed:
                _updatingTasks.contains('manual_login') ? null : _manualLogin,
            tooltip: '手动登录',
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
                          children: [
                            // 显示调试信息内容
                            ...(info['content'] as List<String>)
                                .map((line) => Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: SelectableText(
                                        line,
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    ))
                                .toList(),
                            // 显示手动更新按钮（如果有的话）
                            if (info['manualUpdateButton'] != null)
                              info['manualUpdateButton'] as Widget,
                          ],
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
