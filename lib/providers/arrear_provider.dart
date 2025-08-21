import 'package:flutter/material.dart';
import 'package:iboard_app/models/arrear_model.dart';
import 'package:iboard_app/http/api_client.dart';
import 'package:iboard_app/providers/app_data_provider.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';

// 费用类型枚举
enum FeeType { management, other }

class ArrearProvider extends ChangeNotifier {
  final Logger _logger = Logger();
  final ApiClient _apiClient;
  final AppDataProvider _appDataProvider;

  bool _isLoading = false;
  String? _error;

  // 两种数据源
  ManagementFeeModel? _managementFeeData; // 物业管理费用数据
  OtherFeeModel? _otherFeeData; // 其他分摊费用数据

  String? _selectedBuildingId; // 实际存储的是ismartId，用于API调用
  String? _selectedFloor; // 存储用户选择的楼层，用于UI显示和数据筛选
  String? _selectedUnit;

  // 费用类型选择
  FeeType _selectedFeeType = FeeType.management; // 默认选中管理费用

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
  String? get selectedBuildingId => _selectedBuildingId;
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

  ///3, 获取合并后的楼层列表（用于UI显示）
  List<String> get buildings {
    final floors = <String>{};

    // 从物业管理费用数据中获取楼层
    if (_managementFeeData != null) {
      for (final block in _managementFeeData!.blocks) {
        for (final floor in block.floors) {
          floors.add(floor.name);
        }
      }
    }

    // 从其他分摊费用数据中获取楼层
    if (_otherFeeData != null) {
      for (final block in _otherFeeData!.blocks) {
        for (final floor in block.floors) {
          floors.add(floor.name);
        }
      }
    }

    // 优化排序：字母楼层在前，数字楼层在后
    return floors.toList()
      ..sort((a, b) {
        // 检查是否为字母楼层（第一个字符是字母）
        final aIsLetter = a.isNotEmpty && RegExp(r'^[a-zA-Z]').hasMatch(a[0]);
        final bIsLetter = b.isNotEmpty && RegExp(r'^[a-zA-Z]').hasMatch(b[0]);

        // 如果一个是字母一个是数字，字母排在前面
        if (aIsLetter && !bIsLetter) return -1;
        if (!aIsLetter && bIsLetter) return 1;

        // 如果都是字母或都是数字，按正常排序
        return a.compareTo(b);
      });
  }

  ///4, 获取指定楼层的所有单位
  List<String> getFloors(String selectedFloor) {
    final units = <String>{};

    // 从物业管理费用数据中获取单位
    if (_managementFeeData != null) {
      for (final block in _managementFeeData!.blocks) {
        for (final floor in block.floors) {
          if (floor.name == selectedFloor) {
            for (final unit in floor.units) {
              units.add(unit.name);
            }
          }
        }
      }
    }

    // 从其他分摊费用数据中获取单位
    if (_otherFeeData != null) {
      for (final block in _otherFeeData!.blocks) {
        for (final floor in block.floors) {
          if (floor.name == selectedFloor) {
            for (final unit in floor.units) {
              units.add(unit.name);
            }
          }
        }
      }
    }

    // 优化排序：字母单位在前，数字单位在后
    return units.toList()
      ..sort((a, b) {
        // 检查是否为字母单位（第一个字符是字母）
        final aIsLetter = a.isNotEmpty && RegExp(r'^[a-zA-Z]').hasMatch(a[0]);
        final bIsLetter = b.isNotEmpty && RegExp(r'^[a-zA-Z]').hasMatch(b[0]);

        // 如果一个是字母一个是数字，字母排在前面
        if (aIsLetter && !bIsLetter) return -1;
        if (!aIsLetter && bIsLetter) return 1;

        // 如果都是字母或都是数字，按正常排序
        return a.compareTo(b);
      });
  }

  ///5, 获取指定楼层和单位的费用记录
  Map<String, dynamic>? getFeesByUnit(
      String selectedFloor, String selectedUnit) {
    final Map<String, dynamic> result = {};

    // 获取物业管理费用
    if (_managementFeeData != null) {
      for (final block in _managementFeeData!.blocks) {
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

    // 获取其他分摊费用
    if (_otherFeeData != null) {
      for (final block in _otherFeeData!.blocks) {
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

    return result.isEmpty ? null : result;
  }

  ///5.1, 根据费用类型获取指定楼层和单位的费用记录
  Map<String, dynamic>? getFeesByUnitAndType(
      String selectedFloor, String selectedUnit, FeeType feeType) {
    final Map<String, dynamic> result = {};

    if (feeType == FeeType.management && _managementFeeData != null) {
      // 获取物业管理费用
      for (final block in _managementFeeData!.blocks) {
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
    } else if (feeType == FeeType.other && _otherFeeData != null) {
      // 获取其他分摊费用
      for (final block in _otherFeeData!.blocks) {
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

    return result.isEmpty ? null : result;
  }

  ///25, 根据费用类型获取指定楼层和单位的完整费用记录（包含所有字段）
  List<Bill>? getDetailedFeesByUnitAndType(
      String selectedFloor, String selectedUnit, FeeType feeType) {
    final List<Bill> result = [];

    if (feeType == FeeType.management && _managementFeeData != null) {
      // 获取物业管理费用
      for (final block in _managementFeeData!.blocks) {
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
    } else if (feeType == FeeType.other && _otherFeeData != null) {
      // 获取其他分摊费用
      for (final block in _otherFeeData!.blocks) {
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

    return result.isEmpty ? null : result;
  }

  ///6, 获取当前选中单位的费用记录
  Map<String, dynamic>? get currentArrearage {
    if (_selectedFloor == null || _selectedUnit == null) {
      return null;
    }
    return getFeesByUnitAndType(
        _selectedFloor!, _selectedUnit!, _selectedFeeType);
  }

  ///26, 获取当前选中单位的详细费用记录（包含所有字段）
  List<Bill>? get currentDetailedArrearage {
    if (_selectedFloor == null || _selectedUnit == null) {
      return null;
    }
    return getDetailedFeesByUnitAndType(
        _selectedFloor!, _selectedUnit!, _selectedFeeType);
  }

  ///7, 检查指定楼层和单位是否有其他分摊费用
  bool hasOtherFees(String floor, String unit) {
    if (_otherFeeData == null) return false;

    for (final block in _otherFeeData!.blocks) {
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
    return false;
  }

  ///7.1, 检查指定楼层是否有其他分摊费用（用于楼层选择器）
  bool hasOtherFeesForFloor(String floor) {
    if (_otherFeeData == null) return false;

    for (final block in _otherFeeData!.blocks) {
      for (final floorData in block.floors) {
        if (floorData.name == floor) {
          // 检查该楼层下是否有任何单位有其他分摊费用
          for (final unitData in floorData.units) {
            if (unitData.bills.isNotEmpty) {
              return true;
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
      for (final floor in block.floors) {
        for (final unit in floor.units) {
          if (unit.bills.isNotEmpty) {
            return false; // 找到有费用的单位，返回false
          }
        }
      }
    }
    return true; // 所有单位都没有费用，返回true
  }

  ///9, 从缓存加载数据
  Future<void> loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 加载物业管理费用数据
      final managementFeeCache = prefs.getString(_managementFeeCacheKey);
      if (managementFeeCache != null) {
        final decodedData = json.decode(managementFeeCache);
        _managementFeeData = ManagementFeeModel.fromJson(decodedData);
        _logger.i('✅ 从缓存加载物业管理费用数据成功');
      }

      // 加载其他分摊费用数据
      final otherFeeCache = prefs.getString(_otherFeeCacheKey);
      if (otherFeeCache != null) {
        final decodedData = json.decode(otherFeeCache);
        _otherFeeData = OtherFeeModel.fromJson(decodedData);
        _logger.i('✅ 从缓存加载其他分摊费用数据成功');
      }

      // 自动选择第一个楼层（仅用于UI显示）
      if (buildings.isNotEmpty && _selectedFloor == null) {
        setSelectedFloor(buildings[0]);
      }

      notifyListeners();
    } catch (e) {
      _logger.e('❌ 从缓存加载数据失败: $e');
    }
  }

  ///10, 保存数据到缓存
  Future<void> saveToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().toIso8601String();

      // 保存物业管理费用数据
      if (_managementFeeData != null) {
        final jsonData = json.encode(_managementFeeData!.toJson());
        await prefs.setString(_managementFeeCacheKey, jsonData);
        _logger.i('✅ 物业管理费用数据已保存到缓存');
      }

      // 保存其他分摊费用数据
      if (_otherFeeData != null) {
        final jsonData = json.encode(_otherFeeData!.toJson());
        await prefs.setString(_otherFeeCacheKey, jsonData);
        _logger.i('✅ 其他分摊费用数据已保存到缓存');
      }

      await prefs.setString(_lastUpdateKey, now);
      _logger.i('📅 缓存更新时间: $now');
    } catch (e) {
      _logger.e('❌ 保存数据到缓存失败: $e');
    }
  }

  ///11, 获取缓存更新时间
  Future<String?> getLastUpdateTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_lastUpdateKey);
    } catch (e) {
      _logger.e('❌ 获取缓存更新时间失败: $e');
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

      _logger.i('🗑️ 费用数据缓存已清除');
    } catch (e) {
      _logger.e('❌ 清除缓存失败: $e');
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
      _logger.e('❌ 获取缓存状态失败: $e');
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
    final targetId = (correctIsmartId != null && correctIsmartId.isNotEmpty)
        ? correctIsmartId
        : _fallbackIsmartId;

    if (targetId == _fallbackIsmartId) {
      _logger.w('⚠️ 使用固定备选ismartId: $targetId');
    } else {
      _logger.i('✅ 使用正确的ismartId: $targetId');
    }

    return targetId;
  }

  ///15, 初始化获取费用数据
  Future<void> initGetFeeData() async {
    _logger.i('🚀 开始初始化获取费用数据');

    // 首先尝试从缓存加载数据
    await loadFromCache();

    // 使用强制刷新方法确保获取正确的ismartId
    await forceRefreshWithCorrectIsmartId();
  }

  ///16, 获取费用数据
  Future<void> fetchFeeData({bool reset = false, String? buildingId}) async {
    if (_isLoading) {
      _logger.w('费用数据正在加载中，跳过重复请求');
      return;
    }

    _isLoading = true;
    _error = null;

    if (reset) {
      _managementFeeData = null;
      _otherFeeData = null;
      _logger.i('重置费用数据');
    }

    notifyListeners();

    try {
      String targetBuildingId = buildingId ?? _getTargetIsmartId();
      _logger.i('调用API获取费用数据，使用ismartId: $targetBuildingId');

      // 并行获取两种数据
      final results = await Future.wait([
        _apiClient.getManagementFeeStatus(buildingId: targetBuildingId),
        _apiClient.getOtherFeeStatus(buildingId: targetBuildingId),
      ]);

      // 处理物业管理费用数据
      _managementFeeData = ManagementFeeModel.fromJson(results[0]);
      _logger.i('✅ 成功获取物业管理费用数据');

      // 处理其他分摊费用数据
      _otherFeeData = OtherFeeModel.fromJson(results[1]);
      _logger.i('✅ 成功获取其他分摊费用数据');

      // 保存到缓存
      await saveToCache();

      _error = null;
      _logger.i('✅ 所有费用数据获取完成');
    } catch (e, stackTrace) {
      _logger.e('获取费用数据时发生异常: $e', error: e, stackTrace: stackTrace);

      if (e.toString().contains('Building ID') ||
          e.toString().contains('只能包含数字和英文字母') ||
          e.toString().contains('格式无效')) {
        _error = '楼宇ID格式错误：只能包含数字和英文字母';
      } else {
        if (hasData) {
          _logger.i('网络请求失败，保持现有缓存数据');
        } else {
          _logger.i('网络请求失败，且无缓存数据');
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

  ///18, 设置楼宇ismartId
  void setSelectedBuildingId(String? buildingId) {
    _selectedBuildingId = buildingId;
    _selectedFloor = null;
    _selectedUnit = null;
    _logger.i('设置楼宇ismartId: $buildingId');

    if (buildingId != null) {
      final floorList = buildings;
      if (floorList.isNotEmpty) {
        _selectedFloor = floorList[0];
        _logger.i('自动选择第一个楼层: ${floorList[0]}');

        // 然后为这个楼层选择第一个单位
        final units = getFloors(_selectedFloor!);
        if (units.isNotEmpty) {
          _selectedUnit = units[0];
          _logger.i('自动选择第一个单位: ${units[0]}');
        }
      }
    }

    notifyListeners();
  }

  ///19, 设置选中的楼层
  void setSelectedFloor(String? floor) {
    _selectedFloor = floor;
    _selectedUnit = null;
    _logger.i('🔍 [setSelectedFloor] 设置显示楼层: "$floor"');

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

  ///20, 设置选中的单元
  void setSelectedUnit(String? unit) {
    _selectedUnit = unit;
    _logger.i('🔍 [setSelectedUnit] 设置单元: "$unit"');
    notifyListeners();
  }

  ///21, 强制刷新并使用正确的ismartId
  Future<void> forceRefreshWithCorrectIsmartId() async {
    _logger.i('🔄 强制刷新费用数据，使用正确的ismartId');

    int attempts = 0;
    const maxAttempts = 10;

    while (attempts < maxAttempts) {
      final correctIsmartId = _appDataProvider.settingsModel?.building.ismartId;

      if (correctIsmartId != null && correctIsmartId.isNotEmpty) {
        _logger.i('✅ 获得有效ismartId: $correctIsmartId，开始刷新数据');
        await fetchFeeData(reset: true, buildingId: correctIsmartId);
        return;
      }

      attempts++;
      _logger.w('⏳ 等待有效ismartId... 尝试 $attempts/$maxAttempts');
      await Future.delayed(const Duration(milliseconds: 500));
    }

    _logger.e('❌ 无法获得有效ismartId，使用备选ID');
    await fetchFeeData(reset: true, buildingId: _fallbackIsmartId);
  }

  ///22, 开始定期更新费用数据
  void startPeriodicUpdate({int? updateIntervalMinutes}) {
    if (_isPeriodicUpdateActive) {
      _logger.i('Periodic fee update is already active.');
      return;
    }

    final intervalMinutes = updateIntervalMinutes ?? 1;
    final intervalSeconds = intervalMinutes * 60;
    _logger.i(
        'Starting periodic fee update with interval: $intervalMinutes minutes ($intervalSeconds seconds)');

    _isPeriodicUpdateActive = true;

    // 立即执行一次强制刷新
    forceRefreshWithCorrectIsmartId();

    // 设置定时器进行周期性更新
    _updateTimer = Timer.periodic(Duration(seconds: intervalSeconds), (timer) {
      if (_isPeriodicUpdateActive) {
        _logger.i('🔄 执行定期费用数据更新...');
        final currentTargetId = _getTargetIsmartId();

        if (currentTargetId == _fallbackIsmartId) {
          _logger.w('⚠️ 检测到使用备选ID，尝试强制刷新获取正确ismartId');
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
    _logger.i('Periodic fee update stopped.');
  }

  ///24, 重新初始化Provider
  void reinitialize() {
    _logger.i('🔄 ArrearProvider重新初始化...');

    stopPeriodicUpdate();
    loadFromCache();

    Future.delayed(const Duration(milliseconds: 100), () {
      if (_appDataProvider.isLoggedIn) {
        _logger.i('✅ 重新初始化完成，重启费用数据定时更新');
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
