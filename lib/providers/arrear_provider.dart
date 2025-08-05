import 'package:flutter/material.dart';
import 'package:iboard_app/models/arrear_model.dart';
import 'package:iboard_app/http/api_client.dart';
import 'package:iboard_app/providers/app_data_provider.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';

class ArrearProvider extends ChangeNotifier {
  final Logger _logger = Logger();
  final ApiClient _apiClient;
  final AppDataProvider _appDataProvider;

  bool _isLoading = false;
  String? _error;
  List<ArrearModel> _arrears = [];
  String? _selectedBuildingId; // 实际存储的是ismartId，用于API调用
  String? _selectedFloor; // 存储用户选择的楼层，用于UI显示和数据筛选
  String? _selectedUnit;

  // 存储API返回的原始数据
  List<Map<String, dynamic>> _rawArrearData = [];

  // 缓存键
  static const String _cacheKey = 'arrearage_data_cache';
  static const String _lastUpdateKey = 'arrearage_last_update';

  // 固定备选ismartId（当无法获取正确ismartId时使用）
  static const String _fallbackIsmartId = '0314100';

  ArrearProvider({
    required ApiClient apiClient,
    required AppDataProvider appDataProvider,
  })  : _apiClient = apiClient,
        _appDataProvider = appDataProvider;

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
  String? get selectedFloor => _selectedFloor;
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

        // 自动选择第一个楼层（仅用于UI显示）
        if (_rawArrearData.isNotEmpty && _selectedFloor == null) {
          final firstFloor = buildings.isNotEmpty ? buildings[0] : null;
          if (firstFloor != null) {
            setSelectedFloor(firstFloor);
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

  ///1, 获取所有楼层
  List<String> get buildings {
    final floors = <String>{};
    for (var record in _rawArrearData) {
      if (record.containsKey('單位')) {
        final unit = record['單位'].toString();
        // 解析楼层和单位，例如 "22樓  A" -> 楼层:"22樓", 单位:"A"
        // 先尝试两个空格分割
        List<String> parts = unit.split('  '); // 注意是两个空格
        // 如果没有找到两个空格，尝试一个空格
        if (parts.length < 2) {
          parts = unit.split(' ');
        }

        if (parts.length >= 2) {
          // 提取楼层（保留"樓"字）
          final floor = parts[0].trim();
          if (floor.isNotEmpty) {
            floors.add(floor);
          }
        }
      }
    }
    return floors.toList()..sort();
  }

  ///2, 获取指定楼层的所有单位
  List<String> getFloors(String selectedFloor) {
    final units = <String>{};
    for (var record in _rawArrearData) {
      if (record.containsKey('單位')) {
        final unit = record['單位'].toString();
        // 解析楼层和单位，例如 "22樓  A" -> 楼层:"22樓", 单位:"A"
        // 先尝试两个空格分割
        List<String> parts = unit.split('  '); // 注意是两个空格
        // 如果没有找到两个空格，尝试一个空格
        if (parts.length < 2) {
          parts = unit.split(' ');
        }

        if (parts.length >= 2) {
          // 提取楼层（保留"樓"字）
          final floor = parts[0].trim();
          // 提取单位（去除多余空格）
          final unitName = parts[1].trim();

          // 检查是否匹配指定的楼层
          if (floor == selectedFloor && unitName.isNotEmpty) {
            units.add(unitName);
          }
        }
      }
    }
    return units.toList()..sort();
  }

  ///3, 获取指定楼层和单位的欠款记录
  Map<String, dynamic>? getArrearageByUnit(
      String selectedFloor, String selectedUnit) {
    for (var record in _rawArrearData) {
      if (record.containsKey('單位')) {
        final unitInfo = record['單位'].toString();
        // 解析楼层和单位，例如 "22樓  A" -> 楼层:"22樓", 单位:"A"
        // 先尝试两个空格分割
        List<String> parts = unitInfo.split('  '); // 注意是两个空格
        // 如果没有找到两个空格，尝试一个空格
        if (parts.length < 2) {
          parts = unitInfo.split(' ');
        }

        if (parts.length >= 2) {
          // 提取楼层（保留"樓"字）
          final floor = parts[0].trim();
          // 提取单位（去除多余空格）
          final unitName = parts[1].trim();

          // 检查是否匹配指定的楼层和单位
          if (floor == selectedFloor && unitName == selectedUnit) {
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
    if (_selectedFloor == null || _selectedUnit == null) return null;
    return getArrearageByUnit(_selectedFloor!, _selectedUnit!);
  }

  ///5, 判断是否有数据
  bool get hasData => _rawArrearData.isNotEmpty;

  ///6, 获取目标ismartId（优先使用正确的ismartId，否则使用固定备选值）
  String _getTargetIsmartId() {
    final correctIsmartId = _appDataProvider.settingsModel?.building.ismartId;
    final targetId = (correctIsmartId != null && correctIsmartId.isNotEmpty)
        ? correctIsmartId
        : _fallbackIsmartId;

    if (targetId == _fallbackIsmartId) {
      _logger.w('使用固定备选ismartId: $targetId');
    } else {
      _logger.i('使用正确的ismartId: $targetId');
    }

    return targetId;
  }

  /// 初始化获取欠费数据
  Future<void> initGetArrearData() async {
    _logger.i('开始初始化获取欠费数据');

    // 首先尝试从缓存加载数据
    await loadFromCache();

    // 获取目标ismartId
    final targetIsmartId = _getTargetIsmartId();
    // 然后尝试从网络获取最新数据（不重置缓存数据，如果失败则保持缓存数据）
    await fetchArrears(reset: false, buildingId: targetIsmartId);
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
      // 固定使用正确的ismartId，不使用用户选择的楼层
      String targetBuildingId;

      if (buildingId != null && buildingId.isNotEmpty) {
        // 如果明确传入了buildingId参数，使用它
        targetBuildingId = buildingId;
        _logger.i('使用传入的buildingId: $targetBuildingId');
      } else {
        // 使用辅助方法获取目标ismartId
        targetBuildingId = _getTargetIsmartId();
      }

      _logger.i('调用API获取欠费数据，使用ismartId: $targetBuildingId');
      final response = await _apiClient.getArrearage(
        buildingId: targetBuildingId, // 这里的buildingId实际上是ismartId
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

      // 检查是否是Building ID格式错误或服务端验证错误
      if (e.toString().contains('Building ID') ||
          e.toString().contains('只能包含数字和英文字母') ||
          e.toString().contains('格式无效')) {
        // 对于格式错误，显示明确的错误信息
        _error = '楼宇ID格式错误：只能包含数字和英文字母';
        _logger.w('楼宇ID格式验证失败，显示错误提示');
      } else {
        // 其他网络请求失败时，静默处理，不清空现有数据，也不设置错误
        if (_rawArrearData.isNotEmpty) {
          _logger.i('网络请求失败，保持现有缓存数据，共 ${_rawArrearData.length} 条记录');
        } else {
          _logger.i('网络请求失败，且无缓存数据');
        }
        // 不设置_error，保持静默
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 刷新欠费数据
  Future<void> refreshArrears() async {
    await fetchArrears(reset: true);
  }

  ///7, 设置楼宇ismartId (由AppDataProvider调用，用于API调用)
  /// 注意：这个方法设置的是真正的ismartId，不是用户在UI中选择的楼层
  void setSelectedBuildingId(String? buildingId) {
    _selectedBuildingId = buildingId; // 这里的buildingId实际上是ismartId
    _selectedUnit = null; // 重置单元选择
    _logger.i('设置楼宇ismartId: $buildingId');

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

  ///8, 设置选中的楼层（用于UI显示和数据筛选）
  void setSelectedFloor(String? floor) {
    _selectedFloor = floor;
    _selectedUnit = null; // 重置单元选择
    _logger.i('设置显示楼层: $floor');

    // 自动选择第一个单位
    if (floor != null) {
      final units = getFloors(floor);
      if (units.isNotEmpty) {
        _selectedUnit = units[0];
        _logger.i('自动选择第一个单位: ${units[0]}');
      }
    }

    notifyListeners();
  }

  ///9, 设置选中的单元
  void setSelectedUnit(String? unit) {
    _selectedUnit = unit;
    _logger.i('设置单元: $unit');
    notifyListeners();
  }

  ///6, 设置欠费数据
  void setArrearage(List<Map<String, dynamic>> records) {
    _rawArrearData = records;

    // 如果有数据但没有选中的楼层，自动选择第一个（仅用于UI显示）
    if (_rawArrearData.isNotEmpty && _selectedFloor == null) {
      final firstFloor = buildings.isNotEmpty ? buildings[0] : null;
      if (firstFloor != null) {
        setSelectedFloor(firstFloor);
      }
    }

    notifyListeners();
  }

  ///10, 清除欠费数据
  void clearArrearage() {
    _rawArrearData = [];
    _selectedFloor = null;
    _selectedUnit = null;
    // 注意：不清除_selectedBuildingId，因为它存储的是ismartId，用于API调用
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
        'Starting periodic arrear update with interval: $intervalMinutes minutes ($intervalSeconds seconds)');

    _isPeriodicUpdateActive = true;

    // 立即执行一次更新，使用目标ismartId
    final targetIsmartId = _getTargetIsmartId();
    fetchArrears(reset: false, buildingId: targetIsmartId);

    // 设置定时器进行周期性更新
    _updateTimer = Timer.periodic(Duration(seconds: intervalSeconds), (timer) {
      if (_isPeriodicUpdateActive) {
        _logger.i('Performing periodic arrear update...');
        final currentTargetId = _getTargetIsmartId();
        fetchArrears(reset: false, buildingId: currentTargetId);
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

  ///12，重新初始化Provider（当依赖变化时调用）
  void reinitialize() {
    _logger.i('ArrearProvider reinitializing...');

    // 停止现有的定时更新
    stopPeriodicUpdate();

    // 重新加载缓存数据
    loadFromCache();

    // 如果AppDataProvider已登录，重新启动定时更新
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_appDataProvider.isLoggedIn &&
          _appDataProvider.buildingInfo?.ismartId != null) {
        _logger.i('重新初始化完成，重启欠费数据定时更新');
        final deviceSettings = _appDataProvider.deviceSettings;
        final arrearUpdateInterval =
            deviceSettings?.arrearageUpdateDuration ?? 1;
        startPeriodicUpdate(updateIntervalMinutes: arrearUpdateInterval);
      }
    });
  }
}
