import 'dart:async';
import 'package:flutter/material.dart';
import 'package:iboard_app/providers/app_data_provider.dart';
import 'package:iboard_app/widgets/weather_icon_widget.dart';
import 'package:iboard_app/providers/weather_provider.dart';
import 'package:iboard_app/models/weather_warning_model.dart';
import 'package:iboard_app/models/current_weather_model.dart';
import 'package:iboard_app/utils/weather_icon_util.dart';
import 'package:iboard_app/utils/weather_warning_mapping.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logger/logger.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

class WeatherWidget extends StatefulWidget {
  final bool showOnlyLeft;
  final bool showOnlyRight;
  final double? containerHeight;

  const WeatherWidget({
    super.key,
    this.showOnlyLeft = false,
    this.showOnlyRight = false,
    this.containerHeight,
  });

  @override
  WeatherWidgetState createState() => WeatherWidgetState();
}

class WeatherWidgetState extends State<WeatherWidget> {
  final Logger _logger = Logger();
  String _currentWeatherLocation = '香港天文台';
  Timer? _timeUpdateTimer;
  DateTime _currentTime = DateTime.now();

  // 日志缓存，避免重复日志输出
  String? _lastLoggedLocation;
  DateTime? _lastLogTime;

  @override
  void initState() {
    super.initState();
    _currentTime = DateTime.now();
    _startTimeUpdateTimer();

    initializeDateFormatting('zh_HK', null).then((_) {
      _updateLocationFromProvider();
      _initializeWeatherData();
    });
  }

  @override
  void dispose() {
    _timeUpdateTimer?.cancel();
    _timeUpdateTimer = null;
    super.dispose();
  }

  ///1，启动时间更新定时器 - 每分鈡同步一次系统时间
  void _startTimeUpdateTimer() {
    setState(() {
      _currentTime = DateTime.now();
    });

    final now = DateTime.now();
    final nextMinute =
        DateTime(now.year, now.month, now.day, now.hour, now.minute + 1);
    final delayToNextMinute = nextMinute.difference(now);

    Timer(delayToNextMinute, () {
      if (mounted) {
        setState(() {
          _currentTime = DateTime.now();
        });

        _timeUpdateTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
          if (mounted) {
            setState(() {
              _currentTime = DateTime.now();
            });
          } else {
            timer.cancel();
          }
        });
      }
    });
  }

  ///2，初始化天气数据
  void _initializeWeatherData() {
    final weatherProvider =
        Provider.of<WeatherProvider>(context, listen: false);

    if (!weatherProvider.hasCurrentData) {
      weatherProvider.fetchCurrentWeather();
    }

    if (!weatherProvider.hasForecastData) {
      weatherProvider.fetchWeatherForecast();
    }

    if (!weatherProvider.hasWarningData) {
      weatherProvider.fetchWeatherWarnings();
    }

    if (!weatherProvider.hasCurrentData &&
        !weatherProvider.hasForecastData &&
        !weatherProvider.hasWarningData) {
      weatherProvider.fetchAllWeatherData();
    }
  }

  ///3，从AppDataProvider获取location信息
  void _updateLocationFromProvider() {
    try {
      final appDataProvider =
          Provider.of<AppDataProvider>(context, listen: false);
      if (appDataProvider.buildingInfo?.location != null) {
        final newLocation = appDataProvider.buildingInfo!.location;
        if (newLocation != _currentWeatherLocation) {
          setState(() {
            _currentWeatherLocation = newLocation;
          });

          final weatherProvider =
              Provider.of<WeatherProvider>(context, listen: false);
          if (!weatherProvider.hasCurrentData) {
            weatherProvider.fetchCurrentWeather();
          }
        }
      } else {
        _logger.w('Provider中没有位置信息，使用默认位置: $_currentWeatherLocation');
      }
    } catch (e) {
      _logger.e('获取位置信息失败，使用默认位置', error: e);
    }
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

  ///7，构建天气警告组件
  Widget _buildWeatherWarningWidget(WeatherWarningModel? warningData) {
    List<Widget> warningWidgets = [];

    // 添加實際的天氣警告數據
    if (warningData != null && warningData.warnings.isNotEmpty) {
      final warnings = warningData.warnings;
      final warningEntries = warnings.entries.toList();

      warningWidgets.addAll(warningEntries.map((entry) {
        return _buildWarningRow(entry.key, entry.value);
      }).toList());
    }

    // 8, 固定添加測試用的新界北部水浸特別報告警告信號 (已註釋)
    // final testWarningInfo1 = WeatherWarningInfo(
    //   name: "新界北部水浸特別報告",
    //   code: "WFNTSA",
    //   actionCode: "ISSUE",
    //   type: "", // 根據實際需要設置
    //   issueTime: "2020-09-24T11:40:00+08:00",
    //   updateTime: "2020-09-24T11:40:00+08:00",
    // );

    // warningWidgets.add(_buildWarningRow("WFNTSA", testWarningInfo1));

    // 9, 固定添加測試用的熱帶氣旋警告信號
    // 10, 固定添加測試用的黃色暴雨警告信號 (已註釋)
    // final testWarningInfo3 = WeatherWarningInfo(
    //   name: "暴雨警告信號",
    //   code: "WRAINA",
    //   actionCode: "ISSUE",
    //   type: "黃色",
    //   issueTime: "2020-09-24T09:30:00+08:00",
    //   updateTime: "2020-09-24T09:30:00+08:00",
    // );

    // warningWidgets.add(_buildWarningRow("WRAIN", testWarningInfo3));

    // 如果沒有任何警告（包括測試警告），返回空組件
    if (warningWidgets.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: warningWidgets,
    );
  }

  ///8，构建單个警告行
  Widget _buildWarningRow(String warningKey, WeatherWarningInfo warningInfo) {
    // 🔧 使用新的映射系统获取警告描述和图标
    final warningDescription = WeatherWarningMapping.getWarningDescription(
        warningKey, warningInfo.code, warningInfo.type);
    final iconPath =
        WeatherIconUtil.getWeatherWarningIconPathByCode(warningInfo.code);
    const double fontSize = 15.0;
    const double iconSize = 45.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Image.asset(
            iconPath,
            width: iconSize,
            height: iconSize,
            errorBuilder: (context, error, stackTrace) {
              return const Icon(
                Icons.warning,
                size: iconSize,
                color: Colors.orange,
              );
            },
          ),
          const SizedBox(width: iconSize * 0.25),
          Flexible(
            child: Text(
              warningDescription,
              style: const TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                color: Color.fromARGB(255, 8, 12, 133),
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.visible,
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }

  ///9，构建当前天气卡片第一頁
  Widget _buildCurrentWeatherPage1(CurrentWeatherDataModel currentWeatherData) {
    CurrentTemperatureDataModel? tempLocationData;

    if (currentWeatherData.temperature?.data != null) {
      try {
        tempLocationData = currentWeatherData.temperature!.data
            .firstWhere((t) => t.place == _currentWeatherLocation);
      } catch (e) {
        final now = DateTime.now();
        final shouldLog = _lastLoggedLocation != _currentWeatherLocation ||
            _lastLogTime == null ||
            now.difference(_lastLogTime!).inMinutes > 5;

        if (shouldLog) {
          _logger.w('❌ 未找到位置 $_currentWeatherLocation 的匹配数据，尝试香港天文台作为备选');
          _lastLoggedLocation = _currentWeatherLocation;
          _lastLogTime = now;
        }

        try {
          tempLocationData = currentWeatherData.temperature!.data
              .firstWhere((t) => t.place == '香港天文台');
          if (shouldLog) {
            _logger.w('🔄 使用香港天文台数据: ${tempLocationData.value}°C');
          }
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
      decoration: BoxDecoration(
        color: Colors.lightBlue[50],
        borderRadius: BorderRadius.circular(10.0),
        border: Border.all(color: Colors.lightBlue.shade200, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    DateFormat('HH:mm').format(_currentTime),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey[800],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Consumer<AppDataProvider>(
                    builder: (context, appDataProvider, child) {
                      final buildingName = appDataProvider.buildingInfo?.name;
                      if (buildingName != null && buildingName.isNotEmpty) {
                        return Column(
                          children: [
                            Text(
                              buildingName,
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueGrey[800]),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                          ],
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                  Text(
                    _currentWeatherLocation != '香港天文台'
                        ? _currentWeatherLocation
                        : (tempLocationData != null
                            ? tempLocationData.place
                            : '即時天氣'),
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueGrey[800]),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  if (currentIcon != null)
                    WeatherIconWidget(
                      iconCode: currentIcon,
                      width: 45,
                      height: 45,
                    ),
                  if (currentIcon == null && tempLocationData == null)
                    const SizedBox(height: 45),
                  const SizedBox(height: 6),
                  Text(
                    tempLocationData != null
                        ? '${tempLocationData.value}°${tempLocationData.unit}'
                        : '--°C',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[800]),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  ///10，构建当前天气卡片第二頁
  Widget _buildCurrentWeatherPage2(CurrentWeatherDataModel currentWeatherData) {
    CurrentTemperatureDataModel? tempLocationData;

    if (currentWeatherData.temperature?.data != null) {
      try {
        tempLocationData = currentWeatherData.temperature!.data
            .firstWhere((t) => t.place == _currentWeatherLocation);
      } catch (e) {
        try {
          tempLocationData = currentWeatherData.temperature!.data
              .firstWhere((t) => t.place == '香港天文台');
        } catch (e2) {
          if (currentWeatherData.temperature!.data.isNotEmpty) {
            tempLocationData = currentWeatherData.temperature!.data.first;
          }
        }
      }
    }

    final formattedDate = DateFormat('yyyy-MM-dd').format(_currentTime);
    final formattedWeekday = DateFormat('EEEE', 'zh_HK').format(_currentTime);

    return Container(
      margin: const EdgeInsets.only(right: 8.0),
      decoration: BoxDecoration(
        color: Colors.lightBlue[50],
        borderRadius: BorderRadius.circular(10.0),
        border: Border.all(color: Colors.lightBlue.shade200, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 天气警告区域
                  Consumer<WeatherProvider>(
                    builder: (context, weatherProvider, child) {
                      final warningData = weatherProvider.weatherWarningData;
                      if (warningData != null &&
                          warningData.warnings.isNotEmpty) {
                        return Column(
                          children: [
                            _buildWeatherWarningWidget(warningData),
                          ],
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                  const SizedBox(height: 8),
                  // 温度信息
                  if (tempLocationData != null) ...[
                    Text(
                      ' ${tempLocationData.value}°${tempLocationData.unit}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[800],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  ///11，构建当前天气部分（支持自动轮播）
  Widget _buildCurrentWeatherSection(WeatherProvider weatherProvider) {
    if (weatherProvider.isLoadingCurrent) {
      return const Center(child: CircularProgressIndicator());
    }

    if (weatherProvider.currentError != null ||
        !weatherProvider.hasCurrentData) {
      final hasError = weatherProvider.currentError != null;
      final errorText = hasError
          ? weatherProvider.currentError!.contains('解析错误')
              ? '天氣數據格式錯誤'
              : '當前天氣暫時無法取得'
          : '當前天氣暫時無法取得';

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
            Text(
              DateFormat('HH:mm').format(_currentTime),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey[800],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Icon(
                hasError && weatherProvider.currentError!.contains('解析错误')
                    ? Icons.error_outline
                    : Icons.cloud_off,
                size: 40,
                color:
                    hasError && weatherProvider.currentError!.contains('解析错误')
                        ? Colors.orange
                        : Colors.grey),
            const SizedBox(height: 8),
            Text(errorText,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            if (hasError && weatherProvider.currentError!.contains('解析错误')) ...[
              const SizedBox(height: 4),
              const Text('請檢查網絡連接或稍後重試',
                  style: TextStyle(fontSize: 10, color: Colors.grey)),
            ],
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () {
                _updateLocationFromProvider();
                weatherProvider.fetchCurrentWeather();
              },
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

    // 检查是否有天气警告信息
    final hasWarnings = weatherProvider.weatherWarningData != null &&
        weatherProvider.weatherWarningData!.warnings.isNotEmpty;

    // 如果没有天气警告信息，只显示第一頁
    if (!hasWarnings) {
      return _buildCurrentWeatherPage1(weatherProvider.currentWeatherData!);
    }

    // 根据Provider的状态自动切换頁面（只有在有天气警告时才轮播）
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
      child: weatherProvider.showCurrentWeatherPage1
          ? _buildCurrentWeatherPage1(weatherProvider.currentWeatherData!)
          : _buildCurrentWeatherPage2(weatherProvider.currentWeatherData!),
    );
  }

  ///12，构建天气预报部分
  Widget _buildForecastSection(WeatherProvider weatherProvider) {
    if (weatherProvider.isLoadingForecast) {
      return const Center(child: CircularProgressIndicator());
    }

    if (weatherProvider.forecastError != null ||
        !weatherProvider.hasForecastData) {
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
              onPressed: () => weatherProvider.fetchWeatherForecast(),
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

    final forecastData = weatherProvider.weatherForecastData!;
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

  @override
  Widget build(BuildContext context) {
    return Consumer<WeatherProvider>(
      builder: (context, weatherProvider, child) {
        final double containerHeight = widget.containerHeight ?? 145;

        // 如果只显示左侧部分
        if (widget.showOnlyLeft) {
          return Container(
            padding: const EdgeInsets.fromLTRB(8.0, 0, 8.0, 6.0),
            height: containerHeight,
            child: _buildCurrentWeatherSection(weatherProvider),
          );
        }

        // 如果只显示右侧部分
        if (widget.showOnlyRight) {
          return Container(
            padding: const EdgeInsets.fromLTRB(8.0, 0, 8.0, 6.0),
            height: containerHeight,
            child: _buildForecastSection(weatherProvider),
          );
        }

        // 默认显示完整的天气组件
        return Container(
          padding: const EdgeInsets.fromLTRB(8.0, 0, 8.0, 6.0),
          height: containerHeight,
          child: Row(
            children: [
              // 左侧部分：当前天气显示区域
              Expanded(
                flex: 2,
                child: _buildCurrentWeatherSection(weatherProvider),
              ),
              // 右侧部分：天气预报区域
              Expanded(
                flex: 6,
                child: _buildForecastSection(weatherProvider),
              ),
            ],
          ),
        );
      },
    );
  }
}
