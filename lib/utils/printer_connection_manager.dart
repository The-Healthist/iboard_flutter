import 'dart:convert';
import 'package:iboard_app/utils/wifi_printer_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';

/// 打印機連接管理器 - 負責持久化打印機連接信息
class PrinterConnectionManager {
  static final PrinterConnectionManager _instance =
      PrinterConnectionManager._internal();
  factory PrinterConnectionManager() => _instance;
  PrinterConnectionManager._internal();

  final Logger _logger = Logger();
  final WiFiPrinterService _printerService = WiFiPrinterService();

  static const String _printerListKey = 'saved_printers';
  static const String _defaultPrinterKey = 'default_printer';

  List<PrinterDevice> _savedPrinters = [];
  PrinterDevice? _defaultPrinter;

  /// 1, 初始化 - 從本地存儲載入已保存的打印機
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 載入已保存的打印機列表
      final printersJson = prefs.getString(_printerListKey);
      if (printersJson != null) {
        final printersList = jsonDecode(printersJson) as List;
        _savedPrinters = printersList
            .map((json) => PrinterDeviceJson.fromJson(json))
            .toList();
        _logger.i(' 載入了 ${_savedPrinters.length} 個已保存的打印機');
      }

      // 載入默認打印機
      final defaultPrinterJson = prefs.getString(_defaultPrinterKey);
      if (defaultPrinterJson != null) {
        final defaultPrinterMap = jsonDecode(defaultPrinterJson);
        _defaultPrinter = PrinterDeviceJson.fromJson(defaultPrinterMap);
        _logger.i(' 載入默認打印機: ${_defaultPrinter?.name}');
      }
    } catch (e) {
      _logger.e('初始化打印機管理器失敗: $e');
    }
  }

  /// 2, 保存打印機到本地存儲
  Future<void> savePrinter(PrinterDevice printer) async {
    try {
      // 檢查是否已存在
      final existingIndex =
          _savedPrinters.indexWhere((p) => p.id == printer.id);

      if (existingIndex >= 0) {
        // 更新現有打印機
        _savedPrinters[existingIndex] = printer;
      } else {
        // 添加新打印機
        _savedPrinters.add(printer);
      }

      // 如果沒有默認打印機，設置第一個為默認
      if (_defaultPrinter == null && printer.isConnected) {
        _defaultPrinter = printer;
      }

      await _persistToStorage();
      _logger.i(' 保存打印機: ${printer.name}');
    } catch (e) {
      _logger.e('保存打印機失敗: $e');
    }
  }

  /// 3, 設置默認打印機
  Future<void> setDefaultPrinter(PrinterDevice printer) async {
    try {
      _defaultPrinter = printer;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_defaultPrinterKey, jsonEncode(printer.toJson()));

      _logger.i(' 設置默認打印機: ${printer.name}');
    } catch (e) {
      _logger.e('設置默認打印機失敗: $e');
    }
  }

  /// 4, 移除打印機
  Future<void> removePrinter(String printerId) async {
    try {
      _savedPrinters.removeWhere((p) => p.id == printerId);

      // 如果移除的是默認打印機，清除默認設置
      if (_defaultPrinter?.id == printerId) {
        _defaultPrinter = null;
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_defaultPrinterKey);
      }

      await _persistToStorage();
      _logger.i(' 移除打印機: $printerId');
    } catch (e) {
      _logger.e('移除打印機失敗: $e');
    }
  }

  /// 5, 獲取所有已保存的打印機
  List<PrinterDevice> getSavedPrinters() {
    return List.unmodifiable(_savedPrinters);
  }

  /// 6, 獲取默認打印機
  PrinterDevice? getDefaultPrinter() {
    return _defaultPrinter;
  }

  /// 7, 測試所有已保存打印機的連接狀態
  Future<List<PrinterDevice>> refreshPrinterStatus() async {
    final updatedPrinters = <PrinterDevice>[];

    for (final printer in _savedPrinters) {
      try {
        final isConnected =
            await _printerService.testPrinterConnection(printer);
        final updatedPrinter = PrinterDevice(
          id: printer.id,
          name: printer.name,
          ipAddress: printer.ipAddress,
          isConnected: isConnected,
          model: printer.model,
        );
        updatedPrinters.add(updatedPrinter);
      } catch (e) {
        // 連接失敗，保持原狀態但標記為未連接
        final updatedPrinter = PrinterDevice(
          id: printer.id,
          name: printer.name,
          ipAddress: printer.ipAddress,
          isConnected: false,
          model: printer.model,
        );
        updatedPrinters.add(updatedPrinter);
      }
    }

    _savedPrinters = updatedPrinters;
    await _persistToStorage();

    _logger.i(' 刷新了 ${updatedPrinters.length} 個打印機狀態');
    return updatedPrinters;
  }

  /// 8, 持久化到本地存儲
  Future<void> _persistToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final printersJson =
          jsonEncode(_savedPrinters.map((p) => p.toJson()).toList());
      await prefs.setString(_printerListKey, printersJson);
    } catch (e) {
      _logger.e('持久化打印機數據失敗: $e');
    }
  }

  /// 9, 清除所有數據
  Future<void> clearAll() async {
    try {
      _savedPrinters.clear();
      _defaultPrinter = null;

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_printerListKey);
      await prefs.remove(_defaultPrinterKey);

      _logger.i(' 清除所有打印機數據');
    } catch (e) {
      _logger.e('清除打印機數據失敗: $e');
    }
  }
}

/// PrinterDevice 擴展方法，添加 JSON 序列化支持
extension PrinterDeviceJson on PrinterDevice {
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'ipAddress': ipAddress,
      'isConnected': isConnected,
      'model': model,
    };
  }

  static PrinterDevice fromJson(Map<String, dynamic> json) {
    return PrinterDevice(
      id: json['id'] as String,
      name: json['name'] as String,
      ipAddress: json['ipAddress'] as String?,
      isConnected: json['isConnected'] as bool,
      model: json['model'] as String?,
    );
  }
}
