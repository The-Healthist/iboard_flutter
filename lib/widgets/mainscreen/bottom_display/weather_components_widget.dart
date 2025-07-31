import 'dart:async';
import 'package:flutter/material.dart';
import 'package:iboard_app/providers/weather_provider.dart';
import 'package:iboard_app/models/weather_forecast_model.dart';
import 'package:iboard_app/models/current_weather_model.dart';
import 'package:iboard_app/models/weather_warning_model.dart';
import 'package:iboard_app/providers/app_data_provider.dart';
import 'package:iboard_app/widgets/weather_icon_widget.dart';
import 'package:iboard_app/widgets/weather_data_debug_widget.dart'; // 添加天气数据调试组件导入
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logger/logger.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

class WeatherComponentsWidget extends StatefulWidget {
  const WeatherComponentsWidget({Key? key}) : super(key: key);

  @override
  _WeatherComponentsWidgetState createState() =>
      _WeatherComponentsWidgetState();
}

class _WeatherComponentsWidgetState extends State<WeatherComponentsWidget> {
  final Logger _logger = Logger();
  String _currentWeatherLocation = '香港天文台';
  Timer? _timeUpdateTimer;
  DateTime _currentTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _currentTime = DateTime.now();
    _logger.i(
        'WeatherComponentsWidget初始化时间: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(_currentTime)}');

    initializeDateFormatting('zh_HK', null).then((_) async {
      _updateLocationFromProvider();
      _startTimeUpdateTimer();
      await _initializeWeatherData();
    });
  }

  @override
  void dispose() {
    _timeUpdateTimer?.cancel();
    super.dispose();
  }

  ///1，初始化天气数据
  Future<void> _initializeWeatherData() async {
    final weatherProvider =
        Provider.of<WeatherProvider>(context, listen: false);

    // 等待WeatherProvider完成初始化
    await weatherProvider.waitForInitialization();

    // 优先使用缓存数据，如果有缓存数据就使用，没有才获取新数据
    if (weatherProvider.hasForecastData ||
        weatherProvider.hasCurrentData ||
        weatherProvider.hasWarningData) {
      _logger.i('使用缓存的天气数据');
    } else {
      _logger.i('缓存中缺少天气数据，开始获取...');
      weatherProvider.fetchAllWeatherData();
    }
  }

  ///2，从AppDataProvider获取location信息
  void _updateLocationFromProvider() {
    try {
      final appDataProvider =
          Provider.of<AppDataProvider>(context, listen: false);
      if (appDataProvider.buildingInfo?.location != null) {
        setState(() {
          _currentWeatherLocation = appDataProvider.buildingInfo!.location;
        });
        _logger.i('从Provider更新位置信息: $_currentWeatherLocation');
      } else {
        _logger.w('Provider中没有位置信息，使用默认位置: $_currentWeatherLocation');
      }
    } catch (e) {
      _logger.e('获取位置信息失败，使用默认位置', error: e);
    }
  }

  ///3，启动时间更新定时器
  void _startTimeUpdateTimer() {
    _logger.i('启动时间更新定时器，每秒更新一次');
    _timeUpdateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _currentTime = DateTime.now();
        });
      } else {
        timer.cancel();
      }
    });
  }

  ///4，打开天气数据调试页面
  void _openWeatherDebugPage() {
    _logger.i('🐛 打开天气数据调试页面');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const WeatherDataDebugWidget(),
      ),
    );
  }

  String _getWeatherIconUrl(int iconCode) {
    return 'https://www.hko.gov.hk/images/HKOWxIconOutline/pic$iconCode.png';
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('MM/dd').format(date);
    } catch (e) {
      return dateString;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<WeatherProvider>(
      builder: (context, weatherProvider, child) {
        // 使用MediaQuery计算动态高度，与其他组件保持一致
        final screenSize = MediaQuery.of(context).size;
        final dynamicHeight =
            screenSize.height * (4 / 24) - 20; // 减去padding和margin

        return Container(
          width: double.infinity,
          height: dynamicHeight,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.3),
                spreadRadius: 1,
                blurRadius: 3,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Stack(
            children: [
              Row(
                children: [
                  // 左侧：当前天气信息
                  Expanded(
                    flex: 2,
                    child: _buildCurrentWeatherSection(weatherProvider),
                  ),
                  // 右侧：天气预报信息
                  Expanded(
                    flex: 3,
                    child: weatherProvider.hasForecastData
                        ? _buildForecastSection(
                            weatherProvider.weatherForecastData!)
                        : _buildNoDataSection('天氣預報'),
                  ),
                ],
              ),
              // 调试按钮 - 始终显示在右上角（已注释）
              // Positioned(
              //   top: 4,
              //   right: 4,
              //   child: GestureDetector(
              //     onTap: _openWeatherDebugPage,
              //     child: Container(
              //       width: 24,
              //       height: 24,
              //       decoration: BoxDecoration(
              //         color: Colors.blue.withOpacity(0.8),
              //         borderRadius: BorderRadius.circular(12),
              //       ),
              //       child: const Icon(
              //         Icons.bug_report,
              //         size: 16,
              //         color: Colors.white,
              //       ),
              //     ),
              //   ),
              // ),
            ],
          ),
        );
      },
    );
  }

  // 构建当前天气显示区域的函数
  Widget _buildCurrentWeatherSection(WeatherProvider weatherProvider) {
    final currentData = weatherProvider.currentWeatherData;

    // 检查是否有当前天气数据
    if (currentData == null) {
      return _buildNoDataSection('當前天氣');
    }

    // 尝试获取温度数据
    CurrentTemperatureDataModel? tempLocationData;
    try {
      tempLocationData = currentData.temperature?.data.firstWhere(
        (temp) => temp.place == _currentWeatherLocation,
        orElse: () =>
            currentData.temperature?.data.first ??
            CurrentTemperatureDataModel(place: '香港天文台', value: 0, unit: 'C'),
      );
    } catch (e) {
      _logger.w('获取温度数据失败: $e');
    }

    final currentIcon =
        currentData.icon?.isNotEmpty == true ? currentData.icon!.first : null;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _currentWeatherLocation,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey[800]),
              textAlign: TextAlign.center,
            ),
            if (currentIcon != null)
              CachedNetworkImage(
                imageUrl: _getWeatherIconUrl(currentIcon),
                width: 50,
                height: 50,
                placeholder: (context, url) => const SizedBox(
                    width: 50,
                    height: 50,
                    child: CircularProgressIndicator(strokeWidth: 2.0)),
                errorWidget: (context, url, error) =>
                    const Icon(Icons.cloud_off, size: 50),
              ),
            if (currentIcon == null) const SizedBox(height: 50),
            Text(
              tempLocationData != null
                  ? '${tempLocationData.value}°${tempLocationData.unit}'
                  : '--°C',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[800]),
            )
          ],
        ),
      ],
    );
  }

  // 构建天气预报显示区域的函数
  Widget _buildForecastSection(WeatherData forecastData) {
    final forecastsToShow = forecastData.weatherForecast.take(6).toList();
    if (forecastsToShow.isEmpty) {
      return const Center(child: Text('沒有可用的天氣預報'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4.0, bottom: 0.0, top: 2.0),
          child: Text(
            '未來六天 (更新於: ${DateFormat('HH:mm').format(DateTime.parse(forecastData.updateTime))})',
            style: TextStyle(fontSize: 10, color: Colors.grey[700]),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final double availableWidth = constraints.maxWidth;
              final int numberOfCards = forecastsToShow.length;

              if (numberOfCards == 0) {
                return const SizedBox.shrink();
              }

              final double itemWidth = availableWidth / numberOfCards;

              return ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: numberOfCards,
                itemExtent: itemWidth,
                itemBuilder: (context, index) {
                  final forecast = forecastsToShow[index];
                  return Card(
                    elevation: 1.5,
                    margin: const EdgeInsets.symmetric(
                        horizontal: 3.0, vertical: 3.0),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _formatDate(forecast.forecastDate),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14),
                            textAlign: TextAlign.center,
                          ),
                          Text(
                            '星期${forecast.week.substring(2)}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 3),
                          CachedNetworkImage(
                            imageUrl: _getWeatherIconUrl(forecast.forecastIcon),
                            width: 38,
                            height: 38,
                            placeholder: (context, url) => const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 1.5)),
                            errorWidget: (context, url, error) =>
                                const Icon(Icons.cloud_off, size: 35),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${forecast.forecastMintemp.value}°${forecast.forecastMintemp.unit}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.blue),
                          ),
                          Text(
                            '${forecast.forecastMaxtemp.value}°${forecast.forecastMaxtemp.unit}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.red),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // 构建无数据时的显示区域
  Widget _buildNoDataSection(String title) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.cloud_off,
            size: 40,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '暫無數據',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }
}
