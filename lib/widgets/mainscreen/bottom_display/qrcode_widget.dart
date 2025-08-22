import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:iboard_app/providers/app_data_provider.dart';
import 'package:iboard_app/utils/qr_code_util.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:logger/logger.dart';
import 'dart:io';

class QrcodeWidget extends StatefulWidget {
  final double? containerHeight; // 可选的容器高度参数

  const QrcodeWidget({
    super.key,
    this.containerHeight,
  });

  @override
  QrcodeWidgetState createState() => QrcodeWidgetState();
}

class QrcodeWidgetState extends State<QrcodeWidget> {
  final Logger _logger = Logger();

  @override
  void initState() {
    super.initState();
    // _logger.i('🔲 QrcodeWidget初始化');

    // 在Widget初始化后立即检查并生成二维码
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndGenerateQrCodes();
    });
  }

  ///1，检查并生成二维码（带自动修复）
  void _checkAndGenerateQrCodes() {
    final appDataProvider = context.read<AppDataProvider>();
    // _logger.i('🔍 检查二维码生成状态...');

    // 检查投诉二维码
    if (appDataProvider.cachedComplaintQrCode == null) {
      // _logger.w('⚠️ 投诉二维码未生成，尝试初始化...');
    } else {
      // _logger.d('投诉二维码: ${appDataProvider.cachedComplaintQrCode}');
    }

    // 检查登记二维码
    if (appDataProvider.cachedRegistrationQrCode == null) {
      // _logger.w('⚠️ 登记二维码未生成，尝试初始化...');
    } else {
      // _logger.d('登记二维码: ${appDataProvider.cachedRegistrationQrCode}');
    }

    // 如果二维码未生成，尝试初始化
    if (appDataProvider.cachedComplaintQrCode == null ||
        appDataProvider.cachedRegistrationQrCode == null) {
      // _logger.w('⚠️ 二维码未生成，尝试完整初始化...');
      appDataProvider.initializeQrCodes();
    }
  }

  ///2，构建二维码图片组件（支持本地生成、本地文件和网络URL）- 增强版
  Widget _buildQrCodeImage(String imagePath) {
    // _logger.d('🖼️ 构建二维码图片: $imagePath');

    // 判断是本地文件路径还是网络URL
    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      // _logger.d('🌐 使用网络图片: $imagePath');
      // 网络图片 - 使用增强的错误处理
      return CachedNetworkImage(
        imageUrl: imagePath,
        width: 88,
        height: 88,
        fit: BoxFit.contain,
        // 增加更多的请求头
        httpHeaders: const {
          'User-Agent': 'Mozilla/5.0 (compatible; Flutter App)',
          'Accept': 'image/*,*/*;q=0.8',
        },
        placeholder: (context, url) {
          _logger.d('⏳ 加载中: $url');
          return const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.0),
          );
        },
        errorWidget: (context, url, error) {
          _logger.e('❌ 网络图片加载失败: $url, 错误: $error');

          // 显示错误信息和重试按钮
          return Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.red.shade300),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 30,
                  color: Colors.red.shade400,
                ),
                const SizedBox(height: 4),
                Text(
                  '加载失败',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.red.shade600,
                  ),
                ),
                const SizedBox(height: 2),
                GestureDetector(
                  onTap: () {
                    // _logger.i('🔄 用户点击重试加载二维码');
                    // 清除缓存并重新加载
                    CachedNetworkImage.evictFromCache(url);
                    // 触发重建
                    if (mounted) {
                      setState(() {});
                    }
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Text(
                      '重试',
                      style: TextStyle(
                        fontSize: 8,
                        color: Colors.blue.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
        // 设置缓存时间
        cacheKey: imagePath,
        memCacheWidth: 88,
        memCacheHeight: 88,
      );
    } else {
      // _logger.d('📱 使用本地文件: $imagePath');
      // 本地文件
      final file = File(imagePath);
      return FutureBuilder<bool>(
        future: file.exists(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.0),
            );
          }

          if (snapshot.data == true) {
            return Image.file(
              file,
              width: 88,
              height: 88,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                // _logger.e('❌ 本地文件加载失败: $imagePath, 错误: $error');
                return const Icon(
                  Icons.qr_code,
                  size: 60,
                  color: Colors.grey,
                );
              },
            );
          } else {
            // _logger.w('⚠️ 本地二维码文件不存在: $imagePath');
            return const Icon(
              Icons.qr_code,
              size: 60,
              color: Colors.grey,
            );
          }
        },
      );
    }
  }

  ///2.1，构建本地生成的二维码Widget
  Widget _buildLocalGeneratedQrCode({
    required String qrData,
    double size = 88.0,
  }) {
    // _logger.d('🔲 使用本地生成二维码: $qrData');
    return QrCodeUtil().generateQrCodeWidget(
      data: qrData,
      size: size,
    );
  }

  ///3，构建单个二维码卡片
  Widget _buildQrCodeCard({
    required String title,
    required String subtitle,
    required String? qrCodeUrl,
    String? qrData,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: Colors.grey.shade300, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          // 二维码区域 - 调整尺寸避免溢出
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8.0),
            ),
            child: Center(
              child: _buildQrCodeContent(qrCodeUrl, qrData),
            ),
          ),
          const SizedBox(width: 16),
          // 文字区域
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.blueGrey[800],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blueGrey[600],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  ///3.1，构建二维码内容（优先使用本地生成）
  Widget _buildQrCodeContent(String? qrCodeUrl, String? qrData) {
    // 优先使用本地生成的二维码数据
    if (qrData != null) {
      // _logger.d('🔲 使用本地生成的二维码数据');
      return _buildLocalGeneratedQrCode(qrData: qrData);
    }

    // 其次使用缓存的二维码URL
    if (qrCodeUrl != null) {
      // _logger.d('🖼️ 使用缓存的二维码URL');
      return _buildQrCodeImage(qrCodeUrl);
    }

    // 最后显示默认图标
    // _logger.w('⚠️ 没有可用的二维码数据，显示默认图标');
    return const Icon(
      Icons.qr_code,
      size: 60,
      color: Colors.grey,
    );
  }

  ///3.2，构建意见投诉二维码数据
  String? _buildComplaintQrCodeData(AppDataProvider appDataProvider) {
    final ismartId = appDataProvider.settingsModel?.building.ismartId;
    if (ismartId != null && ismartId.isNotEmpty) {
      return 'https://ismart.legend-in.com.hk/blg_cs_public/$ismartId';
    }
    return null;
  }

  ///3.3，构建住户登记二维码数据
  String? _buildRegistrationQrCodeData(AppDataProvider appDataProvider) {
    final ismartId = appDataProvider.settingsModel?.building.ismartId;
    if (ismartId != null && ismartId.isNotEmpty) {
      return 'https://ismart.legend-in.com.hk/regform/$ismartId';
    }
    return null;
  }

  ///4，构建二维码组件UI - 使用动态高度
  @override
  Widget build(BuildContext context) {
    return Consumer<AppDataProvider>(
      builder: (context, appDataProvider, child) {
        // _logger.d(
        //     '🔍 检查二维码状态: 投诉=${appDataProvider.cachedComplaintQrCode != null}, 登记=${appDataProvider.cachedRegistrationQrCode != null}');

        // 计算容器高度 - 优先使用传入的高度，否则使用默认高度
        final double containerHeight = widget.containerHeight ?? 150;

        return Container(
          height: containerHeight, // 使用动态计算的高度
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Stack(
            children: [
              Row(
                children: [
                  // 意见投诉二维码
                  Expanded(
                    child: _buildQrCodeCard(
                      title: '意見投訴',
                      subtitle: '掃QRCode提交意見投訴',
                      qrCodeUrl: appDataProvider.cachedComplaintQrCode,
                      qrData: _buildComplaintQrCodeData(appDataProvider),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // 住户登记二维码
                  Expanded(
                    child: _buildQrCodeCard(
                      title: '住戶登記',
                      subtitle: '掃QRCode進行住戶登記',
                      qrCodeUrl: appDataProvider.cachedRegistrationQrCode,
                      qrData: _buildRegistrationQrCodeData(appDataProvider),
                    ),
                  ),
                ],
              ),
              // 调试按钮（仅在Debug模式显示）- 已注释
              // if (const bool.fromEnvironment('dart.vm.product') == false)
              //   Positioned(
              //     top: 0,
              //     right: 0,
              //     child: Row(
              //       children: [
              //         // 二维码测试按钮
              //         GestureDetector(
              //           onTap: () {
              //             Navigator.of(context).push(
              //               MaterialPageRoute(
              //                 builder: (context) => const QrCodeTestPage(),
              //               ),
              //             );
              //           },
              //           child: Container(
              //             width: 30,
              //             height: 30,
              //             margin: const EdgeInsets.only(right: 8),
              //             decoration: BoxDecoration(
              //               color: Colors.blue.withOpacity(0.8),
              //               borderRadius: BorderRadius.circular(15),
              //             ),
              //             child: const Icon(
              //               Icons.qr_code,
              //               size: 20,
              //               color: Colors.white,
              //             ),
              //           ),
              //         ),
              //         // 原有调试按钮
              //         GestureDetector(
              //           onTap: () {
              //             Navigator.of(context).push(
              //               MaterialPageRoute(
              //                 builder: (context) => const QrDebugWidget(),
              //               ),
              //             );
              //           },
              //           child: Container(
              //             width: 30,
              //             height: 30,
              //             decoration: BoxDecoration(
              //               color: Colors.red.withOpacity(0.8),
              //               borderRadius: BorderRadius.circular(15),
              //             ),
              //             child: const Icon(
              //               Icons.bug_report,
              //               size: 20,
              //               color: Colors.white,
              //             ),
              //           ),
              //         ),
              //       ],
              //     ),
              //   ),
            ],
          ),
        );
      },
    );
  }
}
