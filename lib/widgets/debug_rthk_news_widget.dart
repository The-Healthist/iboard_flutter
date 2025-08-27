import 'dart:async';
import 'package:flutter/material.dart';
import 'package:iboard_app/providers/rthk_news_provider.dart';
import 'package:provider/provider.dart';

/// RTHK新闻调试组件
/// 显示RTHK新闻的更新倒计时和列表信息
class DebugRthkNewsWidget extends StatefulWidget {
  const DebugRthkNewsWidget({super.key});

  @override
  DebugRthkNewsWidgetState createState() => DebugRthkNewsWidgetState();
}

class DebugRthkNewsWidgetState extends State<DebugRthkNewsWidget> {
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    _startUpdateTimer();
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _updateTimer = null;
    super.dispose();
  }

  ///1, 启动更新定时器 - 每秒更新一次时间显示
  void _startUpdateTimer() {
    _updateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          // 触发UI更新
        });
      }
    });
  }

  ///2, 获取更新倒计时显示
  String _getUpdateCountdown(RthkNewsProvider provider) {
    if (provider.lastUpdateTime == null) {
      return '未更新';
    }

    final now = DateTime.now();
    final lastUpdate = provider.lastUpdateTime!;
    final nextUpdate = lastUpdate.add(const Duration(minutes: 30));
    final remaining = nextUpdate.difference(now);

    if (remaining.isNegative) {
      return '需要更新';
    }

    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  ///3, 获取最后更新时间显示
  String _getLastUpdateDisplay(RthkNewsProvider provider) {
    if (provider.lastUpdateTime == null) {
      return '未更新';
    }

    final now = DateTime.now();
    final lastUpdate = provider.lastUpdateTime!;
    final difference = now.difference(lastUpdate);

    if (difference.inMinutes < 1) {
      return '刚刚';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}分鈡前';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}小时前';
    } else {
      return '${difference.inDays}天前';
    }
  }

  ///4, 获取新闻列表信息
  Map<String, String> _buildNewsList(RthkNewsProvider provider) {
    if (provider.newsList.isEmpty) {
      return {
        '状态': '无新闻数据',
      };
    }

    Map<String, String> newsInfo = {};

    // 显示所有新闻的完整信息
    for (int i = 0; i < provider.newsList.length; i++) {
      final news = provider.newsList[i];

      // 新闻标题
      newsInfo['新闻${i + 1} - 标题'] = news.title;

      // 发布时间
      newsInfo['新闻${i + 1} - 发布时间'] = _formatDateTime(news.pubDate);

      // 新闻鏈接
      newsInfo['新闻${i + 1} - 鏈接'] = news.link;

      // 新闻GUID
      newsInfo['新闻${i + 1} - GUID'] = news.guid;

      // 分隔线（除了最后一条新闻）
      if (i < provider.newsList.length - 1) {
        newsInfo['新闻${i + 1} - 分隔线'] = '─────────────────';
      }
    }

    return newsInfo;
  }

  ///5, 格式化日期时间显示
  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final newsDate = DateTime(dateTime.year, dateTime.month, dateTime.day);

    String dateStr;
    if (newsDate == today) {
      dateStr = '今日';
    } else if (newsDate == today.subtract(const Duration(days: 1))) {
      dateStr = '昨日';
    } else {
      dateStr = '${dateTime.month}/${dateTime.day}';
    }

    return '$dateStr ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RTHK新闻调试工具'),
        backgroundColor: Colors.blue[100],
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              // 刷新新闻数据
              final provider = context.read<RthkNewsProvider>();
              provider.refreshNews();
            },
            tooltip: '刷新状态',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 基本信息
            _buildDebugCard('基本信息', {
              '新闻数量': context.read<RthkNewsProvider>().newsCount.toString(),
              '最后更新': _getLastUpdateDisplay(context.read<RthkNewsProvider>()),
              '下次更新': _getUpdateCountdown(context.read<RthkNewsProvider>()),
              '状态': context.read<RthkNewsProvider>().isLoading
                  ? '⏳更新中'
                  : context.read<RthkNewsProvider>().hasError
                      ? '❌错误'
                      : '✅正常',
              '错误信息': context.read<RthkNewsProvider>().hasError
                  ? context.read<RthkNewsProvider>().errorMessage
                  : '无',
            }),

            // 新闻列表信息
            if (context.read<RthkNewsProvider>().newsList.isNotEmpty)
              _buildDebugCard(
                  '新闻列表', _buildNewsList(context.read<RthkNewsProvider>())),

            const SizedBox(height: 20),

            // 操作按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () {
                    final provider = context.read<RthkNewsProvider>();
                    provider.refreshNews();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('刷新新闻'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final provider = context.read<RthkNewsProvider>();
                    provider.clearNews();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('清空新闻'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDebugCard(String title, Map<String, String> info) {
    return Card(
      elevation: 2.0,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 10),
            ...info.entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${entry.key}: ',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        entry.value,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _getTextColor(entry.key, entry.value),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  ///6, 获取文本颜色
  Color _getTextColor(String key, String value) {
    // 根据关键字和值来设置颜色
    if (value == 'null' || value.isEmpty) {
      return Colors.red;
    }

    if (key.contains('错误') || key.contains('失败')) {
      return Colors.red;
    }

    if (key.contains('状态')) {
      if (value.contains('✅')) {
        return Colors.green;
      } else if (value.contains('❌')) {
        return Colors.red;
      } else if (value.contains('⏳')) {
        return Colors.orange;
      }
    }

    if (key.contains('标题')) {
      return Colors.blue.shade800;
    }

    if (key.contains('鏈接')) {
      return Colors.blue.shade600;
    }

    if (key.contains('GUID')) {
      return Colors.grey.shade600;
    }

    if (key.contains('时间')) {
      return Colors.green.shade700;
    }

    if (key.contains('分隔线')) {
      return Colors.grey.shade500;
    }

    // 默认颜色
    return Colors.black87;
  }
}
