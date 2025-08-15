import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:iboard_app/providers/rthk_news_provider.dart';
import 'package:iboard_app/models/rthk_news_model.dart';
import 'package:iboard_app/widgets/debug_rthk_news_widget.dart';
import 'package:iboard_app/providers/fullscreen_ad_provider.dart';
import 'package:logger/logger.dart';
import 'dart:async'; // Added for Timer

/// 香港电台新闻跑马灯组件
/// 从右到左循环展示新闻数据
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
    with TickerProviderStateMixin {
  final Logger _logger = Logger(); // 添加Logger实例
  late AnimationController _animationController;
  late Animation<double> _animation;
  List<String> _newsTexts = [];
  Timer? _newsTimer;
  bool _isPaused = false; // 新增：暂停状态标记
  
  // 新增：用于检测数据是否真正更新
  List<String> _previousNewsTexts = [];
  bool _isDataUpdated = false;

  @override
  void initState() {
    super.initState();
    _setupAnimation();
    _startNewsTimer();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _newsTimer?.cancel();
    super.dispose();
  }

  ///1, 设置动画控制器 - 使用动态滚动时间
  void _setupAnimation() {
    // 动态计算滚动时间：根据内容长度和期望的滚动速度
    final totalWidth = _getTotalTextWidth();
    final scrollSpeed = 50.0; // 每秒滚动50像素

    // 确保动画范围不会超出合理范围
    // 从右边缘开始，到第一轮新闻完全滚出屏幕结束
    final animationEnd = -(totalWidth - widget.width * 0.1); // 留出10%的屏幕宽度作为缓冲
    final duration = (totalWidth + widget.width * 0.9) / scrollSpeed; // 调整总距离计算

    _animationController = AnimationController(
      duration: Duration(seconds: duration.ceil()), // 动态计算时间
      vsync: this,
    );

    // 连续滚动：从右到左，包含所有新闻
    _animation = Tween<double>(
      begin: widget.width, // 从右边缘开始
      end: animationEnd, // 第一轮新闻完全滚出，但留出缓冲空间
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.linear,
    ));

    // 动画完成后重新开始，实现无限循环
    _animationController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _restartAnimation();
      }
    });
  }

  ///2, 启动新闻定时器
  void _startNewsTimer() {
    _newsTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          // 触发UI更新
        });
      }
    });
  }

  ///3, 计算所有新闻文本的总宽度
  double _getTotalTextWidth() {
    if (_newsTexts.isEmpty) return widget.width;

    // 使用更精确的文本宽度计算
    double totalWidth = 0;
    
    // 创建TextPainter来精确计算文本宽度
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
    );
    
    for (String text in _newsTexts) {
      // 使用TextPainter精确计算每个文本的宽度
      textPainter.text = TextSpan(
        text: text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      );
      textPainter.layout();
      
      // 获取精确的文本宽度，加上右边距
      totalWidth += textPainter.width + 56.0; // 56像素的右边距
    }
    
    // 确保最小宽度，至少是屏幕宽度的2倍
    final minWidth = widget.width * 2;
    return totalWidth > minWidth ? totalWidth : minWidth;
  }

  ///4, 重新开始动画
  void _restartAnimation() {
    if (!_isPaused && _newsTexts.isNotEmpty) {
      _animationController.reset();
      _animationController.forward();
    }
  }

  ///5, 重新计算动画时间（当新闻数据变化时调用）
  void _recalculateAnimation() {
    if (_newsTexts.isNotEmpty) {
      final totalWidth = _getTotalTextWidth();
      final scrollSpeed = 50.0; // 每秒滚动50像素
      
      // 确保动画范围不会超出合理范围
      // 从右边缘开始，到第一轮新闻完全滚出屏幕结束
      final animationEnd = -(totalWidth - widget.width * 0.1); // 留出10%的屏幕宽度作为缓冲
      final duration = (totalWidth + widget.width * 0.9) / scrollSpeed; // 调整总距离计算
      
      // 更新动画控制器的持续时间
      _animationController.duration = Duration(seconds: duration.ceil());
      
      // 更新动画范围
      _animation = Tween<double>(
        begin: widget.width,
        end: animationEnd, // 第一轮新闻完全滚出，但留出缓冲空间
      ).animate(CurvedAnimation(
        parent: _animationController,
        curve: Curves.linear,
      ));
      
      _logger.i(
          '🔄 重新计算动画时间: ${duration.ceil()}秒，总宽度: ${totalWidth.toStringAsFixed(1)}像素，结束位置: ${animationEnd.toStringAsFixed(1)}像素');
    }
  }

  ///6, 构建新闻文本列表
  List<String> _buildNewsTexts(RthkNewsProvider provider) {
    if (provider.newsList.isEmpty) {
      return ['暂无新闻数据'];
    }
    return provider.getAllNewsDisplayTexts();
  }

  ///6.1, 检测数据是否真正更新
  bool _hasDataChanged(List<String> newTexts) {
    if (_previousNewsTexts.length != newTexts.length) {
      return true;
    }
    
    for (int i = 0; i < newTexts.length; i++) {
      if (i >= _previousNewsTexts.length || _previousNewsTexts[i] != newTexts[i]) {
        return true;
      }
    }
    
    return false;
  }

  ///7, 构建新闻行显示
  List<Widget> _buildNewsRow() {
    List<Widget> widgets = [];

    // 为了实现无缝循环，我们需要重复显示新闻
    // 第一轮：原始新闻
    for (int i = 0; i < _newsTexts.length; i++) {
      widgets.add(
        Container(
          margin: EdgeInsets.only(right: 56.0), // 4个字符的间距
          child: Text(
            _newsTexts[i],
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.visible,
          ),
        ),
      );
    }

    // 第二轮：重复新闻（实现无缝循环）
    for (int i = 0; i < _newsTexts.length; i++) {
      widgets.add(
        Container(
          margin: EdgeInsets.only(right: 56.0), // 4个字符的间距
          child: Text(
            _newsTexts[i],
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.visible,
          ),
        ),
      );
    }

    return widgets;
  }

  ///6, 显示调试窗口
  void _showDebugDialog(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('RTHK新闻调试信息'),
            // backgroundColor: Colors.blue.shade600,
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () {
                  final provider = context.read<RthkNewsProvider>();
                  provider.refreshNews();
                },
                tooltip: '刷新',
              ),
            ],
          ),
          body: const DebugRthkNewsWidget(),
        ),
      ),
    );
  }

  ///7, 处理全屏广告状态变化
  void _handleFullscreenAdStateChange(bool isFullscreenAdActive) {
    if (isFullscreenAdActive && !_isPaused) {
      // 进入全屏广告状态，暂停动画
      _pauseAnimation();
    } else if (!isFullscreenAdActive && _isPaused) {
      // 退出全屏广告状态，恢复动画
      _resumeAnimation();
    }
  }

  ///8, 暂停动画
  void _pauseAnimation() {
    if (!_isPaused) {
      _isPaused = true;
      _animationController.stop();
      _logger.i('⏸️ 新闻跑马灯已暂停（全屏广告状态）');
    }
  }

  ///9, 恢复动画
  void _resumeAnimation() {
    if (_isPaused) {
      _isPaused = false;
      if (_newsTexts.isNotEmpty) {
        // 恢复后立即启动动画
        _animationController.forward();
        _logger.i('▶️ 新闻跑马灯已恢复');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<RthkNewsProvider, FullscreenAdProvider>(
      builder: (context, newsProvider, fullscreenAdProvider, child) {
        // 监听全屏广告状态变化
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handleFullscreenAdStateChange(fullscreenAdProvider.isActive);
        });

        // 更新新闻文本列表
        _newsTexts = _buildNewsTexts(newsProvider);
        
        // 检测数据是否真正更新
        _isDataUpdated = _hasDataChanged(_newsTexts);
        
        // 当新闻数据真正变化时，重新计算动画时间
        if (_isDataUpdated && _newsTexts.isNotEmpty && !_isPaused) {
          _logger.i('🔄 检测到新闻数据更新，重新计算轮播时间');
          _recalculateAnimation();
          // 更新前一次的数据记录
          _previousNewsTexts = List.from(_newsTexts);
        }

        // 如果没有新闻，显示默认信息
        if (_newsTexts.isEmpty) {
          return Container(
            height: widget.height,
            width: widget.width,
            // 取消背景色
            child: const Center(
              child: Text(
                '暂无新闻数据',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 14,
                ),
              ),
            ),
          );
        }

        // 启动动画（如果还没有启动且有新闻数据且未暂停）
        if (!_animationController.isAnimating &&
            _newsTexts.isNotEmpty &&
            !_isPaused) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _newsTexts.isNotEmpty && !_isPaused) {
              // 启动连续滚动动画
              _animationController.forward();
            }
          });
        }

        return Container(
          height: widget.height,
          width: widget.width,
          // 添加淡蓝色背景
          decoration: BoxDecoration(
            color: Colors.blue.shade50.withOpacity(0.3), // 淡蓝色背景
          ),
          child: Stack(
            children: [
              // 新闻内容跑马灯 - 使用连续滚动方式
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                bottom: 0,
                child: AnimatedBuilder(
                  animation: _animation,
                  builder: (context, child) {
                    if (_newsTexts.isEmpty) {
                      return const SizedBox.shrink();
                    }

                    // 使用连续滚动，显示所有新闻
                    return Transform.translate(
                      offset: Offset(_animation.value, 0),
                      child: Row(
                        children: _buildNewsRow(),
                      ),
                    );
                  },
                ),
              ),

              // Debug按钮 - 右上角
              Positioned(
                top: 4,
                right: 8,
                child: GestureDetector(
                  onTap: () => _showDebugDialog(context),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6), // 半透明黑色背景
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white, width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.bug_report,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                ),
              ),

              // 新闻计数指示器 - 左下角
              // Positioned(
              //   bottom: 4,
              //   left: 8,
              //   child: Container(
              //     padding:
              //         const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              //     decoration: BoxDecoration(
              //       color: Colors.black.withOpacity(0.6), // 半透明黑色背景
              //       borderRadius: BorderRadius.circular(10),
              //     ),
              //     child: Text(
              //       '${_newsTexts.length}条新闻',
              //       style: const TextStyle(
              //         color: Colors.white, // 白色文字
              //         fontSize: 10,
              //         fontWeight: FontWeight.bold,
              //       ),
              //     ),
              //   ),
              // ),

              // 暂停状态指示器 - 右下角（当暂停时显示）
              if (_isPaused)
                Positioned(
                  bottom: 4,
                  right: 40, // 调整位置，避免与Debug按钮重叠
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.8), // 半透明橙色背景
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.pause,
                      color: Colors.white, // 白色图标
                      size: 12,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
