import 'dart:io';
import 'dart:typed_data';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:logger/logger.dart';
import 'package:path/path.dart' as path;

/// 打印機設備信息
class PrinterDevice {
  final String id;
  final String name;
  final String? ipAddress;
  final bool isConnected;
  final String? model;

  PrinterDevice({
    required this.id,
    required this.name,
    this.ipAddress,
    required this.isConnected,
    this.model,
  });

  @override
  String toString() => '$name${ipAddress != null ? ' ($ipAddress)' : ''}';
}

/// 打印設置
class PrintSettings {
  final bool isDoubleSided;
  final bool isColorPrint;
  final String fileName;
  final PrinterDevice? selectedPrinter;

  // 擴展參數
  final PaperSize? paperSize;
  final PrintOrientation? orientation;
  final int? startPage;
  final int? endPage;
  final int? copies;

  PrintSettings({
    required this.isDoubleSided,
    required this.isColorPrint,
    required this.fileName,
    this.selectedPrinter,
    this.paperSize,
    this.orientation,
    this.startPage,
    this.endPage,
    this.copies,
  });
}

/// 紙張尺寸枚舉
enum PaperSize {
  a4('A4'),
  a5('A5'),
  a6('A6'),
  letter('Letter'),
  legal('Legal');

  const PaperSize(this.displayName);
  final String displayName;
}

/// 打印方向枚舉
enum PrintOrientation {
  portrait('縱向'),
  landscape('橫向');

  const PrintOrientation(this.displayName);
  final String displayName;
}

/// WiFi打印機服務
class WiFiPrinterService {
  static final WiFiPrinterService _instance = WiFiPrinterService._internal();
  factory WiFiPrinterService() => _instance;
  WiFiPrinterService._internal();

  final Logger _logger = Logger();
  List<PrinterDevice> _availablePrinters = [];

  /// 1, 獲取可用的打印機列表
  Future<List<PrinterDevice>> getAvailablePrinters() async {
    try {
      _logger.i('🖨️ 開始掃描可用打印機...');

      // 獲取系統可用的打印機
      final printers = await Printing.listPrinters();

      _availablePrinters = printers.map((printer) {
        return PrinterDevice(
          id: printer.name, // 使用 name 作為 ID
          name: printer.name,
          isConnected: printer.isAvailable,
          model: _detectPrinterModel(printer.name),
        );
      }).toList();

      // 如果沒有找到打印機，嘗試添加預設的HP 7200
      if (_availablePrinters.isEmpty) {
        _availablePrinters.add(PrinterDevice(
          id: 'hp_7200_default',
          name: 'HP LaserJet 7200 (WiFi)',
          ipAddress: await _detectHP7200IPAddress(),
          isConnected: false,
          model: 'HP LaserJet 7200',
        ));
      }

      _logger.i('🖨️ 找到 ${_availablePrinters.length} 個打印機');
      return _availablePrinters;
    } catch (e) {
      _logger.e('掃描打印機失敗: $e');
      return [];
    }
  }

  /// 2, 檢測HP 7200打印機的IP地址
  Future<String?> _detectHP7200IPAddress() async {
    try {
      // 根據用戶實際環境的HP打印機IP地址範圍
      final commonIPs = [
        // 用戶實際網段 192.168.3.x
        '192.168.3.74', // 用戶實際打印機IP
        '192.168.3.100',
        '192.168.3.101',
        '192.168.3.102',
        // 其他常見網段
        '192.168.1.100',
        '192.168.1.101',
        '192.168.0.100',
        '192.168.0.101',
        '10.0.0.100',
      ];

      for (String ip in commonIPs) {
        try {
          final socket = await Socket.connect(ip, 9100,
              timeout: const Duration(seconds: 2));
          socket.destroy();
          _logger.i('🖨️ 在 $ip 找到HP打印機');
          return ip;
        } catch (e) {
          // 繼續檢查下一個IP
        }
      }
    } catch (e) {
      _logger.w('檢測HP打印機IP失敗: $e');
    }
    return null;
  }

  /// 3, 檢測打印機型號
  String? _detectPrinterModel(String printerName) {
    final name = printerName.toLowerCase();
    if (name.contains('hp') && name.contains('7200')) {
      return 'HP LaserJet 7200';
    } else if (name.contains('hp')) {
      return 'HP Printer';
    }
    return null;
  }

  /// 5, 打印PDF文件 - 使用系統打印服務
  Future<bool> printPDF({
    required File pdfFile,
    required PrintSettings settings,
  }) async {
    try {
      _logger.i('🖨️ 開始打印: ${settings.fileName}');

      if (settings.selectedPrinter == null) {
        _logger.e('未選擇打印機');
        return false;
      }

      // 讀取PDF文件
      final pdfBytes = await pdfFile.readAsBytes();

      // 使用系統打印服務
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdfBytes,
        name: settings.fileName,
        format: _getPrintFormat(settings),
      );

      _logger.i('🖨️ 打印任務已通過系統服務發送: ${settings.fileName}');
      return true;
    } catch (e) {
      _logger.e('打印失敗: $e');
      return false;
    }
  }

  /// 6, 打印圖片文件
  Future<bool> printImage({
    required File imageFile,
    required PrintSettings settings,
  }) async {
    try {
      _logger.i('🖨️ 開始打印圖片: ${settings.fileName}');

      if (settings.selectedPrinter == null) {
        _logger.e('未選擇打印機');
        return false;
      }

      // 讀取圖片文件
      final imageBytes = await imageFile.readAsBytes();

      // 創建PDF文檔包含圖片
      final pdf = pw.Document();
      final image = pw.MemoryImage(imageBytes);

      pdf.addPage(
        pw.Page(
          pageFormat: _getPrintFormat(settings),
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Image(image, fit: pw.BoxFit.contain),
            );
          },
        ),
      );

      // 打印PDF
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => await pdf.save(),
        name: settings.fileName,
        format: _getPrintFormat(settings),
      );

      _logger.i('🖨️ 圖片打印任務已發送: ${settings.fileName}');
      return true;
    } catch (e) {
      _logger.e('圖片打印失敗: $e');
      return false;
    }
  }

  /// 7, 獲取打印格式設置
  PdfPageFormat _getPrintFormat(PrintSettings settings) {
    // 根據紙張尺寸設置格式
    PdfPageFormat format;
    switch (settings.paperSize ?? PaperSize.a4) {
      case PaperSize.a4:
        format = PdfPageFormat.a4;
        break;
      case PaperSize.a5:
        format = PdfPageFormat.a5;
        break;
      case PaperSize.a6:
        format = PdfPageFormat.a6;
        break;
      case PaperSize.letter:
        format = PdfPageFormat.letter;
        break;
      case PaperSize.legal:
        format = PdfPageFormat.legal;
        break;
    }

    // 根據方向調整格式
    if (settings.orientation == PrintOrientation.landscape) {
      format = format.landscape;
      _logger.d('🖨️ 設置為橫向打印');
    } else {
      _logger.d('🖨️ 設置為縱向打印');
    }

    // 根據顏色設置調整（在實際應用中可能需要更多配置）
    if (!settings.isColorPrint) {
      _logger.d('🖨️ 設置為黑白打印');
    } else {
      _logger.d('🖨️ 設置為彩色打印');
    }

    // 雙面打印在printing包中通常由系統處理
    if (settings.isDoubleSided) {
      _logger.d('🖨️ 設置為雙面打印');
    }

    // 頁數範圍和份數記錄
    if (settings.startPage != null && settings.endPage != null) {
      _logger.d('🖨️ 打印頁數範圍: ${settings.startPage} - ${settings.endPage}');
    }
    if (settings.copies != null && settings.copies! > 1) {
      _logger.d('🖨️ 打印份數: ${settings.copies}');
    }

    return format;
  }

  /// 8, 獲取文件擴展名
  String _getFileExtension(String fileName) {
    return path.extension(fileName).toLowerCase();
  }

  /// 9, 直接發送到HP 7200（如果支持直接網絡打印）
  Future<bool> printDirectToHP7200({
    required Uint8List data,
    required String ipAddress,
    required PrintSettings settings,
  }) async {
    try {
      _logger.i('🖨️ 直接發送到HP 7200: $ipAddress');

      // 連接到打印機
      final socket = await Socket.connect(ipAddress, 9100);

      // 發送PCL或PostScript命令（簡化版本）
      socket.add(data);
      await socket.flush();
      await socket.close();

      _logger.i('🖨️ 直接打印完成');
      return true;
    } catch (e) {
      _logger.e('直接打印到HP 7200失敗: $e');
      return false;
    }
  }

  /// 10, 重新掃描打印機
  Future<void> refreshPrinters() async {
    _logger.i('🖨️ 重新掃描打印機...');
    await getAvailablePrinters();
  }

  /// 11, 掃描網絡中的打印機（新增方法）
  Future<List<PrinterDevice>> scanNetworkForPrinters() async {
    final foundPrinters = <PrinterDevice>[];

    try {
      _logger.i('🖨️ 開始掃描網絡打印機...');

      // 獲取本機IP地址
      final localIP = await _getLocalIPAddress();
      if (localIP == null) {
        _logger.w('無法獲取本機IP地址');
        return foundPrinters;
      }

      // 解析網段
      final parts = localIP.split('.');
      if (parts.length != 4) return foundPrinters;

      final networkBase = '${parts[0]}.${parts[1]}.${parts[2]}';
      _logger.i('🖨️ 掃描網段: $networkBase.x');

      // 常用打印機IP範圍
      final ipRanges = [
        // 常見打印機IP範圍
        for (int i = 100; i <= 199; i++) '$networkBase.$i',
        // DHCP常見範圍
        for (int i = 50; i <= 99; i++) '$networkBase.$i',
        for (int i = 200; i <= 250; i++) '$networkBase.$i',
      ];

      // 分批掃描以避免網絡過載
      const batchSize = 30;
      for (int i = 0; i < ipRanges.length; i += batchSize) {
        final batch = ipRanges.skip(i).take(batchSize);

        _logger.d(
            '🖨️ 掃描批次 ${(i ~/ batchSize) + 1}/${(ipRanges.length / batchSize).ceil()}');

        final futures = batch.map((ip) => _testAndCreatePrinter(ip));
        final results = await Future.wait(futures);

        for (final printer in results) {
          if (printer != null) {
            foundPrinters.add(printer);
            _logger.i('🖨️ 找到打印機: ${printer.name} (${printer.ipAddress})');
          }
        }

        // 短暫延遲避免網絡過載
        await Future.delayed(const Duration(milliseconds: 100));
      }
    } catch (e) {
      _logger.e('網絡掃描失敗: $e');
    }

    _logger.i('🖨️ 網絡掃描完成，找到 ${foundPrinters.length} 個打印機');
    return foundPrinters;
  }

  /// 12, 獲取本機IP地址
  Future<String?> _getLocalIPAddress() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (var interface in interfaces) {
        // 優先選擇WiFi接口
        if (interface.name.toLowerCase().contains('wi-fi') ||
            interface.name.toLowerCase().contains('wlan')) {
          for (var address in interface.addresses) {
            if (address.type == InternetAddressType.IPv4 &&
                !address.isLoopback) {
              if (_isPrivateIP(address.address)) {
                _logger.i('🖨️ 檢測到WiFi接口IP: ${address.address}');
                return address.address;
              }
            }
          }
        }
      }

      // 如果沒有WiFi接口，選擇任何私有IP
      for (var interface in interfaces) {
        for (var address in interface.addresses) {
          if (address.type == InternetAddressType.IPv4 && !address.isLoopback) {
            if (_isPrivateIP(address.address)) {
              _logger.i('🖨️ 檢測到網絡接口IP: ${address.address}');
              return address.address;
            }
          }
        }
      }
    } catch (e) {
      _logger.e('獲取本機IP失敗: $e');
    }
    return null;
  }

  /// 13, 檢查是否為私有IP地址
  bool _isPrivateIP(String ip) {
    return ip.startsWith('192.168.') ||
        ip.startsWith('10.') ||
        ip.startsWith('172.16.') ||
        ip.startsWith('172.17.') ||
        ip.startsWith('172.18.') ||
        ip.startsWith('172.19.') ||
        ip.startsWith('172.20.') ||
        ip.startsWith('172.21.') ||
        ip.startsWith('172.22.') ||
        ip.startsWith('172.23.') ||
        ip.startsWith('172.24.') ||
        ip.startsWith('172.25.') ||
        ip.startsWith('172.26.') ||
        ip.startsWith('172.27.') ||
        ip.startsWith('172.28.') ||
        ip.startsWith('172.29.') ||
        ip.startsWith('172.30.') ||
        ip.startsWith('172.31.');
  }

  /// 14, 測試並創建打印機設備
  Future<PrinterDevice?> _testAndCreatePrinter(String ip) async {
    try {
      // 測試多個常用打印機端口
      final ports = [9100, 515, 631, 80]; // IPP, LPD, CUPS, HTTP

      for (int port in ports) {
        try {
          final socket = await Socket.connect(ip, port,
              timeout: const Duration(seconds: 2));
          await socket.close();

          // 如果連接成功，創建打印機設備
          final printerName = await _detectPrinterName(ip, port);
          final model = _detectPrinterModel(printerName);

          return PrinterDevice(
            id: 'network_${ip}_$port',
            name: printerName,
            ipAddress: ip,
            isConnected: true,
            model: model,
          );
        } catch (e) {
          // 嘗試下個端口
        }
      }
    } catch (e) {
      // IP不可達
    }
    return null;
  }

  /// 15, 檢測打印機名稱
  Future<String> _detectPrinterName(String ip, int port) async {
    try {
      // 嘗試通過HTTP獲取打印機信息
      if (port == 80 || port == 631) {
        // 簡化版本，實際可以嘗試HTTP請求獲取設備信息
        return 'Network Printer ($ip:$port)';
      }
      return 'Network Printer ($ip:$port)';
    } catch (e) {
      return 'Network Printer ($ip)';
    }
  }

  /// 4, 測試打印機連接（增強版本）
  Future<bool> testPrinterConnection(PrinterDevice printer) async {
    try {
      _logger.i('🖨️ 測試打印機連接: ${printer.name}');

      // 如果有IP地址，優先測試網絡連接
      if (printer.ipAddress != null) {
        final ip = printer.ipAddress!;

        // HP ENVY Inspire 7200 支持的端口（從配置頁面可知該型號支持多種協議）
        final ports = [
          9100, // HP JetDirect (最常用)
          631, // IPP (Internet Printing Protocol)
          80, // HTTP Web Interface
          443, // HTTPS Web Interface
          515, // LPD (Line Printer Daemon)
          8080, // Alternative HTTP
        ];

        _logger.i('🖨️ 測試HP ENVY Inspire 7200 at $ip 的多個端口...');

        for (int port in ports) {
          try {
            _logger.d('🖨️ 嘗試連接 $ip:$port...');
            final socket = await Socket.connect(ip, port,
                timeout: const Duration(seconds: 5) // 增加超時時間
                );

            // 對於HTTP端口，嘗試發送簡單請求驗證是打印機
            if (port == 80 || port == 8080) {
              try {
                socket.write(
                    'HEAD / HTTP/1.1\r\nHost: $ip\r\nConnection: close\r\n\r\n');
                await Future.delayed(const Duration(milliseconds: 500));
              } catch (e) {
                // HTTP請求失敗不影響連接測試
              }
            }

            await socket.close();
            _logger.i('🖨️ ✅ 成功連接到打印機: ${printer.name} ($ip:$port)');
            return true;
          } catch (e) {
            _logger.d(
                '🖨️ ❌ 端口 $port 連接失敗: ${e.toString().contains('Connection refused') ? '連接被拒絕' : e.toString().split(':').last.trim()}');
          }
        }

        // 如果所有端口都失敗，進行網絡診斷
        _logger.w('🖨️ ⚠️  所有打印端口連接失敗，進行網絡診斷...');

        // 嘗試基本的網絡連接測試
        try {
          final socket = await Socket.connect(ip, 22,
              timeout: const Duration(seconds: 2)); // SSH端口
          await socket.close();
          _logger.w(
              '🖨️ ⚠️  設備 $ip 網絡可達但打印服務不可用，請檢查：\n• 打印機是否開啟\n• 打印機網絡設置是否正確\n• 防火牆是否阻止連接');
        } catch (e) {
          _logger.e(
              '🖨️ ❌ 設備 $ip 完全不可達，請檢查：\n• IP地址是否正確\n• 設備和打印機是否在同一網絡\n• 網絡連接是否正常');
        }

        return false;
      }

      // 對於系統打印機，檢查是否可用
      return printer.isConnected;
    } catch (e) {
      _logger.e('打印機連接測試失敗: $e');
      return false;
    }
  }

  /// 獲取當前可用打印機列表
  List<PrinterDevice> get availablePrinters => _availablePrinters;
}
