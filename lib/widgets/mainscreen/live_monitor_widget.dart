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
  final bool disableAutoInit; // 🔧 新增：禁用自动初始化，用于预加载场景

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
    with AutomaticKeepAliveClientMixin {
  List<WebViewController>? _controllers;
  final List<bool> _loadingStates = [true, true, true, true];
  bool _isInitialized = false;
  bool _isDisposed = false;

  // 公開getter供Provider訪問
  bool get isInitialized => _isInitialized;
  bool get isDisposed => _isDisposed;

  // 用户选择的监控URL和名称
  List<String> _streamUrls = [];
  List<String> _streamNames = [];
  bool _hasUserSelection = false;

  @override
  bool get wantKeepAlive => !_isDisposed && _isInitialized;

  @override
  void initState() {
    super.initState();
    // 先加载用户选择的监控通道
    _loadSelectedChannels().then((_) {
      // 🔧 修复：立即初始化，不等待PostFrameCallback，加快显示速度
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
              // 根据保存的通道选择获取对应的URL
              for (final orangepi in monitorResponse.data.orangepis) {
                for (int i = 0; i < orangepi.urls.length; i++) {
                  final channelKey = '${orangepi.orangepi_id}_channel${i + 1}';
                  if (savedChannels.contains(channelKey)) {
                    selectedUrls.add(orangepi.urls[i]);
                    selectedNames
                        .add('${orangepi.orangepi_name}-channel${i + 1}');
                  }
                }
              }
              debugPrint(
                  '[LiveMonitor] ✅ 成功加载用户选择的监控通道: ${selectedNames.length}个');
            }
          }
        } catch (e) {
          debugPrint('[LiveMonitor] 加载监控数据失败: $e');
        }

        if (selectedUrls.isNotEmpty) {
          setState(() {
            _streamUrls = selectedUrls.take(4).toList(); // 最多取4个
            _streamNames = selectedNames.take(4).toList();
            _hasUserSelection = true;
          });
          debugPrint('[LiveMonitor] ✅ 成功加载用户选择的监控通道: ${selectedNames.length}个');
        } else {
          // 如果没有找到用户选择的URL，设置为无选择状态
          setState(() {
            _streamUrls = [];
            _streamNames = [];
            _hasUserSelection = false;
          });
          debugPrint('[LiveMonitor] ⚠️ 未找到用户选择的监控通道');
        }
      } else {
        // 没有保存的选择，设置为无选择状态
        setState(() {
          _streamUrls = [];
          _streamNames = [];
          _hasUserSelection = false;
        });
        debugPrint('[LiveMonitor] ℹ️ 没有用户选择的监控通道');
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
    if (_isInitialized || _isDisposed || !mounted || !_hasUserSelection) return;

    debugPrint('[LiveMonitor] 🚀 開始初始化4個WebView控制器...');
    debugPrint('[LiveMonitor] 📹 使用监控URL: $_streamUrls');

    _controllers = List.generate(
      4,
      (index) {
        final controller = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setBackgroundColor(Colors.black);

        // 🔧 关键：为 Android 平台启用 WebRTC 和媒体播放支持
        if (Platform.isAndroid) {
          final androidController =
              controller.platform as AndroidWebViewController;
          // 启用媒体自动播放（不需要用户交互）
          androidController.setMediaPlaybackRequiresUserGesture(false);
          // 注意：WebRTC 权限请求会在 onPermissionRequest 回调中处理
          debugPrint('[LiveMonitor] ✅ Android WebView[$index] 已启用媒体自动播放');
        }

        controller.setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (String url) {
              if (mounted && !_isDisposed) {
                setState(() => _loadingStates[index] = true);
              }
            },
            onPageFinished: (String url) async {
              if (mounted && !_isDisposed) {
                setState(() => _loadingStates[index] = false);
              }
              debugPrint('[LiveMonitor] ✅ WebView[$index] 加載完成');

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
                  style.textContent = \`
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
              debugPrint(
                  '[LiveMonitor] ⚠️ WebView[$index] 錯誤: ${error.description}');
            },
          ),
        );

        return controller;
      },
    );

    // 🔧 优化：并行加载所有WebView，不使用延迟，最快速度初始化
    final loadFutures = <Future>[];
    for (int i = 0; i < _controllers!.length; i++) {
      if (!mounted || _isDisposed) break;

      if (mounted && !_isDisposed) {
        // 并行发起所有加载请求
        loadFutures
            .add(_controllers![i].loadRequest(Uri.parse(_streamUrls[i])));
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
      debugPrint('[LiveMonitor] ✅ 所有WebView初始化完成');
      widget.onInitialized?.call();
      updateKeepAlive();
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

  ///2, 刷新所有視頻流
  void _refreshAll() {
    if (_controllers == null) return;
    for (var controller in _controllers!) {
      controller.reload();
    }
  }

  ///3, 刷新监控通道（重新加载用户选择的通道）
  Future<void> refreshMonitorChannels() async {
    debugPrint('[LiveMonitor] 🔄 刷新监控通道...');

    // 先释放当前的WebView
    _isDisposed = true;
    _isInitialized = false;
    _controllers?.clear();
    _controllers = null;

    // 重置加载状态
    for (int i = 0; i < _loadingStates.length; i++) {
      _loadingStates[i] = true;
    }

    // 重新加载用户选择的通道
    await _loadSelectedChannels();

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

  @override
  void dispose() {
    _isDisposed = true;
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
            // 🔧 修复：根据顶部广告区域的实际高度动态计算childAspectRatio
            // 顶部广告高度通常是固定的，我们需要让2x2的格子能完整显示
            // 每个格子的宽度 = (总宽度 - padding - spacing) / 2
            // 每个格子的高度 = (总高度 - padding - spacing) / 2
            final gridWidth =
                (constraints.maxWidth - 4 - 2) / 2; // padding(2*2) + spacing(2)
            final gridHeight = (constraints.maxHeight - 4 - 2) / 2;
            final aspectRatio = gridWidth / gridHeight;

            return GridView.builder(
              padding: const EdgeInsets.all(2),
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 2,
                mainAxisSpacing: 2,
                childAspectRatio: aspectRatio,
              ),
              itemCount: 4,
              itemBuilder: (context, index) {
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
