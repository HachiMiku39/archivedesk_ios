# 0.3.0：iOS 性能与自适应优化

## 苹果文档与实现取舍

- [SwiftUI 性能指导](https://developer.apple.com/documentation/Xcode/understanding-and-improving-swiftui-performance)：不在视图 body 中反复扫描、排序全部条目。目录在可取消后台任务计算，只缓存当前目录；搜索去抖 200 ms，版本标记防止旧结果覆盖新查询。性能采样只发布到独立面板模型。
- [NavigationSplitView](https://developer.apple.com/documentation/swiftui/navigationsplitview)：用系统导航，在紧凑宽度选择条目后进入详情，打开新压缩包/进入目录时回到列表。状态保留在导航视图之外。
- [iPad 自适应设计](https://developer.apple.com/videos/play/wwdc2025/208/)：按窗口详情区的实际宽度而非设备名称决策。普通宽屏使用双栏详情；详情宽度不足 720 pt 或辅助功能大字体时，使用可滚动单列。保持系统安全区、原生工具栏与系统文件选择器；提供 ⌘O/⌘E。
- [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)：详情和性能值在辅助功能字号下纵向排列，保留完整文字。密码页大字号仅采用 large detent，支持键盘继续，空密码禁止提交。
- [减少内存使用](https://developer.apple.com/documentation/xcode/making-changes-to-reduce-memory-use)：固定大小进度快照，256 KiB 流式 I/O/分块 autorelease pool，后台停止采样，内存告警取消任务并释放预览/目录计算缓存。任务前等待旧预览解码器结束。开源许可只读取/分段一次，不随视图更新重复处理。
- [目录授权](https://developer.apple.com/documentation/uikit/providing-access-to-directories)：保持 security-scoped URL 和 NSFileCoordinator。外置/iCloud 写入策略不放宽，第三方网盘仍只读；不直接访问任意文件路径。

这些优化是代码层面的开销削减，不是同机基准中量化的性能提升，也不是避免 jetsam 的保证。

## SDK 边界

27.1 SDK 有 Duo 的 ArrangementView/hinge/reservedRegions 接口，27.2 SDK 未包含这些声明。
项目按 SDK 名称 `iphone*27.1` 设置 `DUO_SDK` 条件：Duo 构建保留这些公共接口，其他 SDK 编译标准 SwiftUI 分支。不根据私有机型字符串识别设备，不模拟或覆写 hinge。
本次发布的 arm64 IPA 使用 27.1 SDK，deployment target 仍为 26.0。辅助功能测试字号与示例压缩包仅在 DEBUG 下提供，不进入 Release。

## 验证与未完成事项

- 核心、格式、批量 ZIP/TAR、8 类密码 RAR、损坏/取消回滚由本地验证脚本检查。
- 2026-10-06：核心 79 项通过，2 项桌面文件协调明确跳过；格式/批量/密码 RAR 回归通过。27.2 SDK 编译的通用分支在 Duo 27.1 上完成适配 QA，3/3 通过、0 跳过：辅助功能大字体/旋转/返回、解压性能、多来源 ZIP/TAR。首次返回测试错误地只查导航栏，未找到 Duo 的原生侧边 `BackButton`；按实际层级修正测试查询后通过。该结果不是普通 iPhone/iPad 的验证。
- `ArchiveDeskIOS-AdaptationQA` scheme 包含大字体/旋转/返回导航、解压性能、多来源 ZIP/TAR UI 测试，可在普通 iPhone、iPad、Duo 上运行。
- 27.1 SDK 的 Duo 专用分支：`Test-ArchiveDeskIOS-AdaptationQA-2026.10.06_12-19-04-+0800.xcresult`，3/3 通过、0 跳过。
- 普通 iPhone 17e / iOS 27.2：`Test-ArchiveDeskIOS-AdaptationQA-2026.10.06_12-26-57-+0800.xcresult`，3/3 通过、0 跳过；覆盖大字体、横竖屏、返回导航、CPU/RAM/解压进度、多来源 ZIP/TAR。
- iPad Pro 11-inch (M5) / iPadOS 27.2：`Test-ArchiveDeskIOS-AdaptationQA-2026.10.06_12-35-18-+0800.xcresult`，同三项 3/3 通过、0 跳过。首次打包断言只找到 Export 回执标题，未滚动到下一行的输出路径；检查截图后修正测试滚动，再完整重跑通过。普通 iPhone 和 iPad 均运行了 27.1 SDK 的发布同源分支。
- 本轮运行时故障已恢复：27.0/27.2 模拟器服务曾缓存旧 cryptex 挂载路径，liblaunch_sim.dylib 报 errno 13。正常退出服务和 Device Hub、重新打开 Xcode 查询后，普通 iPhone/iPad 重新可用。未删除运行时/设备数据，未更改系统保护。
- iPad 窄窗口、Stage Manager、硬件键盘及完整 VoiceOver 尚待单独验证；不以旋转/大字体测试替代。
- 真机重签安装、内存压力、USB 外置介质拔盘/只读、真实 iCloud 和第三方文件提供商仍需验证。

## 后续优先级

1. 真机 Instruments/Memory Graph 定位解码峰值，测试低内存与大 solid 字典；应用可用额度不等于设备总 RAM。
2. 为大压缩包优化读取引擎重复从头扫描的开销；先保证完整性与路径安全，不能靠忽略校验提速。
3. 只有有真机证据后，再设计后台任务及跨启动恢复；当前进入后台仍协作式取消，不宣称后台持续解压。
