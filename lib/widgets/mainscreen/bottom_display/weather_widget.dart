import 'dart:async'; // Added for Timer

import 'package:flutter/material.dart';
import 'package:iboard_app/http/weather.dart';
import 'package:iboard_app/models/weather_forecast_model.dart';
import 'package:iboard_app/models/current_weather_model.dart'; // Added
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart'; // Added import
import 'package:logger/logger.dart';
import 'package:cached_network_image/cached_network_image.dart';

class WeatherWidget extends StatefulWidget {
  const WeatherWidget({Key? key}) : super(key: key);

  @override
  _WeatherWidgetState createState() => _WeatherWidgetState();
}

class _WeatherWidgetState extends State<WeatherWidget> {
  final WeatherService _weatherService = WeatherService();
  Future<WeatherData?>? _forecastDataFuture;
  Future<CurrentWeatherDataModel?>? _currentWeatherDataFuture; // Added
  final Logger _logger = Logger();
  final String _currentWeatherLocation =
      '香港天文台'; // Default location for current temp
  Timer? _timeUpdateTimer; // Added timer for updating time
  DateTime _currentTime = DateTime.now(); // Added to track current time

  @override
  void initState() {
    super.initState();
    // Initialize current time immediately
    _currentTime = DateTime.now();
    _logger.i(
        'WeatherWidget初始化时间: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(_currentTime)}');

    initializeDateFormatting('zh_HK', null).then((_) {
      // Added initialization
      _fetchWeatherData();
      _startTimeUpdateTimer(); // Start timer for updating time
    });
  }

  @override
  void dispose() {
    _timeUpdateTimer?.cancel(); // Cancel timer
    super.dispose();
  }

  void _startTimeUpdateTimer() {
    // Update time immediately
    setState(() {
      _currentTime = DateTime.now();
    });
    _logger.i(
        '启动时间更新定时器，当前时间: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(_currentTime)}');

    // Calculate delay to next minute
    final now = DateTime.now();
    final nextMinute =
        DateTime(now.year, now.month, now.day, now.hour, now.minute + 1);
    final delayToNextMinute = nextMinute.difference(now);

    // First update at the next minute
    Timer(delayToNextMinute, () {
      if (mounted) {
        setState(() {
          _currentTime = DateTime.now();
        });
        _logger
            .i('时间更新: ${DateFormat('yyyy-MM-dd HH:mm').format(_currentTime)}');

        // Then update every minute
        _timeUpdateTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
          if (mounted) {
            setState(() {
              _currentTime = DateTime.now();
            });
            _logger.i(
                '定时时间更新: ${DateFormat('yyyy-MM-dd HH:mm').format(_currentTime)}');
          } else {
            timer.cancel();
          }
        });
      }
    });
  }

  void _fetchWeatherData() {
    setState(() {
      _forecastDataFuture = _weatherService.fetchWeatherData();
      _currentWeatherDataFuture =
          _weatherService.fetchCurrentWeatherData(); // Added
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

  Widget _buildCurrentWeatherSection(
      CurrentWeatherDataModel currentWeatherData) {
    CurrentTemperatureDataModel? tempLocationData;
    if (currentWeatherData.temperature?.data != null) {
      try {
        tempLocationData = currentWeatherData.temperature!.data
            .firstWhere((t) => t.place == _currentWeatherLocation);
      } catch (e) {
        if (currentWeatherData.temperature!.data.isNotEmpty) {
          tempLocationData = currentWeatherData.temperature!.data.first;
        }
      }
    }

    int? currentIcon = currentWeatherData.icon?.isNotEmpty == true
        ? currentWeatherData.icon!.first
        : null;

    // Use the tracked current time instead of DateTime.now()
    final formattedDate = DateFormat('yyyy-MM-dd').format(_currentTime);
    final formattedTime = DateFormat('HH:mm').format(_currentTime);
    final formattedWeekday = DateFormat('EEEE', 'zh_HK')
        .format(_currentTime); // Assuming Hong Kong locale for week day

    return Container(
      width: 220, // Adjusted width for the current weather section
      padding: const EdgeInsets.all(10.0), // Adjusted padding
      margin: const EdgeInsets.only(right: 8.0),
      decoration: BoxDecoration(
          color: Colors.lightBlue[50],
          borderRadius: BorderRadius.circular(10.0), // Adjusted radius
          border: Border.all(
              color: Colors.lightBlue.shade200, width: 1)), // Adjusted border
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '$formattedDate ($formattedWeekday)',
            style: TextStyle(
                fontSize: 12, // Date and Weekday font size
                color: Colors.blueGrey[600]),
            textAlign: TextAlign.center,
          ),
          Text(
            formattedTime,
            style: TextStyle(
                fontSize: 16, // Time font size
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey[700]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 5),
          Text(
            tempLocationData != null ? '${tempLocationData.place}' : '即時天氣',
            style: TextStyle(
                fontSize: 14, // Location/Title font size increased
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey[800]), // Darker color
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          if (currentIcon != null)
            CachedNetworkImage(
              imageUrl: _getWeatherIconUrl(currentIcon),
              width: 50, // Increased icon size
              height: 50, // Increased icon size
              placeholder: (context, url) => const SizedBox(
                  width: 30, // Adjusted placeholder size
                  height: 30, // Adjusted placeholder size
                  child: CircularProgressIndicator(strokeWidth: 2.5)),
              errorWidget: (context, url, error) =>
                  const Icon(Icons.cloud_off, size: 50), // Increased icon size
            ),
          if (currentIcon == null && tempLocationData == null)
            const SizedBox(
                height: 50), // Placeholder if no icon, increased size
          const SizedBox(height: 6),
          Text(
            tempLocationData != null
                ? '${tempLocationData.value}°${tempLocationData.unit}'
                : '--°C',
            style: TextStyle(
                fontSize: 22, // Increased temperature font size
                fontWeight: FontWeight.bold,
                color: Colors.blue[800]), // Darker color
          )
        ],
      ),
    );
  }

  Widget _buildForecastSection(WeatherData forecastData) {
    final forecastsToShow =
        forecastData.weatherForecast.take(6).toList(); // Changed to 6 days
    if (forecastsToShow.isEmpty) {
      return const Expanded(child: Center(child: Text('沒有可用的天氣預報')));
    }
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4.0, bottom: 0.0, top: 2.0),
            child: Text(
              '未來六天 (更新於: ${DateFormat('HH:mm').format(DateTime.parse(forecastData.updateTime))})', // Changed title to 6 days
              style: TextStyle(fontSize: 10, color: Colors.grey[700]),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              // Added LayoutBuilder
              builder: (context, constraints) {
                final double availableWidth = constraints.maxWidth;
                final int numberOfCards = forecastsToShow.length;

                if (numberOfCards == 0) {
                  return const SizedBox
                      .shrink(); // Should not happen due to earlier check
                }

                final double itemWidth = availableWidth / numberOfCards;

                return ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: numberOfCards,
                  itemExtent:
                      itemWidth, // Set itemExtent for equal width distribution
                  itemBuilder: (context, index) {
                    final forecast = forecastsToShow[index];
                    return Card(
                      elevation: 1.5,
                      margin: const EdgeInsets.symmetric(
                          horizontal: 3.0, vertical: 3.0),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0), // Adjusted padding
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
                              imageUrl:
                                  _getWeatherIconUrl(forecast.forecastIcon),
                              width: 35,
                              height: 35,
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
          8.0, 8.0, 8.0, 6.0), // Reduced bottom padding
      height: 145, // Adjusted height
      child: Row(
        children: [
          // Current Weather Section
          FutureBuilder<CurrentWeatherDataModel?>(
            future: _currentWeatherDataFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  _forecastDataFuture != null) {
                // Show a smaller loader if forecast is also loading or already loaded
                return const SizedBox(
                    width: 180,
                    child: Center(
                        child: CircularProgressIndicator(
                      strokeWidth: 2.0,
                    )));
              }

              if (snapshot.hasError ||
                  !snapshot.hasData ||
                  snapshot.data == null) {
                _logger.w('Current weather error or no data',
                    error: snapshot.error);
                return SizedBox(
                  width: 180,
                  child: Center(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('即時天氣無法載入',
                              style: TextStyle(
                                  fontSize: 10, color: Colors.redAccent)),
                          IconButton(
                            icon: const Icon(Icons.refresh, size: 20),
                            onPressed: _fetchWeatherData,
                            tooltip: '重試',
                            splashRadius: 18,
                          )
                        ]),
                  ),
                );
              }
              return _buildCurrentWeatherSection(snapshot.data!);
            },
          ),
          // Forecast Section
          FutureBuilder<WeatherData?>(
            future: _forecastDataFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Expanded(
                    child: Center(child: CircularProgressIndicator()));
              }
              if (snapshot.hasError ||
                  !snapshot.hasData ||
                  snapshot.data == null) {
                _logger.e('Forecast weather error or no data',
                    error: snapshot.error);
                return Expanded(
                  child: Center(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('天氣預報無法載入',
                              style: TextStyle(
                                  fontSize: 10, color: Colors.redAccent)),
                          IconButton(
                            icon: const Icon(Icons.refresh, size: 20),
                            onPressed: _fetchWeatherData,
                            tooltip: '重試',
                            splashRadius: 18,
                          )
                        ]),
                  ),
                );
              }
              return _buildForecastSection(snapshot.data!);
            },
          ),
        ],
      ),
    );
  }
}
