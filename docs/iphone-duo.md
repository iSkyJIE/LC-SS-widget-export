# iPhone Duo 适配说明

适配对象：iPhone Duo（`iPhone19,4`，Apple 首款折叠 iPhone，iOS 27）。

| | 外屏（合上） | 内屏（展开） |
| --- | --- | --- |
| 尺寸 | 5.4 英寸 | 7.6 英寸 |
| 分辨率 | 1398 × 2034 | 1878 × 2670 |
| 点尺寸（@3x 推算） | 约 466 × 678 pt | 约 626 × 890 pt |
| 宽高比 | 约 1.4 | 约 1.4（与外屏相同，内容等比缩放） |

点尺寸是按 @3x 推算的，未在真机上实测；下面所有逻辑都不依赖精确数值，
只依赖 600pt 的展开阈值（介于两块屏之间），即使实际 scale 有出入行为也是对的。

## 适配原则

- **不按机型字符串判断。** 没有公开的折叠状态 API，也不在代码里写死
  `iPhone19,4`；一切按实时 scene 尺寸 / size class 走，iPad 和以后的折叠机也受益。
- **不加新开关。** 折叠/展开是自动的，不给用户再加一个设置项。
- **不碰核心注入逻辑。** dyld、JIT、签名、Guest 启动流程与 Duo 无关，不动。

## 本来就已经对的（未改）

- `TARGETED_DEVICE_FAMILY = 1,2`（iPhone + iPad），内屏走 iPad 式布局的基础已在。
- `UIApplicationSupportsMultipleScenes = YES`，iPhone / iPad 四向全支持。
- iOS 27 已有针对性代码：`LCBootstrap.m` 的 dyld 偏移、`AppSceneViewController.m`
  的键盘 deferring、`UIKitPrivate+MultitaskSupport.h` 的 iOS 27 API。
- 主构建用 Xcode 26.2（`.github/workflows/build.yml`），iOS 27 SDK 已覆盖。
- `LCWidgetProbe` 不用改：它没有界面，只是把 SideStore Core Data 快照写成
  `widget_data.json`，与屏幕尺寸无关。

## 改了什么

### 1. 新增 `MultitaskSupport/LCDuoGeometry.swift`（共享几何工具）

- `formFactor(for:horizontalSizeClass:)`：宽 ≥ 600pt 或横向 size class 为 regular
  即展开态，否则为外屏态。
- `keyWindowScene()` / `keyWindow()`：取前台活跃 scene 的 key window，不再取
  `connectedScenes.first`（多 scene / 折叠过渡时 first 可能是错的那个）。
- `initialDecoratedWindowSize(for:landscape:)`：悬浮 Guest 窗口的初始尺寸改为按
  容器比例算，不再固定 320×480 / 480×320。

该文件放在 `MultitaskSupport/` 同步目录下，但这个工程的同步目录**不会**
自动编入 target：新文件必须写进 `project.pbxproj` 里
`MultitaskSupport` 的 `PBXFileSystemSynchronizedBuildFileExceptionSet`
的 `membershipExceptions`（目标 `LiveContainerSwiftUI`），否则编译报
`cannot find 'LCDuoGeometry' in scope`。2026-11-24 的首次构建就是这么
红的，补上这一行才修好。以后再往这个目录加文件，同样要补这一行。

### 2. `MultitaskSupport/MultitaskDockView.swift`（多任务 Dock）

- `keyWindow` 改走 `LCDuoGeometry.keyWindow()`；`bringMultitaskViewToFront`、
  `setupEdgeGestureRecognizers` 同样改走前台 scene。
- `keyWindow!` 的 7 处强制解包全部去掉，改走 `keyWindowBounds`
 （无 key window 时回落到 `UIScreen.main.bounds`）；`init` 里原来会 crash 的
  `keyWindow!.rootViewController!.view.subviews.first!` 链改为
  `attachHostingViewIfNeeded()`，并在每次 `updateDockFrame` 时重试挂载。
- `MultitaskDockSwiftView` 的 `GeometryReader` 上加
  `.onChange(of: g.size)`：折叠/展开只改 scene 尺寸、不改方向，
  原来的 `UIDevice.orientationDidChangeNotification` 根本收不到，
  这是 Dock 跟上折叠的唯一可靠触发点。

### 3. `MultitaskSupport/DecoratedAppSceneViewController.m`（悬浮 Guest 窗口）

- `setupDecoratedView` 的固定 320×480 / 480×320 改为
  `[LCDuoGeometry initialDecoratedWindowSizeForContainerSize:landscape:]`。
  外屏竖屏约 317×475（与原来基本一致），内屏竖屏约 426×639，
  不再是内屏里的一座小孤岛。导航栏 44pt 照旧叠加在上面。

### 4. `MultitaskSupport/VirtualWindowsHostView.m`

- `init` 改走 `LCDuoGeometry.keyWindow()`，并补
  `#import "LiveContainerSwiftUI-Swift.h"`；容器尺寸为 0 时回落到主屏尺寸。

### 5. `LCFloatingMenu/LCFloatingMenu.m`（悬浮菜单，核心改动）

- `buildPanel`：scene 宽 ≥ 600pt 时抽屉宽 346 → 380pt，外屏保持 346pt。
  微珠位置本来就是按比例存的（`orbY` 为 0.1–0.9 的相对值 + 左右吸附），
  折叠后位置自动跟随，不用改。
- `FMEnsureWindowOrientationLayout`：**这是原来折叠会坏的根因。**
  旧逻辑竖屏直接 `return`，因为以前竖屏只有一种尺寸；Duo 的外屏和内屏
  都是竖屏、尺寸不同，折叠时 Guest 窗口会一直停在折叠前的尺寸。
  现在竖屏分支会记录上一次竖屏尺寸，尺寸变化时只把“仍等于旧竖屏尺寸
  的全屏窗口” resize 到新尺寸，多任务窗口、PiP、设置窗口一律不动；
  首次调用只记录不改，保证启动行为不变；尺寸比较让重复调用都是 no-op，
  `layoutSubviews` 不会因此死循环。
  **第二轮修正（2026-11-23，真机仍卡死后查出）：**上面那套逻辑只改了
  函数内部，折叠时它根本不会被调用——竖屏折叠不改变方向、不发方向
  通知，而唯一的通用触发点 `UIWindow.fm_layoutSubviews` 只在横屏才
  调用它。所以改成每次窗口布局都跑一次 ensure（无变化时 no-op，
  有重入保护，不会循环）。另外悬浮 Guest 窗口本身只在创建时按比例
  定尺寸，`DecoratedAppSceneViewController.updateWindowedFrameWithSettings`
  现在容器宽度变化时也会重算尺寸，并跳过折叠过渡期短暂出现的零尺寸，
  防止 `originalFrame` 被 inf/NaN 污染导致窗口丢失。

### 6. 启动屏：不补（已撤回）

仓库里 `UILaunchStoryboardName = LaunchScreen` 一直指向一个不存在的文件，
启动回落到 `Info.plist` 里的老式 `UILaunchImages`。本来补了一个纯 Auto Layout
的启动屏（`Resources/LaunchScreen.storyboard`），但它在 Xcode 26.2 的
`CompileStoryboard` 上失败且日志长期不给诊断，卡住整个构建；启动屏不是
Duo 适配必需的（原版没有它也能启动），2026-11-23 已撤回该文件并从
`project.pbxproj` 的 `Resources` exception set 里删掉登记，恢复成原版行为。
（`UIMainStoryboardFile = Main` 同样指向不存在的文件，但那是 SwiftUI `@main`
的遗留键，实测启动不受影响，本次不动。）

## 构建

- 主 App：GitHub Actions `Xcode - Build`（Xcode 26.2），与原来一样。
- FloatingMenu dylib：`LCOrbit/Build/build.sh`，用 runner 自带 SDK 编译；
  本次改动没用任何新 SDK 符号（只有运行时判断），`macos-15` 的流程不用改。
- 本地 Linux 环境没有 Xcode / iOS SDK，**无法在这里编译验证**；
  以 Actions 绿为准（另见下面的测试清单）。

## 真机测试清单（iPhone Duo `iPhone19,4`）

1. 合上状态冷启动 LC：启动屏铺满、无黑边、无拉伸。
2. 打开一个 Guest，合上 → 展开：Guest 窗口跟到内屏尺寸，不留折叠前的黑框；
   再合上：缩回外屏尺寸。
3. 展开态开悬浮菜单：抽屉 380pt、内容不溢出；合上态：346pt。
4. 展开/合上各拖一次微珠换边，杀掉重进：位置还在同一侧同一高度。
5. 多任务 Dock：展开/合上后 Dock 贴边位置正确，不飘到屏幕外；开两个 Guest
   并排，再折叠一次，两个窗口都不丢。
6. 悬浮窗口：新建一个多任务窗口，展开态明显大于外屏态，拖动缩放正常。
7. 状态栏：Duo 的状态栏是重新设计的，留意 LC 的 `LCStatusBarManager`
   在展开/合上时有没有错位（本次没改它，只做了复核）。
8. 横屏展开：Guest 横屏 + 竖屏各折叠一次，不闪退。

## 已知未验证 / 风险

- 点尺寸（466×678 / 626×890）是 @3x 推算值，以真机实测为准；若与实际不符，
  只调 `LCDuoGeometry.expandedWidthThreshold` 一个数。
- 铰链/折痕处的安全区：系统是否给内屏上报额外的 safe area，目前无真机数据；
  本次所有布局都走 `safeAreaInsets`，理论上会自动避让，仍需目视确认。
- iPhone-only 的 Guest 在内屏是否会按 iPad 宽度渲染，取决于 Guest 自身的
  `UIDeviceFamily` 与 LC 的 scene 设置，本次没改 Guest 的 scene 配置；
  若某 Guest 展开后仍是窄条，那是下一步要单独处理的问题。
- Duo 的竖向系统 Dock 与 LC 的多任务侧边 Dock 都在侧边，留意视觉重叠。
