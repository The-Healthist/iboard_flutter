import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:iboard_app/providers/fullscreen_ad_provider.dart';
import 'package:iboard_app/providers/state_provider.dart';
import 'package:provider/provider.dart';

/// 全屏广告时间调试组件
/// 显示当前广告剩余时间和全屏状态总时间
class DebugFullAdTimeWidget extends StatefulWidget {
  const DebugFullAdTimeWidget({Key? key}) : super(key: key);

  @override
  _DebugFullAdTimeWidgetState createState() => _DebugFullAdTimeWidgetState();
}

class _DebugFullAdTimeWidgetState extends State<DebugFullAdTimeWidget> {
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    _startUpdateTimer();
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  ///1，启动更新定时器 - 每秒更新一次时间显示
  void _startUpdateTimer() {
    _updateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          // 触发UI更新
        });
      }
    });
  }

  ///2，计算当前广告剩余时间
  String _getCurrentAdRemainingTime(FullscreenAdProvider fullscreenProvider) {
    if (!fullscreenProvider.isActive || fullscreenProvider.isPaused) {
      return "暂停";
    }

    final currentAd = fullscreenProvider.getCurrentAd();
    if (currentAd == null || fullscreenProvider.currentAdStartTime == null) {
      return "无广告";
    }

    final now = DateTime.now();
    final elapsed = now.difference(fullscreenProvider.currentAdStartTime!);
    final totalElapsed = elapsed + fullscreenProvider.adElapsedTime;

    // 使用广告自身时长和全屏广告播放时长的较小值
    final adDuration = currentAd.durationObject;
    final fullscreenDuration =
        Duration(seconds: fullscreenProvider.fullscreenAdDuration);
    final effectiveDuration =
        adDuration.inSeconds < fullscreenDuration.inSeconds
            ? adDuration
            : fullscreenDuration;

    final remaining = effectiveDuration - totalElapsed;

    if (remaining.isNegative) {
      return "即将切换";
    }

    return "${remaining.inSeconds}s";
  }

  ///3，计算全屏状态信息
  String _getFullscreenStateInfo(CarouselStateProvider stateProvider,
      FullscreenAdProvider fullscreenProvider) {
    if (stateProvider.currentAppState != AppState.fullscreenAd) {
      return "非全屏状态";
    }

    // 显示全屏广告配置的总时长
    final configuredDuration = stateProvider.fullscreenAdDuration;
    String stateInfo = "状态总时长: ${configuredDuration}s";

    // 使用全屏状态开始时间而不是当前广告开始时间
    if (fullscreenProvider.currentStateStartTime != null) {
      final elapsed =
          DateTime.now().difference(fullscreenProvider.currentStateStartTime!);
      final remaining = configuredDuration - elapsed.inSeconds;
      stateInfo += "\n状态已过: ${elapsed.inSeconds}s";
      stateInfo += "\n状态剩余: ${remaining > 0 ? remaining : 0}s";
    } else {
      stateInfo += "\n状态未开始";
    }

    return stateInfo;
  }

  ///4，获取当前广告信息
  String _getCurrentAdInfo(FullscreenAdProvider fullscreenProvider) {
    if (!fullscreenProvider.isActive) {
      return "未激活";
    }

    final currentAd = fullscreenProvider.getCurrentAd();
    if (currentAd == null) {
      return "无广告";
    }

    final currentIndex = fullscreenProvider.currentAdIndex;
    final totalAds = fullscreenProvider.fullscreenAds.length;
    final adTitle = currentAd.title.length > 10
        ? '${currentAd.title.substring(0, 10)}...'
        : currentAd.title;

    return "$adTitle (${currentIndex + 1}/$totalAds)";
  }

  ///5，获取轮播顺序列表
  List<Widget> _buildCarouselList(FullscreenAdProvider fullscreenProvider) {
    if (fullscreenProvider.fullscreenAds.isEmpty) {
      return [
        Text(
          '📋 轮播列表: 无广告',
          style: TextStyle(
            color: Colors.yellow,
            fontSize: 11,
          ),
        ),
      ];
    }

    List<Widget> widgets = [
      Text(
        '📋 轮播顺序 (${fullscreenProvider.fullscreenAds.length}个):',
        style: TextStyle(
          color: Colors.yellow,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(height: 2),
    ];

    for (int i = 0; i < fullscreenProvider.fullscreenAds.length; i++) {
      final ad = fullscreenProvider.fullscreenAds[i];
      final isCurrentAd = i == fullscreenProvider.currentAdIndex;
      final adTitle =
          ad.title.length > 8 ? '${ad.title.substring(0, 8)}...' : ad.title;
      final duration = ad.durationObject.inSeconds;

      widgets.add(
        Text(
          '${isCurrentAd ? "👉" : "  "}${i + 1}. $adTitle (${duration}s)',
          style: TextStyle(
            color: isCurrentAd ? Colors.orange : Colors.white70,
            fontSize: 10,
            fontWeight: isCurrentAd ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      );
    }

    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    // 强制显示调试widget（包括Release模式）
    // if (!kDebugMode) {
    //   return const SizedBox.shrink();
    // }

    return Positioned(
      right: 10,
      bottom: 10,
      child: Consumer2<FullscreenAdProvider, CarouselStateProvider>(
        builder: (context, fullscreenProvider, stateProvider, child) {
          // 只有在全屏广告状态下才显示
          if (stateProvider.currentAppState != AppState.fullscreenAd) {
            return const SizedBox.shrink();
          }

          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.8),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange, width: 2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题
                Text(
                  '🎬 全屏广告调试',
                  style: TextStyle(
                    color: Colors.orange,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),

                // 轮播顺序列表
                ..._buildCarouselList(fullscreenProvider),
                const SizedBox(height: 8),

                // 当前广告信息
                Text(
                  '当前: ${_getCurrentAdInfo(fullscreenProvider)}',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),

                // 当前广告剩余时间
                Text(
                  '剩余: ${_getCurrentAdRemainingTime(fullscreenProvider)}',
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),

                // 全屏状态信息
                Text(
                  _getFullscreenStateInfo(stateProvider, fullscreenProvider),
                  style: TextStyle(
                    color: Colors.cyan,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),

                // 状态信息
                Text(
                  '状态: ${fullscreenProvider.isPaused ? "⏸️暂停" : "▶️播放"}',
                  style: TextStyle(
                    color:
                        fullscreenProvider.isPaused ? Colors.red : Colors.green,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
