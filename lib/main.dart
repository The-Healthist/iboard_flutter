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
import 'package:iboard_app/providers/printer_provider.dart'; // 添加打印機提供者導入
import 'package:iboard_app/providers/payment_provider.dart'; // 添加支付提供者導入
import 'package:iboard_app/providers/receipt_printer_provider.dart'; // 添加小票打印機提供者導入
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
          ChangeNotifierProvider<PrinterProvider>(
            create: (context) {
              return PrinterProvider();
            },
          ),
          ChangeNotifierProvider<PaymentNotifier>(
            create: (context) {
              return PaymentNotifier();
            },
          ),
          ChangeNotifierProvider<ReceiptPrinterNotifier>(
            create: (context) {
              final receiptPrinter = ReceiptPrinterNotifier();
              // 初始化小票打印機
              receiptPrinter.initializePrinter();
              return receiptPrinter;
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

          // 获取Provider引用（现在通过构造函数注入，无需手动设置）
          final arrearProvider =
              Provider.of<ArrearProvider>(context, listen: false);
          appDataProvider.setArrearProvider(arrearProvider);

          try {
            await appDataProvider.initialize(deviceId: deviceId);
          } catch (loginError) {
            debugPrint('[初始化]初始化其他組件: $loginError');
            // 登录失败不阻止应用启动，继续后续初始化
          }

          // 设置状态管理器引用（无论登录是否成功都要设置）
          appDataProvider.setCarouselStateProvider(carouselStateProvider);

          // 3.初始化天气数据（不需要登录，公开API） - 失败不影响应用启动
          try {
            await weatherProvider.fetchAllWeatherDataWithWarnings();
            // 3.1 启动天气预报和当前天气定时更新（120分鈡一次）
            weatherProvider.startPeriodicUpdate(
                interval: const Duration(minutes: 120));
            // 3.2 启动天气警告独立定时更新（15分鈡一次）
            weatherProvider.startWarningPeriodicUpdate(
                interval: const Duration(minutes: 15));
          } catch (weatherError) {
            debugPrint('[初始化]天氣數據初始化失敗，將使用默認數據: $weatherError');
          }

          if (appDataProvider.deviceSettings != null) {
            try {
              appDataProvider.startPeriodicLogin();
            } catch (e) {
              debugPrint('[初始化]定時登錄任務啟動失敗: $e');
            }

            // 启动健康检查定时任务（30分鈡一次）
            try {
              appDataProvider.startPeriodicHealthCheck();
            } catch (e) {
              debugPrint('[初始化]健康檢查任務啟動失敗: $e');
            }

            // 8.1 初始化打印機提供者
            try {
              final printerProvider =
                  Provider.of<PrinterProvider>(context, listen: false);

              // 設置後端API客戶端
              printerProvider.setApiClient(appDataProvider.apiClient);

              // 從設備設置中獲取香橙派IP
              final deviceSettings = appDataProvider.deviceSettings;
              final orangePiIp = deviceSettings?.orangePiIp;

              if (orangePiIp != null && orangePiIp.isNotEmpty) {
                // 初始化打印機提供者
                await printerProvider.initialize(orangePiIp: orangePiIp);

                // 啟動定時健康檢查（30分鐘一次）
                printerProvider.startPeriodicHealthCheck(
                  interval: const Duration(minutes: 30),
                );

                debugPrint('[初始化]打印機提供者初始化完成，啟動定時健康檢查');
              } else {
                debugPrint('[初始化]香橙派IP未配置，跳過打印機初始化');
              }
            } catch (e) {
              debugPrint('[初始化]打印機提供者初始化失敗: $e');
            }

            try {
              await advertisementProvider.fetchAdvertisements(forceInit: true);
            } catch (adError) {
              debugPrint('[初始化]廣告數據初始化失敗，將使用默認或緩存數據: $adError');
            }

            // 4.2 初始化欠費數據
            try {
              await arrearProvider.fetchFeeData();
            } catch (arrearError) {
              debugPrint('[初始化]欠費數據初始化失敗，將使用默認或緩存數據: $arrearError');
            }

            // 4.3 初始化通告數據
            try {
              await announcementProvider.fetchNotices(forceInit: true);
            } catch (noticeError) {
              debugPrint('[初始化]通告數據初始化失敗，將使用默認或緩存數據: $noticeError');
            }

            // 5. 設置Provider引用（無論上述初始化是否成功都要設置）
            final topAdCarouselProvider =
                Provider.of<TopAdCarouselProvider>(context, listen: false);
            final fullscreenAdProvider =
                Provider.of<FullscreenAdProvider>(context, listen: false);
            final announcementCarouselProvider =
                Provider.of<AnnouncementCarouselProvider>(context,
                    listen: false);

            // 設置廣告輪播提供者的依賴引用
            try {
              advertisementProvider.setCarouselProviders(
                topAdCarouselProvider: topAdCarouselProvider,
                fullscreenAdProvider: fullscreenAdProvider,
              );
            } catch (e) {
              debugPrint('[初始化]廣告輪播提供者依賴設置失敗: $e');
            }

            try {
              announcementCarouselProvider.setAppDataProvider(appDataProvider);
              announcementCarouselProvider.setArrearProvider(arrearProvider);

              announcementCarouselProvider.setHomeButtonCallback(() {
                announcementCarouselProvider.jumpToAnnouncementIndex(0);
                debugPrint('[初始化]通过返回按钮跳转到主屏幕');
              });

              announcementProvider
                  .setCarouselProvider(announcementCarouselProvider);
            } catch (e) {
              debugPrint('[初始化]通告輪播提供者依賴設置失敗: $e');
            }

            // 6. 初始化通告輪播數據（失敗不影響應用啟動）
            try {
              final carouselAnnouncements =
                  announcementProvider.getCarouselAnnouncements();
              if (carouselAnnouncements.isNotEmpty) {
                announcementCarouselProvider
                    .updateCarouselList(carouselAnnouncements);
              } else {
                announcementCarouselProvider.updateCarouselList([]);
                // 異步獲取通告數據，失敗不影響主流程
                announcementProvider.fetchNotices().then((_) {
                  final freshCarouselAnnouncements =
                      announcementProvider.getCarouselAnnouncements();
                  if (freshCarouselAnnouncements.isNotEmpty) {
                    announcementCarouselProvider
                        .updateCarouselList(freshCarouselAnnouncements);
                  }
                }).catchError((e) {
                  debugPrint('[初始化]異步獲取通告數據失敗: $e');
                });
              }
            } catch (carouselError) {
              debugPrint('[初始化]通告輪播初始化失敗，將使用默認配置: $carouselError');
              try {
                announcementCarouselProvider.updateCarouselList([]);
              } catch (e) {
                debugPrint('[初始化]通告輪播默認配置也失敗: $e');
              }
            }

            // 7. 启动定时更新任务（失敗不影響應用啟動）
            try {
              advertisementProvider.startPeriodicUpdate();
            } catch (e) {
              debugPrint('[初始化]廣告定時更新啟動失敗: $e');
            }

            try {
              announcementProvider.startPeriodicUpdate();
            } catch (e) {
              debugPrint('[初始化]通告定時更新啟動失敗: $e');
            }

            try {
              final deviceSettings = appDataProvider.deviceSettings;
              final arrearUpdateInterval =
                  deviceSettings?.arrearageUpdateDuration ?? 1;
              arrearProvider.startPeriodicUpdate(
                  updateIntervalMinutes: arrearUpdateInterval);
            } catch (e) {
              debugPrint('[初始化]欠費數據定時更新啟動失敗: $e');
            }

            // 8. 檢查應用更新（失敗不影響應用啟動）
            try {
              if (!mounted) return;
              final updateProvider =
                  Provider.of<AppUpdateProvider>(context, listen: false);
              await updateProvider.checkForUpdate(autoDownload: true);

              if (!mounted) return;
              // 如果有更新，自動下載到緩存
              if (updateProvider.hasUpdate) {}
            } catch (e) {
              debugPrint('[初始化]檢查應用更新失敗: $e');
            }
          } else {
            debugPrint('[初始化]無設備設置，嘗試從緩存初始化組件');

            // 🔧 關鍵修復：即使沒有設備設置，也要嘗試加載和使用緩存數據
            await _initializeFromCache(
              announcementProvider,
              announcementCarouselProvider:
                  Provider.of<AnnouncementCarouselProvider>(context,
                      listen: false),
              arrearProvider: arrearProvider,
              weatherProvider: weatherProvider,
            );
          }

          // 🎯 關鍵：無論上述任何步驟是否失敗，都嘗試進入主頁面
          try {
            if (mounted) {
              Navigator.pushReplacementNamed(context, '/main');
            }
          } catch (navigationError) {
            debugPrint('[初始化]跳轉主頁面失敗: $navigationError');
          }
        } catch (e) {
          debugPrint('[初始化]應用初始化過程中出現嚴重錯誤: $e');

          try {
            // 緊急模式：嘗試加載所有可用的緩存數據
            final emergencyAnnouncementProvider =
                Provider.of<AnnouncementProvider>(context, listen: false);
            final emergencyArrearProvider =
                Provider.of<ArrearProvider>(context, listen: false);
            final emergencyWeatherProvider =
                Provider.of<WeatherProvider>(context, listen: false);

            await _emergencyInitializeFromCache(
              emergencyAnnouncementProvider,
              emergencyArrearProvider,
              emergencyWeatherProvider,
            );

            // 嘗試進入主頁面，哪怕是最基本的狀態
            if (mounted) {
              Navigator.pushReplacementNamed(context, '/main');

              return; // 成功跳转就不设置错误了
            }
          } catch (emergencyError) {}

          // 只有在所有嘗試都失敗時才設置錯誤狀態
          setState(() {
            _initializationError = _getUserFriendlyError(e.toString());
          });
        }
      }
    } catch (e) {
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

  ///0a, 從緩存初始化組件（當API失敗但有緩存數據時使用）
  Future<void> _initializeFromCache(
    AnnouncementProvider announcementProvider, {
    required AnnouncementCarouselProvider announcementCarouselProvider,
    required ArrearProvider arrearProvider,
    required WeatherProvider weatherProvider,
  }) async {
    try {
      // 1. 加載天氣緩存數據
      try {
        await weatherProvider.fetchAllWeatherDataWithWarnings(); // 使用包含警告的完整方法
      } catch (e) {
        debugPrint('[初始化]天氣緩存數據加載失敗: $e');
      }

      // 2. 加載通告緩存數據
      try {
        // 通告Provider在構造時已自動加載緩存，這裡確保輪播Provider被正確更新
        final carouselAnnouncements =
            announcementProvider.getCarouselAnnouncements();
        announcementCarouselProvider.setAppDataProvider(
            Provider.of<AppDataProvider>(context, listen: false));
        announcementCarouselProvider.setArrearProvider(arrearProvider);

        // 🔧 關鍵修復：設置回調函數，確保輪播組件能正常工作
        announcementCarouselProvider.setHomeButtonCallback(() {
          announcementCarouselProvider.jumpToAnnouncementIndex(0);
        });

        announcementCarouselProvider.updateCarouselList(carouselAnnouncements);
      } catch (e) {
        debugPrint('[初始化]通告緩存數據加載失敗: $e');
        // 即使失敗也要確保基本內容可用
        try {
          // 設置基本回調並更新空列表
          announcementCarouselProvider.setHomeButtonCallback(() {
            announcementCarouselProvider.jumpToAnnouncementIndex(0);
          });
          announcementCarouselProvider.updateCarouselList([]);
        } catch (fallbackError) {
          debugPrint('[初始化]通告輪播基本內容設置失敗: $fallbackError');
        }
      }

      // 3. 加載欠費緩存數據
      try {
        await arrearProvider.loadFromCache();
      } catch (e) {
        debugPrint('[初始化]欠費緩存數據加載失敗: $e');
      }

      debugPrint('[初始化]緩存初始化完成');
    } catch (e) {
      debugPrint('[初始化]緩存初始化過程中發生錯誤: $e');
    }
  }

  ///0b, 緊急模式下的緊急緩存初始化
  Future<void> _emergencyInitializeFromCache(
    AnnouncementProvider announcementProvider,
    ArrearProvider arrearProvider,
    WeatherProvider weatherProvider,
  ) async {
    try {
      debugPrint('[初始化]緊急模式：嘗試加載基本緩存數據...');

      // 1. 嘗試加載天氣緩存
      try {
        await weatherProvider.fetchAllWeatherDataWithWarnings();
        debugPrint('[初始化]緊急模式：天氣緩存已加載');
      } catch (e) {
        debugPrint('[初始化]緊急模式：天氣緩存加載失敗: $e');
      }

      // 2. 嘗試加載欠費緩存
      try {
        await arrearProvider.loadFromCache();
        debugPrint('[初始化]緊急模式：欠費緩存已加載');
      } catch (e) {
        debugPrint('[初始化]緊急模式：欠費緩存加載失敗: $e');
      }

      // 3. 嘗試設置基本的輪播組件
      try {
        final announcementCarouselProvider =
            Provider.of<AnnouncementCarouselProvider>(context, listen: false);

        // 設置基本依賴
        final appDataProvider =
            Provider.of<AppDataProvider>(context, listen: false);
        announcementCarouselProvider.setAppDataProvider(appDataProvider);
        announcementCarouselProvider.setArrearProvider(arrearProvider);

        // 🔧 緊急模式：設置緊急回調函數
        announcementCarouselProvider.setHomeButtonCallback(() {
          announcementCarouselProvider.jumpToAnnouncementIndex(0);
          debugPrint('[初始化] [緊急模式] 通过返回按钮跳转到主屏幕');
        });

        // 獲取緩存的通告數據
        final carouselAnnouncements =
            announcementProvider.getCarouselAnnouncements();
        announcementCarouselProvider.updateCarouselList(carouselAnnouncements);

        debugPrint('[初始化]緊急模式：輪播組件已設置，通告數量: ${carouselAnnouncements.length}');
      } catch (e) {
        debugPrint('[初始化]緊急模式：輪播組件設置失敗: $e');
      }

      debugPrint('[初始化]緊急模式緩存初始化完成');
    } catch (e) {
      debugPrint('[初始化]緊急模式緩存初始化失敗: $e');
    }
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
