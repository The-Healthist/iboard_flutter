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

  ///1, 获取所有楼号
  List<String> get buildings {
    final buildings = <String>{};
    for (var record in _rawArrearData) {
      if (record.containsKey('單位')) {
        final unit = record['單位'].toString();
        // 解析楼号和单元，例如 "22樓  A" -> 楼号:"22", 单元:"A"
        // 先尝试两个空格分割
        List<String> parts = unit.split('  '); // 注意是两个空格
        // 如果没有找到两个空格，尝试一个空格
        if (parts.length < 2) {
          parts = unit.split(' ');
        }

        if (parts.length >= 2) {
          // 提取楼号（去除"樓"字）
          final building = parts[0].replaceAll(RegExp(r'[樓楼]'), '').trim();
          if (building.isNotEmpty) {
            buildings.add(building);
          }
        }
      }
    }
    return buildings.toList()..sort();
  }

  ///2, 获取指定楼号的所有单元号（楼层）
  List<String> getFloors(String building) {
    final floors = <String>{};
    for (var record in _rawArrearData) {
      if (record.containsKey('單位')) {
        final unit = record['單位'].toString();
        // 解析楼号和单元，例如 "22樓  A" -> 楼号:"22", 单元:"A"
        // 先尝试两个空格分割
        List<String> parts = unit.split('  '); // 注意是两个空格
        // 如果没有找到两个空格，尝试一个空格
        if (parts.length < 2) {
          parts = unit.split(' ');
        }

        if (parts.length >= 2) {
          // 提取楼号（去除"樓"字）
          final floor = parts[0].replaceAll(RegExp(r'[樓楼]'), '').trim();
          // 提取单元号（去除多余空格）
          final unitName = parts[1].trim();

          // 检查是否匹配指定的楼号
          if (floor == building && unitName.isNotEmpty) {
            floors.add(unitName);
          }
        }
      }
    }
    return floors.toList()..sort();
  }

  ///3, 获取指定单位的欠款记录
  Map<String, dynamic>? getArrearageByUnit(String building, String unit) {
    for (var record in _rawArrearData) {
      if (record.containsKey('單位')) {
        final unitInfo = record['單位'].toString();
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
          final unitName = parts[1].trim();

          // 检查是否匹配指定的楼号和单元号
          if (floor == building && unitName == unit) {
            // 返回除了"單位"键之外的所有数据
            final data = Map<String, dynamic>.from(record);
            data.remove('單位');
            return data;
          }
        }
      }
    }
    return null;
  }

  ///4, 获取当前选中单位的欠款记录
  Map<String, dynamic>? get currentArrearage {
    if (_selectedBuildingId == null || _selectedUnit == null) return null;
    return getArrearageByUnit(_selectedBuildingId!, _selectedUnit!);
  }

  ///5, 判断是否有数据
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

      // 现在response直接是List<Map<String, dynamic>>类型
      final List<Map<String, dynamic>> records = response;

      _logger.i('解析后的记录数: ${records.length}');
      if (records.isNotEmpty) {
        _logger.i('第一条记录示例: ${records[0]}');
      }

      // 设置欠费数据
      setArrearage(records);

      // 解析为ArrearModel对象
      final List<ArrearModel> parsedArrears =
          records.map((item) => ArrearModel.fromJson(item)).toList();

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

  /// 刷新欠费数据
  Future<void> refreshArrears() async {
    await fetchArrears(reset: true);
  }

  ///7, 设置选中的楼号
  void setSelectedBuildingId(String? buildingId) {
    _selectedBuildingId = buildingId;
    _selectedUnit = null; // 重置单元选择
    _logger.i('设置楼宇ID: $buildingId');

    // 自动选择第一个单元
    if (buildingId != null) {
      final floors = getFloors(buildingId);
      if (floors.isNotEmpty) {
        _selectedUnit = floors[0];
        _logger.i('自动选择第一个单元: ${floors[0]}');
      }
    }

    notifyListeners();
  }

  ///8, 设置选中的单元
  void setSelectedUnit(String? unit) {
    _selectedUnit = unit;
    _logger.i('设置单元: $unit');
    notifyListeners();
  }

  ///6, 设置欠费数据并自动选择第一个楼号
  void setArrearage(List<Map<String, dynamic>> records) {
    _rawArrearData = records;

    // 如果有数据但没有选中的楼号，自动选择第一个
    if (_rawArrearData.isNotEmpty && _selectedBuildingId == null) {
      final firstBuilding = buildings.isNotEmpty ? buildings[0] : null;
      if (firstBuilding != null) {
        setSelectedBuildingId(firstBuilding);
      }
    }

    notifyListeners();
  }

  ///9, 清除欠费数据
  void clearArrearage() {
    _rawArrearData = [];
    _selectedBuildingId = null;
    _selectedUnit = null;
    notifyListeners();
  }
}
