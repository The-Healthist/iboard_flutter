import 'package:flutter/foundation.dart';
import 'package:iboard_app/utils/wifi_printer_service.dart';
import 'package:iboard_app/utils/printer_connection_manager.dart';
import 'package:logger/logger.dart';

/// 全局打印機提供者 - 管理整個應用的打印機狀態
class PrinterProvider extends ChangeNotifier {
  static final PrinterProvider _instance = PrinterProvider._internal();
  factory PrinterProvider() => _instance;
  PrinterProvider._internal();

  final Logger _logger = Logger();
  final PrinterConnectionManager _connectionManager =
      PrinterConnectionManager();
  final WiFiPrinterService _printerService = WiFiPrinterService();

  List<PrinterDevice> _printers = [];
  PrinterDevice? _defaultPrinter;
  bool _isInitialized = false;

  /// 獲取已保存的打印機列表
  List<PrinterDevice> get printers => List.unmodifiable(_printers);

  /// 獲取默認打印機
  PrinterDevice? get defaultPrinter => _defaultPrinter;

  /// 是否已初始化
  bool get isInitialized => _isInitialized;

  /// 1, 初始化打印機提供者
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _logger.i('🖨️ 初始化全局打印機提供者...');

      // 初始化連接管理器
      await _connectionManager.initialize();

      // 載入已保存的打印機
      _printers = _connectionManager.getSavedPrinters();
      _defaultPrinter = _connectionManager.getDefaultPrinter();

      // 刷新打印機狀態
      if (_printers.isNotEmpty) {
        await refreshPrinterStatus();
      }

      _isInitialized = true;
      notifyListeners();

      _logger.i('🖨️ 打印機提供者初始化完成，載入 ${_printers.length} 個打印機');
    } catch (e) {
      _logger.e('初始化打印機提供者失敗: $e');
    }
  }

  /// 2, 添加新打印機
  Future<bool> addPrinter(PrinterDevice printer) async {
    try {
      // 測試連接
      final isConnected = await _printerService.testPrinterConnection(printer);

      if (isConnected) {
        // 創建連接成功的打印機
        final connectedPrinter = PrinterDevice(
          id: printer.id,
          name: printer.name,
          ipAddress: printer.ipAddress,
          isConnected: true,
          model: printer.model,
        );

        // 保存到連接管理器
        await _connectionManager.savePrinter(connectedPrinter);

        // 如果是第一個打印機，設為默認
        if (_defaultPrinter == null) {
          await _connectionManager.setDefaultPrinter(connectedPrinter);
          _defaultPrinter = connectedPrinter;
        }

        // 更新本地列表
        final existingIndex =
            _printers.indexWhere((p) => p.id == connectedPrinter.id);
        if (existingIndex >= 0) {
          _printers[existingIndex] = connectedPrinter;
        } else {
          _printers.add(connectedPrinter);
        }

        notifyListeners();
        _logger.i('🖨️ 成功添加打印機: ${printer.name}');
        return true;
      } else {
        _logger.w('🖨️ 打印機連接失敗: ${printer.name}');
        return false;
      }
    } catch (e) {
      _logger.e('添加打印機失敗: $e');
      return false;
    }
  }

  /// 3, 移除打印機
  Future<void> removePrinter(String printerId) async {
    try {
      await _connectionManager.removePrinter(printerId);

      _printers.removeWhere((p) => p.id == printerId);

      if (_defaultPrinter?.id == printerId) {
        _defaultPrinter = null;
      }

      notifyListeners();
      _logger.i('🖨️ 移除打印機: $printerId');
    } catch (e) {
      _logger.e('移除打印機失敗: $e');
    }
  }

  /// 4, 設置默認打印機
  Future<void> setDefaultPrinter(PrinterDevice printer) async {
    try {
      await _connectionManager.setDefaultPrinter(printer);
      _defaultPrinter = printer;
      notifyListeners();

      _logger.i('🖨️ 設置默認打印機: ${printer.name}');
    } catch (e) {
      _logger.e('設置默認打印機失敗: $e');
    }
  }

  /// 5, 刷新所有打印機狀態
  Future<void> refreshPrinterStatus() async {
    try {
      _logger.i('🖨️ 刷新打印機狀態...');

      final updatedPrinters = await _connectionManager.refreshPrinterStatus();
      _printers = updatedPrinters;

      // 檢查默認打印機狀態
      if (_defaultPrinter != null) {
        final defaultIndex =
            _printers.indexWhere((p) => p.id == _defaultPrinter!.id);
        if (defaultIndex >= 0) {
          _defaultPrinter = _printers[defaultIndex];
        }
      }

      notifyListeners();
      _logger.i('🖨️ 打印機狀態刷新完成');
    } catch (e) {
      _logger.e('刷新打印機狀態失敗: $e');
    }
  }

  /// 6, 獲取可用的打印機（已連接的）
  List<PrinterDevice> getAvailablePrinters() {
    return _printers.where((printer) => printer.isConnected).toList();
  }

  /// 7, 根據ID查找打印機
  PrinterDevice? findPrinterById(String id) {
    try {
      return _printers.firstWhere((printer) => printer.id == id);
    } catch (e) {
      return null;
    }
  }

  /// 8, 清除所有打印機
  Future<void> clearAllPrinters() async {
    try {
      await _connectionManager.clearAll();
      _printers.clear();
      _defaultPrinter = null;
      notifyListeners();

      _logger.i('🖨️ 清除所有打印機');
    } catch (e) {
      _logger.e('清除打印機失敗: $e');
    }
  }

  /// 9, 強制重新載入（用於調試）
  Future<void> forceReload() async {
    _isInitialized = false;
    await initialize();
  }
}
