# WiFi打印服务 API 接口文档

 **Android专用的完整打印API系统 v2.0**

基于CUPS的强大打印服务API，为Android应用提供完整的网络打印解决方案。支持IPP Everywhere协议连接现代WiFi打印机，通过IP地址管理打印机，接收Base64编码的PDF文件并发送打印指令，实时监控打印机状态和打印作业进度。

##  **重要修复说明**

**v2.0版本已修复关键BUG：**
-  修复了 `model: "everywhere"` 参数被错误映射为Raw驱动的问题
-  现在正确使用IPP Everywhere驱动，支持完整的IPP功能
-  解决了 "Print job was not accepted" 错误
-  支持复杂PDF文件的正确打印和处理

##  核心功能

-  **CUPS IPP自动发现**: 使用CUPS IPP协议自动扫描网络中的打印机
-  **简单整数ID管理**: 打印机使用简单的整数ID（1, 2, 3...），便于Android应用处理
-  **RESTful设计**: 完全符合REST API设计规范，parameters通过body传递
-  **Swagger文档**: 自动生成交互式API文档 (http://localhost:8080/api/docs/)
-  **实时状态监控**: 提供丰富的打印机状态和错误信息（缺纸、缺墨等）
-  **Base64打印**: 支持Base64编码的PDF数据直接打印（主要接口）
-  **多种打印参数**: 支持颜色模式、双面打印、纸张规格、打印质量等丰富选项
-  **作业跟踪**: 完整的打印作业状态跟踪和历史记录
-  **CUPS深度集成**: 直接访问CUPS作业队列和状态信息
-  **Docker部署**: 基于Docker Compose的一键部署方案

##  完整API接口列表

| 编号 | 接口 | 方法 | 功能 | Android使用场景 |
|------|------|------|------|----------------|
|1 | `/api/health` | GET | 健康检查 | 应用启动时检查服务状态 |
|2 | `/api/printers/test` | POST | 测试打印机连接 | 连接验证页面 |
|3 | `/api/printers/connect` | POST | 连接打印机 | 添加打印机页面 |
|4 | `/api/printers` | GET | 获取打印机列表 | 打印机管理页面 |
|5 | `/api/printers/{id}` | GET | 获取单个打印机详情 | 打印机详情页面 |
|6 | `/api/printers/{id}` | PUT | 更新打印机信息 | 打印机设置页面 |
|7 | `/api/printers/{id}` | DELETE | 删除打印机 | 打印机管理页面 |
|8 | `/api/printers/ip/{ip}/options` | GET | 获取打印机详细配置 | 高级设置页面 |
|9 | `/api/printers/ip/{ip}/print/base64` | POST | **Base64数据打印（主要）** | **Android主要打印接口** |

|10 | `/api/printers/ip/{ip}/jobs` | GET | **获取指定打印机所有作业** | **作业管理页面** |
|11 | `/api/printers/ip/{ip}/jobs/active` | GET | **获取指定打印机活动作业** | **实时监控页面** |
|12 | `/api/printers/ip/{ip}/jobs/cancel-all` | POST | **取消指定打印机所有活动作业** | **紧急操作页面** |

##  API详细说明和测试数据

### 1. 健康检查接口

#### 接口信息
```http
GET /api/health
```

#### 测试命令（PowerShell）
```powershell
Invoke-RestMethod -Uri "http://localhost:8080/api/health" -Method GET
```

#### 测试命令（PowerShell - 香橙派）
```powershell
Invoke-RestMethod -Uri "http://192.168.50.173:8080/api/health" -Method GET
```

#### 响应示例
```json
{
  "status": "healthy",
  "timestamp": "2025-09-16T10:30:00.000Z",
  "service": "WiFi Print Service API"
}
```

---

### 2. 测试打印机连接

#### 接口信息
```http
POST /api/printers/test
Content-Type: application/json
```

#### 请求参数
```json
{
  "printer_ip": "192.168.1.100"
}
```

#### 测试命令（PowerShell）
```powershell
Invoke-RestMethod -Uri "http://localhost:8080/api/printers/test" -Method POST -ContentType "application/json" -Body '{"printer_ip": "192.168.50.146"}'
```

#### 测试命令（PowerShell - 香橙派）
```powershell
Invoke-RestMethod -Uri "http://192.168.50.173:8080/api/printers/test" -Method POST -ContentType "application/json" -Body '{"printer_ip": "192.168.50.146"}'
```

#### 响应示例（成功）
```json
{
  "success": true,
  "connected": true,
  "printer_ip": "192.168.1.100",
  "protocols": {
    "ipp": true,
    "appSocket": true
  },
  "recommended_uri": "ipp://192.168.1.100:631/ipp/print",
  "message": "打印机连接正常",
  "error_code": null
}
```

#### 响应示例（失败）
```json
{
  "success": false,
  "connected": false,
  "message": "无法连接到打印机 192.168.1.100:631",
  "error_code": "CONNECTION_FAILED"
}
```

---

### 3. 连接打印机

#### 接口信息
```http
POST /api/printers/connect
Content-Type: application/json
```

#### 请求参数
```json
{
  "printer_ip": "192.168.1.100",                    // 必填，打印机IP地址
  "name": "Office_Printer",                         // 可选，自定义打印机名称  
  "description": "办公室激光打印机",                   // 可选，打印机描述
  "location": "办公室",                              // 可选，打印机位置
  "protocol": "ipp",                                 // 可选，连接协议，默认ipp
  "port": 631,                                       // 可选，端口号，默认631
  "test_connection": true                            // 可选，是否测试连接
}
```

####  **IPP Everywhere 优化策略**
- ** 强制使用IPP Everywhere驱动** - 无论用户指定什么model，都使用`everywhere`驱动
- ** 优先IPP协议** - 默认使用`ipp://ip:631/ipp/print`格式，确保最佳兼容性
- ** 最丰富状态信息** - 支持墨盒含量、纸张状态、硬件状态等详细监控
- ** 大厂打印机友好** - 对HP、Canon、Epson、Brother等品牌打印机支持最佳

#### 注意事项
-  同一IP地址只能被一个打印机占用，避免冲突
-  已存在相同IP的打印机将返回错误，需先删除
-  打印机名称默认生成为`Network_Printer_{ip}`格式

#### 测试命令（PowerShell）
```powershell
$connectBody = @{
    printer_ip = "192.168.50.146"
    name = "Office_Printer"
    description = "办公室彩色激光打印机"
    location = "办公区A"
    protocol = "ipp"
    port = 631
    model = "everywhere"
    test_connection = $true
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://localhost:8080/api/printers/connect" -Method POST -ContentType "application/json" -Body $connectBody
```

#### 测试命令（PowerShell - 香橙派）
```powershell
$connectBody = @{
    printer_ip = "192.168.50.146"
    name = "Office_Printer"
    description = "办公室彩色激光打印机"
    location = "办公区A"
    protocol = "ipp"
    port = 631
    model = "everywhere"
    test_connection = $true
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://192.168.50.173:8080/api/printers/connect" -Method POST -ContentType "application/json" -Body $connectBody
```

#### 响应示例（成功）
```json
{
  "success": true,
  "message": "成功连接打印机 192.168.1.100",
  "printer_name": "Office_Printer",
  "printer_ip": "192.168.1.100",
  "printer_uri": "ipp://192.168.1.100:631/ipp/print",
  "protocol": "ipp",
  "model": "everywhere",
  "test_result": {
    "connected": true,
    "protocols": {
      "ipp": true,
      "ipps": true
    }
  }
}
```

#### 响应示例（失败）
```json
{
  "success": false,
  "message": "连接打印机失败: IP地址 192.168.1.100 已被使用",
  "error_code": "IP_ALREADY_EXISTS",
  "printer_ip": "192.168.1.100"
}
```

---

### 4. 获取打印机列表

#### 接口信息
```http
GET /api/printers
```

#### 测试命令（PowerShell）
```powershell
Invoke-RestMethod -Uri "http://localhost:8080/api/printers" -Method GET
```

#### 测试命令（PowerShell - 香橙派）
```powershell
Invoke-RestMethod -Uri "http://192.168.50.173:8080/api/printers" -Method GET
```

#### 响应示例
```json
{
  "success": true,
  "printers": [
    {
      "id": 1,
      "name": "Office_Printer",
      "display_name": "办公室彩色激光打印机",
      "state": "idle",
      "accepting_jobs": true,
      "uri": "ipp://192.168.1.100:631/ipp/print",
      "ip_address": "192.168.1.100",
      "location": "办公区A",
      "description": "办公室彩色激光打印机",
      "enabled": true,
      "type": "network",
      "created_at": "2025-09-25T06:30:00.000Z"
    },
    {
      "id": 2,
      "name": "printer_192_168_1_101",
      "display_name": "WiFi Printer - printer_192_168_1_101",
      "state": "idle",
      "accepting_jobs": true,
      "uri": "ipp://192.168.1.101:631/ipp/print",
      "ip_address": "192.168.1.101",
      "location": "Network",
      "description": "",
      "enabled": true,
      "type": "network",
      "created_at": "2025-09-25T06:35:00.000Z"
    }
  ],
  "count": 2
}
```

---

### 5. 获取单个打印机详情

#### 接口信息
```http
GET /api/printers/{printer_id}
```

#### 请求参数
- `printer_id`: 打印机ID（整数，从1开始）

#### 测试命令（PowerShell）
```powershell
Invoke-RestMethod -Uri "http://localhost:8080/api/printers/1" -Method GET
```

#### 测试命令（PowerShell - 香橙派）
```powershell
Invoke-RestMethod -Uri "http://192.168.50.173:8080/api/printers/1" -Method GET
```


#### 响应示例
```json
{
  "success": true,
  "printer": {
    "id": 1,
    "name": "printer_192_168_1_100",
    "display_name": "WiFi Printer - printer_192_168_1_100",
    "description": "办公室彩色激光打印机",
    "location": "办公区A",
    "make_and_model": "HP LaserJet Pro M404n",
    "state": "idle",
    "state_code": 3,
    "accepting_jobs": true,
    "uri": "ipp://192.168.1.100:631/ipp/print",
    "ip_address": "192.168.1.100",
    "enabled": true,
    "status": {
      "connected": true,
      "status": "idle",
      "is_online": true,
      "accepting_jobs": true,
      "message": " 打印机在线，状态正常"
    },
    "created_at": "2025-09-17T06:30:00.000Z",
    "type": "network"
  }
}
```

---

### 6. 更新打印机信息

#### 接口信息
```http
PUT /api/printers/{printer_id}
Content-Type: application/json
``` 

#### 请求参数
```json
{
  "printer_name": "New_Office_Printer",              // 可选，新的打印机名称
  "description": "办公室彩色激光打印机",               // 可选，打印机描述
  "location": "办公区A",                              // 可选，打印机位置
  "enabled": true,                                   // 可选，是否启用打印机
  "accepting_jobs": true,                            // 可选，是否接受打印作业
  "device_uri": "ipp://192.168.1.101:631/ipp/print", // 可选，设备URI（更改IP地址）
  "model": "everywhere",                             // 可选，打印机驱动模型
  "shared": false,                                   // 可选，是否共享打印机
  "default_options": {                               // 可选，默认打印选项
    "media": "a4",
    "print-color-mode": "color",
    "sides": "one-sided"
  }
}
```

#### 测试命令（PowerShell）
```powershell
$updateBody = @{
    printer_name = "Updated_Office_Printer"
    description = "更新后的打印机描述"
    location = "办公区B"
    enabled = $true
    accepting_jobs = $true
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://localhost:8080/api/printers/1" -Method PUT -ContentType "application/json" -Body $updateBody
```

#### 测试命令（PowerShell - 香橙派）
```powershell
$updateBody = @{
    printer_name = "Updated_Office_Printer"
    description = "更新后的打印机描述"
    location = "办公区B"
    enabled = $true
    accepting_jobs = $true
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://192.168.50.173:8080/api/printers/1" -Method PUT -ContentType "application/json" -Body $updateBody
```

#### 更改IP地址测试（PowerShell）
```powershell
$changeIpBody = @{
    device_uri = "ipp://192.168.50.200:631/ipp/print"
    description = "打印机已迁移到新IP地址"
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://localhost:8080/api/printers/1" -Method PUT -ContentType "application/json" -Body $changeIpBody
```

#### 更改IP地址测试（PowerShell - 香橙派）
```powershell
$changeIpBody = @{
    device_uri = "ipp://192.168.50.200:631/ipp/print"
    description = "打印机已迁移到新IP地址"
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://192.168.50.173:8080/api/printers/1" -Method PUT -ContentType "application/json" -Body $changeIpBody
```

#### 响应示例
```json
{
  "success": true,
  "message": "Printer updated successfully using delete+add approach",
  "original_printer": "Office_Printer",
  "new_printer": "Updated_Office_Printer",
  "method": "delete_and_add",
  "changes_applied": ["printer_name", "description", "location", "enabled"]
}
```

---

### 7. 删除打印机

#### 接口信息
```http
DELETE /api/printers/{printer_id}
```

#### 请求参数
- `printer_id`: 打印机ID（整数，从1开始）

#### 测试命令（PowerShell）
```powershell
Invoke-RestMethod -Uri "http://localhost:8080/api/printers/1" -Method DELETE
```

#### 测试命令（PowerShell - 香橙派）
```powershell
Invoke-RestMethod -Uri "http://192.168.50.173:8080/api/printers/1" -Method DELETE
```

#### 响应示例
```json
{
  "success": true,
  "message": "打印机 'printer_192_168_1_100' 删除成功",
  "deleted_printer": {
    "name": "printer_192_168_1_100",
    "uri": "ipp://192.168.1.100:631/ipp/print",
    "deleted_at": "2025-09-17T06:35:00.000Z"
  }
}
```

---

### 8. 获取打印机详细配置选项

#### 接口信息
```http
GET /api/printers/ip/{printer_ip}/options
```

#### 测试命令（PowerShell）
```powershell
Invoke-RestMethod -Uri "http://localhost:8080/api/printers/ip/192.168.50.146/options" -Method GET
```

#### 测试命令（PowerShell - 香橙派）
```powershell
Invoke-RestMethod -Uri "http://192.168.50.173:8080/api/printers/ip/192.168.50.146/options" -Method GET
```

#### 响应示例
```json
{
  "success": true,
  "printer_name": "Office_Printer",
  "options": {
    "printer-info": "Office Printer",
    "printer-make-and-model": "Generic IPP Everywhere Printer",
    "marker-levels": "60,50",
    "marker-names": "Black Cartridge,Color Cartridge",
    "marker-types": "toner,ink",
    "print-color-mode": "color",
    "printer-state": "3",
    "printer-state-reasons": "none",
    "printer-is-accepting-jobs": "true",
    "device-uri": "ipp://192.168.1.100:631/ipp/print"
  },
  "raw_output": "copies=1 device-uri=ipp://192.168.1.100:631/ipp/print finishings=3 job-cancel-after=10800...",
  "query_time": "2025-09-25T10:30:00.000Z",
  "method": "lpoptions"
}
```

---

### 9. Base64数据打印（Android主要接口）

#### 接口信息
```http
POST /api/printers/ip/{printer_ip}/print/base64
Content-Type: application/json
```
#### 支持的打印参数
- **copies**: 打印份数 (1-99)
- **color_mode**: 颜色模式 (color/bw/blackwhite/monochrome/gray/grayscale)
- **media**: 纸张规格 (a4/a3/letter/legal/a5/b5/4x6/5x7)
- **duplex**: 双面打印 (true/false)
- **duplex_type**: 双面打印类型 (long-edge/short-edge)
- **quality**: 打印质量 (draft/normal/best/high/low)
- **orientation**: 页面方向 (portrait/landscape)
- **page_range**: 页面范围 (如: "1-5,10,15-20")
- **number_up**: 多页合一 (1/2/4/6/9/16)
- **priority**: 打印优先级 (1-100)
- **hold_job**: 作业保持 (indefinite/day-time/evening/night/weekend)
- **banner**: 横幅页 (standard/classified/confidential/secret/topsecret/unclassified)

#### 测试命令（PowerShell - 使用示例PDF）
```powershell
$printBody = @{
    printer_ip = "192.168.50.146"
    file_data = "JVBERi0xLjQKMSAwIG9iago8PAovVHlwZSAvQ2F0YWxvZwovUGFnZXMgMiAwIFIKPj4KZW5kb2JqCjIgMCBvYmoKPDwKL1R5cGUgL1BhZ2VzCi9LaWRzIFszIDAgUl0KL0NvdW50IDEKPD4KZW5kb2JqCjMgMCBvYmoKPDwKL1R5cGUgL1BhZ2UKL1BhcmVudCAyIDAgUgovTWVkaWFCb3ggWzAgMCA2MTIgNzkyXQovUmVzb3VyY2VzIDw8Ci9Gb250IDw8Ci9GMSA0IDAgUgo+Pgo+PgovQ29udGVudHMgNSAwIFIKPj4KZW5kb2JqCjQgMCBvYmoKPDwKL1R5cGUgL0ZvbnQKL1N1YnR5cGUgL1R5cGUxCi9CYXNlRm9udCAvSGVsdmV0aWNhCj4+CmVuZG9iago1IDAgb2JqCjw8Ci9MZW5ndGggNDQKPj4Kc3RyZWFtCkJUCi9GMSA5IFRmCjEwIDUwIFRkCihIZWxsbyBXb3JsZCkgVGoKRVQKZW5kc3RyZWFtCmVuZG9iagp4cmVmCjAgNgowMDAwMDAwMDAwIDY1NTM1IGYgCjAwMDAwMDAwMDkgMDAwMDAgbiAKMDAwMDAwMDA1OCAwMDAwMCBuIAowMDAwMDAwMTE1IDAwMDAwIG4gCjAwMDAwMDAyNDUgMDAwMDAgbiAKMDAwMDAwMDMxNCAwMDAwMCBuIAp0cmFpbGVyCjw8Ci9TaXplIDYKL1Jvb3QgMSAwIFIKPj4Kc3RhcnR4cmVmCjQwOAolJUVPRgo="
    filename = "hello_world.pdf"
    title = "Hello World测试"
    options = @{
        copies = 1
        color_mode = "color"
        media = "a4"
        duplex = $false
        quality = "normal"
    }
} | ConvertTo-Json -Depth 3

Invoke-RestMethod -Uri "http://localhost:8080/api/printers/ip/192.168.50.146/print/base64" -Method POST -ContentType "application/json; charset=utf-8" -Body $printBody
```

#### 测试命令（PowerShell - 使用示例PDF - 香橙派）
```powershell
$printBody = @{
    printer_ip = "192.168.50.146"
    file_data = "JVBERi0xLjQKMSAwIG9iago8PAovVHlwZSAvQ2F0YWxvZwovUGFnZXMgMiAwIFIKPj4KZW5kb2JqCjIgMCBvYmoKPDwKL1R5cGUgL1BhZ2VzCi9LaWRzIFszIDAgUl0KL0NvdW50IDEKPD4KZW5kb2JqCjMgMCBvYmoKPDwKL1R5cGUgL1BhZ2UKL1BhcmVudCAyIDAgUgovTWVkaWFCb3ggWzAgMCA2MTIgNzkyXQovUmVzb3VyY2VzIDw8Ci9Gb250IDw8Ci9GMSA0IDAgUgo+Pgo+PgovQ29udGVudHMgNSAwIFIKPj4KZW5kb2JqCjQgMCBvYmoKPDwKL1R5cGUgL0ZvbnQKL1N1YnR5cGUgL1R5cGUxCi9CYXNlRm9udCAvSGVsdmV0aWNhCj4+CmVuZG9iago1IDAgb2JqCjw8Ci9MZW5ndGggNDQKPj4Kc3RyZWFtCkJUCi9GMSA5IFRmCjEwIDUwIFRkCihIZWxsbyBXb3JsZCkgVGoKRVQKZW5kc3RyZWFtCmVuZG9iagp4cmVmCjAgNgowMDAwMDAwMDAwIDY1NTM1IGYgCjAwMDAwMDAwMDkgMDAwMDAgbiAKMDAwMDAwMDA1OCAwMDAwMCBuIAowMDAwMDAwMTE1IDAwMDAwIG4gCjAwMDAwMDAyNDUgMDAwMDAgbiAKMDAwMDAwMDMxNCAwMDAwMCBuIAp0cmFpbGVyCjw8Ci9TaXplIDYKL1Jvb3QgMSAwIFIKPj4Kc3RhcnR4cmVmCjQwOAolJUVPRgo="
    filename = "hello_world.pdf"
    title = "Hello World测试"
    options = @{
        copies = 1
        color_mode = "color"
        media = "a4"
        duplex = $false
        quality = "normal"
    }
} | ConvertTo-Json -Depth 3

Invoke-RestMethod -Uri "http://192.168.50.173:8080/api/printers/ip/192.168.50.146/print/base64" -Method POST -ContentType "application/json; charset=utf-8" -Body $printBody
```

#### 测试命令（PowerShell - 使用真实PDF文件）
```powershell
# 读取本地PDF文件并转换为Base64
$pdfBytes = [System.IO.File]::ReadAllBytes("uploads/测试文件.pdf")
$base64String = [System.Convert]::ToBase64String($pdfBytes)

$printBody = @{
    printer_ip = "192.168.50.146"
    file_data = $base64String
    filename = "测试文件.pdf"
    title = "真实PDF测试打印"
    options = @{
        copies = 1
        color_mode = "color"        # 彩色打印
        media = "a4"
        duplex = $true              # 双面打印
        duplex_type = "long-edge"   # 长边翻转
        quality = "normal"
        orientation = "portrait"
    }
} | ConvertTo-Json -Depth 3

Invoke-RestMethod -Uri "http://localhost:8080/api/printers/ip/192.168.50.146/print/base64" -Method POST -ContentType "application/json; charset=utf-8" -Body $printBody
```

#### 测试命令（PowerShell - 使用真实PDF文件 - 香橙派）
```powershell
# 读取本地PDF文件并转换为Base64
$pdfBytes = [System.IO.File]::ReadAllBytes("uploads/测试文件.pdf")
$base64String = [System.Convert]::ToBase64String($pdfBytes)

$printBody = @{
    printer_ip = "192.168.50.146"
    file_data = $base64String
    filename = "测试文件.pdf"
    title = "真实PDF测试打印"
    options = @{
        copies = 1
        color_mode = "color"        # 彩色打印
        media = "a4"
        duplex = $true              # 双面打印
        duplex_type = "long-edge"   # 长边翻转
        quality = "normal"
        orientation = "portrait"
    }
} | ConvertTo-Json -Depth 3

Invoke-RestMethod -Uri "http://192.168.50.173:8080/api/printers/ip/192.168.50.146/print/base64" -Method POST -ContentType "application/json; charset=utf-8" -Body $printBody
```


#### 响应示例
```json
{
  "success": true,
  "job_id": 1,
  "cups_job_id": 124,
  "message": "打印作业已提交",
  "printer_ip": "192.168.1.100",
  "printer_name": "Office_Printer",
  "method": "base64_print",
  "driver": "ipp_everywhere",
  "file_info": {
    "filename": "document.pdf",
    "size_kb": 235.2,
    "format": "PDF"
  }
}
```

#### 优化功能
-  **PDF格式验证** - 自动检查文件格式有效性
-  **文件大小监控** - 记录和报告文件传输大小
-  **安全文件名** - 自动处理特殊字符，防止路径注入
-  **智能参数处理** - 支持新版options格式，兼容旧版参数
-  **详细日志记录** - 完整的打印流程日志，便于调试
-  **自动清理** - 打印完成后自动删除临时文件

---


### 10. 获取指定打印机所有作业

#### 接口信息
```http
GET /api/printers/ip/{printer_ip}/jobs?type={job_type}
```

#### 请求参数
- `printer_ip` (必填): 打印机IP地址
- `type` (可选): 作业类型
  - `all`: 所有作业 (默认)
  - `active`: 活动作业 (等待中、打印中等)
  - `completed`: 已完成作业 (已完成、已取消等)

#### 测试命令（PowerShell）
```powershell
# 获取所有作业
Invoke-RestMethod -Uri "http://localhost:8080/api/printers/ip/192.168.50.146/jobs" -Method GET

# 获取活动作业
Invoke-RestMethod -Uri "http://localhost:8080/api/printers/ip/192.168.50.146/jobs?type=active" -Method GET

# 获取已完成作业
Invoke-RestMethod -Uri "http://localhost:8080/api/printers/ip/192.168.50.146/jobs?type=completed" -Method GET
```

#### 测试命令（PowerShell - 香橙派）
```powershell
# 获取所有作业
Invoke-RestMethod -Uri "http://192.168.50.173:8080/api/printers/ip/192.168.50.146/jobs" -Method GET

# 获取活动作业
Invoke-RestMethod -Uri "http://192.168.50.173:8080/api/printers/ip/192.168.50.146/jobs?type=active" -Method GET

# 获取已完成作业
Invoke-RestMethod -Uri "http://192.168.50.173:8080/api/printers/ip/192.168.50.146/jobs?type=completed" -Method GET
```

#### 测试命令（Bash）
```bash
# 获取所有作业
curl -X GET "http://localhost:8080/api/printers/ip/192.168.50.146/jobs"

# 获取活动作业
curl -X GET "http://localhost:8080/api/printers/ip/192.168.50.146/jobs?type=active"

# 获取已完成作业  
curl -X GET "http://localhost:8080/api/printers/ip/192.168.50.146/jobs?type=completed"
```

#### 响应示例
```json
{
  "success": true,
  "printer_ip": "192.168.50.146",
  "printer_name": "Network_Printer_192_168_50_146",
  "job_type": "active",
  "jobs": {
    "2": {
      "job_id": 2,
      "cups_job_id": 2,
      "status": "pending",
      "state_code": 3,
      "printer": "Network_Printer_192_168_50_146",
      "title": "Test Document",
      "user": "admin",
      "size": 24576,
      "pages": 1,
      "created_at": "2025-09-26T10:30:00",
      "completed": false,
      "priority": 50
    }
  },
  "count": 1,
  "method": "lpstat -o Network_Printer_192_168_50_146",
  "query_time": "2025-09-26 10:35:00"
}
```

#### 等效CUPS命令
```bash
# 查看指定打印机的作业
docker exec cups-server lpstat -o Network_Printer_192_168_50_146

# 查看所有历史作业
docker exec cups-server lpstat -W all -o Network_Printer_192_168_50_146
```

---

### 11. 获取指定打印机活动作业

#### 接口信息
```http
GET /api/printers/ip/{printer_ip}/jobs/active
```

#### 测试命令（PowerShell）
```powershell
Invoke-RestMethod -Uri "http://localhost:8080/api/printers/ip/192.168.50.146/jobs/active" -Method GET
```

#### 测试命令（PowerShell - 香橙派）
```powershell
Invoke-RestMethod -Uri "http://192.168.50.173:8080/api/printers/ip/192.168.50.146/jobs/active" -Method GET
```

#### 测试命令（Bash）
```bash
curl -X GET http://localhost:8080/api/printers/ip/192.168.50.146/jobs/active
```

#### 响应示例
```json
{
  "success": true,
  "printer_ip": "192.168.50.146",
  "printer_name": "Network_Printer_192_168_50_146",
  "job_type": "active",
  "jobs": {
    "3": {
      "job_id": 3,
      "cups_job_id": 3,
      "status": "processing",
      "state_code": 5,
      "printer": "Network_Printer_192_168_50_146",
      "title": "Print Job",
      "user": "admin",
      "size": 12288,
      "pages": 0,
      "created_at": "2025-09-26T10:32:00",
      "processing_at": "2025-09-26T10:32:05",
      "completed": false,
      "priority": 50
    }
  },
  "count": 1,
  "method": "lpstat -o Network_Printer_192_168_50_146",
  "query_time": "2025-09-26 10:35:00"
}
```

#### 等效CUPS命令
```bash
docker exec cups-server lpstat -o Network_Printer_192_168_50_146
```

---

### 12. 取消指定打印机所有活动作业

#### 接口信息
```http
POST /api/printers/ip/{printer_ip}/jobs/cancel-all
```

#### 测试命令（PowerShell）
```powershell
Invoke-RestMethod -Uri "http://localhost:8080/api/printers/ip/192.168.50.146/jobs/cancel-all" -Method POST
```

#### 测试命令（PowerShell - 香橙派）
```powershell
Invoke-RestMethod -Uri "http://192.168.50.173:8080/api/printers/ip/192.168.50.146/jobs/cancel-all" -Method POST
```

#### 测试命令（Bash）
```bash
curl -X POST http://localhost:8080/api/printers/ip/192.168.50.146/jobs/cancel-all
```

#### 响应示例（有活动作业时）
```json
{
  "success": true,
  "message": "Cancelled 2 jobs for printer Network_Printer_192_168_50_146",
  "printer_ip": "192.168.50.146",
  "printer_name": "Network_Printer_192_168_50_146",
  "cancelled_jobs": [
    {
      "job_id": 4,
      "title": "Test Document 1",
      "status": "pending"
    },
    {
      "job_id": 5,
      "title": "Test Document 2", 
      "status": "held"
    }
  ],
  "failed_jobs": [],
  "cancelled_count": 2,
  "failed_count": 0,
  "method": "cancel -a Network_Printer_192_168_50_146",
  "executed_at": "2025-09-26 10:40:00"
}
```

#### 响应示例（无活动作业时）
```json
{
  "success": true,
  "message": "No active jobs found for printer Network_Printer_192_168_50_146",
  "printer_ip": "192.168.50.146",
  "printer_name": "Network_Printer_192_168_50_146",
  "cancelled_jobs": [],
  "cancelled_count": 0,
  "method": "cancel -a Network_Printer_192_168_50_146"
}
```

#### 等效CUPS命令
```bash
docker exec cups-server cancel -a Network_Printer_192_168_50_146
```

