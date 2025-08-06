import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:iboard_app/providers/arrear_provider.dart';
// import 'package:iboard_app/widgets/debug_arrear_widget.dart'; // 未使用的导入

class ArrearDisplayWidget extends StatefulWidget {
  final VoidCallback? onHomeButtonPressed; // 添加主頁按鈕回調

  const ArrearDisplayWidget({
    Key? key,
    this.onHomeButtonPressed,
  }) : super(key: key);

  @override
  ArrearDisplayWidgetState createState() => ArrearDisplayWidgetState();
}

class ArrearDisplayWidgetState extends State<ArrearDisplayWidget> {
  String? _selectedBuilding;
  String? _selectedFloor;
  bool _showResults = false;
  int _currentPage = 1;
  final int _itemsPerPage = 6;

  ///1, 自动返回主页方法 - 用于全屏广告状态时调用
  void autoReturnToHome() {
    if (widget.onHomeButtonPressed != null) {
      widget.onHomeButtonPressed!();
    }
  }

    ///2, 强制刷新欠费数据（使用正确的ismartId）
  Future<void> _forceRefreshData() async {
    final provider = Provider.of<ArrearProvider>(context, listen: false);
    
    // 显示当前调试信息
    final debugInfo = provider.getIsmartIdDebugInfo();
    print('🔍 [ArrearDisplayWidget] ismartId调试信息:');
    debugInfo.forEach((key, value) {
      print('  $key: $value');
    });
    
    // 测试AppDataProvider连接
    provider.testAppDataProviderConnection();
    
    print('🔄 [ArrearDisplayWidget] 手动触发强制刷新');
    await provider.forceRefreshWithCorrectIsmartId();
  }

  @override
  void initState() {
    super.initState();
    // 数据已在main.dart中通过AppDataProvider初始化
    // 优先从缓存加载数据，确保即使网络失败也能显示数据
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<ArrearProvider>(context, listen: false);
      print(
          '🔍 [ArrearDisplayWidget] 初始化 - 当前原始数据记录数: ${provider.rawArrearData.length}');

      if (provider.rawArrearData.isEmpty) {
        print('🔍 [ArrearDisplayWidget] 数据为空，从缓存加载');
        provider.loadFromCache();
      } else {
        print('🔍 [ArrearDisplayWidget] 使用现有数据，与欠费总览共享同一数据源');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ArrearProvider>(
      builder: (context, provider, child) {
        return Stack(
          children: [
            // 主要内容
            Container(
              color: Colors.grey.shade50,
              child: Column(
                children: [
                  // 标题区域
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Text(
                      '欠費查詢',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          // 选择器容器
                          _buildSelectorContainer(provider),

                          const SizedBox(height: 20),

                          // 查询按钮
                          _buildQueryButton(),

                          const SizedBox(height: 20),

                          // 查询结果
                          if (_showResults) _buildResultsContainer(provider),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 主頁按鈕 - 位於右上角
            if (widget.onHomeButtonPressed != null)
              Positioned(
                top: 16,
                right: 16,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: widget.onHomeButtonPressed,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.home,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),

            // 调试按钮 - 位于左上角（强制刷新ismartId）
            Positioned(
              top: 16,
              left: 16,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _forceRefreshData,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.refresh,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  ///2, 构建选择器容器
  Widget _buildSelectorContainer(ArrearProvider provider) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // 楼号选择器
          _buildBuildingSelector(provider),

          const SizedBox(height: 16),

          // 楼层选择器
          _buildFloorSelector(provider),
        ],
      ),
    );
  }

  ///3, 构建樓層选择器
  Widget _buildBuildingSelector(ArrearProvider provider) {
    final buildings = provider.buildings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '選擇樓層',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: buildings.map((building) {
            final isSelected = _selectedBuilding == building;
            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedBuilding = building;
                  _selectedFloor = null; // 重置楼层选择
                  _showResults = false; // 重置查询结果
                  // 更新Provider中的选择
                  provider.setSelectedBuildingId(building);
                });
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Theme.of(context).primaryColor
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected
                        ? Theme.of(context).primaryColor
                        : Colors.grey.shade300,
                    width: 1,
                  ),
                ),
                child: Text(
                  '${building}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isSelected ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  ///4, 构建楼层选择器
  Widget _buildFloorSelector(ArrearProvider provider) {
    final floors =
        _selectedBuilding != null ? provider.getFloors(_selectedBuilding!) : [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '選擇單位',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: floors.map((floor) {
            final isSelected = _selectedFloor == floor;
            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedFloor = floor;
                  _showResults = false; // 重置查询结果
                  // 更新Provider中的选择
                  provider.setSelectedUnit(floor);
                });
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Theme.of(context).primaryColor
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected
                        ? Theme.of(context).primaryColor
                        : Colors.grey.shade300,
                    width: 1,
                  ),
                ),
                child: Text(
                  floor,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isSelected ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  ///5, 构建查询按钮
  Widget _buildQueryButton() {
    final canQuery = _selectedBuilding != null && _selectedFloor != null;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: canQuery ? _handleQuery : null,
        style: ElevatedButton.styleFrom(
          backgroundColor:
              canQuery ? Theme.of(context).primaryColor : Colors.grey.shade300,
          foregroundColor: canQuery ? Colors.white : Colors.grey.shade600,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: canQuery ? 2 : 0,
        ),
        child: const Text(
          '查詢繳費記錄',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  ///6, 处理查询
  void _handleQuery() {
    if (_selectedBuilding != null && _selectedFloor != null) {
      setState(() {
        _showResults = true;
        _currentPage = 1;
      });
    }
  }

  ///7, 构建结果容器 - 静默使用缓存数据，但显示格式错误
  Widget _buildResultsContainer(ArrearProvider provider) {
    if (provider.isLoading) {
      return Container(
        padding: const EdgeInsets.all(40),
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // 检查是否有错误需要显示
    if (provider.error != null && provider.error!.isNotEmpty) {
      return _buildErrorContainer(provider.error!);
    }

    final arrears = provider.arrears;
    final hasData = arrears.isNotEmpty || provider.rawArrearData.isNotEmpty;

    // 如果有数据就显示，没有数据就显示空状态
    if (hasData) {
      return _buildDataContent(provider);
    }

    // 没有数据时显示空状态
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Center(
        child: Column(
          children: [
            Icon(Icons.info_outline, color: Colors.grey, size: 60),
            SizedBox(height: 16),
            Text(
              '暫無欠費數據',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '請稍後再試或聯繫管理員',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  ///8, 构建错误容器
  Widget _buildErrorContainer(String errorMessage) {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 60),
            const SizedBox(height: 16),
            const Text(
              '數據獲取失敗',
              style: TextStyle(
                fontSize: 18,
                color: Colors.red,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            SelectableText.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: errorMessage,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              '請聯繫系統管理員檢查樓宇配置',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  ///9, 构建数据内容
  Widget _buildDataContent(ArrearProvider provider) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // 结果标题
          Row(
            children: [
              const Icon(Icons.receipt_long, color: Colors.blue, size: 24),
              const SizedBox(width: 8),
              Text(
                '查詢結果 - ${_selectedBuilding}${_selectedFloor}單位',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // 欠费记录列表
          _buildArrearList(provider),

          const SizedBox(height: 20),

          // 分页控制
          _buildPagination(provider),
        ],
      ),
    );
  }

  ///9, 构建欠费记录列表
  Widget _buildArrearList(ArrearProvider provider) {
    final currentArrearage = provider.currentArrearage;

    if (currentArrearage == null) {
      return const Center(
        child: Text('暂无数据'),
      );
    }

    // 将 Map 转换为列表用于分页显示
    final entries = currentArrearage.entries.toList();
    final startIndex = (_currentPage - 1) * _itemsPerPage;
    final endIndex = (startIndex + _itemsPerPage).clamp(0, entries.length);
    final pageEntries = entries.sublist(startIndex, endIndex);

    return Column(
      children: pageEntries.map((entry) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.key,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      entry.value.toString(),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: _getStatusColor(entry.value),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  /// 获取状态颜色
  Color _getStatusColor(dynamic value) {
    if (value is String && value == '已付') {
      return Colors.green;
    }
    if (value is num && value < 0) {
      return Colors.red;
    }
    return Colors.black87;
  }

  ///10, 构建分页控制
  Widget _buildPagination(ArrearProvider provider) {
    final currentArrearage = provider.currentArrearage;
    if (currentArrearage == null) {
      return const SizedBox.shrink();
    }

    final totalItems = currentArrearage.length;
    final totalPages = (totalItems / _itemsPerPage).ceil();

    if (totalPages <= 1) return const SizedBox.shrink();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 上一页按钮
        ElevatedButton(
          onPressed: _currentPage > 1
              ? () {
                  setState(() {
                    _currentPage--;
                  });
                }
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: _currentPage > 1
                ? Theme.of(context).primaryColor
                : Colors.grey.shade300,
            foregroundColor:
                _currentPage > 1 ? Colors.white : Colors.grey.shade600,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          child: const Text('上一頁'),
        ),

        const SizedBox(width: 16),

        // 页码显示
        Text(
          '第 $_currentPage 頁，共 $totalPages 頁',
          style: const TextStyle(
            fontSize: 14,
            color: Colors.black87,
          ),
        ),

        const SizedBox(width: 16),

        // 下一页按钮
        ElevatedButton(
          onPressed: _currentPage < totalPages
              ? () {
                  setState(() {
                    _currentPage++;
                  });
                }
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: _currentPage < totalPages
                ? Theme.of(context).primaryColor
                : Colors.grey.shade300,
            foregroundColor:
                _currentPage < totalPages ? Colors.white : Colors.grey.shade600,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          child: const Text('下一頁'),
        ),
      ],
    );
  }
}
