- 接入全屏广告、顶部广告的api（先搞一个ads provider用来状态管理、存储广告，然后把全屏、顶部的广告的页面部分接入）(已完成)
- 加一个设备码功能，程序初始化时传入 (已完成)
- 在页面最下方显示一行小小的设备码 (已完成)
- 在app_data_provider添加对各种时间的配置管理（没操作多少秒自动播放全屏广告、多少秒切换公告等等）(已完成)
- 进入到全屏广告状态时，暂停通告轮播、顶部广告轮播（已完成）


- 进入全屏广告时，要记录顶部广告播放了多少秒、通告播放了多少秒。当全屏广告自动退出后，继续播完剩下的秒数（已完成）
- 确保广告、通告可以按照设定的时间自动更新(已完成)
- 如果更新广告、通告时网络异常，不要影响现有的广告、通告(已完成)
- 打开app直接显示轮播主页面(已完成)(已完成)
- 在轮播主页面最下方显示设备ID（容器高度再缩小一点，与字号同高）(已完成)
- 连续点击设备ID 8次进入设计页面(已完成)(进入设计页面后暂停全部定时器,退出则恢复全部定时器)
- 左下角天气预报的时间改成实时的系统时间(已完成)
- 左下角天气预报添加一行特殊天气预警（放到最后做，因为天文台这个API需要给你特别说明一下）(已完成)
- 打包成apk，进行测试

1,现在是可以播放视频了,但是没有预加载,倒是每次进入全屏广告都会卡顿一下,我希望能每次进入全屏广告之前能预加载一下全屏广告,让我的广告播放顺畅一些 2, 在我的mainscreen中添加一个全屏广告轮播定时器,用来控制全屏广告的轮播用,其中轮播逻辑和顶部的轮播逻辑有些类似,就是在全屏广告时间下开始轮播一条全屏广告,播完该廣告的 "duration": 30屬性 后切换下一个广告,如果当退出全屏广告的时候,该广告还没有播放完该全屏广告的duration,就记录下来,然后下次进入全屏广告的时候,继续从该时刻开始播放,直到播放完 duration,切换到下一个全屏广告,其中,当切换下一个广告前,都先进行预加载,来解决切换流畅度的问题,参考顶部广告的切换的预加载逻辑 3,在我的全屏广告的full_ad_widget中切換下一個全屏廣告播放時需要預加載該全屏廣告.來保證全屏廣告輪播切換的流暢性

需要全屏廣告輪播，(已完成)
全屏廣告的視頻播放有bug(已完成)
進入設置頁面暂停全屏廣告輪播(已完成)
一般通告和紧急通告混淆(已完成)
大廈查詢繳費記錄
下方二維碼顯示（像舊板一樣)
可以调整广告播放顺序(已完成)
天氣警告可能會有多個（添加圖標）

(旧系统使用vue和ts开发的欠费页面功能等)
欠费查询页面文件:
/docs/ArrearageFind.vue - 主要的欠费查询界面，用于选择楼号和户号并显示查询结果 --pAGE
欠费表单页面文件:
/docs/ArrangeTable.vue - 欠费数据的表格展示组件，用于以表格形式展示欠费记录 -- WIDGET
相关支持文件:
/docs/arrearage_store.ts - 欠费数据的状态管理 --对应的provider
/docs/arrearage.ts - 欠费相关的类型 --- C:\Users\20216\Documents\GitHub\iboard_flutter\lib\models\arrear_model.dart
/docs/index.ts - 包含获取欠费数据的API接口 --  C:\Users\20216\Documents\GitHub\iboard_flutter\lib\http\api_client.dart
/docs/arrear.md - 欠费接口的文档说明 
欠费查询系统的主要流程是：
通过 ArrearageFind.vue 页面选择楼号和户号
使用 arrearage_store.ts 中的状态管理来存储和获取数据
数据通过 ArrangeTable.vue 组件以表格形式展示
API请求通过 apis/index.ts 中的 getArrearage 函数发送到后端
路由配置中有两个相关路由：
/arrearage-find - 欠费查询页面  --page
/arrearage-table - 欠费表格展示页面 -- widget

我需要你能对应我的旧系统中的实现,在我的本项目也实现类似的效果,其中blg_id由C:\Users\20216\Documents\GitHub\iboard_flutter\lib\providers\app_data_provider.dart 中的builiding数据中的,也就是  // 1. Login
  // Endpoint: POST <<baseUrl>>/api/device/login
  // Body: { "deviceId": "string" }
  Future<Map<String, dynamic>> login({required String deviceId}) async {
    const String endpointPath = '/api/device/login';
    final Uri url = _buildUri(endpointPath, null);
    final String requestBody = json.encode({'deviceId': deviceId});
    final Map<String, String> headers =
        _getHeaders(requiresAuth: false, contentType: 'application/json');

    _logger.i('Attempting login for deviceId: $deviceId');

    final http.Response response = await _sendRequest(
        () => http.post(url, headers: headers, body: requestBody),
        isLoginRequest: true, // Mark as login request
        apiNameForLog: 'login');

    final Map<String, dynamic> responseData =
        await _handleResponse(response, 'login');

    if (responseData.containsKey('token') &&
        responseData['token'] is String &&
        (responseData['token'] as String).isNotEmpty) {
      setAuthToken(responseData['token'] as String);
      _logger.i('Login successful, token stored in ApiClient.');
    } else {
      _logger.w(
          'Login response did not contain a valid token. Clearing any existing token in ApiClient.');
      setAuthToken(null);
    }
    return responseData;
  }接口login后得到的数据中的building.ismartId来替代,最后实现能同步获取欠费数据查询的功能,其中我需要你能生成对应文件,而且在provider文件中,添加关于更新数据的方法,在我的程序初始化的时候更新数据
