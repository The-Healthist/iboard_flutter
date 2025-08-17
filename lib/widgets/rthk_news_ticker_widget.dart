import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:iboard_app/providers/rthk_news_provider.dart';
import 'package:iboard_app/widgets/debug_rthk_news_widget.dart';
import 'package:iboard_app/providers/fullscreen_ad_provider.dart';
import 'package:logger/logger.dart';

/// 优化后的香港电台新闻跑马灯组件
/// 使用ScrollController和AnimationController实现水平连续滚动
/// 结合渐变遮罩避免文字溢出和布局错乱
/// 确保新闻标题完整显示，不被截断
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

  ///2, 启动滚动动画
  void _startScrolling() {
    if (!_scrollController.hasClients) return;

    final maxScrollExtent = _scrollController.position.maxScrollExtent;
    const scrollSpeed = 40.0; // 降低滚动速度，让用户更容易阅读长标题
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

  ///3, 停止滚动动画
  void _stopScrolling() {
    _controller.stop();
  }

  ///4, 更新新闻数据并重新启动滚动
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
    _logger.i('⏸️ 跑马灯动画暂停（全屏广告）');
  }

  ///7, 恢复滚动
  void _resumeScrolling() {
    if (_isPaused) {
      _isPaused = false;
      _controller.forward();
      _logger.i('▶️ 跑马灯动画恢复');
    }
  }

  ///8, 构建渐变遮罩，避免文字在边缘处突然出现或消失
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
                itemCount: _newsTexts.length * 2, // 重复显示两次，确保无缝循环
                itemBuilder: (context, index) {
                  final text = _newsTexts[index % _newsTexts.length];
                  return Container(
                    margin:
                        const EdgeInsets.only(right: 80), // 增加右边距，确保新闻之间有足够间隔
                    // 移除maxWidth限制，让文字能够完整显示
                    child: Text(
                      text,
                      // 移除maxLines和overflow限制，确保文字完整显示
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        height: 1.2, // 添加行高，让文字更易读
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
