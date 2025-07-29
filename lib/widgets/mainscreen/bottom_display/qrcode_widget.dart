import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:iboard_app/providers/app_data_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:logger/logger.dart';

class QrcodeWidget extends StatefulWidget {
  const QrcodeWidget({Key? key}) : super(key: key);

  @override
  _QrcodeWidgetState createState() => _QrcodeWidgetState();
}

class _QrcodeWidgetState extends State<QrcodeWidget> {
  final Logger _logger = Logger();
  bool _showComplaintQr = true; // true显示意见投诉，false显示住户登记

  @override
  void initState() {
    super.initState();
    _logger.i('🔲 QrcodeWidget初始化');
  }

  ///1，切换二维码显示
  void _switchQrCode() {
    setState(() {
      _showComplaintQr = !_showComplaintQr;
    });
    _logger.i('🔄 二维码切换: ${_showComplaintQr ? "意见投诉" : "住户登记"}');
  }

  ///2，构建二维码卡片
  Widget _buildQrCodeCard({
    required String title,
    required String subtitle,
    required String? qrCodeUrl,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2.0),
        padding: const EdgeInsets.all(8.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10.0),
          border: Border.all(color: Colors.lightBlue.shade200, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // 二维码区域
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: qrCodeUrl != null
                  ? CachedNetworkImage(
                      imageUrl: qrCodeUrl,
                      width: 70,
                      height: 70,
                      fit: BoxFit.contain,
                      placeholder: (context, url) => const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.0),
                        ),
                      ),
                      errorWidget: (context, url, error) => const Icon(
                        Icons.qr_code,
                        size: 40,
                        color: Colors.grey,
                      ),
                    )
                  : const Icon(
                      Icons.qr_code,
                      size: 40,
                      color: Colors.grey,
                    ),
            ),
            const SizedBox(width: 12),
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
                      fontSize: 11,
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppDataProvider>(
      builder: (context, appDataProvider, child) {
        // 根据当前显示状态选择对应的二维码数据
        final qrCodeUrl = _showComplaintQr
            ? appDataProvider.cachedComplaintQrCode
            : appDataProvider.cachedRegistrationQrCode;

        final title = _showComplaintQr ? '意見投訴' : '住戶登記';
        final subtitle = _showComplaintQr ? '掃QRCode提交意見投訴' : '掃QRCode進行住戶登記';

        return Container(
          height: 100,
          child: _buildQrCodeCard(
            title: title,
            subtitle: subtitle,
            qrCodeUrl: qrCodeUrl,
            onTap: _switchQrCode,
          ),
        );
      },
    );
  }
}
