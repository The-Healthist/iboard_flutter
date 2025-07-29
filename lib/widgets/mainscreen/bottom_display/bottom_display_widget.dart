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

  @override
  Widget build(BuildContext context) {
    return Consumer<BottomWeatherQrcodeCarouselProvider>(
      builder: (context, bottomProvider, child) {
        return Container(
          padding: const EdgeInsets.fromLTRB(8.0, 0, 8.0, 6.0),
          height: 160, // 增加高度以匹配QrcodeWidget
          child: Row(
            children: [
              // 左侧部分：当前天气显示区域 - 固定显示天气组件的左侧部分
              const Expanded(
                flex: 2,
                child: WeatherWidget(showOnlyLeft: true),
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
                          child: const _WeatherForecastOnlyWidget(),
                        )
                      : Container(
                          key: const ValueKey('qrcode'),
                          child: const QrcodeWidget(),
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

// 只显示天气预报的组件
class _WeatherForecastOnlyWidget extends StatelessWidget {
  const _WeatherForecastOnlyWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const WeatherWidget(showOnlyRight: true);
  }
}
