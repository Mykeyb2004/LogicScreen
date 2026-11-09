# LogicScreen

原生 macOS 多屏工作台：在可视化屏幕布局中选择目标，把其他屏幕的窗口收拢过来，再按需停用屏幕。

## 运行

需要 macOS 14+ 和 Xcode / Swift 工具链，无第三方依赖。

```sh
./script/build_and_run.sh
```

也可以使用 Codex 的 **Run** 按钮。脚本构建 SwiftPM 工程，在 `dist/LogicScreen.app` 生成本地开发应用并启动。

首次运行，点击 **前往授权**，在「系统设置 → 隐私与安全性 → 辅助功能」中开启 LogicScreen。应用会自动更新权限状态。开发版本采用 ad hoc 签名，重新编译后 macOS 可能要求重新授权；正式分发需要稳定的开发者签名和公证。

## 操作

- **屏幕工作台**：点击侧边栏或布局图选择屏幕；显示主副屏状态、逻辑尺寸和窗口数量。
- **窗口预览**：按应用查看其他屏幕上的窗口数量与需要处理的特殊窗口，不读取窗口标题。
- **收拢窗口**：迁移其他屏幕上的可访问窗口，尽量保留大小和相对位置，快捷键 **Shift + Command + G**。
- **设为主屏幕**：切换系统主屏和坐标原点，不隐含迁移窗口。
- **仅使用此屏幕**：先打开检查面板，展示来源、目标和窗口状态；执行时再次迁移和核验，通过后才停用。
- **停用此屏幕**：在「更多屏幕操作」中选择窗口接收屏幕，执行相同流程。
- **恢复布局**：重新连接屏幕、恢复原屏幕排列，并尝试恢复本次已记录的窗口位置。
- **识别屏幕**：短暂显示每块屏幕的编号和名称。

屏幕停用后默认有 15 秒确认时间，未确认则自动恢复。设置中可选 15 / 20 / 30 秒，并支持跟随系统、浅色和深色外观。全局恢复快捷键为 **Control + Option + Command + R**。至少保留一块活动屏幕。

关闭主窗口后，应用继续在菜单栏运行，可快速收拢窗口、恢复布局或重新打开工作台。正常退出时会先尝试恢复本次记录的屏幕和窗口；若恢复未完成，会提示返回工作台或继续退出。

## 支持范围

- 使用逻辑点和 Quartz 全局坐标，支持屏幕在主屏左侧、上方和不同缩放比例的布局。
- 通过 Accessibility API 管理其他应用的窗口，不需要截取屏幕内容。
- Finder 的桌面元素和放在所有屏幕之外的后台辅助窗口不作为待迁移窗口。
- 全屏、最小化、不可移动窗口会跳过普通「收拢」操作；如果它们位于待停用屏幕，会阻止屏幕停用。
- 其他 Spaces、Stage Manager、应用自定义窗口，以及应用在核验后瞬间新建窗口的行为，尚不能保证完整覆盖。
- 屏幕停用使用运行时探测的非公开 `CGSConfigureDisplayEnabled` 接口，属于实验功能；接口存在不代表设备一定支持断开和重新连接。
- 屏幕停用表示从活动桌面布局中移除，不保证硬件断电。没有使用 DDC 物理关机。
- 屏幕配置使用 `CGConfigureOption.forAppOnly`，不写入永久显示配置。正常退出前应用尝试恢复窗口；强制退出或崩溃时依赖系统撤销屏幕配置，窗口原位恢复不保证。
- 尚未签名公证为可分发产品，不以 Mac App Store 为当前分发路线。

## 验证与调试

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache" swift test --disable-sandbox \
  --cache-path .build/cache --config-path .build/config --security-path .build/security
./script/build_and_run.sh --verify
./script/build_and_run.sh --telemetry
agent-desktop snapshot --app LogicScreen -i --compact
```

`LogicScreenProbe` 是独立诊断工具，默认 `--diagnose` 仅读取屏幕和权限状态。需要在真实桌面会话、具有对应权限的终端中运行。`--exercise-main` 和 `--exercise-display ID` 会实际调整屏幕，不属于默认诊断。

`LogicScreenProbe --inventory` 仅读取窗口清单，输出每块屏幕可移动和受限窗口的数量。

实际设备验证记录见 [docs/validation.md](docs/validation.md)。

`--exercise-display ID` 仅接受非主屏，执行：迁移并核验窗口 → 停用 → 恢复连接和排列 → 还原已迁移窗口。失败会请求恢复。可通过 `./script/build_and_run.sh --fixture` 启动专用测试窗口，再运行 `LogicScreenProbe --exercise-windows PID` 验证专用窗口的迁移和还原；该命令只接受 LogicScreen 的进程。

## 代码结构

- `LogicScreenCore`：屏幕模型、窗口几何、停用保护和操作顺序。
- `LogicScreenPlatform`：CoreGraphics 屏幕配置与 Accessibility 窗口管理。
- `LogicScreen`：SwiftUI 主窗口、菜单栏、应用状态、屏幕识别和全局恢复快捷键。
- `LogicScreenProbe`：独立的设备与集成验证入口。

设计依据：[Apple 窗口辅助功能接口](https://developer.apple.com/documentation/applicationservices/1460434-axuielementsetattributevalue)、[Apple 屏幕坐标配置](https://developer.apple.com/documentation/coregraphics/cgconfiguredisplayorigin(_:_:_:_:))、[displayplacer 已知限制](https://github.com/jakehilborn/displayplacer)、[BetterDisplay 连接管理行为](https://betterdisplay.pro/guide/interface-reference/app-menu/device-menu/header-and-connection)。
