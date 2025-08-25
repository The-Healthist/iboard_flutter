import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:iboard_app/providers/arrear_provider.dart';
import 'package:iboard_app/providers/state_provider.dart';
import 'package:iboard_app/providers/app_data_provider.dart';

class ArrearOtherTableWidget extends StatefulWidget {
  final VoidCallback? onHomeButtonPressed;
  final bool isInCarouselMode;
  final Function(int totalPages)? onPaginationComplete;
  final Function(int totalPages)? onPaginationStart;

  const ArrearOtherTableWidget({
    super.key,
    this.onHomeButtonPressed,
    this.isInCarouselMode = false,
    this.onPaginationComplete,
    this.onPaginationStart,
  });

  @override
  ArrearOtherTableWidgetState createState() => ArrearOtherTableWidgetState();
}

class ArrearOtherTableWidgetState extends State<ArrearOtherTableWidget> {
  int _currentPage = 1;
  int _itemsPerPage = 20;
  Timer? _autoPaginationTimer;
  bool _isPaginationPaused = false;
  int _totalPages = 0;

  String? _lastDataVersion;
  bool _isWaitingForDataUpdate = false;

  ///1, 自动返回主页方法
  void autoReturnToHome() {
    if (widget.onHomeButtonPressed != null) {
      widget.onHomeButtonPressed!();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<ArrearProvider>(context, listen: false);

      if (!provider.hasOtherFeeData) {
        provider.loadFromCache();
      }

      if (widget.isInCarouselMode) {
        _startAutoPagination();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ArrearProvider>(
      builder: (context, provider, child) {
        // 检测数据版本是否变化
        if (_lastDataVersion != provider.currentDataVersion) {
          if (_lastDataVersion != null && widget.isInCarouselMode) {
            _isWaitingForDataUpdate = true;
          }
          _lastDataVersion = provider.currentDataVersion;
        }

        // 监听媒体暂停状态 - 仅在轮播模式下生效
        if (widget.isInCarouselMode) {
          final carouselStateProvider = context.watch<CarouselStateProvider>();
          final currentAppState = carouselStateProvider.currentAppState;

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
            Container(
              color: Colors.grey.shade50,
              child: Column(
                children: [
                  // 标题区域
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
                      '其他費用表單',
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

    if (!provider.hasOtherFeeData) {
      return _buildEmptyState();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const double outerPadding = 16 * 2;
        const double titleHeight = 56;
        const double paginationHeight = 56;
        const double rowHeight = 40;
        const double headerHeight = 44;

        final double screenHeight = MediaQuery.of(context).size.height;
        final double mainAreaHeight = screenHeight * 14 / 24;
        final double availableHeight = mainAreaHeight -
            outerPadding -
            titleHeight -
            paginationHeight -
            headerHeight;
        final int dynamicRows =
            ((availableHeight / rowHeight).floor() - 1).clamp(8, 50);

        if (_itemsPerPage != dynamicRows) {
          _itemsPerPage = dynamicRows;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {});
            }
          });
        }

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
                  color: Color(0xFF6C4EB6),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    ..._getTableHeaders(tableData).map((header) => Expanded(
                          flex: header == '單位' ? 1 : 2,
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
                        ..._getTableHeaders(tableData).map((header) => Expanded(
                              flex: header == '單位' ? 1 : 2,
                              child: header == '單位'
                                  ? Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                        horizontal: 16,
                                      ),
                                      child: Text(
                                        record[header]?.toString() ?? '-',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w500,
                                          color: Colors.black87,
                                          fontSize: 13,
                                        ),
                                      ),
                                    )
                                  : Center(
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

  ///3, 构建表格数据（合并所有楼座数据）
  List<Map<String, dynamic>> _buildTableData(ArrearProvider provider) {
    final List<Map<String, dynamic>> tableData = [];

    // 从其他分摊费用数据构建表格数据
    if (provider.otherFeeData != null) {
      for (final block in provider.otherFeeData!.blocks) {
        for (final floor in block.floors) {
          for (final unit in floor.units) {
            for (final bill in unit.bills) {
              final Map<String, dynamic> rowData = {
                '單位': _formatUnitDisplay(block.name, floor.name, unit.name),
                '費用': bill.value,
                '類型': bill.itemId ?? '其他費用',
                '費用明細': bill.remark ?? '-',
                '日期': bill.period,
              };

              tableData.add(rowData);
            }
          }
        }
      }
    }

    return tableData;
  }

  ///3.1, 格式化单位显示（楼座+楼层+单元）
  String _formatUnitDisplay(
      String blockName, String floorName, String unitName) {
    if (blockName.isEmpty) {
      // 如果楼座名称为空，只显示楼层+单元
      return '${floorName}${unitName}';
    } else {
      // 显示楼座+楼层+单元，例如：01座01A
      return '${blockName}座${floorName}${unitName}';
    }
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

    // 固定顺序的表头，包括单位列
    return ['單位', '費用', '類型', '費用明細', '日期'];
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

    int actualItemsPerPage = _itemsPerPage;

    if (_itemsPerPage == 20) {
      final double screenHeight = MediaQuery.of(context).size.height;
      final double mainAreaHeight = screenHeight * 14 / 24;
      const double outerPadding = 16 * 2;
      const double titleHeight = 56;
      const double paginationHeight = 56;
      const double rowHeight = 40;
      const double headerHeight = 44;
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              minimumSize: const Size(70, 26),
            ),
            child: const Text('上一頁', style: TextStyle(fontSize: 17)),
          ),

          const SizedBox(width: 16),

          // 页码显示
          Text(
            '第 $_currentPage 頁，共 $totalPages 頁',
            style: const TextStyle(
              fontSize: 17,
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              minimumSize: const Size(70, 26),
            ),
            child: const Text('下一頁', style: TextStyle(fontSize: 17)),
          ),
        ],
      ),
    );
  }

  ///11, 启动自动翻页
  void _startAutoPagination() {
    if (!widget.isInCarouselMode) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<ArrearProvider>(context, listen: false);
      final tableData = _buildTableData(provider);

      final screenHeight = MediaQuery.of(context).size.height;
      final double mainAreaHeight = screenHeight * 14 / 24;
      const double outerPadding = 16 * 2;
      const double titleHeight = 56;
      const double paginationHeight = 56;
      const double rowHeight = 40;
      const double headerHeight = 44;
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
        Future.delayed(const Duration(seconds: 5), () {
          if (widget.onPaginationComplete != null) {
            widget.onPaginationComplete!(_totalPages);
          }
        });
        return;
      }

      if (widget.onPaginationStart != null) {
        widget.onPaginationStart!(_totalPages);
      }

      _startActualAutoPagination();
    });
  }

  ///12, 启动实际的自动翻页逻辑
  void _startActualAutoPagination() {
    final appDataProvider =
        Provider.of<AppDataProvider>(context, listen: false);
    final deviceSettings = appDataProvider.deviceSettings;
    //paymentTableOnePageDuration 乘以 10
    final paginationDuration =
        (deviceSettings?.paymentTableOnePageDuration ?? 3) * 5;

    _autoPaginationTimer?.cancel();
    _autoPaginationTimer =
        Timer.periodic(Duration(seconds: paginationDuration), (timer) {
      if (_isPaginationPaused) return;

      if (_currentPage < _totalPages) {
        setState(() {
          _currentPage++;
        });
      } else {
        if (_isWaitingForDataUpdate) {
          _isWaitingForDataUpdate = false;
          // 回調前重置為第一頁，便於下次顯示從頭開始
          setState(() {
            _currentPage = 1;
          });
          if (widget.onPaginationComplete != null) {
            widget.onPaginationComplete!(_totalPages);
          }
        } else {
          // 没有新数据时，直接回调 onPaginationComplete，让父组件切换下一表
          // 同時將頁碼重置為第一頁以便返回時從開頭顯示
          setState(() {
            _currentPage = 1;
          });
          if (widget.onPaginationComplete != null) {
            widget.onPaginationComplete!(_totalPages);
          }
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
              '暫無其他費用數據',
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
    _stopAutoPagination();
    super.dispose();
  }
}
