import 'package:flutter/material.dart';
import 'package:iboard_app/pages/main_page.dart';
import 'package:iboard_app/providers/advertisement_provider.dart';
import 'package:iboard_app/providers/announcement_provider.dart';
import 'package:iboard_app/providers/announcement_carousel_provider.dart';
import 'package:iboard_app/providers/app_data_provider.dart';
import 'package:iboard_app/providers/state_provider.dart'; // Added CarouselStateProvider import
import 'package:iboard_app/providers/ad_top_carousel_provider.dart'; // Added TopAdCarouselProvider import
import 'package:iboard_app/providers/ad_full_carousel_provider.dart';
import 'package:iboard_app/providers/rthk_news_provider.dart';
import 'package:iboard_app/providers/app_update_provider.dart'; // 添加应用更新Provider导入
import 'package:iboard_app/managers/file_manager.dart';
import 'package:iboard_app/utils/device_id_util.dart';

import 'package:provider/provider.dart';
import 'pages/mainscreen_page.dart';
import 'pages/fullscreen_ads_page.dart';
import 'pages/settings_page.dart';
import 'pages/carousel_settings_page.dart'; // 添加轮播设置頁面导入
import 'pages/error_page.dart'; // 添加错误頁面导入
import 'providers/arrear_provider.dart'; // 添加欠费provider导入
import 'providers/weather_provider.dart'; // 添加天气provider导入
import 'package:logger/logger.dart';

import 'dart:async';

final Logger _logger = Logger();

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
              return AdvertisementProvider(
                appDataProvider.apiClient,
                appDataProvider,
              );
            },
          ),
          ChangeNotifierProvider(create: (_) => CarouselStateProvider()),
          ChangeNotifierProvider(create: (_) => TopAdCarouselProvider()),
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
        child: const MyApp(),
      ),
    );
  }, (error, stack) {
    _logger.e('Uncaught error: $error', error: error, stackTrace: stack);
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'iBoard App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const HomePage(),
      routes: {
        '/main': (context) => const MainPage(),
        '/announcement': (context) => const AnnouncementPage(),
        '/fullscreen-ads': (context) => const FullscreenAdsPage(),
        '/settings': (context) => const SettingsPage(),
        '/carousel-settings': (context) => const CarouselSettingsPage(),
      },
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
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
      // 1
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
          final weatherProvider =
              Provider.of<WeatherProvider>(context, listen: false);

          appDataProvider.setCarouselStateProvider(carouselStateProvider);

          // 获取Provider引用（现在通过构造函数注入，无需手动设置）
          final arrearProvider =
              Provider.of<ArrearProvider>(context, listen: false);
          appDataProvider.setArrearProvider(arrearProvider);
          carouselStateProvider.setPreloadFullscreenAdCallback(() async {});
          // 2.登录
          await appDataProvider.initialize(deviceId: deviceId);
          // 3.初始化天气数据（不需要登录，公开API）
          await weatherProvider.fetchAllWeatherData();

          // 3.1 启动天气数据定时更新（120分鈡一次）
          weatherProvider.startPeriodicUpdate(
              interval: const Duration(minutes: 120));
          if (appDataProvider.deviceSettings != null) {
            // 启动定时登录任务（12小时一次）
            appDataProvider.startPeriodicLogin();
            // 启动健康检查定时任务（30分鈡一次）
            appDataProvider.startPeriodicHealthCheck();

            // 4. 統一輪播數據初始化區塊
            try {
              // 4.1. 首先初始化所有基礎數據
              await advertisementProvider.fetchAdvertisements(forceInit: true);

              // 4.2 確保欠費數據先初始化完成
              await arrearProvider.fetchFeeData();

              // 4.3 获取通告数据初始化
              await announcementProvider.fetchNotices(forceInit: true);

              // 3. 設置Provider引用
              final topAdCarouselProvider =
                  Provider.of<TopAdCarouselProvider>(context, listen: false);
              final fullscreenAdProvider =
                  Provider.of<FullscreenAdProvider>(context, listen: false);
              final announcementCarouselProvider =
                  Provider.of<AnnouncementCarouselProvider>(context,
                      listen: false);
              // 設置廣告輪播提供者的依賴引用
              advertisementProvider.setCarouselProviders(
                topAdCarouselProvider: topAdCarouselProvider,
                fullscreenAdProvider: fullscreenAdProvider,
              );

              // 設置通告輪播提供者的依賴引用
              announcementCarouselProvider.setAppDataProvider(appDataProvider);
              announcementCarouselProvider.setArrearProvider(arrearProvider);

              // 🔧 修复：在创建Widget之前设置正确的返回按钮回调
              announcementCarouselProvider.setHomeButtonCallback(() {
                // 返回主屏幕的回调逻辑
                announcementCarouselProvider.jumpToAnnouncementIndex(0);
                debugPrint('🏠 [Main] 通过返回按钮跳转到主屏幕');
              });

              // 設置通告提供者的輪播提供者引用
              announcementProvider
                  .setCarouselProvider(announcementCarouselProvider);

              // 4. 最後初始化通告輪播數據（此時所有依賴都已準備好）
              final carouselAnnouncements =
                  announcementProvider.getCarouselAnnouncements();
              if (carouselAnnouncements.isNotEmpty) {
                debugPrint(
                    '🏠 [Main] 初始化轮播（有通告）: ${carouselAnnouncements.length} 个');
                announcementCarouselProvider
                    .updateCarouselList(carouselAnnouncements);
              } else {
                debugPrint('🏠 [Main] 初始化轮播（无通告），创建主屏幕+费用表格模式');
                announcementCarouselProvider.updateCarouselList([]);
                announcementProvider.fetchNotices().then((_) {
                  final freshCarouselAnnouncements =
                      announcementProvider.getCarouselAnnouncements();
                  if (freshCarouselAnnouncements.isNotEmpty) {
                    debugPrint(
                        '🔄 [Main] 异步获取到通告: ${freshCarouselAnnouncements.length} 个');
                    announcementCarouselProvider
                        .updateCarouselList(freshCarouselAnnouncements);
                  }
                }).catchError((e) {
                  debugPrint('異步獲取通告數據失敗: $e');
                });
              }
            } catch (e) {
              debugPrint('輪播數據初始化過程中發生錯誤: $e');
              // 即使部分初始化失敗，也要確保基本的輪播組件可用
              try {
                final announcementCarouselProvider =
                    Provider.of<AnnouncementCarouselProvider>(context,
                        listen: false);
                announcementCarouselProvider.updateCarouselList([]);
                debugPrint('🔧 錯誤恢復：已初始化基本輪播組件');
              } catch (recoveryError) {
                debugPrint('錯誤恢復失敗: $recoveryError');
              }
            }

            // 启动广告定时更新
            advertisementProvider.startPeriodicUpdate();

            // 启动通告定时更新
            announcementProvider.startPeriodicUpdate();

            final deviceSettings = appDataProvider.deviceSettings;
            final arrearUpdateInterval =
                deviceSettings?.arrearageUpdateDuration ?? 1;
            arrearProvider.startPeriodicUpdate(
                updateIntervalMinutes: arrearUpdateInterval);
            debugPrint('欠費數據定時更新已啟動，間隔: $arrearUpdateInterval分鐘');

            // 初始化欠费数据
            try {
              await arrearProvider.fetchFeeData();
              debugPrint('欠費數據初始化完成');
            } catch (e) {
              debugPrint('欠費數據初始化失敗: $e');
            }

            // 檢查應用更新
            try {
              if (!mounted) return;
              final updateProvider =
                  Provider.of<AppUpdateProvider>(context, listen: false);
              await updateProvider.checkForUpdate(autoDownload: true);

              if (!mounted) return;
              // 如果有更新，自動下載到緩存
              if (updateProvider.hasUpdate) {
                debugPrint('🔄 檢測到應用更新: ${updateProvider.remoteVersion}');
                debugPrint('📦 更新包將自動下載到應用緩存目錄');
              }
            } catch (e) {
              debugPrint('檢查應用更新失敗: $e');
            }

            // 自動跳轉到主頁面
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
          debugPrint('Auto login failed: $e');
          final error = e.toString();

          setState(() {
            _initializationError = _getUserFriendlyError(error);
          });
        }
      }
    } catch (e) {
      debugPrint('Failed to generate device ID: $e');
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
      '无法連接到服务器',
      '网络連接失败',
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
      return '🌐 网络連接失败\n\n请检查网络連接后重试，或联系管理员';
    } else if (_isDataParseError(error)) {
      return '📊 服务器数据格式错误\n\n请联系管理员检查服务器配置';
    } else {
      return '❌ 初始化失败\n\n错误信息: $error\n\n请联系管理员';
    }
  }

  ///2，设置全屏广告预加载回调
  void _setupFullscreenAdPreloadCallback() {
    final stateProvider = context.read<CarouselStateProvider>();
    final fullAdProvider = context.read<FullscreenAdProvider>();

    // 设置预加载回调
    stateProvider.setPreloadFullscreenAdCallback(() async {
      // 新的Provider没有预加载方法
    });

    // 设置进入全屏广告模式回调
    stateProvider.setEnterFullscreenAdModeCallback(() {
      fullAdProvider.enterFullscreenMode();
    });

    // 设置退出全屏广告模式回调
    stateProvider.setExitFullscreenAdModeCallback(() {
      fullAdProvider.exitFullscreenMode();
    });
  }

  @override
  Widget build(BuildContext context) {
    // 如果有初始化错误，显示错误頁面
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
                    // 如果是网络错误但有设备设置数据（缓存），不显示错误頁面
                    if ((_isNetworkError(appDataProvider.error!) ||
                            _isDataParseError(appDataProvider.error!)) &&
                        appDataProvider.deviceSettings != null) {
                      // 有缓存数据，继续正常流程，不显示错误
                      debugPrint('檢測到網絡錯誤或數據解析錯誤但有緩存數據，繼續使用緩存數據運行');
                    } else {
                      // 没有缓存数据或非网络错误，显示错误頁面
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
                        const Column(
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text('正在初始化設備...'),
                          ],
                        )
                      else if (appDataProvider.isLoading)
                        const Column(
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text('正在登錄...'),
                          ],
                        )
                      else if (!appDataProvider.isLoggedIn)
                        Column(
                          children: [
                            const Icon(
                              Icons.error_outline,
                              size: 60,
                              color: Colors.orange,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              '設備未登錄',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _retryInitialization,
                              child: const Text('重新嘗試'),
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
                            const SizedBox(height: 16),
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
                              style: const TextStyle(
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
                                padding: const EdgeInsets.only(top: 8),
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
