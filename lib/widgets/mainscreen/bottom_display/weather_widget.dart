import 'dart:async'; // Added for Timer

import 'package:flutter/material.dart';
import 'package:iboard_app/http/weather.dart';
import 'package:iboard_app/models/weather_forecast_model.dart';
import 'package:iboard_app/models/current_weather_model.dart'; // Added
import 'package:iboard_app/models/weather_warning_model.dart'; // 恢复天气警告模型导入
import 'package:iboard_app/providers/app_data_provider.dart'; // 添加AppDataProvider导入
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart'; // Added import
import 'package:logger/logger.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart'; // 添加Provider导入

class WeatherWidget extends StatefulWidget {
  const WeatherWidget({Key? key}) : super(key: key);

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
      _updateLocationFromProvider(); // 获取location
      _fetchWeatherData(); // 初始获取天气数据
      // _startTimeUpdateTimer(); // Start timer for updating time - 注释掉时间更新器
      _startWeatherUpdateTimer(); // 启动天气数据定时更新器（每2小时）
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

  ///2, 获取天气数据
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

  ///4, 启动天气数据定时更新器（每2小时）
  void _startWeatherUpdateTimer() {
    // 立即执行一次更新
    _logger.i('启动天气数据定时更新器，间隔：2小时');

    // 每2小时更新一次天气数据 - 可以改为较短时间进行测试
    // 测试时可以使用: const Duration(minutes: 5)
    // 生产环境使用: const Duration(hours: 2)
    _weatherUpdateTimer = Timer.periodic(const Duration(hours: 2), (timer) {
      if (mounted) {
        _logger.i('定时更新天气数据...');
        _updateLocationFromProvider(); // 同时更新location
        _fetchWeatherData(); // 更新天气数据
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
    // 定义温度位置数据变量，用于存储匹配的温度信息
    CurrentTemperatureDataModel? tempLocationData;
    // 检查当前天气数据中是否包含温度信息
    if (currentWeatherData.temperature?.data != null) {
      try {
        // 尝试根据当前设置的位置查找对应的温度数据
        tempLocationData = currentWeatherData.temperature!.data
            .firstWhere((t) => t.place == _currentWeatherLocation);
        _logger.i(
            '找到匹配位置的温度数据: $_currentWeatherLocation, ${tempLocationData.value}°C');
      } catch (e) {
        // 如果找不到匹配的位置，尝试查找"香港天文台"作为备选
        try {
          tempLocationData = currentWeatherData.temperature!.data
              .firstWhere((t) => t.place == '香港天文台');
          _logger.w(
              '未找到位置 $_currentWeatherLocation 的温度数据，使用香港天文台数据: ${tempLocationData.value}°C');
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
    return Container(
      margin: const EdgeInsets.only(right: 8.0), // 右外边距8像素，与预报区域分隔
      padding: const EdgeInsets.only(
          left: 8.0, right: 8.0, bottom: 8.0), // 移除顶部内边距，让日期文本贴顶显示
      // 容器装饰样式
      decoration: BoxDecoration(
          color: Colors.lightBlue[50], // 浅蓝色背景
          borderRadius: BorderRadius.circular(10.0), // 圆角10像素
          border: Border.all(
              color: Colors.lightBlue.shade200, width: 1)), // 浅蓝色边框，宽度1像素
      // 使用Column垂直布局排列天气信息，充满整个容器高度
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center, // 水平居中对齐
        children: [
          // 日期和星期显示 - 贴顶显示，无顶部间隙
          Padding(
            padding: const EdgeInsets.only(
                left: 4.0,
                top: 2.0,
                bottom: 4.0), // 保持左边距4像素对齐，最小顶部边距2像素，下边距4像素
            child: Text(
              '$formattedDate ($formattedWeekday)', // 显示"日期 (星期)"格式
              style: TextStyle(
                  fontSize: 10, // 字体大小10像素（精简以节省空间）
                  color: Colors.blueGrey[600]), // 蓝灰色文字
              textAlign: TextAlign.left, // 文本左对齐，与右侧预报标题一致
            ),
          ),
          // 使用Expanded填充剩余空间，让其他元素均匀分布
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly, // 垂直空间均匀分布
              crossAxisAlignment: CrossAxisAlignment.center, // 水平居中对齐
              children: [
                // 天气警告区域 - 移到日期和地点之间
                FutureBuilder<WeatherWarningModel?>(
                  future: _weatherWarningFuture, // 异步获取天气警告数据
                  builder: (context, warningSnapshot) {
                    // 检查是否有警告数据且警告列表不为空
                    if (warningSnapshot.hasData &&
                        warningSnapshot.data != null &&
                        warningSnapshot.data!.warnings.isNotEmpty) {
                      // 获取活跃的警告描述
                      final warnings =
                          warningSnapshot.data!.getActiveWarningDescriptions();
                      final warningText =
                          warnings.isNotEmpty ? warnings.first : '';
                      // 显示警告文本
                      return Text(
                        warningText, // 显示警告内容
                        style: TextStyle(
                            fontSize: 16, // 增大字号从11到14像素，突出警告显示
                            fontWeight: FontWeight.bold, // 粗体字
                            color: const Color.fromARGB(
                                255, 8, 12, 133)), // 改为红色警告文字，更加醒目
                        textAlign: TextAlign.center, // 文本居中对齐
                        maxLines: 1, // 只显示1行，增加间距
                        overflow: TextOverflow.ellipsis, // 超出部分显示省略号
                      );
                    }
                    return const SizedBox.shrink(); // 没有警告时不占用空间
                  },
                ),
                // 地点名称显示
                Text(
                  tempLocationData != null
                      ? '${tempLocationData.place}'
                      : '即時天氣', // 显示温度数据的地点或默认"即时天气"
                  style: TextStyle(
                      fontSize: 16, // 字体大小14像素
                      fontWeight: FontWeight.bold, // 粗体字
                      color: Colors.blueGrey[800]), // 更深的蓝灰色文字
                  textAlign: TextAlign.center, // 文本居中对齐
                ),
                // 天气图标显示 - 仅在有图标数据时显示
                if (currentIcon != null)
                  CachedNetworkImage(
                    imageUrl: _getWeatherIconUrl(currentIcon), // 获取天气图标的URL
                    width: 50, // 图标宽度50像素（增大以突出显示）
                    height: 50, // 图标高度50像素（增大以突出显示）
                    // 图标加载中的占位符
                    placeholder: (context, url) => const SizedBox(
                        width: 50, // 占位符宽度50像素
                        height: 50, // 占位符高度50像素
                        child: CircularProgressIndicator(
                            strokeWidth: 2.0)), // 显示加载圆圈
                    // 图标加载失败时的错误占位符
                    errorWidget: (context, url, error) => const Icon(
                        Icons.cloud_off,
                        size: 50), // 显示云朵关闭图标，大小50像素
                  ),
                // 无图标且无温度数据时的占位空间
                if (currentIcon == null && tempLocationData == null)
                  const SizedBox(height: 50), // 占位高度50像素，保持布局一致性
                // 温度显示
                Text(
                  tempLocationData != null
                      ? '${tempLocationData.value}°${tempLocationData.unit}' // 显示实际温度值和单位
                      : '--°C', // 无数据时显示默认占位符
                  style: TextStyle(
                      fontSize: 16, // 字体大小16像素
                      fontWeight: FontWeight.bold, // 粗体字
                      color: Colors.blue[800]), // 深蓝色文字，突出温度显示
                )
              ],
            ),
          ),
        ], // Column的children结束
      ), // Column结束
    ); // Container结束
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

  @override
  Widget build(BuildContext context) {
    // 主容器 - 整个天气组件的最外层容器
    return Container(
      // 设置内边距：左8，上8，右8，下6像素
      padding: const EdgeInsets.fromLTRB(8.0, 0, 8.0, 6.0), // 减少底部内边距以节省空间
      height: 145, // 固定高度145像素，防止布局溢出
      // 使用Row布局 - 水平排列当前天气和预报天气两个部分
      child: Row(
        children: [
          // 左侧部分：当前天气显示区域 - 使用Expanded使其与右侧预报区域高度一致
          Expanded(
            flex: 3, // 左侧占用2份空间（约40%宽度）
            child: FutureBuilder<CurrentWeatherDataModel?>(
              future: _currentWeatherDataFuture, // 异步获取当前天气数据的Future
              builder: (context, snapshot) {
                // 数据加载中状态 - 显示加载指示器
                if (snapshot.connectionState == ConnectionState.waiting &&
                    _forecastDataFuture != null) {
                  return Container(
                    margin:
                        const EdgeInsets.only(right: 8.0), // 右外边距8像素，与预报区域分隔
                    decoration: BoxDecoration(
                        color: Colors.lightBlue[50], // 浅蓝色背景
                        borderRadius: BorderRadius.circular(10.0), // 圆角10像素
                        border: Border.all(
                            color: Colors.lightBlue.shade200,
                            width: 1)), // 浅蓝色边框，宽度1像素
                    child: const Center(
                        child: CircularProgressIndicator(
                      strokeWidth: 2.0, // 加载圆圈的线条粗细
                    )),
                  );
                }

                // 数据获取失败或无数据状态 - 显示错误占位界面
                if (snapshot.hasError ||
                    !snapshot.hasData ||
                    snapshot.data == null) {
                  // 记录调试日志，降低级别避免正常网络问题时的错误显示
                  _logger.d('Current weather data unavailable',
                      error: snapshot.error);
                  // 错误状态的占位容器 - 充满整个Expanded高度
                  return Container(
                    margin:
                        const EdgeInsets.only(right: 8.0), // 右外边距8像素，与预报区域分隔
                    padding: const EdgeInsets.only(
                        left: 8.0,
                        right: 8.0,
                        bottom: 8.0), // 移除顶部内边距，让日期文本贴顶显示
                    decoration: BoxDecoration(
                        color: Colors.lightBlue[50], // 浅蓝色背景
                        borderRadius: BorderRadius.circular(10.0), // 圆角10像素
                        border: Border.all(
                            color: Colors.lightBlue.shade200,
                            width: 1)), // 浅蓝色边框，宽度1像素
                    // 使用Column垂直布局排列错误状态的各个元素，充满整个容器高度
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center, // 水平居中对齐
                      children: [
                        // 日期显示文本 - 与右侧预报标题对齐
                        Padding(
                          padding: const EdgeInsets.only(
                              left: 4.0,
                              top: 0,
                              bottom: 4.0), // 左边距4像素，上边距2像素，下边距4像素，与右侧对齐
                          child: Text(
                            DateFormat('yyyy-MM-dd (EEEE)', 'zh_HK')
                                .format(_currentTime), // 格式化显示当前日期和星期
                            style: TextStyle(
                                fontSize: 10, // 字体大小10像素（精简以节省空间）
                                color: Colors.blueGrey[600]), // 蓝灰色文字
                            textAlign: TextAlign.left, // 文本左对齐，与右侧预报标题一致
                          ),
                        ),
                        // 使用Expanded填充剩余空间
                        Expanded(
                          child: Column(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceEvenly, // 垂直空间均匀分布
                            crossAxisAlignment:
                                CrossAxisAlignment.center, // 水平居中对齐
                            children: [
                              // 天气警告区域 - 在错误状态下也显示警告信息
                              FutureBuilder<WeatherWarningModel?>(
                                future: _weatherWarningFuture, // 异步获取天气警告数据
                                builder: (context, warningSnapshot) {
                                  // 检查是否有警告数据且警告列表不为空
                                  if (warningSnapshot.hasData &&
                                      warningSnapshot.data != null &&
                                      warningSnapshot
                                          .data!.warnings.isNotEmpty) {
                                    // 获取活跃的警告描述
                                    final warnings = warningSnapshot.data!
                                        .getActiveWarningDescriptions();
                                    final warningText = warnings.isNotEmpty
                                        ? warnings.first
                                        : '';
                                    // 显示警告文本
                                    return Text(
                                      warningText, // 显示警告内容
                                      style: TextStyle(
                                          fontSize: 11, // 字体大小11像素
                                          fontWeight: FontWeight.bold, // 粗体字
                                          color: Colors.red[600]), // 红色警告文字
                                      textAlign: TextAlign.center, // 文本居中对齐
                                      maxLines: 1, // 只显示1行
                                      overflow:
                                          TextOverflow.ellipsis, // 超出部分显示省略号
                                    );
                                  }
                                  return const SizedBox.shrink(); // 没有警告时不占用空间
                                },
                              ),
                              // 错误状态提示文本
                              Text(
                                '天氣資料獲取中', // 显示"正在获取天气数据"的提示
                                style: TextStyle(
                                    fontSize: 12, // 字体大小12像素
                                    fontWeight: FontWeight.bold, // 粗体字
                                    color: Colors.blueGrey[800]), // 更深的蓝灰色文字
                                textAlign: TextAlign.center, // 文本居中对齐
                              ),
                              // 错误状态图标
                              const Icon(Icons.cloud_off,
                                  size: 50,
                                  color: Colors.grey), // 云朵关闭图标，大小50像素，灰色
                              // 默认温度显示
                              Text(
                                '--°C', // 显示默认温度占位符
                                style: TextStyle(
                                    fontSize: 16, // 字体大小16像素
                                    fontWeight: FontWeight.bold, // 粗体字
                                    color: Colors.blue[800]), // 深蓝色文字
                              ),
                              // 刷新按钮
                              IconButton(
                                icon: const Icon(Icons.refresh,
                                    size: 12), // 刷新图标，大小12像素
                                onPressed: _fetchWeatherData, // 点击时执行获取天气数据的函数
                                tooltip: '重試', // 鼠标悬停时显示的提示文字
                                splashRadius: 10, // 点击水波效果的半径10像素
                                padding: EdgeInsets.zero, // 移除按钮内边距
                                constraints: const BoxConstraints(
                                    minWidth: 22,
                                    minHeight: 22), // 限制按钮最小尺寸22x22像素
                              )
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }
                // 数据获取成功时，调用构建当前天气显示区域的函数
                return _buildCurrentWeatherSection(snapshot.data!);
              }, // FutureBuilder的builder结束
            ), // FutureBuilder结束
          ), // Expanded结束
          // 右侧部分：天气预报区域 - 使用Expanded占满Row的剩余空间
          Expanded(
            flex: 7, // 右侧占用3份空间（约60%宽度）
            child: FutureBuilder<WeatherData?>(
              future: _forecastDataFuture, // 异步获取天气预报数据的Future
              builder: (context, snapshot) {
                // 数据加载中状态 - 显示加载指示器
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator()); // 居中显示加载圆圈
                }
                // 数据获取失败或无数据状态 - 显示错误占位界面
                if (snapshot.hasError ||
                    !snapshot.hasData ||
                    snapshot.data == null) {
                  // 记录调试日志，降低级别避免正常网络问题时的错误显示
                  _logger.d('Forecast weather data unavailable',
                      error: snapshot.error);
                  // 预报区域的错误状态容器
                  return Container(
                    margin: const EdgeInsets.all(4.0), // 外边距4像素
                    // 容器装饰 - 设置背景色、圆角、边框
                    decoration: BoxDecoration(
                      color: Colors.grey[100], // 浅灰色背景
                      borderRadius: BorderRadius.circular(8.0), // 圆角8像素
                      border: Border.all(
                          color: Colors.grey.shade300, width: 1), // 灰色边框，宽度1像素
                    ),
                    // 使用Column垂直布局排列错误状态的各个元素
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center, // 垂直居中对齐
                      children: [
                        // 错误状态图标
                        const Icon(Icons.cloud_off,
                            size: 40, color: Colors.grey), // 云朵关闭图标，大小40像素，灰色
                        const SizedBox(height: 8), // 垂直间距8像素
                        // 错误提示文本
                        const Text('天氣預報暫時無法取得', // 显示"天气预报暂时无法获取"
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey)), // 字体12像素，灰色
                        const SizedBox(height: 8), // 垂直间距8像素
                        // 重试按钮
                        ElevatedButton.icon(
                          onPressed: _fetchWeatherData, // 点击时执行获取天气数据的函数
                          icon: const Icon(Icons.refresh,
                              size: 16), // 刷新图标，大小16像素
                          label: const Text('重試',
                              style:
                                  TextStyle(fontSize: 12)), // 按钮文字"重试"，字体12像素
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 4), // 按钮内边距：水平16像素，垂直4像素
                            minimumSize: const Size(0, 32), // 按钮最小尺寸：高度32像素
                          ),
                        )
                      ],
                    ),
                  );
                }
                // 数据获取成功时，调用构建天气预报显示区域的函数
                return _buildForecastSection(snapshot.data!);
              },
            ),
          ),
        ], // Row的children结束
      ), // Row结束
    ); // Container结束
  } // build方法结束
}
