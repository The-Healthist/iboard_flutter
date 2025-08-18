// import 'dart:async';
// import 'package:flutter/material.dart';
// import 'package:iboard_app/providers/news_announcement_provider.dart';
// import 'package:provider/provider.dart';

// /// 新闻公报调试组件
// /// 显示新闻公报的更新倒计时和列表信息
// class DebugNewsAnnouncementWidget extends StatefulWidget {
//   const DebugNewsAnnouncementWidget({Key? key}) : super(key: key);

//   @override
//   _DebugNewsAnnouncementWidgetState createState() =>
//       _DebugNewsAnnouncementWidgetState();
// }

// class _DebugNewsAnnouncementWidgetState
//     extends State<DebugNewsAnnouncementWidget> {
//   Timer? _updateTimer;

//   @override
//   void initState() {
//     super.initState();
//     _startUpdateTimer();
//   }

//   @override
//   void dispose() {
//     _updateTimer?.cancel();
//     _updateTimer = null;
//     super.dispose();
//   }

//   ///1, 启动更新定时器 - 每秒更新一次时间显示
//   void _startUpdateTimer() {
//     _updateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
//       if (mounted) {
//         setState(() {
//           // 触发UI更新
//         });
//       }
//     });
//   }

//   ///2, 获取更新倒计时显示
//   String _getUpdateCountdown(NewsAnnouncementProvider provider) {
//     return provider.getUpdateCountdown();
//   }

//   ///3, 获取最后更新时间显示
//   String _getLastUpdateDisplay(NewsAnnouncementProvider provider) {
//     return provider.getLastUpdateDisplay();
//   }

//   ///4, 获取新闻列表信息
//   Map<String, String> _buildNewsList(NewsAnnouncementProvider provider) {
//     if (provider.newsList.isEmpty) {
//       return {
//         '状态': '无新闻',
//       };
//     }

//     Map<String, String> newsInfo = {};

//     // 显示所有新闻的完整信息
//     for (int i = 0; i < provider.newsList.length; i++) {
//       final news = provider.newsList[i];

//       // 新闻标题
//       newsInfo['新闻${i + 1} - 标题'] = news.title;

//       // 发布时间
//       newsInfo['新闻${i + 1} - 发布时间'] = _formatDateTime(news.pubDate);

//       // 新闻内容（完整内容）
//       newsInfo['新闻${i + 1} - 内容'] = news.description;

//       // 分隔线（除了最后一条新闻）
//       if (i < provider.newsList.length - 1) {
//         newsInfo['新闻${i + 1} - 分隔线'] = '─────────────────';
//       }
//     }

//     return newsInfo;
//   }

//   ///5, 格式化日期时间显示
//   String _formatDateTime(DateTime dateTime) {
//     final now = DateTime.now();
//     final today = DateTime(now.year, now.month, now.day);
//     final newsDate = DateTime(dateTime.year, dateTime.month, dateTime.day);

//     String dateStr;
//     if (newsDate == today) {
//       dateStr = '今日';
//     } else if (newsDate == today.subtract(const Duration(days: 1))) {
//       dateStr = '昨日';
//     } else {
//       dateStr = '${dateTime.month}/${dateTime.day}';
//     }

//     return '$dateStr ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('新闻公报调试工具'),
//         backgroundColor: Colors.blue[100],
//         actions: [
//           IconButton(
//             icon: const Icon(Icons.refresh),
//             onPressed: () {
//               // 刷新新闻数据
//               final provider = context.read<NewsAnnouncementProvider>();
//               provider.refreshNews();
//             },
//             tooltip: '刷新状态',
//           ),
//         ],
//       ),
//       body: SingleChildScrollView(
//         padding: const EdgeInsets.all(16),
//         child: Column(
//           children: [
//             // 基本信息
//             _buildDebugCard('基本信息', {
//               '新闻数量':
//                   context.read<NewsAnnouncementProvider>().newsCount.toString(),
//               '最后更新': _getLastUpdateDisplay(
//                   context.read<NewsAnnouncementProvider>()),
//               '下次更新':
//                   _getUpdateCountdown(context.read<NewsAnnouncementProvider>()),
//               '状态': context.read<NewsAnnouncementProvider>().isLoading
//                   ? '⏳更新中'
//                   : context.read<NewsAnnouncementProvider>().hasError
//                       ? '❌错误'
//                       : '✅正常',
//             }),

//             // 新闻列表信息
//             if (context.read<NewsAnnouncementProvider>().newsList.isNotEmpty)
//               _buildDebugCard('新闻列表',
//                   _buildNewsList(context.read<NewsAnnouncementProvider>())),

//             const SizedBox(height: 20),

//             // 操作按钮
//             Row(
//               mainAxisAlignment: MainAxisAlignment.spaceEvenly,
//               children: [
//                 ElevatedButton(
//                   onPressed: () {
//                     final provider = context.read<NewsAnnouncementProvider>();
//                     provider.refreshNews();
//                   },
//                   style: ElevatedButton.styleFrom(
//                     backgroundColor: Colors.blue,
//                   ),
//                   child: const Text('刷新新闻'),
//                 ),
//                 ElevatedButton(
//                   onPressed: () {
//                     final provider = context.read<NewsAnnouncementProvider>();
//                     provider.clearNews();
//                   },
//                   style: ElevatedButton.styleFrom(
//                     backgroundColor: Colors.red,
//                   ),
//                   child: const Text('清空新闻'),
//                 ),
//               ],
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildDebugCard(String title, Map<String, String> info) {
//     return Card(
//       elevation: 2.0,
//       child: Padding(
//         padding: const EdgeInsets.all(16.0),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             Text(
//               title,
//               style: const TextStyle(
//                 fontSize: 18,
//                 fontWeight: FontWeight.bold,
//                 color: Colors.blue,
//               ),
//             ),
//             const SizedBox(height: 10),
//             ...info.entries.map((entry) {
//               return Padding(
//                 padding: const EdgeInsets.symmetric(vertical: 4.0),
//                 child: Row(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Text(
//                       '${entry.key}: ',
//                       style: TextStyle(
//                         fontSize: 14,
//                         fontWeight: FontWeight.w500,
//                         color: Colors.grey.shade700,
//                       ),
//                     ),
//                     Expanded(
//                       child: Text(
//                         entry.value,
//                         style: TextStyle(
//                           fontSize: 14,
//                           fontWeight: FontWeight.w600,
//                           color: _getTextColor(entry.key, entry.value),
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),
//               );
//             }).toList(),
//           ],
//         ),
//       ),
//     );
//   }

//   ///6, 获取文本颜色
//   Color _getTextColor(String key, String value) {
//     // 根据关键字和值来设置颜色
//     if (value == 'null' || value.isEmpty) {
//       return Colors.red;
//     }

//     if (key.contains('错误') || key.contains('失败')) {
//       return Colors.red;
//     }

//     if (key.contains('状态')) {
//       if (value.contains('✅')) {
//         return Colors.green;
//       } else if (value.contains('❌')) {
//         return Colors.red;
//       } else if (value.contains('⏳')) {
//         return Colors.orange;
//       }
//     }

//     if (key.contains('标题')) {
//       return Colors.blue.shade800;
//     }

//     if (key.contains('内容')) {
//       return Colors.black87;
//     }

//     if (key.contains('时间')) {
//       return Colors.green.shade700;
//     }

//     if (key.contains('分隔线')) {
//       return Colors.grey.shade500;
//     }

//     // 默认颜色
//     return Colors.black87;
//   }
// }
