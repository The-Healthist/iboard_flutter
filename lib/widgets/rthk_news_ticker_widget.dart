import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import 'package:iboard_app/providers/rthk_news_provider.dart';
import 'package:iboard_app/providers/ad_full_carousel_provider.dart';

class RthkNewsTickerWidget extends StatefulWidget {
  final double height;
  final double width;

  const RthkNewsTickerWidget({
    super.key,
    required this.height,
    required this.width,
  });

  @override
  RthkNewsTickerWidgetState createState() => RthkNewsTickerWidgetState();
}

class RthkNewsTickerWidgetState extends State<RthkNewsTickerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late ScrollController _scrollController;

  List<String> _newsTexts = [];
  List<String> _previousNewsTexts = [];

  bool _isPaused = false;
  double _totalContentWidth = 0;
  final Logger logger = Logger();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    );
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  ///1, 计算所有新闻文本的总宽度
  double _calculateTotalWidth(List<String> texts) {
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    double totalWidth = 0;

    for (final text in texts) {
      textPainter.text = TextSpan(
        text: text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          height: 1.2,
        ),
      );
      textPainter.layout();
      // 为每条新闻添加足够的间距，确保完整显示
      totalWidth += textPainter.width + 80; // 增加间距从56到80
    }

    // 确保总宽度至少是容器宽度的2倍，保证滚动效果
    final minWidth = widget.width * 2;
    return totalWidth > minWidth ? totalWidth : minWidth;
  }

  ///2, 啟動滾動動畫
  void _startScrolling() {
    if (!_scrollController.hasClients) return;

    final maxScrollExtent = _scrollController.position.maxScrollExtent;
    const scrollSpeed = 40.0; // 降低滾動速度，讓使用者更易讀
    final durationSeconds = (maxScrollExtent / scrollSpeed).ceil();

    if (durationSeconds <= 0) return;

    _controller.duration = Duration(seconds: durationSeconds);

// 定义监听器变量
    void animationListener() {
      if (!_isPaused) {
        final offset = _controller.value * maxScrollExtent;
        _scrollController.jumpTo(offset);
      }
    }

    void animationStatusListener(AnimationStatus status) {
      if (status == AnimationStatus.completed) {
        _controller.reset();
        _controller.forward();
      }
    }

// 先移除已有監聽器
    _controller.removeListener(animationListener);
    _controller.removeStatusListener(animationStatusListener);

// 添加監聽器
    _controller.addListener(animationListener);
    _controller.addStatusListener(animationStatusListener);
    _controller.forward();
  }

  ///3, 停止滚动动画
  void _stopScrolling() {
    _controller.stop();
  }

  ///4, 更新新聞數據並重新啟動滾動
  void _updateNews(List<String> newTexts) {
    if (newTexts.isEmpty) {
      _newsTexts = ['暫無新聞數據'];
    } else {
      _newsTexts = newTexts;
    }

    if (_newsTexts.length == _previousNewsTexts.length &&
        !_newsTexts
            .asMap()
            .entries
            .any((e) => e.value != _previousNewsTexts[e.key])) {
      return;
    }

    _previousNewsTexts = List.from(_newsTexts);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      _totalContentWidth = _calculateTotalWidth(_newsTexts);
      // 調試：總寬度
      logger.i('總寬度: $_totalContentWidth');
      _scrollController.jumpTo(0);

      setState(() {});

      _stopScrolling();
      _controller.reset();
      _startScrolling();
    });
  }

  ///5, 处理全屏广告状态变化
  void _handleFullscreenAdChange(bool isActive) {
    if (isActive && !_isPaused) {
      _pauseScrolling();
    } else if (!isActive && _isPaused) {
      _resumeScrolling();
    }
  }

  ///6, 暂停滚动
  void _pauseScrolling() {
    _isPaused = true;
    _stopScrolling();
  }

  ///7, 恢復滾動
  void _resumeScrolling() {
    if (_isPaused) {
      _isPaused = false;
      // 確保存在有效時長
      _controller.duration ??= const Duration(seconds: 30);
      _controller.forward();
    }
  }

  ///8, 智能确定显示项目数量
  int _getItemCount() {
    // 如果只有一条新闻（通常是网络错误提示），检查是否需要滚动
    if (_newsTexts.length == 1) {
      // 计算單条新闻的宽度
      final textPainter = TextPainter(textDirection: TextDirection.ltr);
      textPainter.text = TextSpan(
        text: _newsTexts.first,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          height: 1.2,
        ),
      );
      textPainter.layout();

      // 如果單条新闻宽度小于容器宽度，不需要滚动，只显示一次
      if (textPainter.width < widget.width - 160) {
        // 减去左右边距
        return 1;
      }
      // 如果單条新闻很长，需要重复显示来实现滚动
      return 2;
    }
    // 如果有多条新闻，重复显示两次确保无缝循环
    return _newsTexts.length * 2;
  }

  ///9, 构建渐变遮罩，避免文字在边缘处突然出现或消失
  Widget _buildFadeMask(Widget child) => ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.transparent,
            Colors.black,
            Colors.black,
            Colors.transparent
          ],
          stops: [0.0, 0.08, 0.92, 1.0], // 调整渐变范围，让文字显示更清晰
        ).createShader(bounds),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    return Consumer2<RthkNewsProvider, FullscreenAdProvider>(
      builder: (context, newsProvider, fullscreenProvider, child) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handleFullscreenAdChange(fullscreenProvider.isActive);
        });

        _updateNews(newsProvider.getAllNewsDisplayTexts());

        return Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            color: Colors.blue.shade50.withOpacity(0.3),
            borderRadius: BorderRadius.circular(4),
          ),
          child: ClipRect(
            child: _buildFadeMask(
              ListView.builder(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _getItemCount(), // 根據新聞數量智能決定顯示次數
                itemBuilder: (context, index) {
                  final text = _newsTexts[index % _newsTexts.length];
                  return Container(
                    margin: const EdgeInsets.only(right: 80),
                    child: Text(
                      text,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        height: 1.2,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
