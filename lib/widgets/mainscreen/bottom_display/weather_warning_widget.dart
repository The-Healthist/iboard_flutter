import 'package:flutter/material.dart';
import 'package:iboard_app/models/weather_warning_model.dart';
import 'package:iboard_app/utils/weather_icon_util.dart';
import 'package:logger/logger.dart';

/// 天气警告显示组件 - 动态显示多个警告信息和图标
class WeatherWarningWidget extends StatelessWidget {
  final WeatherWarningModel? warningData;
  final double fontSize;
  final Color textColor;
  final double iconSize;
  final double verticalSpacing;

  const WeatherWarningWidget({
    Key? key,
    required this.warningData,
    this.fontSize = 14.0,
    this.textColor = const Color.fromARGB(255, 8, 12, 133),
    this.iconSize = 16.0,
    this.verticalSpacing = 2.0,
  }) : super(key: key);

  static final Logger _logger = Logger();

  ///1，构建单个警告行
  Widget _buildWarningRow(String warningCode, WeatherWarningInfo warningInfo) {
    final iconPath =
        WeatherIconUtil.getWeatherWarningIconPathByCode(warningCode);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: verticalSpacing),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 警告图标
          Image.asset(
            iconPath,
            width: iconSize,
            height: iconSize,
            errorBuilder: (context, error, stackTrace) {
              _logger.w('⚠️ 警告图标加载失败: $iconPath');
              return Icon(
                Icons.warning,
                size: iconSize,
                color: Colors.orange,
              );
            },
          ),
          SizedBox(width: iconSize * 0.25), // 图标和文字之间的间距，相对于图标大小
          // 警告文字
          Flexible(
            child: Text(
              warningInfo.name.isNotEmpty ? warningInfo.name : warningCode,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.visible, // 允许文字换行
              softWrap: true, // 启用软换行
            ),
          ),
        ],
      ),
    );
  }

  ///2，构建所有警告的垂直列表显示
  Widget _buildAllWarnings(Map<String, WeatherWarningInfo> warnings) {
    final warningEntries = warnings.entries.toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: warningEntries.map((entry) {
        return _buildWarningRow(entry.key, entry.value);
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 如果没有警告数据，返回空组件
    if (warningData == null || warningData!.warnings.isEmpty) {
      _logger.d('🌤️ 没有天气警告数据');
      return const SizedBox.shrink();
    }

    final warnings = warningData!.warnings;
    final warningCount = warnings.length;

    _logger.i('🌦️ 显示 $warningCount 个天气警告');

    // 始终使用垂直列表显示所有警告，有多少显示多少
    return _buildAllWarnings(warnings);
  }
}
