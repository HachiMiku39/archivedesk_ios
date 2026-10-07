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

## 0.3.1 build 4：本地测试版本（2026-10-06，尚未发布）

- 增加源码静态 UDF 读取后端，保留 ISO9660；UDF 文件数据按块写出，任务内复用索引读取器，避免每个文件重建整个目录。限制目录元数据、路径数量、递归深度和 extent 数量；不是无限制镜像兼容承诺。
- 修复“容量未知等于零”及解码资源限制混同“磁盘空间不足”的错误。外置卷缺少可选属性时用本地卷标志及卷身份辅助判断，仍拒绝无法确认的第三方提供商写入；未绕过系统目录授权。
- 来源快照准备阶段报告字节速度/进度。任务运行时在系统安全区固定显示 CPU、RAM、速度、已处理字节和进度，避免被长来源列表推到屏幕之外。提升可见性并不意味着人为提高 CPU/RAM 使用量；USB、压缩格式和数据本身都可能成为瓶颈。
- 核心回归：90 项通过；2 项桌面 NSFileCoordinator 环境限制明确跳过。16 种普通格式样本、8 类密码 RAR、小型 UDF → ZIP → 解压字节比对通过，损坏/取消/资源限制及回滚回归通过。
- 外置用户 ISO **仅只读列目录**：1,167 项，声明输出 6,360,050,686 字节，其中 `sources/install.wim` 5,394,922,312 字节。旧 ISO9660 路径仅看到说明文件，不能当作完整解压成功。未把此镜像复制到项目或内置盘。
- iPad Pro 11-inch (M5) / iPadOS 27.2，27.1 SDK 同源分支：首次 `Test-ArchiveDeskIOS-AdaptationQA-2026.10.06_20-16-39-+0800.xcresult` 4/4 通过；补充固定 CPU/RAM 行、UDF 元数据上限和隐私清单后的最终 `Test-ArchiveDeskIOS-AdaptationQA-2026.10.06_20-25-25-+0800.xcresult` 再次 4/4 通过、0 失败、0 跳过（171.637 秒）。覆盖 128 MiB 打包进度、解压指标、多来源 ZIP/TAR、大字体/旋转/返回，未验证物理 USB 带宽。报告另有调试会话被 code 9 终止的警告，不计作通过的测试。最终未签名 arm64 真机 Release 已构建成功，资源中已确认包含隐私清单。
- 完整 6 GB 外置 ISO → 外置解压 → 外置 ZIP → 再解压 SHA-256 比对**未执行**：外置测试目录未得到有效写入授权。测试工具只允许指定测试目录，校验原 ISO 前后哈希，成功/失败均清理自己创建的 run 目录，不改动其他 USB 文件。
- 用户 iPad 的 exFAT USB 写入、23 GB 打包、500 GB 空间显示、拔盘及真实 iCloud 仍需物理设备复测；模拟器回归不是这些硬件场景的证明。GitHub 0.3.0 发布版保持不变，0.3.1 仅提供未签名本地测试包与对应源码/重链接材料。

## 0.3.2 build 5：初始化兼容与选择解压（本地测试版）

- 用户 iPad Pro 11 / iPadOS 27.2 的 20 MB 本地来源，在点击创建 ZIP 和 TAR 后都立即报内存安全额度不足。核实代码发现 UTF-8 locale 创建失败也被错误标记为该错误；现改为显示初始化阶段、errno、编解码器已用内存，并依次尝试经过 codeset 验证的 UTF-8 locale 名称。不放宽真正的内存安全额度，不回退 ASCII。确切真机根因仍待复测，不能将模拟器或主机成功当作已修复证明。
- 压缩包浏览页直接提供“解压全部内容”或“解压整个文件夹”；多选可跨目录保留文件/文件夹选择，包含子目录，父子重叠去重。提取前冻结路径集合，密码重试保留同一选择，成功后清空多选。输出仍为新目录，不覆盖已有文件。后续按用户明确确认取消第三方网盘只读限制，统一按系统目录授权及实际可写能力判断；不再因未知提供商/USB 元数据拒绝写入。
- 缓存当前文件夹、当前多选和整个包的可解压状态，打开新包时失效；避免按钮刷新重复筛选全部条目，不保留无限制选择历史。
- 核心 102 项通过，2 项桌面文件协调明确跳过。新增 UTF-8 locale 故障注入覆盖缺失 locale、错误编码、ENOMEM、激活失败、errno 和嵌套恢复。20 MiB 本地文件夹 ZIP/TAR 完整往返、256 KiB 分块字节比对和分配释放通过；实际子集解压检查空目录保留、未选条目不写出。普通格式、UDF、小型 UDF → ZIP、1,500 文件与 8 类密码 RAR 回归通过。
- 同一台 iPad Pro 11-inch (M5) / iPadOS 27.2 首轮五项 UI 回归全部通过；加入选择可用性缓存后，同源最终五项再次全部通过（0 失败、0 跳过，231.440 秒，2026-10-06 20:53:33）。覆盖整包/整目录/多选解压、128 MiB 打包进度、多来源 ZIP/TAR、大字体/旋转/返回及解压指标。报告另有调试会话 code 9 终止警告，不是实测真机/USB 结果。此记录仅对应媒体接入前的版本。
- 纯开源媒体解码已接入源码构建 FFmpeg 9.0.2 / dav1d 1.5.4，禁用 GPL / version3 / nonfree、硬件/系统压缩解码和网络；系统仅显示已解码像素并播放 PCM。PDF / Office 未实现。真实 AV1＋AAC、FLAC、JPEG 全解码、跳转、取消与 UTF-16 日志预览通过；真实四来源 ZIP/TAR 打包进度和 SHA-256 往返通过。测试原件保持不变，私人输入快照和解压输出已清理，不发布样本。
- 增加 UTF-16 BOM、非法 Unicode、可写提供商与未知元数据、加密 ZIP 选择请求密码且输入后仍锁定的实际 Workspace 检查后，核心 111 项通过，2 项桌面协调明确跳过。
- 媒体接入后，同一台 iPad Pro 11-inch (M5) / iPadOS 27.2 原生 6/6 通过，0 失败、0 跳过，349.196 秒，结束于 2026-10-06 21:35:47。包含之前五项回归，以及真实 JPEG 显示、FLAC 和 AV1＋AAC 播放／暂停／跳转、UTF-16 日志预览，私人 ZIP 未进入 App 资源。此前一次因清理构建产物与运行测试冲突导致应用缺失而失败，已停止冲突、完整重建并重跑；不将该次失败计为通过。
- 音频会话配置移至后台，iOS 27 使用异步激活，iOS 26 保留非主线程兼容路径；取消和切换选择后不附加过期输出对象。修改后的同一台 iPad 真实媒体专项再次通过 1/1，163.488 秒，结束于 21:49:38，核心 111 项也重新通过。未再记录会话主线程激活警告；仍有内部线程优先级等待警告，需要真机 Instruments 继续定位，不宣称音频输出链路完全无等待或已完成能耗优化。
- 真实 iPad 的 ZIP/TAR、exFAT 输出和大 ISO 往返仍未验证。GitHub 发布保持 0.3.0 不变。

## 后续优先级（延续）

1. 真机 Instruments/Memory Graph 定位解码峰值，测试低内存与大 solid 字典；应用可用额度不等于设备总 RAM。
2. 为大压缩包优化读取引擎重复从头扫描的开销；先保证完整性与路径安全，不能靠忽略校验提速。
3. 只有有真机证据后，再设计后台任务及跨启动恢复；当前进入后台仍协作式取消，不宣称后台持续解压。
