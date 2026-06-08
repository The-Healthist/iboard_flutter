import 'dart:io';
import 'package:flutter/material.dart';
import 'package:iboard_app/providers/printer_provider.dart';
import 'package:iboard_app/providers/app_data_provider.dart';
import 'package:iboard_app/models/printer_model.dart';
import 'package:iboard_app/models/announcement_model.dart';
import 'package:iboard_app/providers/announcement_provider.dart';
import 'package:provider/provider.dart';
import 'package:logger/logger.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class PrintDeviceListPage extends StatefulWidget {
  const PrintDeviceListPage({super.key});

  @override
  PrintDeviceListPageState createState() => PrintDeviceListPageState();
}

class PrintDeviceListPageState extends State<PrintDeviceListPage> {
  final Logger _logger = Logger();
  PrinterProvider? _printerProvider;
  AppDataProvider? _appDataProvider;

  bool _isLoading = true;
  String? _error;
  String _currentOrangePiIp = '';

  @override
  void initState() {
    super.initState();
    _printerProvider = context.read<PrinterProvider>();
    _appDataProvider = context.read<AppDataProvider>();
    _loadSavedIp();
  }

  /// 1, 載入保存的IP地址
  Future<void> _loadSavedIp() async {
    try {
      // 直接從 PrinterProvider 獲取IP
      final savedIp = _printerProvider?.orangePiIp ?? '';

      if (savedIp.isNotEmpty) {
        setState(() {
          _currentOrangePiIp = savedIp;
        });
        await _initializePrinters();
      } else {
        // 嘗試從後台設置獲取
        final settingsIp = _appDataProvider?.deviceSettings?.orangePiIp ?? '';
        if (settingsIp.isNotEmpty) {
          setState(() {
            _currentOrangePiIp = settingsIp;
          });
          await _printerProvider?.updateOrangePiIp(settingsIp);
          await _initializePrinters();
        } else {
          setState(() {
            _isLoading = false;
          });
        }
      }

      _logger.i(' 當前香橙派IP: $_currentOrangePiIp');
    } catch (e) {
      _logger.e('載入IP地址失敗: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 2, 初始化打印機
  Future<void> _initializePrinters() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      if (_currentOrangePiIp.isEmpty) {
        setState(() {
          _error = '請配置香橙派IP地址';
          _isLoading = false;
        });
        return;
      }

      // 初始化打印機提供者
      await _printerProvider?.initialize(orangePiIp: _currentOrangePiIp);

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      _logger.i(' 打印機初始化完成');
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = '初始化失敗: $e';
        _isLoading = false;
      });

      _logger.e('初始化打印機失敗: $e');
    }
  }

  /// 4, 顯示配置IP對話框
  void _showConfigureIpDialog() {
    final ipController = TextEditingController(text: _currentOrangePiIp);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.settings_ethernet, color: Colors.blue),
            SizedBox(width: 8),
            Text('配置香橙派IP地址'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '請輸入香橙派打印服務的IP地址',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ipController,
                decoration: InputDecoration(
                  labelText: 'IP地址',
                  hintText: '例如: 192.168.50.173',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.computer),
                  suffixIcon: _currentOrangePiIp.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => ipController.clear(),
                        )
                      : null,
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 16, color: Colors.blue.shade700),
                        const SizedBox(width: 4),
                        Text(
                          '提示',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '• 確保香橙派打印服務已啟動\n• 設備需在同一網絡\n• 默認端口為8080',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              final ip = ipController.text.trim();

              if (ip.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('請輸入IP地址')),
                );
                return;
              }

              if (!_isValidIP(ip)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('請輸入有效的IP地址')),
                );
                return;
              }

              Navigator.of(context).pop();
              await _updateIpAddress(ip);
            },
            icon: const Icon(Icons.save),
            label: const Text('保存並連接'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade600,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  /// 3, 更新IP地址
  Future<void> _updateIpAddress(String newIp) async {
    _showLoadingDialog('正在連接到 $newIp...');

    try {
      // 更新PrinterProvider（自動持久化保存）
      await _printerProvider?.updateOrangePiIp(newIp);

      // 更新狀態
      setState(() {
        _currentOrangePiIp = newIp;
      });

      if (!mounted) return;
      Navigator.of(context).pop();

      // 檢查服務健康狀態
      final isHealthy = await _printerProvider?.checkServiceHealth();

      if (!mounted) return;

      if (isHealthy == true) {
        _showMessageDialog(
          title: '連接成功',
          message: '已成功連接到香橙派打印服務\nIP: $newIp',
          isSuccess: true,
        );

        // 刷新打印機列表
        await _refreshPrinters();
      } else {
        _showMessageDialog(
          title: '連接失敗',
          message: '無法連接到打印服務\n\n請檢查：\n• IP地址是否正確\n• 打印服務是否啟動\n• 網絡連接是否正常',
          isSuccess: false,
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();

      _showMessageDialog(
        title: '錯誤',
        message: '配置IP地址失敗: $e',
        isSuccess: false,
      );
    }
  }

  /// 4, 刷新打印機列表
  Future<void> _refreshPrinters() async {
    setState(() => _isLoading = true);

    try {
      await _printerProvider?.refreshPrinters();
      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '刷新失敗: $e';
          _isLoading = false;
        });
      }
    }
  }

  /// 4a, 手動健康檢測
  Future<void> _manualHealthCheck() async {
    _logger.i(' [手動健康檢測] 用戶觸發');

    // 顯示載入對話框
    _showLoadingDialog('正在執行健康檢測...\n請稍候');

    try {
      // 調用批量健康檢查（與定時任務相同的邏輯）
      await _printerProvider?.batchHealthCheck();

      if (!mounted) return;
      Navigator.of(context).pop(); // 關閉載入對話框

      // 刷新打印機列表以顯示最新狀態
      await _refreshPrinters();

      if (!mounted) return;

      // 顯示成功消息
      _showMessageDialog(
        title: '健康檢測完成',
        message: '已完成香橙派服務和打印機連接檢測\n並已上報到後台管理系統',
        isSuccess: true,
      );

      _logger.i(' [手動健康檢測] 完成');
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // 關閉載入對話框

      _logger.e(' [手動健康檢測] 失敗: $e');

      _showMessageDialog(
        title: '健康檢測失敗',
        message: '執行健康檢測時發生錯誤:\n$e',
        isSuccess: false,
      );
    }
  }

  /// 7, 測試打印機連接
  Future<void> _testPrinter(PrinterInfo printer) async {
    _logger.i(' 測試打印機: ${printer.name}');

    _showLoadingDialog('測試連接中...');

    try {
      final isConnected =
          await _printerProvider?.testPrinterConnection(printer.ipAddress);

      if (!mounted) return;
      Navigator.of(context).pop();

      _showMessageDialog(
        title: isConnected == true ? '連接成功' : '連接失敗',
        message: isConnected == true
            ? '打印機 "${printer.name}" 連接正常'
            : '無法連接到打印機 "${printer.name}"',
        isSuccess: isConnected == true,
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();

      _showMessageDialog(
        title: '連接錯誤',
        message: '測試連接時發生錯誤: $e',
        isSuccess: false,
      );
    }
  }

  /// 4, 顯示打印機詳情 (使用Options API)
  Future<void> _showPrinterDetails(PrinterInfo printer) async {
    _showLoadingDialog('載入詳情中...');

    try {
      final options =
          await _printerProvider?.getPrinterOptions(printer.ipAddress);

      if (!mounted) return;
      Navigator.of(context).pop();

      if (options == null) {
        _showMessageDialog(
          title: '錯誤',
          message: '無法獲取打印機詳情',
          isSuccess: false,
        );
        return;
      }

      showDialog(
        context: context,
        builder: (context) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            width: 500,
            constraints: const BoxConstraints(maxHeight: 700),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 標題欄
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.blue.shade600, Colors.blue.shade400],
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.print,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              options.options['printer-info']
                                      ?.replaceAll("'", '') ??
                                  printer.displayName,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              printer.ipAddress,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white.withOpacity(0.9),
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // 內容區域
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 基本信息
                        _buildSectionTitle('基本信息', Icons.info_outline),
                        _buildInfoCard([
                          _buildDetailRow2('設備名稱', options.printerName),
                          _buildDetailRow2(
                              '顯示名稱',
                              options.options['printer-info']
                                      ?.replaceAll("'", '') ??
                                  '-'),
                          _buildDetailRow2(
                              '型號',
                              options.options['printer-make-and-model']
                                      ?.replaceAll("'", '') ??
                                  '-'),
                          _buildDetailRow2(
                              '位置', options.options['printer-location'] ?? '-'),
                          _buildDetailRow2(
                              '設備URI', options.options['device-uri'] ?? '-'),
                        ]),

                        const SizedBox(height: 20),

                        // 狀態信息
                        _buildSectionTitle('狀態信息', Icons.check_circle_outline),
                        _buildInfoCard([
                          _buildStatusRow(
                              '打印機狀態',
                              _getPrinterStateText(
                                  options.options['printer-state']),
                              _getPrinterStateColor(
                                  options.options['printer-state'])),
                          _buildStatusRow(
                              '接受作業',
                              options.options['printer-is-accepting-jobs'] ==
                                      'true'
                                  ? '是'
                                  : '否',
                              options.options['printer-is-accepting-jobs'] ==
                                      'true'
                                  ? Colors.green
                                  : Colors.orange),
                          _buildStatusRow(
                              '共享狀態',
                              options.options['printer-is-shared'] == 'true'
                                  ? '已共享'
                                  : '未共享',
                              Colors.blue),
                          _buildDetailRow2(
                              '狀態原因',
                              options.options['printer-state-reasons'] ??
                                  'none'),
                        ]),
                      ],
                    ),
                  ),
                ),

                // 底部按鈕
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                        label: const Text('關閉'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _testPrinter(printer);
                        },
                        icon: const Icon(Icons.wifi_find),
                        label: const Text('測試連接'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade600,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();

      _showMessageDialog(
        title: '錯誤',
        message: '獲取詳情失敗: $e',
        isSuccess: false,
      );
    }
  }

  /// 構建章節標題
  Widget _buildSectionTitle(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.blue.shade600),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
          ),
        ],
      ),
    );
  }

  /// 構建信息卡片
  Widget _buildInfoCard(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        children: children,
      ),
    );
  }

  /// 構建詳情行 (新版)
  Widget _buildDetailRow2(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: Colors.grey.shade800,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 構建狀態行
  Widget _buildStatusRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 獲取打印機狀態文本
  String _getPrinterStateText(String? stateCode) {
    switch (stateCode) {
      case '3':
        return '空閒 (Idle)';
      case '4':
        return '處理中 (Processing)';
      case '5':
        return '已停止 (Stopped)';
      default:
        return '未知';
    }
  }

  /// 獲取打印機狀態顏色
  Color _getPrinterStateColor(String? stateCode) {
    switch (stateCode) {
      case '3':
        return Colors.green;
      case '4':
        return Colors.blue;
      case '5':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  /// 5, 顯示添加打印機對話框
  void _showAddPrinterDialog() {
    final ipController = TextEditingController();
    final nameController = TextEditingController();
    final descController = TextEditingController();
    final locationController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加網絡打印機'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ipController,
                  decoration: const InputDecoration(
                    labelText: 'IP地址 *',
                    hintText: '例如: 192.168.1.100',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: '打印機名稱',
                    hintText: '例如: Office Printer',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(
                    labelText: '描述',
                    hintText: '例如: 辦公室彩色打印機',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: locationController,
                  decoration: const InputDecoration(
                    labelText: '位置',
                    hintText: '例如: 辦公區A',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '提示：系統將使用IPP Everywhere驅動自動連接打印機',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final ip = ipController.text.trim();

              if (ip.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('請輸入IP地址')),
                );
                return;
              }

              if (!_isValidIP(ip)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('請輸入有效的IP地址')),
                );
                return;
              }

              Navigator.of(context).pop();
              await _addPrinter(
                ip: ip,
                name: nameController.text.trim(),
                description: descController.text.trim(),
                location: locationController.text.trim(),
              );
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  /// 6, 添加打印機
  Future<void> _addPrinter({
    required String ip,
    String? name,
    String? description,
    String? location,
  }) async {
    _showLoadingDialog('正在添加打印機...');

    try {
      final success = await _printerProvider?.addPrinter(
        printerIp: ip,
        name: name,
        description: description,
        location: location,
      );

      if (!mounted) return;
      Navigator.of(context).pop();

      if (success == true) {
        _showMessageDialog(
          title: '添加成功',
          message: '打印機已成功添加並連接',
          isSuccess: true,
        );
        await _refreshPrinters();
      } else {
        _showMessageDialog(
          title: '連接失敗',
          message: '無法連接到打印機\n\n請檢查：\n• IP地址是否正確\n• 打印機是否開啟\n• 是否在同一網絡',
          isSuccess: false,
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();

      _showMessageDialog(
        title: '添加失敗',
        message: '添加打印機時發生錯誤: $e',
        isSuccess: false,
      );
    }
  }

  /// 7, 刪除打印機
  Future<void> _deletePrinter(PrinterInfo printer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確認刪除'),
        content: Text('確定要刪除打印機 "${printer.name}" 嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('刪除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    _showLoadingDialog('正在刪除...');

    try {
      final success = await _printerProvider?.removePrinter(printer.id);

      if (!mounted) return;
      Navigator.of(context).pop();

      if (success == true) {
        _showMessageDialog(
          title: '刪除成功',
          message: '打印機已刪除',
          isSuccess: true,
        );
      } else {
        _showMessageDialog(
          title: '刪除失敗',
          message: '無法刪除打印機',
          isSuccess: false,
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();

      _showMessageDialog(
        title: '錯誤',
        message: '刪除失敗: $e',
        isSuccess: false,
      );
    }
  }

  /// 8, 顯示測試打印對話框
  void _showTestPrintDialog(PrinterInfo printer) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.print, color: Colors.blue),
            SizedBox(width: 8),
            Text('測試打印'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('打印機: ${printer.name}'),
              Text('IP地址: ${printer.ipAddress}',
                  style: const TextStyle(fontFamily: 'monospace')),
              const SizedBox(height: 16),
              const Text(
                '選擇測試內容：',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _printTestPage(printer);
                  },
                  icon: const Icon(Icons.description),
                  label: const Text('打印測試頁面'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _selectAnnouncementToPrint(printer);
                  },
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('選擇通告PDF打印'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  /// 9, 打印測試頁面
  Future<void> _printTestPage(PrinterInfo printer) async {
    _showLoadingDialog('正在生成測試頁面...');

    try {
      final testPdfBytes = await _generateTestPDF(printer);

      if (!mounted) return;
      Navigator.of(context).pop();

      // 創建臨時文件
      final tempDir = Directory.systemTemp;
      final testFile = File(
          '${tempDir.path}/printer_test_${DateTime.now().millisecondsSinceEpoch}.pdf');
      await testFile.writeAsBytes(testPdfBytes);

      // 打印設置
      final printSettings = PrintSettings(
        copies: 1,
        colorMode: 'bw',
        media: 'a4',
        duplex: false,
        quality: 'normal',
      );

      // 執行打印
      final response = await _printerProvider?.printPdf(
        printerIp: printer.ipAddress,
        pdfFile: testFile,
        title: '打印機測試頁面',
        settings: printSettings,
      );

      if (!mounted) return;

      if (response?.success == true) {
        _showMessageDialog(
          title: '測試打印成功',
          message:
              '測試頁面已發送到 ${printer.name}\n\n作業ID: ${response?.jobId}\n請檢查打印機是否正常出紙。',
          isSuccess: true,
        );
      } else {
        _showPrintFailureDialog(printer, response?.message);
      }

      // 清理臨時文件
      try {
        await testFile.delete();
      } catch (e) {
        _logger.w('清理臨時文件失敗: $e');
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();

      _showMessageDialog(
        title: '測試打印失敗',
        message: '生成測試頁面時發生錯誤: $e',
        isSuccess: false,
      );
    }
  }

  /// 10, 生成測試PDF
  Future<List<int>> _generateTestPDF(PrinterInfo printer) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Center(
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text(
                  '打印機測試頁面',
                  style: pw.TextStyle(
                      fontSize: 24, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 20),
                pw.Text('打印機: ${printer.name}'),
                pw.Text('IP地址: ${printer.ipAddress}'),
                pw.Text('測試時間: ${DateTime.now().toString()}'),
                pw.SizedBox(height: 20),
                pw.Text('如果您能看到此頁面，說明打印機工作正常！'),
                pw.SizedBox(height: 40),
                pw.Container(
                  width: 200,
                  height: 100,
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(),
                  ),
                  child: pw.Center(
                    child: pw.Text('測試內容框'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    return await pdf.save();
  }

  /// 11, 選擇通告PDF打印
  Future<void> _selectAnnouncementToPrint(PrinterInfo printer) async {
    try {
      final announcementProvider = context.read<AnnouncementProvider>();
      final announcements = announcementProvider.announcements;

      if (announcements.isEmpty) {
        _showMessageDialog(
          title: '暫無通告',
          message: '當前沒有可用的通告PDF文件。',
          isSuccess: false,
        );
        return;
      }

      final pdfAnnouncements = announcements
          .where((a) => a.file.mimeType.toLowerCase() == 'application/pdf')
          .toList();

      if (pdfAnnouncements.isEmpty) {
        _showMessageDialog(
          title: '暫無PDF通告',
          message: '當前沒有PDF格式的通告文件可供打印。',
          isSuccess: false,
        );
        return;
      }

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('選擇要打印的通告'),
          content: SizedBox(
            width: 400,
            height: 300,
            child: ListView.builder(
              itemCount: pdfAnnouncements.length,
              itemBuilder: (context, index) {
                final announcement = pdfAnnouncements[index];
                return ListTile(
                  leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                  title: Text(announcement.title),
                  subtitle: Text(
                      '文件大小: ${(announcement.file.fileSize / 1024).toStringAsFixed(1)} KB'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _printSelectedAnnouncement(printer, announcement);
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
          ],
        ),
      );
    } catch (e) {
      _showMessageDialog(
        title: '獲取通告失敗',
        message: '無法獲取通告列表: $e',
        isSuccess: false,
      );
    }
  }

  /// 12, 打印選中的通告
  Future<void> _printSelectedAnnouncement(
      PrinterInfo printer, AnnouncementModel announcement) async {
    _showLoadingDialog('正在打印: ${announcement.title}');

    try {
      File? pdfFile;
      if (announcement.file.localFilePath != null) {
        pdfFile = File(announcement.file.localFilePath!);
        if (!await pdfFile.exists()) {
          pdfFile = null;
        }
      }

      if (pdfFile == null) {
        if (!mounted) return;
        Navigator.of(context).pop();

        _showMessageDialog(
          title: '文件未就緒',
          message: '通告PDF文件尚未下載完成，請稍後再試。',
          isSuccess: false,
        );
        return;
      }

      final printSettings = PrintSettings(
        copies: 1,
        colorMode: 'color',
        media: 'a4',
        duplex: false,
        quality: 'normal',
      );

      final response = await _printerProvider?.printPdf(
        printerIp: printer.ipAddress,
        pdfFile: pdfFile,
        title: announcement.title,
        settings: printSettings,
      );

      if (!mounted) return;
      Navigator.of(context).pop();

      if (response?.success == true) {
        _showMessageDialog(
          title: '打印成功',
          message:
              '通告 "${announcement.title}" 已發送到 ${printer.name}\n\n作業ID: ${response?.jobId}',
          isSuccess: true,
        );
      } else {
        _showPrintFailureDialog(printer, response?.message);
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();

      _showMessageDialog(
        title: '打印失敗',
        message: '打印通告時發生錯誤: $e',
        isSuccess: false,
      );
    }
  }

  /// 13, 構建打印機項目
  Widget _buildPrinterItem(PrinterInfo printer) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ListTile(
        leading: _buildPrinterLeadingIcon(printer),
        title: Text(
          printer.displayName,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: _buildPrinterSubtitle(printer),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'test':
                _testPrinter(printer);
                break;
              case 'print':
                _showTestPrintDialog(printer);
                break;
              case 'details':
                _showPrinterDetails(printer);
                break;
              case 'delete':
                _deletePrinter(printer);
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'test',
              child: Row(
                children: [
                  Icon(Icons.wifi_find, size: 20),
                  SizedBox(width: 8),
                  Text('測試連接'),
                ],
              ),
            ),
            if (printer.isOnline)
              const PopupMenuItem(
                value: 'print',
                child: Row(
                  children: [
                    Icon(Icons.print_outlined, size: 20),
                    SizedBox(width: 8),
                    Text('測試打印'),
                  ],
                ),
              ),
            const PopupMenuItem(
              value: 'details',
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 20),
                  SizedBox(width: 8),
                  Text('查看詳情'),
                ],
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete_outline, size: 20, color: Colors.red),
                  SizedBox(width: 8),
                  Text('刪除', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
        ),
        onTap: () => _showPrinterDetails(printer),
      ),
    );
  }

  /// 13a, 構建打印機圖標
  Widget _buildPrinterLeadingIcon(PrinterInfo printer) {
    // 優先使用實際狀態
    final actualStatus = printer.actualStatus;
    final isOnline = actualStatus == 'online' || actualStatus == 'active';

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isOnline ? Colors.green.shade50 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.print,
        color: isOnline ? Colors.green.shade600 : Colors.grey.shade600,
        size: 28,
      ),
    );
  }

  /// 13b, 構建打印機副標題
  Widget _buildPrinterSubtitle(PrinterInfo printer) {
    // 優先使用實際狀態
    final actualStatus = printer.actualStatus;
    final isOnline = actualStatus == 'online' || actualStatus == 'active';
    final statusColor = isOnline ? Colors.green : Colors.orange;
    final statusIcon = isOnline ? Icons.check_circle : Icons.warning;

    // 顯示原因（如果有）
    final String statusText = printer.hasActualStatus && printer.reason != null
        ? '${printer.state} - ${printer.reason}'
        : printer.state;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Text(
          'IP: ${printer.ipAddress}',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
            fontFamily: 'monospace',
          ),
        ),
        if (printer.location != null)
          Text(
            '位置: ${printer.location}',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              statusIcon,
              size: 14,
              color: statusColor,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                statusText,
                style: TextStyle(
                  fontSize: 12,
                  color: statusColor,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 15, 驗證IP地址
  bool _isValidIP(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;

    for (String part in parts) {
      final num = int.tryParse(part);
      if (num == null || num < 0 || num > 255) return false;
    }
    return true;
  }

  /// 16, 顯示載入對話框
  void _showLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  /// 17, 顯示消息對話框
  void _showMessageDialog({
    required String title,
    required String message,
    required bool isSuccess,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              isSuccess ? Icons.check_circle : Icons.error_outline,
              color: isSuccess ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('確定'),
          ),
        ],
      ),
    );
  }

  /// 18, 顯示打印失敗對話框
  void _showPrintFailureDialog(PrinterInfo printer, String? errorMessage) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('打印失敗'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('無法完成打印任務到 ${printer.name}'),
            if (errorMessage != null) ...[
              const SizedBox(height: 12),
              Text('錯誤信息: $errorMessage',
                  style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 16),
            const Text('可能原因：'),
            const Text('• 打印機缺紙或卡紙'),
            const Text('• 打印機處於離線狀態'),
            const Text('• 網絡連接中斷'),
            const Text('• 打印隊列已滿'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('確定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: SafeArea(
        child: Column(
          children: [
            // 頂部標題區域
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    spreadRadius: 1,
                    blurRadius: 3,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back, size: 28),
                      ),
                      const SizedBox(width: 16),
                      Icon(
                        Icons.print,
                        size: 32,
                        color: Colors.blue.shade600,
                      ),
                      const SizedBox(width: 16),
                      Text(
                        '打印機管理',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      const Spacer(),
                      if (_printerProvider?.isServiceAvailable == true)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle,
                                  size: 16, color: Colors.green.shade600),
                              const SizedBox(width: 4),
                              Text(
                                '服務在線',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.green.shade600,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.warning,
                                  size: 16, color: Colors.orange.shade600),
                              const SizedBox(width: 4),
                              Text(
                                '服務離線',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange.shade600,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  // IP配置區域
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _currentOrangePiIp.isNotEmpty
                          ? Colors.blue.shade50
                          : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _currentOrangePiIp.isNotEmpty
                            ? Colors.blue.shade200
                            : Colors.orange.shade200,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.computer,
                          size: 20,
                          color: _currentOrangePiIp.isNotEmpty
                              ? Colors.blue.shade700
                              : Colors.orange.shade700,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '香橙派IP地址',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _currentOrangePiIp.isNotEmpty
                                    ? _currentOrangePiIp
                                    : '未配置',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: _currentOrangePiIp.isNotEmpty
                                      ? Colors.blue.shade700
                                      : Colors.orange.shade700,
                                  fontFamily: _currentOrangePiIp.isNotEmpty
                                      ? 'monospace'
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _showConfigureIpDialog,
                          icon: Icon(
                            _currentOrangePiIp.isNotEmpty
                                ? Icons.edit
                                : Icons.settings,
                            size: 16,
                          ),
                          label: Text(
                            _currentOrangePiIp.isNotEmpty ? '修改' : '配置',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _currentOrangePiIp.isNotEmpty
                                ? Colors.blue.shade600
                                : Colors.orange.shade600,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // 主要內容區域
            Expanded(
              child: _buildBody(),
            ),
          ],
        ),
      ),
    );
  }

  /// 19, 構建主體內容
  Widget _buildBody() {
    return Consumer<PrinterProvider>(
      builder: (context, printerProvider, child) {
        final printers = printerProvider.printers;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),

              // 操作按鈕區
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _refreshPrinters,
                    icon: const Icon(Icons.refresh),
                    label: const Text('刷新列表'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _manualHealthCheck,
                    icon: const Icon(Icons.health_and_safety),
                    label: const Text('手動健康檢測'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _showAddPrinterDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('添加打印機'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade600,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // 載入中
              if (_isLoading && printers.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(40),
                  child: const Center(
                    child: Column(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('載入打印機列表中...'),
                      ],
                    ),
                  ),
                )
              // 錯誤提示
              else if (_error != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Column(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.red,
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          style:
                              const TextStyle(color: Colors.red, fontSize: 16),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _initializePrinters,
                          child: const Text('重試'),
                        ),
                      ],
                    ),
                  ),
                )
              // 空列表
              else if (printers.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(40),
                  child: Center(
                    child: Column(
                      children: [
                        const Icon(
                          Icons.print_disabled,
                          color: Colors.grey,
                          size: 64,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          '暫無打印機',
                          style: TextStyle(fontSize: 18, color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '點擊上方按鈕添加打印機',
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                )
              // 打印機列表
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '打印機列表 (${printers.length})',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...printers.map((printer) => _buildPrinterItem(printer)),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}
