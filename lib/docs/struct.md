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
大廈查詢繳費記錄(已完成)
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


//我需要存在我的应用内存中的东西
1(已完成),当我初始化使用deviceID,login以后得到的数据,
```
{
  "data": {
    "id": 13,
    "createdAt": "2025-07-16T08:17:10.853Z",
    "updatedAt": "2025-07-25T08:58:53.648Z",
    "deletedAt": null,
    "deviceId": "DEVICE_F71722C1",
    "building": {
      "id": 2,
      "createdAt": "2025-01-02T10:08:10.019Z",
      "updatedAt": "2025-04-24T17:06:45.917Z",
      "deletedAt": null,
      "name": "仁英大厦",
      "ismartId": "0314100",
      "remark": "admin123",
      "location": "九龍城",
      "devices": null,
      "notices": null,
      "advertisements": null
    },
    "buildingId": 2,
    "settings": {
      "arrearageUpdateDuration": 60,
      "noticeUpdateDuration": 60,
      "advertisementUpdateDuration": 60,
      "advertisementPlayDuration": 20,
      "noticePlayDuration": 20,
      "spareDuration": 10,
      "noticeStayDuration": 8
    },
    "status": ""
  },
  "message": "Login success",
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJidWlsZGluZ0lkIjoyLCJkZXZpY2VJZCI6IkRFVklDRV9GNzE3MjJDMSIsImV4cCI6MTc1Mzg4MDQwMiwiaXNEZXZpY2UiOnRydWV9.ojpOI5P7nl74YFnz8Ux4IlhyOADaUmQ4CJs-A0qvyH4"
}
```
我需要将上面的这个data不仅仅保存到provider,还需要保存到应用缓存里面,这样的话如果我登录失败,我就不更新这个保存的loing_device_data
2(已完成),使用上面的token,get得到的advertisement和announcement
```
{
  "data": [
    {
      "id": 19,
      "createdAt": "2025-04-23T11:25:51.232Z",
      "updatedAt": "2025-07-03T09:27:40.741Z",
      "deletedAt": null,
      "title": "20250423_335x175",
      "description": "335*175",
      "type": "video",
      "status": "active",
      "duration": 30,
      "priority": 0,
      "startTime": "2025-04-23T11:24:48Z",
      "endTime": "2025-07-31T11:24:48Z",
      "display": "top",
      "fileId": 73,
      "file": {
        "id": 73,
        "createdAt": "2025-04-23T11:25:51.145Z",
        "updatedAt": "2025-04-23T11:25:51.145Z",
        "deletedAt": null,
        "size": 12685657,
        "md5": "U/nBDVGeBBDDlAEiVGZ6Ow==",
        "path": "http://idreamsky.oss-cn-beijing.aliyuncs.com/2025-04-23/57a1301f-0e5f-45f8-aa6d-77049487939d.mp4",
        "mimeType": "video/mp4",
        "oss": "aws",
        "uploader": "admin@example.com",
        "uploaderId": 1,
        "uploaderType": "superAdmin"
      },
      "isPublic": true
    },
    {
      "id": 23,
      "createdAt": "2025-05-14T12:27:42.872Z",
      "updatedAt": "2025-07-16T07:24:21.734Z",
      "deletedAt": null,
      "title": "海關",
      "description": "335x600_1",
      "type": "image",
      "status": "active",
      "duration": 5,
      "priority": 0,
      "startTime": "2025-05-14T12:27:25Z",
      "endTime": "2025-07-31T12:27:25Z",
      "display": "full",
      "fileId": 83,
      "file": {
        "id": 83,
        "createdAt": "2025-05-14T12:27:42.792Z",
        "updatedAt": "2025-05-14T12:27:42.792Z",
        "deletedAt": null,
        "size": 404711,
        "md5": "v3DJezwGJdDicxLQAUj0gA==",
        "path": "http://idreamsky.oss-cn-beijing.aliyuncs.com/2025-05-14/5ab1d6b4-80c8-455a-82b7-0eaa1931385e.png",
        "mimeType": "image/png",
        "oss": "aws",
        "uploader": "admin@example.com",
        "uploaderId": 1,
        "uploaderType": "superAdmin"
      },
      "isPublic": true
    },
    {
      "id": 24,
      "createdAt": "2025-05-14T12:27:55.856Z",
      "updatedAt": "2025-07-16T07:24:12.646Z",
      "deletedAt": null,
      "title": "防騙",
      "description": "335x600_2",
      "type": "image",
      "status": "active",
      "duration": 5,
      "priority": 0,
      "startTime": "2025-05-14T12:27:44Z",
      "endTime": "2025-07-31T12:27:44Z",
      "display": "full",
      "fileId": 84,
      "file": {
        "id": 84,
        "createdAt": "2025-05-14T12:27:55.784Z",
        "updatedAt": "2025-05-14T12:27:55.784Z",
        "deletedAt": null,
        "size": 910119,
        "md5": "ouwqEl8e9PJ+6mAVO1yPdg==",
        "path": "http://idreamsky.oss-cn-beijing.aliyuncs.com/2025-05-14/cde686c4-6454-4a67-8e95-9854144c1f16.png",
        "mimeType": "image/png",
        "oss": "aws",
        "uploader": "admin@example.com",
        "uploaderId": 1,
        "uploaderType": "superAdmin"
      },
      "isPublic": true
    },
    {
      "id": 29,
      "createdAt": "2025-07-09T10:21:55.63Z",
      "updatedAt": "2025-07-09T10:21:55.63Z",
      "deletedAt": null,
      "title": "洗冷氣_FULL ad.",
      "description": "洗冷氣_FULL ad.",
      "type": "image",
      "status": "active",
      "duration": 5,
      "priority": 0,
      "startTime": "2025-07-09T10:21:30Z",
      "endTime": "2025-07-31T10:21:30Z",
      "display": "full",
      "fileId": 96,
      "file": {
        "id": 96,
        "createdAt": "2025-07-09T10:21:55.536Z",
        "updatedAt": "2025-07-09T10:21:55.536Z",
        "deletedAt": null,
        "size": 1559029,
        "md5": "GjvHPhJzFmo0C5fAAcUrUw==",
        "path": "http://idreamsky.oss-cn-beijing.aliyuncs.com/2025-07-09/038706be-c489-49f1-b6a0-16c352513e2c.png",
        "mimeType": "image/png",
        "oss": "aws",
        "uploader": "admin@example.com",
        "uploaderId": 1,
        "uploaderType": "superAdmin"
      },
      "isPublic": true
    },
    {
      "id": 30,
      "createdAt": "2025-07-16T07:22:22.342Z",
      "updatedAt": "2025-07-16T07:22:22.342Z",
      "deletedAt": null,
      "title": "國家安全_POSTER FULL SIZE_20250716",
      "description": "國家安全_POSTER FULL SIZE_20250716",
      "type": "image",
      "status": "active",
      "duration": 10,
      "priority": 0,
      "startTime": "2025-07-16T07:20:41Z",
      "endTime": "2025-07-31T07:20:41Z",
      "display": "topfull",
      "fileId": 100,
      "file": {
        "id": 100,
        "createdAt": "2025-07-16T07:22:22.244Z",
        "updatedAt": "2025-07-16T07:22:22.244Z",
        "deletedAt": null,
        "size": 3690037,
        "md5": "+cM0cB1ZgCOqymqPDErrgw==",
        "path": "http://idreamsky.oss-cn-beijing.aliyuncs.com/2025-07-16/abc2e409-a297-40f8-b8d3-891383b77156.png",
        "mimeType": "image/png",
        "oss": "aws",
        "uploader": "admin@example.com",
        "uploaderId": 1,
        "uploaderType": "superAdmin"
      },
      "isPublic": true
    },
    {
      "id": 32,
      "createdAt": "2025-07-16T07:36:55.922Z",
      "updatedAt": "2025-07-24T06:51:18.219Z",
      "deletedAt": null,
      "title": "國家安全_20250716_2",
      "description": "國家安全_20250716_2",
      "type": "video",
      "status": "active",
      "duration": 30,
      "priority": 0,
      "startTime": "2025-07-16T07:27:47Z",
      "endTime": "2025-07-31T07:27:47Z",
      "display": "full",
      "fileId": 102,
      "file": {
        "id": 102,
        "createdAt": "2025-07-16T07:36:55.84Z",
        "updatedAt": "2025-07-16T07:36:55.84Z",
        "deletedAt": null,
        "size": 18155716,
        "md5": "UEpVWfCJAfu9JzpddUHmhQ==",
        "path": "http://idreamsky.oss-cn-beijing.aliyuncs.com/2025-07-16/7a555e65-5912-45be-9c31-afe207d76ee2.mp4",
        "mimeType": "video/mp4",
        "oss": "aws",
        "uploader": "admin@example.com",
        "uploaderId": 1,
        "uploaderType": "superAdmin"
      },
      "isPublic": true
    }
  ],
  "message": "Get advertisements success"
}
```
和
```
{
  "data": [
    {
      "id": 111,
      "createdAt": "2025-05-22T18:14:46.782Z",
      "updatedAt": "2025-06-10T09:38:08.475Z",
      "deletedAt": null,
      "title": "Notices to visitors",
      "description": "Notices to visitors",
      "type": "normal",
      "isPublic": true,
      "isIsmartNotice": true,
      "priority": 0,
      "status": "active",
      "startTime": "2023-12-31T16:00:00Z",
      "endTime": "2100-01-31T16:00:00Z",
      "fileId": 87,
      "file": {
        "id": 87,
        "createdAt": "2025-05-22T18:14:46.767Z",
        "updatedAt": "2025-05-22T18:14:46.767Z",
        "deletedAt": null,
        "size": 1908135,
        "md5": "e0f3de8d6cc1de2cc66498e37ac7cf72",
        "path": "http://idreamsky.oss-cn-beijing.aliyuncs.com/2025-05-22/67d29806-5a9e-44de-a2c5-12d603336269.pdf",
        "mimeType": "application/pdf",
        "oss": "aliyun",
        "uploader": "admin@example.com",
        "uploaderId": 1,
        "uploaderType": "superAdmin"
      },
      "fileType": "pdf"
    },
    {
      "id": 112,
      "createdAt": "2025-05-22T18:14:58.945Z",
      "updatedAt": "2025-06-10T09:38:08.384Z",
      "deletedAt": null,
      "title": "訪客須知",
      "description": "訪客須知",
      "type": "normal",
      "isPublic": true,
      "isIsmartNotice": true,
      "priority": 0,
      "status": "active",
      "startTime": "2023-12-31T16:00:00Z",
      "endTime": "2100-01-31T16:00:00Z",
      "fileId": 88,
      "file": {
        "id": 88,
        "createdAt": "2025-05-22T18:14:57.634Z",
        "updatedAt": "2025-05-22T18:14:57.634Z",
        "deletedAt": null,
        "size": 3781966,
        "md5": "d5b5b4ef3e4b88636fffef42e09daa1b",
        "path": "http://idreamsky.oss-cn-beijing.aliyuncs.com/2025-05-22/2c8ea995-ead6-415d-bdfc-cb015542bd60.pdf",
        "mimeType": "application/pdf",
        "oss": "aliyun",
        "uploader": "admin@example.com",
        "uploaderId": 1,
        "uploaderType": "superAdmin"
      },
      "fileType": "pdf"
    },
    {
      "id": 119,
      "createdAt": "2025-07-24T09:12:32.135Z",
      "updatedAt": "2025-07-28T10:24:19.279Z",
      "deletedAt": null,
      "title": "Notice_Test_2",
      "description": "Notice_Test_2",
      "type": "urgent",
      "isPublic": true,
      "isIsmartNotice": false,
      "priority": 0,
      "status": "active",
      "startTime": "2025-07-24T09:12:15Z",
      "endTime": "2025-07-31T09:12:15Z",
      "fileId": 105,
      "file": {
        "id": 105,
        "createdAt": "2025-07-24T09:12:32.053Z",
        "updatedAt": "2025-07-24T09:12:32.053Z",
        "deletedAt": null,
        "size": 3949,
        "md5": "ON7CEBBCJxmIohesFK+VHQ==",
        "path": "http://idreamsky.oss-cn-beijing.aliyuncs.com/2025-07-24/90260a34-34b7-4233-b0f8-24fd805d7ae1.pdf",
        "mimeType": "application/pdf",
        "oss": "aws",
        "uploader": "admin@example.com",
        "uploaderId": 1,
        "uploaderType": "superAdmin"
      },
      "fileType": "pdf"
    }
  ],
  "message": "Get notices success"
}
```
我需要6个数组文件,其中两个分别是上面的一个advertisement_list,和我的announcement_list,以及我在@carousel_setting_page.dart文件中设置好的或者说修改好的top_ads_carousel_list文件,full_ads_carousel_list文件,以及announcement_carousel_list文件,这三个文件可能和advertisement_list,和我的announcement_list的顺序不一样,所以需要单独保存,同样的我的数据不只保存在我的provider之中,每次重启应用或者是设备重启,我都会调用其中的init的方法,我希望调用该方法如果成功,更新我的advertisement_list,和我的announcement_list,且关于我的设置好的或者说修改好的top_ads_carousel_list文件,full_ads_carousel_list文件,以及announcement_carousel_list文件,设置好的三个文件,更新的逻辑是,如果对比我原本的数据,如果有那个广告文件剔除在list中的话,就在该list中删除该文件,但是不破坏其他文件的顺序或者说数组的序号,如果更新的数据中有list中没有的话,就在末尾添加该文件,这样的话每次更新都不会轻易破坏我设置好的轮播顺序
3,我需要保存我的欠费数据,我通过我的欠费数据api的话,得到的数据也需要持久化保存,并且更新逻辑的话,也是如果成功的话就更新数据,如果不成功的话就不更新数据
4,关于我的两个二维码,这两二维码的变化可能呢只会在我使用deviceIDlogin成功以后得到的ismartId字段变化后才需要重新获取,所以我的这两二维码的更新逻辑是检查我的ismartId是否更新,如果改变的话就开始重新获取我的两二维码,我需要尽量能下载这两二维码文件到我的应用缓存之中,并且保存两url
5,关于天气的信息,我在本地设置好了静态的图片资源,同理我需要你能保存我的天气的信息,能持久化存储,几个api都是如此,只有成功才会更新对应的信息,否者不更新,这样能保证我的屏幕显示不会出现加载失败导致的错误page

6,我不确定保存到provider中的数据是否可以确保数据的可靠,如果可靠的话帮我实现上面的要求,要求能采用规范的方式方法保留数据,可靠,且我需要你完成的时候能一个一个模块的完成,先完成1,不动其他的文件


總結一下目前大廈屏
1. 全屏廣告無法輪播(已完成)
2. 欠費查詢頁面字眼修改(已完成)
3. 左下角方塊常出現斷線
4. 左下角方塊沒顯示大廈名(已完成)
5. 左下角方塊沒顯示天氣警告圖示(已完成)
6. 通告輪播下沒加入大廈繳費總表
7. 通告点击显示对应的通告(已完成)