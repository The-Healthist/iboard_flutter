import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:iboard_app/providers/arrear_provider.dart';
import 'package:logger/logger.dart';

/// 欠费数据调试工具组件
class ArrearDebugWidget extends StatefulWidget {
  const ArrearDebugWidget({Key? key}) : super(key: key);

  @override
  _ArrearDebugWidgetState createState() => _ArrearDebugWidgetState();
}

class _ArrearDebugWidgetState extends State<ArrearDebugWidget> {
  final Logger _logger = Logger();
  Map<String, dynamic> _debugInfo = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkArrearDataStatus();
  }

  ///1, 检查欠费数据状态
  Future<void> _checkArrearDataStatus() async {
    setState(() {
      _isLoading = true;
    });

    final debugInfo = <String, dynamic>{};

    // 获取Provider实例
    final provider = Provider.of<ArrearProvider>(context, listen: false);

    // 检查缓存状态
    await _checkCacheStatus(debugInfo, provider);

    // 检查当前数据状态
    await _checkCurrentDataStatus(debugInfo, provider);

    // 检查楼宇和单元信息
    await _checkBuildingAndUnitInfo(debugInfo, provider);

    setState(() {
      _debugInfo = debugInfo;
      _isLoading = false;
    });

    _logger.i('💰 欠费数据调试信息: $_debugInfo');
  }

  ///2, 检查缓存状态
  Future<void> _checkCacheStatus(
      Map<String, dynamic> debugInfo, ArrearProvider provider) async {
    final cacheStatus = await provider.getCacheStatus();
    final lastUpdate = await provider.getLastUpdateTime();

    debugInfo['缓存状态'] = {
      '是否有缓存': cacheStatus['hasCache'] ? '✅ 有缓存' : '❌ 无缓存',
      '缓存大小': '${cacheStatus['cacheSize']} 字节',
      '记录数量': cacheStatus['recordCount'],
      '最后更新': lastUpdate ?? '从未更新',
      '缓存状态详情': cacheStatus,
    };
  }

  ///3, 检查当前数据状态
  Future<void> _checkCurrentDataStatus(
      Map<String, dynamic> debugInfo, ArrearProvider provider) async {
    final arrears = provider.arrears;
    final rawData = provider.rawArrearData;
    final isLoading = provider.isLoading;
    final error = provider.error;

    debugInfo['当前数据状态'] = {
      '加载状态': isLoading ? '🔄 加载中' : '✅ 已加载',
      '错误信息': error ?? '无错误',
      'ArrearModel数量': arrears.length,
      '原始数据数量': rawData.length,
      '选中楼宇ID': provider.selectedBuildingId ?? '未选择',
      '选中单元': provider.selectedUnit ?? '未选择',
    };

    // 如果有数据，显示数据统计
    if (rawData.isNotEmpty) {
      final dataStats = _analyzeDataStatistics(rawData);
      debugInfo['数据统计'] = dataStats;
    }
  }

  ///4, 检查楼宇和单元信息
  Future<void> _checkBuildingAndUnitInfo(
      Map<String, dynamic> debugInfo, ArrearProvider provider) async {
    final buildings = provider.buildings;
    final selectedBuilding = provider.selectedBuildingId;
    final selectedUnit = provider.selectedUnit;

    debugInfo['楼宇信息'] = {
      '总楼宇数量': buildings.length,
      '可用楼宇': buildings.join(', '),
      '当前选中楼宇': selectedBuilding ?? '未选择',
      '当前选中单元': selectedUnit ?? '未选择',
    };

    if (selectedBuilding != null) {
      final floors = provider.getFloors(selectedBuilding);
      debugInfo['楼宇信息']['选中楼宇的单元'] = floors.join(', ');
    }
  }

  ///5, 分析数据统计
  Map<String, dynamic> _analyzeDataStatistics(List<Map<String, dynamic>> data) {
    if (data.isEmpty) return {'状态': '无数据'};

    final stats = <String, dynamic>{};
    final firstRecord = data.first;

    // 分析数据结构
    stats['数据字段'] = firstRecord.keys.toList();
    stats['记录总数'] = data.length;

    // 分析单位信息
    final units = <String>{};
    for (final record in data) {
      if (record.containsKey('單位')) {
        units.add(record['單位'].toString());
      }
    }
    stats['单位总数'] = units.length;
    stats['单位列表'] = units.toList()..sort();

    return stats;
  }

  ///6, 手动刷新数据
  Future<void> _refreshData() async {
    final provider = Provider.of<ArrearProvider>(context, listen: false);

    _logger.i('🔄 开始手动刷新欠费数据');

    try {
      await provider.fetchArrears(reset: true);
      _logger.i('✅ 欠费数据刷新成功');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('欠费数据刷新成功'),
            backgroundColor: Colors.green,
          ),
        );
      }

      // 刷新调试信息
      await _checkArrearDataStatus();
    } catch (e) {
      _logger.e('❌ 欠费数据刷新失败: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('刷新失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  ///7, 从缓存加载数据
  Future<void> _loadFromCache() async {
    final provider = Provider.of<ArrearProvider>(context, listen: false);

    _logger.i('📂 从缓存加载欠费数据');

    try {
      await provider.loadFromCache();
      _logger.i('✅ 从缓存加载成功');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('从缓存加载成功'),
            backgroundColor: Colors.green,
          ),
        );
      }

      // 刷新调试信息
      await _checkArrearDataStatus();
    } catch (e) {
      _logger.e('❌ 从缓存加载失败: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('加载失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  ///8, 清除缓存
  Future<void> _clearCache() async {
    final provider = Provider.of<ArrearProvider>(context, listen: false);

    _logger.i('🗑️ 清除欠费数据缓存');

    try {
      await provider.clearCache();
      _logger.i('✅ 缓存清除成功');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('缓存清除成功'),
            backgroundColor: Colors.green,
          ),
        );
      }

      // 刷新调试信息
      await _checkArrearDataStatus();
    } catch (e) {
      _logger.e('❌ 清除缓存失败: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('清除失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  ///9, 获取文本颜色
  Color _getTextColor(String key, dynamic value) {
    if (value == null) return Colors.grey;

    final valueStr = value.toString();

    if (valueStr.contains('❌') ||
        valueStr.contains('错误') ||
        valueStr.contains('失败')) {
      return Colors.red;
    }

    if (valueStr.contains('✅') ||
        valueStr.contains('成功') ||
        valueStr.contains('有缓存')) {
      return Colors.green;
    }

    if (valueStr.contains('🔄') || valueStr.contains('加载中')) {
      return Colors.orange;
    }

    if (key.contains('数量') || key.contains('总数')) {
      return Colors.blue;
    }

    return Colors.black87;
  }

  ///10, 构建调试信息卡片
  Widget _buildDebugCard(String title, Map<String, dynamic> data) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 8),
            ...data.entries
                .where((entry) =>
                    entry.key != '详细信息' &&
                    entry.key != '数据字段' &&
                    entry.key != '单位列表')
                .map((entry) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${entry.key}: ',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Expanded(
                            child: Text(
                              entry.value.toString(),
                              style: TextStyle(
                                color: _getTextColor(entry.key, entry.value),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ))
                .toList(),
          ],
        ),
      ),
    );
  }

  ///11, 构建数据展示卡片
  Widget _buildDataDisplayCard() {
    final provider = Provider.of<ArrearProvider>(context, listen: false);
    final rawData = provider.rawArrearData;

    if (rawData.isEmpty) {
      return Card(
        margin: const EdgeInsets.all(8),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: Text(
              '暂无欠费数据',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '欠费数据预览',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.purple,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 300,
              child: ListView.builder(
                itemCount: rawData.length > 10 ? 10 : rawData.length,
                itemBuilder: (context, index) {
                  final record = rawData[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: record.entries.map((entry) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${entry.key}: ',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  entry.value.toString(),
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  );
                },
              ),
            ),
            if (rawData.length > 10)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  '... 还有更多数据',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('欠费数据调试工具'),
        backgroundColor: Colors.green[100],
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _checkArrearDataStatus,
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
                  Text('正在检查欠费数据状态...'),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // 缓存状态信息
                  if (_debugInfo['缓存状态'] != null)
                    _buildDebugCard('缓存状态', _debugInfo['缓存状态']),

                  // 当前数据状态
                  if (_debugInfo['当前数据状态'] != null)
                    _buildDebugCard('当前数据状态', _debugInfo['当前数据状态']),

                  // 楼宇信息
                  if (_debugInfo['楼宇信息'] != null)
                    _buildDebugCard('楼宇信息', _debugInfo['楼宇信息']),

                  // 数据统计
                  if (_debugInfo['数据统计'] != null)
                    _buildDebugCard('数据统计', _debugInfo['数据统计']),

                  const SizedBox(height: 20),

                  // 数据预览
                  _buildDataDisplayCard(),

                  const SizedBox(height: 20),

                  // 操作按钮
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                        onPressed: _loadFromCache,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('从缓存加载'),
                      ),
                      ElevatedButton(
                        onPressed: _refreshData,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('刷新数据'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                        onPressed: _clearCache,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('清除缓存'),
                      ),
                      ElevatedButton(
                        onPressed: _checkArrearDataStatus,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('重新检查'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // 全部重新检查按钮
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        await _clearCache();
                        await _refreshData();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('清除缓存并重新获取'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
