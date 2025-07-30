import 'package:flutter/material.dart';
import 'package:iboard_app/models/arrear_model.dart';
import 'package:iboard_app/http/api_client.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';

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

  // 缓存键
  static const String _cacheKey = 'arrearage_data_cache';
  static const String _lastUpdateKey = 'arrearage_last_update';

  ArrearProvider({required ApiClient apiClient}) : _apiClient = apiClient;

  // 定时更新相关
  Timer? _updateTimer; // 定时更新定时器
  bool _isPeriodicUpdateActive = false; // 是否正在进行定期更新

  // 检查Provider是否已被销毁的简单方法
  bool get isDisposed => _disposed;
  bool _disposed = false;

  // 定时更新状态getter
  bool get isPeriodicUpdateActive => _isPeriodicUpdateActive;

  @override
  void dispose() {
    stopPeriodicUpdate();
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

  ///1, 从缓存加载欠费数据
  Future<void> loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedData = prefs.getString(_cacheKey);
      final lastUpdate = prefs.getString(_lastUpdateKey);

      if (cachedData != null) {
        final List<dynamic> decodedData = json.decode(cachedData);
        final List<Map<String, dynamic>> records =
            decodedData.map((item) => Map<String, dynamic>.from(item)).toList();

        _rawArrearData = records;
        _arrears = records.map((item) => ArrearModel.fromJson(item)).toList();

        _logger.i('✅ 从缓存加载欠费数据成功，共 ${records.length} 条记录');
        if (lastUpdate != null) {
          _logger.i('📅 缓存更新时间: $lastUpdate');
        }

        // 自动选择第一个楼号
        if (_rawArrearData.isNotEmpty && _selectedBuildingId == null) {
          final firstBuilding = buildings.isNotEmpty ? buildings[0] : null;
          if (firstBuilding != null) {
            setSelectedBuildingId(firstBuilding);
          }
        }

        notifyListeners();
      } else {
        _logger.i('📭 缓存中没有欠费数据');
      }
    } catch (e) {
      _logger.e('❌ 从缓存加载欠费数据失败: $e');
    }
  }

  ///2, 保存欠费数据到缓存
  Future<void> saveToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonData = json.encode(_rawArrearData);
      final now = DateTime.now().toIso8601String();

      await prefs.setString(_cacheKey, jsonData);
      await prefs.setString(_lastUpdateKey, now);

      _logger.i('✅ 欠费数据已保存到缓存，共 ${_rawArrearData.length} 条记录');
      _logger.i('📅 缓存更新时间: $now');
    } catch (e) {
      _logger.e('❌ 保存欠费数据到缓存失败: $e');
    }
  }

  ///3, 获取缓存更新时间
  Future<String?> getLastUpdateTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_lastUpdateKey);
    } catch (e) {
      _logger.e('❌ 获取缓存更新时间失败: $e');
      return null;
    }
  }

  ///4, 清除缓存
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      await prefs.remove(_lastUpdateKey);

      _logger.i('🗑️ 欠费数据缓存已清除');
    } catch (e) {
      _logger.e('❌ 清除缓存失败: $e');
    }
  }

  ///5, 检查缓存状态
  Future<Map<String, dynamic>> getCacheStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedData = prefs.getString(_cacheKey);
      final lastUpdate = prefs.getString(_lastUpdateKey);

      return {
        'hasCache': cachedData != null,
        'lastUpdate': lastUpdate,
        'cacheSize': cachedData?.length ?? 0,
        'recordCount': _rawArrearData.length,
      };
    } catch (e) {
      _logger.e('❌ 获取缓存状态失败: $e');
      return {
        'hasCache': false,
        'lastUpdate': null,
        'cacheSize': 0,
        'recordCount': 0,
        'error': e.toString(),
      };
    }
  }

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

    // 首先尝试从缓存加载数据
    await loadFromCache();

    if (_selectedBuildingId == null || _selectedBuildingId!.isEmpty) {
      _logger.w('楼宇ID未设置，无法初始化欠费数据');
      return;
    }

    // 然后尝试从网络获取最新数据（不重置缓存数据，如果失败则保持缓存数据）
    await fetchArrears(reset: false, buildingId: _selectedBuildingId);
  }

  /// 获取欠费列表
  Future<void> fetchArrears({bool reset = false, String? buildingId}) async {
    if (_isLoading) {
      _logger.w('欠费数据正在加载中，跳过重复请求');
      return;
    }

    _isLoading = true;
    _error = null;

    // 只有在明确要求重置时才清空数据
    if (reset) {
      _arrears = [];
      _rawArrearData = [];
      _logger.i('重置欠费数据');
    }

    notifyListeners();

    try {
      // 确保我们有有效的楼宇ID
      final targetBuildingId = buildingId ?? _selectedBuildingId;
      if (targetBuildingId == null || targetBuildingId.isEmpty) {
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

      // 保存到缓存
      await saveToCache();

      _error = null;
    } catch (e, stackTrace) {
      _logger.e('获取欠费数据时发生异常: $e', error: e, stackTrace: stackTrace);

      // 网络请求失败时，静默处理，不清空现有数据，也不设置错误
      if (_rawArrearData.isNotEmpty) {
        _logger.i('网络请求失败，保持现有缓存数据，共 ${_rawArrearData.length} 条记录');
      } else {
        _logger.i('网络请求失败，且无缓存数据');
      }
      // 不设置_error，保持静默
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

  ///10，开始定期更新欠费数据
  void startPeriodicUpdate({int? updateIntervalMinutes}) {
    if (_isPeriodicUpdateActive) {
      _logger.i('Periodic arrear update is already active.');
      return;
    }

    // 获取更新间隔时间（从设置中获取，单位：分钟）
    final intervalMinutes = updateIntervalMinutes ?? 1; // 默认1分钟
    final intervalSeconds = intervalMinutes * 60; // 转换为秒
    _logger.i(
        'Starting periodic arrear update with interval: ${intervalMinutes} minutes (${intervalSeconds} seconds)');

    _isPeriodicUpdateActive = true;

    // 立即执行一次更新
    if (_selectedBuildingId != null) {
      fetchArrears(reset: false, buildingId: _selectedBuildingId);
    }

    // 设置定时器进行周期性更新
    _updateTimer = Timer.periodic(Duration(seconds: intervalSeconds), (timer) {
      if (_isPeriodicUpdateActive && _selectedBuildingId != null) {
        _logger.i('Performing periodic arrear update...');
        fetchArrears(reset: false, buildingId: _selectedBuildingId);
      } else {
        timer.cancel();
      }
    });
  }

  ///11，停止定期更新
  void stopPeriodicUpdate() {
    if (_updateTimer != null) {
      _updateTimer!.cancel();
      _updateTimer = null;
    }
    _isPeriodicUpdateActive = false;
    _logger.i('Periodic arrear update stopped.');
  }
}
