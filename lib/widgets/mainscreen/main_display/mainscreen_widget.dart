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

  // 當前選中的功能
  String _selectedFunction = '通告列表'; // 默認選中通告列表

  // 欠費查詢相關狀態
  String? _selectedBuilding; // 实际存储的是楼层，如"G楼"
  String? _selectedFloor; // 实际存储的是单位，如"01"
  bool _showArrearResults = false;

  // 繳費表單相關狀態
  String? _selectedTableBuilding; // 实际存储的是楼层，如"G楼"
  String? _selectedTableFloor; // 实际存储的是单位，如"01"
  bool _showTableResults = false;

  @override
  void initState() {
    super.initState();
    // Fetch notices when the widget is initialized
    // Use WidgetsBinding.instance.addPostFrameCallback to ensure Provider is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Check if the widget is still mounted before accessing the provider
      if (mounted) {
        Provider.of<AnnouncementProvider>(context, listen: false)
            .fetchNotices();
      }
    });
  }

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
                color: Colors.grey.shade50, // 使用浅灰色背景替代图片
              ),
              child: const Center(
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
                      '功能開發中...',
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
    final floors =
        _selectedBuilding != null ? provider.getFloors(_selectedBuilding!) : [];

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
          Wrap(
            alignment: WrapAlignment.start, // 確保左對齊與樓層選擇器一致
            spacing: 8,
            runSpacing: 8,
            children: floors.map((floor) {
              final isSelected = _selectedFloor == floor;
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
      ),
    );
  }

  ///9, 構建查詢按鈕
  Widget _buildArrearQueryButton(ArrearProvider provider) {
    final canQuery = _selectedBuilding != null && _selectedFloor != null;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: canQuery ? _handleArrearQuery : null,
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

    final arrears = provider.arrears;
    final hasData = arrears.isNotEmpty || provider.rawArrearData.isNotEmpty;

    if (hasData) {
      return _buildArrearDataContent(provider);
    }

    return Container(
      padding: const EdgeInsets.all(0),
      decoration: BoxDecoration(
        // color: Colors.white,
        borderRadius: BorderRadius.circular(12),
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
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        // color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // 結果標題
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
                    SizedBox(height: 8),
                    Text(
                      '功能開發中...',
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

  // ///17, 構建繳費表單內容
  // Widget _buildPaymentFormContent() {
  //   return Consumer<ArrearProvider>(
  //     builder: (context, arrearProvider, child) {
  //       return Container(
  //         padding: const EdgeInsets.fromLTRB(16.0, 20.0, 16.0, 20.0),
  //         child: Column(
  //           crossAxisAlignment: CrossAxisAlignment.start,
  //           children: [
  //             Expanded(
  //               child: SingleChildScrollView(
  //                 child: Column(
  //                   children: [
  //                     // 選擇器容器
  //                     _buildPaymentFormSelectorContainer(arrearProvider),
  //                     // 高度
  //                     const SizedBox(height: 16),

  //                     // 直接顯示繳費表單表格
  //                     _buildPaymentFormTable(arrearProvider),
  //                   ],
  //                 ),
  //               ),
  //             ),
  //           ],
  //         ),
  //       );
  //     },
  //   );
  // }

  // ///18, 構建繳費表單選擇器容器
  // Widget _buildPaymentFormSelectorContainer(ArrearProvider provider) {
  //   return Container(
  //     width: double.infinity,
  //     padding: const EdgeInsets.all(10),
  //     decoration: BoxDecoration(
  //       borderRadius: BorderRadius.circular(12),
  //     ),
  //     child: Column(
  //       children: [
  //         // 顯示全部數據的說明
  //         Container(
  //           width: double.infinity,
  //           padding: const EdgeInsets.all(16),
  //           decoration: BoxDecoration(
  //             color: Colors.blue.shade50,
  //             borderRadius: BorderRadius.circular(8),
  //             border: Border.all(color: Colors.blue.shade200),
  //           ),
  //           child: Row(
  //             children: [
  //               Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
  //               const SizedBox(width: 8),
  //               Expanded(
  //                 child: Text(
  //                   '繳費表單顯示所有單位的欠費數據，無需選擇特定樓層和單位',
  //                   style: TextStyle(
  //                     fontSize: 14,
  //                     color: Colors.blue.shade700,
  //                     fontWeight: FontWeight.w500,
  //                   ),
  //                 ),
  //               ),
  //             ],
  //           ),
  //         ),
  //       ],
  //     ),
  //   );
  // }

  // ///19, 構建繳費表單表格 - 顯示全部數據
  // Widget _buildPaymentFormTable(ArrearProvider provider) {
  //   if (provider.isLoading) {
  //     return const Center(
  //       child: CircularProgressIndicator(),
  //     );
  //   }

  //   if (provider.error != null && provider.error!.isNotEmpty) {
  //     return _buildPaymentFormErrorContainer(provider.error!);
  //   }

  //   final rawData = provider.rawArrearData;

  //   if (rawData.isEmpty) {
  //     return Container(
  //       padding: const EdgeInsets.all(40),
  //       decoration: BoxDecoration(
  //         color: Colors.white,
  //         borderRadius: BorderRadius.circular(12),
  //         boxShadow: [
  //           BoxShadow(
  //             color: Colors.black.withOpacity(0.06),
  //             blurRadius: 8,
  //             offset: const Offset(0, 2),
  //           ),
  //         ],
  //       ),
  //       child: const Center(
  //         child: Column(
  //           children: [
  //             Icon(Icons.table_chart_outlined, color: Colors.grey, size: 60),
  //             SizedBox(height: 16),
  //             Text(
  //               '暫無欠費數據',
  //               style: TextStyle(
  //                 fontSize: 18,
  //                 color: Colors.grey,
  //                 fontWeight: FontWeight.w500,
  //               ),
  //             ),
  //             SizedBox(height: 8),
  //             Text(
  //               '請稍後再試或聯繫管理員',
  //               style: TextStyle(
  //                 fontSize: 14,
  //                 color: Colors.grey,
  //               ),
  //             ),
  //           ],
  //         ),
  //       ),
  //     );
  //   }

  //   // 獲取表頭（排除"單位"字段）
  //   final headers = _getTableHeaders(rawData);

  //   return Container(
  //     width: double.infinity,
  //     decoration: BoxDecoration(
  //       color: Colors.white,
  //       borderRadius: BorderRadius.circular(12),
  //       boxShadow: [
  //         BoxShadow(
  //           color: Colors.black.withOpacity(0.06),
  //           blurRadius: 8,
  //           offset: const Offset(0, 2),
  //         ),
  //       ],
  //     ),
  //     child: Column(
  //       children: [
  //         // 自定義表頭
  //         Container(
  //           decoration: const BoxDecoration(
  //             color: Color(0xFF6C4EB6), // 主題色
  //             borderRadius: BorderRadius.only(
  //               topLeft: Radius.circular(12),
  //               topRight: Radius.circular(12),
  //             ),
  //           ),
  //           padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
  //           child: Row(
  //             children: [
  //               Expanded(
  //                 flex: 2,
  //                 child: Text(
  //                   '單位',
  //                   style: const TextStyle(
  //                     color: Colors.white,
  //                     fontWeight: FontWeight.w600,
  //                     fontSize: 14,
  //                   ),
  //                 ),
  //               ),
  //               ...headers.map((header) => Expanded(
  //                     flex: 2,
  //                     child: Text(
  //                       header,
  //                       style: const TextStyle(
  //                         color: Colors.white,
  //                         fontWeight: FontWeight.w600,
  //                         fontSize: 14,
  //                       ),
  //                         textAlign: TextAlign.center,
  //                     ),
  //                   )),
  //             ],
  //           ),
  //         ),
  //         // 數據區域 - 顯示全部數據
  //         ...rawData.map((record) => Container(
  //               decoration: const BoxDecoration(
  //                 border: Border(
  //                   bottom: BorderSide(color: Color(0xFFF0F0F0)),
  //                 ),
  //               ),
  //               child: Row(
  //                 children: [
  //                   Expanded(
  //                     flex: 2,
  //                     child: Padding(
  //                       padding: const EdgeInsets.symmetric(
  //                         vertical: 10,
  //                         horizontal: 16,
  //                       ),
  //                       child: Text(
  //                         record['單位']?.toString() ?? '-',
  //                         style: const TextStyle(
  //                           fontWeight: FontWeight.w500,
  //                           color: Colors.black87,
  //                           fontSize: 13,
  //                         ),
  //                       ),
  //                     ),
  //                   ),
  //                   ...headers.map((header) => Expanded(
  //                         flex: 2,
  //                         child: Center(
  //                           child: _buildStatusChip(record[header]),
  //                         ),
  //                       )),
  //                 ],
  //               ),
  //             )),
  //       ],
  //     ),
  //   );
  // }

  // ///20, 獲取表頭
  // List<String> _getTableHeaders(List<Map<String, dynamic>> rawData) {
  //   if (rawData.isEmpty) return [];

  //   // 獲取第一條記錄的所有鍵，排除"單位"字段
  //   final firstRecord = rawData.first;
  //   return firstRecord.keys.where((key) => key != '單位').toList();
  // }

  // ///21, 構建狀態芯片
  // Widget _buildStatusChip(dynamic value) {
  //   return Container(
  //     padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  //     decoration: BoxDecoration(
  //       color: _getStatusColor(value),
  //       borderRadius: BorderRadius.circular(12),
  //     ),
  //     child: Text(
  //       _getStatusText(value),
  //       style: TextStyle(
  //         fontSize: 11,
  //         fontWeight: FontWeight.w500,
  //         color: _getStatusTextColor(value),
  //       ),
  //       textAlign: TextAlign.center,
  //     ),
  //   );
  // }

  // ///22, 獲取狀態顏色
  // Color _getStatusColor(dynamic value) {
  //   if (value == null) return Colors.grey.shade100;
  //   if (value == '已付') return Colors.green.shade100;
  //   if (value is num && value < 0) return Colors.red.shade100;
  //   return Colors.grey.shade100;
  // }

  // ///23, 獲取狀態文字顏色
  // Color _getStatusTextColor(dynamic value) {
  //   if (value == null) return Colors.grey.shade800;
  //   if (value == '已付') return Colors.green.shade800;
  //   if (value is num && value < 0) return Colors.red.shade800;
  //   return Colors.grey.shade800;
  // }

  // ///24, 獲取狀態文字
  // String _getStatusText(dynamic value) {
  //   if (value == null) return '-';
  //   return value.toString();
  // }

  // ///25, 構建繳費表單樓層選擇器
  // Widget _buildPaymentFormBuildingSelector(ArrearProvider provider) {
  //   final buildings = provider.buildings;

  //   return SizedBox(
  //     width: double.infinity,
  //     child: Column(
  //       crossAxisAlignment: CrossAxisAlignment.start,
  //       children: [
  //         const Text(
  //           '選擇樓層',
  //           style: TextStyle(
  //           fontSize: 16,
  //           fontWeight: FontWeight.w600,
  //           color: Colors.black87,
  //         ),
  //       ),
  //       const SizedBox(height: 12),
  //       Wrap(
  //         alignment: WrapAlignment.start,
  //         spacing: 8,
  //         runSpacing: 8,
  //         children: buildings.map((building) {
  //           final isSelected = _selectedTableBuilding == building;
  //           return GestureDetector(
  //             onTap: () {
  //               setState(() {
  //                 _selectedTableBuilding = building;
  //                 _selectedTableFloor = null;
  //                 _showTableResults = false;
  //                 // 设置楼层（不是buildingId）
  //                 provider.setSelectedFloor(building);
  //               });
  //             },
  //             child: Container(
  //               padding:
  //                   const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  //               decoration: BoxDecoration(
  //                 color: isSelected
  //                     ? Theme.of(context).primaryColor
  //                     : Colors.grey.shade100,
  //                 borderRadius: BorderRadius.circular(8),
  //                 border: Border.all(
  //                   color: isSelected
  //                       ? Theme.of(context).primaryColor
  //                       : Colors.grey.shade300,
  //                   width: 1,
  //               ),
  //             ),
  //             child: Text(
  //               '$building',
  //               style: TextStyle(
  //                 fontSize: 14,
  //                 fontWeight: FontWeight.w500,
  //                 color: isSelected ? Colors.white : Colors.black87,
  //               ),
  //             ),
  //           ),
  //         ),
  //       ),
  //     ],
  //   ),
  // );
  // }

  // ///26, 構建繳費表單單位選擇器
  // Widget _buildPaymentFormFloorSelector(ArrearProvider provider) {
  //   final floors = _selectedTableBuilding != null
  //       ? provider.getFloors(_selectedTableBuilding!)
  //       : [];

  //   return SizedBox(
  //     width: double.infinity,
  //     child: Column(
  //       crossAxisAlignment: CrossAxisAlignment.start,
  //       children: [
  //         const Text(
  //           '選擇單位',
  //           style: TextStyle(
  //           fontSize: 16,
  //           fontWeight: FontWeight.w600,
  //           color: Colors.black87,
  //         ),
  //       ),
  //       const SizedBox(height: 12),
  //       Wrap(
  //         alignment: WrapAlignment.start,
  //         spacing: 8,
  //         runSpacing: 8,
  //         children: floors.map((floor) {
  //           final isSelected = _selectedTableBuilding == floor;
  //           return GestureDetector(
  //             onTap: () {
  //               setState(() {
  //                 _selectedTableFloor = floor;
  //                 _showTableResults = false;
  //                 provider.setSelectedUnit(floor);
  //               });
  //             },
  //             child: Container(
  //               padding:
  //                   const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  //               decoration: BoxDecoration(
  //                 color: isSelected
  //                     ? Theme.of(context).primaryColor
  //                     : Colors.grey.shade100,
  //                 borderRadius: BorderRadius.circular(8),
  //                 border: Border.all(
  //                   color: isSelected
  //                       ? Theme.of(context).primaryColor
  //                       : Colors.grey.shade300,
  //                   width: 1,
  //               ),
  //             ),
  //             child: Text(
  //               floor,
  //               style: TextStyle(
  //                 fontSize: 14,
  //                 fontWeight: FontWeight.w500,
  //                 color: isSelected ? Colors.white : Colors.black87,
  //               ),
  //             ),
  //           ),
  //         ),
  //       ),
  //     ],
  //   ),
  // }

  // ///27, 構建繳費表單查詢按鈕
  // Widget _buildPaymentFormQueryButton(ArrearProvider provider) {
  //   final canQuery =
  //       _selectedTableBuilding != null && _selectedTableFloor != null;

  //   return SizedBox(
  //     width: double.infinity,
  //     child: ElevatedButton(
  //       onPressed: canQuery ? _handlePaymentFormQuery : null,
  //       style: ElevatedButton.styleFrom(
  //         backgroundColor:
  //             canQuery ? Theme.of(context).primaryColor : Colors.grey.shade300,
  //         foregroundColor: canQuery ? Colors.white : Colors.grey.shade600,
  //         padding: const EdgeInsets.symmetric(vertical: 16),
  //         shape: RoundedRectangleBorder(
  //         borderRadius: BorderRadius.circular(8),
  //       ),
  //       elevation: canQuery ? 2 : 0,
  //     ),
  //     child: const Text(
  //       '查詢繳費記錄',
  //       style: TextStyle(
  //         fontSize: 18,
  //         fontWeight: FontWeight.w600,
  //       ),
  //     ),
  //   ),
  // }

  // ///28, 處理繳費表單查詢
  // void _handlePaymentFormQuery() {
  //   if (_selectedTableBuilding != null && _selectedTableFloor != null) {
  //     setState(() {
  //       _showTableResults = true;
  //     });
  //   }
  // }

  // ///29, 構建繳費表單查詢結果容器
  // Widget _buildPaymentFormResultsContainer(ArrearProvider provider) {
  //   if (provider.isLoading) {
  //     return Container(
  //       padding: const EdgeInsets.all(0),
  //       child: const Center(
  //         child: CircularProgressIndicator(),
  //       ),
  //     );
  //   }

  //   if (provider.error != null && provider.error!.isNotEmpty) {
  //     return _buildPaymentFormErrorContainer(provider.error!);
  //   }

  //   // 使用與欠費查詢完全相同的數據判斷邏輯
  //   final arrears = provider.arrears;
  //   final hasData = arrears.isNotEmpty || provider.rawArrearData.isNotEmpty;

  //   if (hasData) {
  //     return _buildPaymentFormDataContent(provider);
  //   }

  //   return Container(
  //     padding: const EdgeInsets.all(0),
  //     decoration: BoxDecoration(
  //       borderRadius: BorderRadius.circular(12),
  //     ),
  //     child: const Center(
  //       child: Column(
  //         children: [
  //           Icon(Icons.info_outline, color: Colors.grey, size: 60),
  //           SizedBox(height: 16),
  //           Text(
  //             '暫無欠費數據',
  //             style: TextStyle(
  //               fontSize: 18,
  //               color: Colors.grey,
  //               fontWeight: FontWeight.w500,
  //             ),
  //           ),
  //           SizedBox(height: 8),
  //           Text(
  //             '請稍後再試或聯繫管理員',
  //             style: TextStyle(
  //               fontSize: 14,
  //               color: Colors.grey,
  //             ),
  //           ),
  //         ],
  //       ),
  //     ),
  //   );
  // }

  // ///30, 構建繳費表單錯誤容器
  // Widget _buildPaymentFormErrorContainer(String errorMessage) {
  //   return Container(
  //     width: double.infinity,
  //     padding: const EdgeInsets.all(0),
  //     decoration: BoxDecoration(
  //       borderRadius: BorderRadius.circular(12),
  //       boxShadow: [
  //         BoxShadow(
  //           color: Colors.black.withOpacity(0.06),
  //           blurRadius: 8,
  //           offset: const Offset(0, 2),
  //         ),
  //       ],
  //     ),
  //     child: Center(
  //       child: Column(
  //         children: [
  //           const Icon(Icons.error_outline, color: Colors.red, size: 60),
  //           const SizedBox(height: 16),
  //           const Text(
  //             '數據獲取失敗',
  //             style: TextStyle(
  //               fontSize: 18,
  //               color: Colors.red,
  //               fontWeight: FontWeight.w500,
  //             ),
  //           ),
  //           const SizedBox(height: 8),
  //           SelectableText.rich(
  //             TextSpan(
  //             children: [
  //               TextSpan(
  //                 text: errorMessage,
  //                 style: const TextStyle(
  //                 fontSize: 14,
  //                 color: Colors.red,
  //               ),
  //             ),
  //           ),
  //           textAlign: TextAlign.center,
  //         ),
  //       ),
  //     ),
  //   );
  // }

  // ///31, 構建繳費表單數據內容
  // Widget _buildPaymentFormDataContent(ArrearProvider provider) {
  //   return Container(
  //     padding: const EdgeInsets.all(10),
  //     decoration: BoxDecoration(
  //       borderRadius: BorderRadius.circular(12),
  //     ),
  //     child: Column(
  //       children: [
  //         // 結果標題
  //         Row(
  //           children: [
  //             const Icon(Icons.table_chart, color: Colors.blue, size: 24),
  //             const SizedBox(width: 8),
  //             Text(
  //               '繳費表單 - ${_selectedTableBuilding}${_selectedTableFloor}單位',
  //               style: const TextStyle(
  //                 fontSize: 18,
  //                 fontWeight: FontWeight.w600,
  //                 color: Colors.black87,
  //               ),
  //             ),
  //           ],
  //         ),

  //         const SizedBox(height: 16),

  //         // 繳費表單記錄列表 - 使用與欠費查詢相同的數據顯示方式
  //         _buildPaymentFormList(provider),
  //       ],
  //     ),
  //   );
  // }

  // ///32, 構建繳費表單記錄列表
  // Widget _buildPaymentFormList(ArrearProvider provider) {
  //   final currentArrearage = provider.currentArrearage;

  //   if (currentArrearage == null) {
  //     return const Center(
  //       child: Text('暫無數據'),
  //     );
  //   }

  //   final entries = currentArrearage.entries.toList();

  //   return Column(
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
      // case '繳費表單':
      //   return _buildPaymentFormContent();
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
