import 'dart:math';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

class DeviceIdUtil {
  static final DeviceIdUtil _instance = DeviceIdUtil._internal();

  factory DeviceIdUtil() {
    return _instance;
  }

  DeviceIdUtil._internal();

  /// 生成一个唯一的设备ID
  /// 格式: DEVICE_XXXXXXXX (X为大写字母或数字)
  /// 同一设备每次生成的ID相同
  Future<String> generateUniqueDeviceId() async {
    // 获取设备信息
    String deviceInfo = await _getDeviceInfo();

    // 使用设备信息生成哈希值
    String uniqueId = _generateDeterministicId(deviceInfo);

    // 格式化为DEVICE_XXXXXXXX
    return 'DEVICE_$uniqueId';
  }

  /// 获取设备信息
  Future<String> _getDeviceInfo() async {
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    String info = '';

    try {
      if (kIsWeb) {
        WebBrowserInfo webInfo = await deviceInfo.webBrowserInfo;
        // Web平台尽量收集更多信息以提高唯一性
        info =
            '${webInfo.browserName.name}|${webInfo.platform}|${webInfo.userAgent}|${webInfo.vendor}';
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        // Android平台使用更多固定信息
        info =
            '${androidInfo.model}|${androidInfo.id}|${androidInfo.brand}|${androidInfo.board}|${androidInfo.device}|${androidInfo.display}|${androidInfo.hardware}|${androidInfo.fingerprint}';
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
        // iOS平台使用设备标识符
        info =
            '${iosInfo.model}|${iosInfo.systemName}|${iosInfo.systemVersion}|${iosInfo.identifierForVendor}|${iosInfo.name}|${iosInfo.localizedModel}';
      } else if (defaultTargetPlatform == TargetPlatform.windows) {
        WindowsDeviceInfo winInfo = await deviceInfo.windowsInfo;
        info =
            '${winInfo.computerName}|${winInfo.deviceId}|${winInfo.userName}';
      } else if (defaultTargetPlatform == TargetPlatform.macOS) {
        MacOsDeviceInfo macInfo = await deviceInfo.macOsInfo;
        info =
            '${macInfo.computerName}|${macInfo.model}|${macInfo.systemGUID}|${macInfo.hostName}';
      } else if (defaultTargetPlatform == TargetPlatform.linux) {
        LinuxDeviceInfo linuxInfo = await deviceInfo.linuxInfo;
        info =
            '${linuxInfo.name}|${linuxInfo.version}|${linuxInfo.id}|${linuxInfo.machineId}';
      } else {
        // 其他平台，使用一个固定字符串加上平台信息
        info = 'unknown_platform|${defaultTargetPlatform.toString()}';
      }
    } catch (e) {
      // 如果获取设备信息失败，使用平台信息作为备选
      // 不使用时间戳，因为这会导致每次生成不同的ID
      info = 'fallback|${defaultTargetPlatform.toString()}';
    }

    return info;
  }

  /// 从设备信息生成确定性ID
  String _generateDeterministicId(String deviceInfo) {
    // 使用SHA-256生成哈希
    var bytes = utf8.encode(deviceInfo);
    var digest = sha256.convert(bytes);

    // 取哈希的前16个字符
    String hashString = digest.toString().substring(0, 16).toUpperCase();

    // 确保结果是8位字母数字
    return _formatDeterministicId(hashString);
  }

  /// 格式化ID为8位大写字母和数字
  String _formatDeterministicId(String hashString) {
    String result = '';
    final validChars = RegExp(r'[A-Z0-9]');

    // 创建一个伪随机数生成器，但种子是固定的，基于hashString
    // 这样同样的hashString会产生同样的"随机"序列
    final random = Random(hashString.codeUnits.reduce((a, b) => a + b));

    int charIndex = 0;
    for (int i = 0; i < 8; i++) {
      if (charIndex < hashString.length) {
        String char = hashString[charIndex++];
        // 如果字符不是大写字母或数字，使用确定性的替换
        if (!validChars.hasMatch(char)) {
          // 使用字符的ASCII值来确定性地选择一个有效字符
          int charCode = char.codeUnitAt(0);
          char = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'[charCode % 36];
        }
        result += char;
      } else {
        // 如果hashString不够长，使用确定性的填充
        result += 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'[random.nextInt(36)];
      }
    }

    return result;
  }

  /// 验证设备ID格式是否正确
  bool isValidDeviceId(String deviceId) {
    final RegExp deviceIdPattern = RegExp(r'^DEVICE_[A-Z0-9]{8}$');
    return deviceIdPattern.hasMatch(deviceId);
  }
}
