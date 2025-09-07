import 'dart:io';
import 'package:flutter/material.dart';
import 'package:iboard_app/utils/wifi_printer_service.dart';
import 'package:iboard_app/providers/printer_provider.dart';
import 'package:iboard_app/models/announcement_model.dart';
import 'package:iboard_app/providers/announcement_provider.dart';
import 'package:iboard_app/widgets/add_printer_dialog.dart';
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
  final WiFiPrinterService _printerService = WiFiPrinterService();
  PrinterProvider? _printerProvider;

  List<PrinterDevice> _printers = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _printerProvider = context.read<PrinterProvider>();
    _loadPrinters();
  }

  /// 1, 載入列印機列表
  Future<void> _loadPrinters() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // 確保列印機提供者已初始化
      if (_printerProvider != null) {
        await _printerProvider!.initialize();

        // 先載入已保存的列印機
        List<PrinterDevice> printers = _printerProvider!.printers;

        // 刷新已保存列印機的狀態
        await _printerProvider!.refreshPrinterStatus();
        printers = _printerProvider!.printers;

        // 如果沒有已保存的列印機，掃描新的
        if (printers.isEmpty) {
          printers = await _printerService.getAvailablePrinters();
          // 將掃描到的列印機保存到提供者
          for (final printer in printers) {
            await _printerProvider!.addPrinter(printer);
          }
        }

        if (!mounted) return;

        setState(() {
          _printers = printers;
          _isLoading = false;
        });
      }

      _logger.i('📱 載入了 ${_printers.length} 個列印機');
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = '載入列印機失敗: $e';
        _isLoading = false;
      });

      _logger.e('載入列印機失敗: $e');
    }
  }

  /// 2, 測試列印機連接
  Future<void> _testPrinter(PrinterDevice printer) async {
    _logger.i('🖨️ 測試列印機: ${printer.name}');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('測試連接中...'),
          ],
        ),
      ),
    );

    try {
      final isConnected = await _printerService.testPrinterConnection(printer);
      if (!mounted) return;

      Navigator.of(context).pop(); // 關閉進度對話框

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(isConnected ? '連接成功' : '連接失敗'),
          content: Text(isConnected
              ? '列印機 "${printer.name}" 連接正常'
              : '無法連接到列印機 "${printer.name}"'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('確定'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;

      Navigator.of(context).pop(); // 關閉進度對話框

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('連接錯誤'),
          content: Text('測試連接時發生錯誤: $e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('確定'),
            ),
          ],
        ),
      );
    }
  }

  /// 3, 構建列印機項目
  Widget _buildPrinterItem(PrinterDevice printer) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: printer.isConnected
                ? Colors.green.shade50
                : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.print,
            color: printer.isConnected
                ? Colors.green.shade600
                : Colors.grey.shade600,
            size: 24,
          ),
        ),
        title: Text(
          printer.name,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (printer.model != null)
              Text(
                '型號: ${printer.model}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            if (printer.ipAddress != null)
              Text(
                'IP: ${printer.ipAddress}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            Text(
              printer.isConnected ? '已連接' : '未連接',
              style: TextStyle(
                fontSize: 12,
                color: printer.isConnected ? Colors.green : Colors.red,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.wifi_find, size: 20),
              onPressed: () => _testPrinter(printer),
              tooltip: '測試連接',
              color: Colors.blue.shade600,
            ),
            if (printer.isConnected)
              IconButton(
                icon: const Icon(Icons.print_outlined, size: 20),
                onPressed: () => _showTestPrintDialog(printer),
                tooltip: '測試列印',
                color: Colors.blue.shade600,
              ),
            Icon(
              printer.isConnected ? Icons.check_circle : Icons.error,
              color: printer.isConnected ? Colors.green : Colors.red,
              size: 20,
            ),
          ],
        ),
        onTap: () => _showPrinterDetails(printer),
      ),
    );
  }

  /// 4, 顯示列印機詳細信息
  void _showPrinterDetails(PrinterDevice printer) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(printer.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('ID', printer.id),
            _buildDetailRow('名稱', printer.name),
            if (printer.model != null) _buildDetailRow('型號', printer.model!),
            if (printer.ipAddress != null)
              _buildDetailRow('IP地址', printer.ipAddress!),
            _buildDetailRow('狀態', printer.isConnected ? '已連接' : '未連接'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('關閉'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _testPrinter(printer);
            },
            child: const Text('測試連接'),
          ),
        ],
      ),
    );
  }

  /// 5, 構建詳細信息行
  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  /// 6, 顯示手動添加列印機對話框
  void _showAddPrinterDialog() {
    final ipController = TextEditingController();
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('手動添加WiFi列印機'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: '列印機名稱',
                  hintText: '例如: HP LaserJet 7200',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ipController,
                decoration: const InputDecoration(
                  labelText: 'IP地址',
                  hintText: '例如: 192.168.1.100',
                  border: OutlineInputBorder(),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 16),
              const Text(
                '提示：請確保列印機已連接到相同的WiFi網絡',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
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
              final name = nameController.text.trim();

              if (ip.isEmpty || name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('請填寫完整信息')),
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
              await _addManualPrinter(name, ip);
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  /// 7, 驗證IP地址格式
  bool _isValidIP(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;

    for (String part in parts) {
      final num = int.tryParse(part);
      if (num == null || num < 0 || num > 255) return false;
    }
    return true;
  }

  /// 8, 手動添加列印機
  Future<void> _addManualPrinter(String name, String ip) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('測試連接中...'),
          ],
        ),
      ),
    );

    try {
      // 創建手動列印機設備
      final printer = PrinterDevice(
        id: 'manual_$ip',
        name: name,
        ipAddress: ip,
        isConnected: false,
        model: 'WiFi列印機',
      );

      // 保存到列印機提供者
      if (_printerProvider != null) {
        final success = await _printerProvider!.addPrinter(printer);

        if (!mounted) return;
        Navigator.of(context).pop(); // 關閉進度對話框

        if (success) {
          // 刷新列表
          setState(() {
            _printers = _printerProvider!.printers;
          });

          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('添加成功'),
              content: Text('列印機 "$name" 已成功添加並連接'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('確定'),
                ),
              ],
            ),
          );

          _logger.i('🖨️ 手動添加列印機成功: $name ($ip)');
        } else {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('連接失敗'),
              content: Text(
                  '無法連接到列印機 "$name" ($ip)\n\n請檢查：\n• IP地址是否正確\n• 列印機是否開啟\n• 是否在同一WiFi網絡'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('確定'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // 關閉進度對話框

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('添加失敗'),
          content: Text('添加列印機時發生錯誤: $e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('確定'),
            ),
          ],
        ),
      );

      _logger.e('手動添加列印機失敗: $e');
    }
  }

  /// 10, 顯示測試列印對話框
  void _showTestPrintDialog(PrinterDevice printer) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.print, color: Colors.blue),
            SizedBox(width: 8),
            Text('測試列印'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('列印機: ${printer.name}'),
              if (printer.ipAddress != null)
                Text('IP地址: ${printer.ipAddress}',
                    style: const TextStyle(fontFamily: 'monospace')),
              const SizedBox(height: 16),
              const Text(
                '選擇測試內容：',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),

              // 測試頁面按鈕
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _printTestPage(printer);
                  },
                  icon: const Icon(Icons.description),
                  label: const Text('列印測試頁面'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // 列印通告PDF按鈕
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _selectAnnouncementToPrint(printer);
                  },
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('選擇通告PDF列印'),
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

  /// 11, 列印測試頁面
  Future<void> _printTestPage(PrinterDevice printer) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('正在生成測試頁面...'),
          ],
        ),
      ),
    );

    try {
      // 創建測試PDF內容
      final testPdfBytes = await _generateTestPDF(printer);

      if (!mounted) return;
      Navigator.of(context).pop(); // 關閉進度對話框

      // 創建臨時文件
      final tempDir = Directory.systemTemp;
      final testFile = File(
          '${tempDir.path}/printer_test_${DateTime.now().millisecondsSinceEpoch}.pdf');
      await testFile.writeAsBytes(testPdfBytes);

      // 列印設置
      final printSettings = PrintSettings(
        isDoubleSided: false,
        isColorPrint: false, // 測試頁面使用黑白
        fileName: '列印機測試頁面',
        selectedPrinter: printer,
      );

      // 執行列印
      final success = await _printerService.printPDF(
        pdfFile: testFile,
        settings: printSettings,
      );

      if (!mounted) return;

      if (success) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('測試列印成功'),
              ],
            ),
            content: Text('測試頁面已發送到 ${printer.name}\n\n請檢查列印機是否正常出紙。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('確定'),
              ),
            ],
          ),
        );
      } else {
        _showPrintFailureDialog(printer);
      }

      // 清理臨時文件
      try {
        await testFile.delete();
      } catch (e) {
        _logger.w('清理臨時文件失敗: $e');
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // 關閉進度對話框

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('測試列印失敗'),
          content: Text('生成測試頁面時發生錯誤: $e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('確定'),
            ),
          ],
        ),
      );

      _logger.e('測試列印失敗: $e');
    }
  }

  /// 12, 生成測試PDF
  Future<List<int>> _generateTestPDF(PrinterDevice? printer) async {
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
                  '列印機測試頁面',
                  style: pw.TextStyle(
                      fontSize: 24, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 20),
                pw.Text('列印機: ${printer?.name ?? "HP ENVY Inspire 7200"}'),
                pw.Text('測試時間: ${DateTime.now().toString()}'),
                pw.SizedBox(height: 20),
                pw.Text('如果您能看到此頁面，說明列印機工作正常！'),
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

  /// 13, 選擇通告PDF進行列印
  Future<void> _selectAnnouncementToPrint(PrinterDevice printer) async {
    try {
      // 獲取通告列表
      final announcementProvider = context.read<AnnouncementProvider>();
      final announcements = announcementProvider.announcements;

      if (announcements.isEmpty) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('暫無通告'),
            content: const Text('當前沒有可用的通告PDF文件。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('確定'),
              ),
            ],
          ),
        );
        return;
      }

      // 篩選PDF類型的通告
      final pdfAnnouncements = announcements
          .where((a) => a.file.mimeType.toLowerCase() == 'application/pdf')
          .toList();

      if (pdfAnnouncements.isEmpty) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('暫無PDF通告'),
            content: const Text('當前沒有PDF格式的通告文件可供列印。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('確定'),
              ),
            ],
          ),
        );
        return;
      }

      // 顯示選擇對話框
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('選擇要列印的通告'),
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
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('獲取通告失敗'),
          content: Text('無法獲取通告列表: $e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('確定'),
            ),
          ],
        ),
      );

      _logger.e('獲取通告列表失敗: $e');
    }
  }

  /// 14, 列印選中的通告
  Future<void> _printSelectedAnnouncement(
      PrinterDevice printer, AnnouncementModel announcement) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('正在列印: ${announcement.title}'),
            const SizedBox(height: 8),
            const Text('請稍候...', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );

    try {
      // 檢查文件是否已下載
      File? pdfFile;
      if (announcement.file.localFilePath != null) {
        pdfFile = File(announcement.file.localFilePath!);
        if (!await pdfFile.exists()) {
          pdfFile = null;
        }
      }

      // 如果文件未下載，提示用戶
      if (pdfFile == null) {
        if (!mounted) return;
        Navigator.of(context).pop();

        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('文件未就緒'),
            content: const Text('通告PDF文件尚未下載完成，請稍後再試。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('確定'),
              ),
            ],
          ),
        );
        return;
      }

      // 列印設置
      final printSettings = PrintSettings(
        isDoubleSided: false,
        isColorPrint: true,
        fileName: announcement.title,
        selectedPrinter: printer,
      );

      // 執行列印
      final success = await _printerService.printPDF(
        pdfFile: pdfFile,
        settings: printSettings,
      );

      if (!mounted) return;
      Navigator.of(context).pop(); // 關閉進度對話框

      if (success) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('列印成功'),
              ],
            ),
            content: Text('通告 "${announcement.title}" 已發送到 ${printer.name}'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('確定'),
              ),
            ],
          ),
        );

        _logger.i('🖨️ 通告列印成功: ${announcement.title}');
      } else {
        _showPrintFailureDialog(printer);
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // 關閉進度對話框

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('列印失敗'),
          content: Text('列印通告時發生錯誤: $e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('確定'),
            ),
          ],
        ),
      );

      _logger.e('列印通告失敗: $e');
    }
  }

  /// 15, 顯示列印失敗對話框
  void _showPrintFailureDialog(PrinterDevice printer) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('列印失敗'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('無法完成列印任務到 ${printer.name}'),
            const SizedBox(height: 16),
            const Text('可能原因：'),
            const Text('• 列印機缺紙或卡紙'),
            const Text('• 列印機處於離線狀態'),
            const Text('• 網絡連接中斷'),
            const Text('• 列印隊列已滿'),
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

  /// 16, 顯示新的添加列印機對話框
  Future<void> _showNewAddPrinterDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const AddPrinterDialog(),
    );

    // 如果成功添加了列印機，刷新列表
    if (result == true) {
      await _loadPrinters();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvoked: (didPop) {
        // 直接返回，不恢复轮播，因为这只是返回到設置頁面
      },
      child: Scaffold(
        backgroundColor: Colors.grey.shade50,
        body: SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: SafeArea(
            child: Column(
              children: [
                // 顶部标题区域
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.05),
                        spreadRadius: 1,
                        blurRadius: 3,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () {
                          Navigator.pop(context);
                        },
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
                        '列印機設置',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
                // 主要内容区域
                Expanded(
                  child: _buildBody(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 17, 構建主體內容
  Widget _buildBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),

          // 說明文字
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: Colors.blue.shade600,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '系統會自動掃描網絡中的WiFi列印機，您也可以手動添加已知IP地址的列印機。',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.blue.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          if (_isLoading)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.05),
                    spreadRadius: 1,
                    blurRadius: 3,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('掃描列印機中...'),
                  ],
                ),
              ),
            )
          else if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.05),
                    spreadRadius: 1,
                    blurRadius: 3,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
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
                      style: const TextStyle(color: Colors.red, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _loadPrinters,
                      child: const Text('重新嘗試'),
                    ),
                  ],
                ),
              ),
            )
          else if (_printers.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.05),
                    spreadRadius: 1,
                    blurRadius: 3,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: Column(
                  children: [
                    const Icon(
                      Icons.print_disabled,
                      color: Colors.grey,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '未找到可用的列印機',
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '請確保列印機已連接並開啟',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _loadPrinters,
                          icon: const Icon(Icons.refresh),
                          label: const Text('重新掃描'),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: _showNewAddPrinterDialog,
                          icon: const Icon(Icons.add),
                          label: const Text('添加列印機'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade600,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            )
          else
            // 列印機列表
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.05),
                    spreadRadius: 1,
                    blurRadius: 3,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.print,
                          color: Colors.blue.shade600,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        '已添加的列印機',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${_printers.length} 個列印機',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ..._printers.map((printer) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _buildPrinterItem(printer),
                      )),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
