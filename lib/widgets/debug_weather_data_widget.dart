import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:iboard_app/providers/weather_provider.dart';
import 'package:logger/logger.dart';
import 'package:intl/intl.dart';

/// 天氣數據調試工具組件
class WeatherDataDebugWidget extends StatefulWidget {
  const WeatherDataDebugWidget({super.key});

  @override
  WeatherDataDebugWidgetState createState() => WeatherDataDebugWidgetState();
}

class WeatherDataDebugWidgetState extends State<WeatherDataDebugWidget> {
  final Logger _logger = Logger();
  Map<String, dynamic> _cacheStatus = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCacheStatus();
  }

  ///1，加載緩存狀態信息
  Future<void> _loadCacheStatus() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final weatherProvider =
          Provider.of<WeatherProvider>(context, listen: false);
      final status = await weatherProvider.getCacheStatus();
      if (!mounted) return;
      setState(() {
        _cacheStatus = status;
        _isLoading = false;
      });
    } catch (e) {
      _logger.e('獲取緩存狀態失敗', error: e);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  ///2，刷新天氣數據
  Future<void> _refreshWeatherData() async {
    try {
      final weatherProvider =
          Provider.of<WeatherProvider>(context, listen: false);
      await weatherProvider.fetchAllWeatherData();

      // 重新加載緩存狀態
      await _loadCacheStatus();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('天氣數據已刷新'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      _logger.e('刷新天氣數據失敗', error: e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('刷新失敗: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  ///3，清除緩存
  Future<void> _clearCache() async {
    try {
      final weatherProvider =
          Provider.of<WeatherProvider>(context, listen: false);
      await weatherProvider.clearCache();

      // 重新加載緩存狀態
      await _loadCacheStatus();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('天氣數據緩存已清除'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      _logger.e('清除緩存失敗', error: e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('清除失敗: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  ///4，啟動定時更新
  void _startPeriodicUpdate() {
    final weatherProvider =
        Provider.of<WeatherProvider>(context, listen: false);
    weatherProvider.startPeriodicUpdate(interval: const Duration(hours: 2));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已啟動定時更新（每2小時）'),
        backgroundColor: Colors.blue,
      ),
    );

    // 重新加載狀態
    _loadCacheStatus();
  }

  ///5，停止定時更新
  void _stopPeriodicUpdate() {
    final weatherProvider =
        Provider.of<WeatherProvider>(context, listen: false);
    weatherProvider.stopPeriodicUpdate();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已停止定時更新'),
        backgroundColor: Colors.orange,
      ),
    );

    // 重新加載狀態
    _loadCacheStatus();
  }

  ///6，構建緩存狀態卡片
  Widget _buildCacheStatusCard() {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '緩存狀態',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 12),
            _buildStatusRow(
                '天氣預報緩存', _cacheStatus['hasForecastCache'] ?? false),
            _buildStatusRow('當前天氣緩存', _cacheStatus['hasCurrentCache'] ?? false),
            _buildStatusRow('天氣警告緩存', _cacheStatus['hasWarningCache'] ?? false),
            _buildStatusRow(
                '定時更新狀態', _cacheStatus['isPeriodicUpdateActive'] ?? false),
            const SizedBox(height: 8),
            if (_cacheStatus['lastUpdate'] != null)
              SelectableText(
                '最後更新: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.parse(_cacheStatus['lastUpdate']))}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }

  ///7，構建狀態行
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
          SelectableText(
            label,
            style: const TextStyle(fontSize: 14),
          ),
          const Spacer(),
          SelectableText(
            status ? '✅ 有數據' : '❌ 無數據',
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

  ///8，構建錯誤信息卡片
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
            const SelectableText(
              '錯誤信息',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 12),
            if (_cacheStatus['forecastError'] != null)
              _buildErrorRow('天氣預報', _cacheStatus['forecastError']),
            if (_cacheStatus['currentError'] != null)
              _buildErrorRow('當前天氣', _cacheStatus['currentError']),
            if (_cacheStatus['warningError'] != null)
              _buildErrorRow('天氣警告', _cacheStatus['warningError']),
          ],
        ),
      ),
    );
  }

  ///9，構建錯誤行
  Widget _buildErrorRow(String label, String error) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            '$label:',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
          ),
          SelectableText(
            error,
            style: const TextStyle(fontSize: 12, color: Colors.red),
          ),
        ],
      ),
    );
  }

  ///10，構建天氣數據預覽卡片
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
                const SelectableText(
                  '數據預覽',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.purple,
                  ),
                ),
                const SizedBox(height: 12),

                // 天氣預報數據預覽
                if (weatherProvider.hasForecastData)
                  _buildDataPreviewSection(
                    '天氣預報',
                    '更新於: ${DateFormat('HH:mm').format(DateTime.parse(weatherProvider.weatherForecastData!.updateTime))}',
                    '${weatherProvider.weatherForecastData!.weatherForecast.length} 天預報',
                  ),

                // 當前天氣數據預覽
                if (weatherProvider.hasCurrentData)
                  _buildDataPreviewSection(
                    '當前天氣',
                    '更新於: ${DateFormat('HH:mm').format(DateTime.parse(weatherProvider.currentWeatherData!.updateTime))}',
                    '溫度: ${weatherProvider.currentWeatherData!.temperature?.data.first.value ?? '--'}°C',
                  ),

                // 天氣警告數據預覽
                if (weatherProvider.hasWarningData)
                  _buildDataPreviewSection(
                    '天氣警告',
                    '警告數量: ${weatherProvider.weatherWarningData!.warnings.length}',
                    weatherProvider.weatherWarningData!.warnings.isNotEmpty
                        ? weatherProvider.weatherWarningData!
                            .getActiveWarningDescriptions()
                            .first
                        : '無活動警告',
                  ),

                if (!weatherProvider.hasForecastData &&
                    !weatherProvider.hasCurrentData &&
                    !weatherProvider.hasWarningData)
                  const SelectableText(
                    '暫無緩存數據',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  ///11，構建數據預覽部分
  Widget _buildDataPreviewSection(
      String title, String subtitle, String content) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.purple,
            ),
          ),
          SelectableText(
            subtitle,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          SelectableText(
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
        title: const Text('天氣數據調試工具'),
        backgroundColor: Colors.blue[100],
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadCacheStatus,
            tooltip: '刷新狀態',
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
                  SelectableText('正在加載緩存狀態...'),
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
                        child: const Text('刷新數據'),
                      ),
                      ElevatedButton(
                        onPressed: _clearCache,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('清除緩存'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // 定時更新控制按鈕
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                        onPressed: _startPeriodicUpdate,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('啟動定時更新'),
                      ),
                      ElevatedButton(
                        onPressed: _stopPeriodicUpdate,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('停止定時更新'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // 说明信息
                  Card(
                    color: Colors.grey[50],
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText(
                            '說明',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 8),
                          SelectableText(
                            '• 此工具用於調試天氣數據的持久化存儲狀態\n'
                            '• 可以查看緩存中的數據狀態和錯誤信息\n'
                            '• 支持手動刷新數據和清除緩存\n'
                            '• 可以控制定時更新功能\n'
                            '• 斷開網絡連接後仍可查看緩存的數據',
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
