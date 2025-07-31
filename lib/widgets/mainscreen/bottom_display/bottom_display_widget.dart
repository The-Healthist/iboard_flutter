import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:iboard_app/providers/bottom_weather_qrcode_carousel_provider.dart';
import 'package:iboard_app/widgets/mainscreen/bottom_display/weather_widget.dart';
import 'package:iboard_app/widgets/mainscreen/bottom_display/qrcode_widget.dart';
import 'package:logger/logger.dart';

class BottomDisplayWidget extends StatefulWidget {
  const BottomDisplayWidget({Key? key}) : super(key: key);

  @override
  _BottomDisplayWidgetState createState() => _BottomDisplayWidgetState();
}

class _BottomDisplayWidgetState extends State<BottomDisplayWidget> {
  final Logger _logger = Logger();

  @override
  void initState() {
    super.initState();
    _logger.i('🌤️ BottomDisplayWidget初始化');
  }

  ///1，构建底部显示组件 - 使用固定高度确保统一显示
  @override
  Widget build(BuildContext context) {
    return Consumer<BottomWeatherQrcodeCarouselProvider>(
      builder: (context, bottomProvider, child) {
        // 获取屏幕尺寸，计算固定高度
        final screenSize = MediaQuery.of(context).size;
        final fixedHeight = screenSize.height * (4 / 24); // 根据布局比例 4/24 计算固定高度

        return Container(
          padding: const EdgeInsets.fromLTRB(8.0, 0, 8.0, 6.0),
          height: fixedHeight, // 使用计算出的固定高度
          child: Row(
            children: [
              // 左侧部分：当前天气显示区域 - 固定显示天气组件的左侧部分
              Expanded(
                flex: 2,
                child: WeatherWidget(
                    showOnlyLeft: true, containerHeight: fixedHeight),
              ),
              // 右侧部分：轮播区域 - 天气预报/二维码轮播
              Expanded(
                flex: 6,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 500),
                  transitionBuilder:
                      (Widget child, Animation<double> animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: child,
                    );
                  },
                  child: bottomProvider.showWeather
                      ? Container(
                          key: const ValueKey('weather_forecast'),
                          child: _WeatherForecastOnlyWidget(
                              containerHeight: fixedHeight),
                        )
                      : Container(
                          key: const ValueKey('qrcode'),
                          child: QrcodeWidget(containerHeight: fixedHeight),
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

///2，只显示天气预报的组件
class _WeatherForecastOnlyWidget extends StatelessWidget {
  final double containerHeight;

  const _WeatherForecastOnlyWidget({
    Key? key,
    required this.containerHeight,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return WeatherWidget(showOnlyRight: true, containerHeight: containerHeight);
  }
}
