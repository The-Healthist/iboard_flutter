import 'package:package_info_plus/package_info_plus.dart';
import 'package:logger/logger.dart';

///1. 版本工具类 - 处理版本比较和获取本地版本信息
class VersionUtil {
  static final Logger _logger = Logger();

  ///2. 获取当前应用版本信息
  static Future<Map<String, String>> getCurrentAppVersion() async {
    try {
      PackageInfo packageInfo = await PackageInfo.fromPlatform();

      return {
        'version': packageInfo.version,
        'buildNumber': packageInfo.buildNumber,
        'appName': packageInfo.appName,
        'packageName': packageInfo.packageName,
      };
    } catch (e) {
      _logger.e('獲取應用版本信息失敗: $e');
      return {
        'version': '1.0.0',
        'buildNumber': '1',
        'appName': 'iBoard',
        'packageName': 'com.ismart.iboard',
      };
    }
  }

  ///3. 比较版本号 - 返回值: 1表示version1更新, -1表示version2更新, 0表示相同
  static int compareVersions(String version1, String version2) {
    final v1Parts = _parseVersionParts(version1);
    final v2Parts = _parseVersionParts(version2);

    // 补齐版本号位数
    final maxLength =
        v1Parts.length > v2Parts.length ? v1Parts.length : v2Parts.length;
    while (v1Parts.length < maxLength) {
      v1Parts.add(0);
    }
    while (v2Parts.length < maxLength) {
      v2Parts.add(0);
    }

    for (int i = 0; i < maxLength; i++) {
      if (v1Parts[i] > v2Parts[i]) return 1;
      if (v1Parts[i] < v2Parts[i]) return -1;
    }

    return 0;
  }

  ///4. 比较构建号
  static int compareBuildNumbers(String build1, String build2) {
    final b1 = int.tryParse(build1.trim()) ?? 0;
    final b2 = int.tryParse(build2.trim()) ?? 0;

    if (b1 > b2) return 1;
    if (b1 < b2) return -1;
    return 0;
  }

  ///5. 检查是否需要更新 - 综合版本号和构建号判断
  static bool needsUpdate(String currentVersion, String currentBuild,
      String remoteVersion, String remoteBuild) {
    int versionCompare = compareVersions(currentVersion, remoteVersion);

    // 如果远程版本更高，需要更新
    if (versionCompare < 0) return true;

    // 如果版本相同，比较构建号
    if (versionCompare == 0) {
      int buildCompare = compareBuildNumbers(currentBuild, remoteBuild);
      return buildCompare < 0;
    }

    // 当前版本更高，不需要更新
    return false;
  }

  ///6. 格式化版本信息显示
  static String formatVersionInfo(String version, String buildNumber) {
    return 'v$version ($buildNumber)';
  }

  ///7. 验证版本号格式
  static bool isValidVersionFormat(String version) {
    final RegExp versionRegex = RegExp(r'^\d+(\.\d+)*$');
    return versionRegex.hasMatch(version);
  }

  ///8. 验证构建号格式
  static bool isValidBuildNumber(String buildNumber) {
    final RegExp buildRegex = RegExp(r'^\d+$');
    return buildRegex.hasMatch(buildNumber.trim());
  }

  static List<int> _parseVersionParts(String version) {
    return version
        .trim()
        .split('.')
        .map((part) => RegExp(r'^\d+').firstMatch(part)?.group(0))
        .map((part) => int.tryParse(part ?? '') ?? 0)
        .toList();
  }
}
