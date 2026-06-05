# iBoard Flutter 项目业务逻辑总览

本文档用于给后续开发者或 AI 快速理解 `iboard_flutter` 项目的业务逻辑。项目本质是一个长期运行在 Android 大屏上的楼宇信息展示系统，业务重点不是单页交互，而是多区域轮播、后台配置、缓存降级、全屏广告、缴费、欠费、天气、新闻、打印和实时监控的协同。

项目使用 `provider` + `ChangeNotifier` 管理状态。不要在局部优化中引入新的状态管理框架。

## 一、业务域总数

当前项目可以归纳为 12 个业务域，合计 180 条核心业务逻辑，另有 10 条重点修改原则：

1. 应用启动、设备身份与登录
2. 全局状态机与区域播放控制
3. 后台设置与时间参数
4. 广告业务
5. 通告与中部轮播业务
6. 主屏、手动操作与设置页业务
7. 天气、二维码与新闻业务
8. 欠费与费用表业务
9. 电子缴费业务
10. 打印与小票业务
11. 实时监控业务
12. 更新、缓存、异常降级与接口业务

## 二、应用启动、设备身份与登录

1. 应用入口是 `lib/main.dart`，`main()` 使用 `runZonedGuarded` 捕获未处理异常，启动前先初始化 Flutter binding。

2. 应用通过 `MultiProvider` 注册所有核心 Provider，包括 `AppDataProvider`、广告、通告、轮播状态、天气、新闻、欠费、打印、支付、小票打印和更新等。

3. `HomePageState._initializeDeviceId()` 使用 `DeviceIdUtil.generateUniqueDeviceId()` 生成本机设备 ID。

4. 设备 ID 是设备登录、设备配置、楼宇绑定和接口授权的核心身份。

5. `AppDataProvider.initialize(deviceId)` 会尝试调用设备登录接口；登录成功后保存 token、楼宇信息和后台设置。

6. 设备登录失败时不会直接阻止应用启动，而是尝试从 `SharedPreferences` 加载缓存的登录设备数据。

7. 如果登录失败且缓存也不可用，应用仍保留初始化流程，但会记录初始化错误，用于错误页或后续降级展示。

8. `AppDataProvider` 构造时会异步预加载缓存设备数据，使设置页和部分页面在网络未完成时也能先显示缓存内容。

9. 登录成功或缓存加载成功后，`ApiClient.setAuthToken()` 会设置后续接口使用的 Bearer token。

10. 登录设备数据会缓存到 `login_device_data`，用于断网启动或服务器不可用时恢复楼宇配置。

11. `AppDataProvider.startPeriodicLogin()` 按固定周期重新登录，用于刷新 token、楼宇配置和后台时间参数。

12. `AppDataProvider` 可以执行设备健康检查，并记录最后一次健康检查时间和结果。

## 三、全局状态机与区域播放控制

13. 全局状态机由 `lib/providers/state_provider.dart` 的 `CarouselStateProvider` 管理，是项目最重要的业务中心。

14. 全局状态 `AppState` 分三种：`defaultState`、`fullscreenAd`、`manualOperation`。

15. `defaultState` 表示正常自动播放状态，不是静态首页。顶部广告、中部轮播、底部区域自动播放，全屏广告暂停。

16. `fullscreenAd` 表示全屏广告状态。顶部广告、中部轮播、底部区域暂停，全屏广告播放。

17. `manualOperation` 表示用户手动操作状态。顶部和底部继续自动播放，中部进入手动暂停状态，全屏广告暂停。

18. 区域播放状态 `PlaybackState` 分为 `auto`、`paused`、`manual`。

19. 区域类型 `AreaType` 分为顶部广告、中部通告、底部区域和全屏广告。

20. 手动状态不能直接调用 `toDefaultState()`，否则会抛错。业务恢复必须走 `exitManualOperationToDefault()` 或 `resetToDefault()`。

21. `CarouselStateProvider` 同时管理三个全局计时器：全屏广告计时器、手动操作超时计时器、默认态进入全屏广告计时器。

22. 状态切换前必须清理旧计时器，避免多个 timer 同时触发导致状态互相覆盖。

23. 进入全屏广告时，状态机会暂停顶部广告、暂停中部轮播、暂停底部轮播、暂停 RTHK 新闻跑马灯，并启动全屏广告 Provider。

24. 全屏广告自动结束时会回到默认态，并关闭全屏广告弹窗。

25. 用户主动关闭全屏广告时会进入手动操作态，并把中部轮播跳回主屏。

26. 在默认态任意点击屏幕会进入手动操作态。

27. 在手动操作态继续点击只会刷新手动操作超时计时器，并带有节流逻辑。

28. 电子缴费等需要长时间停留的页面可以禁用手动操作超时。

## 四、后台设置与时间参数

29. 后台设置模型是 `SettingsModel` 和 `Settings`，位于 `lib/models/settings_model.dart`。

30. `Settings.advertisementPlayDuration` 控制全屏广告状态总时长，也会影响单个全屏广告播放上限。

31. `Settings.noticeStayDuration` 控制中部通告或内容停留时长。

32. `Settings.bottomCarouselDuration` 控制底部天气和二维码切换时长。

33. `Settings.paymentTableOnePageDuration` 控制缴费表格或欠费表格单页停留时长。

34. `Settings.normalToAnnouncementCarouselDuration` 控制手动操作无交互后恢复到通告轮播的时间。

35. `Settings.announcementCarouselToFullAdsCarouselDuration` 控制默认通告轮播态多久进入全屏广告。

36. `Settings.noticeUpdateDuration` 控制通告数据定时刷新间隔。

37. `Settings.advertisementUpdateDuration` 控制广告数据定时刷新间隔。

38. `Settings.arrearageUpdateDuration` 控制欠费数据刷新间隔。

39. `Settings.appUpdateDuration` 控制应用版本检查间隔。

40. `Settings.printPassWord` 是打印或设置相关密码字段。

41. `Settings.orangePiIp` 是打印服务所在 OrangePi 的 IP，未配置或连接不上时不应阻塞应用主业务。

42. 设置字段解析支持多个打印密码字段名：`printPassWord`、`printPassword`、`print_password`、`print_pass_word`。

## 五、广告业务

43. 广告模型是 `AdModel`，展示类型 `AdDisplayType` 包含顶部、全屏、顶部加全屏。

44. `AdvertisementProvider` 负责从接口获取广告数据，并拆分为顶部轮播广告和全屏轮播广告。

45. 顶部广告接口使用 `ApiClient.getCarouselTopAdvertisements()`。

46. 全屏广告接口使用 `ApiClient.getCarouselFullAdvertisements()`。

47. 广告数据会缓存到 `advertisements_data`、`top_carousel_advertisements`、`full_carousel_advertisements`。

48. 广告刷新失败时应继续使用已有缓存，避免大屏空白。

49. 广告列表是否变化主要按 id 和顺序判断，不做深度字段比较。

50. `AdvertisementProvider` 登录后会按后台设置的广告更新间隔启动周期刷新。

51. `TopAdCarouselProvider` 管理顶部广告播放、定时器、暂停恢复、Widget 缓存和视频资源。

52. 顶部广告支持图片、视频和实时监控插入项。

53. 如果监控布局不是 hidden 且已选择通道，顶部广告列表末尾会追加 `LiveMonitorAdModel`。

54. 顶部广告进入全屏广告前会保存当前播放时间，退出全屏广告后根据业务恢复或切到下一条。

55. 顶部实时监控不是普通视频广告，恢复时应继续剩余时间，不按普通广告强制切换。

56. `FullscreenAdProvider` 管理全屏广告内部轮播、Widget 缓存、视频进度和全屏广告视频控制器释放。

57. 全屏广告状态总时长由状态机控制，单条全屏广告展示上限由 `FullscreenAdProvider.fullscreenAdDuration` 读取后台设置。

58. 全屏广告进入前会清理可能残留的视频控制器，退出时也会释放控制器，避免视频解码器资源占用。

59. 全屏广告播放中如果广告列表变化，Provider 会延迟到下次切换时更新 Widget，避免重建正在播放的视频。

60. 全屏广告退出后 `_currentAdIndex` 会前进，下次进入时从下一条继续。

## 六、通告与中部轮播业务

61. 通告数据由 `AnnouncementProvider` 获取、缓存和定时更新。

62. 通告轮播接口使用 `ApiClient.getCarouselNotices()`。

63. 通告数据缓存键是 `announcements_data`。

64. 通告 Provider 会预下载通告附件文件，并清理不再使用的缓存文件。

65. 通告列表变化同样主要按 id 和顺序判断。

66. `AnnouncementCarouselProvider` 管理中部区域，是最复杂的 Provider。

67. 中部轮播固定索引约定：索引 0 是主屏幕，索引 1 是独立通告占位，索引 2 以后是通告、管理费表、其他费用表等正常轮播内容。

68. 正常轮播不能把索引 0 首页纳入循环，首页只是用户和业务回退目标。

69. 正常通告轮播应从索引 2 开始。

70. 独立通告模式用于用户点击主屏右侧某条通告后单独查看通告详情。

71. 进入独立通告模式时会保存原正常轮播索引，临时把中部轮播改成主屏和当前通告详情两页。

72. 退出独立通告模式时会重建正常轮播内容，并恢复到之前保存的正常轮播索引。

73. 通告附件如果是 PDF，多页播放时会通知 Provider 延长停留时间，避免 PDF 未翻完就切走。

74. 中部轮播同时负责挂载管理费表和其他费用表，费用表分页未完成时不能强行切到下一项。

75. 如果没有通告但有费用表，中部轮播仍应能工作。

76. 中部轮播有 watchdog，用于检测默认态下异常暂停并恢复。

77. 设置页或全屏广告会暂停中部轮播，恢复时需要按保存索引或最后有效索引继续。

## 七、主屏、手动操作与设置页业务

78. 主容器是 `MainPage`，实际大屏页面是 `AnnouncementPage`。

79. `MainPage` 注册显示和关闭全屏广告弹窗的回调，并捕获用户点击进入手动操作。

80. 全屏广告弹窗关闭后会区分自动关闭和用户关闭：自动关闭保持默认态，用户关闭进入手动操作态。

81. `AnnouncementPage` 负责把全局状态同步到顶部、中部、底部和新闻 Provider。

82. `AnnouncementPage` 初始化顶部广告、中部轮播、底部轮播、RTHK 新闻和欠费数据。

83. `MainScreenWidget` 是中部首页，承载楼宇信息、通告入口、欠费入口、电子缴费入口等主屏业务。

84. 点击主屏上的通告会进入独立通告模式。

85. 点击电子缴费会进入手动操作态，并禁用全局手动超时，直到缴费页自己的无操作超时恢复。

86. 进入设置页时，项目会进入手动操作态并暂停所有轮播和媒体。

87. 从设置页返回时，会重置到默认态并恢复顶部、中部、全屏广告和媒体播放通知。

88. 设置页包含时间设置、打印设备管理、监控设置和应用更新入口。

89. 时间设置页主要用于查看或调整后台控制的各类轮播时长。

90. 轮播设置页用于调试或调整广告、通告、全屏广告相关播放规则。

## 八、天气、二维码与新闻业务

91. 天气数据由 `WeatherProvider` 管理，底层请求类是 `WeatherService`。

92. 天气包含三类数据：天气预报、当前天气、天气警告。

93. 天气预报和当前天气会按较长周期刷新，天气警告会按较短周期独立刷新。

94. 天气数据分别缓存到 `weather_forecast_cache`、`weather_current_cache`、`weather_warning_cache`。

95. 天气接口失败时会使用缓存数据作为降级。

96. 底部区域在天气和二维码之间轮播，默认间隔由后台 `bottomCarouselDuration` 控制。

97. 当前天气卡片内部有 page1 和 page2 两页；只有存在天气警告时才启用内部轮播，否则固定在第一页。

98. 二维码由 `AppDataProvider` 初始化并缓存，包含投诉二维码和登记二维码。

99. 二维码缓存使用本地文件路径，避免每次启动重复生成或下载。

100. RTHK 新闻由 `RthkNewsProvider` 管理，30 分钟检查一次。

101. RTHK 新闻数据会缓存到 `rthk_news`，并保存最后更新时间。

102. RTHK 新闻会过滤测试数据和网络错误占位数据。

103. 进入全屏广告时 RTHK 新闻跑马灯暂停，退出全屏广告后恢复。

## 九、欠费与费用表业务

104. 欠费数据由 `ArrearProvider` 管理，费用类型分为管理费和其他分摊费用。

105. 管理费数据模型是 `ManagementFeeModel`，其他分摊费用模型是 `OtherFeeModel`。

106. 欠费接口包含 `ApiClient.getManagementFeeStatus()` 和 `ApiClient.getOtherFeeStatus()`。

107. 欠费业务以楼宇 `ismartId` 为关键参数，无法取得时有固定 fallback id。

108. 欠费数据会缓存管理费、其他费用和最后更新时间。

109. 欠费数据按后台设置周期刷新，刷新后通知中部轮播重建费用表 Widget。

110. 欠费查询支持楼座、楼层、单位三级筛选。

111. 楼座、楼层、单位列表会合并管理费和其他费用数据，并做排序。

112. 字母楼层或单位排在数字楼层或单位前面。

113. 费用表可以作为中部轮播内容自动展示。

114. 费用表分页开始时会通知中部轮播延长停留时间，分页完成后再允许切换下一项。

115. 欠费表 Widget 有缓存和数据版本号，避免数据未变化时重复构建。

116. 主屏上用户也可以手动查看指定单位的费用信息。

## 十、电子缴费业务

117. 电子缴费由 `PaymentNotifier` 管理状态，模型位于 `lib/models/payment_model.dart`。

118. 支付底层接口有两套：`ApiClient` 内的支付创建和查询接口，以及 `PaymentClient` 的 iSmartPOS 物业支付接口。

119. 支付方式包括微信、支付宝、云闪付等。

120. 缴费入口会先选择大厦，再加载单位列表。

121. 选择大厦后会加载支付配置和费率配置；配置为空时代表支付功能不可用。

122. 单位列表按楼层和单位做筛选与排序。

123. 选择单位后会加载该单位账单。

124. 用户选择账单后计算总金额，并按支付方式生成支付二维码或支付订单。

125. 创建支付订单后会进入轮询状态，定时查询支付结果。

126. 支付成功后会保存支付记录，本地最多保留最近 50 条。

127. 支付记录包含支付 id、交易 id、状态、大厦、单位、账单数量和总金额。

128. 缴费页面有自己的无操作超时，超时后恢复到默认通告轮播，而不是依赖全局手动操作超时。

129. 支付成功后可以触发小票打印业务。

130. 支付接口包含交易列表、清机、入账记录、银行账户、支付上报等扩展能力。

## 十一、打印与小票业务

131. 网络打印业务由 `PrinterProvider` 管理，打印 API 客户端是 `PrintApiClient`。

132. 打印服务部署在 OrangePi 上，默认访问 `http://{orangePiIp}:8080`。

133. 如果后台或缓存中没有 OrangePi IP，打印 Provider 只标记已初始化，不影响应用启动。

134. 如果 OrangePi 不可用，打印服务应标记为不可用，不应阻塞主屏、广告、天气或缴费业务。

135. 打印机列表缓存键是 `api_saved_printers`，默认打印机缓存键是 `api_default_printer_id`。

136. OrangePi IP 缓存键是 `orange_pi_ip`。

137. 打印 Provider 支持刷新打印机、添加打印机、删除打印机、设置默认打印机、获取详情、获取配置。

138. 添加打印机前会先测试 IP 连通性。

139. 打印 PDF 时会把 PDF 文件转为 base64 后发送到 OrangePi 打印服务。

140. 打印服务支持获取打印任务、取消任务、批量测试打印机和健康检查。

141. 打印健康检查会将 OrangePi 状态和打印机状态回传业务后端。

142. `PrinterConnectionManager` 是另一套本地打印机连接管理，负责保存系统打印机和默认打印机。

143. `WiFiPrinterService` 使用 `printing` 包扫描系统打印机，并支持 PDF、图片打印。

144. 如果系统没有发现打印机，WiFi 打印服务会尝试添加预设 HP LaserJet 7200。

145. `ReceiptPrinterNotifier` 管理小票打印。

146. 小票打印初始化会检查权限，并准备 USB 或蓝牙热敏打印机候选项。

147. 小票内容会生成 80mm 宽度 PDF，包含大厦、单位、支付方式、支付时间、支付编号、账单明细和总金额。

148. 桌面平台通过系统打印对话框打印小票，移动平台保存文件或分享。

## 十二、实时监控业务

149. 实时监控配置模型位于 `monitor_models.dart`，布局类型 `MonitorLayoutType` 控制隐藏、四宫格等展示方式。

150. 实时监控以 `LiveMonitorAdModel` 形式插入顶部广告轮播。

151. 只有监控布局不是 hidden，且已选择通道时，才会插入实时监控广告项。

152. `LiveMonitorWidget` 负责真实监控画面展示。

153. 监控配置存储在本地 `SharedPreferences`，例如布局类型和已选择通道。

154. 设置页修改监控配置后，`TopAdCarouselProvider.refreshAllMonitorWidgets()` 会检测配置变化并刷新已有监控 Widget。

155. 实时监控不参与普通视频预加载，避免占用过多资源。

156. 实时监控在顶部广告恢复时应继续剩余时长，不应被当成普通广告强制切换。

157. `LiveMonitorWebViewPage` 是监控 WebView 页面入口。

## 十三、更新、缓存、异常降级与接口业务

158. 应用更新由 `AppUpdateProvider` 管理。

159. 启动时会检查更新权限，并调用 `checkForUpdate(autoDownload: true)`。

160. 更新 Provider 会读取当前版本、远程版本、更新说明、下载地址和本地 APK 状态。

161. Android 更新需要处理存储权限和安装 APK 权限。

162. 检查更新和安装都有节流，避免重复点击或重复请求。

163. 下载 APK 时记录下载进度、已接收字节和总字节。

164. 下载完成后可以打开 APK 或跳转外部链接。

165. `ApiClient` 是主业务后端客户端，负责设备登录、健康检查、广告、通告、新闻、欠费、打印状态回传、支付创建与查询。

166. `ApiClient` 对普通请求设置超时、一次重试和 token 刷新机制。

167. 需要鉴权的接口会带 Bearer token。

168. 如果请求前健康检查失败，非登录和非健康检查请求可能会被中断或降级。

169. token 刷新通过 `onNeedsTokenRefresh` 回调触发，并避免并发刷新。

170. `PaymentClient` 是 iSmartPOS/AWS API Gateway 客户端，负责物业缴费相关扩展接口。

171. `WeatherService` 是香港天气公开接口客户端。

172. `FileManager` 负责广告、通告等远程文件的本地缓存。

173. 广告、通告、天气、新闻、欠费、登录设置都具备缓存降级逻辑。

174. 业务原则是大屏不能因为单个接口失败而整体不可用。

175. 网络失败时优先使用缓存；没有缓存时才展示错误或离线状态。

176. 所有定时器在 Provider dispose 或页面 dispose 时应取消，避免后台持续执行。

177. 视频广告和监控业务需要注意解码器资源，避免多个 `VideoPlayerController` 同时占用硬件解码器。

178. `PreciseVideoPoolManager` 用于精确管理视频控制器和解码器占用，降低广告轮播中的闪退风险。

179. 主屏长期运行场景下，应优先优化内存、计时器、缓存文件、视频控制器释放和网络失败降级。

180. 后续优化任何业务时，应先判断它属于上述哪个业务域，再按对应 Provider 和模型定位，不要只从页面 Widget 修改。

## 十四、重点修改原则

1. 修改全局播放状态时，优先检查 `CarouselStateProvider`。

2. 修改中部内容顺序时，必须遵守索引 0 首页、索引 1 独立通告占位、索引 2 以后正常轮播内容的约定。

3. 修改广告时，要同时考虑 `AdvertisementProvider`、`TopAdCarouselProvider` 和 `FullscreenAdProvider`。

4. 修改天气或二维码时，要考虑底部轮播暂停恢复。

5. 修改缴费时，要考虑手动操作超时禁用和缴费页自己的无操作恢复。

6. 修改打印时，要保证 OrangePi 不可用不会拖慢或阻塞主业务。

7. 修改实时监控时，要避免把它当普通视频广告处理。

8. 修改接口时，要保留缓存降级，避免断网时大屏空白。

9. 修改设置页时，要保证进入设置暂停轮播，退出设置恢复默认态。

10. 修改视频相关逻辑时，要优先检查控制器释放和解码器占用。
