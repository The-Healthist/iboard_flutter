import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:iboard_app/providers/rthk_news_provider.dart';
import 'package:iboard_app/widgets/debug_rthk_news_widget.dart';
import 'package:iboard_app/providers/fullscreen_ad_provider.dart';
import 'package:logger/logger.dart';

/// 优化后的香港电台新闻跑马灯组件
/// 使用ScrollController和AnimationController实现水平连续滚动
/// 结合渐变遮罩避免文字溢出和布局错乱
class RthkNewsTickerWidget extends StatefulWidget {
  final double height;
  final double width;

  const RthkNewsTickerWidget({
    Key? key,
    required this.height,
    required this.width,
  }) : super(key: key);

  @override
  _RthkNewsTickerWidgetState createState() => _RthkNewsTickerWidgetState();
}

class _RthkNewsTickerWidgetState extends State<RthkNewsTickerWidget>
    with SingleTickerProviderStateMixin {
  final Logger _logger = Logger();

  late AnimationController _controller;
  late ScrollController _scrollController;

  List<String> _newsTexts = [];
  List<String> _previousNewsTexts = [];

  bool _isPaused = false;
  double _totalContentWidth = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  double _calculateTotalWidth(List<String> texts) {
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    double totalWidth = 0;

    for (final text in texts) {
      textPainter.text = TextSpan(
        text: text,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      );
      textPainter.layout();
      totalWidth += textPainter.width + 56;
    }

    final minWidth = widget.width * 2;
    return totalWidth > minWidth ? totalWidth : minWidth;
  }

  void _startScrolling() {
    if (!_scrollController.hasClients) return;

    final maxScrollExtent = _scrollController.position.maxScrollExtent;
    const scrollSpeed = 50.0;
    final durationSeconds = (maxScrollExtent / scrollSpeed).ceil();

    if (durationSeconds <= 0) return;

    _controller.duration = Duration(seconds: durationSeconds);

// 定义监听器变量
    void _animationListener() {
      if (!_isPaused) {
        final offset = _controller.value * maxScrollExtent;
        _scrollController.jumpTo(offset);
      }
    }

    void _animationStatusListener(AnimationStatus status) {
      if (status == AnimationStatus.completed) {
        _controller.reset();
        _controller.forward();
      }
    }

// 先移除已有监听器
    _controller.removeListener(_animationListener);
    _controller.removeStatusListener(_animationStatusListener);

// 添加监听器
    _controller.addListener(_animationListener);
    _controller.addStatusListener(_animationStatusListener);
    _controller.addStatusListener(_animationStatusListener);
    _controller.forward();

    _logger.i('▶️ 跑马灯动画启动，滚动宽度: $_totalContentWidth');
  }

  void _stopScrolling() {
    _controller.stop();
  }

  void _updateNews(List<String> newTexts) {
    if (newTexts.isEmpty) {
      _newsTexts = ['暂无新闻数据'];
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

      _scrollController.jumpTo(0);

      setState(() {});

      _stopScrolling();
      _controller.reset();
      _startScrolling();
    });
  }

  void _handleFullscreenAdChange(bool isActive) {
    if (isActive && !_isPaused) {
      _pauseScrolling();
    } else if (!isActive && _isPaused) {
      _resumeScrolling();
    }
  }

  void _pauseScrolling() {
    _isPaused = true;
    _stopScrolling();
    _logger.i('⏸️ 跑马灯动画暂停（全屏广告）');
  }

  void _resumeScrolling() {
    if (_isPaused) {
      _isPaused = false;
      _controller.forward();
      _logger.i('▶️ 跑马灯动画恢复');
    }
  }

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
          stops: [0.0, 0.05, 0.95, 1.0],
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
                itemCount: _newsTexts.length * 2,
                itemBuilder: (context, index) {
                  final text = _newsTexts[index % _newsTexts.length];
                  return Container(
                    margin: const EdgeInsets.only(right: 56),
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
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
