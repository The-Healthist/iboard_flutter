import 'dart:math';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceIdUtil {
  static final DeviceIdUtil _instance = DeviceIdUtil._internal();

  factory DeviceIdUtil() {
    return _instance;
  }

  DeviceIdUtil._internal();

  /// 1, 生成一个唯一的设备ID
  Future<String> generateUniqueDeviceId() async {
    String? existingId = await _getCachedDeviceId();
    if (existingId != null && isValidDeviceId(existingId)) {
      return existingId;
    }
    String deviceInfo = await _getEnhancedDeviceInfo();
    String uniqueId = _generateDeterministicId(deviceInfo);
    String newDeviceId = 'DEVICE_$uniqueId';

    await _cacheDeviceId(newDeviceId);
    return newDeviceId;
  }

  /// 2,从本地存储获取已保存的设备ID
  Future<String?> _getCachedDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('device_id');
    } catch (e) {
      return null;
    }
  }

  /// 3, 保存设备ID到本地存储
  Future<void> _cacheDeviceId(String deviceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_device_id', deviceId);
    } catch (e) {
      // 如果保存失败，继续使用，但不会缓存
    }
  }

  /// 4, 获取增强的设备信息（包含更多唯一性标识符）
  Future<String> _getEnhancedDeviceInfo() async {
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    List<String> infoComponents = [];

    try {
      if (kIsWeb) {
        // Web平台信息
        infoComponents.addAll([
          'platform:web',
          'userAgent:${Uri.encodeComponent('web_agent')}',
          'timestamp:${DateTime.now().millisecondsSinceEpoch ~/ 86400000}', // 按天计算，减少变化
        ]);
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;

        // Android设备信息 - 添加更多唯一性标识符
        infoComponents.addAll([
          'platform:android',
          'model:${androidInfo.model}',
          'androidId:${androidInfo.id}', // Android ID
          'brand:${androidInfo.brand}',
          'board:${androidInfo.board}',
          'device:${androidInfo.device}',
          'display:${androidInfo.display}',
          'hardware:${androidInfo.hardware}',
          'fingerprint:${androidInfo.fingerprint}',
          'product:${androidInfo.product}',
          'manufacturer:${androidInfo.manufacturer}',
          'bootloader:${androidInfo.bootloader}',
          'host:${androidInfo.host}',
          'tags:${androidInfo.tags}',
          'type:${androidInfo.type}',
          'isPhysicalDevice:${androidInfo.isPhysicalDevice}',
          'serialNumber:${androidInfo.serialNumber}', // 序列号（如果可用）
        ]);

        // 尝试获取更多系统信息
        try {
          // 添加一些系统属性
          infoComponents.addAll([
            'sdkInt:${androidInfo.version.sdkInt}',
            'release:${androidInfo.version.release}',
            'codename:${androidInfo.version.codename}',
          ]);
        } catch (e) {
          // 忽略获取失败的信息
        }
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
        infoComponents.addAll([
          'platform:ios',
          'model:${iosInfo.model}',
          'systemName:${iosInfo.systemName}',
          'systemVersion:${iosInfo.systemVersion}',
          'identifierForVendor:${iosInfo.identifierForVendor}',
          'name:${iosInfo.name}',
          'localizedModel:${iosInfo.localizedModel}',
          'isPhysicalDevice:${iosInfo.isPhysicalDevice}',
        ]);
      } else if (defaultTargetPlatform == TargetPlatform.windows) {
        WindowsDeviceInfo winInfo = await deviceInfo.windowsInfo;
        infoComponents.addAll([
          'platform:windows',
          'computerName:${winInfo.computerName}',
          'deviceId:${winInfo.deviceId}',
          'userName:${winInfo.userName}',
        ]);
      } else if (defaultTargetPlatform == TargetPlatform.macOS) {
        MacOsDeviceInfo macInfo = await deviceInfo.macOsInfo;
        infoComponents.addAll([
          'platform:macos',
          'computerName:${macInfo.computerName}',
          'model:${macInfo.model}',
          'systemGUID:${macInfo.systemGUID}',
          'hostName:${macInfo.hostName}',
        ]);
      } else if (defaultTargetPlatform == TargetPlatform.linux) {
        LinuxDeviceInfo linuxInfo = await deviceInfo.linuxInfo;
        infoComponents.addAll([
          'platform:linux',
          'name:${linuxInfo.name}',
          'version:${linuxInfo.version}',
          'id:${linuxInfo.id}',
          'machineId:${linuxInfo.machineId}',
        ]);
      } else {
        infoComponents.addAll([
          'platform:unknown',
          'targetPlatform:${defaultTargetPlatform.toString()}',
        ]);
      }
    } catch (e) {
      // 如果获取设备信息失败，使用fallback + 生成一个随机但持久的标识符
      String fallbackId = await _generateFallbackId();
      infoComponents.addAll([
        'platform:fallback',
        'targetPlatform:${defaultTargetPlatform.toString()}',
        'fallbackId:$fallbackId',
      ]);
    }

    // 将所有组件连接成一个字符串
    return infoComponents.join('|');
  }

  /// 5, 生成fallback ID（当设备信息不可用时）
  Future<String> _generateFallbackId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? existingFallback = prefs.getString('fallback_device_id');

      if (existingFallback != null && existingFallback.isNotEmpty) {
        return existingFallback;
      }

      // 生成新的fallback ID
      String newFallback = _generateRandomPersistentId();
      await prefs.setString('fallback_device_id', newFallback);
      return newFallback;
    } catch (e) {
      // 如果SharedPreferences也失败，使用基于时间的ID（不理想但总比没有好）
      return 'fallback_${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  /// 6, 生成随机但持久的ID
  String _generateRandomPersistentId() {
    final random = Random.secure();
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(16, (index) => chars[random.nextInt(chars.length)])
        .join();
  }

  /// 7, 从设备信息生成确定性ID
  String _generateDeterministicId(String deviceInfo) {
    // 使用SHA-256生成哈希
    var bytes = utf8.encode(deviceInfo);
    var digest = sha256.convert(bytes);

    // 取哈希的前16个字符
    String hashString = digest.toString().substring(0, 16).toUpperCase();

    // 确保结果是8位字母数字
    return _formatDeterministicId(hashString);
  }

  /// 8, 格式化ID为8位大写字母和数字
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

  /// 9, 验证设备ID格式是否正确
  bool isValidDeviceId(String deviceId) {
    final RegExp deviceIdPattern = RegExp(r'^DEVICE_[A-Z0-9]{8}$');
    return deviceIdPattern.hasMatch(deviceId);
  }

  /// 10, 清除本地存储的设备ID（强制重新生成）
  Future<void> clearStoredDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('cached_device_id');
      await prefs.remove('fallback_device_id');
    } catch (e) {
      // 忽略清除失败的错误
    }
  }

  /// 11, 获取设备ID调试信息
  Future<Map<String, dynamic>> getDeviceIdDebugInfo() async {
    try {
      String deviceInfo = await _getEnhancedDeviceInfo();
      String? storedId = await _getCachedDeviceId();

      return {
        'deviceInfo': deviceInfo,
        'storedDeviceId': storedId,
        'platform': defaultTargetPlatform.toString(),
        'infoLength': deviceInfo.length,
        'infoComponents': deviceInfo.split('|').length,
      };
    } catch (e) {
      return {
        'error': e.toString(),
        'platform': defaultTargetPlatform.toString(),
      };
    }
  }
}
