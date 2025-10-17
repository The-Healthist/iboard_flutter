import 'package:flutter/material.dart';
import 'package:iboard_app/providers/printer_provider.dart';
import 'package:provider/provider.dart';
import 'package:logger/logger.dart';

/// 通用添加打印機對話框
class AddPrinterDialog extends StatefulWidget {
  const AddPrinterDialog({super.key});

  @override
  AddPrinterDialogState createState() => AddPrinterDialogState();
}

class AddPrinterDialogState extends State<AddPrinterDialog> {
  final Logger _logger = Logger();
  final _nameController = TextEditingController();
  final _ipController = TextEditingController(text: '192.168.');

  bool _isConnecting = false;
  String? _connectionError;

  @override
  void dispose() {
    _nameController.dispose();
    _ipController.dispose();
    super.dispose();
  }

  /// 1, 驗證IP地址格式
  bool _isValidIP(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;

    for (String part in parts) {
      final num = int.tryParse(part);
      if (num == null || num < 0 || num > 255) return false;
    }
    return true;
  }

  /// 2, 添加打印機
  Future<void> _addPrinter() async {
    final name = _nameController.text.trim();
    final ip = _ipController.text.trim();

    // 驗證輸入
    if (ip.isEmpty || !_isValidIP(ip)) {
      setState(() {
        _connectionError = '請輸入有效的IP地址';
      });
      return;
    }

    setState(() {
      _isConnecting = true;
      _connectionError = null;
    });

    try {
      // 獲取打印機提供者
      final printerProvider = context.read<PrinterProvider>();
      final success = await printerProvider.addPrinter(
        printerIp: ip,
        name: name.isNotEmpty ? name : null,
      );

      if (!mounted) return;

      setState(() {
        _isConnecting = false;
      });

      if (success) {
        // 成功添加
        Navigator.of(context).pop(true); // 返回成功標誌

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('打印機 "${name.isNotEmpty ? name : ip}" 已成功添加'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );

        _logger.i('🖨️ 成功添加打印機: ${name.isNotEmpty ? name : ip} ($ip)');
      } else {
        setState(() {
          _connectionError = '無法連接到打印機，請檢查IP地址和網絡連接';
        });
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isConnecting = false;
        _connectionError = '添加打印機時發生錯誤: $e';
      });

      _logger.e('添加打印機失敗: $e');
    }
  }

  /// 3, 快速填充常見設備
  void _quickFillDevice(String deviceName, String ipSuffix) {
    _nameController.text = deviceName;
    _ipController.text = '192.168.$ipSuffix';
    setState(() {
      _connectionError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.add, color: Colors.blue),
          SizedBox(width: 8),
          Text('添加網絡打印機'),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 打印機名稱輸入
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '打印機名稱 (可選)',
                hintText: '例如: HP ENVY Inspire 7200',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.print),
              ),
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
            ),

            const SizedBox(height: 16),

            // IP地址輸入
            TextField(
              controller: _ipController,
              decoration: const InputDecoration(
                labelText: 'IP地址 *',
                hintText: '例如: 192.168.1.100',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.router),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _addPrinter(),
            ),

            const SizedBox(height: 16),

            // 快速選擇常見設備
            const Text(
              '快速選擇常見設備:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),

            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _buildQuickSelectChip(
                  'HP ENVY 7200',
                  '3.74',
                  Icons.print,
                  Colors.blue,
                ),
                _buildQuickSelectChip(
                  'Canon PIXMA',
                  '1.100',
                  Icons.print_outlined,
                  Colors.red,
                ),
                _buildQuickSelectChip(
                  'Epson WorkForce',
                  '1.101',
                  Icons.local_print_shop,
                  Colors.green,
                ),
                _buildQuickSelectChip(
                  '自定義',
                  '1.200',
                  Icons.edit,
                  Colors.orange,
                ),
              ],
            ),

            const SizedBox(height: 16),

            // 提示信息
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      color: Colors.blue.shade600, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '請確保設備和打印機連接到同一WiFi網絡',
                      style: TextStyle(
                        color: Colors.blue.shade700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 錯誤信息顯示
            if (_connectionError != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline,
                        color: Colors.red.shade600, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _connectionError!,
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isConnecting ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _isConnecting ? null : _addPrinter,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
          child: _isConnecting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text('添加打印機'),
        ),
      ],
    );
  }

  /// 4, 構建快速選擇芯片
  Widget _buildQuickSelectChip(
    String name,
    String ipSuffix,
    IconData icon,
    Color color,
  ) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(
        name,
        style: const TextStyle(fontSize: 12),
      ),
      onPressed: () => _quickFillDevice(name, ipSuffix),
      backgroundColor: color.withOpacity(0.1),
      side: BorderSide(color: color.withOpacity(0.3)),
    );
  }
}
