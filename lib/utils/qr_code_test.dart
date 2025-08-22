import 'package:flutter/material.dart';
import 'package:iboard_app/utils/qr_code_util.dart';
import 'package:logger/logger.dart';

/// 二维码生成工具测试页面
/// 用于验证二维码生成功能是否正常工作
class QrCodeTestPage extends StatefulWidget {
  const QrCodeTestPage({super.key});

  @override
  _QrCodeTestPageState createState() => _QrCodeTestPageState();
}

class _QrCodeTestPageState extends State<QrCodeTestPage> {
  final Logger _logger = Logger();
  final QrCodeUtil _qrCodeUtil = QrCodeUtil();

  @override
  void initState() {
    super.initState();
    // _logger.i('🧪 二维码测试页面初始化');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('二维码生成测试'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 测试标题
            const Text(
              '二维码生成工具测试',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),

            // 基本二维码测试
            _buildTestSection(
              title: '1. 基本二维码测试',
              children: [
                _buildQrCodeTest(
                  title: '测试URL',
                  data: 'https://example.com/test',
                ),
                const SizedBox(height: 16),
                _buildQrCodeTest(
                  title: '测试文本',
                  data: 'Hello World!',
                ),
              ],
            ),

            const SizedBox(height: 20),

            // 意见投诉二维码测试
            _buildTestSection(
              title: '2. 意见投诉二维码测试',
              children: [
                _buildQrCodeTest(
                  title: '投诉二维码',
                  data: 'https://ismart.legend-in.com.hk/blg_cs_public/0314100',
                ),
              ],
            ),

            const SizedBox(height: 20),

            // 住户登记二维码测试
            _buildTestSection(
              title: '3. 住户登记二维码测试',
              children: [
                _buildQrCodeTest(
                  title: '登记二维码',
                  data: 'https://ismart.legend-in.com.hk/regform/0314100',
                ),
              ],
            ),

            const SizedBox(height: 20),

            // 不同尺寸测试
            _buildTestSection(
              title: '4. 不同尺寸测试',
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildQrCodeTest(
                        title: '64x64',
                        data: 'https://example.com/small',
                        size: 64,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildQrCodeTest(
                        title: '88x88',
                        data: 'https://example.com/medium',
                        size: 88,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildQrCodeTest(
                        title: '120x120',
                        data: 'https://example.com/large',
                        size: 120,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 20),

            // 不同颜色测试
            _buildTestSection(
              title: '5. 不同颜色测试',
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildQrCodeTest(
                        title: '黑色',
                        data: 'https://example.com/black',
                        foregroundColor: Colors.black,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildQrCodeTest(
                        title: '蓝色',
                        data: 'https://example.com/blue',
                        foregroundColor: Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildQrCodeTest(
                        title: '红色',
                        data: 'https://example.com/red',
                        foregroundColor: Colors.red,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 20),

            // 工具方法测试
            _buildTestSection(
              title: '6. 工具方法测试',
              children: [
                _buildMethodTest(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  ///1，构建测试区域
  Widget _buildTestSection({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  ///2，构建二维码测试项
  Widget _buildQrCodeTest({
    required String title,
    required String data,
    double size = 88.0,
    Color foregroundColor = Colors.black,
  }) {
    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          _qrCodeUtil.generateQrCodeWidget(
            data: data,
            size: size,
            foregroundColor: foregroundColor,
          ),
          const SizedBox(height: 8),
          Text(
            data,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  ///3，构建方法测试
  Widget _buildMethodTest() {
    return Column(
      children: [
        // 数据验证测试
        _buildMethodTestItem(
          title: '数据验证测试',
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  '投诉URL: ${_qrCodeUtil.isValidQrCodeData('https://ismart.legend-in.com.hk/blg_cs_public/0314100')}'),
              Text(
                  '登记URL: ${_qrCodeUtil.isValidQrCodeData('https://ismart.legend-in.com.hk/regform/0314100')}'),
              Text(
                  'invalid_data: ${_qrCodeUtil.isValidQrCodeData('invalid_data')}'),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // URL测试
        _buildMethodTestItem(
          title: 'URL测试',
          content: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  '投诉URL: https://ismart.legend-in.com.hk/blg_cs_public/0314100'),
              Text('登记URL: https://ismart.legend-in.com.hk/regform/0314100'),
            ],
          ),
        ),
      ],
    );
  }

  ///4，构建方法测试项
  Widget _buildMethodTestItem({
    required String title,
    required Widget content,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          content,
        ],
      ),
    );
  }
}
