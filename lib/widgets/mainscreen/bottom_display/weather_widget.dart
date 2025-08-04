import 'dart:async'; // Added for Timer

import 'package:flutter/material.dart';
import 'package:iboard_app/http/weather.dart';
import 'package:iboard_app/models/weather_forecast_model.dart';
import 'package:iboard_app/models/current_weather_model.dart'; // Added
import 'package:iboard_app/models/weather_warning_model.dart'; // 恢复天气警告模型导入
import 'package:iboard_app/providers/app_data_provider.dart'; // 添加AppDataProvider导入
import 'package:iboard_app/widgets/weather_icon_widget.dart';
import 'package:iboard_app/widgets/debug_weather_data_widget.dart'; // 添加天气数据调试组件导入
import 'package:iboard_app/widgets/mainscreen/bottom_display/weather_warning_widget.dart'; // 添加天气警告组件导入
import 'package:iboard_app/providers/weather_provider.dart'; // 添加天气provider导入
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart'; // Added import
import 'package:logger/logger.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart'; // 添加Provider导入

class WeatherWidget extends StatefulWidget {
  final bool showOnlyLeft;
  final bool showOnlyRight;
  final double? containerHeight; // 可选的容器高度参数

  const WeatherWidget({
    Key? key,
    this.showOnlyLeft = false,
    this.showOnlyRight = false,
    this.containerHeight,
  }) : super(key: key);

  @override
  _WeatherWidgetState createState() => _WeatherWidgetState();
}

class _WeatherWidgetState extends State<WeatherWidget> {
  final WeatherService _weatherService = WeatherService();
  Future<WeatherData?>? _forecastDataFuture;
  Future<CurrentWeatherDataModel?>? _currentWeatherDataFuture; // Added
  Future<WeatherWarningModel?>? _weatherWarningFuture; // 恢复天气警告Future
  final Logger _logger = Logger();
  String _currentWeatherLocation = '香港天文台'; // 动态获取的location，默认为香港天文台
  Timer? _timeUpdateTimer; // Added timer for updating time
  Timer? _weatherUpdateTimer; // 添加天气数据定时更新器
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
      _logger.i('🚀 WeatherWidget初始化开始');
      _updateLocationFromProvider(); // 获取location
      _initializeWeatherData(); // 初始化天气数据
      _startWeatherUpdateTimer(); // 启动天气数据定时更新器（每2小时）
      _logger.i('📍 初始化完成，当前位置: $_currentWeatherLocation');
    });
  }

  @override
  void dispose() {
    _timeUpdateTimer?.cancel(); // Cancel timer
    _weatherUpdateTimer?.cancel(); // 取消天气更新定时器
    super.dispose();
  }

  ///1, 开始时间更新定时器 - 注释掉整个时间更新功能
  /*
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
  */

  ///2, 初始化天气数据
  void _initializeWeatherData() {
    // 使用WeatherProvider获取天气数据
    final weatherProvider =
        Provider.of<WeatherProvider>(context, listen: false);

    _logger.i(
        '🌤️ 初始化天气数据 - CurrentData: ${weatherProvider.hasCurrentData}, ForecastData: ${weatherProvider.hasForecastData}');

    // 总是尝试获取最新数据，特别是当前天气数据
    if (!weatherProvider.hasCurrentData) {
      _logger.i('📡 WeatherProvider中没有当前天气数据，强制获取');
      weatherProvider.fetchCurrentWeather();
    }

    if (!weatherProvider.hasForecastData) {
      _logger.i('📡 WeatherProvider中没有预报数据，强制获取');
      weatherProvider.fetchWeatherForecast();
    }

    if (!weatherProvider.hasWarningData) {
      _logger.i('📡 WeatherProvider中没有警告数据，强制获取');
      weatherProvider.fetchWeatherWarnings();
    }

    // 如果没有任何数据，获取全部
    if (!weatherProvider.hasCurrentData &&
        !weatherProvider.hasForecastData &&
        !weatherProvider.hasWarningData) {
      _logger.i('📡 WeatherProvider中没有任何缓存数据，获取全部天气数据');
      weatherProvider.fetchAllWeatherData();
    }
  }

  ///3, 获取天气数据（保留原有方法用于兼容）
  void _fetchWeatherData() {
    // 每次获取天气数据时也更新location
    _updateLocationFromProvider();

    setState(() {
      _forecastDataFuture = _weatherService.fetchWeatherData();
      _currentWeatherDataFuture =
          _weatherService.fetchCurrentWeatherData(); // Added
      _weatherWarningFuture =
          _weatherService.fetchWeatherWarnings(); // 恢复天气警告获取
    });
    _logger.i('开始获取天气数据，当前位置: $_currentWeatherLocation');
  }

  ///3, 从AppDataProvider获取location信息
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
          _logger.i('🔄 从Provider更新位置信息: $_currentWeatherLocation');

          // 位置更新后重新获取天气数据（如果需要的话）
          final weatherProvider =
              Provider.of<WeatherProvider>(context, listen: false);
          if (!weatherProvider.hasCurrentData) {
            _logger.i('📡 位置更新后触发天气数据重新获取');
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

  ///4, 启动天气数据定时更新器（每2小时）
  void _startWeatherUpdateTimer() {
    // 立即执行一次更新
    _logger.i('启动天气数据定时更新器，间隔：2小时');

    // 使用WeatherProvider的定时更新功能
    final weatherProvider =
        Provider.of<WeatherProvider>(context, listen: false);
    weatherProvider.startPeriodicUpdate(interval: const Duration(hours: 2));

    // 保留原有的定时器用于更新location
    _weatherUpdateTimer = Timer.periodic(const Duration(hours: 2), (timer) {
      if (mounted) {
        _logger.i('定时更新location信息...');
        _updateLocationFromProvider(); // 更新location
      } else {
        timer.cancel();
      }
    });
  }

  /*
  void _testWeatherService() async {
    _logger.i('开始测试天气服务连接...');
    try {
      final testData = await _weatherService.fetchWeatherData();
      if (testData != null) {
        _logger.i('天气服务连接测试成功');
      } else {
        _logger.w('天气服务返回空数据');
      }
    } catch (e, stackTrace) {
      _logger.e('天气服务连接测试失败', error: e, stackTrace: stackTrace);
    }
  }
  */

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
  // 参数：当前天气数据模型
  Widget _buildCurrentWeatherSection(
      CurrentWeatherDataModel currentWeatherData) {
    _logger.d('🌡️ 开始构建当前天气区域，当前位置设置: $_currentWeatherLocation');

    // 定义温度位置数据变量，用于存储匹配的温度信息
    CurrentTemperatureDataModel? tempLocationData;
    // 检查当前天气数据中是否包含温度信息
    if (currentWeatherData.temperature?.data != null) {
      try {
        // 尝试根据当前设置的位置查找对应的温度数据
        tempLocationData = currentWeatherData.temperature!.data
            .firstWhere((t) => t.place == _currentWeatherLocation);
        _logger.i(
            '✅ 找到匹配位置的温度数据: $_currentWeatherLocation, ${tempLocationData.value}°C');

        // 输出可用地区列表以便调试
        final availablePlaces =
            currentWeatherData.temperature!.data.map((t) => t.place).join(', ');
        _logger.d('可用天气地区: $availablePlaces');
        _logger.d('当前查找的位置: $_currentWeatherLocation');
        _logger.i(
            '天气卡片将显示的地区名称: ${_currentWeatherLocation != '香港天文台' ? _currentWeatherLocation : tempLocationData.place}');
      } catch (e) {
        // 如果找不到匹配的位置，尝试查找"香港天文台"作为备选
        _logger.w('❌ 未找到位置 $_currentWeatherLocation 的匹配数据，尝试香港天文台作为备选');
        try {
          tempLocationData = currentWeatherData.temperature!.data
              .firstWhere((t) => t.place == '香港天文台');
          _logger.w('🔄 使用香港天文台数据: ${tempLocationData.value}°C');
        } catch (e2) {
          // 如果连"香港天文台"都找不到，使用第一个可用数据作为最后备选
          if (currentWeatherData.temperature!.data.isNotEmpty) {
            tempLocationData = currentWeatherData.temperature!.data.first;
            _logger.w(
                '未找到香港天文台数据，使用第一个可用数据: ${tempLocationData.place}, ${tempLocationData.value}°C');
          }
        }
      }
    }

    // 获取当前天气图标代码（如果存在的话）
    int? currentIcon = currentWeatherData.icon?.isNotEmpty == true
        ? currentWeatherData.icon!.first // 取第一个图标代码
        : null; // 如果没有图标数据则为null

    // 格式化时间显示 - 使用追踪的当前时间而不是DateTime.now()
    final formattedDate =
        DateFormat('yyyy-MM-dd').format(_currentTime); // 格式化日期：年-月-日
    // final formattedTime = DateFormat('HH:mm').format(_currentTime); // 格式化时间：时:分 - 注释掉时间格式化
    final formattedWeekday =
        DateFormat('EEEE', 'zh_HK').format(_currentTime); // 格式化星期：使用香港中文本地化

    // 返回当前天气显示容器 - 使用全高度布局适配Expanded容器
    // 外部Container仅负责浅蓝色卡片背景和外边距
    return Container(
      margin: const EdgeInsets.only(right: 8.0),
      decoration: BoxDecoration(
        color: Colors.lightBlue[50],
        borderRadius: BorderRadius.circular(10.0),
        border: Border.all(color: Colors.lightBlue.shade200, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, // 顶部日期左对齐
        children: [
          // 顶部日期永远顶格
          Padding(
            padding: const EdgeInsets.only(left: 4.0, top: 2.0, bottom: 4.0),
            child: Text(
              '$formattedDate ($formattedWeekday)',
              style: TextStyle(fontSize: 10, color: Colors.blueGrey[600]),
              textAlign: TextAlign.left,
            ),
          ),
          // 卡片内容区域居中显示（地区、警告、天气icon、温度）
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 天气警告区域
                  FutureBuilder<WeatherWarningModel?>(
                    future: _weatherWarningFuture,
                    builder: (context, warningSnapshot) {
                      // 判断警告条数，动态调整字号和图标
                      final warningCount =
                          warningSnapshot.data?.warnings.length ?? 0;
                      final double fontSize = warningCount > 1 ? 14.0 : 12.0;
                      final double iconSize = warningCount > 1 ? 16.0 : 12.0;
                      return WeatherWarningWidget(
                        warningData: warningSnapshot.data,
                        fontSize: fontSize, // 多行时增大字号
                        textColor: const Color.fromARGB(255, 8, 12, 133),
                        iconSize: iconSize, // 多行时增大图标
                        verticalSpacing: 1.0,
                        useSimulatedData: false,
                      );
                    },
                  ),
                  const SizedBox(height: 6),
                  // 大厦名称 - 显示building name
                  Consumer<AppDataProvider>(
                    builder: (context, appDataProvider, child) {
                      final buildingName = appDataProvider.buildingInfo?.name;
                      if (buildingName != null && buildingName.isNotEmpty) {
                        return Column(
                          children: [
                            Text(
                              buildingName,
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueGrey[800]),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                          ],
                        );
                      }
                      return const SizedBox.shrink(); // 如果没有大厦名称则不显示
                    },
                  ),
                  // 地区名称 - 显示building location，如果没有则显示API返回的place
                  Text(
                    _currentWeatherLocation != '香港天文台'
                        ? _currentWeatherLocation // 显示building location
                        : (tempLocationData != null
                            ? tempLocationData.place
                            : '即時天氣'),
                    style: TextStyle(
                        fontSize: 16,
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
  } // _buildCurrentWeatherSection函数结束

  // 构建天气预报显示区域的函数 - 适配已在Expanded容器中的布局
  // 参数：天气预报数据模型
  Widget _buildForecastSection(WeatherData forecastData) {
    // 获取要显示的预报数据，限制为前6天
    final forecastsToShow =
        forecastData.weatherForecast.take(6).toList(); // 取前6天的预报数据
    // 检查是否有预报数据可显示
    if (forecastsToShow.isEmpty) {
      return const Center(child: Text('沒有可用的天氣預報')); // 无数据时显示提示
    }
    // 返回预报区域容器 - 不再使用Expanded，因为父容器已经是Expanded
    return Column(
      // 使用Column垂直布局排列预报标题和内容
      crossAxisAlignment: CrossAxisAlignment.start, // 左对齐
      children: [
        // 预报标题区域
        Padding(
          padding: const EdgeInsets.only(
              left: 4.0, bottom: 0.0, top: 2.0), // 左边距4像素，上边距2像素
          child: Text(
            '未來六天 (更新於: ${DateFormat('HH:mm').format(DateTime.parse(forecastData.updateTime))})', // 显示标题和更新时间
            style: TextStyle(fontSize: 10, color: Colors.grey[700]), // 小字体灰色显示
          ),
        ),
        // 预报卡片滚动区域
        Expanded(
          // 使用Expanded占满Column的剩余垂直空间
          child: LayoutBuilder(
            // 使用LayoutBuilder获取可用空间尺寸
            builder: (context, constraints) {
              final double availableWidth = constraints.maxWidth; // 获取可用宽度
              final int numberOfCards = forecastsToShow.length; // 预报卡片数量

              // 安全检查，虽然前面已经检查过，但确保不会出现0张卡片的情况
              if (numberOfCards == 0) {
                return const SizedBox.shrink(); // 返回空组件，不占用空间
              }

              // 计算每张卡片的宽度 = 总宽度 / 卡片数量
              final double itemWidth = availableWidth / numberOfCards;

              // 水平滚动的预报卡片列表
              return ListView.builder(
                scrollDirection: Axis.horizontal, // 设置为水平滚动
                itemCount: numberOfCards, // 卡片总数
                itemExtent: itemWidth, // 设置每个卡片的固定宽度，确保等宽分布
                itemBuilder: (context, index) {
                  // 构建每张预报卡片
                  final forecast = forecastsToShow[index]; // 获取当前索引的预报数据
                  // 返回单张预报卡片
                  return Card(
                    elevation: 1.5, // 卡片阴影高度1.5像素
                    margin: const EdgeInsets.symmetric(
                        horizontal: 3.0, vertical: 3.0), // 卡片外边距：水平3像素，垂直3像素
                    child: Padding(
                      padding: const EdgeInsets.all(8.0), // 卡片内边距8像素
                      child: Column(
                        // 使用Column垂直布局排列卡片内容
                        mainAxisAlignment: MainAxisAlignment.center, // 垂直居中对齐
                        children: [
                          // 预报日期显示
                          Text(
                            _formatDate(
                                forecast.forecastDate), // 格式化并显示预报日期（MM/dd格式）
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14), // 粗体，字体14像素
                            textAlign: TextAlign.center, // 文本居中对齐
                          ),
                          // 预报星期显示
                          Text(
                            '星期${forecast.week.substring(2)}', // 显示星期（去掉前缀"星期"）
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14), // 粗体，字体14像素
                            textAlign: TextAlign.center, // 文本居中对齐
                          ),
                          const SizedBox(height: 3), // 垂直间距3像素
                          // 预报天气图标
                          CachedNetworkImage(
                            imageUrl: _getWeatherIconUrl(
                                forecast.forecastIcon), // 获取预报天气图标URL
                            width: 38, // 图标宽度38像素
                            height: 38, // 图标高度38像素
                            // 图标加载中的占位符
                            placeholder: (context, url) => const SizedBox(
                                width: 18, // 占位符宽度18像素
                                height: 18, // 占位符高度18像素
                                child: CircularProgressIndicator(
                                    strokeWidth: 1.5)), // 显示加载圆圈，线条粗细1.5像素
                            // 图标加载失败时的错误占位符
                            errorWidget: (context, url, error) => const Icon(
                                Icons.cloud_off,
                                size: 35), // 显示云朵关闭图标，大小35像素
                          ),
                          const SizedBox(height: 3), // 垂直间距3像素
                          // 预报温度范围显示
                          Text(
                            '${forecast.forecastMintemp.value}°${forecast.forecastMintemp.unit} - ${forecast.forecastMaxtemp.value}°${forecast.forecastMaxtemp.unit}', // 显示最低温度到最高温度的范围
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12), // 粗体，字体12像素
                            textAlign: TextAlign.center, // 文本居中对齐
                          ),
                        ], // Column的children结束
                      ), // Padding结束
                    ), // Card的child结束
                  ); // Card结束
                }, // itemBuilder结束
              ); // ListView.builder结束
            }, // LayoutBuilder的builder结束
          ), // LayoutBuilder结束
        ), // Expanded结束
      ], // Column的children结束
    ); // Column结束 - _buildForecastSection函数的返回值
  } // _buildForecastSection函数结束

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
                        _currentWeatherLocation != '香港天文台'
                            ? _currentWeatherLocation // 显示building location
                            : '天氣資料獲取中',
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

  // 使用WeatherProvider构建当前天气部分
  Widget _buildCurrentWeatherPartWithProvider(WeatherProvider weatherProvider) {
    _logger.d(
        'WeatherProvider状态 - Loading: ${weatherProvider.isLoadingCurrent}, HasData: ${weatherProvider.hasCurrentData}, Error: ${weatherProvider.currentError}');

    if (weatherProvider.isLoadingCurrent) {
      return const Center(child: CircularProgressIndicator());
    }

    if (weatherProvider.currentError != null ||
        !weatherProvider.hasCurrentData) {
      _logger.w(
          '天气数据不可用 - Error: ${weatherProvider.currentError}, HasData: ${weatherProvider.hasCurrentData}');
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
            const Text('當前天氣暫時無法取得',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () {
                _logger.i('🔄 手动重试获取天气数据，当前位置: $_currentWeatherLocation');
                // 先更新位置，再获取数据
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

    return _buildCurrentWeatherSection(weatherProvider.currentWeatherData!);
  }

  // 使用WeatherProvider构建天气预报部分
  Widget _buildForecastPartWithProvider(WeatherProvider weatherProvider) {
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

    return _buildForecastSection(weatherProvider.weatherForecastData!);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<WeatherProvider>(
      builder: (context, weatherProvider, child) {
        // 计算容器高度 - 优先使用传入的高度，否则使用默认高度
        final double containerHeight = widget.containerHeight ?? 145;

        // 如果只显示左侧部分
        if (widget.showOnlyLeft) {
          return Container(
            padding: const EdgeInsets.fromLTRB(8.0, 0, 8.0, 6.0),
            height: containerHeight,
            child: _buildCurrentWeatherPartWithProvider(weatherProvider),
          );
        }

        // 如果只显示右侧部分
        if (widget.showOnlyRight) {
          return Container(
            padding: const EdgeInsets.fromLTRB(8.0, 0, 8.0, 6.0),
            height: containerHeight,
            child: _buildForecastPartWithProvider(weatherProvider),
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
                child: _buildCurrentWeatherPartWithProvider(weatherProvider),
              ),
              // 右侧部分：天气预报区域
              Expanded(
                flex: 6,
                child: _buildForecastPartWithProvider(weatherProvider),
              ),
            ],
          ),
        );
      },
    );
  }
}
