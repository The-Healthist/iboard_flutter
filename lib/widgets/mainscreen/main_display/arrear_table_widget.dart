import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:iboard_app/providers/arrear_provider.dart';
import 'package:iboard_app/providers/state_provider.dart';
import 'package:iboard_app/providers/app_data_provider.dart';

class ArrearTableWidget extends StatefulWidget {
  final VoidCallback? onHomeButtonPressed; // 添加主頁按鈕回調
  final bool isInCarouselMode; // 是否在轮播模式中
  final Function(int totalPages)? onPaginationComplete; // 轮播模式下翻页完成回调
  final Function(int totalPages)? onPaginationStart; // 轮播模式下翻页开始回调

  const ArrearTableWidget({
    Key? key,
    this.onHomeButtonPressed,
    this.isInCarouselMode = false, // 默认不在轮播模式
    this.onPaginationComplete,
    this.onPaginationStart,
  }) : super(key: key);

  @override
  ArrearTableWidgetState createState() => ArrearTableWidgetState();
}

class ArrearTableWidgetState extends State<ArrearTableWidget> {
  int _currentPage = 1;
  int _itemsPerPage = 20; // 增加初始每页项数以减少空白
  Timer? _autoPaginationTimer; // 自动翻页定时器
  bool _isPaginationPaused = false; // 翻页是否暂停
  int _totalPages = 0; // 总页数

  ///1, 自动返回主页方法 - 用于全屏广告状态时调用
  void autoReturnToHome() {
    if (widget.onHomeButtonPressed != null) {
      widget.onHomeButtonPressed!();
    }
  }

  @override
  void initState() {
    super.initState();
    // 确保数据已加载 - 使用与欠费查询相同的数据源
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<ArrearProvider>(context, listen: false);

      if (!provider.hasData) {
        provider.loadFromCache();
      }
      // 如果在轮播模式下，启动自动翻页
      if (widget.isInCarouselMode && provider.hasData) {
        _startAutoPagination();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ArrearProvider>(
      builder: (context, provider, child) {
        // 监听媒体暂停状态 - 仅在轮播模式下生效
        if (widget.isInCarouselMode) {
          final carouselStateProvider = context.watch<CarouselStateProvider>();
          final currentAppState = carouselStateProvider.currentAppState;

          // 检查中部通告轮播是否应该暂停（全屏广告或手动操作状态）
          final shouldPauseCarousel =
              currentAppState == AppState.fullscreenAd ||
                  currentAppState == AppState.manualOperation;
          if (shouldPauseCarousel && !_isPaginationPaused) {
            _pauseAutoPagination();
          } else if (!shouldPauseCarousel && _isPaginationPaused) {
            _resumeAutoPagination();
          }
        }

        return Stack(
          children: [
            // 主要内容
            Container(
              color: Colors.grey.shade50,
              child: Column(
                children: [
                  // 标题区域 - 与欠费查询保持一致的样式
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 16),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(12),
                        topRight: Radius.circular(12),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Text(
                      '繳費表單',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  // 表格内容区域
                  Expanded(
                    child: _buildTableContent(provider),
                  ),
                  // 分頁欄放在表格下方
                  _buildPagination(provider),
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
          ],
        );
      },
    );
  }

  ///2, 构建表格内容
  Widget _buildTableContent(ArrearProvider provider) {
    if (provider.isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    // 使用新的费用数据结构
    if (!provider.hasData) {
      return _buildEmptyState();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // 動態計算每頁顯示的行數，增加顯示行數以減少空白
        final double outerPadding = 16 * 2; // 上下margin
        final double titleHeight = 56; // 标题区域高度
        final double paginationHeight = 56; // 分页栏高度
        final double rowHeight = 40; // 減少每行高度從48到40
        final double headerHeight = 44; // 表头高度

        final double screenHeight = MediaQuery.of(context).size.height;
        final double mainAreaHeight = screenHeight * 14 / 24;
        final double availableHeight = mainAreaHeight -
            outerPadding -
            titleHeight -
            paginationHeight -
            headerHeight;
        final int dynamicRows = ((availableHeight / rowHeight).floor() - 1)
            .clamp(8, 50); // 行數減1防止溢出

        // 如果每页项数发生变化，更新状态以确保分页控件显示正确
        if (_itemsPerPage != dynamicRows) {
          _itemsPerPage = dynamicRows;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                // 触发重新构建以更新分页控件
              });
            }
          });
        }

        // 构建表格数据
        final tableData = _buildTableData(provider);
        final paginatedData = _getPaginatedData(tableData);

        return Container(
          margin: const EdgeInsets.all(16),
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
              // 自定義表頭
              Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF6C4EB6), // 你的主題色
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10), // 減少垂直padding
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        '單位',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    ..._getTableHeaders(tableData).map((header) => Expanded(
                          flex: 2,
                          child: Text(
                            header,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        )),
                  ],
                ),
              ),
              // 數據區域
              ...paginatedData.map((record) => Container(
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Color(0xFFF0F0F0)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 10, // 減少垂直padding從12到10
                              horizontal: 16,
                            ),
                            child: Text(
                              record['單位']?.toString() ?? '-',
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                                color: Colors.black87,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        ..._getTableHeaders(tableData).map((header) => Expanded(
                              flex: 2,
                              child: Center(
                                child: _buildStatusChip(record[header]),
                              ),
                            )),
                      ],
                    ),
                  )),
              // 用Expanded自動填滿剩餘空間
              Expanded(child: Container()),
            ],
          ),
        );
      },
    );
  }

  ///3, 构建表格数据（仅包含物业管理费用）
  List<Map<String, dynamic>> _buildTableData(ArrearProvider provider) {
    final List<Map<String, dynamic>> tableData = [];

    // 仅从物业管理费用数据构建表格数据
    if (provider.managementFeeData != null) {
      for (final block in provider.managementFeeData!.blocks) {
        for (final floor in block.floors) {
          for (final unit in floor.units) {
            final Map<String, dynamic> rowData = {
              '單位': '${floor.name}${unit.name}',
            };

            // 添加费用数据
            for (final bill in unit.bills) {
              rowData[bill.period] = bill.value;
            }

            tableData.add(rowData);
          }
        }
      }
    }

    return tableData;
  }

  ///4, 构建状态芯片 - 優化尺寸以節省空間
  Widget _buildStatusChip(dynamic value) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 4), // 減少padding
      decoration: BoxDecoration(
        color: _getStatusColor(value),
        borderRadius: BorderRadius.circular(12), // 減少圓角
      ),
      child: Text(
        _getStatusText(value),
        style: TextStyle(
          fontSize: 11, // 減少字體大小
          fontWeight: FontWeight.w500,
          color: _getStatusTextColor(value),
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  ///5, 获取状态颜色
  Color _getStatusColor(dynamic value) {
    if (value == null) return Colors.grey.shade100;
    if (value == '已付') return Colors.green.shade100;
    if (value is num && value < 0) return Colors.red.shade100;
    return Colors.grey.shade100;
  }

  ///6, 获取状态文字颜色
  Color _getStatusTextColor(dynamic value) {
    if (value == null) return Colors.grey.shade800;
    if (value == '已付') return Colors.green.shade800;
    if (value is num && value < 0) return Colors.red.shade800;
    return Colors.grey.shade800;
  }

  ///7, 获取状态文字
  String _getStatusText(dynamic value) {
    if (value == null) return '-';
    return value.toString();
  }

  ///8, 获取表头
  List<String> _getTableHeaders(List<Map<String, dynamic>> tableData) {
    if (tableData.isEmpty) return [];

    // 获取第一条记录的所有键，排除"單位"字段
    final firstRecord = tableData.first;
    return firstRecord.keys.where((key) => key != '單位').toList();
  }

  ///9, 获取分页数据
  List<Map<String, dynamic>> _getPaginatedData(
      List<Map<String, dynamic>> tableData) {
    final startIndex = (_currentPage - 1) * _itemsPerPage;
    final endIndex = (startIndex + _itemsPerPage).clamp(0, tableData.length);
    return tableData.sublist(startIndex, endIndex);
  }

  ///10, 构建分页控件
  Widget _buildPagination(ArrearProvider provider) {
    final tableData = _buildTableData(provider);
    final totalItems = tableData.length;

    // 确保使用正确计算的每页项数
    int actualItemsPerPage = _itemsPerPage;

    // 如果还是初始值（20），重新计算正确的每页项数
    if (_itemsPerPage == 20) {
      final double screenHeight = MediaQuery.of(context).size.height;
      final double mainAreaHeight = screenHeight * 14 / 24;
      final double outerPadding = 16 * 2;
      final double titleHeight = 56;
      final double paginationHeight = 56;
      final double rowHeight = 40;
      final double headerHeight = 44;
      final double availableHeight = mainAreaHeight -
          outerPadding -
          titleHeight -
          paginationHeight -
          headerHeight;
      actualItemsPerPage =
          ((availableHeight / rowHeight).floor() - 1).clamp(8, 50);
    }

    final totalPages = (totalItems / actualItemsPerPage).ceil();

    if (totalPages <= 1) return const SizedBox.shrink();

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
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
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 4), // 进一步减少按钮padding
              minimumSize: const Size(70, 26), // 设置更小的最小尺寸
            ),
            child: const Text('上一頁', style: TextStyle(fontSize: 17)), // 增大4px
          ),

          const SizedBox(width: 16),

          // 页码显示
          Text(
            '第 $_currentPage 頁，共 $totalPages 頁',
            style: const TextStyle(
              fontSize: 17, // 增大4px
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
              foregroundColor: _currentPage < totalPages
                  ? Colors.white
                  : Colors.grey.shade600,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 4), // 进一步减少按钮padding
              minimumSize: const Size(70, 26), // 设置更小的最小尺寸
            ),
            child: const Text('下一頁', style: TextStyle(fontSize: 17)), // 增大4px
          ),
        ],
      ),
    );
  }

  ///11, 启动自动翻页 - 仅在轮播模式下使用
  void _startAutoPagination() {
    if (!widget.isInCarouselMode) return;

    // 确保在启动自动翻页前先计算正确的每页项数
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<ArrearProvider>(context, listen: false);
      final tableData = _buildTableData(provider);

      // 重新计算每页项数，确保总页数准确
      final screenHeight = MediaQuery.of(context).size.height;
      final double mainAreaHeight = screenHeight * 14 / 24;
      final double outerPadding = 16 * 2;
      final double titleHeight = 56;
      final double paginationHeight = 56;
      final double rowHeight = 40;
      final double headerHeight = 44;
      final double availableHeight = mainAreaHeight -
          outerPadding -
          titleHeight -
          paginationHeight -
          headerHeight;
      final int dynamicRows =
          ((availableHeight / rowHeight).floor() - 1).clamp(8, 50);

      _itemsPerPage = dynamicRows;

      _totalPages = (tableData.length / _itemsPerPage).ceil();

      if (_totalPages <= 1) {
        // 只有一页，直接通知完成
        Future.delayed(Duration(seconds: 5), () {
          if (widget.onPaginationComplete != null) {
            widget.onPaginationComplete!(_totalPages);
          }
        });
        return;
      }

      // 通知轮播提供者开始翻页（用于动态延长停留时间）
      if (widget.onPaginationStart != null) {
        widget.onPaginationStart!(_totalPages);
      }

      // 启动实际的自动翻页逻辑
      _startActualAutoPagination();
    });
  }

  ///12, 启动实际的自动翻页逻辑
  void _startActualAutoPagination() {
    // 获取设置中的翻页时间，默认为5秒
    final appDataProvider =
        Provider.of<AppDataProvider>(context, listen: false);
    final deviceSettings = appDataProvider.deviceSettings;
    final paginationDuration = deviceSettings?.paymentTableOnePageDuration ?? 5;

    _autoPaginationTimer?.cancel();
    _autoPaginationTimer =
        Timer.periodic(Duration(seconds: paginationDuration), (timer) {
      if (_isPaginationPaused) return; // 如果暂停，跳过这次执行

      if (_currentPage < _totalPages) {
        setState(() {
          _currentPage++;
        });
      } else {
        // 已经是最后一页，重置到第一页并通知完成
        setState(() {
          _currentPage = 1; // 重置到第一页，開始新的循環
        });

        if (widget.onPaginationComplete != null) {
          widget.onPaginationComplete!(_totalPages);
        }
      }
    });
  }

  ///13, 暂停自动翻页
  void _pauseAutoPagination() {
    if (!_isPaginationPaused) {
      _isPaginationPaused = true;
    }
  }

  ///14, 恢复自动翻页
  void _resumeAutoPagination() {
    if (_isPaginationPaused) {
      _isPaginationPaused = false;

      // 如果定时器不活跃且还有页面需要翻页，重新启动翻页
      if ((_autoPaginationTimer == null || !_autoPaginationTimer!.isActive) &&
          _currentPage < _totalPages) {
        _startActualAutoPagination();
      }
    }
  }

  ///15, 停止自动翻页
  void _stopAutoPagination() {
    _autoPaginationTimer?.cancel();
    _autoPaginationTimer = null;
    _isPaginationPaused = false;
  }

  ///16, 构建空状态
  Widget _buildEmptyState() {
    return Container(
      margin: const EdgeInsets.all(16),
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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.table_chart_outlined, color: Colors.grey, size: 60),
            SizedBox(height: 16),
            Text(
              '暫無費用數據',
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

  @override
  void dispose() {
    _stopAutoPagination(); // 清理自动翻页定时器
    super.dispose();
  }
}
