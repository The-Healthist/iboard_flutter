// import 'dart:io';
// import 'package:flutter/material.dart';
// import 'package:iboard_app/utils/wifi_printer_service.dart';
// import 'package:iboard_app/providers/printer_provider.dart';
// import 'package:iboard_app/models/announcement_model.dart';
// import 'package:provider/provider.dart';
// import 'package:logger/logger.dart';

// /// 增強型打印對話框
// class EnhancedPrintDialog extends StatefulWidget {
//   final AnnouncementModel announcement;
//   final String? localFilePath;

//   const EnhancedPrintDialog({
//     super.key,
//     required this.announcement,
//     this.localFilePath,
//   });

//   @override
//   EnhancedPrintDialogState createState() => EnhancedPrintDialogState();
// }

// class EnhancedPrintDialogState extends State<EnhancedPrintDialog> {
//   final Logger _logger = Logger();
//   PrinterProvider? _printerProvider;

//   List<PrinterDevice> _printers = [];
//   PrinterDevice? _selectedPrinter;
//   PaperSize _paperSize = PaperSize.a4;
//   bool _isColorPrint = true;
//   PrintOrientation _orientation = PrintOrientation.portrait;
//   bool _isDoubleSided = false;
//   int _startPage = 1;
//   int _endPage = 1;
//   int _copies = 1;
//   int _totalPages = 1;
//   bool _isLoading = true;

//   @override
//   void initState() {
//     super.initState();
//     // 從context中獲取全局PrinterProvider
//     _printerProvider = Provider.of<PrinterProvider>(context, listen: false);
//     _initializeDialog();
//   }

//   /// 1, 初始化對話框
//   Future<void> _initializeDialog() async {
//     try {
//       // 初始化打印機提供者
//       if (_printerProvider != null) {
//         await _printerProvider!.initialize();

//         // 獲取已保存的打印機
//         _printers = _printerProvider!.printers;
//         _selectedPrinter = _printerProvider!.defaultPrinter;

//         // 如果沒有打印機，刷新狀態
//         if (_printers.isEmpty) {
//           await _printerProvider!.refreshPrinterStatus();
//           _printers = _printerProvider!.printers;
//           _selectedPrinter = _printerProvider!.defaultPrinter;
//         }
//       }

//       // 估算PDF頁數（簡化版本）
//       _totalPages = await _estimatePageCount();
//       _endPage = _totalPages;

//       setState(() {
//         _isLoading = false;
//       });

//       _logger.i('🖨️ 打印對話框初始化完成，載入 ${_printers.length} 個打印機');
//     } catch (e) {
//       setState(() {
//         _isLoading = false;
//       });
//       _logger.e('初始化打印對話框失敗: $e');
//     }
//   }

//   /// 2, 估算PDF頁數
//   Future<int> _estimatePageCount() async {
//     try {
//       if (widget.localFilePath != null) {
//         final file = File(widget.localFilePath!);
//         if (await file.exists()) {
//           // 簡化估算：根據文件大小估算頁數
//           final fileSize = await file.length();
//           return (fileSize / (100 * 1024)).ceil().clamp(1, 999); // 假設每頁100KB
//         }
//       }
//       return 1;
//     } catch (e) {
//       return 1;
//     }
//   }

//   /// 3, 處理打印操作
//   Future<void> _handlePrint() async {
//     if (_selectedPrinter == null) {
//       _showErrorDialog('請選擇打印機');
//       return;
//     }

//     if (widget.localFilePath == null) {
//       _showErrorDialog('文件未準備就緒，請稍後再試');
//       return;
//     }

//     try {
//       // 顯示打印進度
//       showDialog(
//         context: context,
//         barrierDismissible: false,
//         builder: (context) => const AlertDialog(
//           content: Row(
//             children: [
//               CircularProgressIndicator(),
//               SizedBox(width: 20),
//               Text('正在打印...'),
//             ],
//           ),
//         ),
//       );

//       // 創建擴展的打印設置
//       final printSettings = PrintSettings(
//         selectedPrinter: _selectedPrinter,
//         isDoubleSided: _isDoubleSided,
//         isColorPrint: _isColorPrint,
//         fileName: widget.announcement.title,
//         paperSize: _paperSize,
//         orientation: _orientation,
//         startPage: _startPage,
//         endPage: _endPage,
//         copies: _copies,
//       );

//       // 執行打印
//       final printerService = WiFiPrinterService();
//       final success = await printerService.printPDF(
//         pdfFile: File(widget.localFilePath!),
//         settings: printSettings,
//       );

//       if (!mounted) return;
//       Navigator.of(context).pop(); // 關閉進度對話框

//       if (success) {
//         // 打印成功
//         Navigator.of(context).pop(); // 關閉打印對話框

//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text('文件 "${widget.announcement.title}" 已發送到打印機'),
//             backgroundColor: Colors.green,
//             duration: const Duration(seconds: 3),
//           ),
//         );
//       } else {
//         _showErrorDialog('打印失敗，請檢查打印機連接');
//       }
//     } catch (e) {
//       if (!mounted) return;
//       Navigator.of(context).pop(); // 關閉進度對話框
//       _showErrorDialog('打印時發生錯誤: $e');
//       _logger.e('打印失敗: $e');
//     }
//   }

//   /// 4, 顯示錯誤對話框
//   void _showErrorDialog(String message) {
//     showDialog(
//       context: context,
//       builder: (context) => AlertDialog(
//         title: const Text('打印錯誤'),
//         content: Text(message),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.of(context).pop(),
//             child: const Text('確定'),
//           ),
//         ],
//       ),
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Dialog(
//       child: Container(
//         width: 500,
//         constraints: const BoxConstraints(maxHeight: 700),
//         child: Column(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             // 標題欄
//             Container(
//               padding: const EdgeInsets.all(16),
//               decoration: BoxDecoration(
//                 color: Theme.of(context).primaryColor,
//                 borderRadius: const BorderRadius.only(
//                   topLeft: Radius.circular(4),
//                   topRight: Radius.circular(4),
//                 ),
//               ),
//               child: const Row(
//                 children: [
//                   Icon(Icons.print, color: Colors.white),
//                   SizedBox(width: 8),
//                   Expanded(
//                     child: Text(
//                       '高級打印設置',
//                       style: TextStyle(
//                         color: Colors.white,
//                         fontSize: 18,
//                         fontWeight: FontWeight.w600,
//                       ),
//                     ),
//                   ),
//                 ],
//               ),
//             ),

//             // 內容區域
//             Flexible(
//               child: _isLoading
//                   ? const SizedBox(
//                       height: 200,
//                       child: Center(child: CircularProgressIndicator()),
//                     )
//                   : SingleChildScrollView(
//                       padding: const EdgeInsets.all(16),
//                       child: Column(
//                         crossAxisAlignment: CrossAxisAlignment.start,
//                         children: [
//                           // 文件信息
//                           Container(
//                             padding: const EdgeInsets.all(12),
//                             decoration: BoxDecoration(
//                               color: Colors.grey.shade100,
//                               borderRadius: BorderRadius.circular(8),
//                             ),
//                             child: Row(
//                               children: [
//                                 const Icon(Icons.description,
//                                     color: Colors.blue, size: 20),
//                                 const SizedBox(width: 8),
//                                 Expanded(
//                                   child: Text(
//                                     widget.announcement.title,
//                                     style: const TextStyle(
//                                       fontWeight: FontWeight.w500,
//                                     ),
//                                   ),
//                                 ),
//                               ],
//                             ),
//                           ),

//                           const SizedBox(height: 16),

//                           // 打印機選擇
//                           Row(
//                             children: [
//                               const SizedBox(
//                                 width: 80,
//                                 child: Text('打印機:',
//                                     style:
//                                         TextStyle(fontWeight: FontWeight.w500)),
//                               ),
//                               Expanded(
//                                 child: DropdownButton<PrinterDevice>(
//                                   value: _selectedPrinter,
//                                   hint: const Text('請選擇打印機'),
//                                   isExpanded: true,
//                                   items: _printers.map((printer) {
//                                     return DropdownMenuItem<PrinterDevice>(
//                                       value: printer,
//                                       child: Row(
//                                         children: [
//                                           Icon(
//                                             Icons.print,
//                                             color: printer.isConnected
//                                                 ? Colors.green
//                                                 : Colors.grey,
//                                             size: 16,
//                                           ),
//                                           const SizedBox(width: 8),
//                                           Expanded(
//                                             child: Text(printer.name),
//                                           ),
//                                           if (!printer.isConnected)
//                                             const Text(
//                                               '(離線)',
//                                               style: TextStyle(
//                                                 color: Colors.red,
//                                                 fontSize: 12,
//                                               ),
//                                             ),
//                                         ],
//                                       ),
//                                     );
//                                   }).toList(),
//                                   onChanged: (value) {
//                                     setState(() {
//                                       _selectedPrinter = value;
//                                     });
//                                   },
//                                 ),
//                               ),
//                             ],
//                           ),

//                           const SizedBox(height: 12),

//                           // 紙張尺寸
//                           Row(
//                             children: [
//                               const SizedBox(
//                                 width: 80,
//                                 child: Text('紙張:',
//                                     style:
//                                         TextStyle(fontWeight: FontWeight.w500)),
//                               ),
//                               Expanded(
//                                 child: DropdownButton<PaperSize>(
//                                   value: _paperSize,
//                                   isExpanded: true,
//                                   items: PaperSize.values.map((size) {
//                                     return DropdownMenuItem<PaperSize>(
//                                       value: size,
//                                       child: Text(size.displayName),
//                                     );
//                                   }).toList(),
//                                   onChanged: (value) {
//                                     if (value != null) {
//                                       setState(() {
//                                         _paperSize = value;
//                                       });
//                                     }
//                                   },
//                                 ),
//                               ),
//                             ],
//                           ),

//                           const SizedBox(height: 12),

//                           // 彩色設置
//                           SwitchListTile(
//                             title: const Text('彩色打印'),
//                             value: _isColorPrint,
//                             onChanged: (value) {
//                               setState(() {
//                                 _isColorPrint = value;
//                               });
//                             },
//                             contentPadding: EdgeInsets.zero,
//                           ),

//                           // 方向設置
//                           Row(
//                             children: [
//                               const SizedBox(
//                                 width: 80,
//                                 child: Text('方向:',
//                                     style:
//                                         TextStyle(fontWeight: FontWeight.w500)),
//                               ),
//                               Expanded(
//                                 child: SegmentedButton<PrintOrientation>(
//                                   segments: PrintOrientation.values
//                                       .map((orientation) {
//                                     return ButtonSegment(
//                                       value: orientation,
//                                       label: Text(orientation.displayName),
//                                     );
//                                   }).toList(),
//                                   selected: {_orientation},
//                                   onSelectionChanged: (value) {
//                                     setState(() {
//                                       _orientation = value.first;
//                                     });
//                                   },
//                                 ),
//                               ),
//                             ],
//                           ),

//                           const SizedBox(height: 12),

//                           // 雙面打印
//                           SwitchListTile(
//                             title: const Text('雙面打印'),
//                             value: _isDoubleSided,
//                             onChanged: (value) {
//                               setState(() {
//                                 _isDoubleSided = value;
//                               });
//                             },
//                             contentPadding: EdgeInsets.zero,
//                           ),

//                           // 頁數範圍
//                           Row(
//                             children: [
//                               const SizedBox(
//                                 width: 80,
//                                 child: Text('頁數:',
//                                     style:
//                                         TextStyle(fontWeight: FontWeight.w500)),
//                               ),
//                               SizedBox(
//                                 width: 60,
//                                 child: TextFormField(
//                                   initialValue: _startPage.toString(),
//                                   keyboardType: TextInputType.number,
//                                   onChanged: (value) {
//                                     final page = int.tryParse(value);
//                                     if (page != null &&
//                                         page >= 1 &&
//                                         page <= _totalPages) {
//                                       _startPage = page;
//                                       if (_startPage > _endPage) {
//                                         _endPage = _startPage;
//                                       }
//                                     }
//                                   },
//                                 ),
//                               ),
//                               const SizedBox(width: 8),
//                               const Text('至'),
//                               const SizedBox(width: 8),
//                               SizedBox(
//                                 width: 60,
//                                 child: TextFormField(
//                                   initialValue: _endPage.toString(),
//                                   keyboardType: TextInputType.number,
//                                   onChanged: (value) {
//                                     final page = int.tryParse(value);
//                                     if (page != null &&
//                                         page >= _startPage &&
//                                         page <= _totalPages) {
//                                       _endPage = page;
//                                     }
//                                   },
//                                 ),
//                               ),
//                               const SizedBox(width: 8),
//                               Text('(共 $_totalPages 頁)'),
//                             ],
//                           ),

//                           const SizedBox(height: 12),

//                           // 份數
//                           Row(
//                             children: [
//                               const SizedBox(
//                                 width: 80,
//                                 child: Text('份數:',
//                                     style:
//                                         TextStyle(fontWeight: FontWeight.w500)),
//                               ),
//                               SizedBox(
//                                 width: 80,
//                                 child: TextFormField(
//                                   initialValue: _copies.toString(),
//                                   keyboardType: TextInputType.number,
//                                   onChanged: (value) {
//                                     final copies = int.tryParse(value);
//                                     if (copies != null &&
//                                         copies >= 1 &&
//                                         copies <= 99) {
//                                       _copies = copies;
//                                     }
//                                   },
//                                 ),
//                               ),
//                               const SizedBox(width: 8),
//                               const Text('份'),
//                             ],
//                           ),
//                         ],
//                       ),
//                     ),
//             ),

//             // 按鈕區域
//             Container(
//               padding: const EdgeInsets.all(16),
//               decoration: BoxDecoration(
//                 color: Colors.grey.shade50,
//                 borderRadius: const BorderRadius.only(
//                   bottomLeft: Radius.circular(4),
//                   bottomRight: Radius.circular(4),
//                 ),
//               ),
//               child: Row(
//                 mainAxisAlignment: MainAxisAlignment.end,
//                 children: [
//                   TextButton(
//                     onPressed: () => Navigator.of(context).pop(),
//                     child: const Text('取消'),
//                   ),
//                   const SizedBox(width: 12),
//                   ElevatedButton(
//                     onPressed: _selectedPrinter == null ? null : _handlePrint,
//                     style: ElevatedButton.styleFrom(
//                       backgroundColor: Colors.blue,
//                       foregroundColor: Colors.white,
//                       padding: const EdgeInsets.symmetric(
//                           horizontal: 24, vertical: 12),
//                     ),
//                     child: const Row(
//                       mainAxisSize: MainAxisSize.min,
//                       children: [
//                         Icon(Icons.print, size: 18),
//                         SizedBox(width: 8),
//                         Text('開始打印'),
//                       ],
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

