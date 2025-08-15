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

  // 缓存楼层、单位和明细数据，避免重复计算
  Map<String, List<String>> _cachedFloorUnits = {};
  List<String> _cachedBuildings = [];
  // floor -> unit -> record data
  Map<String, Map<String, Map<String, dynamic>>> _cachedArrearMap = {};
  bool _isCacheValid = false;

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
        _isCacheValid = false; // 数据加载后重置缓存
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

  ///1, 获取所有楼层（缓存）
  List<String> get buildings {
    if (!_isCacheValid) _buildCache();
    return _cachedBuildings;
  }

  ///2, 获取指定楼层的所有单位（缓存）
  List<String> getFloors(String selectedFloor) {
    if (!_isCacheValid) _buildCache();
    return _cachedFloorUnits[selectedFloor] ?? [];
  }

  ///3, 获取指定楼层和单位的欠款记录（缓存）
  Map<String, dynamic>? getArrearageByUnit(
      String selectedFloor, String selectedUnit) {
    if (!_isCacheValid) _buildCache();
    return _cachedArrearMap[selectedFloor]?[selectedUnit];
  }

  ///4, 获取当前选中单位的欠款记录
  Map<String, dynamic>? get currentArrearage {
    _logger.i(
        '🔍 [currentArrearage] 当前状态 - 楼层: "$_selectedFloor", 单位: "$_selectedUnit"');

    if (_selectedFloor == null || _selectedUnit == null) {
      _logger.w('⚠️ [currentArrearage] 楼层或单位未选择，返回null');
      return null;
    }

    _logger.i(
        '🔍 [currentArrearage] 开始查找楼层 "$_selectedFloor" 单位 "$_selectedUnit" 的记录');
    return getArrearageByUnit(_selectedFloor!, _selectedUnit!);
  }

  ///4a, 健壮的楼层和单位解析方法
  Map<String, String> _parseFloorAndUnit(String unitString) {
    // 尝试多种分割方式
    List<String> parts = [];

    // 方式1: 两个空格分割 (例如: "02樓  B")
    if (unitString.contains('  ')) {
      parts = unitString.split('  ');
    }
    // 方式2: 一个空格分割 (例如: "G楼 01")
    else if (unitString.contains(' ')) {
      parts = unitString.split(' ');
    }
    // 方式3: 查找"樓"字作为分隔符 (例如: "G楼01")
    else if (unitString.contains('樓')) {
      final floorIndex = unitString.indexOf('樓');
      if (floorIndex != -1) {
        final floor = unitString.substring(0, floorIndex + 1);
        final unit = unitString.substring(floorIndex + 1);
        parts = [floor, unit];
      }
    }
    // 方式4: 查找数字作为分隔符 (例如: "G楼01")
    else {
      // 查找第一个数字的位置
      int? firstDigitIndex;
      for (int i = 0; i < unitString.length; i++) {
        if (unitString[i].contains(RegExp(r'[0-9]'))) {
          firstDigitIndex = i;
          break;
        }
      }

      if (firstDigitIndex != null) {
        final floor = unitString.substring(0, firstDigitIndex);
        final unit = unitString.substring(firstDigitIndex);
        parts = [floor, unit];
      }
    }

    if (parts.length >= 2) {
      final floor = parts[0].trim();
      final unit = parts[1].trim();
      return {'floor': floor, 'unit': unit};
    } else {
      return {'floor': '', 'unit': ''};
    }
  }

  ///5, 判断是否有数据
  bool get hasData => _rawArrearData.isNotEmpty;

  ///6, 获取目标ismartId（优先使用正确的ismartId，否则使用固定备选值）
  String _getTargetIsmartId() {
    final correctIsmartId = _appDataProvider.settingsModel?.building.ismartId;

    // 详细调试日志
    _logger.i('🔍 [调试ismartId获取]');
    _logger.i('  - AppDataProvider已登录: ${_appDataProvider.isLoggedIn}');
    _logger.i('  - SettingsModel存在: ${_appDataProvider.settingsModel != null}');
    _logger.i(
        '  - Building信息存在: ${_appDataProvider.settingsModel?.building != null}');
    _logger.i('  - ismartId值: $correctIsmartId');
    _logger.i('  - ismartId长度: ${correctIsmartId?.length ?? 0}');
    _logger.i('  - ismartId非空: ${correctIsmartId?.isNotEmpty ?? false}');

    final targetId = (correctIsmartId != null && correctIsmartId.isNotEmpty)
        ? correctIsmartId
        : _fallbackIsmartId;

    if (targetId == _fallbackIsmartId) {
      _logger.w('⚠️ 使用固定备选ismartId: $targetId');
      _logger.w(
          '   原因: ${correctIsmartId == null ? 'ismartId为null' : correctIsmartId.isEmpty ? 'ismartId为空字符串' : '未知原因'}');
      _logger.w('   详细诊断:');
      _logger.w('     - AppDataProvider实例: ${_appDataProvider.runtimeType}');
      _logger.w('     - 是否已登录: ${_appDataProvider.isLoggedIn}');
      _logger.w(
          '     - SettingsModel: ${_appDataProvider.settingsModel?.runtimeType}');
      _logger.w(
          '     - Building: ${_appDataProvider.settingsModel!.building.runtimeType}');
      _logger.w(
          '     - Building name: ${_appDataProvider.settingsModel!.building.name}');
      _logger.w(
          '     - Building ismartId原始值: "${_appDataProvider.settingsModel!.building.ismartId}"');
    } else {
      _logger.i('✅ 使用正确的ismartId: $targetId');
    }

    return targetId;
  }

  /// 初始化获取欠费数据
  Future<void> initGetArrearData() async {
    _logger.i('🚀 开始初始化获取欠费数据');

    // 首先尝试从缓存加载数据
    await loadFromCache();

    // 使用强制刷新方法确保获取正确的ismartId
    await forceRefreshWithCorrectIsmartId();
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
    _logger.i('🔍 [setSelectedFloor] 设置显示楼层: "$floor"');

    // 自动选择第一个单位
    if (floor != null) {
      final units = getFloors(floor);
      _logger.i('🔍 [setSelectedFloor] 楼层 "$floor" 的所有单位: $units');

      if (units.isNotEmpty) {
        _selectedUnit = units[0];
        _logger.i('🔍 [setSelectedFloor] 自动选择第一个单位: "${units[0]}"');
      } else {
        _logger.w('⚠️ [setSelectedFloor] 楼层 "$floor" 没有找到任何单位');
      }
    }

    notifyListeners();
  }

  ///9, 设置选中的单元
  void setSelectedUnit(String? unit) {
    _selectedUnit = unit;
    _logger.i('🔍 [setSelectedUnit] 设置单元: "$unit"');
    notifyListeners();
  }

  ///6, 设置欠费数据
  void setArrearage(List<Map<String, dynamic>> records) {
    _rawArrearData = records;
    _isCacheValid = false; // 新数据后重置缓存

    // 如果有数据但没有选中的楼层，自动选择第一个（仅用于UI显示）
    if (_rawArrearData.isNotEmpty && _selectedFloor == null) {
      final firstFloor = buildings.isNotEmpty ? buildings[0] : null;
      if (firstFloor != null) {
        setSelectedFloor(firstFloor);
      }
    }

    notifyListeners();
  }

  /// 构建并缓存楼层、单位及记录映射，避免重复解析
  void _buildCache() {
    _cachedBuildings.clear();
    _cachedFloorUnits.clear();
    _cachedArrearMap.clear();
    final floorSet = <String>{};
    final floorUnitsMap = <String, Set<String>>{};
    for (var record in _rawArrearData) {
      final unitString = record['單位']?.toString() ?? '';
      final parsed = _parseFloorAndUnit(unitString);
      final floor = parsed['floor'] ?? '';
      final unit = parsed['unit'] ?? '';
      if (floor.isNotEmpty && unit.isNotEmpty) {
        floorSet.add(floor);
        floorUnitsMap.putIfAbsent(floor, () => <String>{}).add(unit);
        _cachedArrearMap.putIfAbsent(floor, () => {})[unit] = Map.from(record)
          ..remove('單位');
      }
    }
    _cachedBuildings = floorSet.toList()..sort();
    for (var floor in _cachedBuildings) {
      final units = (floorUnitsMap[floor] ?? {}).toList()..sort();
      _cachedFloorUnits[floor] = units;
    }
    _isCacheValid = true;
  }

  ///10, 清除欠费数据
  void clearArrearage() {
    _rawArrearData = [];
    _selectedFloor = null;
    _selectedUnit = null;
    // 注意：不清除_selectedBuildingId，因为它存储的是ismartId，用于API调用
    notifyListeners();
  }

  ///13, 强制刷新并使用正确的ismartId
  Future<void> forceRefreshWithCorrectIsmartId() async {
    _logger.i('🔄 强制刷新欠费数据，使用正确的ismartId');

    // 首先测试AppDataProvider连接状态
    testAppDataProviderConnection();

    // 等待AppDataProvider完全初始化
    int attempts = 0;
    const maxAttempts = 10;

    while (attempts < maxAttempts) {
      final correctIsmartId = _appDataProvider.settingsModel?.building.ismartId;

      if (correctIsmartId != null && correctIsmartId.isNotEmpty) {
        _logger.i('✅ 获得有效ismartId: $correctIsmartId，开始刷新数据');
        await fetchArrears(reset: true, buildingId: correctIsmartId);
        return;
      }

      attempts++;
      _logger.w('⏳ 等待有效ismartId... 尝试 $attempts/$maxAttempts');
      await Future.delayed(const Duration(milliseconds: 500));
    }

    _logger.e('❌ 无法获得有效ismartId，使用备选ID');
    await fetchArrears(reset: true, buildingId: _fallbackIsmartId);
  }

  ///14, 获取当前ismartId调试信息
  Map<String, dynamic> getIsmartIdDebugInfo() {
    final correctIsmartId = _appDataProvider.settingsModel?.building.ismartId;
    final currentTargetId = _getTargetIsmartId();

    return {
      'appDataProvider_isLoggedIn': _appDataProvider.isLoggedIn,
      'settingsModel_exists': _appDataProvider.settingsModel != null,
      'building_exists': _appDataProvider.settingsModel != null,
      'building_name': _appDataProvider.settingsModel?.building.name,
      'ismartId_from_settings': correctIsmartId,
      'ismartId_length': correctIsmartId?.length ?? 0,
      'ismartId_isEmpty': correctIsmartId?.isEmpty ?? true,
      'current_target_id': currentTargetId,
      'using_fallback': currentTargetId == _fallbackIsmartId,
      'fallback_id': _fallbackIsmartId,
      'periodic_update_active': _isPeriodicUpdateActive,
    };
  }

  ///15, 测试AppDataProvider连接状态
  void testAppDataProviderConnection() {
    _logger.i('🔍 [测试AppDataProvider连接状态]');
    _logger.i('  AppDataProvider类型: ${_appDataProvider.runtimeType}');
    _logger.i('  AppDataProvider哈希: ${_appDataProvider.hashCode}');
    _logger.i('  是否已登录: ${_appDataProvider.isLoggedIn}');

    try {
      final settingsModel = _appDataProvider.settingsModel;
      _logger.i('  SettingsModel: ${settingsModel != null ? '存在' : '不存在'}');

      if (settingsModel != null) {
        _logger.i('    - deviceId: ${settingsModel.deviceId}');
        _logger.i('    - buildingId: ${settingsModel.buildingId}');
        _logger.i('    - status: ${settingsModel.status}');

        final building = settingsModel.building;
        _logger.i('    - Building: 存在');

        {
          _logger.i('      - id: ${building.id}');
          _logger.i('      - name: "${building.name}"');
          _logger.i('      - ismartId: "${building.ismartId}"');
          _logger.i('      - location: "${building.location}"');
          _logger.i('      - ismartId长度: ${building.ismartId.length}');
          _logger.i('      - ismartId是否为空: ${building.ismartId.isEmpty}');
        }
      }
    } catch (e, stackTrace) {
      _logger.e('❌ 测试AppDataProvider连接时出错: $e',
          error: e, stackTrace: stackTrace);
    }
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

    // 立即执行一次强制刷新，确保使用正确的ismartId
    forceRefreshWithCorrectIsmartId();

    // 设置定时器进行周期性更新
    _updateTimer = Timer.periodic(Duration(seconds: intervalSeconds), (timer) {
      if (_isPeriodicUpdateActive) {
        _logger.i('🔄 执行定期欠费数据更新...');
        final currentTargetId = _getTargetIsmartId();

        // 检查是否使用了备选ID，如果是则尝试强制刷新
        if (currentTargetId == _fallbackIsmartId) {
          _logger.w('⚠️ 检测到使用备选ID，尝试强制刷新获取正确ismartId');
          // 使用异步方式避免阻塞定时器
          Future.microtask(() => forceRefreshWithCorrectIsmartId());
        } else {
          fetchArrears(reset: false, buildingId: currentTargetId);
        }
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
    _logger.i('🔄 ArrearProvider重新初始化...');

    // 停止现有的定时更新
    stopPeriodicUpdate();

    // 重新加载缓存数据
    loadFromCache();

    // 如果AppDataProvider已登录，重新启动定时更新
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_appDataProvider.isLoggedIn) {
        _logger.i('✅ 重新初始化完成，重启欠费数据定时更新');
        final deviceSettings = _appDataProvider.deviceSettings;
        final arrearUpdateInterval =
            deviceSettings?.arrearageUpdateDuration ?? 1;
        startPeriodicUpdate(updateIntervalMinutes: arrearUpdateInterval);
      } else {
        _logger.w('⚠️ AppDataProvider未登录，跳过定时更新');
      }
    });
  }
}
