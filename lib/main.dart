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
import 'providers/arrear_provider.dart'; // 添加欠费provider导入
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

  @override
  void initState() {
    super.initState();
    _initializeDeviceId();
  }

  Future<void> _initializeDeviceId() async {
    setState(() {
      _isInitializing = true;
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
          await appDataProvider.initializeAndLogin(deviceIdToSet: deviceId);

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
          }
        } catch (e) {
          print('Auto login failed: $e');
          // 不显示错误，用户可以手动点击Main按钮重试
        }
      }
    } catch (e) {
      print('Failed to generate device ID: $e');
    } finally {
      setState(() {
        _isInitializing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // appBar: AppBar(
      //   title: Text('iBoard 主頁'),
      //   backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      // ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Consumer<AppDataProvider>(
                builder: (context, appDataProvider, child) {
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
                      // 注释掉主要的UI内容，因为现在会自动跳转到主页面
                      // else ...[
                      //   // 显示登录状态
                      //   Container(
                      //     padding: EdgeInsets.all(16),
                      //     margin: EdgeInsets.all(16),
                      //     decoration: BoxDecoration(
                      //       color: appDataProvider.isLoggedIn
                      //           ? Colors.green.shade50
                      //           : Colors.orange.shade50,
                      //       borderRadius: BorderRadius.circular(8),
                      //       border: Border.all(
                      //         color: appDataProvider.isLoggedIn
                      //             ? Colors.green.shade200
                      //             : Colors.orange.shade200,
                      //       ),
                      //     ),
                      //     child: Row(
                      //       mainAxisSize: MainAxisSize.min,
                      //       children: [
                      //         Icon(
                      //           appDataProvider.isLoggedIn
                      //               ? Icons.check_circle
                      //               : Icons.warning,
                      //           color: appDataProvider.isLoggedIn
                      //               ? Colors.green.shade700
                      //               : Colors.orange.shade700,
                      //         ),
                      //         SizedBox(width: 8),
                      //         Text(
                      //           appDataProvider.isLoggedIn ? '設備已登錄' : '設備未登錄',
                      //           style: TextStyle(
                      //             color: appDataProvider.isLoggedIn
                      //                 ? Colors.green.shade700
                      //                 : Colors.orange.shade700,
                      //             fontWeight: FontWeight.w600,
                      //           ),
                      //         ),
                      //       ],
                      //     ),
                      //   ),
                      //   SizedBox(height: 20),
                      //   ElevatedButton(
                      //     onPressed: () async {
                      //       if (_deviceId == null) {
                      //         ScaffoldMessenger.of(context).showSnackBar(
                      //           SnackBar(content: Text('設備碼尚未生成')),
                      //         );
                      //         return;
                      //       }

                      //       try {
                      //         final appDataProvider =
                      //             Provider.of<AppDataProvider>(context,
                      //                 listen: false);
                      //         final carouselStateProvider =
                      //             Provider.of<CarouselStateProvider>(context,
                      //                 listen: false);
                      //         final advertisementProvider =
                      //             Provider.of<AdvertisementProvider>(context,
                      //                 listen: false);
                      //         final announcementProvider =
                      //             Provider.of<AnnouncementProvider>(context,
                      //                 listen: false);

                      //         // 确保Provider间的关联已设置
                      //         appDataProvider.setCarouselStateProvider(
                      //             carouselStateProvider);

                      //         if (!appDataProvider.isLoggedIn) {
                      //           await appDataProvider.initializeAndLogin(
                      //               deviceIdToSet: _deviceId);
                      //         }

                      //         // 登录成功后启动定时更新
                      //         if (appDataProvider.isLoggedIn) {
                      //           advertisementProvider.startPeriodicUpdate();
                      //           announcementProvider.startPeriodicUpdate();
                      //         }

                      //         if (context.mounted) {
                      //           Navigator.pushNamed(context, '/main');
                      //         }
                      //       } catch (e) {
                      //         if (context.mounted) {
                      //           ScaffoldMessenger.of(context).showSnackBar(
                      //             SnackBar(content: Text('Login failed: $e')),
                      //           );
                      //         }
                      //         print("Login failed: $e");
                      //       }
                      //     },
                      //     child: Text('Main'),
                      //   ),
                      //   SizedBox(height: 20),
                      //   ElevatedButton(
                      //     onPressed: () {
                      //       Navigator.pushNamed(context, '/settings');
                      //     },
                      //     child: Text('設置頁面'),
                      //   ),

                      //   // 显示错误信息（如果有）
                      //   if (appDataProvider.error != null) ...[
                      //     SizedBox(height: 20),
                      //     Container(
                      //       padding: EdgeInsets.all(12),
                      //       margin: EdgeInsets.all(16),
                      //       decoration: BoxDecoration(
                      //         color: Colors.red.shade50,
                      //         borderRadius: BorderRadius.circular(8),
                      //         border: Border.all(color: Colors.red.shade200),
                      //       ),
                      //       child: Row(
                      //         children: [
                      //           Icon(
                      //             Icons.error_outline,
                      //             color: Colors.red.shade700,
                      //             size: 20,
                      //           ),
                      //           SizedBox(width: 10),
                      //           Expanded(
                      //             child: Text(
                      //               appDataProvider.error!,
                      //               style: TextStyle(
                      //                 fontSize: 14,
                      //                 color: Colors.red.shade700,
                      //               ),
                      //             ),
                      //           ),
                      //         ],
                      //       ),
                      //     ),
                      //   ],
                      // ],
                    ],
                  );
                },
              ),
            ),
          ),
          // 底部显示设备码 - 也注释掉，因为主页面已经有设备ID显示
          // Container(
          //   width: double.infinity,
          //   padding: EdgeInsets.all(16),
          //   color: Colors.grey.shade100,
          //   child: Text(
          //     _deviceId != null ? '設備碼: $_deviceId' : '設備碼生成中...',
          //     style: TextStyle(
          //       fontSize: 12,
          //       color: Colors.grey.shade600,
          //     ),
          //     textAlign: TextAlign.center,
          //   ),
          // ),
        ],
      ),
    );
  }
}
