/// 打印機狀態原因工具類
class PrinterStateReasons {
  static const Map<String, Map<String, String>> _reasons = {
    'none': {
      'category': 'normal',
      'severity': 'info',
      'description': '無問題',
      'message': '✅ 打印機狀態正常',
      'solution': ''
    },
    'media-needed': {
      'category': 'media',
      'severity': 'warning',
      'description': '需要紙張',
      'message': '📄 請添加紙張',
      'solution': '在紙盒中添加合適的紙張'
    },
    'media-empty': {
      'category': 'media',
      'severity': 'warning',
      'description': '紙張用完',
      'message': '📭 紙張已用完',
      'solution': '在紙盒中添加紙張'
    },
    'media-empty-error': {
      'category': 'media',
      'severity': 'error',
      'description': '紙張用完錯誤',
      'message': '🔴 紙張用完，無法打印',
      'solution': '立即添加紙張到紙盒中'
    },
    'media-empty-report': {
      'category': 'media',
      'severity': 'info',
      'description': '紙張空報告',
      'message': '📭 紙盒可能為空',
      'solution': '檢查紙盒並根據需要添加紙張'
    },
    'media-low': {
      'category': 'media',
      'severity': 'warning',
      'description': '紙張不足',
      'message': '⚠️ 紙張不足，請及時添加',
      'solution': '準備添加更多紙張'
    },
    'media-jam': {
      'category': 'media',
      'severity': 'error',
      'description': '卡紙',
      'message': '🔴 打印機卡紙',
      'solution': '打開打印機清除卡紙，檢查紙張路徑'
    },
    'marker-supply-low': {
      'category': 'marker',
      'severity': 'warning',
      'description': '墨盒/碳粉不足',
      'message': '🟠 墨盒/碳粉不足',
      'solution': '準備更換墨盒或添加碳粉'
    },
    'marker-supply-empty': {
      'category': 'marker',
      'severity': 'error',
      'description': '墨盒/碳粉用完',
      'message': '🔴 墨盒/碳粉已用完',
      'solution': '更換新的墨盒或添加碳粉'
    },
    'toner-low': {
      'category': 'marker',
      'severity': 'warning',
      'description': '碳粉不足',
      'message': '🟠 碳粉不足',
      'solution': '準備更換碳粉盒'
    },
    'toner-empty': {
      'category': 'marker',
      'severity': 'error',
      'description': '碳粉用完',
      'message': '🔴 碳粉已用完',
      'solution': '更換新的碳粉盒'
    },
    'door-open': {
      'category': 'hardware',
      'severity': 'error',
      'description': '門未關閉',
      'message': '🔴 打印機門未關閉',
      'solution': '關閉打印機的所有門和蓋子'
    },
    'cover-open': {
      'category': 'hardware',
      'severity': 'error',
      'description': '蓋子打開',
      'message': '🔴 打印機蓋子打開',
      'solution': '關閉打印機蓋子'
    },
    'offline': {
      'category': 'connection',
      'severity': 'error',
      'description': '離線',
      'message': '⚠️ 打印機離線',
      'solution': '檢查打印機電源和網絡連接'
    },
    'offline-error': {
      'category': 'connection',
      'severity': 'error',
      'description': '離線錯誤',
      'message': '🔴 打印機離線，無法連接',
      'solution': '檢查電源、網絡連接和打印機狀態'
    },
    'output-area-full': {
      'category': 'tray',
      'severity': 'error',
      'description': '出紙區已滿',
      'message': '🔴 出紙區已滿',
      'solution': '清空出紙區的紙張'
    },
    'paused': {
      'category': 'control',
      'severity': 'info',
      'description': '已暫停',
      'message': '⏸️ 打印機已暫停',
      'solution': '恢復打印機運行'
    },
  };

  ///1, 獲取狀態原因的詳細信息
  static Map<String, String> getReasonInfo(String reason) {
    return _reasons[reason] ??
        {
          'category': 'unknown',
          'severity': 'info',
          'description': '未知狀態: $reason',
          'message': '❓ 未知狀態: $reason',
          'solution': '請查看打印機手冊或聯繫技術支持'
        };
  }

  ///2, 獲取狀態原因的汇總信息
  static Map<String, dynamic> getStatusSummary(List<String> reasons) {
    if (reasons.isEmpty || reasons.contains('none')) {
      return {
        'overall_status': 'normal',
        'severity': 'info',
        'message': '✅ 打印機狀態正常',
        'issues_count': 0,
        'categories': <String>[],
        'issues': <Map<String, dynamic>>[]
      };
    }

    final issues = <Map<String, dynamic>>[];
    final categories = <String>{};
    var maxSeverity = 'info';

    const severityOrder = {'info': 0, 'warning': 1, 'error': 2};

    for (final reason in reasons) {
      final info = getReasonInfo(reason);
      issues.add({
        'reason': reason,
        'message': info['message'],
        'solution': info['solution'],
        'severity': info['severity'],
        'category': info['category']
      });
      categories.add(info['category']!);

      if ((severityOrder[info['severity']] ?? 0) >
          (severityOrder[maxSeverity] ?? 0)) {
        maxSeverity = info['severity']!;
      }
    }

    String overallStatus;
    String summaryMessage;

    if (maxSeverity == 'error') {
      overallStatus = 'error';
      summaryMessage = '🔴 打印機有 ${issues.length} 個問題需要解決';
    } else if (maxSeverity == 'warning') {
      overallStatus = 'warning';
      summaryMessage = '🟠 打印機有 ${issues.length} 個警告';
    } else {
      overallStatus = 'info';
      summaryMessage = 'ℹ️ 打印機有 ${issues.length} 個狀態信息';
    }

    return {
      'overall_status': overallStatus,
      'severity': maxSeverity,
      'message': summaryMessage,
      'issues_count': issues.length,
      'categories': categories.toList(),
      'issues': issues
    };
  }

  ///3, 獲取類別的中文描述
  static String getCategoryDescription(String category) {
    const categoryMap = {
      'normal': '正常狀態',
      'media': '紙張問題',
      'marker': '墨盒/碳粉問題',
      'hardware': '硬件問題',
      'connection': '連接問題',
      'tray': '紙盒問題',
      'service': '維護問題',
      'control': '控制狀態',
      'system': '系統問題',
      'unknown': '未知問題'
    };
    return categoryMap[category] ?? category;
  }

  ///4, 從 printer-state-reasons 字符串解析原因列表
  static List<String> parseStateReasons(String? stateReasons) {
    if (stateReasons == null || stateReasons.isEmpty || stateReasons == 'none') {
      return ['none'];
    }
    return stateReasons.split(',').map((e) => e.trim()).toList();
  }
}



