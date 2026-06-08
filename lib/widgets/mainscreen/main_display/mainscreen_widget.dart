import 'package:flutter/material.dart';
import 'package:iboard_app/models/announcement_model.dart';
import 'package:iboard_app/providers/announcement_provider.dart';
import 'package:iboard_app/providers/arrear_provider.dart';
import 'package:iboard_app/providers/state_provider.dart';
import 'package:iboard_app/widgets/mainscreen/main_display/payment_widget.dart';
import 'package:provider/provider.dart';
import 'package:logger/logger.dart';

class MainScreenWidget extends StatefulWidget {
  final Function(AnnouncementModel? announcement)?
      onAnnouncementTap; // 修改回调函数支持null
  final VoidCallback? onArrearTableTap; // 添加欠费总览回调

  const MainScreenWidget({
    super.key,
    this.onAnnouncementTap,
    this.onArrearTableTap,
  });

  @override
  MainScreenWidgetState createState() => MainScreenWidgetState();
}

class MainScreenWidgetState extends State<MainScreenWidget> {
  final Logger _logger = Logger();
  // Set default to all
  AnnouncementTypeUi _selectedAnnouncementType = AnnouncementTypeUi.all;
  // 当前选中的樓座、樓层与單位
  String? _selectedBlock;
  String? _selectedBuilding;
  String? _selectedFloor;
  // 是否显示查询结果
  bool _showArrearResults = false;
  // 当前功能选项: 通告列表、欠費查詢、電子繳費等
  String _selectedFunction = '通告列表';

  @override
  void initState() {
    super.initState();
    // 确保数据已加载 - 使用与欠费查询相同的数据源
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<ArrearProvider>(context, listen: false);

      if (!provider.hasData) {
        provider.loadFromCache();
      }

      // 同步Provider的樓座选择状态
      if (provider.selectedBlock != null) {
        _selectedBlock = provider.selectedBlock;
      }
      if (provider.selectedFloor != null) {
        _selectedBuilding = provider.selectedFloor;
      }
      if (provider.selectedUnit != null) {
        _selectedFloor = provider.selectedUnit;
      }
    });
  }

  @override
  void dispose() {
    // 33, 清理時確保恢復輪播狀態
    try {
      final carouselStateProvider = context.read<CarouselStateProvider>();
      if (carouselStateProvider.currentAppState == AppState.manualOperation) {
        carouselStateProvider.enterDefaultState();
      }
    } catch (_) {}
    super.dispose();
  }

  ///1, 構建功能按鈕
  Widget _buildFunctionButton(
      String chineseTitle, String englishTitle, IconData icon) {
    bool isSelected = _selectedFunction == chineseTitle;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final buttonHeight =
                constraints.maxHeight.isFinite ? constraints.maxHeight : 96.0;
            final isCompact = buttonHeight < 92;
            final isVeryCompact = buttonHeight < 76;
            final iconSize = isVeryCompact
                ? 22.0
                : isCompact
                    ? 28.0
                    : 36.0;
            final titleFontSize = isVeryCompact
                ? 17.0
                : isCompact
                    ? 20.0
                    : 24.0;
            final subtitleFontSize = isVeryCompact
                ? 12.0
                : isCompact
                    ? 14.0
                    : 16.0;
            final verticalPadding = isVeryCompact
                ? 4.0
                : isCompact
                    ? 8.0
                    : 12.0;
            final titleGap = isVeryCompact ? 3.0 : 6.0;
            final subtitleGap = isVeryCompact ? 1.0 : 3.0;

            return SizedBox.expand(
              child: ElevatedButton(
                onPressed: () {
                  setState(() {
                    _selectedFunction = chineseTitle;
                  });

                  // 29, 處理功能按鈕點擊，電子繳費需要暫停輪播
                  if (chineseTitle == '電子繳費') {
                    _logger
                        .i(' [MainScreenWidget] 用戶點擊電子繳費按鈕 - 進入手動操作狀態（禁用超時）');
                    final carouselStateProvider =
                        context.read<CarouselStateProvider>();
                    carouselStateProvider.enterManualOperation(
                        disableTimeout: true);
                  } else if (chineseTitle == '通告列表') {
                    // 30, 返回通告列表時恢復輪播
                    _logger.i(' [MainScreenWidget] 用戶點擊通告列表 - 恢復默認狀態');
                    final carouselStateProvider =
                        context.read<CarouselStateProvider>();
                    carouselStateProvider.enterDefaultState();
                  }
                  // 处理功能按钮点击
                  else if (chineseTitle == '欠費查詢') {
                    _logger.i(' [MainScreenWidget] 用戶點擊欠費查詢按鈕 - 在右側顯示');
                    // 不再调用回调函数，直接在右侧显示欠费查询内容
                    // widget.onAnnouncementTap?.call(null); // 注释掉原有逻辑
                    _logger.i(' [MainScreenWidget] 右側顯示欠費查詢內容');
                  } else {
                    _logger.i('$chineseTitle pressed');
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : null, // 使用默認背景色
                  foregroundColor: isSelected
                      ? Theme.of(context).colorScheme.onPrimary // 選中時使用對比色文字
                      : null, // 未選中時使用默認文字顏色
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                  padding: EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: verticalPadding,
                  ),
                  minimumSize: const Size(double.infinity, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: iconSize),
                      SizedBox(height: titleGap),
                      Text(
                        chineseTitle,
                        style: TextStyle(
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.w800,
                          height: 1.08,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: subtitleGap),
                      Text(
                        englishTitle,
                        style: TextStyle(
                          fontSize: subtitleFontSize,
                          fontWeight: FontWeight.w700,
                          height: 1.08,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildAnnouncementTypeSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 0.0),
      child: Wrap(
        spacing: 8.0,
        runSpacing: 4.0,
        // Use AnnouncementTypeUi.values
        children: AnnouncementTypeUi.values.map((type) {
          final isSelected = _selectedAnnouncementType == type;
          return ChoiceChip(
            label: Text(
              _getAnnouncementTypeText(type),
              style: TextStyle(
                fontSize: 18,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
              ),
            ),
            selected: isSelected,
            labelPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            onSelected: (selected) {
              if (selected) {
                setState(() {
                  _selectedAnnouncementType = type;
                  // Filtering will be applied by the ListView builder
                  _logger.i('Selected type: $type');
                });
              }
            },
          );
        }).toList(),
      ),
    );
  }

  ///2, 獲取通告類型文字
  String _getAnnouncementTypeText(AnnouncementTypeUi type) {
    switch (type) {
      case AnnouncementTypeUi.all:
        return '全部';
      case AnnouncementTypeUi.general:
        return '一般';
      case AnnouncementTypeUi.emergency:
        return '緊急';
      case AnnouncementTypeUi.government:
        return '政府';
      case AnnouncementTypeUi.corporation:
        return '法團';
    }
  }

  ///3, 構建電子繳費頁面
  Widget _buildElectronicPaymentPage() {
    return PaymentWidget(
      onIdleTimeout: () {
        // 28, 無操作超時，恢復輪播（自動切換到通告和繳費列表）
        debugPrint(' [MainScreenWidget] 電子繳費頁面無操作超時，恢復通告輪播');
        if (mounted) {
          final carouselStateProvider = context.read<CarouselStateProvider>();

          // 40, 使用專門的方法從手動操作狀態恢復到默認狀態
          // 這個方法會正確處理輪播恢復、全屏廣告計時器啟動等邏輯
          try {
            carouselStateProvider.exitManualOperationToDefault();
            debugPrint(' [MainScreenWidget] 已調用 exitManualOperationToDefault');
          } catch (e) {
            debugPrint(' [MainScreenWidget] 恢復通告輪播失敗: $e');
          }

          // 32, 重置本地選擇狀態
          setState(() {
            _selectedFunction = '通告列表';
          });
        }
      },
    );
  }

  ///4, 構建欠費查詢內容
  Widget _buildArrearQueryContent() {
    return Consumer<ArrearProvider>(
      builder: (context, arrearProvider, child) {
        return Container(
          padding: const EdgeInsets.fromLTRB(16.0, 20.0, 16.0, 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      // 選擇器容器
                      _buildArrearSelectorContainer(arrearProvider),
                      // 高度
                      const SizedBox(height: 16),

                      // 费用类型切换按钮
                      _buildFeeTypeSelector(arrearProvider),

                      const SizedBox(height: 16),

                      // 查詢按鈕
                      _buildArrearQueryButton(arrearProvider),

                      const SizedBox(height: 16),

                      // 查詢結果
                      if (_showArrearResults)
                        _buildArrearResultsContainer(arrearProvider),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  ///6, 構建欠費選擇器容器
  Widget _buildArrearSelectorContainer(ArrearProvider provider) {
    return Container(
      width: double.infinity, //占据全部的widget
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 360),
        child: SingleChildScrollView(
          child: Column(
            children: [
              // 樓座选择器（只有当有多个非空名称的樓座时才显示）
              if (provider.shouldShowBlockSelector) ...[
                _buildArrearBlockSelector(provider),
                const SizedBox(height: 14),
              ],

              // 樓層選擇器
              _buildArrearBuildingSelector(provider),

              const SizedBox(height: 14),

              // 單位選擇器
              _buildArrearFloorSelector(provider),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildArrearSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        height: 1.15,
        color: Colors.black87,
      ),
    );
  }

  Widget _buildArrearOptionChip({
    required String text,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final primaryColor = Theme.of(context).primaryColor;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          constraints: const BoxConstraints(
            minWidth: 66,
            minHeight: 50,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          decoration: BoxDecoration(
            color: isSelected ? primaryColor : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? primaryColor : Colors.grey.shade300,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              height: 1.1,
              color: isSelected ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildArrearEmptyHint(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Center(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 18,
            color: Colors.grey.shade700,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  ///6.1, 構建樓座選擇器
  Widget _buildArrearBlockSelector(ArrearProvider provider) {
    final blocks = provider.blocks;

    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildArrearSectionTitle('選擇座數'),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.start,
            spacing: 10,
            runSpacing: 10,
            children: blocks.map((block) {
              final isSelected = _selectedBlock == block;
              return _buildArrearOptionChip(
                text: '$block座',
                isSelected: isSelected,
                onTap: () {
                  setState(() {
                    _selectedBlock = block;
                    _selectedBuilding = null; // 重置樓層選擇
                    _selectedFloor = null; // 重置單位選擇
                    _showArrearResults = false; // 重置查詢結果
                    // 设置樓座
                    provider.setSelectedBlock(block);
                  });
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  ///7, 構建樓層選擇器
  Widget _buildArrearBuildingSelector(ArrearProvider provider) {
    final buildings = provider.buildings;

    return SizedBox(
      width: double.infinity, // 固定寬度
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildArrearSectionTitle('選擇樓層'),
          const SizedBox(height: 12),
          // 如果没有樓层数据，显示相应提示
          if (buildings.isEmpty) ...[
            _buildArrearEmptyHint(
              provider.blocks.length > 1 ? '請先選擇樓座' : '暫無樓層數據',
            ),
          ] else ...[
            Wrap(
              alignment: WrapAlignment.start, // 確保左對齊
              spacing: 10,
              runSpacing: 10,
              children: buildings.map((building) {
                final isSelected = _selectedBuilding == building;
                return _buildArrearOptionChip(
                  text: building,
                  isSelected: isSelected,
                  onTap: () {
                    setState(() {
                      _selectedBuilding = building;
                      _selectedFloor = null; // 重置單位選擇
                      _showArrearResults = false; // 重置查詢結果
                      // 设置樓层（不是buildingId）
                      provider.setSelectedFloor(building);
                    });
                  },
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  ///8, 構建單位選擇器
  Widget _buildArrearFloorSelector(ArrearProvider provider) {
    final floors = _selectedBuilding != null
        ? provider.getFloors(_selectedBuilding!) // 使用getFloors获取所有單位
        : [];

    return SizedBox(
      width: double.infinity, // 固定寬度
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildArrearSectionTitle('選擇單位'),
          const SizedBox(height: 12),
          // 如果没有單位数据，显示相应提示
          if (floors.isEmpty) ...[
            _buildArrearEmptyHint('請先選擇樓層'),
          ] else ...[
            Wrap(
              alignment: WrapAlignment.start, // 確保左對齊與樓層選擇器一致
              spacing: 10,
              runSpacing: 10,
              children: floors.map((floor) {
                final isSelected = _selectedFloor == floor;
                // 检查该單位是否有其他分摊费用（根据费用类型决定是否显示淡紫色）
                // final hasOtherFees =
                //     provider.hasOtherFees(_selectedBuilding!, floor);

                return _buildArrearOptionChip(
                  text: floor,
                  isSelected: isSelected,
                  onTap: () {
                    setState(() {
                      _selectedFloor = floor;
                      _showArrearResults = false; // 重置查詢結果
                      // 设置單位
                      provider.setSelectedUnit(floor);
                      _logger.i(' [MainScreenWidget] 選擇單位: "$floor"');
                    });
                  },
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  ///9, 構建查詢按鈕
  Widget _buildArrearQueryButton(ArrearProvider provider) {
    // 判斷當前是否可以查詢
    final bool hasValidSelection = _hasValidArrearSelection(provider);
    final bool hasDataForSelection =
        hasValidSelection && provider.hasDataForCurrentSelection;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () {
          if (hasDataForSelection) {
            _handleArrearQuery();
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: hasDataForSelection
              ? Theme.of(context).primaryColor
              : Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
          foregroundColor: hasDataForSelection ? Colors.white : Colors.black87,
          padding: const EdgeInsets.symmetric(vertical: 7),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: hasDataForSelection ? 2 : 0,
        ),
        child: Column(
          children: [
            Text(
              // 無效選擇時強制提示先選擇樓層和單元
              (!hasValidSelection)
                  ? _getInvalidSelectionText(provider)
                  : _getQueryButtonText(provider),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                height: 1.05,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              // 根據狀態顯示不同的英文提示
              (!hasValidSelection)
                  ? _getInvalidSelectionEnglishText(provider)
                  : 'Query Payment Records',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1.05,
              ),
            ),
          ],
        ),
      ),
    );
  }

  ///9.0, 检查欠费查询选择是否有效
  bool _hasValidArrearSelection(ArrearProvider provider) {
    // 如果有多个樓座，必须选择樓座
    if (provider.blocks.length > 1 && _selectedBlock == null) {
      return false;
    }

    // 必须选择樓层和單位
    return _selectedBuilding != null && _selectedFloor != null;
  }

  ///9.1, 获取无效选择的提示文本
  String _getInvalidSelectionText(ArrearProvider provider) {
    if (provider.blocks.length > 1 && _selectedBlock == null) {
      return '請先選擇樓座';
    }
    if (_selectedBuilding == null) {
      return '請先選擇樓層';
    }
    if (_selectedFloor == null) {
      return '請先選擇單位';
    }
    return '請先選擇樓層和單位';
  }

  ///9.2, 获取无效选择的英文提示文本
  String _getInvalidSelectionEnglishText(ArrearProvider provider) {
    if (provider.blocks.length > 1 && _selectedBlock == null) {
      return 'Please Select Block';
    }
    if (_selectedBuilding == null) {
      return 'Please Select Floor';
    }
    if (_selectedFloor == null) {
      return 'Please Select Unit';
    }
    return 'Please Select Floor and Unit';
  }

  ///9.2, 获取查询按钮文本
  String _getQueryButtonText(ArrearProvider provider) {
    if (_selectedBuilding == null || _selectedFloor == null) {
      return '請選擇樓層和單位';
    }
    // 針對當前選擇
    if (!provider.hasDataForCurrentSelection) {
      return provider.selectedFeeType == FeeType.management
          ? '暫無管理費用數據'
          : '暫無其他費用數據';
    }

    return '查詢繳費記錄';
  }

  ///10, 處理查詢
  void _handleArrearQuery() {
    if (_selectedBuilding != null && _selectedFloor != null) {
      setState(() {
        _showArrearResults = true;
      });
    }
  }

  ///11, 構建查詢結果容器
  Widget _buildArrearResultsContainer(ArrearProvider provider) {
    // 若當前選擇沒有數據，直接不顯示結果容器
    if (!provider.hasDataForCurrentSelection) {
      return const SizedBox.shrink();
    }
    if (provider.isLoading) {
      return Container(
        padding: const EdgeInsets.all(0),
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (provider.error != null && provider.error!.isNotEmpty) {
      return _buildArrearErrorContainer(provider.error!);
    }

    // 當前選擇有數據
    if (provider.hasDataForCurrentSelection) {
      return _buildArrearDataContent(provider);
    }

    return Container(
      padding: const EdgeInsets.all(0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Column(
          children: [
            Icon(
                provider.selectedFeeType == FeeType.management
                    ? Icons.receipt_long
                    : Icons.account_balance_wallet,
                color: Colors.grey,
                size: 60),
            const SizedBox(height: 16),
            Text(
              provider.selectedFeeType == FeeType.management
                  ? '暫無管理費用數據'
                  : '無其他費用記錄',
              style: const TextStyle(
                fontSize: 18,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              provider.selectedFeeType == FeeType.management
                  ? '請稍後再試或聯繫管理員'
                  : '該單位暫無其他分攤費用',
              style: const TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  ///12, 構建錯誤容器
  Widget _buildArrearErrorContainer(String errorMessage) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(0),
      decoration: BoxDecoration(
        // color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
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
          ],
        ),
      ),
    );
  }

  ///13, 構建數據內容
  Widget _buildArrearDataContent(ArrearProvider provider) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        // color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // 結果標題
          Row(
            children: [
              Icon(
                  provider.selectedFeeType == FeeType.management
                      ? Icons.receipt_long
                      : Icons.account_balance_wallet,
                  color: provider.selectedFeeType == FeeType.management
                      ? Colors.blue
                      : Colors.purple,
                  size: 24),
              const SizedBox(width: 8),
              Text(
                '  ${provider.currentUnitDisplayName ?? '未知單位'}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 欠費記錄列表
          _buildArrearList(provider),
        ],
      ),
    );
  }

  ///14, 構建欠費記錄列表
  Widget _buildArrearList(ArrearProvider provider) {
    // 如果是其他费用类型，使用详细显示
    if (provider.selectedFeeType == FeeType.other) {
      return _buildDetailedArrearList(provider);
    }

    // 管理费用使用原有简單显示
    final currentArrearage = provider.currentArrearage;

    if (currentArrearage == null) {
      return const Center(
        child: Text('暫無數據'),
      );
    }

    final entries = currentArrearage.entries.toList();

    return Column(
      children: entries.map((entry) {
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
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
                        color: _getArrearStatusColor(entry.value),
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

  ///14.1, 構建其他費用詳細記錄列表（簡潔左右兩列顯示）
  Widget _buildDetailedArrearList(ArrearProvider provider) {
    final detailedArrearage = provider.currentDetailedArrearage;

    if (detailedArrearage == null || detailedArrearage.isEmpty) {
      return const Center(
        child: Text('暫無數據'),
      );
    }

    return Column(
      children: detailedArrearage.map((bill) {
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              // 左側兩條信息
              Expanded(
                flex: 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 期間
                    Text(
                      bill.period,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // 項目
                    Text(
                      bill.itemId ?? '分攤費用',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 16),

              // 右側兩條信息
              Expanded(
                flex: 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // 金額
                    Text(
                      bill.value.toString(),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _getArrearStatusColor(bill.value),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // 備註
                    Text(
                      bill.remark ?? '-',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                      textAlign: TextAlign.end,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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

  ///15, 獲取狀態顏色
  Color _getArrearStatusColor(dynamic value) {
    if (value is String && value == '已付') {
      return Colors.green;
    }
    if (value is num && value < 0) {
      return Colors.red;
    }
    return Colors.black87;
  }

  ///16, 構建便利服務頁面
  Widget _buildConvenientServicesPage() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16.0, 20.0, 16.0, 20.0), // 移除上下內邊距
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
                color: Colors.white, // 改为白色背景，让图片更清晰
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8), // 保持圆角
                child: Image.asset(
                  'assets/images/convenient_services.png',
                  width: double.infinity, // 宽度填满容器
                  height: double.infinity, // 高度填满容器
                  fit: BoxFit.cover, // 填满容器，不保持比例
                  errorBuilder: (context, error, stackTrace) {
                    // 如果图片加载失败，显示备用内容
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.store,
                            size: 64,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 16),
                          Text(
                            '便利服務',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.black87,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Convenient Services',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF757575),
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            '該大廈尚未開通此功能',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  ///27, 構建費用類型選擇器
  Widget _buildFeeTypeSelector(ArrearProvider provider) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '選擇費用類型',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildFeeTypeButton(
                  provider,
                  '管理費用',
                  'Management Fee',
                  FeeType.management,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildFeeTypeButton(
                  provider,
                  '其他費用',
                  'Other Fee',
                  FeeType.other,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  ///28, 構建費用類型按鈕
  Widget _buildFeeTypeButton(
    ArrearProvider provider,
    String chineseTitle,
    String englishTitle,
    FeeType feeType,
  ) {
    final isSelected = provider.selectedFeeType == feeType;
    final isOtherFee = feeType == FeeType.other;

    // 檢查該費用類型是否有數據
    final hasData = isOtherFee
        ? (provider.hasOtherFeeData && !provider.isOtherFeeDataEmpty)
        : provider.hasManagementFeeData;

    return ElevatedButton(
      onPressed: () {
        provider.setFeeType(feeType);
        // 重置查询结果
        setState(() {
          _showArrearResults = false;
        });
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected
            ? Theme.of(context).primaryColor
            : !hasData
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
                : Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
        foregroundColor: isSelected
            ? Colors.white
            : !hasData
                ? Colors.black87
                : Colors.black87,
        padding: const EdgeInsets.symmetric(vertical: 5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        elevation: isSelected ? 2 : 0,
      ),
      child: Column(
        children: [
          Text(
            chineseTitle,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            englishTitle,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.05,
            ),
          ),
        ],
      ),
    );
  }

  //     children: entries.map((entry) {
  //       return Container(
  //         margin: const EdgeInsets.only(bottom: 10),
  //         padding: const EdgeInsets.all(12),
  //         decoration: BoxDecoration(
  //           color: Colors.grey.shade50,
  //           borderRadius: BorderRadius.circular(8),
  //           border: Border.all(color: Colors.grey.shade200),
  //         ),
  //         child: Row(
  //           children: [
  //             Expanded(
  //               child: Column(
  //                 crossAxisAlignment: CrossAxisAlignment.start,
  //                 children: [
  //                   Text(
  //                     entry.key,
  //                     style: TextStyle(
  //                       fontSize: 16,
  //                       fontWeight: FontWeight.w500,
  //                       color: Colors.black87,
  //                     ),
  //                   ),
  //                   const SizedBox(height: 8),
  //                   Text(
  //                     entry.value.toString(),
  //                     style: TextStyle(
  //                       fontSize: 18,
  //                       fontWeight: FontWeight.w600,
  //                       color: _getArrearStatusColor(entry.value),
  //                     ),
  //                   ),
  //                 ],
  //               ),
  //             ),
  //           ],
  //         ),
  //       );
  //     }).toList(),
  //   );
  // }

  ///5, 構建右側內容
  Widget _buildRightContent(AnnouncementProvider announcementProvider,
      List<AnnouncementModel> filteredAnnouncements) {
    switch (_selectedFunction) {
      case '通告列表':
        return _buildAnnouncementListContent(
            announcementProvider, filteredAnnouncements);
      case '欠費查詢':
        return _buildArrearQueryContent();

      case '電子繳費':
        return _buildElectronicPaymentPage();
      case '便利服務':
        return _buildConvenientServicesPage();
      default:
        return _buildAnnouncementListContent(
            announcementProvider, filteredAnnouncements);
    }
  }

  ///6, 構建通告列表內容
  Widget _buildAnnouncementListContent(
      AnnouncementProvider announcementProvider,
      List<AnnouncementModel> filteredAnnouncements) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16.0, 20, 16.0, 20.0), // 移除上下內邊距
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (announcementProvider.isLoading)
                const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.0)),
            ],
          ),
          _buildAnnouncementTypeSelector(),
          // 智能错误显示：网络错误且有缓存数据时不显示错误信息
          if (announcementProvider.error != null &&
              !announcementProvider.isLoading) ...[
            Builder(
              builder: (context) {
                // 检查是否是网络错误且有缓存数据
                final error = announcementProvider.error!;
                final hasCachedData =
                    announcementProvider.announcements.isNotEmpty;
                final isNetworkError = error.contains('网络連接失败') ||
                    error.contains('请求超时') ||
                    error.contains('使用缓存的');

                // 只有在非网络错误或没有缓存数据时才显示错误
                if (!isNetworkError || !hasCachedData) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                    child: Text(
                      'Error: $error',
                      style: const TextStyle(color: Colors.red),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ],
          Expanded(
            child: announcementProvider.isLoading &&
                    filteredAnnouncements.isEmpty
                ? const Center(
                    child: Text(
                        "讀取中...")) // Show loading text if initially loading and no data yet
                : filteredAnnouncements.isEmpty
                    ? const Center(
                        child: Text('没有任何通告.')) // Updated for all types
                    : ListView.builder(
                        itemCount: filteredAnnouncements.length,
                        itemBuilder: (context, index) {
                          final announcement = filteredAnnouncements[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4.0),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 18.0, vertical: 8.0),
                              title: Text(
                                announcement.title,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  height: 1.25,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${_getAnnouncementTypeText(announcement.uiType)} - ${announcement.description}',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade700,
                                  height: 1.25,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () {
                                _logger.i(
                                    ' [MainScreenWidget] 用戶點擊通告: ${announcement.title} (類型: ${announcement.uiType})');
                                // 调用回调函数传递announcement对象
                                widget.onAnnouncementTap?.call(announcement);
                                _logger.i(
                                    ' [MainScreenWidget] 已調用 onAnnouncementTap(${announcement.title})');
                              },
                            ),
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
    return Consumer<AnnouncementProvider>(
      builder: (context, announcementProvider, child) {
        // Filter announcements based on the selected UI type
        final List<AnnouncementModel> filteredAnnouncements;
        if (_selectedAnnouncementType == AnnouncementTypeUi.all) {
          filteredAnnouncements = announcementProvider.announcements;
        } else {
          filteredAnnouncements = announcementProvider.announcements
              .where((announcement) =>
                  announcement.uiType == _selectedAnnouncementType)
              .toList();
        }

        return ColoredBox(
          color: Colors.grey.shade50,
          child: Row(
            children: [
              // Left Side: Function Selection
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.all(12.0),
                  color: Colors.white,
                  child: Column(
                    children: [
                      _buildFunctionButton(
                          '通告列表', 'Announcement List', Icons.list_alt),
                      _buildFunctionButton(
                          '欠費查詢', 'Payment Query', Icons.search),
                      // _buildFunctionButton(
                      //     '繳費表單', 'Payment Form', Icons.table_chart),
                      _buildFunctionButton(
                          '電子繳費', 'Electronic Payment', Icons.payment),
                      _buildFunctionButton(
                          '便利服務', 'Convenient Services', Icons.store),
                    ],
                  ),
                ),
              ),
              // Right Side: Dynamic Content
              Expanded(
                flex: 5,
                child: _buildRightContent(
                    announcementProvider, filteredAnnouncements),
              ),
            ],
          ),
        );
      },
    );
  }
}
