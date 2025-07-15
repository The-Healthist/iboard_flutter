# 香港天文台天氣預報模塊集成指南

## 📋 概述

這個模塊將香港天文台的7天天氣預報功能完美集成到iBoard的自動輪播界面中，提供了豐富的天氣信息顯示功能。

## 🎯 核心功能

### 1. **雙視圖自動切換**
- **現況視圖**：顯示當前天氣信息（原有功能）
- **預報視圖**：顯示香港天文台7天天氣預報（新增功能）
- 每15秒自動切換一次視圖，提供動態的信息展示

### 2. **豐富的天氣數據**
- 今日和明日天氣詳情
- 未來7天天氣預報
- 溫度範圍、天氣描述、降雨概率
- 官方天氣圖標顯示
- 風力、濕度等詳細信息

### 3. **優雅的用戶界面**
- 漸變背景色根據天氣類型動態變化
- 流暢的切換動畫效果
- 視圖指示器和刷新按鈕
- 響應式佈局適配不同屏幕

## 🚀 使用方法

### 自動集成（已完成）
天氣模塊已經自動集成到現有的自動輪播界面中：

```dart
// 在 AutoCarouselWidget 中已經使用
Container(
  child: const EnhancedWeatherWidget(),
)
```

### 手動使用增強版天氣組件
如果需要在其他地方單獨使用：

```dart
import '../widgets/enhanced_weather_widget.dart';

// 在任何需要的地方使用
const EnhancedWeatherWidget()
```

### 獨立使用天氣預報組件
如果只需要香港天文台預報功能：

```dart
import '../widgets/weather_forecast_widget.dart';

WeatherForecastWidget(
  showDetailedView: true,  // 詳細視圖
  maxDays: 7,             // 顯示天數
)
```

### 簡化的天氣卡片
用於在其他頁面嵌入天氣信息：

```dart
import '../screens/weather_demo_screen.dart';

// 緊凑模式
WeatherInfoCard(compact: true)

// 展開模式  
WeatherInfoCard(compact: false)
```

## 📱 界面說明

### 現況視圖（左側顯示15秒）
- **地點和溫度**：顯示當前位置和實時溫度
- **天氣條件**：當前天氣狀況描述
- **天氣圖標**：對應的天氣圖標
- **詳細信息**：濕度、風速等

### 預報視圖（右側顯示15秒）
- **今日預報**：突出顯示今天的詳細天氣
- **明日預報**：明天的天氣概況
- **未來幾天**：4天的天氣預報列表
- **官方圖標**：香港天文台提供的天氣圖標

### 交互元素
- **視圖指示器**（左上角）：顯示當前是"現況"還是"預報"
- **刷新按鈕**（右上角）：手動刷新天氣數據
- **自動切換**：每15秒自動在兩個視圖間切換

## 🔧 配置選項

### WeatherManager 配置
天氣管理器已經內置以下配置：

```dart
// 自動更新間隔（30分鐘）
static const Duration _autoUpdateInterval = Duration(minutes: 30);

// API端點（香港天文台）
static const String _apiBaseUrl = 'https://data.weather.gov.hk/weatherAPI/opendata/weather.php';
```

### 自定義切換時間
如需修改視圖切換間隔，編輯 `enhanced_weather_widget.dart`：

```dart
void _startViewSwitchTimer() {
  Future.delayed(const Duration(seconds: 15), () { // 修改這裡的時間
    if (mounted) {
      _toggleView();
      _startViewSwitchTimer();
    }
  });
}
```

## 📊 數據訪問

通過 WeatherManager 可以訪問所有天氣數據：

```dart
// 獲取天氣管理器
final weatherManager = context.read<WeatherManager>();

// 香港天文台預報數據
final todayForecast = weatherManager.todayForecast;
final tomorrowForecast = weatherManager.tomorrowForecast;
final sevenDaysForecast = weatherManager.sevenDaysForecast;
final generalSituation = weatherManager.generalSituation;

// 數據狀態檢查
final hasForecastData = weatherManager.hasForecastData;
final isRainyToday = weatherManager.isRainyToday;
final isSunnyToday = weatherManager.isSunnyToday;

// 手動刷新
await weatherManager.refreshWeatherForecast();
```

## 🎨 主題配置

### 背景顏色
- **現況視圖**：根據當前天氣類型選擇對應的顏色主題
- **預報視圖**：使用藍色漸變（代表天文台官方色調）

### 動畫效果
- **淡入淡出**：視圖切換時的透明度動畫
- **滑動**：從右側滑入的切換效果
- **持續時間**：1.2秒的流暢過渡

## 🔄 更新機制

### 自動更新
- WeatherManager 每30分鐘自動更新一次數據
- 應用啟動時立即獲取最新數據
- 網絡錯誤時使用本地緩存數據

### 手動更新
- 點擊右上角刷新按鈕
- 調用 `weatherManager.refreshWeatherForecast()`

## 📁 相關文件

```
lib/
├── models/
│   ├── weather.dart              # 香港天文台數據模型
│   ├── weather.g.dart            # 自動生成的序列化代碼
│   └── weather_info.dart         # 原有天氣信息模型
├── services/
│   ├── weather_service.dart      # 香港天文台API服務
│   └── weather_manager.dart      # 天氣數據管理器
├── widgets/
│   ├── enhanced_weather_widget.dart    # 增強版天氣組件（主要）
│   ├── weather_forecast_widget.dart    # 預報組件
│   ├── weather_widget.dart            # 原有天氣組件
│   └── auto_carousel_widget.dart      # 自動輪播組件
└── screens/
    └── weather_demo_screen.dart       # 天氣演示頁面
```

## 🚨 注意事項

1. **網絡權限**：確保應用有網絡訪問權限
2. **API限制**：香港天文台API有使用頻率限制，已內置30分鐘緩存
3. **圖標加載**：天氣圖標從網絡加載，有本地備用圖標
4. **數據更新**：首次啟動可能需要幾秒鐘獲取數據

## 🎉 完成狀態

✅ 香港天文台API集成  
✅ 7天天氣預報數據模型  
✅ 自動輪播界面集成  
✅ 雙視圖自動切換  
✅ 動畫效果和UI優化  
✅ 錯誤處理和緩存機制  
✅ 響應式佈局設計  

天氣模塊已經完全集成到您的iBoard項目中，可以立即使用！