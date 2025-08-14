import 'dart:async'; // Added import for Timer

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:iboard_app/models/announcement_model.dart';
import 'package:iboard_app/pages/fullscreen_ads_page.dart';
import 'package:iboard_app/pages/mainscreen_page.dart';
import 'package:iboard_app/providers/announcement_provider.dart';
import 'package:iboard_app/providers/state_provider.dart'; // Added import for CarouselStateProvider

import 'package:provider/provider.dart';

class MainPage extends StatefulWidget {
  @override
  _MainPageState createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  Timer? _mainTimer;
  List<AnnouncementModel>?
      _previousAnnouncementsForBuild; // Added state variable
  bool _isAdsDialogOpen = false; // 是否已打開全屏廣告對話框

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeTopWidgets();
    });
  }

  @override
  void dispose() {
    _mainTimer?.cancel();
    super.dispose();
  }

  //1，初始化頂部广告
  void _initializeTopWidgets() {
    // 初始化為默認播放狀態並啟動計時器
    final carouselProvider = context.read<CarouselStateProvider>();

    // 設置全屏廣告回調
    carouselProvider.setFullscreenAdCallback(() {
      showAdsDialog();
    });

    // 設置關閉全屏廣告回調
    carouselProvider.setCloseFullscreenAdCallback(() {
      closeAdsDialog();
    });

    // 設置通告轮播下一个回调 - 這個功能現在由mainscreen_page.dart處理
    // carouselProvider.setNoticeCarouselNextCallback(() {
    //   // 通告轮播下一个的逻辑会由mainscreen_page.dart处理
    // });

    // 啟動通告輪播系統（可選，如果需要集成state_provider的輪播）
    // carouselProvider.startNoticeCarousel();

    carouselProvider.resetToDefault(); // 使用resetToDefault確保計時器正確啟動
  }

  //2， Method to show FullscreenAdsPage in a dialog
  void showAdsDialog() {
    if (_isAdsDialogOpen) return; // Prevent multiple dialogs

    setState(() {
      _isAdsDialogOpen = true;
    });

    showDialog(
      context: context,
      barrierDismissible: true, //点击区域之外就关闭窗口，但不会触发状态转换
      builder: (BuildContext context) {
        return Listener(
            onPointerDown: (event) => {},
            child: Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: EdgeInsets.symmetric(
                horizontal: MediaQuery.of(context).size.width * 0.05,
                vertical: MediaQuery.of(context).size.height * 0.05,
              ),
              child: Container(
                width: MediaQuery.of(context).size.width * 0.9,
                height: MediaQuery.of(context).size.height * 0.9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: FullscreenAdsPage(),
                ),
              ),
            ));
      },
    ).then((_) {
      // Dialog closed - 重置狀態並觸發狀態轉換到手動操作狀態
      setState(() {
        _isAdsDialogOpen = false;
        print('11111111111111 我关闭了全屏广告弹窗哦');
      });

      // 關閉全屏廣告彈窗後，自動切換到手動操作狀態
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final carouselProvider = context.read<CarouselStateProvider>();
          // 檢查當前是否在全屏廣告狀態，如果是則切換到手動操作狀態
          if (carouselProvider.currentAppState == AppState.fullscreenAd) {
            print('🔄 全屏廣告彈窗關閉，自動切換到手動操作狀態');
            carouselProvider.enterManualOperation();
          }
        }
      });

      // Fullscreen ad dialog closed log (always available)
      // print('Fullscreen ad dialog closed');
    });
  }

  //3， Method to close the ads dialog
  void closeAdsDialog() {
    if (_isAdsDialogOpen && Navigator.canPop(context)) {
      // 關閉彈窗前先記錄當前狀態
      final carouselProvider = context.read<CarouselStateProvider>();
      final wasInFullscreenAd =
          carouselProvider.currentAppState == AppState.fullscreenAd;

      Navigator.of(context).pop();

      // 如果之前在全屏廣告狀態，關閉後自動切換到手動操作狀態
      if (wasInFullscreenAd) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            print('🔄 通過closeAdsDialog關閉全屏廣告，自動切換到手動操作狀態');
            carouselProvider.enterManualOperation();
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen to AnnouncementProvider for changes
    final announcementProvider = context.watch<AnnouncementProvider>();
    final currentAnnouncements = announcementProvider.announcements;

    // If announcements have changed, re-initialize the mid widgets
    if (_previousAnnouncementsForBuild == null ||
        !listEquals(_previousAnnouncementsForBuild, currentAnnouncements)) {
      if (mounted) {
        // Ensure widget is still in the tree
        _previousAnnouncementsForBuild =
            List.from(currentAnnouncements); // Update the stored list
      }
    }

    return Consumer<CarouselStateProvider>(
      builder: (context, carouselState, child) {
        // Normal Page Layout
        return Scaffold(
          body: SafeArea(
            child: Listener(
              onPointerDown: (PointerDownEvent event) {
                // 檢測到按下後，調用用戶交互方法
                // 使用 addPostFrameCallback 延迟执行，避免在构建过程中调用 setState()
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    carouselState.onUserInteraction();
                    // User interaction detected log (always available)
                    // print('User interaction detected');
                    // print(carouselState.getStateDescription());
                  }
                });
              },
              child: const AnnouncementPage(),
            ),
          ),
        );
      },
    );
  }
}
