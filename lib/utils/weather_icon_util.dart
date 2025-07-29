import 'package:flutter/services.dart';
import 'package:logger/logger.dart';

/// 天气图标工具类 - 管理本地和网络天气图标资源
class WeatherIconUtil {
  static final Logger _logger = Logger();

  /// 天气图标缓存
  static final Map<int, String> _iconCache = {};

  ///1，获取天气图标路径（优先使用本地资源，fallback到网络）
  static String getWeatherIconPath(int iconCode) {
    // 检查缓存
    if (_iconCache.containsKey(iconCode)) {
      return _iconCache[iconCode]!;
    }

    // 本地资源路径
    final localPath = 'assets/images/hko/pic$iconCode.png';

    // 缓存并返回本地路径
    _iconCache[iconCode] = localPath;
    return localPath;
  }

  ///2，获取网络天气图标URL（作为备选方案）
  static String getWeatherIconUrl(int iconCode) {
    return 'https://www.hko.gov.hk/images/HKOWxIconOutline/pic$iconCode.png';
  }

  ///3，检查本地图标是否存在
  static Future<bool> isLocalIconAvailable(int iconCode) async {
    try {
      final localPath = 'assets/images/hko/pic$iconCode.png';
      await rootBundle.load(localPath);
      _logger.d('✅ 本地天气图标存在: pic$iconCode.png');
      return true;
    } catch (e) {
      _logger.w('⚠️ 本地天气图标不存在: pic$iconCode.png');
      return false;
    }
  }

  ///4，获取台风警告图标路径
  static String getTyphoonWarningIconPath(String warningCode) {
    return 'assets/images/hko/tc$warningCode.png';
  }

  ///5，获取天气警告图标路径
  static String getWeatherWarningIconPath(String warningType) {
    // 根据警告类型映射到对应图标
    switch (warningType.toLowerCase()) {
      case 'cold':
        return 'assets/images/hko/wcold.png';
      case 'hot':
        return 'assets/images/hko/whot.png';
      case 'frost':
        return 'assets/images/hko/wfrost.png';
      case 'fire_danger_red':
        return 'assets/images/hko/wfirer.png';
      case 'fire_danger_yellow':
        return 'assets/images/hko/wfirey.png';
      case 'rain_amber':
        return 'assets/images/hko/wraina.png';
      case 'rain_black':
        return 'assets/images/hko/wrainb.png';
      case 'rain_red':
        return 'assets/images/hko/wrainr.png';
      case 'landslip':
        return 'assets/images/hko/wl.png';
      case 'thunderstorm':
        return 'assets/images/hko/wts.png';
      case 'strong_monsoon':
        return 'assets/images/hko/wmsgnl.png';
      case 'tsunami':
        return 'assets/images/hko/wfntsa.png';
      default:
        _logger.w('⚠️ 未知的天气警告类型: $warningType');
        return 'assets/images/hko/wmsgnl.png'; // 默认图标
    }
  }

  ///6，根据警告代码获取天气警告图标路径（直接映射警告代码到图标文件）
  static String getWeatherWarningIconPathByCode(String warningCode) {
    // 将警告代码直接映射到图标文件名（转换为小写）
    final iconFileName = warningCode.toLowerCase();
    final iconPath = 'assets/images/hko/$iconFileName.png';

    _logger.d('🌦️ 获取警告图标: $warningCode -> $iconPath');
    return iconPath;
  }

  ///7，获取温湿度图标路径
  static String getTemperatureIconPath() => 'assets/images/hko/temp.png';
  static String getHumidityIconPath() => 'assets/images/hko/hum.png';
  static String getUVIconPath() => 'assets/images/hko/uv.png';
  static String getLightningIconPath() => 'assets/images/hko/lightning.png';

  ///8，预加载常用天气图标
  static Future<void> preloadCommonIcons() async {
    _logger.i('🔄 开始预加载常用天气图标...');

    // 常用天气图标代码
    final commonIconCodes = [
      50,
      51,
      52,
      53,
      54,
      60,
      61,
      62,
      63,
      64,
      65,
      70,
      71,
      72,
      73,
      74,
      75,
      76,
      77,
      80,
      81,
      82,
      83,
      84,
      85,
      90,
      91,
      92,
      93
    ];

    int loadedCount = 0;
    for (final iconCode in commonIconCodes) {
      if (await isLocalIconAvailable(iconCode)) {
        loadedCount++;
      }
    }

    _logger.i('✅ 天气图标预加载完成: $loadedCount/${commonIconCodes.length}');
  }

  ///9，清理图标缓存
  static void clearCache() {
    _iconCache.clear();
    _logger.d('🗑️ 天气图标缓存已清理');
  }
}
