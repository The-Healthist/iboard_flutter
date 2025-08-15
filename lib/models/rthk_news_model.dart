import 'package:intl/intl.dart';

/// 香港电台新闻模型
/// 对应RTHK RSS数据结构
class RthkNewsModel {
  final String title;
  final String guid;
  final String link;
  final DateTime pubDate;
  final String formattedTime;

  const RthkNewsModel({
    required this.title,
    required this.guid,
    required this.link,
    required this.pubDate,
    required this.formattedTime,
  });

  ///1, 从RSS XML数据创建新闻模型
  factory RthkNewsModel.fromRssXml(Map<String, dynamic> item) {
    // 解析发布时间
    DateTime pubDate = _parseRssDate(item['pubDate'] ?? '');

    // 格式化时间为 HH:mm 格式
    String formattedTime =
        '${pubDate.hour.toString().padLeft(2, '0')}:${pubDate.minute.toString().padLeft(2, '0')}';

    return RthkNewsModel(
      title: _extractCDataContent(item['title'] ?? ''),
      guid: item['guid'] ?? '',
      link: item['link'] ?? '',
      pubDate: pubDate,
      formattedTime: formattedTime,
    );
  }

  ///2, 提取CDATA内容
  static String _extractCDataContent(String rawContent) {
    // 查找CDATA标签
    final cdataPattern = RegExp(r'<!\[CDATA\[(.*?)\]\]>', dotAll: true);
    final match = cdataPattern.firstMatch(rawContent);

    if (match != null) {
      return match.group(1)?.trim() ?? rawContent;
    }

    // 如果没有CDATA标签，直接返回原内容
    return rawContent;
  }

  ///3, 解析RSS日期格式
  static DateTime _parseRssDate(String dateStr) {
    try {
      // 尝试解析RTHK的日期格式: "Fri, 15 Aug 2025 16:40:08 +0800"
      final formats = [
        'EEE, dd MMM yyyy HH:mm:ss Z',
        'EEE, dd MMM yyyy HH:mm:ss',
        'yyyy-MM-dd HH:mm:ss',
      ];

      for (final format in formats) {
        try {
          return DateFormat(format).parse(dateStr);
        } catch (e) {
          // 继续尝试下一个格式
        }
      }

      // 如果所有格式都失败，返回当前时间
      return DateTime.now();
    } catch (e) {
      return DateTime.now();
    }
  }

  ///4, 获取显示格式的新闻文本
  String get displayText => '($formattedTime) $title';

  ///5, 转换为JSON格式
  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'guid': guid,
      'link': link,
      'pubDate': pubDate.toIso8601String(),
      'formattedTime': formattedTime,
    };
  }

  ///6, 从JSON格式创建模型
  factory RthkNewsModel.fromJson(Map<String, dynamic> json) {
    return RthkNewsModel(
      title: json['title'] ?? '',
      guid: json['guid'] ?? '',
      link: json['link'] ?? '',
      pubDate: DateTime.tryParse(json['pubDate'] ?? '') ?? DateTime.now(),
      formattedTime: json['formattedTime'] ?? '',
    );
  }

  @override
  String toString() {
    return 'RthkNewsModel(title: $title, time: $formattedTime)';
  }
}
