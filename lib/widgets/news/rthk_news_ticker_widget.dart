import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:iboard_app/providers/rthk_news_provider.dart';

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

  List<String> _newsTexts = [];
  List<String> _previousNewsTexts = [];
  String? _pendingNewsSignature;
  double _cycleWidth = 0;
  int _displayItemCount = 0;

  bool _isPaused = false;

  void Function(AnimationStatus)? _animationStatusListener;
  bool _isAnimating = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    );
  }

  @override
  void dispose() {
    _stopScrolling();
    _controller.dispose();
    super.dispose();
  }

  ///1, 计算一轮新闻文本的宽度
  double _calculateCycleWidth(List<String> texts) {
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
      totalWidth += textPainter.width + 80;
    }

    return totalWidth;
  }

  ///2, 啟動滾動動畫
  void _startScrolling() {
    if (_isAnimating || _cycleWidth <= widget.width) return;

    // 简化速度控制 - 恢复历史版本的稳定算法
    const scrollSpeed = 40.0; // 固定滚动速度 (像素/秒)
    final durationSeconds = (_cycleWidth / scrollSpeed).ceil(); // 向上取整确保完整滚动

    // 设置合理的时长范围 (10-120秒)
    final clampedDuration = durationSeconds.clamp(10, 120);
    _controller.duration = Duration(seconds: clampedDuration);

    // 先移除已有監聽器
    _removeListeners();

    _animationStatusListener = (AnimationStatus status) {
      if (status == AnimationStatus.completed && mounted) {
        _controller.reset();
        if (!_isPaused) {
          _controller.forward();
        }
      }
    };

    // 添加新監聽器
    _controller.addStatusListener(_animationStatusListener!);

    _isAnimating = true;
    _controller.forward();
  }

  ///3, 移除动画监听器
  void _removeListeners() {
    if (_animationStatusListener != null) {
      _controller.removeStatusListener(_animationStatusListener!);
      _animationStatusListener = null;
    }
  }

  ///4, 停止滚动动画
  void _stopScrolling() {
    _isAnimating = false;
    _controller.stop();
    _removeListeners();
  }

  ///5, 更新新聞數據並重新啟動滾動
  void _updateNews(List<String> newTexts) {
    final nextTexts = newTexts.isEmpty ? ['暫無新聞數據'] : newTexts;

    // 检查内容是否真的发生了变化
    if (nextTexts.length == _previousNewsTexts.length &&
        !nextTexts
            .asMap()
            .entries
            .any((e) => e.value != _previousNewsTexts[e.key])) {
      return;
    }

    final signature = nextTexts.join('\u001f');
    if (_pendingNewsSignature == signature) {
      return;
    }
    _pendingNewsSignature = signature;

    _newsTexts = nextTexts;
    _previousNewsTexts = List.from(_newsTexts);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_pendingNewsSignature != signature) return;
      _pendingNewsSignature = null;

      _cycleWidth = _calculateCycleWidth(_newsTexts);
      _displayItemCount = _resolveDisplayItemCount();
      setState(() {});

      // 延迟一帧再重新开始动画，确保UI已更新
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _stopScrolling();
        _controller.reset();
        _startScrolling();
      });
    });
  }

  ///6, 根据Provider状态处理滚动控制
  void _handleProviderPauseState(bool isProviderPaused) {
    if (isProviderPaused && !_isPaused) {
      _pauseScrolling();
    } else if (!isProviderPaused && _isPaused) {
      _resumeScrolling();
    }
  }

  ///7, 暂停滚动
  void _pauseScrolling() {
    _isPaused = true;
    _controller.stop();
  }

  ///8, 恢復滾動
  void _resumeScrolling() {
    if (_isPaused && mounted) {
      _isPaused = false;
      if (_isAnimating) {
        _controller.forward();
      } else {
        _startScrolling();
      }
    }
  }

  ///9, 智能确定显示项目数量
  int _resolveDisplayItemCount() {
    if (_newsTexts.isEmpty) return 0;
    if (_cycleWidth <= widget.width) {
      return _newsTexts.length;
    }
    return _newsTexts.length * 2;
  }

  ///10, 构建渐变遮罩，避免文字在边缘处突然出现或消失
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
    return Selector<RthkNewsProvider, _RthkTickerData>(
      selector: (_, newsProvider) => _RthkTickerData(
        texts: newsProvider.getAllNewsDisplayTexts(),
        isPaused: newsProvider.isScrollingPaused,
      ),
      builder: (context, tickerData, child) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handleProviderPauseState(tickerData.isPaused);
        });

        _updateNews(tickerData.texts);

        return RepaintBoundary(
          child: Container(
            height: widget.height,
            width: widget.width,
            decoration: BoxDecoration(
              color: Colors.blue.shade50.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(4),
            ),
            child: ClipRect(
              child: _buildFadeMask(
                Align(
                  alignment: Alignment.centerLeft,
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    minWidth: 0,
                    maxWidth: double.infinity,
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) {
                        return Transform.translate(
                          offset: Offset(-_controller.value * _cycleWidth, 0),
                          child: child,
                        );
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(_displayItemCount, (index) {
                          final text = _newsTexts[index % _newsTexts.length];
                          return Padding(
                            padding: const EdgeInsets.only(right: 80),
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
                        }),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

@immutable
class _RthkTickerData {
  final List<String> texts;
  final bool isPaused;

  _RthkTickerData({
    required List<String> texts,
    required this.isPaused,
  }) : texts = List.unmodifiable(texts);

  @override
  bool operator ==(Object other) {
    return other is _RthkTickerData &&
        other.isPaused == isPaused &&
        _listEquals(other.texts, texts);
  }

  @override
  int get hashCode => Object.hash(Object.hashAll(texts), isPaused);
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
