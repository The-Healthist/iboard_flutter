import 'package:flutter/material.dart';
import 'package:iboard_app/models/announcement_model.dart';
import 'package:iboard_app/providers/announcement_provider.dart';
import 'package:iboard_app/providers/arrear_provider.dart';
import 'package:provider/provider.dart';

class MainScreenWidget extends StatefulWidget {
  final Function(AnnouncementModel? announcement)?
      onAnnouncementTap; // 修改回调函数支持null
  final VoidCallback? onArrearTableTap; // 添加欠费总览回调

  const MainScreenWidget({
    Key? key,
    this.onAnnouncementTap,
    this.onArrearTableTap,
  }) : super(key: key);

  @override
  MainScreenWidgetState createState() => MainScreenWidgetState();
}

class MainScreenWidgetState extends State<MainScreenWidget> {
  // Set default to all
  AnnouncementTypeUi _selectedAnnouncementType = AnnouncementTypeUi.all;
  // 当前选中的楼层与单位
  String? _selectedBuilding;
  String? _selectedFloor;
  // 是否显示查询结果
  bool _showArrearResults = false;
  // 当前功能选项: 通告列表、欠費查詢、電子繳費等
  String _selectedFunction = '通告列表';

  ///1, 構建功能按鈕
  Widget _buildFunctionButton(
      String chineseTitle, String englishTitle, IconData icon) {
    bool isSelected = _selectedFunction == chineseTitle;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0), // 移除按鈕間隙
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              setState(() {
                _selectedFunction = chineseTitle;
              });

              // 处理功能按钮点击
              if (chineseTitle == '欠費查詢') {
                print('🔵 [MainScreenWidget] 用户点击欠费查询按钮 - 在右侧显示');
                // 不再调用回调函数，直接在右侧显示欠费查询内容
                // widget.onAnnouncementTap?.call(null); // 注释掉原有逻辑
                print('🔵 [MainScreenWidget] 右侧显示欠费查询内容');
              }
              // 添加繳費表單功能
              // else if (chineseTitle == '繳費表單') {
              //   print('🔵 [MainScreenWidget] 用户点击繳費表單按钮 - 在右侧显示');
              //   // 缴费表单现在显示全部数据，不需要选择器，所以不需要重置状态
              //   print('🔵 [MainScreenWidget] 右侧显示缴费表单内容');
              // }
              // 註釋掉繳費表單功能
              // else if (chineseTitle == '繳費表單') {
              //   print('🔵 [MainScreenWidget] 用户点击繳費表單按钮');
              //   // 导航到繳費表單页面
              //   widget.onArrearTableTap?.call();
              //   print('🔵 [MainScreenWidget] 已调用 onArrearTableTap()');
              // }
              else {
                print('$chineseTitle pressed');
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
              padding: const EdgeInsets.all(16.0),
              minimumSize: const Size(double.infinity, 0),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 32),
                const SizedBox(height: 8),
                Text(
                  chineseTitle,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  englishTitle,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.normal,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
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
          return ChoiceChip(
            label: Text(_getAnnouncementTypeText(type)),
            selected: _selectedAnnouncementType == type,
            onSelected: (selected) {
              if (selected) {
                setState(() {
                  _selectedAnnouncementType = type;
                  // Filtering will be applied by the ListView builder
                  print('Selected type: $type');
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
      default:
        return ''; // Should not happen
    }
  }

  ///3, 構建電子繳費頁面
  Widget _buildElectronicPaymentPage() {
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
                  'assets/images/payment.png',
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
                            Icons.payment,
                            size: 64,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 16),
                          Text(
                            '電子繳費功能',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.black87,
                              fontWeight: FontWeight.w500,
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
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // 樓層選擇器
          _buildArrearBuildingSelector(provider),

          const SizedBox(height: 10),

          // 單位選擇器
          _buildArrearFloorSelector(provider),
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
            alignment: WrapAlignment.start, // 確保左對齊
            spacing: 8,
            runSpacing: 8,
            children: buildings.map((building) {
              final isSelected = _selectedBuilding == building;
              // 检查该楼层是否有其他分摊费用
              final hasOtherFees = provider.hasOtherFeesForFloor(building);
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedBuilding = building;
                    _selectedFloor = null; // 重置單位選擇
                    _showArrearResults = false; // 重置查詢結果
                    // 设置楼层（不是buildingId）
                    provider.setSelectedFloor(building);
                    print('🔍 [MainScreenWidget] 选择楼层: "$building"');
                  });
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Theme.of(context).primaryColor
                        : hasOtherFees
                            ? Colors.purple.shade100 // 有其他分摊费用的楼层使用淡紫色背景
                            : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? Theme.of(context).primaryColor
                          : hasOtherFees
                              ? Colors.purple.shade300 // 有其他分摊费用的楼层使用淡紫色边框
                              : Colors.grey.shade300,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    '$building',
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
      ),
    );
  }

  ///8, 構建單位選擇器
  Widget _buildArrearFloorSelector(ArrearProvider provider) {
    final floors = _selectedBuilding != null
        ? provider.getFloors(_selectedBuilding!) // 使用getFloors获取所有单位
        : [];

    return SizedBox(
      width: double.infinity, // 固定寬度
      child: Column(
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
          // 如果没有单位数据，显示相应提示
          if (floors.isEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Center(
                child: Text(
                  '暫無單位數據',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ] else ...[
            Wrap(
              alignment: WrapAlignment.start, // 確保左對齊與樓層選擇器一致
              spacing: 8,
              runSpacing: 8,
              children: floors.map((floor) {
                final isSelected = _selectedFloor == floor;
                // 检查该单位是否有其他分摊费用（根据费用类型决定是否显示淡紫色）
                final hasOtherFees =
                    provider.hasOtherFees(_selectedBuilding!, floor);

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedFloor = floor;
                      _showArrearResults = false; // 重置查詢結果
                      // 设置单位
                      provider.setSelectedUnit(floor);
                      print('🔍 [MainScreenWidget] 选择单位: "$floor"');
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Theme.of(context).primaryColor
                          : hasOtherFees
                              ? Colors.purple.shade100
                              : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected
                            ? Theme.of(context).primaryColor
                            : hasOtherFees
                                ? Colors.purple.shade300
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
        ],
      ),
    );
  }

  ///9, 構建查詢按鈕
  Widget _buildArrearQueryButton(ArrearProvider provider) {
    // 判斷當前是否可以查詢，同時檢查選中的單元是否屬於該樓層
    final floors = _selectedBuilding != null
        ? provider.getFloors(_selectedBuilding!)
        : <String>[];
    final bool hasValidSelection = _selectedBuilding != null &&
        _selectedFloor != null &&
        floors.contains(_selectedFloor);
    final bool canQuery =
        hasValidSelection && _hasDataForSelectedFeeType(provider);

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () {
          if (canQuery) {
            _handleArrearQuery();
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor:
              canQuery ? Theme.of(context).primaryColor : Colors.grey.shade100,
          foregroundColor: canQuery ? Colors.white : Colors.black87,
          padding: const EdgeInsets.symmetric(vertical: 8), // 保持原有 padding
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: canQuery ? 2 : 0,
        ),
        child: Column(
          children: [
            Text(
              // 無效選擇時強制提示先選擇樓層和單元
              (!hasValidSelection)
                  ? '請先選擇樓層和單位'
                  : _getQueryButtonText(provider),
              style: const TextStyle(
                fontSize: 14, // 保持原有文字大小
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              // 根據狀態顯示不同的英文提示
              (!hasValidSelection)
                  ? 'Please Select Floor and Unit'
                  : 'Query Payment Records',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  ///9.1, 检查选中的费用类型是否有数据
  bool _hasDataForSelectedFeeType(ArrearProvider provider) {
    if (provider.selectedFeeType == FeeType.management) {
      return provider.hasManagementFeeData;
    } else {
      return provider.hasOtherFeeData && !provider.isOtherFeeDataEmpty;
    }
  }

  ///9.2, 获取查询按钮文本
  String _getQueryButtonText(ArrearProvider provider) {
    if (_selectedBuilding == null || _selectedFloor == null) {
      return '請選擇樓層和單位';
    }

    if (provider.selectedFeeType == FeeType.management) {
      if (!provider.hasManagementFeeData) {
        return '暫無管理費用數據';
      }
    } else {
      if (!provider.hasOtherFeeData) {
        return '暫無其他費用數據';
      }
      if (provider.isOtherFeeDataEmpty) {
        return '無其他費用記錄';
      }
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

    // 根据费用类型检查是否有数据
    final hasData = provider.selectedFeeType == FeeType.management
        ? provider.hasManagementFeeData
        : (provider.hasOtherFeeData && !provider.isOtherFeeDataEmpty);

    if (hasData) {
      return _buildArrearDataContent(provider);
    }

    return Container(
      padding: const EdgeInsets.all(0),
      decoration: BoxDecoration(
        // color: Colors.white,
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
          ],
        ),
      ),
    );
  }

  ///13, 構建數據內容
  Widget _buildArrearDataContent(ArrearProvider provider) {
    final feeTypeText =
        provider.selectedFeeType == FeeType.management ? '管理費用' : '其他費用';

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
                '查詢結果 - ${_selectedBuilding}${_selectedFloor}單位 ($feeTypeText)',
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
                color: Colors.grey.shade50, // 使用浅灰色背景替代图片
              ),
              child: const Center(
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
                    const SizedBox(height: 4),
                    Text(
                      'Convenient Services',
                      style: TextStyle(
                        fontSize: 12,
                        color: const Color(0xFF757575),
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '該大廈尚未開通此功能',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                  ],
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
    return Container(
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
    final hasOtherFeeData =
        provider.hasOtherFeeData && !provider.isOtherFeeDataEmpty;

    return ElevatedButton(
      onPressed: () {
        provider.setFeeType(feeType);
        // 重置查询结果
        setState(() {
          _showArrearResults = false;
        });
        print('🔍 [MainScreenWidget] 选择费用类型: $chineseTitle');
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected
            ? Theme.of(context).primaryColor
            : isOtherFee && !hasOtherFeeData
                ? Colors.grey.shade300
                : Colors.grey.shade100,
        foregroundColor: isSelected
            ? Colors.white
            : isOtherFee && !hasOtherFeeData
                ? Colors.grey.shade500
                : Colors.black87,
        padding: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        elevation: isSelected ? 2 : 0,
      ),
      child: Column(
        children: [
          Text(
            chineseTitle,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            englishTitle,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.normal,
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
                final isNetworkError = error.contains('网络连接失败') ||
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
                        child: Text('沒有任何通告.')) // Updated for all types
                    : ListView.builder(
                        itemCount: filteredAnnouncements.length,
                        itemBuilder: (context, index) {
                          final announcement = filteredAnnouncements[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4.0),
                            child: ListTile(
                              title: Text(announcement.title),
                              subtitle: Text(
                                  '${_getAnnouncementTypeText(announcement.uiType)} - ${announcement.description}'),
                              onTap: () {
                                print(
                                    '📰 [MainScreenWidget] 用户点击通告: ${announcement.title} (类型: ${announcement.uiType})');
                                // 调用回调函数传递announcement对象
                                widget.onAnnouncementTap?.call(announcement);
                                print(
                                    '📰 [MainScreenWidget] 已调用 onAnnouncementTap(${announcement.title})');
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

        return Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                // Left Side: Function Selection
                Expanded(
                  flex: 2,
                  child: Container(
                    padding: const EdgeInsets.all(16.0),
                    color: Colors.white,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
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
          ),
        );
      },
    );
  }
}
