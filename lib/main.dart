import 'package:flutter/material.dart';
import 'package:iboard_app/pages/main_page.dart';
import 'package:iboard_app/providers/advertisement_provider.dart';
import 'package:iboard_app/providers/announcement_provider.dart';
import 'package:iboard_app/providers/announcement_carousel_provider.dart';
import 'package:iboard_app/providers/app_data_provider.dart';
import 'package:iboard_app/providers/state_provider.dart'; // Added CarouselStateProvider import
import 'package:iboard_app/providers/top_ad_carousel_provider.dart'; // Added TopAdCarouselProvider import
import 'package:iboard_app/providers/fullscreen_ad_provider.dart';
import 'package:iboard_app/providers/bottom_weather_qrcode_carousel_provider.dart';
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
              // 主服务器地址
              baseUrl: 'http://test.iboard.skylinedances.com',
              // 备用服务器地址（暂时设为null，需要实际IP时请替换）
              fallbackUrl: null, // 如需备用服务器，请替换为: 'http://实际IP:端口'
            ),
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
          ChangeNotifierProvider(
              create: (_) =>
                  AnnouncementCarouselProvider()), // Add AnnouncementCarouselProvider here
          ChangeNotifierProvider<FullscreenAdProvider>(
            create: (context) {
              final appDataProvider =
                  Provider.of<AppDataProvider>(context, listen: false);
              return FullscreenAdProvider(appDataProvider);
            },
          ),
          ChangeNotifierProvider(
              create: (_) =>
                  BottomWeatherQrcodeCarouselProvider()), // Add BottomWeatherQrcodeCarouselProvider here
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
          ChangeNotifierProvider(
            create: (context) => WeatherProvider(),
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

          // 执行登录

          await appDataProvider.initialize(deviceIdToSet: deviceId);
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

            // 自动跳转到主页面
            if (mounted) {
              Navigator.pushReplacementNamed(context, '/main');
            }
          } else {
            // 既没有登录成功也没有可用的缓存数据
            setState(() {
              _initializationError = appDataProvider.error ?? '无法获取设备配置数据';
            });
          }
        } catch (e) {
          print('Auto login failed: $e');
          setState(() {
            _initializationError = '登录失败: $e';
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
                  // 如果AppDataProvider有错误且不在加载状态，显示错误页面
                  if (appDataProvider.error != null &&
                      !appDataProvider.isLoading) {
                    return ErrorPage(
                      errorMessage: appDataProvider.error!,
                      onRetry: _retryInitialization,
                    );
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
                              Icons.check_circle,
                              size: 60,
                              color: Colors.green,
                            ),
                            SizedBox(height: 16),
                            Text(
                              '設備已登錄',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
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
