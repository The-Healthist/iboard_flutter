// import 'dart:async';
// import 'dart:io';
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:video_player/video_player.dart';
// import 'package:logger/logger.dart';

// /// 视频类型枚举
// enum VideoType {
//   topAd, // 顶部广告视频
//   fullAd, // 全屏广告视频
// }

// /// 视频控制器元数据
// class VideoControllerWrapper {
//   final VideoPlayerController controller;
//   final String filePath;
//   final VideoType videoType;
//   DateTime lastUsed;
//   int useCount;
//   bool _isInUse; // 私有属性

//   // 构造函数
//   VideoControllerWrapper({
//     required this.controller,
//     required this.filePath,
//     required this.videoType,
//     required this.lastUsed,
//     this.useCount = 0,
//     bool isInUse = false,
//   }) : _isInUse = isInUse;

//   // Getter
//   bool get isInUse => _isInUse;

//   // Setter
//   set isInUse(bool value) {
//     _isInUse = value;
//   }
// }

// /// 增强型视频资源管理器
// class EnhancedVideoPoolManager {
//   static final Logger _logger = Logger();
//   static EnhancedVideoPoolManager? _instance;

//   // 视频控制器缓存
//   final Map<String, VideoControllerWrapper> _controllerCache = {};
//   static const int _maxCacheSize = 8; // 降低缓存大小以减少解码器压力
//   static const int _maxActiveDecoders = 3; // 最大同时活跃解码器数量
//   static const int _maxConcurrentPlaying = 2; // 最大同时播放视频数量

//   // 釋放中的鍵，避免重入
//   final Set<String> _releasingKeys = {};
//   // 記錄失敗文件，避免重複嘗試
//   final Set<String> _failedFiles = {};

//   // 解码器资源跟踪
//   int _activeDecoders = 0; // 当前活跃的解码器数量
//   int _playingControllers = 0; // 当前播放中的控制器数量
//   final Map<String, DateTime> _decoderUsageLog = {}; // 解码器使用记录

//   factory EnhancedVideoPoolManager() {
//     _instance ??= EnhancedVideoPoolManager._internal();
//     return _instance!;
//   }

//   EnhancedVideoPoolManager._internal();

//   /// 检查解码器资源是否可用
//   bool _isDecoderResourceAvailable() {
//     return _activeDecoders < _maxActiveDecoders;
//   }

//   /// 检查是否可以同时播放更多视频
//   bool _canPlayConcurrently() {
//     return _playingControllers < _maxConcurrentPlaying;
//   }

//   /// 获取解码器资源状态
//   Map<String, dynamic> _getDecoderResourceStatus() {
//     return {
//       'activeDecoders': _activeDecoders,
//       'maxActiveDecoders': _maxActiveDecoders,
//       'playingControllers': _playingControllers,
//       'maxConcurrentPlaying': _maxConcurrentPlaying,
//       'availableDecoders': _maxActiveDecoders - _activeDecoders,
//       'canCreateNew': _isDecoderResourceAvailable(),
//       'canPlayNew': _canPlayConcurrently(),
//     };
//   }

//   /// 分析设备硬件解码器能力
//   Map<String, dynamic> _analyzeHardwareCapability() {
//     return {
//       'platform':
//           Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : 'other'),
//       'estimatedMaxDecoders': Platform.isAndroid ? 4 : 6,
//       'recommendedMaxConcurrent': Platform.isAndroid ? 2 : 3,
//       'riskLevel': _getRiskLevel(),
//     };
//   }

//   /// 获取当前风险等级
//   String _getRiskLevel() {
//     if (_activeDecoders >= _maxActiveDecoders ||
//         _playingControllers >= _maxConcurrentPlaying) {
//       return 'high';
//     } else if (_activeDecoders >= _maxActiveDecoders * 0.7) {
//       return 'medium';
//     } else {
//       return 'low';
//     }
//   }

//   /// 强制释放最旧的解码器资源
//   Future<void> _forceReleaseOldestDecoder() async {
//     if (_controllerCache.isEmpty) return;

//     // 找到最旧且正在播放的控制器
//     final playingControllers = _controllerCache.entries
//         .where((entry) => entry.value.controller.value.isPlaying)
//         .toList();

//     if (playingControllers.isEmpty) return;

//     // 按最后使用时间排序，选择最旧的
//     playingControllers
//         .sort((a, b) => a.value.lastUsed.compareTo(b.value.lastUsed));
//     final oldest = playingControllers.first;

//     try {
//       await oldest.value.controller.pause();
//       _playingControllers--;
//       _decoderUsageLog[oldest.key] = DateTime.now();

//       debugPrint('🚨 强制释放最旧解码器: ${oldest.key} (剩余活跃: $_playingControllers)');
//     } catch (e) {
//       debugPrint('⚠️ 强制释放解码器失败: $e');
//     }
//   }

//   /// 獲取內存使用信息
//   String _getMemoryInfo() {
//     try {
//       // ProcessInfo.currentRss 在不同平台單位不同，嘗試多種轉換
//       final info = ProcessInfo.currentRss;
//       final maxInfo = ProcessInfo.maxRss;

//       double rssInMB, maxRssInMB;

//       // 如果數值很大，可能是bytes單位
//       if (info > 1000000) {
//         rssInMB = info / (1024 * 1024); // bytes -> MB
//         maxRssInMB = maxInfo / (1024 * 1024);
//       } else {
//         rssInMB = info / 1024; // KB -> MB
//         maxRssInMB = maxInfo / 1024;
//       }

//       // RSS內存通常比系統設置顯示值高20-60MB（正常現象）
//       return 'RSS內存: ${rssInMB.toStringAsFixed(1)}MB (峰值: ${maxRssInMB.toStringAsFixed(1)}MB) '
//           '解码器: $_activeDecoders/$_maxActiveDecoders, 播放: $_playingControllers/$_maxConcurrentPlaying, 緩存: ${_controllerCache.length}';
//     } catch (e) {
//       // Fallback：使用緩存數量作為內存負載指示
//       final cacheLoad = _controllerCache.length;
//       final estimatedMemory = (cacheLoad * 15).toString(); // 假設每個控制器約15MB
//       return '內存: ~${estimatedMemory}MB (緩存: ${cacheLoad}個控制器) '
//           '解码器: $_activeDecoders/$_maxActiveDecoders, 播放: $_playingControllers/$_maxConcurrentPlaying';
//     }
//   }

//   /// 檢查內存是否過高
//   bool _isMemoryHigh() {
//     try {
//       final info = ProcessInfo.currentRss;
//       double rssInMB;

//       // 根據數值大小判斷單位並轉換
//       if (info > 1000000) {
//         rssInMB = info / (1024 * 1024); // bytes -> MB
//       } else {
//         rssInMB = info / 1024; // KB -> MB
//       }

//       // 考虑到RSS比系统显示值高20-60MB，设置合理阈值600MB
//       // 这样实际系统显示约580-640MB时触发清理
//       return rssInMB > 600;
//     } catch (e) {
//       // 無法獲取內存時，根據緩存數量判斷
//       return _controllerCache.length > 8;
//     }
//   }

//   /// 获取视频控制器（优先使用缓存）
//   Future<VideoPlayerController?> getController({
//     required String filePath,
//     required VideoType videoType,
//     bool isNetwork = false,
//     bool autoPlay = false,
//     bool looping = false,
//     VoidCallback? onError,
//   }) async {
//     // 优先检查黑名单，快速失败避免重复尝试和崩溃
//     if (_failedFiles.contains(filePath)) {
//       debugPrint('🚫 文件在黑名單中，直接跳過: $filePath');
//       onError?.call(); // 立即通知失败
//       return null;
//     }

//     // 检查解码器资源是否充足
//     if (autoPlay && !_canPlayConcurrently()) {
//       debugPrint('🚨 播放资源不足，当前播放: $_playingControllers/$_maxConcurrentPlaying');
//       await _forceReleaseOldestDecoder();

//       if (!_canPlayConcurrently()) {
//         debugPrint('❌ 仍无法获取播放资源，拒绝请求');
//         onError?.call();
//         return null;
//       }
//     }

//     // 生成唯一标识键
//     final key = _generateControllerKey(filePath, videoType);
//     final decoderStatus = _getDecoderResourceStatus();

//     debugPrint('🎯 請求控制器: $key (autoPlay: $autoPlay) ${_getMemoryInfo()}');
//     debugPrint(
//         '🎮 解码器状态: ${decoderStatus['activeDecoders']}/${decoderStatus['maxActiveDecoders']} 活跃, 播放: ${decoderStatus['playingControllers']}/${decoderStatus['maxConcurrentPlaying']}');

//     // 检查是否已有缓存的控制器
//     if (_controllerCache.containsKey(key)) {
//       final wrapper = _controllerCache[key]!;
//       final controller = wrapper.controller;

//       debugPrint(
//           '📋 發現緩存控制器: $key (isInUse: ${wrapper.isInUse}, useCount: ${wrapper.useCount})');

//       try {
//         // 检查控制器是否有效
//         if (_isControllerValid(controller)) {
//           // 直接復用控制器（移除isInUse檢查，因為每個key只會被一個組件使用）
//           wrapper.isInUse = true; // 標記為使用中

//           // 重置控制器状态
//           await _resetControllerSettings(controller, autoPlay, looping);

//           // 更新解码器计数
//           if (autoPlay && !controller.value.isPlaying) {
//             _playingControllers++;
//           }

//           // 更新使用信息
//           wrapper.lastUsed = DateTime.now();
//           wrapper.useCount++;

//           debugPrint('🔄 直接复用视频控制器: $key (使用次数: ${wrapper.useCount})');
//           debugPrint('📊 更新后解码器状态: 播放中 $_playingControllers 个');
//           return controller;
//         } else {
//           // 如果控制器无效，移除並釋放
//           debugPrint('⚠️ 控制器無效，移除並清理: $key');
//           _controllerCache.remove(key);
//           _activeDecoders = (_activeDecoders - 1).clamp(0, _maxActiveDecoders);
//           try {
//             await controller.dispose();
//           } catch (e) {
//             debugPrint('⚠️ 釋放無效控制器失敗: $e');
//           }
//         }
//       } catch (e) {
//         debugPrint('❌ 控制器重用失败: $e');
//         _controllerCache.remove(key);
//         _activeDecoders = (_activeDecoders - 1).clamp(0, _maxActiveDecoders);
//         try {
//           await controller.dispose();
//         } catch (disposeError) {
//           debugPrint('⚠️ 清理失敗控制器時出錯: $disposeError');
//         }
//       }
//     } else {
//       debugPrint('📋 緩存中沒有找到控制器: $key');
//     }

//     // 检查是否可以创建新的解码器
//     if (!_isDecoderResourceAvailable()) {
//       debugPrint('🚨 解码器资源不足，强制清理旧资源');
//       await _forceCleanupOldControllers();

//       if (!_isDecoderResourceAvailable()) {
//         debugPrint('❌ 解码器资源严重不足，拒绝创建新控制器');
//         onError?.call();
//         return null;
//       }
//     }

//     // 创建新的控制器前先檢查內存
//     if (_isMemoryHigh()) {
//       debugPrint('! RSS內存使用過高，強制清理緩存 ${_getMemoryInfo()}');
//       await _forceCleanupOldControllers();
//     }

//     debugPrint('🆕 創建新視頻控制器: $key ${_getMemoryInfo()}');
//     final controller = await _createController(
//       filePath: filePath,
//       isNetwork: isNetwork,
//       autoPlay: autoPlay,
//       looping: looping,
//       onError: onError,
//     );

//     // 缓存新创建的控制器
//     if (controller != null) {
//       _activeDecoders++;
//       if (autoPlay) {
//         _playingControllers++;
//       }
//       _decoderUsageLog[key] = DateTime.now();

//       await _cacheController(controller, filePath, videoType);
//       debugPrint(
//           '📊 创建控制器后状态: 活跃解码器 $_activeDecoders/$_maxActiveDecoders, 播放中 $_playingControllers/$_maxConcurrentPlaying');
//     } else {
//       debugPrint('❌ 創建控制器失敗: $key ${_getMemoryInfo()}');
//       // 立即调用错误回调，通知上层Widget控制器创建失败
//       onError?.call();

//       // 将失败的文件路径添加到黑名单，避免后续重复尝试
//       _failedFiles.add(filePath);
//       debugPrint('🚫 文件已添加到失敗黑名單: $filePath (总失败: ${_failedFiles.length})');
//     }

//     return controller;
//   }

//   /// 缓存控制器，管理缓存大小
//   Future<void> _cacheController(VideoPlayerController controller,
//       String filePath, VideoType videoType) async {
//     final key = _generateControllerKey(filePath, videoType);

//     // 如果已經有相同key的控制器，先釋放舊的
//     if (_controllerCache.containsKey(key)) {
//       final oldWrapper = _controllerCache[key];
//       try {
//         await oldWrapper?.controller.dispose();
//         debugPrint('🗑️ 釋放舊的重複控制器: $key');
//       } catch (e) {
//         debugPrint('⚠️ 釋放舊控制器失敗: $e');
//       }
//     }

//     // 如果缓存已满，移除最久未使用的控制器（智能清理策略）
//     while (_controllerCache.length > _maxCacheSize) {
//       // 優先清理使用次數最少且最久未使用的控制器
//       final oldestEntry = _controllerCache.entries.reduce((a, b) {
//         // 首先比較使用次數，使用次數少的優先被清理
//         if (a.value.useCount != b.value.useCount) {
//           return a.value.useCount < b.value.useCount ? a : b;
//         }
//         // 使用次數相同時，比較最後使用時間
//         return a.value.lastUsed.isBefore(b.value.lastUsed) ? a : b;
//       });

//       final oldestWrapper = _controllerCache.remove(oldestEntry.key);
//       try {
//         await oldestWrapper?.controller.dispose();
//         debugPrint(
//             '🗑️ 智能清理控制器: ${oldestEntry.key} (使用次數: ${oldestWrapper?.useCount}) ${_getMemoryInfo()}');
//       } catch (e) {
//         debugPrint('⚠️ 清理控制器失敗: $e');
//       }
//     }

//     _controllerCache[key] = VideoControllerWrapper(
//       controller: controller,
//       filePath: filePath,
//       videoType: videoType,
//       lastUsed: DateTime.now(),
//       useCount: 1,
//       isInUse: true, // 新創建的控制器標記為使用中
//     );

//     debugPrint(
//         '💾 控制器已緩存: $key (緩存總數: ${_controllerCache.length}) ${_getMemoryInfo()}');
//   }

//   /// 创建视频控制器（增强版本 - 添加文件檢查和重試機制）
//   Future<VideoPlayerController?> _createController({
//     required String filePath,
//     bool isNetwork = false,
//     bool autoPlay = false,
//     bool looping = false,
//     VoidCallback? onError,
//   }) async {
//     // 檢查是否是已知的失敗文件
//     if (_failedFiles.contains(filePath)) {
//       debugPrint('⚠️ 跳過已知失敗文件: $filePath');
//       onError?.call();
//       return null;
//     }

//     // 先檢查文件是否存在（僅針對本地文件）
//     if (!isNetwork) {
//       final file = File(filePath);
//       if (!await file.exists()) {
//         debugPrint('❌ 視頻文件不存在: $filePath');
//         onError?.call();
//         return null;
//       }

//       // 檢查文件大小
//       try {
//         final fileSize = await file.length();
//         if (fileSize == 0) {
//           debugPrint('❌ 視頻文件為空: $filePath');
//           onError?.call();
//           return null;
//         }
//         debugPrint(
//             '📁 視頻文件檢查通過: $filePath (大小: ${(fileSize / 1024 / 1024).toStringAsFixed(2)}MB)');
//       } catch (e) {
//         debugPrint('⚠️ 無法讀取文件大小: $filePath, 錯誤: $e');
//       }
//     }

//     // 只重試2次，避免過長等待導致用戶體驗差和潛在崩潰
//     for (int attempt = 1; attempt <= 2; attempt++) {
//       VideoPlayerController? controller;
//       try {
//         debugPrint('🎬 嘗試創建控制器 (第${attempt}次): $filePath ${_getMemoryInfo()}');

//         controller = isNetwork
//             ? VideoPlayerController.networkUrl(Uri.parse(filePath))
//             : VideoPlayerController.file(File(filePath));

//         // 更快的超时，减少等待时间：第一次5秒，第二次8秒
//         final timeoutSeconds = attempt == 1 ? 5 : 8;
//         await controller.initialize().timeout(
//           Duration(seconds: timeoutSeconds),
//           onTimeout: () {
//             // 安全释放控制器，避免内存泄漏导致崩溃
//             try {
//               controller?.dispose();
//             } catch (e) {
//               debugPrint('⚠️ 超时后释放控制器失败: $e');
//             }
//             debugPrint('⏰ 控制器初始化超時: $filePath ${_getMemoryInfo()}');
//             throw TimeoutException('视频初始化超时 (${timeoutSeconds}秒)',
//                 Duration(seconds: timeoutSeconds));
//           },
//         );

//         // 检查初始化结果
//         if (!controller.value.isInitialized) {
//           await controller.dispose();
//           throw Exception('视频控制器初始化失败 - 控制器未初始化');
//         }

//         if (controller.value.hasError) {
//           final error = controller.value.errorDescription ?? '未知錯誤';
//           await controller.dispose();
//           throw Exception('视频控制器初始化失败 - 控制器錯誤: $error');
//         }

//         // 设置循环和自动播放
//         controller.setLooping(looping);

//         // 设置音量为最大（确保有声音）
//         await controller.setVolume(1.0);

//         if (autoPlay && !controller.value.hasError) {
//           await controller.play();
//         }

//         debugPrint(
//             '✅ 成功创建视频控制器 (第${attempt}次嘗試): $filePath ${_getMemoryInfo()}');
//         return controller;
//       } catch (e) {
//         // 确保控制器被正确释放，防止内存泄漏导致崩溃
//         if (controller != null) {
//           try {
//             await controller.dispose();
//           } catch (disposeError) {
//             debugPrint('⚠️ 异常中释放控制器失败: $disposeError');
//           }
//         }

//         debugPrint('❌ 创建控制器失败 (第${attempt}次嘗試): $e ${_getMemoryInfo()}');

//         // 如果是最後一次嘗試，或者是文件不存在等致命錯誤，不再重試
//         if (attempt == 2 ||
//             e.toString().contains('文件不存在') ||
//             e.toString().contains('為空')) {
//           debugPrint('💀 停止重試，創建控制器最終失敗: $filePath');

//           // 將失敗文件加入黑名單，避免重複嘗試
//           _failedFiles.add(filePath);
//           debugPrint('🚫 文件已添加到失敗列表: $filePath (总失败: ${_failedFiles.length})');

//           // 如果失败文件较多，进行性能分析
//           if (_failedFiles.length % 3 == 0) {
//             _analyzeDevicePerformance();
//           }

//           onError?.call();
//           return null;
//         }

//         // 简化等待策略：失败后等待500毫秒
//         debugPrint('⏳ 等待500毫秒后重试...');
//         await Future.delayed(const Duration(milliseconds: 500));
//       }
//     }

//     // 這行應該不會被執行到
//     onError?.call();
//     return null;
//   }

//   /// 重置控制器设置
//   ///2, 重置控制器设置（增强状态检查和错误处理）
//   Future<void> _resetControllerSettings(
//       VideoPlayerController controller, bool autoPlay, bool looping) async {
//     try {
//       // 严格的状态检查
//       if (!controller.value.isInitialized || controller.value.hasError) {
//         debugPrint(
//             '⚠️ 控制器状态异常，跳过重置: initialized=${controller.value.isInitialized}, hasError=${controller.value.hasError}');
//         return;
//       }

//       // 添加额外的安全检查，确保控制器没有被释放
//       if (controller.value.duration == Duration.zero) {
//         debugPrint('⚠️ 控制器duration为0，可能已被释放，跳过重置');
//         return;
//       }

//       // 记录播放状态变化
//       final wasPlaying = controller.value.isPlaying;

//       // 安全地重置到开头
//       try {
//         await controller.seekTo(Duration.zero);
//       } catch (e) {
//         debugPrint('⚠️ 重置到开头失败: $e');
//         // 继续执行其他设置
//       }

//       // 设置循环和音量
//       controller.setLooping(looping);
//       await controller.setVolume(1.0);

//       // 根据需要播放或暂停，加强异常处理
//       if (autoPlay) {
//         try {
//           if (controller.value.isInitialized &&
//               !controller.value.hasError &&
//               !controller.value.isPlaying) {
//             await controller.play();
//             // 更新播放计数
//             if (!wasPlaying) {
//               _playingControllers++;
//             }
//             debugPrint('✅ 视频控制器播放成功 (当前播放: $_playingControllers)');
//           }
//         } catch (e) {
//           debugPrint('⚠️ 重置并播放控制器时出错: $e');
//           // 不要重新抛出异常，避免影响后续逻辑
//         }
//       } else {
//         try {
//           if (controller.value.isPlaying) {
//             await controller.pause();
//             // 更新播放计数
//             if (wasPlaying) {
//               _playingControllers =
//                   (_playingControllers - 1).clamp(0, _maxConcurrentPlaying);
//             }
//             debugPrint('⏸️ 视频控制器已暂停 (当前播放: $_playingControllers)');
//           }
//         } catch (e) {
//           debugPrint('⚠️ 暂停控制器时出错: $e');
//         }
//       }
//     } catch (e) {
//       debugPrint('❌ 重置控制器设置整体失败: $e');
//       // 不要重新抛出，避免影响缓存逻辑
//     }
//   }

//   /// 检查控制器是否有效
//   ///1, 增强判断控制器是否有效的逻辑
//   bool _isControllerValid(VideoPlayerController controller) {
//     try {
//       // 检查基本状态
//       if (!controller.value.isInitialized || controller.value.hasError) {
//         return false;
//       }

//       // 检查duration，如果为0可能表示控制器异常
//       if (controller.value.duration == Duration.zero) {
//         debugPrint('⚠️ 控制器duration为0，可能异常');
//         return false;
//       }

//       // 尝试访问控制器的其他属性来验证完整性
//       controller.value.position;

//       return true;
//     } catch (e) {
//       debugPrint('⚠️ 检查控制器有效性时出错: $e');
//       return false;
//     }
//   }

//   /// 生成控制器唯一标识（类型+文件路径作为唯一key，不会冲突）
//   String _generateControllerKey(String filePath, VideoType type) {
//     return '${type.toString()}::$filePath';
//   }

//   /// 根据广告类型生成多个控制器Key（处理topfull类型）
//   List<String> generateControllerKeys(String filePath, String adType) {
//     final keys = <String>[];

//     if (adType == 'topfull') {
//       // topfull类型需要创建两个独立的控制器
//       keys.add('${VideoType.topAd.toString()}::$filePath');
//       keys.add('${VideoType.fullAd.toString()}::$filePath');
//     } else if (adType == 'top') {
//       keys.add('${VideoType.topAd.toString()}::$filePath');
//     } else if (adType == 'full') {
//       keys.add('${VideoType.fullAd.toString()}::$filePath');
//     }

//     return keys;
//   }

//   /// 获取控制器缓存状态
//   Map<String, dynamic> getPoolStatus() {
//     return {
//       'totalControllers': _controllerCache.length,
//       'controllers': _controllerCache.keys.toList(),
//       'usageDetails': _controllerCache.map((key, wrapper) => MapEntry(key, {
//             'useCount': wrapper.useCount,
//             'lastUsed': wrapper.lastUsed,
//             'videoType': wrapper.videoType.toString(),
//             'isInUse': wrapper.isInUse,
//             'isValid': _isControllerValid(wrapper.controller),
//           })),
//     };
//   }

//   /// 檢查特定控制器是否存在且可用（簡化邏輯）
//   bool isControllerAvailable(String filePath, VideoType videoType) {
//     final key = _generateControllerKey(filePath, videoType);
//     if (!_controllerCache.containsKey(key)) return false;

//     final wrapper = _controllerCache[key]!;
//     return _isControllerValid(wrapper.controller);
//   }

//   /// 獲取控制器使用統計
//   Map<String, int> getUsageStats() {
//     final stats = <String, int>{};
//     stats['total'] = _controllerCache.length;
//     stats['inUse'] = _controllerCache.values.where((w) => w.isInUse).length;
//     stats['available'] =
//         _controllerCache.values.where((w) => !w.isInUse).length;
//     stats['invalid'] = _controllerCache.values
//         .where((w) => !_isControllerValid(w.controller))
//         .length;
//     return stats;
//   }

//   /// 调试：打印控制器池状态
//   void debugPrintPoolStatus() {
//     debugPrint('📊 视频控制器池状态：');
//     _controllerCache.forEach((key, wrapper) {
//       debugPrint(
//           ' 🎬 $key - 使用次数: ${wrapper.useCount}, 类型: ${wrapper.videoType}');
//     });
//   }

//   /// 设备性能分析（用于优化视频控制器创建策略）
//   void _analyzeDevicePerformance() {
//     try {
//       final rss = ProcessInfo.currentRss;
//       final maxRss = ProcessInfo.maxRss;
//       final cacheSize = _controllerCache.length;

//       // 分析设备性能指标
//       debugPrint('📊 设备性能分析:');
//       debugPrint(
//           '   RSS内存: ${rss > 1000000 ? (rss / 1024 / 1024).toStringAsFixed(1) : (rss / 1024).toStringAsFixed(1)}MB');
//       debugPrint(
//           '   峰值内存: ${maxRss > 1000000 ? (maxRss / 1024 / 1024).toStringAsFixed(1) : (maxRss / 1024).toStringAsFixed(1)}MB');
//       debugPrint('   缓存控制器数: $cacheSize');
//       debugPrint('   失败文件数: ${_failedFiles.length}');

//       // 根据性能状况给出建议
//       if (_failedFiles.length > 5) {
//         debugPrint('⚠️ 建议: 失败文件过多，可能需要检查视频文件质量或设备性能');
//       }

//       if (cacheSize > 8) {
//         debugPrint('💡 建议: 缓存较多，考虑主动清理释放内存');
//       }
//     } catch (e) {
//       debugPrint('❌ 性能分析失败: $e');
//     }
//   }

//   /// 安全获取控制器，带空值检查（推荐在Widget中使用）
//   Future<VideoPlayerController?> getControllerSafely({
//     required String filePath,
//     required VideoType videoType,
//     bool isNetwork = false,
//     bool autoPlay = false,
//     bool looping = false,
//     VoidCallback? onError,
//   }) async {
//     try {
//       final controller = await getController(
//         filePath: filePath,
//         videoType: videoType,
//         isNetwork: isNetwork,
//         autoPlay: autoPlay,
//         looping: looping,
//         onError: onError,
//       );

//       // 双重检查控制器有效性
//       if (controller != null && _isControllerValid(controller)) {
//         debugPrint(
//             '✅ 安全获取控制器成功: ${_generateControllerKey(filePath, videoType)}');
//         return controller;
//       } else {
//         debugPrint('❌ 控制器无效或为null，通知错误');
//         onError?.call();
//         return null;
//       }
//     } catch (e) {
//       debugPrint('❌ 安全获取控制器异常: $e');
//       onError?.call();
//       return null;
//     }
//   }

//   /// 清理失败文件黑名单（在新的视频列表更新时调用）
//   void clearFailedFiles() {
//     final count = _failedFiles.length;
//     _failedFiles.clear();
//     debugPrint('🧹 清理失败文件黑名单: $count 个文件被移除');
//   }

//   /// 获取失败文件统计
//   Map<String, dynamic> getFailedFilesStats() {
//     return {
//       'failedCount': _failedFiles.length,
//       'failedFiles': _failedFiles.toList(),
//     };
//   }

//   /// 获取完整的资源使用报告（包含解码器状态）
//   Map<String, dynamic> getResourceUsageReport() {
//     final decoderStatus = _getDecoderResourceStatus();
//     final hardwareInfo = _analyzeHardwareCapability();
//     final memoryInfo = _getMemoryInfo();

//     return {
//       'decoderStatus': decoderStatus,
//       'hardwareCapability': hardwareInfo,
//       'memoryStatus': memoryInfo,
//       'cacheStatus': {
//         'totalControllers': _controllerCache.length,
//         'maxCacheSize': _maxCacheSize,
//         'inUseControllers':
//             _controllerCache.values.where((w) => w.isInUse).length,
//         'validControllers': _controllerCache.values
//             .where((w) => _isControllerValid(w.controller))
//             .length,
//       },
//       'performanceMetrics': {
//         'failedFiles': _failedFiles.length,
//         'decoderUsageHistory': _decoderUsageLog.length,
//         'riskAssessment': _getRiskAssessment(),
//       },
//       'recommendations': _getPerformanceRecommendations(),
//     };
//   }

//   /// 获取风险评估
//   Map<String, dynamic> _getRiskAssessment() {
//     final riskLevel = _getRiskLevel();
//     final issues = <String>[];
//     final warnings = <String>[];

//     if (_activeDecoders >= _maxActiveDecoders) {
//       issues.add('解码器资源已满');
//     } else if (_activeDecoders >= _maxActiveDecoders * 0.8) {
//       warnings.add('解码器资源接近上限');
//     }

//     if (_playingControllers >= _maxConcurrentPlaying) {
//       issues.add('同时播放数量已达上限');
//     }

//     if (_isMemoryHigh()) {
//       issues.add('内存使用过高');
//     }

//     if (_failedFiles.length > 5) {
//       warnings.add('失败文件数量较多');
//     }

//     return {
//       'level': riskLevel,
//       'issues': issues,
//       'warnings': warnings,
//       'score': _calculateRiskScore(),
//     };
//   }

//   /// 计算风险分数（0-100，越高风险越大）
//   int _calculateRiskScore() {
//     int score = 0;

//     // 解码器使用率（0-40分）
//     score += ((_activeDecoders / _maxActiveDecoders) * 40).round();

//     // 播放数量（0-30分）
//     score += ((_playingControllers / _maxConcurrentPlaying) * 30).round();

//     // 内存使用（0-20分）
//     if (_isMemoryHigh()) score += 20;

//     // 失败文件影响（0-10分）
//     if (_failedFiles.length > 10)
//       score += 10;
//     else if (_failedFiles.length > 5) score += 5;

//     return score.clamp(0, 100);
//   }

//   /// 获取性能优化建议
//   List<String> _getPerformanceRecommendations() {
//     final recommendations = <String>[];

//     if (_activeDecoders >= _maxActiveDecoders) {
//       recommendations.add('🚨 立即释放未使用的视频控制器');
//     }

//     if (_playingControllers >= _maxConcurrentPlaying) {
//       recommendations.add('⏸️ 暂停部分视频以释放播放资源');
//     }

//     if (_isMemoryHigh()) {
//       recommendations.add('💾 内存使用过高，建议清理缓存');
//     }

//     if (_failedFiles.length > 5) {
//       recommendations.add('📁 检查视频文件格式或设备解码能力');
//     }

//     if (_controllerCache.length > _maxCacheSize * 0.8) {
//       recommendations.add('🧹 主动清理旧的控制器缓存');
//     }

//     if (recommendations.isEmpty) {
//       recommendations.add('✅ 当前资源使用正常');
//     }

//     return recommendations;
//   }

//   /// 强制释放所有控制器
//   Future<void> disposeAllControllers() async {
//     debugPrint('🗑️ 開始釋放所有控制器 ${_getMemoryInfo()}');
//     debugPrint(
//         '📊 释放前解码器状态: 活跃 $_activeDecoders/$_maxActiveDecoders, 播放中 $_playingControllers/$_maxConcurrentPlaying');

//     for (final wrapper in _controllerCache.values) {
//       try {
//         await wrapper.controller.dispose();
//       } catch (e) {
//         debugPrint('销毁控制器时出错: $e');
//       }
//     }
//     _controllerCache.clear();

//     // 重置所有计数器
//     _activeDecoders = 0;
//     _playingControllers = 0;
//     _decoderUsageLog.clear();

//     debugPrint('✅ 所有控制器已釋放 ${_getMemoryInfo()}');
//     debugPrint(
//         '📊 重置后解码器状态: 活跃 $_activeDecoders/$_maxActiveDecoders, 播放中 $_playingControllers/$_maxConcurrentPlaying');
//   }

//   /// 強制清理舊控制器以釋放內存
//   Future<void> _forceCleanupOldControllers() async {
//     debugPrint('🧹 強制清理開始，當前緩存: ${_controllerCache.length}');
//     debugPrint(
//         '📊 清理前解码器状态: 活跃 $_activeDecoders/$_maxActiveDecoders, 播放中 $_playingControllers/$_maxConcurrentPlaying');

//     // 优先清理不在使用且不在播放的控制器
//     final entries = _controllerCache.entries.toList();
//     entries.sort((a, b) {
//       // 优先级：未使用且未播放 > 未播放但在使用 > 其他
//       final aPlaying = a.value.controller.value.isPlaying;
//       final bPlaying = b.value.controller.value.isPlaying;
//       final aInUse = a.value.isInUse;
//       final bInUse = b.value.isInUse;

//       if (!aPlaying && !aInUse && (bPlaying || bInUse)) return -1;
//       if (!bPlaying && !bInUse && (aPlaying || aInUse)) return 1;

//       // 其次按最后使用时间排序
//       return a.value.lastUsed.compareTo(b.value.lastUsed);
//     });

//     // 保留最多3个最近使用的控制器，但优先保留正在播放的
//     int cleanupCount = 0;
//     final maxCleanup =
//         (_controllerCache.length - 3).clamp(0, _controllerCache.length);

//     for (int i = 0; i < entries.length && cleanupCount < maxCleanup; i++) {
//       final entry = entries[i];
//       final wasPlaying = entry.value.controller.value.isPlaying;

//       try {
//         await entry.value.controller.dispose();
//         _controllerCache.remove(entry.key);

//         // 更新计数器
//         _activeDecoders = (_activeDecoders - 1).clamp(0, _maxActiveDecoders);
//         if (wasPlaying) {
//           _playingControllers =
//               (_playingControllers - 1).clamp(0, _maxConcurrentPlaying);
//         }

//         cleanupCount++;
//         debugPrint('🗑️ 強制清理控制器: ${entry.key} (播放中: $wasPlaying)');
//       } catch (e) {
//         debugPrint('⚠️ 強制清理失敗: $e');
//       }
//     }

//     debugPrint('✅ 強制清理完成，剩餘緩存: ${_controllerCache.length} ${_getMemoryInfo()}');
//     debugPrint(
//         '📊 清理后解码器状态: 活跃 $_activeDecoders/$_maxActiveDecoders, 播放中 $_playingControllers/$_maxConcurrentPlaying');
//   }

//   /// 释放控制器（不真正dispose，而是標記為可復用）
//   Future<void> releaseController({
//     required String filePath,
//     required VideoType videoType,
//     bool isNetwork = false,
//   }) async {
//     final key = _generateControllerKey(filePath, videoType);

//     debugPrint('🔓 嘗試釋放控制器: $key ${_getMemoryInfo()}');

//     if (_controllerCache.containsKey(key)) {
//       if (_releasingKeys.contains(key)) {
//         debugPrint('⏳ 控制器釋放進行中，略過: $key');
//         return;
//       }

//       _releasingKeys.add(key);
//       final wrapper = _controllerCache[key]!;
//       final controller = wrapper.controller;

//       try {
//         // 检查控制器是否仍然有效
//         if (!_isControllerValid(controller)) {
//           debugPrint('⚠️ 控制器已无效，移除缓存並dispose: $key');
//           _controllerCache.remove(key);
//           _activeDecoders = (_activeDecoders - 1).clamp(0, _maxActiveDecoders);
//           try {
//             await controller.dispose();
//           } catch (e) {
//             debugPrint('⚠️ Dispose無效控制器失敗: $e');
//           }
//           return;
//         }

//         // 记录当前播放状态
//         final wasPlaying = controller.value.isPlaying;

//         // 安全地暂停播放並重置，但不dispose
//         try {
//           if (controller.value.isInitialized && !controller.value.hasError) {
//             if (controller.value.isPlaying) {
//               await controller.pause();
//               // 更新播放计数
//               if (wasPlaying) {
//                 _playingControllers =
//                     (_playingControllers - 1).clamp(0, _maxConcurrentPlaying);
//               }
//             }
//             // 不要每次都重置到開頭，避免影響復用性能
//             // await controller.seekTo(Duration.zero);
//           }
//         } catch (e) {
//           debugPrint('⚠️ 释放控制器操作時出錯: $e');
//         }

//         // 立即標記為可復用（未使用中）- 確保狀態同步更新
//         wrapper.isInUse = false;
//         wrapper.lastUsed = DateTime.now();

//         // 记录解码器释放时间
//         _decoderUsageLog[key] = DateTime.now();

//         debugPrint(
//             '🔓 控制器已釋放並可復用: $key (使用次數: ${wrapper.useCount}) ${_getMemoryInfo()}');
//         debugPrint(
//             '📊 释放后解码器状态: 活跃 $_activeDecoders/$_maxActiveDecoders, 播放中 $_playingControllers/$_maxConcurrentPlaying');
//       } catch (e) {
//         debugPrint('❌ 释放控制器時出錯: $e ${_getMemoryInfo()}');
//         // 出錯時移除緩存並dispose，避免保留損壞的控制器
//         _controllerCache.remove(key);
//         _activeDecoders = (_activeDecoders - 1).clamp(0, _maxActiveDecoders);
//         _playingControllers =
//             (_playingControllers - 1).clamp(0, _maxConcurrentPlaying);
//         try {
//           await controller.dispose();
//         } catch (disposeError) {
//           debugPrint('⚠️ Dispose出錯控制器失敗: $disposeError');
//         }
//       } finally {
//         _releasingKeys.remove(key);
//       }
//     } else {
//       debugPrint('⚠️ 嘗試釋放不存在的控制器: $key');
//     }
//   }

//   /// 强制移除控制器
//   Future<void> forceRemoveController({
//     required String filePath,
//     required VideoType videoType,
//     bool isNetwork = false,
//   }) async {
//     final key = _generateControllerKey(filePath, videoType);

//     debugPrint('🗑️ 強制移除控制器: $key ${_getMemoryInfo()}');

//     if (_controllerCache.containsKey(key)) {
//       final wrapper = _controllerCache.remove(key);
//       final wasPlaying = wrapper?.controller.value.isPlaying ?? false;

//       try {
//         await wrapper?.controller.dispose();

//         // 更新计数器
//         _activeDecoders = (_activeDecoders - 1).clamp(0, _maxActiveDecoders);
//         if (wasPlaying) {
//           _playingControllers =
//               (_playingControllers - 1).clamp(0, _maxConcurrentPlaying);
//         }

//         // 移除使用记录
//         _decoderUsageLog.remove(key);

//         debugPrint('✅ 控制器已強制移除並dispose: $key ${_getMemoryInfo()}');
//         debugPrint(
//             '📊 移除后解码器状态: 活跃 $_activeDecoders/$_maxActiveDecoders, 播放中 $_playingControllers/$_maxConcurrentPlaying');
//       } catch (e) {
//         debugPrint('❌ 强制移除控制器时出错: $e ${_getMemoryInfo()}');
//       }
//     } else {
//       debugPrint('⚠️ 嘗試移除不存在的控制器: $key');
//     }
//   }

//   /// 更新视频列表
//   Future<void> updateVideoList({
//     required List<String> topAdVideos,
//     required List<String> fullAdVideos,
//     bool isNetwork = false,
//   }) async {
//     _logger.i('🔄 更新视频列表: 顶部${topAdVideos.length}个, 全屏${fullAdVideos.length}个');

//     // 合并所有类型视频路径键
//     final allTypePaths = <String>{};
//     for (final path in topAdVideos) {
//       allTypePaths.add(_generateControllerKey(path, VideoType.topAd));
//     }
//     for (final path in fullAdVideos) {
//       allTypePaths.add(_generateControllerKey(path, VideoType.fullAd));
//     }

//     // 移除不再需要的控制器
//     final keysToRemove = _controllerCache.keys
//         .where((key) => !allTypePaths.contains(key))
//         .toList();

//     for (final key in keysToRemove) {
//       try {
//         final wrapper = _controllerCache.remove(key);
//         await wrapper?.controller.dispose();
//       } catch (e) {
//         debugPrint('移除控制器时出错: $e');
//       }
//     }

//     debugPrint(
//         '✅ 列表更新完成，当前池大小: ${_controllerCache.length} ${_getMemoryInfo()}');
//   }
// }
