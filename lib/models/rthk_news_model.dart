import 'package:intl/intl.dart';

/// 香港電台新聞模型
/// 對應RTHK RSS資料結構
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

  ///1, 從RSS XML資料建立新聞模型
  factory RthkNewsModel.fromRssXml(Map<String, dynamic> item) {
    // 解析發佈時間
    DateTime pubDate = _parseRssDate(item['pubDate']?.toString() ?? '');

    // 格式化時間為 HH:mm 格式
    String formattedTime =
        '${pubDate.hour.toString().padLeft(2, '0')}:${pubDate.minute.toString().padLeft(2, '0')}';

    return RthkNewsModel(
      title: _extractCDataContent(item['title']?.toString() ?? ''),
      guid: item['guid']?.toString() ?? '',
      link: item['link']?.toString() ?? '',
      pubDate: pubDate,
      formattedTime: formattedTime,
    );
  }

  ///2, 提取CDATA內容
  static String _extractCDataContent(String rawContent) {
    // 查找CDATA標籤
    final cdataPattern = RegExp(r'<!\[CDATA\[(.*?)\]\]>', dotAll: true);
    final match = cdataPattern.firstMatch(rawContent);

    if (match != null) {
      return match.group(1)?.trim() ?? rawContent;
    }

    // 如果沒有CDATA標籤，直接回傳原內容
    return rawContent;
  }

  ///3, 解析RSS日期格式
  static DateTime _parseRssDate(String dateStr) {
    try {
      // 嘗試解析RTHK的日期格式: "Fri, 15 Aug 2025 16:40:08 +0800"
      final formats = [
        'EEE, dd MMM yyyy HH:mm:ss Z',
        'EEE, dd MMM yyyy HH:mm:ss',
        'yyyy-MM-dd HH:mm:ss',
      ];

      for (final format in formats) {
        try {
          return DateFormat(format).parse(dateStr);
        } catch (e) {
          // 繼續嘗試下一個格式
        }
      }

      // 如果所有格式都失敗，回傳當前時間
      return DateTime.now();
    } catch (e) {
      return DateTime.now();
    }
  }

  ///4, 取得顯示格式的新聞文字
  String get displayText => '($formattedTime) $title';

  ///5, 轉換為JSON格式
  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'guid': guid,
      'link': link,
      'pubDate': pubDate.toIso8601String(),
      'formattedTime': formattedTime,
    };
  }

  ///6, 從JSON格式建立模型
  factory RthkNewsModel.fromJson(Map<String, dynamic> json) {
    final parsedPubDate = DateTime.tryParse(json['pubDate']?.toString() ?? '');
    final pubDate = parsedPubDate ?? DateTime.now();
    return RthkNewsModel(
      title: json['title']?.toString() ?? '',
      guid: json['guid']?.toString() ?? '',
      link: json['link']?.toString() ?? '',
      pubDate: pubDate,
      formattedTime: json['formattedTime']?.toString() ??
          '${pubDate.hour.toString().padLeft(2, '0')}:${pubDate.minute.toString().padLeft(2, '0')}',
    );
  }

  @override
  String toString() {
    return 'RthkNewsModel(title: $title, time: $formattedTime)';
  }
}
