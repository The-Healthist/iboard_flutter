import 'package:flutter/material.dart';
import 'package:iboard_app/pages/main_page.dart';
import 'package:iboard_app/providers/advertisement_provider.dart';
import 'package:iboard_app/providers/announcement_provider.dart';
import 'package:iboard_app/providers/announcement_carousel_provider.dart';
import 'package:iboard_app/providers/app_data_provider.dart';
import 'package:iboard_app/providers/state_provider.dart'; // Added CarouselStateProvider import
import 'package:iboard_app/providers/ad_top_carousel_provider.dart'; // Added TopAdCarouselProvider import
import 'package:iboard_app/providers/ad_fullscreen_provider.dart';
import 'package:iboard_app/providers/rthk_news_provider.dart';
import 'package:iboard_app/providers/app_update_provider.dart'; // 添加应用更新Provider导入
import 'package:iboard_app/managers/file_manager.dart';
import 'package:iboard_app/utils/device_id_util.dart';

import 'package:provider/provider.dart';
import 'pages/mainscreen_page.dart';
import 'pages/fullscreen_ads_page.dart';
import 'pages/settings_page.dart';
import 'pages/carousel_settings_page.dart'; // 添加轮播设置页面导入
import 'pages/error_page.dart'; // 添加错误页面导入
import 'providers/arrear_provider.dart'; // 添加欠费provider导入
import 'providers/weather_provider.dart'; // 添加天气provider导入

import 'dart:async';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runZonedGuarded(() {
    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (context) => AppDataProvider(
                baseUrl: 'http://test.iboard.skylinedances.com'),
            // baseUrl: 'http://117.72.193.54:10031'),
          ),
          Provider<FileManager>(
            create: (context) => FileManager(),
          ),
          ChangeNotifierProvider<AnnouncementProvider>(
            create: (context) {
              final appDataProvider =
                  Provider.of<AppDataProvider>(context, listen: false);
              final fileManager =
                  Provider.of<FileManager>(context, listen: false);
              return AnnouncementProvider(
                appDataProvider.apiClient,
                appDataProvider,
                fileManager,
              );
            },
          ),
          ChangeNotifierProvider<AdvertisementProvider>(
            create: (context) {
              final appDataProvider =
                  Provider.of<AppDataProvider>(context, listen: false);
              final fileManager =
                  Provider.of<FileManager>(context, listen: false);
              return AdvertisementProvider(
                appDataProvider.apiClient,
                appDataProvider,
                fileManager,
              );
            },
          ),
          ChangeNotifierProvider(
              create: (_) =>
                  CarouselStateProvider()), // Add CarouselStateProvider here
          ChangeNotifierProvider(
              create: (_) =>
                  TopAdCarouselProvider()), // Add TopAdCarouselProvider here
          ChangeNotifierProvider<AnnouncementCarouselProvider>(
            create: (context) {
              final announcementProvider = AnnouncementCarouselProvider();
              final appDataProvider =
                  Provider.of<AppDataProvider>(context, listen: false);
              announcementProvider.setAppDataProvider(appDataProvider);
              return announcementProvider;
            },
          ),
          ChangeNotifierProvider<FullscreenAdProvider>(
            create: (context) {
              final appDataProvider =
                  Provider.of<AppDataProvider>(context, listen: false);
              return FullscreenAdProvider(appDataProvider);
            },
          ),
          ChangeNotifierProvider<WeatherProvider>(
            create: (context) {
              final weatherProvider = WeatherProvider();
              final appDataProvider =
                  Provider.of<AppDataProvider>(context, listen: false);
              // 设置AppDataProvider引用
              weatherProvider.setAppDataProvider(appDataProvider);
              // 初始化底部轮播
              weatherProvider.initializeBottomCarousel();
              // 初始化当前天气卡片轮播
              weatherProvider.initializeCurrentWeatherCardCarousel();
              return weatherProvider;
            },
          ),
          ChangeNotifierProvider<RthkNewsProvider>(
            create: (context) {
              final appDataProvider =
                  Provider.of<AppDataProvider>(context, listen: false);
              return RthkNewsProvider(appDataProvider.apiClient);
            },
          ),
          ChangeNotifierProvider<ArrearProvider>(
            create: (context) {
              final appDataProvider =
                  Provider.of<AppDataProvider>(context, listen: false);
              return ArrearProvider(
                apiClient: appDataProvider.apiClient,
                appDataProvider: appDataProvider,
              );
            },
          ),
          ChangeNotifierProvider<AppUpdateProvider>(
            create: (context) {
              final updateProvider = AppUpdateProvider();
              // 在应用启动时初始化权限和检查更新（启用自动下载）
              updateProvider.initializePermissions();
              updateProvider.checkForUpdate(autoDownload: true);
              return updateProvider;
            },
          ),
        ],
        child: MyApp(),
      ),
    );
  }, (error, stack) {
    print('Uncaught error: '
        '\$error\nStack trace: \$stack');
  });
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'iBoard App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: HomePage(),
      routes: {
        '/main': (context) => MainPage(),
        '/announcement': (context) => AnnouncementPage(),
        '/fullscreen-ads': (context) => FullscreenAdsPage(),
        '/settings': (context) => SettingsPage(),
        '/carousel-settings': (context) => CarouselSettingsPage(),
      },
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _isInitializing = false;
  String? _initializationError;

  @override
  void initState() {
    super.initState();
    _initializeDeviceId();
  }

  Future<void> _initializeDeviceId() async {
    setState(() {
      _isInitializing = true;
      _initializationError = null;
    });

    try {
      final deviceIdUtil = DeviceIdUtil();
      final deviceId = await deviceIdUtil.generateUniqueDeviceId();

      // 自动使用生成的设备ID登录
      if (mounted) {
        try {
          final appDataProvider =
              Provider.of<AppDataProvider>(context, listen: false);
          final carouselStateProvider =
              Provider.of<CarouselStateProvider>(context, listen: false);
          final advertisementProvider =
              Provider.of<AdvertisementProvider>(context, listen: false);
          final announcementProvider =
              Provider.of<AnnouncementProvider>(context, listen: false);

          // 设置Provider间的关联
          appDataProvider.setCarouselStateProvider(carouselStateProvider);

          // 获取Provider引用（现在通过构造函数注入，无需手动设置）
          final arrearProvider =
              Provider.of<ArrearProvider>(context, listen: false);
          appDataProvider.setArrearProvider(arrearProvider);

          // 设置预加载回调
          carouselStateProvider.setPreloadFullscreenAdCallback(() {
            // 新的Provider没有预加载方法
          });

          // 初始化天气数据（不需要登录，公开API）
          try {
            final weatherProvider =
                Provider.of<WeatherProvider>(context, listen: false);

            // 等待WeatherProvider完成初始化
            await weatherProvider.waitForInitialization();

            // 如果缓存中没有数据，才获取新数据
            if (!weatherProvider.hasForecastData &&
                !weatherProvider.hasCurrentData &&
                !weatherProvider.hasWarningData) {
              await weatherProvider.fetchAllWeatherData();
            } else {
              print('使用缓存的天气数据');
            }

            weatherProvider.startPeriodicUpdate(
                interval: const Duration(minutes: 1));
            print('天气数据初始化完成 - 定时更新间隔设置为1分钟');
          } catch (e) {
            print('天气数据初始化失败: $e');
          }

          // 执行登录前检查缓存状态
          print('🚀 开始执行设备初始化和登录流程');
          print('🔍 检查初始化前的缓存状态...');
          await appDataProvider.debugSharedPreferencesKeys();
          final hasCachedData = await appDataProvider.hasCachedLoginData();
          print('🔍 初始化前缓存数据存在: $hasCachedData');

          await appDataProvider.initialize(deviceIdToSet: deviceId);
          print('🚀 设备初始化流程完成');

          // 初始化完成后启动定时更新和初始化欠费数据（数据可能来自登录或缓存）
          print('初始化完成，登录状态: ${appDataProvider.isLoggedIn}');
          print('Token状态: ${appDataProvider.token != null ? '有效' : '无效'}');
          print(
              '设备设置状态: ${appDataProvider.deviceSettings != null ? '已加载' : '未加载'}');
          print('数据源: ${appDataProvider.isLoggedIn ? '最新登录数据' : '缓存备用数据'}');

          // 如果有设备设置数据（无论是从登录还是缓存获取），就启动应用
          if (appDataProvider.deviceSettings != null) {
            // 启动定时登录任务（12小时一次）
            appDataProvider.startPeriodicLogin();
            print('定时登录任务已启动');

            // 启动健康检查定时任务（30分钟一次）
            appDataProvider.startPeriodicHealthCheck();
            print('健康检查定时任务已启动');

            // 启动广告定时更新
            print(
                '准备启动广告定时更新，设备设置: ${appDataProvider.deviceSettings?.advertisementUpdateDuration ?? '未设置'}');
            advertisementProvider.startPeriodicUpdate();
            print('广告定时更新已启动');

            // 启动通告定时更新
            print(
                '准备启动通告定时更新，设备设置: ${appDataProvider.deviceSettings?.noticeUpdateDuration ?? '未设置'}');
            announcementProvider.startPeriodicUpdate();
            print('通告定时更新已启动');

            // 启动欠费数据定时更新
            final deviceSettings = appDataProvider.deviceSettings;
            final arrearUpdateInterval =
                deviceSettings?.arrearageUpdateDuration ?? 1;
            arrearProvider.startPeriodicUpdate(
                updateIntervalMinutes: arrearUpdateInterval);
            print('欠费数据定时更新已启动，间隔: ${arrearUpdateInterval}分钟');

            // 初始化欠费数据
            try {
              await appDataProvider.initGetArrearData();
              print('欠费数据初始化完成');
            } catch (e) {
              print('欠费数据初始化失败: $e');
            }

            // 检查应用更新
            try {
              final updateProvider =
                  Provider.of<AppUpdateProvider>(context, listen: false);
              await updateProvider.checkForUpdate(autoDownload: true);

              // 如果有更新，自动下载到缓存
              if (mounted && updateProvider.hasUpdate) {
                print('🔄 检测到应用更新: ${updateProvider.remoteVersion}');
                print('📦 更新包将自动下载到应用缓存目录');
              }
            } catch (e) {
              print('检查应用更新失败: $e');
            }

            // 自动跳转到主页面
            if (mounted) {
              Navigator.pushReplacementNamed(context, '/main');
            }
          } else {
            // 既没有登录成功也没有可用的缓存数据
            final error = appDataProvider.error ?? '无法获取设备配置数据';

            setState(() {
              _initializationError = _getUserFriendlyError(error);
            });
          }
        } catch (e) {
          print('Auto login failed: $e');
          final error = e.toString();

          setState(() {
            _initializationError = _getUserFriendlyError(error);
          });
        }
      }
    } catch (e) {
      print('Failed to generate device ID: $e');
      setState(() {
        _initializationError = '设备ID生成失败: $e';
      });
    } finally {
      setState(() {
        _isInitializing = false;
      });
    }
  }

  void _retryInitialization() async {
    // 重新尝试初始化
    await _initializeDeviceId();
  }

  ///1, 检查是否为网络错误
  bool _isNetworkError(String error) {
    final networkErrorKeywords = [
      '无法连接到服务器',
      '网络连接失败',
      '请求超时',
      'SocketException',
      'ClientException',
      'TimeoutException',
      'Failed host lookup',
      'No address associated with hostname',
      '🌐', '⏱️', '🔌', '📱' // 用户友好的网络错误图标
    ];

    return networkErrorKeywords.any((keyword) => error.contains(keyword));
  }

  ///2, 检查是否为数据解析错误
  bool _isDataParseError(String error) {
    final parseErrorKeywords = [
      'type \'Null\' is not a subtype of type',
      'Failed to parse',
      'JSON decode error',
      'Invalid JSON',
      'Parse error',
      '数据解析失败',
      '服务器响应格式错误'
    ];

    return parseErrorKeywords.any((keyword) => error.contains(keyword));
  }

  ///3, 获取用户友好的错误信息
  String _getUserFriendlyError(String error) {
    if (_isNetworkError(error)) {
      return '🌐 网络连接失败\n\n请检查网络连接后重试，或联系管理员';
    } else if (_isDataParseError(error)) {
      return '📊 服务器数据格式错误\n\n请联系管理员检查服务器配置';
    } else {
      return '❌ 初始化失败\n\n错误信息: $error\n\n请联系管理员';
    }
  }

  @override
  Widget build(BuildContext context) {
    // 如果有初始化错误，显示错误页面
    if (_initializationError != null) {
      return ErrorPage(
        errorMessage: _initializationError!,
        onRetry: _retryInitialization,
      );
    }

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Consumer<AppDataProvider>(
                builder: (context, appDataProvider, child) {
                  // 如果AppDataProvider有错误且不在加载状态，检查是否有缓存数据可用
                  if (appDataProvider.error != null &&
                      !appDataProvider.isLoading) {
                    // 如果是网络错误但有设备设置数据（缓存），不显示错误页面
                    if ((_isNetworkError(appDataProvider.error!) ||
                            _isDataParseError(appDataProvider.error!)) &&
                        appDataProvider.deviceSettings != null) {
                      // 有缓存数据，继续正常流程，不显示错误
                      print('检测到网络错误或数据解析错误但有缓存数据，继续使用缓存数据运行');
                    } else {
                      // 没有缓存数据或非网络错误，显示错误页面
                      return ErrorPage(
                        errorMessage:
                            _getUserFriendlyError(appDataProvider.error!),
                        onRetry: _retryInitialization,
                      );
                    }
                  }

                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isInitializing)
                        Column(
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text('正在初始化設備...'),
                          ],
                        )
                      else if (appDataProvider.isLoading)
                        Column(
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text('正在登錄...'),
                          ],
                        )
                      else if (!appDataProvider.isLoggedIn)
                        Column(
                          children: [
                            Icon(
                              Icons.error_outline,
                              size: 60,
                              color: Colors.orange,
                            ),
                            SizedBox(height: 16),
                            Text(
                              '設備未登錄',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _retryInitialization,
                              child: Text('重新嘗試'),
                            ),
                          ],
                        )
                      else
                        Column(
                          children: [
                            Icon(
                              appDataProvider.isLoggedIn
                                  ? Icons.check_circle
                                  : ((_isNetworkError(appDataProvider.error ??
                                                  '') ||
                                              _isDataParseError(
                                                  appDataProvider.error ??
                                                      '')) &&
                                          appDataProvider.deviceSettings !=
                                              null)
                                      ? Icons.offline_bolt
                                      : Icons.check_circle,
                              size: 60,
                              color: appDataProvider.isLoggedIn
                                  ? Colors.green
                                  : ((_isNetworkError(appDataProvider.error ??
                                                  '') ||
                                              _isDataParseError(
                                                  appDataProvider.error ??
                                                      '')) &&
                                          appDataProvider.deviceSettings !=
                                              null)
                                      ? Colors.orange
                                      : Colors.green,
                            ),
                            SizedBox(height: 16),
                            Text(
                              appDataProvider.isLoggedIn
                                  ? '設備已登錄'
                                  : ((_isNetworkError(appDataProvider.error ??
                                                  '') ||
                                              _isDataParseError(
                                                  appDataProvider.error ??
                                                      '')) &&
                                          appDataProvider.deviceSettings !=
                                              null)
                                      ? '離線模式（使用緩存數據）'
                                      : '設備已登錄',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            if (!appDataProvider.isLoggedIn &&
                                (_isNetworkError(appDataProvider.error ?? '') ||
                                    _isDataParseError(
                                        appDataProvider.error ?? '')) &&
                                appDataProvider.deviceSettings != null)
                              Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Text(
                                  '網絡連接中斷或數據格式錯誤，正在使用緩存數據',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                          ],
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
