import 'package:flutter/material.dart';
import 'package:iboard_app/models/arrear_model.dart';
import 'package:iboard_app/http/api_client.dart';
import 'package:iboard_app/widgets/mainscreen/main_display/arrear_manage_table_widget.dart'; // Added import for ArrearTableWidget
import 'package:iboard_app/providers/app_data_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'package:iboard_app/widgets/mainscreen/main_display/arrear_other_table_widget.dart'; // Added import for ArrearOtherTableWidget

// 费用类型枚举
enum FeeType { management, other }

class ArrearProvider extends ChangeNotifier {
  final ApiClient _apiClient;
  final AppDataProvider _appDataProvider;

  bool _isLoading = false;
  String? _error;

  // 两种数据源
  ManagementFeeModel? _managementFeeData;
  OtherFeeModel? _otherFeeData;

  String? _ismartId;
  String? _selectedBlock;
  String? _selectedFloor;
  String? _selectedUnit;

  // 费用类型选择
  FeeType _selectedFeeType = FeeType.management;

  // 缓存键
  static const String _managementFeeCacheKey = 'management_fee_cache';
  static const String _otherFeeCacheKey = 'other_fee_cache';
  static const String _lastUpdateKey = 'arrearage_last_update';

  // 固定备选ismartId（当无法获取正确ismartId时使用）
  static const String _fallbackIsmartId = '0314100';

  ArrearProvider({
    required ApiClient apiClient,
    required AppDataProvider appDataProvider,
  })  : _apiClient = apiClient,
        _appDataProvider = appDataProvider;

  // 定时更新相关
  Timer? _updateTimer;
  bool _isPeriodicUpdateActive = false;

  // Widget缓存机制
  final Map<String, Widget> _widgetCache = {};
  final Map<String, dynamic> _cachedTableData = {};
  String? _currentDataVersion;
  bool _hasPendingUpdate = false;

  bool get isDisposed => _disposed;
  bool _disposed = false;

  bool get isPeriodicUpdateActive => _isPeriodicUpdateActive;
  bool get hasPendingUpdate => _hasPendingUpdate;
  String? get currentDataVersion => _currentDataVersion;

  @override
  void dispose() {
    stopPeriodicUpdate();
    _widgetCache.clear();
    _cachedTableData.clear();
    _disposed = true;
    super.dispose();
  }

  // Getters
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get ismartId => _ismartId;
  String? get selectedBlock => _selectedBlock; // 新增
  String? get selectedFloor => _selectedFloor;
  String? get selectedUnit => _selectedUnit;

  ///1, 获取当前选中的费用类型
  FeeType get selectedFeeType => _selectedFeeType;

  ///2, 设置费用类型
  void setFeeType(FeeType feeType) {
    _selectedFeeType = feeType;
    notifyListeners();
  }

  ///1, 获取物业管理费用数据
  ManagementFeeModel? get managementFeeData => _managementFeeData;

  ///2, 获取其他分摊费用数据
  OtherFeeModel? get otherFeeData => _otherFeeData;

  ///3, 获取所有樓座列表
  List<String> get blocks {
    final blockNames = <String>{};

    // 从物业管理费用数据中获取樓座
    if (_managementFeeData != null) {
      for (final block in _managementFeeData!.blocks) {
        // 只添加非空的樓座名称
        if (block.name.isNotEmpty) {
          blockNames.add(block.name);
        }
      }
    }

    // 从其他分摊费用数据中获取樓座
    if (_otherFeeData != null) {
      for (final block in _otherFeeData!.blocks) {
        // 只添加非空的樓座名称
        if (block.name.isNotEmpty) {
          blockNames.add(block.name);
        }
      }
    }

    // 排序：数字樓座在前，字母樓座在后
    return blockNames.toList()
      ..sort((a, b) {
        final aIsNumber = a.isNotEmpty && RegExp(r'^[0-9]').hasMatch(a[0]);
        final bIsNumber = b.isNotEmpty && RegExp(r'^[0-9]').hasMatch(b[0]);

        if (aIsNumber && !bIsNumber) return -1;
        if (!aIsNumber && bIsNumber) return 1;

        return a.compareTo(b);
      });
  }

  ///4, 获取合并后的樓层列表（用于UI显示）
  List<String> get buildings {
    final floors = <String>{};

    // 从物业管理费用数据中获取樓层
    if (_managementFeeData != null) {
      for (final block in _managementFeeData!.blocks) {
        // 如果选择了特定樓座，只显示该樓座的数据
        // 如果樓座名称为空，也包含在内（作为默认樓座）
        if (_selectedBlock == null ||
            block.name == _selectedBlock ||
            block.name.isEmpty) {
          for (final floor in block.floors) {
            floors.add(floor.name);
          }
        }
      }
    }

    // 从其他分摊费用数据中获取樓层
    if (_otherFeeData != null) {
      for (final block in _otherFeeData!.blocks) {
        // 如果选择了特定樓座，只显示该樓座的数据
        // 如果樓座名称为空，也包含在内（作为默认樓座）
        if (_selectedBlock == null ||
            block.name == _selectedBlock ||
            block.name.isEmpty) {
          for (final floor in block.floors) {
            floors.add(floor.name);
          }
        }
      }
    }

    // 优化排序：字母樓层在前，数字樓层在后
    return floors.toList()
      ..sort((a, b) {
        // 检查是否为字母樓层（第一个字符是字母）
        final aIsLetter = a.isNotEmpty && RegExp(r'^[a-zA-Z]').hasMatch(a[0]);
        final bIsLetter = b.isNotEmpty && RegExp(r'^[a-zA-Z]').hasMatch(b[0]);

        // 如果一个是字母一个是数字，字母排在前面
        if (aIsLetter && !bIsLetter) return -1;
        if (!aIsLetter && bIsLetter) return 1;

        // 如果都是字母或都是数字，按正常排序
        return a.compareTo(b);
      });
  }

  ///5, 获取指定樓层的所有單位
  List<String> getFloors(String selectedFloor) {
    final units = <String>{};

    // 从物业管理费用数据中获取單位
    if (_managementFeeData != null) {
      for (final block in _managementFeeData!.blocks) {
        // 如果选择了特定樓座，只显示该樓座的数据
        // 如果樓座名称为空，也包含在内（作为默认樓座）
        if (_selectedBlock == null ||
            block.name == _selectedBlock ||
            block.name.isEmpty) {
          for (final floor in block.floors) {
            if (floor.name == selectedFloor) {
              for (final unit in floor.units) {
                units.add(unit.name);
              }
            }
          }
        }
      }
    }

    // 从其他分摊费用数据中获取單位
    if (_otherFeeData != null) {
      for (final block in _otherFeeData!.blocks) {
        // 如果选择了特定樓座，只显示该樓座的数据
        // 如果樓座名称为空，也包含在内（作为默认樓座）
        if (_selectedBlock == null ||
            block.name == _selectedBlock ||
            block.name.isEmpty) {
          for (final floor in block.floors) {
            if (floor.name == selectedFloor) {
              for (final unit in floor.units) {
                units.add(unit.name);
              }
            }
          }
        }
      }
    }

    // 优化排序：字母單位在前，数字單位在后
    return units.toList()
      ..sort((a, b) {
        // 检查是否为字母單位（第一个字符是字母）
        final aIsLetter = a.isNotEmpty && RegExp(r'^[a-zA-Z]').hasMatch(a[0]);
        final bIsLetter = b.isNotEmpty && RegExp(r'^[a-zA-Z]').hasMatch(b[0]);

        // 如果一个是字母一个是数字，字母排在前面
        if (aIsLetter && !bIsLetter) return -1;
        if (!aIsLetter && bIsLetter) return 1;

        // 如果都是字母或都是数字，按正常排序
        return a.compareTo(b);
      });
  }

  ///5, 获取指定樓层和單位的费用记录
  Map<String, dynamic>? getFeesByUnit(
      String selectedFloor, String selectedUnit) {
    final Map<String, dynamic> result = {};

    // 获取物业管理费用
    if (_managementFeeData != null) {
      for (final block in _managementFeeData!.blocks) {
        // 如果选择了特定樓座，只显示该樓座的数据
        if (_selectedBlock == null || block.name == _selectedBlock) {
          for (final floor in block.floors) {
            if (floor.name == selectedFloor) {
              for (final unit in floor.units) {
                if (unit.name == selectedUnit) {
                  for (final bill in unit.bills) {
                    result[bill.period] = bill.value;
                  }
                }
              }
            }
          }
        }
      }
    }

    // 获取其他分摊费用
    if (_otherFeeData != null) {
      for (final block in _otherFeeData!.blocks) {
        // 如果选择了特定樓座，只显示该樓座的数据
        if (_selectedBlock == null || block.name == _selectedBlock) {
          for (final floor in block.floors) {
            if (floor.name == selectedFloor) {
              for (final unit in floor.units) {
                if (unit.name == selectedUnit) {
                  for (final bill in unit.bills) {
                    // 为其他费用添加前缀以区分
                    final key = '${bill.period} (${bill.itemId ?? "分攤費用"})';
                    result[key] = bill.value;
                  }
                }
              }
            }
          }
        }
      }
    }

    return result.isEmpty ? null : result;
  }

  ///5.1, 根据费用类型获取指定樓层和單位的费用记录
  Map<String, dynamic>? getFeesByUnitAndType(
      String selectedFloor, String selectedUnit, FeeType feeType) {
    final Map<String, dynamic> result = {};

    if (feeType == FeeType.management && _managementFeeData != null) {
      // 获取物业管理费用
      for (final block in _managementFeeData!.blocks) {
        // 如果选择了特定樓座，只显示该樓座的数据
        if (_selectedBlock == null || block.name == _selectedBlock) {
          for (final floor in block.floors) {
            if (floor.name == selectedFloor) {
              for (final unit in floor.units) {
                if (unit.name == selectedUnit) {
                  for (final bill in unit.bills) {
                    result[bill.period] = bill.value;
                  }
                }
              }
            }
          }
        }
      }
    } else if (feeType == FeeType.other && _otherFeeData != null) {
      // 获取其他分摊费用
      for (final block in _otherFeeData!.blocks) {
        // 如果选择了特定樓座，只显示该樓座的数据
        if (_selectedBlock == null || block.name == _selectedBlock) {
          for (final floor in block.floors) {
            if (floor.name == selectedFloor) {
              for (final unit in floor.units) {
                if (unit.name == selectedUnit) {
                  for (final bill in unit.bills) {
                    result[bill.period] = bill.value;
                  }
                }
              }
            }
          }
        }
      }
    }

    return result.isEmpty ? null : result;
  }

  ///25, 根据费用类型获取指定樓层和單位的完整费用记录（包含所有字段）
  List<Bill>? getDetailedFeesByUnitAndType(
      String selectedFloor, String selectedUnit, FeeType feeType) {
    final List<Bill> result = [];

    if (feeType == FeeType.management && _managementFeeData != null) {
      // 获取物业管理费用
      for (final block in _managementFeeData!.blocks) {
        // 如果选择了特定樓座，只显示该樓座的数据
        if (_selectedBlock == null || block.name == _selectedBlock) {
          for (final floor in block.floors) {
            if (floor.name == selectedFloor) {
              for (final unit in floor.units) {
                if (unit.name == selectedUnit) {
                  result.addAll(unit.bills);
                }
              }
            }
          }
        }
      }
    } else if (feeType == FeeType.other && _otherFeeData != null) {
      // 获取其他分摊费用
      for (final block in _otherFeeData!.blocks) {
        // 如果选择了特定樓座，只显示该樓座的数据
        if (_selectedBlock == null || block.name == _selectedBlock) {
          for (final floor in block.floors) {
            if (floor.name == selectedFloor) {
              for (final unit in floor.units) {
                if (unit.name == selectedUnit) {
                  result.addAll(unit.bills);
                }
              }
            }
          }
        }
      }
    }

    return result.isEmpty ? null : result;
  }

  ///6, 获取当前选中單位的费用记录
  Map<String, dynamic>? get currentArrearage {
    if (_selectedFloor == null || _selectedUnit == null) {
      return null;
    }
    return getFeesByUnitAndType(
        _selectedFloor!, _selectedUnit!, _selectedFeeType);
  }

  ///26, 获取当前选中單位的详细费用记录（包含所有字段）
  List<Bill>? get currentDetailedArrearage {
    if (_selectedFloor == null || _selectedUnit == null) {
      return null;
    }
    return getDetailedFeesByUnitAndType(
        _selectedFloor!, _selectedUnit!, _selectedFeeType);
  }

  ///7, 检查指定樓层和單位是否有其他分摊费用
  bool hasOtherFees(String floor, String unit) {
    if (_otherFeeData == null) return false;

    for (final block in _otherFeeData!.blocks) {
      // 如果选择了特定樓座，只检查该樓座的数据
      if (_selectedBlock == null || block.name == _selectedBlock) {
        for (final floorData in block.floors) {
          if (floorData.name == floor) {
            for (final unitData in floorData.units) {
              if (unitData.name == unit) {
                return unitData.bills.isNotEmpty;
              }
            }
          }
        }
      }
    }
    return false;
  }

  ///7.1, 检查指定樓层是否有其他分摊费用（用于樓层选择器）
  bool hasOtherFeesForFloor(String floor) {
    if (_otherFeeData == null) return false;

    for (final block in _otherFeeData!.blocks) {
      // 如果选择了特定樓座，只检查该樓座的数据
      if (_selectedBlock == null || block.name == _selectedBlock) {
        for (final floorData in block.floors) {
          if (floorData.name == floor) {
            // 检查该樓层下是否有任何單位有其他分摊费用
            for (final unitData in floorData.units) {
              if (unitData.bills.isNotEmpty) {
                return true;
              }
            }
          }
        }
      }
    }
    return false;
  }

  ///8, 检查是否有数据
  bool get hasData => _managementFeeData != null || _otherFeeData != null;

  ///8.1, 检查是否有管理费用数据
  bool get hasManagementFeeData => _managementFeeData != null;

  ///8.2, 检查是否有其他费用数据
  bool get hasOtherFeeData => _otherFeeData != null;

  ///8.3, 检查其他费用数据是否为空（没有实际的费用记录）
  bool get isOtherFeeDataEmpty {
    if (_otherFeeData == null) return true;

    for (final block in _otherFeeData!.blocks) {
      // 如果选择了特定樓座，只检查该樓座的数据
      if (_selectedBlock == null || block.name == _selectedBlock) {
        for (final floor in block.floors) {
          for (final unit in floor.units) {
            if (unit.bills.isNotEmpty) {
              return false; // 找到有费用的單位，返回false
            }
          }
        }
      }
    }
    return true; // 所有單位都没有费用，返回true
  }

  ///38, 是否存在任意其他費用記錄（忽略樓座選擇，用於輪播判斷）
  bool get hasAnyOtherFeeRecords {
    if (_otherFeeData == null) return false;
    for (final block in _otherFeeData!.blocks) {
      for (final floor in block.floors) {
        for (final unit in floor.units) {
          if (unit.bills.isNotEmpty) {
            return true;
          }
        }
      }
    }
    return false;
  }

  ///39, 當前選擇是否有數據（基於樓層+單位+費用類型）
  bool get hasDataForCurrentSelection {
    if (_selectedFloor == null || _selectedUnit == null) return false;
    if (_selectedFeeType == FeeType.management) {
      final map = getFeesByUnitAndType(
          _selectedFloor!, _selectedUnit!, FeeType.management);
      return map != null && map.isNotEmpty;
    } else {
      final list = getDetailedFeesByUnitAndType(
          _selectedFloor!, _selectedUnit!, FeeType.other);
      return list != null && list.isNotEmpty;
    }
  }

  ///9a，處理欠費API失敗的回退邏輯
  Future<void> _handleArrearFallback() async {
    if (hasData) {
      _hasPendingUpdate = true;
    } else {
      await loadFromCache();
      if (hasData) {
        _hasPendingUpdate = true;
      }
    }
  }

  ///9, 从缓存加载数据
  Future<void> loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final managementFeeCache = prefs.getString(_managementFeeCacheKey);
      if (managementFeeCache != null) {
        final decodedData = json.decode(managementFeeCache);
        _managementFeeData = ManagementFeeModel.fromJson(decodedData);
      }

      final otherFeeCache = prefs.getString(_otherFeeCacheKey);
      if (otherFeeCache != null) {
        final decodedData = json.decode(otherFeeCache);
        _otherFeeData = OtherFeeModel.fromJson(decodedData);
      }

      if (blocks.isNotEmpty && _selectedBlock == null) {
        setSelectedBlock(blocks[0]);
      }

      notifyListeners();
    } catch (e) {
      _error = '從緩存加載數據失敗';
    }
  }

  ///10, 保存数据到缓存
  Future<void> saveToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().toIso8601String();

      if (_managementFeeData != null) {
        final jsonData = json.encode(_managementFeeData!.toJson());
        await prefs.setString(_managementFeeCacheKey, jsonData);
      }

      if (_otherFeeData != null) {
        final jsonData = json.encode(_otherFeeData!.toJson());
        await prefs.setString(_otherFeeCacheKey, jsonData);
      }

      await prefs.setString(_lastUpdateKey, now);
    } catch (e) {
      _error = '保存緩存失敗';
    }
  }

  ///11, 获取缓存更新时间
  Future<String?> getLastUpdateTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_lastUpdateKey);
    } catch (e) {
      return null;
    }
  }

  ///12, 清除缓存
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_managementFeeCacheKey);
      await prefs.remove(_otherFeeCacheKey);
      await prefs.remove(_lastUpdateKey);
    } catch (e) {
      _error = '清除緩存失敗';
    }
  }

  ///13, 检查缓存状态
  Future<Map<String, dynamic>> getCacheStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final managementFeeCache = prefs.getString(_managementFeeCacheKey);
      final otherFeeCache = prefs.getString(_otherFeeCacheKey);
      final lastUpdate = prefs.getString(_lastUpdateKey);

      return {
        'hasManagementFeeCache': managementFeeCache != null,
        'hasOtherFeeCache': otherFeeCache != null,
        'lastUpdate': lastUpdate,
        'managementFeeDataExists': _managementFeeData != null,
        'otherFeeDataExists': _otherFeeData != null,
      };
    } catch (e) {
      return {
        'hasManagementFeeCache': false,
        'hasOtherFeeCache': false,
        'lastUpdate': null,
        'managementFeeDataExists': false,
        'otherFeeDataExists': false,
        'error': e.toString(),
      };
    }
  }

  ///14, 获取目标ismartId
  String _getTargetIsmartId() {
    final correctIsmartId = _appDataProvider.settingsModel?.building.ismartId;
    return (correctIsmartId != null && correctIsmartId.isNotEmpty)
        ? correctIsmartId
        : _fallbackIsmartId;
  }

  ///15, 初始化获取费用数据
  Future<void> initGetFeeData() async {
    await loadFromCache();
    await forceRefreshWithCorrectIsmartId();
  }

  ///16, 获取费用数据
  Future<void> fetchFeeData({bool reset = false, String? buildingId}) async {
    if (_isLoading) {
      return;
    }

    _isLoading = true;
    _error = null;

    if (reset) {
      _managementFeeData = null;
      _otherFeeData = null;
    }

    notifyListeners();

    try {
      String targetBuildingId = buildingId ?? _getTargetIsmartId();

      // 并行获取两种数据
      final results = await Future.wait([
        _apiClient.getManagementFeeStatus(buildingId: targetBuildingId),
        _apiClient.getOtherFeeStatus(buildingId: targetBuildingId),
      ]);

      _managementFeeData = ManagementFeeModel.fromJson(results[0]);
      _otherFeeData = OtherFeeModel.fromJson(results[1]);
      await saveToCache();
      _updateDataVersion();
      _hasPendingUpdate = true;
      _error = null;
    } catch (e) {
      await _handleArrearFallback();

      if (e.toString().contains('Building ID') ||
          e.toString().contains('只能包含数字和英文字母') ||
          e.toString().contains('格式无效')) {
        _error = '樓宇ID格式错误：只能包含数字和英文字母';
      } else {
        if (!hasData) {
          _error = 'API失敗且無緩存數據可用';
        } else {
          _error = null;
        }
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  ///17, 刷新费用数据
  Future<void> refreshFeeData() async {
    await fetchFeeData(reset: true);
  }

  ///18, 设置樓宇ismartId
  void setIsmartId(String? buildingId) {
    _ismartId = buildingId;
    _selectedBlock = null;
    _selectedFloor = null;
    _selectedUnit = null;

    if (buildingId != null) {
      final blockList = blocks;
      if (blockList.isNotEmpty) {
        setSelectedBlock(blockList[0]);
      }
    }

    notifyListeners();
  }

  ///19, 设置选中的樓座
  void setSelectedBlock(String? block) {
    _selectedBlock = block;
    _selectedFloor = null;
    _selectedUnit = null;

    if (block != null) {
      // 自动选择第一个樓层
      final floorList = buildings;
      if (floorList.isNotEmpty) {
        setSelectedFloor(floorList[0]);
      }
    }

    notifyListeners();
  }

  ///20, 设置选中的樓层
  void setSelectedFloor(String? floor) {
    _selectedFloor = floor;
    _selectedUnit = null;
    if (floor != null) {
      final units = getFloors(floor);
      if (units.isNotEmpty) {
        _selectedUnit = units[0];
      }
    }

    notifyListeners();
  }

  ///21, 设置选中的單元
  void setSelectedUnit(String? unit) {
    _selectedUnit = unit;
    notifyListeners();
  }

  ///21, 强制刷新并使用正确的ismartId
  Future<void> forceRefreshWithCorrectIsmartId() async {
    int attempts = 0;
    const maxAttempts = 10;

    while (attempts < maxAttempts) {
      final correctIsmartId = _appDataProvider.settingsModel?.building.ismartId;

      if (correctIsmartId != null && correctIsmartId.isNotEmpty) {
        await fetchFeeData(reset: true, buildingId: correctIsmartId);
        return;
      }

      attempts++;
      await Future.delayed(const Duration(milliseconds: 500));
    }

    await fetchFeeData(reset: true, buildingId: _fallbackIsmartId);
  }

  ///22, 开始定期更新费用数据
  void startPeriodicUpdate({int? updateIntervalMinutes}) {
    if (_isPeriodicUpdateActive) {
      return;
    }

    final intervalMinutes = updateIntervalMinutes ?? 1;
    final intervalSeconds = intervalMinutes * 60;
    _isPeriodicUpdateActive = true;
    debugPrint('[ArrearProvider] ⏰ 启动欠费数据定时更新，间隔: ${intervalMinutes}分钟');

    forceRefreshWithCorrectIsmartId();

    _updateTimer = Timer.periodic(Duration(seconds: intervalSeconds), (timer) {
      if (_isPeriodicUpdateActive) {
        debugPrint('[ArrearProvider] 🔄 执行定时欠费数据更新');
        final currentTargetId = _getTargetIsmartId();

        if (currentTargetId == _fallbackIsmartId) {
          Future.microtask(() => forceRefreshWithCorrectIsmartId());
        } else {
          fetchFeeData(reset: false, buildingId: currentTargetId);
        }
      } else {
        timer.cancel();
      }
    });
  }

  ///23, 停止定期更新
  void stopPeriodicUpdate() {
    if (_updateTimer != null) {
      _updateTimer!.cancel();
      _updateTimer = null;
    }
    _isPeriodicUpdateActive = false;
    debugPrint('[ArrearProvider] ⏹️ 停止欠费数据定时更新');
  }

  ///24, 重新初始化Provider
  void reinitialize() {
    stopPeriodicUpdate();
    loadFromCache();

    Future.delayed(const Duration(milliseconds: 100), () {
      if (_appDataProvider.isLoggedIn) {
        final deviceSettings = _appDataProvider.deviceSettings;
        final arrearUpdateInterval =
            deviceSettings?.arrearageUpdateDuration ?? 1;
        startPeriodicUpdate(updateIntervalMinutes: arrearUpdateInterval);
      }
    });
  }

  ///27, 更新数据版本标识
  void _updateDataVersion() {
    _currentDataVersion = DateTime.now().millisecondsSinceEpoch.toString();
  }

  ///28, 获取表格数据（缓存版本）
  List<Map<String, dynamic>> getTableData() {
    final List<Map<String, dynamic>> tableData = [];

    // 从物业管理费用数据构建表格数据
    if (_managementFeeData != null) {
      for (final block in _managementFeeData!.blocks) {
        // 如果选择了特定樓座，只显示该樓座的数据
        if (_selectedBlock == null || block.name == _selectedBlock) {
          for (final floor in block.floors) {
            for (final unit in floor.units) {
              final Map<String, dynamic> rowData = {
                '單位': _formatUnitDisplay(block.name, floor.name, unit.name),
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
    }

    return tableData;
  }

  ///32, 格式化單位显示（樓座+樓层+單元）
  String _formatUnitDisplay(
      String blockName, String floorName, String unitName) {
    if (blockName.isEmpty) {
      // 如果樓座名称为空，显示：XX樓XX室
      return '${floorName}樓${unitName}室';
    } else {
      // 显示樓座+樓层+單元，例如：01座01樓A室
      return '${blockName}座${floorName}樓${unitName}室';
    }
  }

  ///33, 获取当前选中單位的完整显示名称
  String? get currentUnitDisplayName {
    if (_selectedFloor == null || _selectedUnit == null) {
      return null;
    }
    // 如果选中的樓座名称为空，不显示樓座号
    final blockName = _selectedBlock ?? '';
    return _formatUnitDisplay(blockName, _selectedFloor!, _selectedUnit!);
  }

  ///34, 获取当前选中樓座的显示名称
  String? get currentBlockDisplayName {
    if (_selectedBlock == null || _selectedBlock!.isEmpty) {
      return null;
    }
    return '${_selectedBlock}座';
  }

  ///35, 检查是否应该显示樓座选择器
  bool get shouldShowBlockSelector {
    // 只有当有多个非空名称的樓座时才显示选择器
    return blocks.length > 1;
  }

  ///29, 创建管理费用表單Widget（缓存版本）
  Widget createArrearManagementTableWidget({
    required VoidCallback? onHomeButtonPressed,
    required bool isInCarouselMode,
    required Function(int totalPages)? onPaginationComplete,
    required Function(int totalPages)? onPaginationStart,
  }) {
    final dataVersion = _currentDataVersion ?? 'initial';
    final key = 'management_fee_table_$dataVersion';

    if (_widgetCache.containsKey(key)) {
      return _widgetCache[key]!;
    }

    final widget = ArrearManagementTableWidget(
      key: ValueKey(key),
      onHomeButtonPressed: onHomeButtonPressed,
      isInCarouselMode: isInCarouselMode,
      onPaginationComplete: onPaginationComplete,
      onPaginationStart: onPaginationStart,
    );

    _widgetCache[key] = widget;
    _cachedTableData[key] = getTableData();
    _cleanupOldCache();

    return widget;
  }

  ///30, 清理旧缓存
  void _cleanupOldCache() {
    if (_widgetCache.length > 2) {
      final keys = _widgetCache.keys.toList()..sort();
      final keysToRemove = keys.take(keys.length - 2);

      for (final key in keysToRemove) {
        _widgetCache.remove(key);
        _cachedTableData.remove(key);
      }
    }
  }

  ///31, 标记数据更新完成（由ArrearTableWidget调用）
  void markUpdateApplied() {
    _hasPendingUpdate = false;
  }

  ///36, 获取其他费用表格数据（缓存版本）
  List<Map<String, dynamic>> getOtherTableData() {
    final List<Map<String, dynamic>> tableData = [];

    // 从其他分摊费用数据构建表格数据
    if (_otherFeeData != null) {
      for (final block in _otherFeeData!.blocks) {
        // 如果选择了特定樓座，只显示该樓座的数据
        if (_selectedBlock == null || block.name == _selectedBlock) {
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
    }

    return tableData;
  }

  ///37, 创建其他费用表單Widget（缓存版本）
  Widget createArrearOtherTableWidget({
    required VoidCallback? onHomeButtonPressed,
    required bool isInCarouselMode,
    required Function(int totalPages)? onPaginationComplete,
    required Function(int totalPages)? onPaginationStart,
  }) {
    final dataVersion = _currentDataVersion ?? 'initial';
    final key = 'other_fee_table_$dataVersion';

    if (_widgetCache.containsKey(key)) {
      return _widgetCache[key]!;
    }

    final widget = ArrearOtherTableWidget(
      key: ValueKey(key),
      onHomeButtonPressed: onHomeButtonPressed,
      isInCarouselMode: isInCarouselMode,
      onPaginationComplete: onPaginationComplete,
      onPaginationStart: onPaginationStart,
    );

    _widgetCache[key] = widget;
    _cachedTableData[key] = getOtherTableData();
    _cleanupOldCache();

    return widget;
  }
}
