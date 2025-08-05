import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:iboard_app/providers/weather_provider.dart';
import 'package:iboard_app/models/weather_forecast_model.dart';
import 'package:iboard_app/models/current_weather_model.dart';
import 'package:iboard_app/models/weather_warning_model.dart';
import 'package:logger/logger.dart';
import 'package:intl/intl.dart';

/// 天气数据调试工具组件
class WeatherDataDebugWidget extends StatefulWidget {
  const WeatherDataDebugWidget({Key? key}) : super(key: key);

  @override
  _WeatherDataDebugWidgetState createState() => _WeatherDataDebugWidgetState();
}

class _WeatherDataDebugWidgetState extends State<WeatherDataDebugWidget> {
  final Logger _logger = Logger();
  Map<String, dynamic> _cacheStatus = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCacheStatus();
  }

  ///1，加载缓存状态信息
  Future<void> _loadCacheStatus() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final weatherProvider =
          Provider.of<WeatherProvider>(context, listen: false);
      final status = await weatherProvider.getCacheStatus();

      setState(() {
        _cacheStatus = status;
        _isLoading = false;
      });

      // _logger.i('天气数据缓存状态: $_cacheStatus');
    } catch (e) {
      _logger.e('获取缓存状态失败', error: e);
      setState(() {
        _isLoading = false;
      });
    }
  }

  ///2，刷新天气数据
  Future<void> _refreshWeatherData() async {
    try {
      final weatherProvider =
          Provider.of<WeatherProvider>(context, listen: false);
      await weatherProvider.fetchAllWeatherData();

      // 重新加载缓存状态
      await _loadCacheStatus();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('天气数据已刷新'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      _logger.e('刷新天气数据失败', error: e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('刷新失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  ///3，清除缓存
  Future<void> _clearCache() async {
    try {
      final weatherProvider =
          Provider.of<WeatherProvider>(context, listen: false);
      await weatherProvider.clearCache();

      // 重新加载缓存状态
      await _loadCacheStatus();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('天气数据缓存已清除'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      _logger.e('清除缓存失败', error: e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('清除失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  ///4，启动定时更新
  void _startPeriodicUpdate() {
    final weatherProvider =
        Provider.of<WeatherProvider>(context, listen: false);
    weatherProvider.startPeriodicUpdate(interval: const Duration(hours: 2));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已启动定时更新（每2小时）'),
        backgroundColor: Colors.blue,
      ),
    );

    // 重新加载状态
    _loadCacheStatus();
  }

  ///5，停止定时更新
  void _stopPeriodicUpdate() {
    final weatherProvider =
        Provider.of<WeatherProvider>(context, listen: false);
    weatherProvider.stopPeriodicUpdate();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已停止定时更新'),
        backgroundColor: Colors.orange,
      ),
    );

    // 重新加载状态
    _loadCacheStatus();
  }

  ///6，构建缓存状态卡片
  Widget _buildCacheStatusCard() {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '缓存状态',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 12),
            _buildStatusRow(
                '天气预报缓存', _cacheStatus['hasForecastCache'] ?? false),
            _buildStatusRow('当前天气缓存', _cacheStatus['hasCurrentCache'] ?? false),
            _buildStatusRow('天气警告缓存', _cacheStatus['hasWarningCache'] ?? false),
            _buildStatusRow(
                '定时更新状态', _cacheStatus['isPeriodicUpdateActive'] ?? false),
            const SizedBox(height: 8),
            if (_cacheStatus['lastUpdate'] != null)
              Text(
                '最后更新: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.parse(_cacheStatus['lastUpdate']))}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }

  ///7，构建状态行
  Widget _buildStatusRow(String label, bool status) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            status ? Icons.check_circle : Icons.cancel,
            color: status ? Colors.green : Colors.red,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 14),
          ),
          const Spacer(),
          Text(
            status ? '✅ 有数据' : '❌ 无数据',
            style: TextStyle(
              fontSize: 12,
              color: status ? Colors.green : Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  ///8，构建错误信息卡片
  Widget _buildErrorCard() {
    final hasErrors = (_cacheStatus['forecastError'] != null ||
        _cacheStatus['currentError'] != null ||
        _cacheStatus['warningError'] != null);

    if (!hasErrors) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.all(8),
      color: Colors.red[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '错误信息',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 12),
            if (_cacheStatus['forecastError'] != null)
              _buildErrorRow('天气预报', _cacheStatus['forecastError']),
            if (_cacheStatus['currentError'] != null)
              _buildErrorRow('当前天气', _cacheStatus['currentError']),
            if (_cacheStatus['warningError'] != null)
              _buildErrorRow('天气警告', _cacheStatus['warningError']),
          ],
        ),
      ),
    );
  }

  ///9，构建错误行
  Widget _buildErrorRow(String label, String error) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label:',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
          ),
          Text(
            error,
            style: const TextStyle(fontSize: 12, color: Colors.red),
          ),
        ],
      ),
    );
  }

  ///10，构建天气数据预览卡片
  Widget _buildWeatherDataPreviewCard() {
    return Consumer<WeatherProvider>(
      builder: (context, weatherProvider, child) {
        return Card(
          margin: const EdgeInsets.all(8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '数据预览',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.purple,
                  ),
                ),
                const SizedBox(height: 12),

                // 天气预报数据预览
                if (weatherProvider.hasForecastData)
                  _buildDataPreviewSection(
                    '天气预报',
                    '更新于: ${DateFormat('HH:mm').format(DateTime.parse(weatherProvider.weatherForecastData!.updateTime))}',
                    '${weatherProvider.weatherForecastData!.weatherForecast.length} 天预报',
                  ),

                // 当前天气数据预览
                if (weatherProvider.hasCurrentData)
                  _buildDataPreviewSection(
                    '当前天气',
                    '更新于: ${DateFormat('HH:mm').format(DateTime.parse(weatherProvider.currentWeatherData!.updateTime))}',
                    '温度: ${weatherProvider.currentWeatherData!.temperature?.data.first.value ?? '--'}°C',
                  ),

                // 天气警告数据预览
                if (weatherProvider.hasWarningData)
                  _buildDataPreviewSection(
                    '天气警告',
                    '警告数量: ${weatherProvider.weatherWarningData!.warnings.length}',
                    weatherProvider.weatherWarningData!.warnings.isNotEmpty
                        ? weatherProvider.weatherWarningData!
                            .getActiveWarningDescriptions()
                            .first
                        : '无活动警告',
                  ),

                if (!weatherProvider.hasForecastData &&
                    !weatherProvider.hasCurrentData &&
                    !weatherProvider.hasWarningData)
                  const Text(
                    '暂无缓存数据',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  ///11，构建数据预览部分
  Widget _buildDataPreviewSection(
      String title, String subtitle, String content) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.purple,
            ),
          ),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          Text(
            content,
            style: const TextStyle(fontSize: 12),
          ),
          const Divider(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('天气数据调试工具'),
        backgroundColor: Colors.blue[100],
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadCacheStatus,
            tooltip: '刷新状态',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在加载缓存状态...'),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // 缓存状态卡片
                  _buildCacheStatusCard(),

                  // 错误信息卡片
                  _buildErrorCard(),

                  // 天气数据预览卡片
                  _buildWeatherDataPreviewCard(),

                  const SizedBox(height: 20),

                  // 操作按钮
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                        onPressed: _refreshWeatherData,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('刷新数据'),
                      ),
                      ElevatedButton(
                        onPressed: _clearCache,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('清除缓存'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // 定时更新控制按钮
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                        onPressed: _startPeriodicUpdate,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('启动定时更新'),
                      ),
                      ElevatedButton(
                        onPressed: _stopPeriodicUpdate,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('停止定时更新'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // 说明信息
                  Card(
                    color: Colors.grey[50],
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '说明',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '• 此工具用于调试天气数据的持久化存储状态\n'
                            '• 可以查看缓存中的数据状态和错误信息\n'
                            '• 支持手动刷新数据和清除缓存\n'
                            '• 可以控制定时更新功能\n'
                            '• 断开网络连接后仍可查看缓存的数据',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
