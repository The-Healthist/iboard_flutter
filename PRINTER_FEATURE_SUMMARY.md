# 打印機功能實現總結

## 已完成的工作

### 1. ✅ 創建打印機狀態原因工具類
**文件**: `lib/utils/printer_state_reasons.dart`

- 完整的打印機狀態原因對照表(中文)
- `getReasonInfo()`: 獲取單個狀態原因詳情
- `getStatusSummary()`: 獲取多個狀態原因的彙總
- `getCategoryDescription()`: 獲取類別中文描述
- `parseStateReasons()`: 解析狀態原因字符串

### 2. ✅ 更新 PrinterModel 
**文件**: `lib/models/printer_model.dart`

- 在 `PrinterInfo` 添加了 `status` 和 `reason` 字段
- 添加了 `actualStatus` getter (優先使用實際狀態)
- 添加了 `hasActualStatus` getter
- 更新了 `fromJson`, `toJson`, `copyWith` 方法

### 3. ✅ 更新 PrinterProvider
**文件**: `lib/providers/printer_provider.dart`

添加的功能:
- `_statusPrint`: Map 存儲打印機實際狀態
- `_apiClient`: ApiClient 實例(用於後端管理系統API)
- `setApiClient()`: 設置 ApiClient
- `updatePrinterStatus()`: 更新打印機實際狀態
- `getPrinterStatus()`: 獲取打印機實際狀態
- `batchHealthCheck()`: 批量測試並上報健康狀態
- `printCallback()`: 打印後回調更新狀態
- `monitorPrintJob()`: 監控打印作業狀態

### 4. ✅ 更新 API 客戶端
**文件**: `lib/http/api_client.dart`

添加了兩個新接口:
- `printersHealthCheck()`: POST /api/device/client/printers/health
- `printersCallback()`: POST /api/device/client/printers/callback

**文件**: `lib/http/api_print.dart`

添加的方法:
- `getPrinterActiveJobs()`: 獲取活動作業
- `batchTestPrinters()`: 批量測試打印機連接

---

## 待完成的工作

### 5. ⏳ 更新 SimplePrintDialog
**文件**: `lib/widgets/simple_print_dialog.dart`

需要添加的打印參數:
- [ ] 份數 (copies)
- [ ] 黑白/彩色 (color_mode)
- [ ] 單面/雙面 (duplex)
- [ ] 長邊翻轉 (duplex_type)
- [ ] 紙張大小 (固定 A4)
- [ ] 頁碼範圍 (page_range)

打印流程改進:
- [ ] 先測試連接
- [ ] PDF 轉 Base64
- [ ] 調用打印 API
- [ ] 後台監控打印作業
- [ ] 根據作業狀態調用回調接口

### 6. ⏳ 更新 PrintDeviceListPage
**文件**: `lib/pages/print_device_list_page.dart`

需要修改:
- [ ] 顯示實際狀態(優先使用 `_statusPrint`)
- [ ] 顯示狀態原因 (reason)
- [ ] 使用 `PrinterStateReasons` 工具類解析原因

### 7. ⏳ 添加定時健康檢查
**位置**: AppDataProvider 或專門的服務

需要實現:
- [ ] 每 3-5 分鐘執行一次 `batchHealthCheck()`
- [ ] 使用 Timer 或 WorkManager
- [ ] 在應用啟動時初始化
- [ ] 在應用暫停時取消

### 8. ⏳ 在 main.dart 初始化 ApiClient
**文件**: `lib/main.dart`

需要添加:
```dart
final apiClient = Provider.of<ApiClient>(context, listen: false);
printerProvider.setApiClient(apiClient);
```

---

## 接口說明

### 1. 健康檢查接口
**端點**: `POST <<baseUrl>>/api/device/client/printers/health`

**請求體**:
```json
{
  "printers": [
    {
      "display_name": "Network Printer 192.168.50.139",
      "ip_address": "192.168.50.139",
      "name": "Network_Printer_192_168_50_139",
      "state": "idle",
      "uri": "ipp://192.168.50.139:631/ipp/print",
      "status": "online",
      "reason": ""
    }
  ]
}
```

**觸發時機**: 定時任務(每 3-5 分鐘)

### 2. 回調接口
**端點**: `POST <<baseUrl>>/api/device/client/printers/callback`

**請求體**:
```json
{
  "printers": [
    {
      "ip_address": "192.168.50.139",
      "status": "online",
      "reason": ""
    }
  ]
}
```

**觸發時機**: 每次打印任務完成後

---

## 打印流程設計

```
1. 用戶點擊"開始列印"
   ↓
2. 驗證列印密碼
   ↓
3. 測試打印機連接 (testPrinterConnection)
   ↓ (成功)
4. 讀取 PDF 並轉 Base64
   ↓
5. 調用打印 API (printPdfBase64)
   ↓ (獲得 cupsJobId)
6. 後台監控作業 (monitorPrintJob)
   - 等待 3 分鐘 (copies < 3) 或 5 分鐘
   - 檢查活動作業
   - 檢查全部作業狀態
   ↓
7. 根據結果調用回調 (printCallback)
   - 成功: status=online, reason=null
   - 失敗: status=offline, reason=錯誤原因
```

---

## 狀態原因示例

### 成功情況
```json
{
  "status": "online",
  "reason": ""
}
```

### 失敗情況 - 缺紙
```json
{
  "status": "offline",
  "reason": "media-empty-report"
}
```

解析後:
- 類別: 紙張問題
- 嚴重程度: info
- 消息: 📭 紙盒可能為空
- 解決方案: 檢查紙盒並根據需要添加紙張

---

## 下一步行動

1. **立即**: 在 main.dart 中設置 ApiClient 到 PrinterProvider
2. **高優先級**: 更新 SimplePrintDialog 添加打印參數
3. **高優先級**: 實現完整打印流程
4. **中優先級**: 更新 PrintDeviceListPage 顯示實際狀態
5. **中優先級**: 添加定時健康檢查功能

---

## 測試檢查清單

- [ ] 打印機狀態原因正確解析
- [ ] 健康檢查接口正常調用
- [ ] 回調接口正常調用
- [ ] 打印流程完整執行
- [ ] 打印成功後狀態更新為 online
- [ ] 打印失敗後狀態更新為 offline 並顯示原因
- [ ] 定時健康檢查正常運行
- [ ] 打印機列表正確顯示實際狀態

---

## 注意事項

1. `printersHealthCheck` 和 `printersCallback` 必須使用 `ApiClient` (後端管理系統)
2. 其他打印機操作使用 `PrintApiClient` (香橙派)
3. 狀態優先級: 實際狀態 > 接口狀態
4. 打印監控是後台任務,不阻塞 UI
5. 健康檢查定時任務需要正確清理以避免內存泄漏



