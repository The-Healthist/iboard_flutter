import 'dart:async';
import 'package:flutter/material.dart';
import 'package:iboard_app/http/weather.dart';
import 'package:iboard_app/models/weather_forecast_model.dart';
import 'package:iboard_app/models/current_weather_model.dart';
import 'package:iboard_app/models/weather_warning_model.dart';
import 'package:iboard_app/providers/app_data_provider.dart';
import 'package:iboard_app/widgets/weather_icon_widget.dart';
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
  final WeatherService _weatherService = WeatherService();
  Future<WeatherData?>? _forecastDataFuture;
  Future<CurrentWeatherDataModel?>? _currentWeatherDataFuture;
  Future<WeatherWarningModel?>? _weatherWarningFuture;
  final Logger _logger = Logger();
  String _currentWeatherLocation = '香港天文台';
  Timer? _timeUpdateTimer;
  Timer? _weatherUpdateTimer;
  DateTime _currentTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _currentTime = DateTime.now();
    _logger.i(
        'WeatherComponentsWidget初始化时间: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(_currentTime)}');

    initializeDateFormatting('zh_HK', null).then((_) {
      _updateLocationFromProvider();
      _fetchWeatherData();
      _startWeatherUpdateTimer();
    });
  }

  @override
  void dispose() {
    _timeUpdateTimer?.cancel();
    _weatherUpdateTimer?.cancel();
    super.dispose();
  }

  ///1，获取天气数据
  void _fetchWeatherData() {
    _updateLocationFromProvider();

    setState(() {
      _forecastDataFuture = _weatherService.fetchWeatherData();
      _currentWeatherDataFuture = _weatherService.fetchCurrentWeatherData();
      _weatherWarningFuture = _weatherService.fetchWeatherWarnings();
    });
    _logger.i('开始获取天气数据，当前位置: $_currentWeatherLocation');
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

  ///3，启动天气数据定时更新器（每2小时）
  void _startWeatherUpdateTimer() {
    _logger.i('启动天气数据定时更新器，间隔：2小时');
    _weatherUpdateTimer = Timer.periodic(const Duration(hours: 2), (timer) {
      if (mounted) {
        _logger.i('定时更新天气数据...');
        _updateLocationFromProvider();
        _fetchWeatherData();
      } else {
        timer.cancel();
      }
    });
  }

  String _getWeatherIconUrl(int iconCode) {
    return 'https://www.hko.gov.hk/images/HKOWxIconOutline/pic$iconCode.png';
  }

  String _formatDate(String yyyyMMdd) {
    try {
      final date = DateTime.parse(yyyyMMdd);
      return DateFormat('MM/dd').format(date);
    } catch (e) {
      _logger.e('Error formatting date: $yyyyMMdd', error: e);
      return yyyyMMdd;
    }
  }

  // 构建当前天气显示区域的函数
  Widget _buildCurrentWeatherSection(
      CurrentWeatherDataModel currentWeatherData) {
    CurrentTemperatureDataModel? tempLocationData;
    if (currentWeatherData.temperature?.data != null) {
      try {
        tempLocationData = currentWeatherData.temperature!.data
            .firstWhere((t) => t.place == _currentWeatherLocation);
        _logger.i(
            '找到匹配位置的温度数据: $_currentWeatherLocation, ${tempLocationData.value}°C');
      } catch (e) {
        try {
          tempLocationData = currentWeatherData.temperature!.data
              .firstWhere((t) => t.place == '香港天文台');
          _logger.w(
              '未找到位置 $_currentWeatherLocation 的温度数据，使用香港天文台数据: ${tempLocationData.value}°C');
        } catch (e2) {
          if (currentWeatherData.temperature!.data.isNotEmpty) {
            tempLocationData = currentWeatherData.temperature!.data.first;
            _logger.w(
                '未找到香港天文台数据，使用第一个可用数据: ${tempLocationData.place}, ${tempLocationData.value}°C');
          }
        }
      }
    }

    int? currentIcon = currentWeatherData.icon?.isNotEmpty == true
        ? currentWeatherData.icon!.first
        : null;

    final formattedDate = DateFormat('yyyy-MM-dd').format(_currentTime);
    final formattedWeekday = DateFormat('EEEE', 'zh_HK').format(_currentTime);

    return Container(
      margin: const EdgeInsets.only(right: 8.0),
      padding: const EdgeInsets.only(left: 8.0, right: 8.0, bottom: 8.0),
      decoration: BoxDecoration(
          color: Colors.lightBlue[50],
          borderRadius: BorderRadius.circular(10.0),
          border: Border.all(color: Colors.lightBlue.shade200, width: 1)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4.0, top: 2.0, bottom: 4.0),
            child: Text(
              '$formattedDate ($formattedWeekday)',
              style: TextStyle(fontSize: 10, color: Colors.blueGrey[600]),
              textAlign: TextAlign.left,
            ),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                FutureBuilder<WeatherWarningModel?>(
                  future: _weatherWarningFuture,
                  builder: (context, warningSnapshot) {
                    if (warningSnapshot.hasData &&
                        warningSnapshot.data != null &&
                        warningSnapshot.data!.warnings.isNotEmpty) {
                      final warnings =
                          warningSnapshot.data!.getActiveWarningDescriptions();
                      final warningText =
                          warnings.isNotEmpty ? warnings.first : '';
                      return Text(
                        warningText,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: const Color.fromARGB(255, 8, 12, 133)),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
                Text(
                  tempLocationData != null
                      ? '${tempLocationData.place}'
                      : '即時天氣',
                  style: TextStyle(
                      fontSize: 16,
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
                if (currentIcon == null && tempLocationData == null)
                  const SizedBox(height: 50),
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
          ),
        ],
      ),
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
                            '${forecast.forecastMintemp.value}°${forecast.forecastMintemp.unit} - ${forecast.forecastMaxtemp.value}°${forecast.forecastMaxtemp.unit}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12),
                            textAlign: TextAlign.center,
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

  // 构建左侧当前天气部分
  Widget buildCurrentWeatherPart() {
    return FutureBuilder<CurrentWeatherDataModel?>(
      future: _currentWeatherDataFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            _forecastDataFuture != null) {
          return Container(
            margin: const EdgeInsets.only(right: 8.0),
            decoration: BoxDecoration(
                color: Colors.lightBlue[50],
                borderRadius: BorderRadius.circular(10.0),
                border: Border.all(color: Colors.lightBlue.shade200, width: 1)),
            child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2.0)),
          );
        }

        if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
          _logger.d('Current weather data unavailable', error: snapshot.error);
          return Container(
            margin: const EdgeInsets.only(right: 8.0),
            padding: const EdgeInsets.only(left: 8.0, right: 8.0, bottom: 8.0),
            decoration: BoxDecoration(
                color: Colors.lightBlue[50],
                borderRadius: BorderRadius.circular(10.0),
                border: Border.all(color: Colors.lightBlue.shade200, width: 1)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.only(left: 4.0, top: 0, bottom: 4.0),
                  child: Text(
                    DateFormat('yyyy-MM-dd (EEEE)', 'zh_HK')
                        .format(_currentTime),
                    style: TextStyle(fontSize: 10, color: Colors.blueGrey[600]),
                    textAlign: TextAlign.left,
                  ),
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      FutureBuilder<WeatherWarningModel?>(
                        future: _weatherWarningFuture,
                        builder: (context, warningSnapshot) {
                          if (warningSnapshot.hasData &&
                              warningSnapshot.data != null &&
                              warningSnapshot.data!.warnings.isNotEmpty) {
                            final warnings = warningSnapshot.data!
                                .getActiveWarningDescriptions();
                            final warningText =
                                warnings.isNotEmpty ? warnings.first : '';
                            return Text(
                              warningText,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red[600]),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                      Text(
                        '天氣資料獲取中',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.blueGrey[800]),
                        textAlign: TextAlign.center,
                      ),
                      const Icon(Icons.cloud_off, size: 50, color: Colors.grey),
                      Text(
                        '--°C',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[800]),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 12),
                        onPressed: _fetchWeatherData,
                        tooltip: '重試',
                        splashRadius: 10,
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 22, minHeight: 22),
                      )
                    ],
                  ),
                ),
              ],
            ),
          );
        }
        return _buildCurrentWeatherSection(snapshot.data!);
      },
    );
  }

  // 构建右侧天气预报部分
  Widget buildForecastPart() {
    return FutureBuilder<WeatherData?>(
      future: _forecastDataFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
          _logger.d('Forecast weather data unavailable', error: snapshot.error);
          return Container(
            margin: const EdgeInsets.all(4.0),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8.0),
              border: Border.all(color: Colors.grey.shade300, width: 1),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cloud_off, size: 40, color: Colors.grey),
                const SizedBox(height: 8),
                const Text('天氣預報暫時無法取得',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _fetchWeatherData,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('重試', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    minimumSize: const Size(0, 32),
                  ),
                )
              ],
            ),
          );
        }
        return _buildForecastSection(snapshot.data!);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(); // 这个widget主要提供方法，不需要实际渲染
  }
}
