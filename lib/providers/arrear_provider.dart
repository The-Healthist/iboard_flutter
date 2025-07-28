import 'package:flutter/material.dart';
import 'package:iboard_app/models/arrear_model.dart';
import 'package:iboard_app/http/api_client.dart';
import 'package:logger/logger.dart';

class ArrearProvider extends ChangeNotifier {
  final Logger _logger = Logger();
  final ApiClient _apiClient;

  bool _isLoading = false;
  String? _error;
  List<ArrearModel> _arrears = [];
  String? _selectedBuildingId;
  String? _selectedUnit;

  // 存储API返回的原始数据
  List<Map<String, dynamic>> _rawArrearData = [];

  // 楼号到单元的映射
  Map<String, List<String>> _buildingToUnits = {};

  ArrearProvider({required ApiClient apiClient}) : _apiClient = apiClient;

  // 检查Provider是否已被销毁的简单方法
  bool get isDisposed => _disposed;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  // Getters
  bool get isLoading => _isLoading;
  String? get error => _error;
  List<ArrearModel> get arrears => _arrears;
  String? get selectedBuildingId => _selectedBuildingId;
  String? get selectedUnit => _selectedUnit;
  List<Map<String, dynamic>> get rawArrearData => _rawArrearData;

  // 获取所有楼号
  List<String> get buildings {
    return _buildingToUnits.keys.toList()..sort();
  }

  // 获取指定楼号的所有单元号
  List<String> getFloors(String building) {
    final floors = _buildingToUnits[building]?.toList() ?? [];
    floors.sort();
    return floors;
  }

  // 获取指定单位的欠款记录
  Map<String, dynamic>? getArrearageByUnit(String building, String unit) {
    for (var item in _rawArrearData) {
      if (item.containsKey('單位')) {
        final unitInfo = item['單位'].toString();
        // 解析楼号和单元，例如 "22樓  A" -> 楼号:"22", 单元:"A"
        final parts = unitInfo.split('  '); // 注意是两个空格
        if (parts.length >= 2) {
          final floor = parts[0].replaceAll('樓', '');
          final unitName = parts[1];

          // 检查是否匹配指定的楼号和单元号
          if (floor == building && unitName == unit) {
            // 返回除了"單位"键之外的所有数据
            final data = Map<String, dynamic>.from(item);
            data.remove('單位');
            return data;
          }
        }
      }
    }
    return null;
  }

  // 获取当前选中单位的欠款记录
  Map<String, dynamic>? get currentArrearage {
    if (_selectedBuildingId == null || _selectedUnit == null) return null;
    return getArrearageByUnit(_selectedBuildingId!, _selectedUnit!);
  }

  // 判断是否有数据
  bool get hasData => _rawArrearData.isNotEmpty;

  /// 初始化获取欠费数据
  Future<void> initGetArrearData() async {
    _logger.i('开始初始化获取欠费数据');
    if (_selectedBuildingId == null || _selectedBuildingId!.isEmpty) {
      _logger.w('楼宇ID未设置，无法初始化欠费数据');
      return;
    }
    await fetchArrears(reset: true, buildingId: _selectedBuildingId);
  }

  /// 获取欠费列表
  Future<void> fetchArrears({bool reset = false, String? buildingId}) async {
    if (_isLoading) {
      _logger.w('欠费数据正在加载中，跳过重复请求');
      return;
    }

    _isLoading = true;
    _error = null;

    if (reset) {
      _arrears = [];
      _rawArrearData = [];
      _buildingToUnits = {};
    }

    notifyListeners();

    try {
      // 确保我们有有效的楼宇ID
      final targetBuildingId = buildingId ?? _selectedBuildingId;
      if (targetBuildingId == null || targetBuildingId.isEmpty) {
        _error = '楼宇ID不能为空';
        _logger.w('无法获取欠费数据：楼宇ID为空');
        return;
      }

      _logger.i('调用API获取欠费数据，楼宇ID: $targetBuildingId');
      final response = await _apiClient.getArrearage(
        buildingId: targetBuildingId,
      );

      _logger.i('API响应类型: ${response.runtimeType}');
      _logger.i('API完整响应: $response');

      // 处理响应数据
      List<Map<String, dynamic>> records = [];
      
      // 检查响应格式 (response是Map<String, dynamic>类型)
      // 对象格式，检查不同的可能结构
      if (response.containsKey('data') && response['data'] is List) {
        _logger.i('响应为包含data字段的格式');
        for (var item in response['data'] as List) {
          if (item is Map) {
            records.add(Map<String, dynamic>.from(item as Map));
          } else {
            _logger.w('data数组中的项目不是Map类型: ${item.runtimeType}');
          }
        }
      } else if (response.containsKey('status') && 
                 response['status'] == 'success' && 
                 response.containsKey('data') && 
                 response['data'] is List) {
        _logger.i('响应为{status: success, data: [...]}格式');
        for (var item in response['data'] as List) {
          if (item is Map) {
            records.add(Map<String, dynamic>.from(item as Map));
          } else {
            _logger.w('data数组中的项目不是Map类型: ${item.runtimeType}');
          }
        }
      } else {
        // 尝试直接处理Map对象
        _logger.i('尝试直接处理Map对象');
        // 直接添加Map对象
        records.add(Map<String, dynamic>.from(response));
      }

      _logger.i('解析后的记录数: ${records.length}');
      if (records.isNotEmpty) {
        _logger.i('第一条记录示例: ${records[0]}');
      }

      // 设置欠费数据
      setArrearage(records);

      // 解析为ArrearModel对象
      final List<ArrearModel> parsedArrears = records
          .map((item) => ArrearModel.fromJson(item))
          .toList();

      _arrears = parsedArrears;
      _logger.i('成功解析 ${parsedArrears.length} 条欠费记录');

      _error = null;
    } catch (e, stackTrace) {
      _error = '网络请求失败: $e';
      _logger.e('获取欠费数据时发生异常: $e', error: e, stackTrace: stackTrace);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 处理原始欠费数据，构建楼号到单元的映射
  void _processRawArrearData() {
    _buildingToUnits = {};
    _logger.i('开始处理原始欠费数据，共 ${_rawArrearData.length} 条记录');

    for (var item in _rawArrearData) {
      if (item.containsKey('單位')) {
        final unitInfo = item['單位'].toString();
        _logger.d('处理单位信息: $unitInfo');
        // 解析楼号和单元，例如 "22樓  A" -> 楼号:"22", 单元:"A"
        // 先尝试两个空格分割
        List<String> parts = unitInfo.split('  '); // 注意是两个空格
        // 如果没有找到两个空格，尝试一个空格
        if (parts.length < 2) {
          parts = unitInfo.split(' ');
        }
        
        if (parts.length >= 2) {
          // 提取楼号（去除"樓"字）
          final floor = parts[0].replaceAll(RegExp(r'[樓楼]'), '').trim();
          // 提取单元号（去除多余空格）
          final unit = parts[1].trim();

          _logger.d('解析结果 - 楼号: $floor, 单元: $unit');

          // 确保楼号和单元都不为空
          if (floor.isNotEmpty && unit.isNotEmpty) {
            // 将楼号添加到映射中
            if (!_buildingToUnits.containsKey(floor)) {
              _buildingToUnits[floor] = [];
            }

            // 将单元添加到对应楼号的列表中
            if (!_buildingToUnits[floor]!.contains(unit)) {
              _buildingToUnits[floor]!.add(unit);
            }
          } else {
            _logger.w('楼号或单元为空，跳过该记录: 楼号="$floor", 单元="$unit"');
          }
        } else {
          _logger.w('单位信息格式不正确，无法解析: $unitInfo');
        }
      } else {
        _logger.w('记录缺少"單位"字段: $item');
      }
    }

    _logger.i('处理完成，楼号到单元映射: $_buildingToUnits');
  }

  /// 刷新欠费数据
  Future<void> refreshArrears() async {
    await fetchArrears(reset: true);
  }

  // Setters
  void setSelectedBuildingId(String? buildingId) {
    _selectedBuildingId = buildingId;
    _selectedUnit = null; // 重置单元选择
    _logger.i('设置楼宇ID: $buildingId');
    notifyListeners();

    // 自动选择第一个单元
    if (buildingId != null) {
      final floors = getFloors(buildingId);
      if (floors.isNotEmpty) {
        setSelectedUnit(floors[0]);
      }
    }
  }

  void setSelectedUnit(String? unit) {
    _selectedUnit = unit;
    _logger.i('设置单元: $unit');
    notifyListeners();
  }

  // Actions
  void setArrearage(List<Map<String, dynamic>> records) {
    _rawArrearData = records;
    _processRawArrearData();
    notifyListeners();
  }

  void clearArrearage() {
    _rawArrearData = [];
    _buildingToUnits = {};
    _selectedBuildingId = null;
    _selectedUnit = null;
    notifyListeners();
  }
}
