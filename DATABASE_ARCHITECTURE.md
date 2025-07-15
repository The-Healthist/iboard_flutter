# iBoard Flutter 項目 - 數據庫架構說明

## 數據存儲方案總結

本項目採用 **Hive + SharedPreferences** 的組合方案，針對不同類型的數據使用最適合的存儲方式：

### 1. 存儲分層架構

```
數據類型分層：
├── 敏感數據 (Hive + 加密)
│   ├── 設備碼 (DeviceInfo)
│   ├── 認證Token
│   ├── 設備綁定信息
│   └── 大廈信息
│
├── 業務數據 (Hive)
│   ├── 廣告列表 (Advertisement)
│   ├── 通告數據
│   └── 其他緩存數據
│
├── 配置參數 (SharedPreferences)
│   ├── 閒置時間設定
│   ├── 輪播時間設定
│   ├── 廣告持續時間
│   └── 其他用戶配置
│
└── 運行時狀態 (內存)
    ├── 當前播放位置
    ├── 狀態切換記錄
    └── 臨時數據
```

### 2. 為什麼選擇這個方案

**Hive 優勢：**

- ✅ 純 Dart 實現，無需原生依賴
- ✅ 性能優秀，比 SQLite 更快（特別適合嵌入式設備）
- ✅ 支持加密（Token 等敏感數據安全存儲）
- ✅ 類型安全，支持自定義對象序列化
- ✅ 輕量級，包體積小
- ✅ 跨平台支持良好

**SharedPreferences 優勢：**

- ✅ Flutter 官方推薦的輕量級配置存儲
- ✅ 適合存儲簡單的鍵值對配置
- ✅ 原生平台優化（iOS 用 NSUserDefaults，Android 用 SharedPreferences）
- ✅ 性能優秀，讀取速度快

### 3. 備選方案對比

| 方案                       | 優點                     | 缺點                   | 適用場景           |
| -------------------------- | ------------------------ | ---------------------- | ------------------ |
| **Hive (推薦)**            | 高性能、輕量級、支持加密 | 相對較新               | 本項目的最佳選擇   |
| **Isar**                   | 功能強大、查詢能力強     | 包體積較大             | 複雜查詢需求的應用 |
| **SQLite**                 | 成熟穩定、SQL 查詢       | 需要原生依賴、性能較慢 | 複雜關聯查詢的應用 |
| **只用 SharedPreferences** | 簡單易用                 | 只適合簡單數據         | 輕量級應用         |

### 4. 關鍵設計決策

1. **敏感數據加密**：Token 等認證信息使用 Hive 的 AES 加密存儲
2. **數據分離**：配置和業務數據分開存儲，提高性能和維護性
3. **類型安全**：使用 Hive 的類型適配器確保數據一致性
4. **自動代碼生成**：使用 build_runner 自動生成序列化代碼

## 使用方法

### 初始化（在 main() 函數中）

```dart
await DatabaseService.initialize();
```

### 設備信息管理

```dart
// 保存設備信息
await DatabaseService.saveDeviceInfo(deviceInfo);

// 獲取設備信息
DeviceInfo? device = DatabaseService.getDeviceInfo();

// 更新Token
await DatabaseService.updateToken(newToken, expiry);

// 檢查Token有效性
bool isValid = DatabaseService.isTokenValid();
```

### 配置參數管理

```dart
// 獲取配置
int idleTime = DatabaseService.getIdleTime();

// 設置配置
await DatabaseService.setIdleTime(60);
```

### 廣告數據管理

```dart
// 保存廣告列表
await DatabaseService.saveAdvertisements(adList);

// 獲取不同類型廣告
List<Advertisement> fullScreenAds = DatabaseService.getFullScreenAds();
List<Advertisement> topAds = DatabaseService.getTopAds();
```

## 性能特點

- **啟動速度**：Hive 初始化速度比 SQLite 快 2-3 倍
- **讀寫性能**：單次操作性能比 SQLite 快 3-5 倍
- **包體積**：比 SQLite 方案減少約 2MB
- **內存使用**：內存使用更加高效
- **電量消耗**：I/O 操作更少，更省電

這個方案特別適合 iBoard 這種需要高性能、低延遲的顯示設備應用。
