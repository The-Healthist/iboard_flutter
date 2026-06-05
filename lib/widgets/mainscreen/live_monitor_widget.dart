import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:iboard_app/models/monitor_models.dart';
import 'package:iboard_app/providers/app_data_provider.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;

///實時監控Widget - 四宮格方案
///可作為頂部廣告輪播的一部分
///支持懶加載和資源釋放
class LiveMonitorWidget extends StatefulWidget {
  final bool autoPlay;
  final VoidCallback? onInitialized;
  final bool disableAutoInit; //  新增：禁用自动初始化，用于预加载场景

  const LiveMonitorWidget({
    super.key,
    this.autoPlay = true,
    this.onInitialized,
    this.disableAutoInit = false, // 默认自动初始化
  });

  @override
  State<LiveMonitorWidget> createState() => LiveMonitorWidgetState();
}

class LiveMonitorWidgetState extends State<LiveMonitorWidget>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  List<WebViewController>? _controllers;
  late List<bool> _loadingStates;
  bool _isInitialized = false;
  bool _isDisposed = false;

  // 公開getter供Provider訪問
  bool get isInitialized => _isInitialized;
  bool get isDisposed => _isDisposed;

  // 用户选择的监控URL和名称
  List<String> _streamUrls = [];
  List<String> _streamNames = [];
  bool _hasUserSelection = false;
  MonitorLayoutType _layoutType = MonitorLayoutType.grid4;

  // 保存上次的配置，用于检测变化
  List<String>? _lastSavedChannels;
  String? _lastSavedLayout;

  ///布局类型

  // =====  健康检查相关字段 =====
  late List<DateTime?> _lastFrameTime; // 每个流最后一帧时间
  late List<int> _frameErrorCount; // 每个流的错误计数
  late List<String> _lastErrorReason; // 每个流的最后错误原因
  late List<bool> _isRetrying; //  新增：每个流是否正在重试
  late List<DateTime?> _lastRetryTime; //  新增：每个流上次重试时间
  Timer? _forceRefreshTimer; // 定期强制刷新定时器
  static const int _maxErrorCount = 3; // 最大错误次数阈值（提高到3次，避免误判）
  static const Duration _retryDelay = Duration(seconds: 5); //  新增：重试延迟时间
  static const Duration _retryMinInterval =
      Duration(seconds: 15); //  新增：最小重试间隔，避免频繁重试

  @override
  bool get wantKeepAlive => !_isDisposed && _isInitialized;

  @override
  void initState() {
    super.initState();
    // 添加应用生命周期观察者
    WidgetsBinding.instance.addObserver(this);

    // 初始化加载状态列表（默认4格）
    _loadingStates = List.filled(4, true);

    // 初始化健康检查相关字段
    _lastFrameTime = List.filled(4, null);
    _frameErrorCount = List.filled(4, 0);
    _lastErrorReason = List.filled(4, '');
    _isRetrying = List.filled(4, false);
    _lastRetryTime = List.filled(4, null);

    // 先加载用户选择的监控通道
    _loadSelectedChannels().then((_) {
      //  修复：立即初始化，不等待PostFrameCallback，加快显示速度
      if (!widget.disableAutoInit) {
        // 延迟50ms，让Widget先完成基础渲染
        Future.delayed(const Duration(milliseconds: 50), () {
          if (mounted && !_isDisposed) {
            initializeWebViews();
          }
        });
      }
    });
  }

  ///1, 加载用户选择的监控通道
  Future<void> _loadSelectedChannels() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedChannels = prefs.getStringList('monitor_selected_channels');
      final savedApiUrl = prefs.getString('monitor_api_url');
      final savedLayout = prefs.getString('monitor_layout_type');

      // 加载布局类型
      _layoutType = MonitorLayoutType.fromString(savedLayout ?? 'grid4');

      // 从AppDataProvider获取大厦ismartid
      String? ismartId;
      try {
        // 尝试从AppDataProvider获取ismartid
        final appDataProvider =
            Provider.of<AppDataProvider>(context, listen: false);
        ismartId = appDataProvider.settingsModel?.building.ismartId;
      } catch (e) {
        debugPrint('[LiveMonitor] 获取AppDataProvider失败: $e');
      }

      if (savedChannels != null &&
          savedChannels.isNotEmpty &&
          ismartId != null) {
        // 从保存的channelKey解析出URL信息
        // channelKey格式: "orangepiId_channelName"
        final List<String> selectedUrls = [];
        final List<String> selectedNames = [];

        // 使用用户保存的API地址或默认地址
        final apiUrl =
            savedApiUrl ?? 'http://ajlive.sunofw.cn:32001/api/auth/public';

        // 重新获取监控数据以得到最新的URL
        try {
          final response = await http.post(
            Uri.parse(apiUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(MonitorRequest(
              ismartId: ismartId,
              isStaff: true,
            ).toJson()),
          );

          if (response.statusCode == 200) {
            final monitorResponse =
                MonitorResponse.fromJson(jsonDecode(response.body));
            if (monitorResponse.success) {
              // 根据保存的通道选择获取对应的URL（直接使用原始认证URL）
              for (final orangepi in monitorResponse.data.orangepis) {
                for (int i = 0; i < orangepi.urls.length; i++) {
                  final channelKey = '${orangepi.orangepi_id}_channel${i + 1}';
                  if (savedChannels.contains(channelKey)) {
                    selectedUrls.add(orangepi.urls[i]);
                    selectedNames
                        .add('${orangepi.orangepi_name}-channel${i + 1}');
                    debugPrint('[LiveMonitor]  使用原始认证URL: ${orangepi.urls[i]}');
                  }
                }
              }
              debugPrint(
                  '[LiveMonitor]  成功加载用户选择的监控通道: ${selectedNames.length}个');
            }
          }
        } catch (e) {
          debugPrint('[LiveMonitor] 加载监控数据失败: $e');
        }

        if (selectedUrls.isNotEmpty) {
          final actualCount = _layoutType.count;
          setState(() {
            _streamUrls = selectedUrls.take(actualCount).toList();
            _streamNames = selectedNames.take(actualCount).toList();
            _hasUserSelection = true;
            _lastSavedChannels = savedChannels;
            _lastSavedLayout = savedLayout;
            // 根据实际布局重新初始化健康检查相关字段
            _loadingStates = List.filled(actualCount, true);
            _lastFrameTime = List.filled(actualCount, null);
            _frameErrorCount = List.filled(actualCount, 0);
            _lastErrorReason = List.filled(actualCount, '');
            _isRetrying = List.filled(actualCount, false);
            _lastRetryTime = List.filled(actualCount, null);
          });
          debugPrint(
              '[LiveMonitor]  加载监控通道: ${_streamUrls.length}个, 布局: $_layoutType');
        } else {
          // 没有保存的选择，设置为无选择状态
          setState(() {
            _streamUrls = [];
            _streamNames = [];
            _hasUserSelection = false;
          });
          debugPrint('[LiveMonitor] ℹ 没有用户选择的监控通道');
        }
      } else {
        // 没有保存的选择，设置为无选择状态
        setState(() {
          _streamUrls = [];
          _streamNames = [];
          _hasUserSelection = false;
        });
        debugPrint('[LiveMonitor] ℹ 没有用户选择的监控通道');
      }
    } catch (e) {
      debugPrint('[LiveMonitor] 加载用户选择失败: $e');
      // 出错时设置为无选择状态
      setState(() {
        _streamUrls = [];
        _streamNames = [];
        _hasUserSelection = false;
      });
    }
  }

  ///2, 初始化所有WebView控制器(公開方法供Provider調用)
  Future<void> initializeWebViews() async {
    if (_isInitialized || _isDisposed || !mounted) return;

    // 如果没有用户选择，显示黑屏或错误信息
    if (!_hasUserSelection) {
      debugPrint('[LiveMonitor] ℹ 没有用户选择的监控通道，显示黑屏');
      _isInitialized = true;
      if (mounted) {
        setState(() {});
      }
      return;
    }

    debugPrint('[LiveMonitor]  開始初始化WebView控制器...');
    debugPrint('[LiveMonitor]  布局类型: ${_layoutType.label}');
    debugPrint('[LiveMonitor]  使用监控URL: $_streamUrls');

    // 初始化加载状态列表和健康检查字段（防止布局切换时数组长度不一致）
    _loadingStates = List.filled(_layoutType.count, true);
    _lastFrameTime = List.filled(_layoutType.count, null);
    _frameErrorCount = List.filled(_layoutType.count, 0);
    _lastErrorReason = List.filled(_layoutType.count, '');

    _controllers = List.generate(
      _layoutType.count,
      (index) {
        final controller = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setBackgroundColor(Colors.black);

        //  关键：为 Android 平台启用 WebRTC 和媒体播放支持
        if (Platform.isAndroid) {
          final androidController =
              controller.platform as AndroidWebViewController;
          // 启用媒体自动播放（不需要用户交互）
          androidController.setMediaPlaybackRequiresUserGesture(false);

          // 注意：混合内容已通过 AndroidManifest.xml 中的 usesCleartextTraffic="true" 启用
          // 注意：WebRTC 权限请求会在 onPermissionRequest 回调中处理
          debugPrint('[LiveMonitor]  Android WebView[$index] 已启用媒体自动播放');
        }

        controller.setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (String url) {
              if (mounted && !_isDisposed && index < _loadingStates.length) {
                setState(() => _loadingStates[index] = true);
              }
              debugPrint('[LiveMonitor]  WebView[$index] 开始加载: $url');
            },
            onPageFinished: (String url) async {
              if (mounted && !_isDisposed) {
                setState(() => _loadingStates[index] = false);
              }
              debugPrint('[LiveMonitor]  WebView[$index] 加載完成: $url');

              // 專業方式禁用全屏功能
              await _controllers![index].runJavaScript('''
                (function() {
                  'use strict';
                  
                  let fullscreenCheckInterval = null;
                  
                  // 1. 強制退出全屏的函數
                  const forceExitFullscreen = function() {
                    if (document.fullscreenElement || 
                        document.webkitFullscreenElement || 
                        document.mozFullScreenElement || 
                        document.msFullscreenElement) {
                      
                      console.warn('[Fullscreen Blocked] Force exiting fullscreen');
                      
                      try {
                        if (document.exitFullscreen) {
                          document.exitFullscreen();
                        } else if (document.webkitExitFullscreen) {
                          document.webkitExitFullscreen();
                        } else if (document.mozCancelFullScreen) {
                          document.mozCancelFullScreen();
                        } else if (document.msExitFullscreen) {
                          document.msExitFullscreen();
                        }
                      } catch(e) {
                        console.error('[Fullscreen Blocked] Error exiting:', e);
                      }
                    }
                  };
                  
                  // 2. 攔截所有點擊事件（最高優先級）
                  document.addEventListener('click', function(e) {
                    const target = e.target;
                    // 檢查是否點擊了全屏按鈕
                    if (target.tagName === 'BUTTON' || target.closest('button')) {
                      const button = target.tagName === 'BUTTON' ? target : target.closest('button');
                      const classList = button.className.toLowerCase();
                      const ariaLabel = (button.getAttribute('aria-label') || '').toLowerCase();
                      const title = (button.getAttribute('title') || '').toLowerCase();
                      
                      if (classList.includes('fullscreen') || 
                          ariaLabel.includes('fullscreen') || 
                          title.includes('fullscreen')) {
                        e.preventDefault();
                        e.stopPropagation();
                        e.stopImmediatePropagation();
                        console.warn('[Fullscreen Blocked] Fullscreen button click prevented');
                        return false;
                      }
                    }
                  }, true);
                  
                  // 3. 監聽fullscreenchange事件並立即退出
                  const fullscreenEvents = [
                    'fullscreenchange',
                    'webkitfullscreenchange', 
                    'mozfullscreenchange',
                    'MSFullscreenChange'
                  ];
                  
                  fullscreenEvents.forEach(function(eventName) {
                    document.addEventListener(eventName, function(e) {
                      forceExitFullscreen();
                    }, true);
                  });
                  
                  // 4. 攔截beforefullscreenchange事件
                  document.addEventListener('fullscreenchange', function(e) {
                    e.preventDefault();
                    e.stopPropagation();
                    forceExitFullscreen();
                  }, true);
                  
                  // 5. 使用setInterval持續檢查全屏狀態（最強防線）
                  fullscreenCheckInterval = setInterval(function() {
                    forceExitFullscreen();
                  }, 100); // 每100ms檢查一次
                  
                  // 6. CSS隱藏全屏按鈕和音量控制
                  const style = document.createElement('style');
                  style.textContent = `
                    /* 隱藏全屏按鈕 */
                    button[class*="fullscreen" i],
                    button[aria-label*="fullscreen" i],
                    button[title*="fullscreen" i],
                    video::-webkit-media-controls-fullscreen-button {
                      display: none !important;
                      visibility: hidden !important;
                      pointer-events: none !important;
                    }
                    
                    /* 隱藏音量/靜音按鈕 - 全面覆蓋所有可能的選擇器 */
                    button[class*="mute" i],
                    button[class*="volume" i],
                    button[class*="sound" i],
                    button[class*="audio" i],
                    button[aria-label*="mute" i],
                    button[aria-label*="volume" i],
                    button[aria-label*="sound" i],
                    button[aria-label*="audio" i],
                    button[title*="mute" i],
                    button[title*="volume" i],
                    button[title*="sound" i],
                    button[title*="audio" i],
                    [class*="mute" i],
                    [class*="volume" i],
                    [class*="sound" i],
                    div[class*="volume" i],
                    div[class*="mute" i],
                    input[type="range"],
                    video::-webkit-media-controls-mute-button,
                    video::-webkit-media-controls-volume-slider,
                    video::-webkit-media-controls-volume-control-container,
                    video::-moz-media-controls-mute-button,
                    video::-moz-media-controls-volume-slider {
                      display: none !important;
                      visibility: hidden !important;
                      pointer-events: none !important;
                      opacity: 0 !important;
                      width: 0 !important;
                      height: 0 !important;
                    }
                  \`;
                  document.head.appendChild(style);
                  
                  // 7. 直接禁用video的原生controls（關鍵！）
                  setTimeout(function() {
                    const disableVideoControls = function() {
                      const videos = document.querySelectorAll('video');
                      console.log('[Video Controls] 找到video元素:', videos.length);
                      
                      videos.forEach(function(video, index) {
                        // 移除controls屬性
                        video.removeAttribute('controls');
                        video.controls = false;
                        
                        // 鎖定controls屬性（防止被重新啟用）
                        Object.defineProperty(video, 'controls', {
                          get: function() { return false; },
                          set: function(value) { 
                            console.warn('[Video Controls Blocked] Attempt to enable controls blocked'); 
                          },
                          configurable: false
                        });
                        
                        console.log('[Video Controls] Video #' + index + ' controls已禁用');
                      });
                    };
                    
                    // 立即執行
                    disableVideoControls();
                    
                    // 延遲後再次執行（確保動態加載的video也被處理）
                    setTimeout(disableVideoControls, 500);
                    setTimeout(disableVideoControls, 1000);
                    setTimeout(disableVideoControls, 2000);
                    
                    // 使用MutationObserver監聽新添加的video元素
                    const observer = new MutationObserver(function(mutations) {
                      let hasNewVideo = false;
                      mutations.forEach(function(mutation) {
                        mutation.addedNodes.forEach(function(node) {
                          if (node.nodeType === 1 && node.tagName === 'VIDEO') {
                            hasNewVideo = true;
                          }
                        });
                      });
                      if (hasNewVideo) {
                        console.log('[Video Controls] 檢測到新video元素，禁用controls');
                        disableVideoControls();
                      }
                    });
                    
                    observer.observe(document.documentElement, {
                      childList: true,
                      subtree: true
                    });
                  }, 100);
                  
                  // 7. 攔截雙擊事件
                  document.addEventListener('dblclick', function(e) {
                    if (e.target.tagName === 'VIDEO' || e.target.closest('video')) {
                      e.preventDefault();
                      e.stopPropagation();
                      e.stopImmediatePropagation();
                      console.warn('[Fullscreen Blocked] Video double-click prevented');
                      return false;
                    }
                  }, true);
                  
                  // 8. 攔截鍵盤快捷鍵
                  document.addEventListener('keydown', function(e) {
                    if ((e.key === 'f' || e.key === 'F') && !e.shiftKey && !e.altKey) {
                      const activeElement = document.activeElement;
                      if (activeElement && activeElement.tagName === 'VIDEO') {
                        e.preventDefault();
                        e.stopPropagation();
                        e.stopImmediatePropagation();
                        console.warn('[Fullscreen Blocked] Keyboard shortcut prevented');
                        return false;
                      }
                    }
                  }, true);
                  
                  console.log('[Fullscreen Disabled] Aggressive fullscreen blocking initialized');
                })();
              ''');
            },
            onWebResourceError: (WebResourceError error) {
              debugPrint('[LiveMonitor]  WebView[$index] 资源错误:');
              debugPrint('  - 错误类型: ${error.errorType}');
              debugPrint('  - 错误码: ${error.errorCode}');
              debugPrint('  - 描述: ${error.description}');
              debugPrint('  - URL: ${error.url}');

              // 记录到健康检查
              if (index < _frameErrorCount.length) {
                _frameErrorCount[index]++;
                _lastErrorReason[index] = 'Network error: ${error.description}';
              }

              //  检测严重错误并自动重试
              // 只对主页面加载错误触发重试（URL包含channel且不包含whep/api）
              final errorUrl = error.url ?? '';
              final isMainPageError = errorUrl.contains('channel') &&
                  !errorUrl.contains('/whep/') &&
                  !errorUrl.contains('/api/');

              final isSevereError =
                  error.description.contains('ERR_EMPTY_RESPONSE') ||
                      error.description.contains('ERR_CONNECTION_RESET') ||
                      error.description.contains('ERR_CONNECTION_REFUSED') ||
                      error.description.contains('ERR_NAME_NOT_RESOLVED') ||
                      error.description.contains('ERR_INTERNET_DISCONNECTED') ||
                      error.description.contains('ERR_TIMED_OUT');

              if (isMainPageError && isSevereError) {
                _scheduleAutoRetry(index);
              }
            },
            onHttpError: (HttpResponseError error) {
              debugPrint('[LiveMonitor]  WebView[$index] HTTP错误:');
              debugPrint('  - 状态码: ${error.response?.statusCode}');
              debugPrint('  - URL: ${error.response?.uri}');
            },
          ),
        );

        return controller;
      },
    );

    //  优化：并行加载所有WebView，不使用延迟，最快速度初始化
    final loadFutures = <Future>[];
    for (int i = 0; i < _controllers!.length; i++) {
      if (!mounted || _isDisposed) break;

      if (mounted && !_isDisposed && i < _streamUrls.length) {
        debugPrint('[LiveMonitor]  准备加载流[$i]: ${_streamUrls[i]}');
        // 并行发起所有加载请求
        try {
          loadFutures.add(
              _controllers![i].loadRequest(Uri.parse(_streamUrls[i])).timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              debugPrint('[LiveMonitor]  流[$i] 加载超时 (15秒)');
              throw TimeoutException('WebView load timeout');
            },
          ));
        } catch (e) {
          debugPrint('[LiveMonitor]  流[$i] 加载请求失败: $e');
        }
      }
    }

    // 等待所有加载请求完成
    if (loadFutures.isNotEmpty) {
      await Future.wait(loadFutures, eagerError: false);
    }

    if (mounted && !_isDisposed) {
      setState(() {
        _isInitialized = true;
      });
      debugPrint('[LiveMonitor]  所有WebView初始化完成');
      widget.onInitialized?.call();
      updateKeepAlive();

      //  禁用Flutter健康检查 - WebRTC播放器HTML已内置完整重连逻辑
      // 后端每30秒检查，90秒无数据自动重连，无需Flutter层干预
      // _startVideoHealthCheck();

      // 只保留定期刷新作为保底机制（10分钟）
      _startPeriodicRefresh();
    }
  }

  ///1a, 手動釋放所有WebView資源
  Future<void> releaseResources() async {
    if (_isDisposed || _controllers == null) return;

    debugPrint('[LiveMonitor]  開始釋放WebView資源...');

    _isDisposed = true;

    // 清空控制器,触发WebView销毁
    if (_controllers != null) {
      try {
        _controllers!.clear();
        _controllers = null;
      } catch (e) {
        debugPrint('[LiveMonitor]  釋放WebView時出錯: $e');
      }
    }

    if (mounted) {
      setState(() {
        _isInitialized = false;
      });
      updateKeepAlive();
    }

    debugPrint('[LiveMonitor]  WebView資源釋放完成');
  }

  ///2b,  调度自动重试（延迟重新加载单个WebView）
  void _scheduleAutoRetry(int index) {
    if (!mounted || _isDisposed || _controllers == null) return;
    if (index < 0 || index >= _controllers!.length) return;
    if (index >= _isRetrying.length) return;

    // 检查是否正在重试
    if (_isRetrying[index]) {
      debugPrint('[LiveMonitor]  流[$index] 已在重试队列中，跳过');
      return;
    }

    // 检查最小重试间隔
    final lastRetry = _lastRetryTime[index];
    if (lastRetry != null) {
      final elapsed = DateTime.now().difference(lastRetry);
      if (elapsed < _retryMinInterval) {
        debugPrint(
            '[LiveMonitor]  流[$index] 距离上次重试不足${_retryMinInterval.inSeconds}秒，跳过');
        return;
      }
    }

    _isRetrying[index] = true;
    debugPrint('[LiveMonitor]  流[$index] 将在${_retryDelay.inSeconds}秒后自动重试...');

    Future.delayed(_retryDelay, () async {
      if (!mounted || _isDisposed || _controllers == null) {
        if (index < _isRetrying.length) _isRetrying[index] = false;
        return;
      }
      if (index >= _controllers!.length || index >= _streamUrls.length) {
        if (index < _isRetrying.length) _isRetrying[index] = false;
        return;
      }

      try {
        debugPrint('[LiveMonitor]  流[$index] 开始自动重试加载...');
        _lastRetryTime[index] = DateTime.now();

        // 重新加载WebView
        await _controllers![index].loadRequest(Uri.parse(_streamUrls[index]));

        // 重置错误计数
        _frameErrorCount[index] = 0;
        _lastErrorReason[index] = '';
        _lastFrameTime[index] = DateTime.now();

        debugPrint('[LiveMonitor]  流[$index] 自动重试完成');
      } catch (e) {
        debugPrint('[LiveMonitor]  流[$index] 自动重试失败: $e');
      } finally {
        if (index < _isRetrying.length) {
          _isRetrying[index] = false;
        }
      }
    });
  }

  ///2c,  检查是否有错误并刷新（供外部调用）
  Future<void> checkAndRefreshIfHasErrors() async {
    if (!mounted || _isDisposed || _controllers == null) return;

    bool hasErrors = false;
    for (int i = 0;
        i < _frameErrorCount.length && i < _controllers!.length;
        i++) {
      if (_frameErrorCount[i] >= _maxErrorCount) {
        hasErrors = true;
        debugPrint('[LiveMonitor]  流[$i] 错误计数达到阈值: ${_frameErrorCount[i]}');
        break;
      }
    }

    if (hasErrors) {
      debugPrint('[LiveMonitor]  检测到错误，触发刷新...');
      await refreshMonitorChannels();
    } else {
      debugPrint('[LiveMonitor]  无严重错误，无需刷新');
    }
  }

  ///3, 刷新监控通道（重新加载用户选择的通道）
  Future<void> refreshMonitorChannels() async {
    debugPrint('[LiveMonitor]  刷新监控通道...');

    // 停止现有的健康检查
    _stopVideoHealthCheck();

    // 先释放当前的WebView
    _isDisposed = true;
    _isInitialized = false;
    _controllers?.clear();
    _controllers = null;

    // 重新加载用户选择的通道
    await _loadSelectedChannels();

    // 根据新的布局类型初始化加载状态和健康检查字段
    if (_hasUserSelection) {
      _loadingStates = List.filled(_layoutType.count, true);
      _lastFrameTime = List.filled(_layoutType.count, null);
      _frameErrorCount = List.filled(_layoutType.count, 0);
      _lastErrorReason = List.filled(_layoutType.count, '');
      _isRetrying = List.filled(_layoutType.count, false);
      _lastRetryTime = List.filled(_layoutType.count, null);
    }

    // 重置状态
    if (mounted) {
      setState(() {
        _isDisposed = false;
        _isInitialized = false;
      });

      // 重新初始化WebView（如果有用户选择）
      if (_hasUserSelection) {
        await initializeWebViews();
      }
    }
  }

  ///3a,  重载监控配置并重新初始化（由外部调用，例如用户更新监控设置后）
  Future<void> reloadMonitorConfig() async {
    debugPrint('[LiveMonitor]  重载监控配置...');
    debugPrint(
        '[LiveMonitor]   - mounted: $mounted, _isDisposed: $_isDisposed, _isInitialized: $_isInitialized');
    debugPrint(
        '[LiveMonitor]   - 当前布局: ${_layoutType.label}, 通道数: ${_streamUrls.length}');

    if (!mounted) {
      debugPrint('[LiveMonitor]  Widget未mounted，取消刷新');
      return;
    }

    // 直接调用刷新监控通道方法
    debugPrint('[LiveMonitor]  开始刷新监控通道...');
    await refreshMonitorChannels();
    debugPrint('[LiveMonitor]  监控配置重载完成');
  }

  ///3b,  检查配置是否有变化（用于判断是否需要刷新）
  Future<bool> hasConfigChanged() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedChannels = prefs.getStringList('monitor_selected_channels');
      final savedLayout = prefs.getString('monitor_layout_type');

      // 比较通道和布局是否有变化
      final channelsChanged = (savedChannels?.join(',') ?? '') !=
          (_lastSavedChannels?.join(',') ?? '');
      final layoutChanged = savedLayout != _lastSavedLayout;

      return channelsChanged || layoutChanged;
    } catch (e) {
      debugPrint('[LiveMonitor] 检查配置变化失败: $e');
      return false;
    }
  }

  ///4,  启动定期刷新（仅保底机制，信任后端重连）
  void _startPeriodicRefresh() {
    if (_forceRefreshTimer != null) return;

    debugPrint('[LiveMonitor]  启动定期刷新 (间隔: 10分钟)，信任WebRTC内置重连逻辑...');

    // 只启动定期刷新，不做健康检查（后端HTML已有完整重连机制）
    _forceRefreshTimer = Timer.periodic(const Duration(minutes: 10), (_) async {
      if (!mounted || _isDisposed || _controllers == null) {
        _forceRefreshTimer?.cancel();
        _forceRefreshTimer = null;
        return;
      }

      debugPrint('[LiveMonitor]  定期刷新所有流（保底机制）...');
      await _performForceRefreshAll();
    });
  }

  ///5,  停止健康检查和定期刷新
  void _stopVideoHealthCheck() {
    _forceRefreshTimer?.cancel();
    _forceRefreshTimer = null;
    debugPrint('[LiveMonitor]  停止健康检查和定期刷新');
  }

  ///9,  获取健康检查统计信息
  Map<String, dynamic> getHealthStats() {
    return {
      'timestamp': DateTime.now().toIso8601String(),
      'total_streams': _streamUrls.length,
      'healthy_streams': _frameErrorCount.where((e) => e == 0).length,
      'streams': List.generate(
        _streamUrls.length,
        (i) => {
          'index': i,
          'url': _streamUrls[i],
          'name': _streamNames[i],
          'error_count': _frameErrorCount[i],
          'last_error': _lastErrorReason[i],
          'last_frame_time': _lastFrameTime[i]?.toIso8601String() ?? 'never',
          'status': _frameErrorCount[i] == 0
              ? 'healthy'
              : _frameErrorCount[i] < _maxErrorCount
                  ? 'degraded'
                  : 'unhealthy',
        },
      ),
    };
  }

  ///10, 公开方法：检查配置变化并刷新（供外部调用）
  Future<void> checkConfigAndRefresh() async {
    await _checkAndRefreshIfConfigChanged();
  }

  ///10a, 监听应用生命周期变化
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      debugPrint('[LiveMonitor]  应用恢复前台');
      _checkAndRefreshIfConfigChanged();
    }
  }

  ///11, 检查配置是否变化，如果变化则自动刷新
  Future<void> _checkAndRefreshIfConfigChanged() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentChannels = prefs.getStringList('monitor_selected_channels');
      final currentLayout = prefs.getString('monitor_layout_type');

      // 比较配置是否变化
      final channelsChanged = !_listEquals(_lastSavedChannels, currentChannels);
      final layoutChanged = _lastSavedLayout != currentLayout;

      if (channelsChanged || layoutChanged) {
        debugPrint('[LiveMonitor]  检测到配置变化，自动刷新...');
        debugPrint('[LiveMonitor]   - 频道变化: $channelsChanged');
        debugPrint('[LiveMonitor]   - 布局变化: $layoutChanged');
        await refreshMonitorChannels();
      } else {
        debugPrint('[LiveMonitor]  配置未变化，无需刷新');
      }
    } catch (e) {
      debugPrint('[LiveMonitor]  检查配置变化时出错: $e');
    }
  }

  ///12,  比较两个列表是否相等（辅助方法）
  bool _listEquals(List<String>? a, List<String>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  ///13,  定期强制刷新所有流（保底机制，防止WebRTC连接长时间后失效）
  Future<void> _performForceRefreshAll() async {
    if (!mounted ||
        _isDisposed ||
        _controllers == null ||
        _controllers!.isEmpty) {
      return;
    }

    debugPrint('[LiveMonitor]  执行定期强制刷新（${_controllers!.length}个流）...');

    for (int i = 0; i < _controllers!.length; i++) {
      if (!mounted || _isDisposed) break;

      try {
        // 重新加载WebView
        await _controllers![i].reload();

        // 重置错误计数和状态（重要：避免刷新后立即误判）
        _frameErrorCount[i] = 0;
        _lastErrorReason[i] = '';
        _lastFrameTime[i] = DateTime.now(); // 设置当前时间作为基准

        debugPrint('[LiveMonitor]  流[$i] 强制刷新完成');

        // 延迟1秒，给WebView足够的加载时间
        await Future.delayed(const Duration(seconds: 1));
      } catch (e) {
        debugPrint('[LiveMonitor]  流[$i] 强制刷新失败: $e');
      }
    }

    debugPrint('[LiveMonitor]  所有流强制刷新完成，等待10秒后恢复健康检查');

    // 刷新完成后等待10秒，让所有流稳定后再进行健康检查
    await Future.delayed(const Duration(seconds: 10));
  }

  @override
  void dispose() {
    // 移除生命周期观察者
    WidgetsBinding.instance.removeObserver(this);

    _isDisposed = true;
    _stopVideoHealthCheck(); // 停止健康检查
    _controllers?.clear();
    _controllers = null;
    debugPrint('[LiveMonitor]  Widget已dispose');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isDisposed) {
      return _buildPlaceholder();
    }

    if (!_hasUserSelection) {
      return _buildNoSelectionPrompt();
    }

    if (!_isInitialized) {
      return _buildPlaceholder();
    }

    return _buildContent();
  }

  ///3, 構建實時監控內容
  Widget _buildContent() {
    if (_controllers == null || _isDisposed) {
      return _buildPlaceholder();
    }

    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black,
      child: RepaintBoundary(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columns = _layoutType.columns;
            if (columns == 0) {
              return const SizedBox.shrink();
            }
            const gridSpacing = 2.0;
            const gridPadding = 2.0;

            final gridWidth = (constraints.maxWidth -
                    (gridPadding * 2) -
                    (gridSpacing * (columns - 1))) /
                columns;
            final gridHeight = (constraints.maxHeight -
                    (gridPadding * 2) -
                    (gridSpacing * (_layoutType.rows - 1))) /
                _layoutType.rows;
            final aspectRatio = gridWidth / gridHeight;

            return GridView.builder(
              padding: EdgeInsets.all(gridPadding),
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: gridSpacing,
                mainAxisSpacing: gridSpacing,
                childAspectRatio: aspectRatio,
              ),
              itemCount: _layoutType.count,
              itemBuilder: (context, index) {
                // 如果索引超过实际的URL数量，显示黑屏
                if (index >= _streamUrls.length) {
                  return RepaintBoundary(
                    child: Container(
                      color: Colors.black,
                      child: Center(
                        child: Text(
                          '未使用',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.3),
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  );
                }

                return RepaintBoundary(
                  child: _CameraViewWidget(
                    controller: _controllers![index],
                    isLoading: _loadingStates[index],
                    streamName: _streamNames[index],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  ///4, 構建無選擇提示界面
  Widget _buildNoSelectionPrompt() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.grey.shade800,
            Colors.grey.shade900,
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.videocam_off_outlined,
              size: 64,
              color: Colors.white.withOpacity(0.6),
            ),
            const SizedBox(height: 16),
            Text(
              '尚未選擇監控通道',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Colors.white.withOpacity(0.9),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '請前往設置頁面選擇您要監控的通道',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  ///5, 構建占位符
  Widget _buildPlaceholder() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.grey.shade800,
            Colors.grey.shade900,
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.videocam_outlined,
              size: 48,
              color: Colors.white.withOpacity(0.6),
            ),
            const SizedBox(height: 12),
            Text(
              '正在載入實時監控...',
              style: TextStyle(
                fontSize: 16,
                color: Colors.white.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

///攝像頭視圖組件
class _CameraViewWidget extends StatelessWidget {
  final WebViewController controller;
  final bool isLoading;
  final String streamName;

  const _CameraViewWidget({
    required this.controller,
    required this.isLoading,
    required this.streamName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border.all(color: Colors.grey[800]!, width: 1),
      ),
      child: Stack(
        children: [
          WebViewWidget(controller: controller),
          if (isLoading)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '載入中...',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.8),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.circle,
                color: Colors.white,
                size: 6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
