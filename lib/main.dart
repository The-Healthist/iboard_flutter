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
import 'pages/carousel_settings_page.dart'; // 添加轮播设置页面导入
import 'pages/error_page.dart'; // 添加错误页面导入
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
              return AdvertisementProvider(
                appDataProvider.apiClient,
                appDataProvider,
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
  final Logger _logger = Logger();
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
              _logger.i('使用緩存的天氣數據');
            }

            weatherProvider.startPeriodicUpdate(
                interval: const Duration(minutes: 1));
            _logger.i('天氣數據初始化完成 - 定時更新間隔設置為1分鐘');
          } catch (e) {
            _logger.e('天氣數據初始化失敗: $e');
          }

          // 执行登录前检查缓存状态
          _logger.i('🚀 開始執行設備初始化和登錄流程');
          _logger.i('🔍 檢查初始化前的緩存狀態...');
          await appDataProvider.debugSharedPreferencesKeys();
          final hasCachedData = await appDataProvider.hasCachedLoginData();
          _logger.i('🔍 初始化前緩存數據存在: $hasCachedData');

          await appDataProvider.initialize(deviceIdToSet: deviceId);
          _logger.i('🚀 設備初始化流程完成');

          // 初始化完成后启动定时更新和初始化欠费数据（数据可能来自登录或缓存）
          _logger.i('初始化完成，登錄狀態: ${appDataProvider.isLoggedIn}');
          _logger.i('Token狀態: ${appDataProvider.token != null ? '有效' : '無效'}');
          _logger.i(
              '設備設置狀態: ${appDataProvider.deviceSettings != null ? '已加載' : '未加載'}');
          _logger.i('數據源: ${appDataProvider.isLoggedIn ? '最新登錄數據' : '緩存備用數據'}');

          // 在 _initializeDeviceId 方法中，優化初始化順序和錯誤處理
          // 如果有设备设置数据（无论是从登录还是缓存获取），就启动应用
          if (appDataProvider.deviceSettings != null) {
            // 启动定时登录任务（12小时一次）
            appDataProvider.startPeriodicLogin();
            _logger.i('定時登錄任務已啟動');

            // 启动健康检查定时任务（30分钟一次）
            appDataProvider.startPeriodicHealthCheck();
            _logger.i('健康檢查定時任務已啟動');

            // ===== 統一輪播數據初始化區塊 =====
            try {
              // 1. 首先初始化所有基礎數據
              await advertisementProvider.initializeCarouselAdvertisements();
              
              // 2. 確保欠費數據先初始化完成
              await appDataProvider.initGetArrearData();
              _logger.i('✅ 欠費數據初始化完成');
              
              // 3. 設置Provider引用
              final topAdCarouselProvider = Provider.of<TopAdCarouselProvider>(context, listen: false);
              final fullscreenAdProvider = Provider.of<FullscreenAdProvider>(context, listen: false);
              final announcementCarouselProvider = Provider.of<AnnouncementCarouselProvider>(context, listen: false);
              
              advertisementProvider.setCarouselProviders(
                topAdCarouselProvider: topAdCarouselProvider,
                fullscreenAdProvider: fullscreenAdProvider,
              );
              
              // 設置通告輪播提供者的依賴引用
              announcementCarouselProvider.setAppDataProvider(appDataProvider);
              announcementCarouselProvider.setArrearProvider(arrearProvider);
              
              // 設置通告提供者的輪播提供者引用
              announcementProvider.setCarouselProvider(announcementCarouselProvider);
              
              // 4. 最後初始化通告輪播數據（此時所有依賴都已準備好）
              final carouselAnnouncements = announcementProvider.getCarouselAnnouncements();
              if (carouselAnnouncements.isNotEmpty) {
                announcementCarouselProvider.updateCarouselList(carouselAnnouncements);
                _logger.i('✅ 通告輪播數據從緩存初始化完成: ${carouselAnnouncements.length} 個通告');
              } else {
                // 如果緩存中沒有數據，先初始化空輪播組件（確保主屏幕可用）
                announcementCarouselProvider.updateCarouselList([]);
                _logger.i('⚠️ 緩存中暫無通告數據，已初始化空輪播組件（包含主屏幕）');
                
                // 然後異步獲取通告數據
                announcementProvider.fetchNotices().then((_) {
                  final freshCarouselAnnouncements = announcementProvider.getCarouselAnnouncements();
                  if (freshCarouselAnnouncements.isNotEmpty) {
                    announcementCarouselProvider.updateCarouselList(freshCarouselAnnouncements);
                    _logger.i('✅ 通告輪播數據從網絡異步更新完成: ${freshCarouselAnnouncements.length} 個通告');
                  }
                }).catchError((e) {
                  _logger.e('異步獲取通告數據失敗: $e');
                });
              }
              
              _logger.i('🎯 所有輪播數據初始化完成，確保內容正常顯示');
            } catch (e) {
              _logger.e('輪播數據初始化過程中發生錯誤: $e');
              // 即使部分初始化失敗，也要確保基本的輪播組件可用
              try {
                final announcementCarouselProvider = Provider.of<AnnouncementCarouselProvider>(context, listen: false);
                announcementCarouselProvider.updateCarouselList([]);
                _logger.i('🔧 錯誤恢復：已初始化基本輪播組件');
              } catch (recoveryError) {
                _logger.e('錯誤恢復失敗: $recoveryError');
              }
            }

            // 启动广告定时更新
            _logger.i(
                '準備啟動廣告定時更新，設備設置: ${appDataProvider.deviceSettings?.advertisementUpdateDuration ?? '未設置'}');
            advertisementProvider.startPeriodicUpdate();
            _logger.i('廣告定時更新已啟動');

            // 启动通告定时更新
            _logger.i(
                '準備啟動通告定時更新，設備設置: ${appDataProvider.deviceSettings?.noticeUpdateDuration ?? '未設置'}');
            announcementProvider.startPeriodicUpdate();
            _logger.i('通告定時更新已啟動');

            final deviceSettings = appDataProvider.deviceSettings;
            final arrearUpdateInterval =
                deviceSettings?.arrearageUpdateDuration ?? 1;
            arrearProvider.startPeriodicUpdate(
                updateIntervalMinutes: arrearUpdateInterval);
            _logger.i('欠費數據定時更新已啟動，間隔: $arrearUpdateInterval分鐘');

            // 初始化欠费数据
            try {
              await appDataProvider.initGetArrearData();
              _logger.i('欠費數據初始化完成');
            } catch (e) {
              _logger.e('欠費數據初始化失敗: $e');
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
                _logger.i('🔄 檢測到應用更新: ${updateProvider.remoteVersion}');
                _logger.i('📦 更新包將自動下載到應用緩存目錄');
              }
            } catch (e) {
              _logger.e('檢查應用更新失敗: $e');
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
          _logger.e('Auto login failed: $e');
          final error = e.toString();

          setState(() {
            _initializationError = _getUserFriendlyError(error);
          });
        }
      }
    } catch (e) {
      _logger.e('Failed to generate device ID: $e');
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
                      _logger.i('檢測到網絡錯誤或數據解析錯誤但有緩存數據，繼續使用緩存數據運行');
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
