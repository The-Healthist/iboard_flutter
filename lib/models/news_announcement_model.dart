// import 'package:intl/intl.dart';

// /// 新闻公报模型
// /// 对应香港特区政府新闻公报RSS数据结构
// class NewsAnnouncementModel {
//   final String title;
//   final String description;
//   final String guid;
//   final String link;
//   final DateTime pubDate;
//   final String content;

//   const NewsAnnouncementModel({
//     required this.title,
//     required this.description,
//     required this.guid,
//     required this.link,
//     required this.pubDate,
//     required this.content,
//   });

//   ///1, 从RSS XML数据创建新闻公报模型
//   factory NewsAnnouncementModel.fromRssXml(Map<String, dynamic> item) {
//     // 提取标题 - 查找CDATA内容
//     String title = _extractCDataContent(item['title'] ?? '');

//     // 提取描述内容 - 查找CDATA内容并处理HTML标签
//     String description = _extractCDataContent(item['description'] ?? '');
//     description = _processHtmlContent(description);

//     // 解析发布时间
//     DateTime pubDate = _parseRssDate(item['pubDate'] ?? '');

//     // 只保留当天的新闻
//     final now = DateTime.now();
//     final today = DateTime(now.year, now.month, now.day);
//     final newsDate = DateTime(pubDate.year, pubDate.month, pubDate.day);

//     if (newsDate != today) {
//       throw Exception('新闻不是今天的，跳过');
//     }

//     return NewsAnnouncementModel(
//       title: title,
//       description: description,
//       guid: item['guid'] ?? '',
//       link: item['link'] ?? '',
//       pubDate: pubDate,
//       content: description, // 内容就是处理后的描述
//     );
//   }

//   ///2, 提取CDATA内容
//   static String _extractCDataContent(String rawContent) {
//     // 查找CDATA标签
//     final cdataPattern = RegExp(r'<!\[CDATA\[(.*?)\]\]>', dotAll: true);
//     final match = cdataPattern.firstMatch(rawContent);

//     if (match != null) {
//       return match.group(1)?.trim() ?? rawContent;
//     }

//     // 如果没有CDATA标签，直接返回原内容
//     return rawContent;
//   }

//   ///3, 处理HTML内容，将br标签转换为换行符
//   static String _processHtmlContent(String htmlContent) {
//     // 将<br />、<br>、<br/>等br标签替换为换行符
//     String processed = htmlContent.replaceAll(
//         RegExp(r'<br\s*/?>', caseSensitive: false), '\n');

//     // 移除其他HTML标签
//     processed = processed.replaceAll(RegExp(r'<[^>]*>'), '');

//     // 清理多余的空白字符
//     processed = processed.replaceAll(RegExp(r'\n\s*\n'), '\n\n');
//     processed = processed.trim();

//     return processed;
//   }

//   ///4, 解析RSS日期格式
//   static DateTime _parseRssDate(String dateStr) {
//     try {
//       // 尝试解析常见的RSS日期格式
//       // 例如: "Fri, 15 Aug 2025 12:40:00 +0800"
//       final formats = [
//         'EEE, dd MMM yyyy HH:mm:ss Z',
//         'EEE, dd MMM yyyy HH:mm:ss',
//         'yyyy-MM-dd HH:mm:ss',
//         'dd/MM/yyyy HH:mm:ss',
//       ];

//       for (final format in formats) {
//         try {
//           return DateFormat(format).parse(dateStr);
//         } catch (e) {
//           // 继续尝试下一个格式
//         }
//       }

//       // 如果所有格式都失败，返回当前时间
//       return DateTime.now();
//     } catch (e) {
//       return DateTime.now();
//     }
//   }

//   ///5, 获取格式化的发布时间显示
//   String get formattedPubDate {
//     final now = DateTime.now();
//     final today = DateTime(now.year, now.month, now.day);
//     final newsDate = DateTime(pubDate.year, pubDate.month, pubDate.day);

//     String dateStr;
//     if (newsDate == today) {
//       dateStr = '今日';
//     } else if (newsDate == today.subtract(const Duration(days: 1))) {
//       dateStr = '昨日';
//     } else {
//       dateStr = '${pubDate.month}/${pubDate.day}';
//     }

//     return '$dateStr ${pubDate.hour.toString().padLeft(2, '0')}:${pubDate.minute.toString().padLeft(2, '0')}';
//   }

//   ///6, 获取格式化的时间显示（仅时间）
//   String get formattedTime {
//     return '${pubDate.hour.toString().padLeft(2, '0')}:${pubDate.minute.toString().padLeft(2, '0')}';
//   }

//   ///7, 获取格式化的日期显示（仅日期）
//   String get formattedDate {
//     return '${pubDate.month}/${pubDate.day}';
//   }

//   ///8, 转换为JSON格式（用于本地存储）
//   Map<String, dynamic> toJson() {
//     return {
//       'title': title,
//       'description': description,
//       'guid': guid,
//       'link': link,
//       'pubDate': pubDate.toIso8601String(),
//       'content': content,
//     };
//   }

//   ///9, 从JSON格式创建模型（用于本地存储恢复）
//   factory NewsAnnouncementModel.fromJson(Map<String, dynamic> json) {
//     return NewsAnnouncementModel(
//       title: json['title'] ?? '',
//       description: json['description'] ?? '',
//       guid: json['guid'] ?? '',
//       link: json['link'] ?? '',
//       pubDate: DateTime.tryParse(json['pubDate'] ?? '') ?? DateTime.now(),
//       content: json['content'] ?? '',
//     );
//   }

//   ///10, 复制并修改某些字段
//   NewsAnnouncementModel copyWith({
//     String? title,
//     String? description,
//     String? guid,
//     String? link,
//     DateTime? pubDate,
//     String? content,
//   }) {
//     return NewsAnnouncementModel(
//       title: title ?? this.title,
//       description: description ?? this.description,
//       guid: guid ?? this.guid,
//       link: link ?? this.link,
//       pubDate: pubDate ?? this.pubDate,
//       content: content ?? this.content,
//     );
//   }

//   ///11, 检查是否为有效新闻（有标题和内容）
//   bool get isValid => title.isNotEmpty && description.isNotEmpty;

//   @override
//   String toString() {
//     return 'NewsAnnouncementModel(title: $title, pubDate: $pubDate)';
//   }

//   @override
//   bool operator ==(Object other) {
//     if (identical(this, other)) return true;
//     return other is NewsAnnouncementModel && other.guid == guid;
//   }

//   @override
//   int get hashCode => guid.hashCode;
// }
