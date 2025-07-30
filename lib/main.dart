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
                baseUrl: 'http://test.iboard.skylinedances.com'),
          ),
          Provider<FileManager>(
            create: (context) => FileManager(),
          ),
          ChangeNotifierProxyProvider2<AppDataProvider, FileManager,
              AnnouncementProvider>(
            create: (context) => AnnouncementProvider(
              Provider.of<AppDataProvider>(context, listen: false).apiClient,
              Provider.of<AppDataProvider>(context, listen: false),
              Provider.of<FileManager>(context, listen: false),
            ),
            update: (context, appDataProvider, fileManager,
                    previousAnnouncementProvider) =>
                AnnouncementProvider(
              appDataProvider.apiClient,
              appDataProvider,
              fileManager,
            ),
          ),
          ChangeNotifierProxyProvider2<AppDataProvider, FileManager,
              AdvertisementProvider>(
            create: (context) => AdvertisementProvider(
              Provider.of<AppDataProvider>(context, listen: false).apiClient,
              Provider.of<AppDataProvider>(context, listen: false),
              Provider.of<FileManager>(context, listen: false),
            ),
            update: (context, appDataProvider, fileManager,
                    previousAdvertisementProvider) =>
                AdvertisementProvider(
              appDataProvider.apiClient,
              appDataProvider,
              fileManager,
            ),
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
          ChangeNotifierProvider(
              create: (_) =>
                  FullscreenAdProvider()), // Add FullscreenAdProvider here
          ChangeNotifierProvider(
              create: (_) =>
                  BottomWeatherQrcodeCarouselProvider()), // Add BottomWeatherQrcodeCarouselProvider here
          ChangeNotifierProvider<ArrearProvider>(
            create: (context) => ArrearProvider(
              apiClient: Provider.of<AppDataProvider>(context, listen: false)
                  .apiClient,
            ),
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
          final fullscreenAdProvider =
              Provider.of<FullscreenAdProvider>(context, listen: false);

          // 设置Provider间的关联
          appDataProvider.setCarouselStateProvider(carouselStateProvider);
          fullscreenAdProvider.setAppDataProvider(appDataProvider);

          // 设置ArrearProvider引用
          final arrearProvider =
              Provider.of<ArrearProvider>(context, listen: false);
          appDataProvider.setArrearProvider(arrearProvider);

          // 设置预加载回调
          carouselStateProvider.setPreloadFullscreenAdCallback(() {
            // 新的Provider没有预加载方法
          });

          // 执行登录

          // await appDataProvider.initializeAndLogin(deviceIdToSet: deviceId);
          await appDataProvider.initialize(deviceIdToSet: deviceId);
          // 登录成功后启动定时更新和初始化欠费数据
          if (appDataProvider.isLoggedIn) {
            advertisementProvider.startPeriodicUpdate();
            announcementProvider.startPeriodicUpdate();

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
          } else if (appDataProvider.error != null) {
            // 登录失败，显示错误信息
            setState(() {
              _initializationError = appDataProvider.error;
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
