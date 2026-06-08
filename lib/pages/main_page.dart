import 'dart:async'; // Added import for Timer

import 'package:flutter/material.dart';
import 'package:iboard_app/pages/fullscreen_ads_page.dart';
import 'package:iboard_app/pages/mainscreen_page.dart';
import 'package:iboard_app/providers/announcement_provider.dart';
import 'package:iboard_app/providers/state_provider.dart'; // Added import for CarouselStateProvider
import 'package:iboard_app/providers/announcement_carousel_provider.dart'; // Added import for AnnouncementCarouselProvider
import 'package:logger/logger.dart';

import 'package:provider/provider.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  MainPageState createState() => MainPageState();
}

class MainPageState extends State<MainPage> {
  Timer? _mainTimer;
  bool _isAdsDialogOpen = false;
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

    carouselProvider.resetToDefault(); // 使用resetToDefault確保計時器正確啟動

    // 设置Provider之间的引用关系
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final announcementProvider = context.read<AnnouncementProvider>();
        final announcementCarouselProvider =
            context.read<AnnouncementCarouselProvider>();

        // 设置通告轮播Provider引用
        announcementProvider.setCarouselProvider(announcementCarouselProvider);
      }
    });
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
              child: SizedBox(
                width: MediaQuery.of(context).size.width * 0.9,
                height: MediaQuery.of(context).size.height * 0.9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: const FullscreenAdsPage(),
                ),
              ),
            ));
      },
    ).then((_) {
      // Dialog closed - 重置狀態並觸發狀態轉換到手動操作狀態
      setState(() {
        _isAdsDialogOpen = false;
      });
      //  修復：只有在真正由用戶關閉時才切換到手動操作狀態
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final carouselProvider = context.read<CarouselStateProvider>();
          final wasInFullscreenAd =
              carouselProvider.currentAppState == AppState.fullscreenAd;

          //  重要修復：檢查當前狀態，如果已經是默認狀態說明是定時器自動退出
          if (carouselProvider.currentAppState == AppState.defaultState) {
            Logger().i(' 全屏廣告已自動退出到默認狀態，保持默認狀態不變');
          } else if (wasInFullscreenAd) {
            // 只有仍在全屏廣告狀態時才認為是用戶手動關閉
            Logger().i(' 用戶手動關閉全屏廣告，切換到手動操作狀態');
            carouselProvider.enterManualOperation();

            // 通知通告轮播提供者回到主屏幕
            final announcementCarouselProvider =
                context.read<AnnouncementCarouselProvider>();
            announcementCarouselProvider.jumpToAnnouncementIndex(0);
          }
        }
      });
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
            debugPrint('[MainPage] 通過closeAdsDialog關閉全屏廣告，自動切換到手動操作狀態');
            carouselProvider.enterManualOperation();

            // 通知通告轮播提供者回到主屏幕
            final announcementCarouselProvider =
                context.read<AnnouncementCarouselProvider>();
            announcementCarouselProvider.jumpToAnnouncementIndex(0);
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Listener(
          onPointerDown: (PointerDownEvent event) {
            context.read<CarouselStateProvider>().onUserInteraction();
            debugPrint('[main_page]  檢測到用戶交互');
          },
          child: const AnnouncementPage(),
        ),
      ),
    );
  }
}
