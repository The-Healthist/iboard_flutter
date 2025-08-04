import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:iboard_app/providers/app_data_provider.dart';
import 'package:iboard_app/utils/qr_code_util.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

/// 二维码调试工具组件
class QrDebugWidget extends StatefulWidget {
  const QrDebugWidget({Key? key}) : super(key: key);

  @override
  _QrDebugWidgetState createState() => _QrDebugWidgetState();
}

class _QrDebugWidgetState extends State<QrDebugWidget> {
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

    // 投诉二维码状态
    final complaintQrCode = appDataProvider.cachedComplaintQrCode;
    final complaintQrData = _buildComplaintQrCodeData(appDataProvider);
    debugInfo['投诉二维码'] = {
      '是否为空': complaintQrCode == null,
      '本地文件路径': complaintQrCode ?? 'null',
      '生成的目标URL': complaintQrData ?? 'null',
      '类型': '本地生成文件',
    };

    if (complaintQrCode != null) {
      // 检查本地文件
      final file = File(complaintQrCode);
      final exists = await file.exists();
      debugInfo['投诉二维码']['文件存在'] = exists;

      if (exists) {
        final stat = await file.stat();
        debugInfo['投诉二维码']['文件大小'] = '${stat.size} bytes';
        debugInfo['投诉二维码']['修改时间'] = stat.modified.toString();
        debugInfo['投诉二维码']['生成状态'] = '✅ 本地生成成功';
      } else {
        debugInfo['投诉二维码']['生成状态'] = '❌ 本地生成失败';
        debugInfo['投诉二维码']['错误信息'] = '本地文件不存在，可能生成失败或文件被删除';
      }
    } else {
      debugInfo['投诉二维码']['生成状态'] = '❌ 未生成';
      debugInfo['投诉二维码']['错误信息'] = '二维码未生成或初始化失败';
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

    _logger.i('🐛 二维码调试信息: $_debugInfo');
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
        '工具状态': '❌ 加载失败',
        '错误信息': e.toString(),
      };
      _logger.e('❌ 获取本地生成工具信息失败', error: e);
    }
  }

  ///添加缓存路径和错误信息
  Future<void> _addCachePathInfo(Map<String, dynamic> debugInfo) async {
    try {
      // 获取应用文档目录
      final directory = await getApplicationDocumentsDirectory();
      final qrCodeDir = Directory('${directory.path}/qr_codes');

      debugInfo['缓存路径信息'] = {
        '应用文档目录': directory.path,
        '二维码目录': qrCodeDir.path,
        '二维码目录存在': await qrCodeDir.exists(),
      };

      // 如果目录存在，列出所有文件
      if (await qrCodeDir.exists()) {
        final files = await qrCodeDir.list().toList();
        debugInfo['缓存路径信息']['目录文件数量'] = files.length;
        debugInfo['缓存路径信息']['文件列表'] =
            files.map((f) => f.path.split('/').last).toList();
      } else {
        debugInfo['缓存路径信息']['错误信息'] = '二维码缓存目录不存在';
      }

      // 检查权限
      try {
        if (!await qrCodeDir.exists()) {
          await qrCodeDir.create(recursive: true);
          debugInfo['缓存路径信息']['目录创建'] = '成功';
          // 测试写入权限
          final testFile = File('${qrCodeDir.path}/test.txt');
          await testFile.writeAsString('test');
          await testFile.delete();
          debugInfo['缓存路径信息']['写入权限'] = '正常';
        }
      } catch (e) {
        debugInfo['缓存路径信息']['权限错误'] = e.toString();
      }
    } catch (e) {
      debugInfo['缓存路径信息'] = {'错误': '获取缓存路径失败: $e'};
      _logger.e('❌ 获取缓存路径信息失败', error: e);
    }
  }

  ///获取文本颜色
  Color _getTextColor(String key, dynamic value) {
    // 根据关键字和值来设置颜色
    if (value == null || value == 'null') {
      return Colors.red;
    }

    if (key.contains('错误') || key.contains('失败')) {
      return Colors.red;
    }

    if (key.contains('生成状态') || key.contains('下载状态')) {
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

    if (key.contains('写入权限') && value == '正常') {
      return Colors.green;
    }

    if (key.contains('工具状态') && value.toString().contains('✅')) {
      return Colors.green;
    }

    if (key.contains('测试生成') && value.toString().contains('✅')) {
      return Colors.green;
    }

    if (key.contains('数据验证') && value.toString().contains('✅')) {
      return Colors.green;
    }

    return Colors.black87;
  }

  ///获取文本粗细
  FontWeight _getTextWeight(String key) {
    if (key.contains('生成状态') || key.contains('下载状态') || key.contains('错误信息')) {
      return FontWeight.bold;
    }
    return FontWeight.normal;
  }

  ///2，手动重新生成投诉二维码
  Future<void> _regenerateComplaintQrCode() async {
    _logger.i('🔄 手动重新生成投诉二维码');
    final appDataProvider = context.read<AppDataProvider>();

    try {
      // 清除现有缓存
      await appDataProvider.clearQrCodeCache();

      // 重新生成
      final result = await appDataProvider.generateComplaintQrCode();
      _logger.i('✅ 投诉二维码本地重新生成结果: $result');

      // 刷新调试信息
      await _checkQrCodeStatus();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result != null ? '投诉二维码本地重新生成成功' : '投诉二维码本地重新生成失败'),
          backgroundColor: result != null ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      _logger.e('❌ 重新生成投诉二维码失败', error: e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('本地重新生成失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  ///3，手动重新生成登记二维码
  Future<void> _regenerateRegistrationQrCode() async {
    _logger.i('🔄 手动重新生成登记二维码');
    final appDataProvider = context.read<AppDataProvider>();

    try {
      // 清除现有缓存
      await appDataProvider.clearQrCodeCache();

      // 重新生成
      final result = await appDataProvider.generateRegistrationQrCode();
      _logger.i('✅ 登记二维码本地重新生成结果: $result');

      // 刷新调试信息
      await _checkQrCodeStatus();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result != null ? '登记二维码本地重新生成成功' : '登记二维码本地重新生成失败'),
          backgroundColor: result != null ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      _logger.e('❌ 重新生成登记二维码失败', error: e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('本地重新生成失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  ///4，构建调试信息卡片
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
            ...data.entries
                .map((entry) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${entry.key}: ',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Expanded(
                            child: Text(
                              entry.value.toString(),
                              style: TextStyle(
                                color: _getTextColor(entry.key, entry.value),
                                fontWeight: _getTextWeight(entry.key),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ))
                .toList(),
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
              _buildDebugCard('本地生成工具', _debugInfo['本地生成工具']),

            // 缓存路径信息
            if (_debugInfo['缓存路径信息'] != null)
              _buildDebugCard('缓存路径信息', _debugInfo['缓存路径信息']),

            // 投诉二维码信息
            if (_debugInfo['投诉二维码'] != null)
              _buildDebugCard('投诉二维码', _debugInfo['投诉二维码']),

            // 登记二维码信息
            if (_debugInfo['登记二维码'] != null)
              _buildDebugCard('登记二维码', _debugInfo['登记二维码']),

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
                  child: const Text('重新生成投诉二维码'),
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

            // 全部重新生成按钮
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
