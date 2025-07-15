import 'dart:async'; // Added import for Timer

import 'package:flutter/foundation.dart' show listEquals, kDebugMode;
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
  bool _isAdsDialogOpen = false; // Track dialog state

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
  }

  // Method to show FullscreenAdsPage in a dialog
  void showAdsDialog() {
    if (_isAdsDialogOpen) return; // Prevent multiple dialogs

    setState(() {
      _isAdsDialogOpen = true;
    });

    showDialog(
      context: context,
      barrierDismissible: true,
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
      // Dialog closed - 重置狀態但不觸發狀態轉換（由計時器或回調處理）
      setState(() {
        _isAdsDialogOpen = false;
      });
      if (kDebugMode) {
        print('Fullscreen ad dialog closed');
      }
    });
  }

  // Method to close the ads dialog
  void closeAdsDialog() {
    if (_isAdsDialogOpen && Navigator.canPop(context)) {
      Navigator.of(context).pop();
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
                carouselState.onUserInteraction();
                if (kDebugMode) {
                  print('User interaction detected');
                  print(carouselState.getStateDescription());
                }
              },
              child: AnnouncementPage(),
            ),
          ),
        );
      },
    );
  }
}
