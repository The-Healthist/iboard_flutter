/// 天气警告映射工具类 - 处理香港天文台API的警告代号和子类型映射
class WeatherWarningMapping {
  /// 主警告类型到子类型的映射
  static const Map<String, Map<String, String>> warningSubtypes = {
    'WFIRE': {
      'WFIREY': '黃色火災危險警告',
      'WFIRER': '紅色火災危險警告',
    },
    'WRAIN': {
      'WRAINA': '黃色暴雨警告信號',
      'WRAINR': '紅色暴雨警告信號',
      'WRAINB': '黑色暴雨警告信號',
    },
    'WTCSGNL': {
      'TC1': '一號戒備信號',
      'TC3': '三號強風信號',
      'TC8NE': '八號東北烈風或暴風信號',
      'TC8SE': '八號東南烈風或暴風信號',
      'TC8SW': '八號西南烈風或暴風信號',
      'TC8NW': '八號西北烈風或暴風信號',
      'TC9': '九號烈風或暴風風力增強信號',
      'TC10': '十號颶風信號',
      'CANCEL': '取消所有熱帶氣旋警告信號',
    },
  };

  /// 主警告类型的基本描述
  static const Map<String, String> mainWarningDescriptions = {
    'WFIRE': '火災危險警告',
    'WFROST': '霜凍警告',
    'WHOT': '酷熱天氣警告',
    'WCOLD': '寒冷天氣警告',
    'WMSGNL': '強烈季候風信號',
    'WTCPRE8': '預警八號熱帶氣旋警告信號之特別報告',
    'WRAIN': '暴雨警告信號',
    'WFNTSA': '新界北部水浸特別報告',
    'WL': '山泥傾瀉警告',
    'WTCSGNL': '熱帶氣旋警告信號',
    'WTMW': '海嘯警告',
    'WTS': '雷暴警告',
  };

  /// 警告代号到图标文件的映射
  static const Map<String, String> warningCodeToIcon = {
    // 火災危險警告
    'WFIREY': 'wfirey.png',
    'WFIRER': 'wfirer.png',
    'WFIRE': 'wfirer.png', // 默認使用紅色

    // 暴雨警告信號
    'WRAINA': 'wraina.png',
    'WRAINR': 'wrainr.png',
    'WRAINB': 'wrainb.png',
    'WRAIN': 'wraina.png', // 默認使用黃色

    // 熱帶氣旋警告信號
    'TC1': 'tc1.png',
    'TC3': 'tc3.png',
    'TC8NE': 'tc8ne.png',
    'TC8SE': 'tc8se.png',
    'TC8SW': 'tc8sw.png',
    'TC8NW': 'tc8nw.png',
    'TC9': 'tc9.png',
    'TC10': 'tc10.png',
    'CANCEL': 'tc1.png', // 取消信號使用默認圖標

    // 其他警告
    'WCOLD': 'wcold.png',
    'WHOT': 'whot.png',
    'WFROST': 'wfrost.png',
    'WMSGNL': 'wmsgnl.png',
    'WFNTSA': 'wfntsa.png',
    'WL': 'wl.png',
    'WTS': 'wts.png',
    'WTMW': 'wtmw.png',
    'WTCPRE8': 'tc1.png', // 預警信號使用一號信號圖標
  };

  ///1，獲取警告的完整描述（包含子類型）
  static String getWarningDescription(
      String warningKey, String warningCode, String? type) {
    // 如果有type字段，優先使用type（適用於熱帶氣旋警告信號）
    if (type != null && type.isNotEmpty) {
      return type;
    }

    // 檢查是否有子類型映射
    if (warningSubtypes.containsKey(warningKey)) {
      final subtypes = warningSubtypes[warningKey]!;
      if (subtypes.containsKey(warningCode)) {
        return subtypes[warningCode]!;
      }
    }

    // 檢查主警告描述
    if (mainWarningDescriptions.containsKey(warningKey)) {
      return mainWarningDescriptions[warningKey]!;
    }

    // 檢查警告代號描述
    if (mainWarningDescriptions.containsKey(warningCode)) {
      return mainWarningDescriptions[warningCode]!;
    }

    // 默認返回警告代號
    return warningCode;
  }

  ///2，獲取警告圖標路徑
  static String getWarningIconPath(String warningCode) {
    final iconFileName =
        warningCodeToIcon[warningCode.toUpperCase()] ?? 'wmsgnl.png';
    return 'assets/images/hko/$iconFileName';
  }

  ///3，檢查是否有子類型
  static bool hasSubtypes(String warningKey) {
    return warningSubtypes.containsKey(warningKey);
  }

  ///4，獲取所有子類型
  static Map<String, String>? getSubtypes(String warningKey) {
    return warningSubtypes[warningKey];
  }

  ///5，獲取警告的優先級（用於排序顯示）
  static int getWarningPriority(String warningCode) {
    switch (warningCode.toUpperCase()) {
      // 最高優先級：熱帶氣旋警告信號
      case 'TC10':
        return 1;
      case 'TC9':
        return 2;
      case 'TC8NE':
      case 'TC8SE':
      case 'TC8SW':
      case 'TC8NW':
        return 3;
      case 'TC3':
        return 4;
      case 'TC1':
        return 5;

      // 高優先級：暴雨警告信號
      case 'WRAINB':
        return 6;
      case 'WRAINR':
        return 7;
      case 'WRAINA':
        return 8;

      // 中優先級：火災危險警告
      case 'WFIRER':
        return 9;
      case 'WFIREY':
        return 10;

      // 其他警告
      case 'WTS':
        return 11;
      case 'WL':
        return 12;
      case 'WHOT':
        return 13;
      case 'WCOLD':
        return 14;
      case 'WFROST':
        return 15;
      case 'WMSGNL':
        return 16;
      case 'WFNTSA':
        return 17;
      case 'WTMW':
        return 18;
      case 'WTCPRE8':
        return 19;

      default:
        return 99;
    }
  }

  ///6，獲取警告的顏色（用於UI顯示）
  static String getWarningColor(String warningCode) {
    switch (warningCode.toUpperCase()) {
      // 紅色警告
      case 'TC10':
      case 'TC9':
      case 'TC8NE':
      case 'TC8SE':
      case 'TC8SW':
      case 'TC8NW':
      case 'WRAINB':
      case 'WRAINR':
      case 'WFIRER':
        return 'red';

      // 黃色警告
      case 'TC3':
      case 'TC1':
      case 'WRAINA':
      case 'WFIREY':
        return 'yellow';

      // 橙色警告
      case 'WTS':
      case 'WL':
      case 'WHOT':
      case 'WCOLD':
        return 'orange';

      // 藍色警告
      case 'WFROST':
      case 'WMSGNL':
      case 'WFNTSA':
      case 'WTMW':
      case 'WTCPRE8':
        return 'blue';

      default:
        return 'grey';
    }
  }

  ///7，檢查警告是否為熱帶氣旋警告
  static bool isTropicalCycloneWarning(String warningCode) {
    return warningCode.toUpperCase().startsWith('TC') ||
        warningCode.toUpperCase() == 'CANCEL' ||
        warningCode.toUpperCase() == 'WTCPRE8';
  }

  ///8，檢查警告是否為暴雨警告
  static bool isRainWarning(String warningCode) {
    return warningCode.toUpperCase().startsWith('WRAIN');
  }

  ///9，檢查警告是否為火災危險警告
  static bool isFireWarning(String warningCode) {
    return warningCode.toUpperCase().startsWith('WFIRE');
  }

  ///10，獲取警告的簡短描述（用於緊湊顯示）
  static String getShortDescription(String warningCode) {
    switch (warningCode.toUpperCase()) {
      case 'TC10':
        return '十號颶風';
      case 'TC9':
        return '九號烈風';
      case 'TC8NE':
        return '八號東北';
      case 'TC8SE':
        return '八號東南';
      case 'TC8SW':
        return '八號西南';
      case 'TC8NW':
        return '八號西北';
      case 'TC3':
        return '三號強風';
      case 'TC1':
        return '一號戒備';
      case 'WRAINB':
        return '黑色暴雨';
      case 'WRAINR':
        return '紅色暴雨';
      case 'WRAINA':
        return '黃色暴雨';
      case 'WFIRER':
        return '紅色火災';
      case 'WFIREY':
        return '黃色火災';
      case 'WTS':
        return '雷暴';
      case 'WL':
        return '山泥傾瀉';
      case 'WHOT':
        return '酷熱';
      case 'WCOLD':
        return '寒冷';
      case 'WFROST':
        return '霜凍';
      case 'WMSGNL':
        return '季候風';
      case 'WFNTSA':
        return '水浸';
      case 'WTMW':
        return '海嘯';
      case 'WTCPRE8':
        return '預警八號';
      default:
        return warningCode;
    }
  }
}

