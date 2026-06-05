import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:iboard_app/utils/weather_icon_util.dart';
import 'package:logger/logger.dart';

/// 智能天气图标组件 - 优先使用本地资源，网络资源作为fallback
class WeatherIconWidget extends StatefulWidget {
  final int iconCode;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;

  const WeatherIconWidget({
    super.key,
    required this.iconCode,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.placeholder,
    this.errorWidget,
  });

  @override
  WeatherIconWidgetState createState() => WeatherIconWidgetState();
}

class WeatherIconWidgetState extends State<WeatherIconWidget> {
  final Logger _logger = Logger();
  bool _useLocalIcon = true;
  late Future<bool> _localIconAvailable;

  @override
  void initState() {
    super.initState();
    _localIconAvailable = WeatherIconUtil.isLocalIconAvailable(widget.iconCode);
  }

  ///1，构建默认占位符
  Widget _buildDefaultPlaceholder() {
    return widget.placeholder ??
        SizedBox(
          width: widget.width ?? 50,
          height: widget.height ?? 50,
          child: const CircularProgressIndicator(strokeWidth: 2.0),
        );
  }

  ///2，构建默认错误组件
  Widget _buildDefaultErrorWidget() {
    return widget.errorWidget ??
        Icon(
          Icons.cloud_off,
          size: (widget.width ?? 50).clamp(24.0, 60.0),
          color: Colors.grey,
        );
  }

  ///3，构建本地图标
  Widget _buildLocalIcon() {
    final localPath = WeatherIconUtil.getWeatherIconPath(widget.iconCode);

    return Image.asset(
      localPath,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      errorBuilder: (context, error, stackTrace) {
        // _logger.w(' 本地天气图标加载失败，切换到网络图标: pic${widget.iconCode}.png');
        // 本地图标加载失败，切换到网络图标
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _useLocalIcon = false;
            });
          }
        });
        return _buildDefaultErrorWidget();
      },
    );
  }

  ///4，构建网络图标
  Widget _buildNetworkIcon() {
    final networkUrl = WeatherIconUtil.getWeatherIconUrl(widget.iconCode);

    return CachedNetworkImage(
      imageUrl: networkUrl,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      placeholder: (context, url) => _buildDefaultPlaceholder(),
      errorWidget: (context, url, error) {
        _logger.e(' 网络天气图标加载失败: pic${widget.iconCode}.png', error: error);
        return _buildDefaultErrorWidget();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _localIconAvailable,
      builder: (context, snapshot) {
        // 正在检查本地图标可用性
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildDefaultPlaceholder();
        }

        // 检查完成，根据结果决定使用本地还是网络图标
        final hasLocalIcon = snapshot.data ?? false;

        if (hasLocalIcon && _useLocalIcon) {
          // _logger.d(' 使用本地天气图标: pic${widget.iconCode}.png');
          return _buildLocalIcon();
        } else {
          // _logger.d(' 使用网络天气图标: pic${widget.iconCode}.png');
          return _buildNetworkIcon();
        }
      },
    );
  }
}

/// 天气警告图标组件
class WeatherWarningIconWidget extends StatelessWidget {
  final String warningType;
  final double? width;
  final double? height;
  final BoxFit fit;

  const WeatherWarningIconWidget({
    super.key,
    required this.warningType,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    final iconPath = WeatherIconUtil.getWeatherWarningIconPath(warningType);

    return Image.asset(
      iconPath,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (context, error, stackTrace) => Icon(
        Icons.warning,
        size: (width ?? 30).clamp(16.0, 40.0),
        color: Colors.orange,
      ),
    );
  }
}

/// 台风警告图标组件
class TyphoonWarningIconWidget extends StatelessWidget {
  final String warningCode;
  final double? width;
  final double? height;
  final BoxFit fit;

  const TyphoonWarningIconWidget({
    super.key,
    required this.warningCode,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    final iconPath = WeatherIconUtil.getTyphoonWarningIconPath(warningCode);

    return Image.asset(
      iconPath,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (context, error, stackTrace) => Icon(
        Icons.cyclone,
        size: (width ?? 30).clamp(16.0, 40.0),
        color: Colors.red,
      ),
    );
  }
}
