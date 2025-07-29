// import 'dart:async';
// import 'package:flutter/foundation.dart';
// import 'package:flutter/material.dart';
// import 'package:iboard_app/managers/file_manager.dart';
// import 'package:iboard_app/models/ad_model.dart';
// import 'package:iboard_app/widgets/full_ad_widget.dart';
// import 'package:logger/logger.dart';
// import 'package:iboard_app/providers/app_data_provider.dart';

// /// 全屏广告轮播Provider
// /// 负责管理全屏广告的轮播逻辑、暂停恢复、定时器管理等
// class FullAdvertisementCarouselProvider extends ChangeNotifier {
//   final Logger _logger = Logger();
//   AppDataProvider? _appDataProvider;

//   // 定时器管理
//   Timer? _carouselTimer;
//   Timer? _debugTimer;

//   // 广告数据
//   List<AdModel> _fullscreenAds = [];
//   List<Widget> _adWidgets = [];

//   // 状态管理
//   bool _isPaused = false;
//   bool _isActive = false;
//   bool _isPreloading = false;
//   bool _isPreloaded = false;
//   int _currentAdIndex = 0;

//   // 时间记录
//   DateTime? _fullscreenStartTime;
//   DateTime? _currentAdStartTime;
//   DateTime? _currentAdPauseTime;
//   Duration _adElapsedTime = Duration.zero;
//   Duration _expectedAdElapsedTime = Duration.zero;
//   Duration _adDuration = Duration.zero;

//   // 视频播放进度记录
//   Map<String, Duration> _videoProgressMap = {};

//   // 图片显示时间记录
//   Map<String, Duration> _imageDisplayTimeMap = {};

//   // 广告切换控制
//   bool isNeedSwitchAd = false;
//   int switchTime = 0;

//   // Getters
//   List<AdModel> get fullscreenAds => _fullscreenAds;
//   List<Widget> get adWidgets => _adWidgets;
//   bool get isPaused => _isPaused;
//   bool get isActive => _isActive;
//   bool get isPreloading => _isPreloading;
//   bool get isPreloaded => _isPreloaded;
//   int get currentAdIndex => _currentAdIndex;
//   DateTime? get currentAdStartTime => _currentAdStartTime;
//   Duration get adElapsedTime => _adElapsedTime;
//   Duration get expectedAdElapsedTime => _expectedAdElapsedTime;
//   Duration get adDuration => _adDuration;
//   Map<String, Duration> get videoProgressMap => _videoProgressMap;
//   Map<String, Duration> get imageDisplayTimeMap => _imageDisplayTimeMap;
//   Duration? get getRemainingAdTime => _calculateCurrentAdRemainingTime();

//   /// 设置AppDataProvider引用
//   void setAppDataProvider(AppDataProvider appDataProvider) {
//     _appDataProvider = appDataProvider;
//   }

//   ///1，更新全屏广告数据并创建Widget组件
//   void updateFullscreenAds(List<AdModel> newAds) {
//     if (!listEquals(_fullscreenAds, newAds)) {
//       _fullscreenAds = newAds;
//       _createAdWidgets();

//       if (_fullscreenAds.isNotEmpty &&
//           _currentAdIndex >= _fullscreenAds.length) {
//         _currentAdIndex = 0;
//         _logger.i('🔄 广告索引已重置为0，因为超出新广告列表范围');
//       }

//       _logger.i(
//           '📺 全屏广告数据更新: ${_fullscreenAds.length} 条广告, 当前索引: $_currentAdIndex');
//       notifyListeners();
//     }
//   }

//   ///2，预加载全屏广告
//   Future<void> preloadFullscreenAd() async {
//     if (_isPreloading || _isPreloaded || _fullscreenAds.isEmpty) return;

//     _isPreloading = true;
//     notifyListeners();

//     try {
//       final firstAd = _fullscreenAds[0];
//       final fileManager = FileManager();
//       await fileManager.getFile(firstAd.file);
//       _isPreloaded = true;
//       _logger.i('✅ 全屏广告预加载完成: ${firstAd.file}');
//     } catch (e) {
//       _logger.e('❌ 全屏广告预加载失败: $e');
//     } finally {
//       _isPreloading = false;
//       notifyListeners();
//     }
//   }

//   ///3，创建广告Widget组件列表
//   void _createAdWidgets() {
//     _safelyDisposeCurrentWidget();
//     _adWidgets = _fullscreenAds.asMap().entries.map((entry) {
//       return _createSingleAdWidget(entry.value, entry.key);
//     }).toList();
//     _logger.i('📺 创建了 ${_adWidgets.length} 个广告Widget');
//   }

//   ///4，进入全屏广告模式并开始轮播
//   void enterFullscreenMode(int totalFullscreenDuration) {
//     if (_isActive) return;

//     _isActive = true;
//     _isPaused = false;
//     _currentAdPauseTime = null;
//     _fullscreenStartTime = DateTime.now();

//     if (_fullscreenAds.isNotEmpty) {
//       if (_currentAdIndex >= _fullscreenAds.length) {
//         _currentAdIndex = 0;
//       }

//       _createAdWidgets();
//       _handleCurrentAdState(totalFullscreenDuration);

//       if (_isPreloaded) {
//         _isPreloaded = false;
//       }

//       startDebugTimer();
//     }

//     notifyListeners();
//   }

//   ///5，处理当前广告状态
//   void _handleCurrentAdState(int totalFullscreenDuration) {
//     final currentAd = getCurrentAd();
//     if (currentAd == null) {
//       _startCarouselTimer(totalFullscreenDuration);
//       return;
//     }

//     int fullScreenStateTime = _getFullScreenStateTime(totalFullscreenDuration);

//     // 获取实际已播放时间（视频的实际播放进度或图片的显示时间）
//     Duration actualElapsedTime = Duration.zero;

//     // 对于视频广告，使用保存的播放进度
//     if (currentAd.file.mimeType.startsWith('video/')) {
//       final videoProgress = getVideoProgress(currentAd.id.toString());
//       if (videoProgress != null) {
//         actualElapsedTime = videoProgress;
//         _adElapsedTime = videoProgress; // 更新已播放时间为实际视频进度
//       }
//     }
//     // 对于图片广告，使用保存的显示时间
//     else if (currentAd.file.mimeType.startsWith('image/')) {
//       final imageDisplayTime = getImageDisplayTime(currentAd.id.toString());
//       if (imageDisplayTime != null) {
//         actualElapsedTime = imageDisplayTime;
//         _adElapsedTime = imageDisplayTime; // 更新已播放时间为图片显示时间
//       }
//     }

//     // 检查是否需要切换广告
//     // 条件1: 实际已播放时间 + 全屏状态时间 >= 广告总时长
//     bool shouldSwitchByActualTime =
//         (actualElapsedTime.inSeconds + fullScreenStateTime) >=
//             _adDuration.inSeconds;

//     // 条件2: 预计已播放时间 + 全屏状态时间 >= 广告总时长
//     bool shouldSwitchByExpectedTime =
//         (_expectedAdElapsedTime.inSeconds + fullScreenStateTime) >=
//             _adDuration.inSeconds;

//     if (shouldSwitchByActualTime || shouldSwitchByExpectedTime) {
//       // 需要切换广告
//       isNeedSwitchAd = true;
//       switchTime = 0;
//     } else {
//       // 不需要切换广告
//       isNeedSwitchAd = false;
//       switchTime = 0;
//     }

//     _preloadNextAd();
//     _startCarouselTimer(fullScreenStateTime);
//   }

//   ///6，启动轮播定时器
//   void _startCarouselTimer(int totalFullscreenDuration) {
//     _carouselTimer?.cancel();

//     if (_fullscreenAds.isEmpty || !_isActive || _isPaused) return;

//     if (_currentAdIndex >= _fullscreenAds.length) {
//       _currentAdIndex = 0;
//     }

//     final currentAd = _fullscreenAds[_currentAdIndex];
//     _currentAdStartTime = DateTime.now();
//     _adDuration = currentAd.durationObject;

//     if (_currentAdPauseTime != null) {
//       _handlePausedAdState();
//     }

//     Duration waitTime = _adDuration;

//     if (_fullscreenStartTime != null) {
//       final fullscreenElapsed =
//           DateTime.now().difference(_fullscreenStartTime!);
//       final remainingTotalTime =
//           Duration(seconds: totalFullscreenDuration) - fullscreenElapsed;

//       if (remainingTotalTime.inMilliseconds <= _adDuration.inMilliseconds) {
//         waitTime = Duration(
//             milliseconds: (remainingTotalTime.inMilliseconds * 0.9)
//                 .round()
//                 .clamp(200, remainingTotalTime.inMilliseconds - 100));
//       }
//     }

//     if (_adElapsedTime.inMilliseconds > 0) {
//       waitTime = waitTime - _adElapsedTime;
//       _adElapsedTime = Duration.zero;
//     }

//     _carouselTimer = Timer(waitTime, () {
//       if (!_isPaused &&
//           _fullscreenAds.isNotEmpty &&
//           _isActive &&
//           isNeedSwitchAd) {
//         _nextAd(totalFullscreenDuration);
//       }
//     });
//   }

//   ///7，切换到下一个广告
//   void _nextAd(int totalFullscreenDuration) {
//     if (_fullscreenAds.isEmpty || _isPaused || !_isActive) return;

//     final previousIndex = _currentAdIndex;
//     final previousAd = _fullscreenAds[previousIndex];

//     _safelyDisposeCurrentWidget();

//     Future.delayed(const Duration(milliseconds: 100), () {
//       if (!_isActive) return;

//       _handleVideoProgress(previousAd);
//       _currentAdIndex = (_currentAdIndex + 1) % _fullscreenAds.length;

//       _adElapsedTime = Duration.zero;
//       _expectedAdElapsedTime = Duration.zero;
//       _currentAdPauseTime = null;

//       notifyListeners();
//       _startCarouselTimer(totalFullscreenDuration);
//     });
//   }

//   ///8，暂停轮播
//   void pauseCarousel() {
//     if (_isPaused || !_isActive) return;

//     _isPaused = true;
//     _currentAdPauseTime = DateTime.now();

//     if (_currentAdStartTime != null &&
//         _currentAdIndex < _fullscreenAds.length) {
//       final rawElapsed = _currentAdPauseTime!.difference(_currentAdStartTime!);
//       _adElapsedTime += rawElapsed;

//       if (_adElapsedTime >= _adDuration) {
//         _adElapsedTime = _adDuration;
//       }

//       // 保存当前广告的显示进度（无论是图片还是视频）
//       final currentAd = getCurrentAd();
//       if (currentAd != null) {
//         if (currentAd.file.mimeType.startsWith('video/')) {
//           final videoProgress = getCurrentVideoProgress();
//           if (videoProgress != null) {
//             saveVideoProgress(currentAd.id.toString(), videoProgress);
//             _adElapsedTime = videoProgress; // 更新为实际视频进度
//           }
//         } else if (currentAd.file.mimeType.startsWith('image/')) {
//           saveImageDisplayTime(currentAd.id.toString(), _adElapsedTime);
//         }
//       }
//     }

//     _carouselTimer?.cancel();
//     notifyListeners();
//   }

//   ///9，恢复轮播
//   void resumeCarousel(int totalFullscreenDuration) {
//     if (!_isPaused || !_isActive) return;

//     _isPaused = false;

//     if (_fullscreenAds.isNotEmpty) {
//       final currentAd = getCurrentAd();
//       if (currentAd == null) return;

//       int? fullScreenStateTime;

//       if (_appDataProvider?.settingsModel?.settings != null) {
//         fullScreenStateTime =
//             _appDataProvider!.settingsModel!.settings.advertisementPlayDuration;
//       }

//       if (fullScreenStateTime == null) return;

//       // 获取实际已播放时间
//       Duration actualElapsedTime = _adElapsedTime;

//       // 对于视频广告，使用保存的播放进度
//       if (currentAd.file.mimeType.startsWith('video/')) {
//         final videoProgress = getVideoProgress(currentAd.id.toString());
//         if (videoProgress != null) {
//           actualElapsedTime = videoProgress;
//           _adElapsedTime = videoProgress; // 更新为实际视频进度
//         }
//       }
//       // 对于图片广告，使用保存的显示时间
//       else if (currentAd.file.mimeType.startsWith('image/')) {
//         final imageDisplayTime = getImageDisplayTime(currentAd.id.toString());
//         if (imageDisplayTime != null) {
//           actualElapsedTime = imageDisplayTime;
//           _adElapsedTime = imageDisplayTime; // 更新为图片显示时间
//         }
//       }

//       // 计算剩余时间
//       Duration remainingTime = _adDuration - actualElapsedTime;

//       if (remainingTime.inSeconds > 0) {
//         _currentAdStartTime = DateTime.now();
//         _carouselTimer = Timer(remainingTime, () {
//           if (!_isPaused && _fullscreenAds.isNotEmpty && _isActive) {
//             _nextAd(totalFullscreenDuration);
//           }
//         });
//       } else {
//         _nextAd(totalFullscreenDuration);
//       }
//     }

//     notifyListeners();
//   }

//   ///10，退出全屏广告模式
//   void exitFullscreenMode() {
//     if (!_isActive) return;

//     _safelyDisposeCurrentWidget();

//     final currentAd = getCurrentAd();
//     if (currentAd != null) {
//       if (isCurrentAdVideo()) {
//         final videoProgress = getCurrentVideoProgress();
//         if (videoProgress != null) {
//           saveVideoProgress(currentAd.id.toString(), videoProgress);
//         }
//       } else if (currentAd.file.mimeType.startsWith('image/')) {
//         // 保存图片广告的显示时间
//         saveImageDisplayTime(currentAd.id.toString(), _adElapsedTime);
//       }
//     }

//     _isActive = false;
//     _carouselTimer?.cancel();
//     _debugTimer?.cancel();

//     _fullscreenStartTime = null;
//     _currentAdStartTime = null;
//     _currentAdPauseTime = null;
//     _adElapsedTime = Duration.zero;
//     _expectedAdElapsedTime = Duration.zero; // 重置预计已播放时间

//     notifyListeners();
//   }

//   ///11，检查是否需要切换广告
//   void checkAndSwitchAdIfNeeded() {
//     if (!isNeedSwitchAd || switchTime <= 0) return;

//     if (_fullscreenStartTime != null) {
//       final elapsed =
//           DateTime.now().difference(_fullscreenStartTime!).inSeconds;

//       if (elapsed >= switchTime) {
//         isNeedSwitchAd = false;
//         switchTime = 0;
//         _switchToNextAdImmediately();
//       }
//     }
//   }

//   ///12，立即切换到下一个广告
//   void _switchToNextAdImmediately() {
//     if (_fullscreenAds.isEmpty || !_isActive) return;

//     final previousIndex = _currentAdIndex;
//     final previousAd = _fullscreenAds[previousIndex];

//     _safelyDisposeCurrentWidget();

//     Future.delayed(const Duration(milliseconds: 100), () {
//       if (!_isActive) return;

//       _handleVideoProgress(previousAd);
//       _currentAdIndex = (_currentAdIndex + 1) % _fullscreenAds.length;

//       final nextAd = _fullscreenAds[_currentAdIndex];

//       _adElapsedTime = Duration.zero;
//       // 注意：这里不重置预计已播放时间，因为我们需要累积它
//       _currentAdPauseTime = null;
//       _currentAdStartTime = DateTime.now();
//       _adDuration = nextAd.durationObject;

//       notifyListeners();

//       final remainingTimeInState = _calculateRemainingTimeInState();

//       if (remainingTimeInState.inSeconds > 0) {
//         _carouselTimer?.cancel();
//         _carouselTimer = Timer(remainingTimeInState, () {
//           if (!_isPaused && _fullscreenAds.isNotEmpty && _isActive) {
//             _nextAd(_calculateTotalFullscreenDuration());
//           }
//         });
//       } else {
//         Future.delayed(Duration.zero, () {
//           _nextAd(_calculateTotalFullscreenDuration());
//         });
//       }
//     });
//   }

//   ///13，启动调试定时器
//   void startDebugTimer({bool enableLogging = true}) {
//     _debugTimer?.cancel();
//     _debugTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
//       if (!_isActive || !enableLogging) return;

//       String statusText = _isPaused ? '⏸️ 暂停' : '▶️ 播放';
//       String timeInfo = '';

//       if (_currentAdStartTime != null &&
//           _currentAdIndex < _fullscreenAds.length) {
//         // 使用保存的显示时间（图片或视频）来计算剩余时间
//         final currentAd = getCurrentAd();
//         Duration remaining = _adDuration - _adElapsedTime;

//         if (currentAd != null) {
//           if (currentAd.file.mimeType.startsWith('video/')) {
//             final videoProgress = getVideoProgress(currentAd.id.toString());
//             if (videoProgress != null) {
//               remaining = _adDuration - videoProgress;
//             }
//           } else if (currentAd.file.mimeType.startsWith('image/')) {
//             final imageDisplayTime =
//                 getImageDisplayTime(currentAd.id.toString());
//             if (imageDisplayTime != null) {
//               remaining = _adDuration - imageDisplayTime;
//             }
//           }
//         }

//         // 获取实际已播放时间用于显示
//         Duration actualElapsedTime = _adElapsedTime;
//         if (currentAd != null) {
//           if (currentAd.file.mimeType.startsWith('video/')) {
//             final videoProgress = getVideoProgress(currentAd.id.toString());
//             if (videoProgress != null) {
//               actualElapsedTime = videoProgress;
//             }
//           } else if (currentAd.file.mimeType.startsWith('image/')) {
//             final imageDisplayTime =
//                 getImageDisplayTime(currentAd.id.toString());
//             if (imageDisplayTime != null) {
//               actualElapsedTime = imageDisplayTime;
//             }
//           }
//         }

//         if (_isPaused) {
//           timeInfo =
//               '剩余: ${remaining.inSeconds}s/${_adDuration.inSeconds}s | 实际已播放: ${actualElapsedTime.inSeconds}s | 预计已播放: ${_expectedAdElapsedTime.inSeconds}s';
//         } else {
//           final currentElapsed =
//               DateTime.now().difference(_currentAdStartTime!);
//           final totalElapsed = currentElapsed + _adElapsedTime;
//           remaining = _adDuration - totalElapsed;
//           timeInfo =
//               '剩余: ${remaining.inSeconds.clamp(0, _adDuration.inSeconds)}s/${_adDuration.inSeconds}s | 实际已播放: ${actualElapsedTime.inSeconds}s | 预计已播放: ${_expectedAdElapsedTime.inSeconds}s';
//         }
//       }

//       final currentAd = getCurrentAd();
//       final adTitle = currentAd?.title ?? '无广告';
//       final timerActive = _carouselTimer?.isActive ?? false;

//       _logger.i(
//           '🎬 [全屏广告] $statusText | [${_currentAdIndex + 1}/${_fullscreenAds.length}] $adTitle | $timeInfo | Timer活跃: $timerActive');
//     });
//   }

//   ///14，停止调试定时器
//   void stopDebugTimer() {
//     _debugTimer?.cancel();
//   }

//   ///15，重置轮播索引
//   void resetCarouselIndex() {
//     _currentAdIndex = 0;
//     _adElapsedTime = Duration.zero;
//     _expectedAdElapsedTime = Duration.zero; // 重置预计已播放时间
//     _currentAdStartTime = null;
//     _currentAdPauseTime = null;
//     notifyListeners();
//   }

//   // 工具方法

//   ///20，安全清理当前Widget资源
//   void _safelyDisposeCurrentWidget() {
//     if (_currentAdIndex < _adWidgets.length) {
//       final currentWidget = _adWidgets[_currentAdIndex];
//       if (currentWidget is FullAdWidget) {
//         _logger.i('🧹 准备清理当前广告Widget资源: $_currentAdIndex');
//       }
//     }
//   }

//   ///21，创建单个广告Widget
//   Widget _createSingleAdWidget(AdModel ad, int index) {
//     final FileManager fileManager = FileManager();
//     fileManager.getFile(ad.file);

//     Duration? initialPosition;
//     if (ad.file.mimeType.startsWith('video/')) {
//       initialPosition = getVideoProgress(ad.id.toString());
//     } else if (ad.file.mimeType.startsWith('image/')) {
//       initialPosition = getImageDisplayTime(ad.id.toString());
//     }

//     return FullAdWidget(
//       key: ValueKey('fullad_${ad.id}_$index'),
//       ad: ad,
//       fileManager: fileManager,
//       initialVideoPosition: initialPosition,
//       onVideoProgressChanged: (adId, position) {
//         final currentAd = getCurrentAd();
//         if (currentAd != null && currentAd.id.toString() == adId) {
//           if (currentAd.file.mimeType.startsWith('video/')) {
//             saveVideoProgress(adId, position);
//           } else if (currentAd.file.mimeType.startsWith('image/')) {
//             saveImageDisplayTime(adId, position);
//           }
//         }
//       },
//       onVideoDisposed: () => _logger.i('🎬 广告 ${ad.id} 资源已释放'),
//     );
//   }

//   ///22，预加载下一个广告
//   void _preloadNextAd() {
//     if (_fullscreenAds.isEmpty) return;

//     final nextAdIndex = (_currentAdIndex + 1) % _fullscreenAds.length;
//     final nextAd = _fullscreenAds[nextAdIndex];

//     final fileManager = FileManager();
//     fileManager.getFile(nextAd.file);
//   }

//   ///23，处理暂停后的广告状态
//   void _handlePausedAdState() {
//     final currentAd = getCurrentAd();
//     if (currentAd == null) return;

//     int? fullScreenStateTime;

//     if (_appDataProvider?.settingsModel?.settings != null) {
//       fullScreenStateTime =
//           _appDataProvider!.settingsModel!.settings.advertisementPlayDuration;
//     }

//     if (fullScreenStateTime == null) return;

//     // 获取实际已播放时间
//     Duration actualElapsedTime = _adElapsedTime;

//     // 对于视频广告，使用保存的播放进度
//     if (currentAd.file.mimeType.startsWith('video/')) {
//       final videoProgress = getVideoProgress(currentAd.id.toString());
//       if (videoProgress != null) {
//         actualElapsedTime = videoProgress;
//       }
//     }
//     // 对于图片广告，使用保存的显示时间
//     else if (currentAd.file.mimeType.startsWith('image/')) {
//       final imageDisplayTime = getImageDisplayTime(currentAd.id.toString());
//       if (imageDisplayTime != null) {
//         actualElapsedTime = imageDisplayTime;
//       }
//     }

//     // 检查是否需要切换广告
//     // 条件1: 实际已播放时间 + 全屏状态时间 >= 广告总时长
//     bool shouldSwitchByActualTime =
//         (actualElapsedTime.inSeconds + fullScreenStateTime) >=
//             _adDuration.inSeconds;

//     // 条件2: 预计已播放时间 + 全屏状态时间 >= 广告总时长
//     bool shouldSwitchByExpectedTime =
//         (_expectedAdElapsedTime.inSeconds + fullScreenStateTime) >=
//             _adDuration.inSeconds;

//     if (shouldSwitchByActualTime || shouldSwitchByExpectedTime) {
//       // 需要切换广告
//       isNeedSwitchAd = true;
//       switchTime = 0;
//     } else {
//       // 不需要切换广告
//       isNeedSwitchAd = false;
//       switchTime = 0;
//     }
//   }

//   ///24，处理视频广告的播放进度
//   void _handleVideoProgress(AdModel ad) {
//     final currentAd = getCurrentAd();
//     if (ad.file.mimeType.startsWith('video/')) {
//       if (currentAd != null && currentAd.id == ad.id) {
//         // 中途切换，保存播放进度
//         final progress = getVideoProgress(ad.id.toString());
//         if (progress != null) {
//           saveVideoProgress(ad.id.toString(), progress);
//         }
//       } else {
//         // 播放完成，清除播放进度
//         clearVideoProgress(ad.id.toString());
//       }
//     } else if (ad.file.mimeType.startsWith('image/')) {
//       if (currentAd != null && currentAd.id == ad.id) {
//         // 中途切换，保存显示时间
//         saveImageDisplayTime(ad.id.toString(), _adElapsedTime);
//       } else {
//         // 显示完成，清除显示时间
//         clearImageDisplayTime(ad.id.toString());
//       }
//     }
//   }

//   ///25，计算全屏广告状态中的剩余时间
//   Duration _calculateRemainingTimeInState() {
//     if (_fullscreenStartTime == null) return Duration.zero;

//     int fullScreenStateTime = _getFullScreenStateTime(10);
//     final elapsed = DateTime.now().difference(_fullscreenStartTime!).inSeconds;
//     final remaining = fullScreenStateTime - elapsed;

//     return remaining > 0 ? Duration(seconds: remaining) : Duration.zero;
//   }

//   ///26，计算总的全屏广告状态时间
//   int _calculateTotalFullscreenDuration() {
//     return _getFullScreenStateTime(10);
//   }

//   ///27，获取全屏广告状态时间
//   int _getFullScreenStateTime(int defaultDuration) {
//     if (_appDataProvider?.settingsModel?.settings != null) {
//       return _appDataProvider!
//           .settingsModel!.settings.advertisementPlayDuration;
//     }
//     return defaultDuration;
//   }

//   ///28，计算当前广告的剩余播放时间
//   Duration _calculateCurrentAdRemainingTime() {
//     if (_currentAdStartTime == null) return _adDuration;

//     final currentElapsed = DateTime.now().difference(_currentAdStartTime!);
//     final totalElapsed = currentElapsed + _adElapsedTime;
//     final remaining = _adDuration - totalElapsed;

//     return remaining.isNegative ? Duration.zero : remaining;
//   }

//   ///29，获取当前播放的广告模型
//   AdModel? getCurrentAd() {
//     if (_currentAdIndex >= _fullscreenAds.length) return null;
//     return _fullscreenAds[_currentAdIndex];
//   }

//   ///30，获取当前播放的Widget
//   Widget? getCurrentWidget() {
//     if (_currentAdIndex >= _adWidgets.length) return null;
//     return _adWidgets[_currentAdIndex];
//   }

//   ///31，获取当前播放的广告Widget
//   Widget? getCurrentAdWidget() => getCurrentWidget();

//   ///32，记录视频播放进度
//   void saveVideoProgress(String adId, Duration position) {
//     _videoProgressMap[adId] = position;
//   }

//   ///33，获取视频播放进度
//   Duration? getVideoProgress(String adId) {
//     return _videoProgressMap[adId];
//   }

//   ///34，清除特定视频的播放进度
//   void clearVideoProgress(String adId) {
//     if (_videoProgressMap.containsKey(adId)) {
//       _videoProgressMap.remove(adId);
//     }
//   }

//   ///35，记录图片显示时间
//   void saveImageDisplayTime(String adId, Duration displayTime) {
//     _imageDisplayTimeMap[adId] = displayTime;
//   }

//   ///36，获取图片显示时间
//   Duration? getImageDisplayTime(String adId) {
//     return _imageDisplayTimeMap[adId];
//   }

//   ///37，清除特定图片的显示时间
//   void clearImageDisplayTime(String adId) {
//     if (_imageDisplayTimeMap.containsKey(adId)) {
//       _imageDisplayTimeMap.remove(adId);
//     }
//   }

//   ///38，检查当前广告是否为视频
//   bool isCurrentAdVideo() {
//     final currentAd = getCurrentAd();
//     return currentAd?.file.mimeType.startsWith('video/') ?? false;
//   }

//   ///39，获取当前视频广告的播放进度
//   Duration? getCurrentVideoProgress() {
//     final currentAd = getCurrentAd();
//     if (currentAd != null && isCurrentAdVideo()) {
//       return getVideoProgress(currentAd.id.toString());
//     }
//     return null;
//   }

//   @override
//   void dispose() {
//     _carouselTimer?.cancel();
//     _debugTimer?.cancel();
//     super.dispose();
//   }
// }
