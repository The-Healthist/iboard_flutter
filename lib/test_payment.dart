import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'http/api_client.dart';

/// 測試支付功能的演示頁面
class TestPaymentPage extends StatefulWidget {
  const TestPaymentPage({Key? key}) : super(key: key);

  @override
  State<TestPaymentPage> createState() => _TestPaymentPageState();
}

class _TestPaymentPageState extends State<TestPaymentPage> {
  late ApiClient _apiClient;
  String _result = '';
  bool _isLoading = false;
  final TextEditingController _amountController = TextEditingController(text: '0.1');

  @override
  void initState() {
    super.initState();
    _apiClient = ApiClient(baseUrl: PaymentApiConfig.baseUrl);
  }

  ///1, 測試微信支付
  Future<void> _testWechatPayment() async {
    if (_isLoading) return;
    
    setState(() {
      _isLoading = true;
      _result = '正在創建微信支付訂單...';
    });

    try {
      // 生成唯一订单号
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final random = (timestamp % 999999).toString().padLeft(6, '0');
      final orderNo = 'TEST_WX_$timestamp$random';
      final amount = double.tryParse(_amountController.text) ?? 0.1;
      
      print('🎯 [測試] 開始創建微信支付，訂單號: $orderNo');
      
      final result = await _apiClient.createWechatPayment(
        orderNo: orderNo,
        amount: amount,
        subject: '測試微信支付 - $timestamp',
        body: '這是一個測試微信支付訂單',
        returnUrl: 'https://ismart-pay.li-iop.com/',
      );

      setState(() {
        _result = '✅ 微信支付創建成功！\n\n'
            '訂單號：$orderNo\n'
            '金額：HK\$ $amount\n'
            '時間戳：$timestamp\n\n'
            '完整響應數據：\n${result.toString()}';
      });
      
      // 檢查各種可能的QR碼字段
      String? qrData;
      if (result.containsKey('payData')) {
        qrData = result['payData'];
        _showQrCodeDialog('微信支付QR碼 (payData)', qrData!);
      } else if (result.containsKey('codeUrl')) {
        qrData = result['codeUrl'];
        _showQrCodeDialog('微信支付QR碼 (codeUrl)', qrData!);
      } else if (result.containsKey('qr_code')) {
        qrData = result['qr_code'];
        _showQrCodeDialog('微信支付QR碼 (qr_code)', qrData!);
      } else {
        print('⚠️ [測試] 響應中沒有找到QR碼數據');
        print('📋 [測試] 可用字段: ${result.keys.toList()}');
      }
    } catch (e) {
      setState(() {
        _result = '❌ 微信支付創建失敗：\n$e\n\n錯誤類型：${e.runtimeType}';
      });
      print('💥 [測試] 微信支付創建異常: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  ///2, 測試支付寶支付
  Future<void> _testAlipayPayment() async {
    if (_isLoading) return;
    
    setState(() {
      _isLoading = true;
      _result = '正在創建支付寶訂單...';
    });

    try {
      final orderNo = 'test_ali_${DateTime.now().millisecondsSinceEpoch}';
      final amount = double.tryParse(_amountController.text) ?? 0.1;
      
      final result = await _apiClient.createAlipayPayment(
        orderNo: orderNo,
        amount: amount,
        subject: '測試支付寶支付',
        body: '這是一個測試支付寶訂單',
        returnUrl: 'https://ismart-pay.li-iop.com/',
      );

      setState(() {
        _result = '✅ 支付寶創建成功！\n\n'
            '訂單號：$orderNo\n'
            '金額：HK\$ $amount\n'
            '響應數據：\n${result.toString()}';
      });
      
      // 如果返回了QR碼URL，可以顯示
      if (result.containsKey('payData')) {
        _showQrCodeDialog('支付寶QR碼', result['payData']);
      }
    } catch (e) {
      setState(() {
        _result = '❌ 支付寶創建失敗：$e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  ///3, 測試銀聯支付
  Future<void> _testUnionpayPayment() async {
    if (_isLoading) return;
    
    setState(() {
      _isLoading = true;
      _result = '正在創建銀聯支付訂單...';
    });

    try {
      final orderNo = 'test_up_${DateTime.now().millisecondsSinceEpoch}';
      final amount = double.tryParse(_amountController.text) ?? 0.1;
      
      final result = await _apiClient.createUnionpayPayment(
        orderNo: orderNo,
        amount: amount,
        subject: '測試銀聯支付',
        body: '這是一個測試銀聯訂單',
        returnUrl: 'https://ismart-pay.li-iop.com/',
      );

      setState(() {
        _result = '✅ 銀聯支付創建成功！\n\n'
            '訂單號：$orderNo\n'
            '金額：HK\$ $amount\n'
            '響應數據：\n${result.toString()}';
      });
      
      // 如果返回了QR碼URL，可以顯示
      if (result.containsKey('payData')) {
        _showQrCodeDialog('銀聯支付QR碼', result['payData']);
      }
    } catch (e) {
      setState(() {
        _result = '❌ 銀聯支付創建失敗：$e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  ///4, 顯示QR碼對話框
  void _showQrCodeDialog(String title, String qrData) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(
                '支付數據：\n$qrData',
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: qrData));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('支付數據已複製到剪貼板')),
                  );
                },
                child: const Text('複製支付數據'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('關閉'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('支付功能測試'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 金額輸入
            TextField(
              controller: _amountController,
              decoration: const InputDecoration(
                labelText: '支付金額 (HKD)',
                hintText: '請輸入支付金額，例如：0.1',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 16),
            
            // 支付按鈕
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _testWechatPayment,
                    icon: const Icon(Icons.payment),
                    label: const Text('微信支付'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 48),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _testAlipayPayment,
                    icon: const Icon(Icons.account_balance_wallet),
                    label: const Text('支付寶'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 48),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _testUnionpayPayment,
                    icon: const Icon(Icons.credit_card),
                    label: const Text('銀聯'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 48),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // 載入指示器
            if (_isLoading)
              const LinearProgressIndicator(),
            
            const SizedBox(height: 16),
            
            // 結果顯示
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    _result.isEmpty ? '請點擊上方按鈕測試支付功能' : _result,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
            
            // 配置資訊
            Container(
              margin: const EdgeInsets.only(top: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('配置資訊：', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('API URL: ${PaymentApiConfig.baseUrl}'),
                  Text('微信/支付寶商戶號: ${PaymentApiConfig.mchNo}'),
                  Text('雲閃付商戶號: ${PaymentApiConfig.unionPayMchNo}'),
                  Text('微信/支付寶 AppId: ${PaymentApiConfig.wechatAlipayAppId}'),
                  Text('銀聯 AppId: ${PaymentApiConfig.unionPayQrAppId}'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }
}