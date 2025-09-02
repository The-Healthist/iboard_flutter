// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:iboard_app/utils/weather_icon_util.dart';
// import 'package:iboard_app/widgets/weather_icon_widget.dart';
// import 'package:logger/logger.dart';

// /// 天氣圖標調試工具組件
// class WeatherDebugWidget extends StatefulWidget {
//   const WeatherDebugWidget({super.key});

//   @override
//   WeatherDebugWidgetState createState() => WeatherDebugWidgetState();
// }

// class WeatherDebugWidgetState extends State<WeatherDebugWidget> {
//   final Logger _logger = Logger();
//   Map<String, dynamic> _debugInfo = {};
//   bool _isLoading = true;

//   @override
//   void initState() {
//     super.initState();
//     _checkWeatherIconsStatus();
//   }

//   ///0，測試單個資源文件是否可用
//   Future<bool> _testAssetAvailability(String assetPath) async {
//     try {
//       await rootBundle.load(assetPath);
//       // _logger.d('✅ 資源文件可用: $assetPath');
//       return true;
//     } catch (e) {
//       // _logger.w('❌ 資源文件不可用: $assetPath, 錯誤: $e');
//       return false;
//     }
//   }

//   ///1.1，檢查基本資源信息
//   Future<void> _checkBasicResourceInfo(Map<String, dynamic> debugInfo) async {
//     final resourceInfo = <String, dynamic>{};

//     // 測試一些關鍵的資源路徑
//     final testPaths = [
//       'assets/images/hko/pic50.png',
//       'assets/images/hko/temp.png',
//       'assets/images/hko/hum.png',
//     ];

//     int availableTestPaths = 0;
//     for (final path in testPaths) {
//       final isAvailable = await _testAssetAvailability(path);
//       resourceInfo[path] = isAvailable ? '✅ 可用' : '❌ 缺失';
//       if (isAvailable) availableTestPaths++;
//     }

//     debugInfo['資源路徑測試'] = {
//       '測試路徑數量': testPaths.length,
//       '可用路徑數量': availableTestPaths,
//       '路徑測試詳情': resourceInfo,
//       '建議': availableTestPaths == 0
//           ? '❌ 所有測試路徑都無法訪問，請檢查pubspec.yaml中的assets配置'
//           : availableTestPaths < testPaths.length
//               ? '⚠️ 部分資源路徑無法訪問'
//               : '✅ 資源路徑配置正常'
//     };
//   }

//   ///1，檢查天氣圖標狀態
//   Future<void> _checkWeatherIconsStatus() async {
//     if (!mounted) return;
//     setState(() {
//       _isLoading = true;
//     });

//     final debugInfo = <String, dynamic>{};

//     // 首先檢查基本的資源路徑可用性
//     await _checkBasicResourceInfo(debugInfo);

//     // 基本天氣圖標（pic系列）
//     final weatherIconCodes = [
//       50,
//       51,
//       52,
//       53,
//       54,
//       60,
//       61,
//       62,
//       63,
//       64,
//       65,
//       70,
//       71,
//       72,
//       73,
//       74,
//       75,
//       76,
//       77,
//       80,
//       81,
//       82,
//       83,
//       84,
//       85,
//       90,
//       91,
//       92,
//       93
//     ];

//     // 颱風警告圖標
//     final typhoonWarningCodes = [
//       '1',
//       '3',
//       '8ne',
//       '8nw',
//       '8se',
//       '8sw',
//       '9',
//       '10'
//     ];

//     // 天氣警告圖標
//     final weatherWarningTypes = [
//       'cold',
//       'hot',
//       'frost',
//       'fire_danger_red',
//       'fire_danger_yellow',
//       'rain_amber',
//       'rain_black',
//       'rain_red',
//       'landslip',
//       'thunderstorm',
//       'strong_monsoon',
//       'tsunami'
//     ];

//     // 溫濕度圖標
//     final utilityIcons = ['temp', 'hum', 'uv', 'lightning'];

//     await _checkBasicWeatherIcons(debugInfo, weatherIconCodes);
//     await _checkTyphoonWarningIcons(debugInfo, typhoonWarningCodes);
//     await _checkWeatherWarningIcons(debugInfo, weatherWarningTypes);
//     await _checkUtilityIcons(debugInfo, utilityIcons);
//     if (!mounted) return;
//     setState(() {
//       _debugInfo = debugInfo;
//       _isLoading = false;
//     });

//     // _logger.i('🌤️ 天氣圖標調試信息: $_debugInfo');
//   }

//   ///2，檢查基本天氣圖標
//   Future<void> _checkBasicWeatherIcons(
//       Map<String, dynamic> debugInfo, List<int> iconCodes) async {
//     final basicIconsInfo = <String, dynamic>{};
//     int availableCount = 0;

//     for (final iconCode in iconCodes) {
//       final iconPath = WeatherIconUtil.getWeatherIconPath(iconCode);
//       bool isAvailable = false;
//       String errorMessage = '';

//       try {
//         await rootBundle.load(iconPath);
//         isAvailable = true;
//         availableCount++;
//         // _logger.d('✅ 天气图标可用: $iconPath');
//       } catch (e) {
//         errorMessage = e.toString();
//         // _logger.w('❌ 天气图标不可用: $iconPath, 错误: $e');
//       }

//       basicIconsInfo['pic$iconCode.png'] = {
//         '状态': isAvailable ? '✅ 可用' : '❌ 缺失',
//         '路径': iconPath,
//         '网络URL': WeatherIconUtil.getWeatherIconUrl(iconCode),
//         if (!isAvailable) '错误信息': errorMessage,
//       };
//     }

//     debugInfo['基本天气图标'] = {
//       '总数': iconCodes.length,
//       '可用数量': availableCount,
//       '缺失数量': iconCodes.length - availableCount,
//       '完整性': '${(availableCount / iconCodes.length * 100).toStringAsFixed(1)}%',
//       '详细信息': basicIconsInfo,
//     };
//   }

//   ///3，检查台风警告图标
//   Future<void> _checkTyphoonWarningIcons(
//       Map<String, dynamic> debugInfo, List<String> warningCodes) async {
//     final typhoonIconsInfo = <String, dynamic>{};
//     int availableCount = 0;

//     for (final code in warningCodes) {
//       final iconPath = WeatherIconUtil.getTyphoonWarningIconPath(code);
//       bool isAvailable = false;

//       try {
//         await rootBundle.load(iconPath);
//         isAvailable = true;
//         availableCount++;
//       } catch (e) {
//         // 图标不存在
//       }

//       typhoonIconsInfo['tc$code.png'] = {
//         '状态': isAvailable ? '✅ 可用' : '❌ 缺失',
//         '路径': iconPath,
//       };
//     }

//     debugInfo['台风警告图标'] = {
//       '总数': warningCodes.length,
//       '可用数量': availableCount,
//       '缺失数量': warningCodes.length - availableCount,
//       '完整性':
//           '${(availableCount / warningCodes.length * 100).toStringAsFixed(1)}%',
//       '详细信息': typhoonIconsInfo,
//     };
//   }

//   ///4，检查天气警告图标
//   Future<void> _checkWeatherWarningIcons(
//       Map<String, dynamic> debugInfo, List<String> warningTypes) async {
//     final warningIconsInfo = <String, dynamic>{};
//     int availableCount = 0;

//     for (final warningType in warningTypes) {
//       final iconPath = WeatherIconUtil.getWeatherWarningIconPath(warningType);
//       bool isAvailable = false;

//       try {
//         await rootBundle.load(iconPath);
//         isAvailable = true;
//         availableCount++;
//       } catch (e) {
//         // 图标不存在
//       }

//       warningIconsInfo[warningType] = {
//         '状态': isAvailable ? '✅ 可用' : '❌ 缺失',
//         '路径': iconPath,
//         '文件名': iconPath.split('/').last,
//       };
//     }

//     debugInfo['天气警告图标'] = {
//       '总数': warningTypes.length,
//       '可用数量': availableCount,
//       '缺失数量': warningTypes.length - availableCount,
//       '完整性':
//           '${(availableCount / warningTypes.length * 100).toStringAsFixed(1)}%',
//       '详细信息': warningIconsInfo,
//     };
//   }

//   ///5，检查温湿度等工具图标
//   Future<void> _checkUtilityIcons(
//       Map<String, dynamic> debugInfo, List<String> iconNames) async {
//     final utilityIconsInfo = <String, dynamic>{};
//     int availableCount = 0;

//     final iconPaths = {
//       'temp': WeatherIconUtil.getTemperatureIconPath(),
//       'hum': WeatherIconUtil.getHumidityIconPath(),
//       'uv': WeatherIconUtil.getUVIconPath(),
//       'lightning': WeatherIconUtil.getLightningIconPath(),
//     };

//     for (final iconName in iconNames) {
//       final iconPath = iconPaths[iconName]!;
//       bool isAvailable = false;

//       try {
//         await rootBundle.load(iconPath);
//         isAvailable = true;
//         availableCount++;
//       } catch (e) {
//         // 图标不存在
//       }

//       utilityIconsInfo['$iconName.png'] = {
//         '状态': isAvailable ? '✅ 可用' : '❌ 缺失',
//         '路径': iconPath,
//       };
//     }

//     debugInfo['工具图标'] = {
//       '总数': iconNames.length,
//       '可用数量': availableCount,
//       '缺失数量': iconNames.length - availableCount,
//       '完整性': '${(availableCount / iconNames.length * 100).toStringAsFixed(1)}%',
//       '详细信息': utilityIconsInfo,
//     };
//   }

//   ///6，获取文本颜色
//   Color _getTextColor(String key, dynamic value) {
//     if (value == null ||
//         value.toString().contains('缺失') ||
//         value.toString().contains('❌')) {
//       return Colors.red;
//     }

//     if (value.toString().contains('✅') || value.toString().contains('可用')) {
//       return Colors.green;
//     }

//     if (key.contains('完整性')) {
//       final percentage =
//           double.tryParse(value.toString().replaceAll('%', '')) ?? 0;
//       if (percentage == 100) {
//         return Colors.green;
//       } else if (percentage >= 80) {
//         return Colors.orange;
//       } else {
//         return Colors.red;
//       }
//     }

//     return Colors.black87;
//   }

//   ///7，获取文本粗细
//   FontWeight _getTextWeight(String key) {
//     if (key.contains('状态') || key.contains('完整性') || key.contains('总数')) {
//       return FontWeight.bold;
//     }
//     return FontWeight.normal;
//   }

//   ///8，清理图标缓存
//   void _clearIconCache() {
//     WeatherIconUtil.clearCache();
//     // _logger.i('🗑️ 天氣圖標緩存已清理');
//     if (!mounted) return;
//     ScaffoldMessenger.of(context).showSnackBar(
//       const SnackBar(
//         content: SelectableText('天氣圖標緩存已清理'),
//         backgroundColor: Colors.green,
//       ),
//     );
//   }

//   ///9，預加載常用圖標
//   Future<void> _preloadCommonIcons() async {
//     // _logger.i('🔄 開始預加載常用天氣圖標');

//     try {
//       await WeatherIconUtil.preloadCommonIcons();
//       // _logger.i('✅ 天氣圖標預加載完成');
//       if (!mounted) return;
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(
//           content: SelectableText('常用天氣圖標預加載完成'),
//           backgroundColor: Colors.green,
//         ),
//       );

//       // 刷新調試信息
//       await _checkWeatherIconsStatus();
//     } catch (e) {
//       _logger.e('❌ 預加載天氣圖標失敗', error: e);
//       if (!mounted) return;
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(
//           content: SelectableText('預加載失敗: $e'),
//           backgroundColor: Colors.red,
//         ),
//       );
//     }
//   }

//   ///10，構建調試信息卡片
//   Widget _buildDebugCard(String title, Map<String, dynamic> data) {
//     return Card(
//       margin: const EdgeInsets.all(8),
//       child: Padding(
//         padding: const EdgeInsets.all(16),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             SelectableText(
//               title,
//               style: const TextStyle(
//                 fontSize: 18,
//                 fontWeight: FontWeight.bold,
//                 color: Colors.blue,
//               ),
//             ),
//             const SizedBox(height: 8),
//             ...data.entries
//                 .where((entry) => entry.key != '詳細信息')
//                 .map((entry) => Padding(
//                       padding: const EdgeInsets.symmetric(vertical: 2),
//                       child: Row(
//                         crossAxisAlignment: CrossAxisAlignment.start,
//                         children: [
//                           SelectableText(
//                             '${entry.key}: ',
//                             style: const TextStyle(fontWeight: FontWeight.w600),
//                           ),
//                           Expanded(
//                             child: SelectableText(
//                               entry.value.toString(),
//                               style: TextStyle(
//                                 color: _getTextColor(entry.key, entry.value),
//                                 fontWeight: _getTextWeight(entry.key),
//                               ),
//                             ),
//                           ),
//                         ],
//                       ),
//                     )),
//           ],
//         ),
//       ),
//     );
//   }

//   ///11，構建圖標展示網格
//   Widget _buildIconGrid(String title, Map<String, dynamic> detailsData) {
//     return Card(
//       margin: const EdgeInsets.all(8),
//       child: Padding(
//         padding: const EdgeInsets.all(16),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             SelectableText(
//               '$title - 圖標展示',
//               style: const TextStyle(
//                 fontSize: 18,
//                 fontWeight: FontWeight.bold,
//                 color: Colors.purple,
//               ),
//             ),
//             const SizedBox(height: 12),
//             GridView.builder(
//               shrinkWrap: true,
//               physics: const NeverScrollableScrollPhysics(),
//               gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
//                 crossAxisCount: 4,
//                 crossAxisSpacing: 8,
//                 mainAxisSpacing: 8,
//                 childAspectRatio: 1.2,
//               ),
//               itemCount: detailsData.length,
//               itemBuilder: (context, index) {
//                 final entry = detailsData.entries.elementAt(index);
//                 final iconInfo = entry.value as Map<String, dynamic>;
//                 final isAvailable = iconInfo['状态'].toString().contains('✅');

//                 return Card(
//                   elevation: 2,
//                   child: Padding(
//                     padding: const EdgeInsets.all(4),
//                     child: Column(
//                       mainAxisAlignment: MainAxisAlignment.center,
//                       children: [
//                         if (title == '基本天气图标' && isAvailable)
//                           WeatherIconWidget(
//                             iconCode: int.parse(entry.key
//                                 .replaceAll('pic', '')
//                                 .replaceAll('.png', '')),
//                             width: 32,
//                             height: 32,
//                           )
//                         else if (title != '基本天气图标' && isAvailable)
//                           Image.asset(
//                             iconInfo['路径'] as String,
//                             width: 32,
//                             height: 32,
//                             errorBuilder: (context, error, stackTrace) =>
//                                 const Icon(
//                               Icons.broken_image,
//                               size: 32,
//                               color: Colors.red,
//                             ),
//                           )
//                         else
//                           const Icon(
//                             Icons.broken_image,
//                             size: 32,
//                             color: Colors.grey,
//                           ),
//                         const SizedBox(height: 4),
//                         Text(
//                           entry.key,
//                           style: TextStyle(
//                             fontSize: 10,
//                             color: isAvailable ? Colors.green : Colors.red,
//                             fontWeight: FontWeight.bold,
//                           ),
//                           textAlign: TextAlign.center,
//                           overflow: TextOverflow.ellipsis,
//                         ),
//                       ],
//                     ),
//                   ),
//                 );
//               },
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const SelectableText('天氣圖標調試工具'),
//         backgroundColor: Colors.blue[100],
//         actions: [
//           IconButton(
//             icon: const Icon(Icons.refresh),
//             onPressed: _checkWeatherIconsStatus,
//             tooltip: '刷新狀態',
//           ),
//         ],
//       ),
//       body: _isLoading
//           ? const Center(
//               child: Column(
//                 mainAxisAlignment: MainAxisAlignment.center,
//                 children: [
//                   CircularProgressIndicator(),
//                   SizedBox(height: 16),
//                   SelectableText('正在檢查天氣圖標狀態...'),
//                 ],
//               ),
//             )
//           : SingleChildScrollView(
//               padding: const EdgeInsets.all(16),
//               child: Column(
//                 children: [
//                   // 資源路徑測試信息
//                   if (_debugInfo['資源路徑測試'] != null)
//                     _buildDebugCard('資源路徑測試', _debugInfo['資源路徑測試']),

//                   // 統計信息卡片
//                   if (_debugInfo['基本天氣圖標'] != null)
//                     _buildDebugCard('基本天氣圖標', _debugInfo['基本天氣圖標']),

//                   if (_debugInfo['颱風警告圖標'] != null)
//                     _buildDebugCard('颱風警告圖標', _debugInfo['颱風警告圖標']),

//                   if (_debugInfo['天氣警告圖標'] != null)
//                     _buildDebugCard('天氣警告圖標', _debugInfo['天氣警告圖標']),

//                   if (_debugInfo['工具圖標'] != null)
//                     _buildDebugCard('工具圖標', _debugInfo['工具圖標']),

//                   const SizedBox(height: 20),

//                   // 圖標展示網格
//                   if (_debugInfo['基本天氣圖標']?['詳細信息'] != null)
//                     _buildIconGrid('基本天氣圖標', _debugInfo['基本天氣圖標']['詳細信息']),

//                   if (_debugInfo['颱風警告圖標']?['詳細信息'] != null)
//                     _buildIconGrid('颱風警告圖標', _debugInfo['颱風警告圖標']['詳細信息']),

//                   if (_debugInfo['天氣警告圖標']?['詳細信息'] != null)
//                     _buildIconGrid('天氣警告圖標', _debugInfo['天氣警告圖標']['詳細信息']),

//                   if (_debugInfo['工具圖標']?['詳細信息'] != null)
//                     _buildIconGrid('工具圖標', _debugInfo['工具圖標']['詳細信息']),

//                   const SizedBox(height: 20),

//                   // 操作按鈕
//                   Row(
//                     mainAxisAlignment: MainAxisAlignment.spaceEvenly,
//                     children: [
//                       ElevatedButton(
//                         onPressed: _preloadCommonIcons,
//                         style: ElevatedButton.styleFrom(
//                           backgroundColor: Colors.blue,
//                           foregroundColor: Colors.white,
//                         ),
//                         child: const SelectableText('預加載常用圖標'),
//                       ),
//                       ElevatedButton(
//                         onPressed: _clearIconCache,
//                         style: ElevatedButton.styleFrom(
//                           backgroundColor: Colors.orange,
//                           foregroundColor: Colors.white,
//                         ),
//                         child: const SelectableText('清理圖標緩存'),
//                       ),
//                     ],
//                   ),

//                   const SizedBox(height: 20),

//                   // 全部重新檢查按鈕
//                   SizedBox(
//                     width: double.infinity,
//                     child: ElevatedButton(
//                       onPressed: _checkWeatherIconsStatus,
//                       style: ElevatedButton.styleFrom(
//                         backgroundColor: Colors.green,
//                         foregroundColor: Colors.white,
//                         padding: const EdgeInsets.symmetric(vertical: 12),
//                       ),
//                       child: const SelectableText('重新檢查所有圖標'),
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//     );
//   }
// }
