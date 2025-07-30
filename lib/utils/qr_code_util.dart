import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:logger/logger.dart';

/// 二维码生成工具类
/// 提供本地生成二维码的功能，支持自定义尺寸和样式
class QrCodeUtil {
  static final QrCodeUtil _instance = QrCodeUtil._internal();
  final Logger _logger = Logger();

  factory QrCodeUtil() {
    return _instance;
  }

  QrCodeUtil._internal();

  ///1，生成二维码图片数据
  /// 将二维码转换为Uint8List格式的图片数据
  Future<Uint8List?> generateQrCodeImageData({
    required String data,
    int size = 88,
    Color foregroundColor = Colors.black,
    Color backgroundColor = Colors.white,
    int errorCorrectionLevel = QrErrorCorrectLevel.M,
  }) async {
    try {
      _logger.d('🔲 开始生成二维码: $data, 尺寸: ${size}x$size');

      // 创建QR码绘制器
      final qrPainter = QrPainter(
        data: data,
        version: QrVersions.auto,
        gapless: false,
        embeddedImage: null,
        embeddedImageStyle: null,
        errorCorrectionLevel: errorCorrectionLevel,
        color: foregroundColor,
        emptyColor: backgroundColor,
      );

      // 创建图片记录器
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final paint = Paint()..color = backgroundColor;

      // 绘制背景
      canvas.drawRect(
          Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()), paint);

      // 绘制二维码
      qrPainter.paint(canvas, Size(size.toDouble(), size.toDouble()));

      // 完成绘制
      final picture = recorder.endRecording();
      final image = await picture.toImage(size, size);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData != null) {
        final bytes = byteData.buffer.asUint8List();
        _logger.i('✅ 二维码生成成功: ${bytes.length} bytes');
        return bytes;
      } else {
        _logger.e('❌ 二维码生成失败: byteData为null');
        return null;
      }
    } catch (e, stackTrace) {
      _logger.e('❌ 二维码生成异常: $e\n$stackTrace');
      return null;
    }
  }

  ///2，生成二维码Widget
  /// 返回一个可以直接在UI中使用的二维码Widget
  Widget generateQrCodeWidget({
    required String data,
    double size = 88.0,
    Color foregroundColor = Colors.black,
    Color backgroundColor = Colors.white,
    int errorCorrectionLevel = QrErrorCorrectLevel.M,
    EdgeInsetsGeometry? padding,
    BoxDecoration? decoration,
  }) {
    _logger.d('🔲 创建二维码Widget: $data, 尺寸: ${size}x$size');

    Widget qrWidget = QrImageView(
      data: data,
      version: QrVersions.auto,
      size: size,
      gapless: false,
      embeddedImage: null,
      embeddedImageStyle: null,
      errorCorrectionLevel: errorCorrectionLevel,
      eyeStyle: QrEyeStyle(
        eyeShape: QrEyeShape.square,
        color: foregroundColor,
      ),
      dataModuleStyle: QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: foregroundColor,
      ),
      backgroundColor: backgroundColor,
    );

    // 添加装饰
    if (decoration != null) {
      qrWidget = Container(
        decoration: decoration,
        child: qrWidget,
      );
    }

    // 添加内边距
    if (padding != null) {
      qrWidget = Padding(
        padding: padding,
        child: qrWidget,
      );
    }

    return qrWidget;
  }

  ///3，生成带Logo的二维码Widget
  /// 在二维码中心添加Logo图片
  Widget generateQrCodeWithLogoWidget({
    required String data,
    required Widget logo,
    double size = 88.0,
    double logoSize = 20.0,
    Color foregroundColor = Colors.black,
    Color backgroundColor = Colors.white,
    int errorCorrectionLevel = QrErrorCorrectLevel.M,
  }) {
    _logger.d(
        '🔲 创建带Logo的二维码Widget: $data, 尺寸: ${size}x$size, Logo尺寸: ${logoSize}x$logoSize');

    return Stack(
      alignment: Alignment.center,
      children: [
        QrImageView(
          data: data,
          version: QrVersions.auto,
          size: size,
          gapless: false,
          embeddedImage: null,
          embeddedImageStyle: null,
          errorCorrectionLevel: errorCorrectionLevel,
          eyeStyle: QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color: foregroundColor,
          ),
          dataModuleStyle: QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: foregroundColor,
          ),
          backgroundColor: backgroundColor,
        ),
        Container(
          width: logoSize,
          height: logoSize,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(4),
          ),
          child: logo,
        ),
      ],
    );
  }

  ///4，生成意见投诉二维码数据
  /// 根据楼宇ID生成意见投诉二维码
  Future<Uint8List?> generateComplaintQrCode({
    required String ismartId,
    int size = 88,
  }) async {
    final qrData = _buildComplaintQrCodeData(ismartId);
    return generateQrCodeImageData(
      data: qrData,
      size: size,
    );
  }

  ///5，生成住户登记二维码数据
  /// 根据楼宇ID生成住户登记二维码
  Future<Uint8List?> generateRegistrationQrCode({
    required String ismartId,
    int size = 88,
  }) async {
    final qrData = _buildRegistrationQrCodeData(ismartId);
    return generateQrCodeImageData(
      data: qrData,
      size: size,
    );
  }

  ///6，生成意见投诉二维码Widget
  /// 返回意见投诉二维码Widget
  Widget generateComplaintQrCodeWidget({
    required String ismartId,
    double size = 88.0,
    Color foregroundColor = Colors.black,
    Color backgroundColor = Colors.white,
  }) {
    final qrData = _buildComplaintQrCodeData(ismartId);
    return generateQrCodeWidget(
      data: qrData,
      size: size,
      foregroundColor: foregroundColor,
      backgroundColor: backgroundColor,
    );
  }

  ///7，生成住户登记二维码Widget
  /// 返回住户登记二维码Widget
  Widget generateRegistrationQrCodeWidget({
    required String ismartId,
    double size = 88.0,
    Color foregroundColor = Colors.black,
    Color backgroundColor = Colors.white,
  }) {
    final qrData = _buildRegistrationQrCodeData(ismartId);
    return generateQrCodeWidget(
      data: qrData,
      size: size,
      foregroundColor: foregroundColor,
      backgroundColor: backgroundColor,
    );
  }

  ///8，构建意见投诉二维码数据
  /// 生成意见投诉的二维码内容
  String _buildComplaintQrCodeData(String ismartId) {
    return 'https://ismart.legend-in.com.hk/blg_cs_public/$ismartId';
  }

  ///9，构建住户登记二维码数据
  /// 生成住户登记的二维码内容
  String _buildRegistrationQrCodeData(String ismartId) {
    return 'https://ismart.legend-in.com.hk/regform/$ismartId';
  }

  ///10，验证二维码数据格式
  /// 检查二维码数据是否符合预期格式
  bool isValidQrCodeData(String data) {
    if (data.isEmpty) return false;

    // 检查是否是投诉二维码URL
    if (data.startsWith('https://ismart.legend-in.com.hk/blg_cs_public/')) {
      return _validateComplaintQrCodeData(data);
    }

    // 检查是否是登记二维码URL
    if (data.startsWith('https://ismart.legend-in.com.hk/regform/')) {
      return _validateRegistrationQrCodeData(data);
    }

    // 检查是否是有效的URL
    return _validateUrlFormat(data);
  }

  ///11，验证投诉二维码数据格式
  bool _validateComplaintQrCodeData(String data) {
    try {
      final uri = Uri.parse(data);
      return uri.host == 'ismart.legend-in.com.hk' &&
          uri.path.startsWith('/blg_cs_public/') &&
          uri.pathSegments.length >= 2;
    } catch (e) {
      return false;
    }
  }

  ///12，验证登记二维码数据格式
  bool _validateRegistrationQrCodeData(String data) {
    try {
      final uri = Uri.parse(data);
      return uri.host == 'ismart.legend-in.com.hk' &&
          uri.path.startsWith('/regform/') &&
          uri.pathSegments.length >= 2;
    } catch (e) {
      return false;
    }
  }

  ///13，验证URL格式
  bool _validateUrlFormat(String data) {
    try {
      final uri = Uri.parse(data);
      return uri.hasScheme && uri.hasAuthority;
    } catch (e) {
      return false;
    }
  }

  ///14，从二维码数据中提取楼宇ID
  String? extractIsmartIdFromQrCodeData(String data) {
    try {
      final uri = Uri.parse(data);
      if (uri.pathSegments.length >= 2) {
        return uri.pathSegments[1]; // 获取路径中的第二个部分作为楼宇ID
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  ///14，生成测试二维码数据
  /// 用于调试和测试的二维码数据
  Future<Uint8List?> generateTestQrCode({
    String data = 'https://example.com/test',
    int size = 88,
  }) async {
    _logger.d('🧪 生成测试二维码: $data');
    return generateQrCodeImageData(
      data: data,
      size: size,
    );
  }
}
