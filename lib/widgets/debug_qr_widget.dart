import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:iboard_app/providers/app_data_provider.dart';
import 'package:iboard_app/utils/qr_code_util.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

/// 二维码调试工具组件
class QrDebugWidget extends StatefulWidget {
  const QrDebugWidget({super.key});

  @override
  QrDebugWidgetState createState() => QrDebugWidgetState();
}

class QrDebugWidgetState extends State<QrDebugWidget> {
  final Logger _logger = Logger();
  Map<String, dynamic> _debugInfo = {};

  @override
  void initState() {
    super.initState();
    _checkQrCodeStatus();
  }

  ///构建意见投诉二维码数据
  String? _buildComplaintQrCodeData(AppDataProvider appDataProvider) {
    final ismartId = appDataProvider.settingsModel?.building.ismartId;
    if (ismartId != null && ismartId.isNotEmpty) {
      return 'https://ismart.legend-in.com.hk/blg_cs_public/$ismartId';
    }
    return null;
  }

  ///构建住户登记二维码数据
  String? _buildRegistrationQrCodeData(AppDataProvider appDataProvider) {
    final ismartId = appDataProvider.settingsModel?.building.ismartId;
    if (ismartId != null && ismartId.isNotEmpty) {
      return 'https://ismart.legend-in.com.hk/regform/$ismartId';
    }
    return null;
  }

  ///1，检查二维码状态
  Future<void> _checkQrCodeStatus() async {
    final appDataProvider = context.read<AppDataProvider>();
    final debugInfo = <String, dynamic>{};

    // 基本信息
    debugInfo['登录状态'] = appDataProvider.isLoggedIn;
    debugInfo['ismartId'] =
        appDataProvider.settingsModel?.building.ismartId ?? 'null';

    // 添加本地缓存路径信息
    await _addCachePathInfo(debugInfo);

    // 投訴二维码状态
    final complaintQrCode = appDataProvider.cachedComplaintQrCode;
    final complaintQrData = _buildComplaintQrCodeData(appDataProvider);
    debugInfo['投訴二维码'] = {
      '是否为空': complaintQrCode == null,
      '本地文件路径': complaintQrCode ?? 'null',
      '生成的目标URL': complaintQrData ?? 'null',
      '类型': '本地生成文件',
    };

    if (complaintQrCode != null) {
      // 检查本地文件
      final file = File(complaintQrCode);
      final exists = await file.exists();
      debugInfo['投訴二维码']['文件存在'] = exists;

      if (exists) {
        final stat = await file.stat();
        debugInfo['投訴二维码']['文件大小'] = '${stat.size} bytes';
        debugInfo['投訴二维码']['修改时间'] = stat.modified.toString();
        debugInfo['投訴二维码']['生成状态'] = '✅ 本地生成成功';
      } else {
        debugInfo['投诉二维码']['生成状态'] = '❌ 本地生成失败';
        debugInfo['投訴二维码']['错误信息'] = '本地文件不存在，可能生成失败或文件被删除';
      }
    } else {
      debugInfo['投訴二维码']['生成状态'] = '❌ 未生成';
      debugInfo['投訴二维码']['错误信息'] = '二维码未生成或初始化失败';
    }

    // 登记二维码状态
    final registrationQrCode = appDataProvider.cachedRegistrationQrCode;
    final registrationQrData = _buildRegistrationQrCodeData(appDataProvider);
    debugInfo['登记二维码'] = {
      '是否为空': registrationQrCode == null,
      '本地文件路径': registrationQrCode ?? 'null',
      '生成的目标URL': registrationQrData ?? 'null',
      '类型': '本地生成文件',
    };

    if (registrationQrCode != null) {
      // 检查本地文件
      final file = File(registrationQrCode);
      final exists = await file.exists();
      debugInfo['登记二维码']['文件存在'] = exists;

      if (exists) {
        final stat = await file.stat();
        debugInfo['登记二维码']['文件大小'] = '${stat.size} bytes';
        debugInfo['登记二维码']['修改时间'] = stat.modified.toString();
        debugInfo['登记二维码']['生成状态'] = '✅ 本地生成成功';
      } else {
        debugInfo['登记二维码']['生成状态'] = '❌ 本地生成失败';
        debugInfo['登记二维码']['错误信息'] = '本地文件不存在，可能生成失败或文件被删除';
      }
    } else {
      debugInfo['登记二维码']['生成状态'] = '❌ 未生成';
      debugInfo['登记二维码']['错误信息'] = '二维码未生成或初始化失败';
    }

    // 添加本地生成工具信息
    await _addLocalGenerationInfo(debugInfo, appDataProvider);

    setState(() {
      _debugInfo = debugInfo;
    });

    // _logger.i('🐛 二维码调试信息: $_debugInfo');
  }

  ///添加本地生成工具信息
  Future<void> _addLocalGenerationInfo(
      Map<String, dynamic> debugInfo, AppDataProvider appDataProvider) async {
    try {
      final qrCodeUtil = QrCodeUtil();
      final ismartId = appDataProvider.settingsModel?.building.ismartId;

      debugInfo['本地生成工具'] = {
        '工具状态': '✅ 已加载',
        '工具版本': 'qr_flutter: ^4.1.0',
        '默认尺寸': '88x88',
      };

      if (ismartId != null && ismartId.isNotEmpty) {
        // 测试本地生成功能
        final testData =
            'https://ismart.legend-in.com.hk/blg_cs_public/$ismartId';
        final testImageData = await qrCodeUtil.generateQrCodeImageData(
          data: testData,
          size: 88,
        );

        debugInfo['本地生成工具']['测试生成'] = testImageData != null ? '✅ 成功' : '❌ 失败';
        debugInfo['本地生成工具']['测试数据大小'] =
            testImageData != null ? '${testImageData.length} bytes' : 'null';
        debugInfo['本地生成工具']['数据验证'] =
            qrCodeUtil.isValidQrCodeData(testData) ? '✅ 有效' : '❌ 无效';
      } else {
        debugInfo['本地生成工具']['测试生成'] = '⚠️ 无法测试（ismartId为空）';
      }
    } catch (e) {
      debugInfo['本地生成工具'] = {
        '工具状态': '❌ 加載失敗',
        '錯誤信息': e.toString(),
      };
      _logger.e('❌ 獲取本地生成工具信息失敗', error: e);
    }
  }

  ///添加緩存路徑和錯誤信息
  Future<void> _addCachePathInfo(Map<String, dynamic> debugInfo) async {
    try {
      // 獲取應用文檔目錄
      final directory = await getApplicationDocumentsDirectory();
      final qrCodeDir = Directory('${directory.path}/qr_codes');

      debugInfo['緩存路徑信息'] = {
        '應用文檔目錄': directory.path,
        '二維碼目錄': qrCodeDir.path,
        '二維碼目錄存在': await qrCodeDir.exists(),
      };

      // 如果目錄存在，列出所有文件
      if (await qrCodeDir.exists()) {
        final files = await qrCodeDir.list().toList();
        debugInfo['緩存路徑信息']['目錄文件數量'] = files.length;
        debugInfo['緩存路徑信息']['文件列表'] =
            files.map((f) => f.path.split('/').last).toList();
      } else {
        debugInfo['緩存路徑信息']['錯誤信息'] = '二維碼緩存目錄不存在';
      }

      // 檢查權限
      try {
        if (!await qrCodeDir.exists()) {
          await qrCodeDir.create(recursive: true);
          debugInfo['緩存路徑信息']['目錄創建'] = '成功';
          // 測試寫入權限
          final testFile = File('${qrCodeDir.path}/test.txt');
          await testFile.writeAsString('test');
          await testFile.delete();
          debugInfo['緩存路徑信息']['寫入權限'] = '正常';
        }
      } catch (e) {
        debugInfo['緩存路徑信息']['權限錯誤'] = e.toString();
      }
    } catch (e) {
      debugInfo['緩存路徑信息'] = {'錯誤': '獲取緩存路徑失敗: $e'};
      _logger.e('❌ 獲取緩存路徑信息失敗', error: e);
    }
  }

  ///獲取文本顏色
  Color _getTextColor(String key, dynamic value) {
    // 根據關鍵字和值來設置顏色
    if (value == null || value == 'null') {
      return Colors.red;
    }

    if (key.contains('錯誤') || key.contains('失敗')) {
      return Colors.red;
    }

    if (key.contains('生成狀態') || key.contains('下載狀態')) {
      if (value.toString().contains('✅')) {
        return Colors.green;
      } else if (value.toString().contains('❌')) {
        return Colors.red;
      } else if (value.toString().contains('⚠️')) {
        return Colors.orange;
      }
    }

    if (key.contains('文件存在') && value == false) {
      return Colors.red;
    }

    if (key.contains('寫入權限') && value == '正常') {
      return Colors.green;
    }

    if (key.contains('工具狀態') && value.toString().contains('✅')) {
      return Colors.green;
    }

    if (key.contains('測試生成') && value.toString().contains('✅')) {
      return Colors.green;
    }

    if (key.contains('數據驗證') && value.toString().contains('✅')) {
      return Colors.green;
    }

    return Colors.black87;
  }

  ///獲取文本粗細
  FontWeight _getTextWeight(String key) {
    if (key.contains('生成狀態') || key.contains('下載狀態') || key.contains('錯誤信息')) {
      return FontWeight.bold;
    }
    return FontWeight.normal;
  }

  ///2，手動重新生成投訴二維碼
  Future<void> _regenerateComplaintQrCode() async {
    // _logger.i('🔄 手動重新生成投訴二維碼');
    if (!mounted) return;
    final appDataProvider = context.read<AppDataProvider>();

    try {
      // 清除現有緩存
      await appDataProvider.clearQrCodeCache();

      // 重新生成
      final result = await appDataProvider.generateComplaintQrCode();
      // _logger.i('✅ 投訴二維碼本地重新生成結果: $result');

      // 刷新調試信息
      await _checkQrCodeStatus();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result != null ? '投訴二維碼本地重新生成成功' : '投訴二維碼本地重新生成失敗'),
          backgroundColor: result != null ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      // _logger.e('❌ 重新生成投訴二維碼失敗', error: e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('本地重新生成失敗: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  ///3，手動重新生成登記二維碼
  Future<void> _regenerateRegistrationQrCode() async {
    // _logger.i('🔄 手動重新生成登記二維碼');
    if (!mounted) return;
    final appDataProvider = context.read<AppDataProvider>();

    try {
      // 清除現有緩存
      await appDataProvider.clearQrCodeCache();

      // 重新生成
      final result = await appDataProvider.generateRegistrationQrCode();
      // _logger.i('✅ 登記二維碼本地重新生成結果: $result');

      // 刷新調試信息
      await _checkQrCodeStatus();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result != null ? '登記二維碼本地重新生成成功' : '登記二維碼本地重新生成失敗'),
          backgroundColor: result != null ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      // _logger.e('❌ 重新生成登記二維碼失敗', error: e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('本地重新生成失敗: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  ///4，構建調試信息卡片
  Widget _buildDebugCard(String title, Map<String, dynamic> data) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 8),
            ...data.entries.map((entry) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${entry.key}: ',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Expanded(
                        child: SelectableText(
                          entry.value.toString(),
                          style: TextStyle(
                            color: _getTextColor(entry.key, entry.value),
                            fontWeight: _getTextWeight(entry.key),
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('二维码调试工具'),
        backgroundColor: Colors.blue[100],
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _checkQrCodeStatus,
            tooltip: '刷新状态',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 基本信息
            _buildDebugCard('基本信息', {
              '登录状态': _debugInfo['登录状态'] ?? 'unknown',
              'ismartId': _debugInfo['ismartId'] ?? 'unknown',
            }),

            // 本地生成工具信息
            if (_debugInfo['本地生成工具'] != null)
              _buildDebugCard('本地生成工具', _debugInfo['本地生成工具']!),

            // 緩存路徑信息
            if (_debugInfo['緩存路徑信息'] != null)
              _buildDebugCard('緩存路徑信息', _debugInfo['緩存路徑信息']!),

            // 投訴二维码信息
            if (_debugInfo['投訴二维码'] != null)
              _buildDebugCard('投訴二维码', _debugInfo['投訴二维码']!),

            // 登记二维码信息
            if (_debugInfo['登记二维码'] != null)
              _buildDebugCard('登记二维码', _debugInfo['登记二维码']!),

            const SizedBox(height: 20),

            // 操作按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: _regenerateComplaintQrCode,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('重新生成投訴二维码'),
                ),
                ElevatedButton(
                  onPressed: _regenerateRegistrationQrCode,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('重新生成登记二维码'),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // 全部重新生成按鈕
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  await _regenerateComplaintQrCode();
                  await _regenerateRegistrationQrCode();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('重新生成所有二维码'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
