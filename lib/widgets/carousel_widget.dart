import 'package:flutter/material.dart';
import 'dart:async';

/// 媒体暂停通知类
class MediaPauseNotification extends Notification {}

/// 媒体恢复通知类
class MediaResumeNotification extends Notification {}

/// Controller for the CarouselWidget that provides programmatic access to carousel functions
class CarouselController {
  _CarouselWidgetState? _state;

  void _attach(_CarouselWidgetState state) {
    _state = state;
  }

  void _detach() {
    _state = null;
  }

  /// Set the carousel array with a new list of widgets
  void setCarouselArray(List<Widget> widgets) {
    _state?.setCarouselArray(widgets);
  }

  /// Clear all widgets from the carousel
  void clearCarouselArray() {
    _state?.clearCarouselArray();
  }

  /// Delete a widget at the specified index
  void delete(int index) {
    _state?.delete(index);
  }

  /// Add a widget to the end of the carousel
  void push(Widget widget) {
    _state?.push(widget);
  }

  /// Play the next widget (loops to first if at end)
  void playNext() {
    _state?.playNext();
  }

  /// Play the previous widget (loops to last if at beginning)
  void playPrev() {
    _state?.playPrev();
  }

  /// Jump to a specific index without animation
  void jumpToIndex(int index) {
    _state?.jumpToIndex(index);
  }

  /// Pause all video content in the carousel
  void pauseAllMedia() {
    _state?.pauseAllMedia();
  }

  /// Resume all video content in the carousel
  void resumeAllMedia() {
    _state?.resumeAllMedia();
  }

  /// Get current index
  int get currentIndex => _state?.currentIndex ?? 0;

  /// Get total count of widgets
  int get widgetCount => _state?.widgetCount ?? 0;

  /// Get current widget
  Widget? get currentWidget => _state?.currentWidget;

  /// Check if controller is attached to a widget
  bool get isAttached => _state != null;
}

/// A carousel widget that displays different widgets one by one with smooth transitions
/// Provides comprehensive control over the carousel including navigation and array management
class CarouselWidget extends StatefulWidget {
  /// List of widgets to display in the carousel
  final List<Widget> initialWidgets;

  /// Duration for auto-play (set to null to disable auto-play)
  final Duration? autoPlayDuration;

  /// Animation duration for transitions
  final Duration animationDuration;

  /// Animation curve for transitions
  final Curve animationCurve;

  /// Whether to show page indicators
  final bool showIndicators;

  /// Whether to allow manual swiping
  final bool allowManualSwipe;

  /// Callback when page changes
  final Function(int index)? onPageChanged;

  /// Height of the carousel (if null, takes available height)
  final double? height;

  /// Controller for programmatic access to carousel functions
  final CarouselController? controller;

  const CarouselWidget({
    Key? key,
    this.initialWidgets = const [],
    this.autoPlayDuration,
    this.animationDuration = const Duration(milliseconds: 300),
    this.animationCurve = Curves.easeInOut,
    this.showIndicators = true,
    this.allowManualSwipe = true,
    this.onPageChanged,
    this.height,
    this.controller,
  }) : super(key: key);

  @override
  State<CarouselWidget> createState() => _CarouselWidgetState();
}

class _CarouselWidgetState extends State<CarouselWidget>
    with TickerProviderStateMixin {
  late PageController _pageController;
  late List<Widget> _widgets;
  int _currentIndex = 0;
  Timer? _autoPlayTimer;
  bool _isAnimating = false;

  @override
  void initState() {
    super.initState();
    _widgets = List.from(widget.initialWidgets);
    _pageController = PageController(initialPage: 0);
    widget.controller?._attach(this);
    _startAutoPlay();
  }

  @override
  void dispose() {
    widget.controller?._detach();
    _stopAutoPlay();
    _pageController.dispose();
    super.dispose();
  }

  /// Start auto-play timer if auto-play is enabled
  void _startAutoPlay() {
    if (widget.autoPlayDuration != null && _widgets.isNotEmpty) {
      _autoPlayTimer = Timer.periodic(widget.autoPlayDuration!, (timer) {
        if (!_isAnimating && mounted) {
          playNext();
        }
      });
    }
  }

  /// Stop auto-play timer
  void _stopAutoPlay() {
    _autoPlayTimer?.cancel();
    _autoPlayTimer = null;
  }

  /// Restart auto-play timer
  void _restartAutoPlay() {
    _stopAutoPlay();
    _startAutoPlay();
  }

  /// Set the carousel array with a new list of widgets
  ///
  /// Preserve current index when possible to avoid jumping back to the main screen
  /// during runtime updates. If previous index is out of range, clamp to last.
  void setCarouselArray(List<Widget> widgets) {
    final int prevIndex = _currentIndex;

    setState(() {
      _widgets = List.from(widgets);
      if (_widgets.isEmpty) {
        _currentIndex = 0;
      } else {
        _currentIndex = prevIndex.clamp(0, _widgets.length - 1);
      }
    });

    if (_widgets.isNotEmpty && _pageController.hasClients) {
      // Jump to the preserved index without animation to avoid interrupting media playback
      debugPrint(
          'CarouselWidget: jumping to page $_currentIndex without animation');
      _pageController.jumpToPage(_currentIndex);
    }

    _restartAutoPlay();

    if (widget.onPageChanged != null) {
      widget.onPageChanged!(_widgets.isEmpty ? -1 : _currentIndex);
    }
  }

  /// Clear all widgets from the carousel
  void clearCarouselArray() {
    setState(() {
      _widgets.clear();
      _currentIndex = 0;
    });

    _stopAutoPlay();

    if (widget.onPageChanged != null) {
      widget.onPageChanged!(-1);
    }
  }

  /// Delete a widget at the specified index
  void delete(int index) {
    if (index < 0 || index >= _widgets.length) {
      // debugPrint('CarouselWidget: Invalid index $index for deletion');
      return;
    }

    setState(() {
      _widgets.removeAt(index);

      // Adjust current index if necessary
      if (_currentIndex >= _widgets.length && _widgets.isNotEmpty) {
        _currentIndex = _widgets.length - 1;
      } else if (_widgets.isEmpty) {
        _currentIndex = 0;
      }
    });

    // Navigate to adjusted index if widgets still exist and controller is attached
    if (_widgets.isNotEmpty && _pageController.hasClients) {
      _pageController.animateToPage(
        _currentIndex,
        duration: widget.animationDuration,
        curve: widget.animationCurve,
      );
      _restartAutoPlay();
    } else {
      _stopAutoPlay();
    }

    if (widget.onPageChanged != null) {
      widget.onPageChanged!(_widgets.isEmpty ? -1 : _currentIndex);
    }
  }

  /// Add a widget to the end of the carousel
  void push(Widget newWidget) {
    setState(() {
      _widgets.add(newWidget);
    });

    // If this is the first widget, navigate to it (only if controller is attached)
    if (_widgets.length == 1 && _pageController.hasClients) {
      _currentIndex = 0;
      _pageController.animateToPage(
        0,
        duration: widget.animationDuration,
        curve: widget.animationCurve,
      );
      _restartAutoPlay();

      if (widget.onPageChanged != null) {
        widget.onPageChanged!(0);
      }
    } else if (_widgets.length == 1) {
      // If controller not attached yet, just update state
      _currentIndex = 0;
      _restartAutoPlay();

      if (widget.onPageChanged != null) {
        widget.onPageChanged!(0);
      }
    }
  }

  /// Play the next widget (loops to first if at end)
  void playNext() {
    if (_widgets.isEmpty || _isAnimating || !_pageController.hasClients) return;

    _isAnimating = true;
    int nextIndex = (_currentIndex + 1) % _widgets.length;

    _pageController
        .animateToPage(
      nextIndex,
      duration: widget.animationDuration,
      curve: widget.animationCurve,
    )
        .then((_) {
      if (mounted) {
        setState(() {
          _currentIndex = nextIndex;
          _isAnimating = false;
        });

        if (widget.onPageChanged != null) {
          widget.onPageChanged!(_currentIndex);
        }
      }
    }).catchError((error) {
      // Handle animation errors gracefully
      if (mounted) {
        setState(() {
          _isAnimating = false;
        });
      }
      // debugPrint('CarouselWidget: Animation error - $error');
    });
  }

  /// Play the previous widget (loops to last if at beginning)
  void playPrev() {
    if (_widgets.isEmpty || _isAnimating || !_pageController.hasClients) return;

    _isAnimating = true;
    int prevIndex = (_currentIndex - 1 + _widgets.length) % _widgets.length;

    _pageController
        .animateToPage(
      prevIndex,
      duration: widget.animationDuration,
      curve: widget.animationCurve,
    )
        .then((_) {
      if (mounted) {
        setState(() {
          _currentIndex = prevIndex;
          _isAnimating = false;
        });

        if (widget.onPageChanged != null) {
          widget.onPageChanged!(_currentIndex);
        }
      }
    }).catchError((error) {
      // Handle animation errors gracefully
      if (mounted) {
        setState(() {
          _isAnimating = false;
        });
      }
      // debugPrint('CarouselWidget: Animation error - $error');
    });
  }

  /// Jump to a specific index without animation
  void jumpToIndex(int index) {
    if (index < 0 || index >= _widgets.length || !_pageController.hasClients)
      return;

    setState(() {
      _currentIndex = index;
    });

    _pageController.jumpToPage(index);
    _restartAutoPlay();

    if (widget.onPageChanged != null) {
      widget.onPageChanged!(_currentIndex);
    }
  }

  /// Get current index
  int get currentIndex => _currentIndex;

  /// Get total count of widgets
  int get widgetCount => _widgets.length;

  /// Get current widget
  Widget? get currentWidget =>
      _widgets.isEmpty ? null : _widgets[_currentIndex];

  /// Pause all video content in the carousel
  void pauseAllMedia() {
    // 发送通知给所有子组件暂停媒体播放
    if (context.mounted) {
      // 使用通知机制通知所有子组件
      MediaPauseNotification().dispatch(context);
      // debugPrint('CarouselWidget: Sent media pause notification');
    }
  }

  /// Resume all video content in the carousel
  void resumeAllMedia() {
    // 发送通知给所有子组件恢复媒体播放
    if (context.mounted) {
      // 使用通知机制通知所有子组件
      MediaResumeNotification().dispatch(context);
      // debugPrint('CarouselWidget: Sent media resume notification');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_widgets.isEmpty) {
      return Container(
        width: double.infinity,
        height: widget.height,
        child: const Center(
          child: Text(
            'No content available',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      height: widget.height,
      child: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              physics: widget.allowManualSwipe
                  ? const PageScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });

                if (widget.onPageChanged != null) {
                  widget.onPageChanged!(index);
                }

                _restartAutoPlay();
              },
              itemCount: _widgets.length,
              itemBuilder: (context, index) {
                return _widgets[index];
              },
            ),
          ),
          if (widget.showIndicators && _widgets.length > 1)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_widgets.length, (index) {
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3.0),
                    width: 8.0,
                    height: 8.0,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _currentIndex == index
                          ? Theme.of(context).primaryColor
                          : Colors.grey.withOpacity(0.4),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}
