// import 'package:flutter/material.dart';
// import 'package:iboard_app/models/news_announcement_model.dart';
// import 'package:iboard_app/widgets/debug_news_announcement_widget.dart';
// import 'package:intl/intl.dart';
// import 'package:iboard_app/providers/news_announcement_provider.dart'; // Added import for NewsAnnouncementProvider
// import 'package:provider/provider.dart'; // Added import for ChangeNotifierProvider

// /// 新闻公报显示组件
// /// 参考天气预报的卡片样式，显示单条新闻信息
// class NewsAnnouncementWidget extends StatelessWidget {
//   final NewsAnnouncementModel news;
//   final double? width;
//   final double? height;

//   const NewsAnnouncementWidget({
//     Key? key,
//     required this.news,
//     this.width,
//     this.height,
//   }) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       width: width,
//       height: height,
//       margin: const EdgeInsets.all(8.0),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(12.0),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withOpacity(0.1),
//             blurRadius: 8.0,
//             offset: const Offset(0, 2),
//           ),
//         ],
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           // 标题栏
//           Container(
//             width: double.infinity,
//             padding: const EdgeInsets.all(16.0),
//             decoration: BoxDecoration(
//               color: Colors.blue.shade600,
//               borderRadius: const BorderRadius.only(
//                 topLeft: Radius.circular(12.0),
//                 topRight: Radius.circular(12.0),
//               ),
//             ),
//             child: Row(
//               children: [
//                 Icon(
//                   Icons.newspaper,
//                   color: Colors.white,
//                   size: 24,
//                 ),
//                 const SizedBox(width: 8),
//                 Expanded(
//                   child: Text(
//                     '香港特区政府新闻公报',
//                     style: TextStyle(
//                       color: Colors.white,
//                       fontSize: 16,
//                       fontWeight: FontWeight.bold,
//                     ),
//                   ),
//                 ),
//                 Container(
//                   padding: const EdgeInsets.symmetric(
//                     horizontal: 8.0,
//                     vertical: 4.0,
//                   ),
//                   decoration: BoxDecoration(
//                     color: Colors.white.withOpacity(0.2),
//                     borderRadius: BorderRadius.circular(12.0),
//                   ),
//                   child: Text(
//                     _formatDate(news.pubDate),
//                     style: TextStyle(
//                       color: Colors.white,
//                       fontSize: 12,
//                       fontWeight: FontWeight.w500,
//                     ),
//                   ),
//                 ),
//               ],
//             ),
//           ),

//           // 新闻内容
//           Expanded(
//             child: Padding(
//               padding: const EdgeInsets.all(16.0),
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   // 新闻标题
//                   Text(
//                     news.title,
//                     style: TextStyle(
//                       fontSize: 18,
//                       fontWeight: FontWeight.bold,
//                       color: Colors.grey.shade800,
//                       height: 1.3,
//                     ),
//                     maxLines: 3,
//                     overflow: TextOverflow.ellipsis,
//                   ),

//                   const SizedBox(height: 12),

//                   // 新闻摘要
//                   Expanded(
//                     child: Text(
//                       news.description,
//                       style: TextStyle(
//                         fontSize: 14,
//                         color: Colors.grey.shade600,
//                         height: 1.4,
//                       ),
//                       maxLines: 8,
//                       overflow: TextOverflow.ellipsis,
//                     ),
//                   ),

//                   const SizedBox(height: 12),

//                   // 底部信息栏
//                   Row(
//                     children: [
//                       Icon(
//                         Icons.access_time,
//                         size: 16,
//                         color: Colors.grey.shade500,
//                       ),
//                       const SizedBox(width: 4),
//                       Text(
//                         _formatTime(news.pubDate),
//                         style: TextStyle(
//                           fontSize: 12,
//                           color: Colors.grey.shade500,
//                         ),
//                       ),
//                       const Spacer(),
//                       Container(
//                         padding: const EdgeInsets.symmetric(
//                           horizontal: 8.0,
//                           vertical: 4.0,
//                         ),
//                         decoration: BoxDecoration(
//                           color: Colors.blue.shade50,
//                           borderRadius: BorderRadius.circular(8.0),
//                           border: Border.all(
//                             color: Colors.blue.shade200,
//                             width: 1,
//                           ),
//                         ),
//                         child: Text(
//                           '政府公告',
//                           style: TextStyle(
//                             fontSize: 11,
//                             color: Colors.blue.shade700,
//                             fontWeight: FontWeight.w500,
//                           ),
//                         ),
//                       ),
//                     ],
//                   ),
//                 ],
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   ///1, 格式化日期显示
//   String _formatDate(DateTime date) {
//     final now = DateTime.now();
//     final today = DateTime(now.year, now.month, now.day);
//     final newsDate = DateTime(date.year, date.month, date.day);

//     if (newsDate == today) {
//       return '今日';
//     } else if (newsDate == today.subtract(const Duration(days: 1))) {
//       return '昨日';
//     } else {
//       return DateFormat('MM/dd').format(date);
//     }
//   }

//   ///2, 格式化时间显示
//   String _formatTime(DateTime date) {
//     return DateFormat('HH:mm').format(date);
//   }
// }

// /// 新闻公报轮播组件
// /// 用于在底部轮播中显示新闻公报
// class NewsAnnouncementCarouselWidget extends StatelessWidget {
//   final NewsAnnouncementModel news;
//   final double? width;
//   final double? height;

//   const NewsAnnouncementCarouselWidget({
//     Key? key,
//     required this.news,
//     this.width,
//     this.height,
//   }) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     return Stack(
//       children: [
//         Container(
//           width: width,
//           height: height,
//           margin: const EdgeInsets.symmetric(horizontal: 4.0),
//           decoration: BoxDecoration(
//             color: Colors.white,
//             borderRadius: BorderRadius.circular(8.0),
//             boxShadow: [
//               BoxShadow(
//                 color: Colors.black.withOpacity(0.1),
//                 blurRadius: 4.0,
//                 offset: const Offset(0, 1),
//               ),
//             ],
//           ),
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               // 标题栏
//               Container(
//                 width: double.infinity,
//                 padding: const EdgeInsets.all(12.0),
//                 decoration: const BoxDecoration(
//                   borderRadius: BorderRadius.only(
//                     topLeft: Radius.circular(8.0),
//                     topRight: Radius.circular(8.0),
//                   ),
//                 ),
//                 child: Row(
//                   children: [
//                     Icon(
//                       Icons.newspaper,
//                       color: Colors.blue.shade600,
//                       size: 18,
//                     ),
//                     const SizedBox(width: 6),
//                     Expanded(
//                       child: Text(
//                         '新闻公报', // 固定显示"新闻公报"，不显示具体标题
//                         style: TextStyle(
//                           color: Colors.grey.shade800,
//                           fontSize: 14,
//                           fontWeight: FontWeight.bold,
//                         ),
//                         maxLines: 1,
//                         overflow: TextOverflow.ellipsis,
//                       ),
//                     ),
//                     Text(
//                       news.formattedTime, // 使用新的时间格式
//                       style: TextStyle(
//                         color: Colors.grey.shade600,
//                         fontSize: 11,
//                         fontWeight: FontWeight.w500,
//                       ),
//                     ),
//                   ],
//                 ),
//               ),

//               // 新闻内容
//               Expanded(
//                 child: Padding(
//                   padding: const EdgeInsets.all(12.0),
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       // 新闻标题
//                       Text(
//                         news.title,
//                         style: TextStyle(
//                           fontSize: 16,
//                           fontWeight: FontWeight.bold,
//                           color: Colors.grey.shade800,
//                           height: 1.3,
//                         ),
//                         maxLines: 2,
//                         overflow: TextOverflow.ellipsis,
//                       ),

//                       const SizedBox(height: 8),

//                       // 新闻内容（不包含标题，只显示描述内容）
//                       Expanded(
//                         child: Text(
//                           news.description,
//                           style: TextStyle(
//                             fontSize: 13,
//                             color: Colors.grey.shade600,
//                             height: 1.4,
//                           ),
//                           maxLines: 4,
//                           overflow: TextOverflow.ellipsis,
//                         ),
//                       ),

//                       const SizedBox(height: 8),

//                       // 时间信息
//                       Row(
//                         children: [
//                           Icon(
//                             Icons.access_time,
//                             size: 14,
//                             color: Colors.grey.shade500,
//                           ),
//                           const SizedBox(width: 4),
//                           Text(
//                             news.formattedTime, // 使用新的时间格式
//                             style: TextStyle(
//                               fontSize: 11,
//                               color: Colors.grey.shade500,
//                             ),
//                           ),
//                         ],
//                       ),
//                     ],
//                   ),
//                 ),
//               ),
//             ],
//           ),
//         ),

//         // Debug按钮 - 右上角
//         Positioned(
//           top: 8,
//           right: 8,
//           child: GestureDetector(
//             onTap: () {
//               print('🐛 Debug按钮被点击！'); // 添加调试信息
//               _showDebugDialog(context);
//             },
//             child: Container(
//               padding: const EdgeInsets.all(6),
//               decoration: BoxDecoration(
//                 color: Colors.blue.shade600,
//                 borderRadius: BorderRadius.circular(6),
//                 border: Border.all(color: Colors.white, width: 1),
//                 boxShadow: [
//                   BoxShadow(
//                     color: Colors.black.withOpacity(0.3),
//                     blurRadius: 4,
//                     offset: const Offset(0, 2),
//                   ),
//                 ],
//               ),
//               child: const Icon(
//                 Icons.bug_report,
//                 color: Colors.white,
//                 size: 14,
//               ),
//             ),
//           ),
//         ),
//       ],
//     );
//   }

//   ///3, 格式化日期显示（轮播版本）
//   String _formatDate(DateTime date) {
//     final now = DateTime.now();
//     final today = DateTime(now.year, now.month, now.day);
//     final newsDate = DateTime(date.year, date.month, date.day);

//     if (newsDate == today) {
//       return '今日';
//     } else if (newsDate == today.subtract(const Duration(days: 1))) {
//       return '昨日';
//     } else {
//       return DateFormat('MM/dd').format(date);
//     }
//   }

//   ///4, 格式化时间显示（轮播版本）
//   String _formatTime(DateTime date) {
//     return DateFormat('HH:mm').format(date);
//   }

//   ///5, 显示调试对话框
//   void _showDebugDialog(BuildContext context) {
//     print('🐛 开始显示debug对话框'); // 添加调试信息
    
//     // 获取NewsAnnouncementProvider实例
//     final newsProvider = Provider.of<NewsAnnouncementProvider>(context, listen: false);
    
//     // 使用Navigator.push而不是showDialog，避免ParentDataWidget错误
//     Navigator.of(context).push(
//       MaterialPageRoute(
//         builder: (context) => Scaffold(
//           appBar: AppBar(
//             title: const Text('新闻公报调试信息'),
//             backgroundColor: Colors.blue.shade600,
//             foregroundColor: Colors.white,
//             actions: [
//               IconButton(
//                 icon: const Icon(Icons.refresh),
//                 onPressed: () {
//                   newsProvider.refreshNews();
//                 },
//                 tooltip: '刷新',
//               ),
//             ],
//           ),
//           body: const DebugNewsAnnouncementWidget(),
//         ),
//       ),
//     );
//   }
// }
