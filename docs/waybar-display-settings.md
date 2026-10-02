# Waybar 显示器设置

Waybar 中间区的显示器图标位于取色器与电源模式之间。左键打开“显示器设置”，再次点击关闭；空闲时按 Esc 关闭。窗口是固定尺寸的普通 GTK3 浮动窗口，每个已连接输出一张紧凑表单，“启用”开关放在标题旁，方便单屏使用。

窗口沿用系统现有 GTK 深色粉色主题；栏上的图标复用相邻模块的颜色与 Powerline 分组。维护时以 GTK 主题和 `configs/config/waybar/style.css` 为视觉来源，保留现有系统风格。

## 使用

1. 选择启用的输出，再调整分辨率、刷新率、缩放、旋转、X/Y 位置与支持的 VRR。已关闭输出的参数仍可预先编辑。“自动并排”按当前 X 顺序排列启用输出。
2. 点击“应用”开始预览。显示正常时，在 **10 秒内**点击“保留更改”；不确认会自动还原。
3. 确认中点击“还原”或按 Esc 会还原。关闭窗口或再次点击入口也会请求还原；后端守护进程另有应用退出保护。
4. 空闲时“重置”重新读取当前配置。连接的显示器变化且有未应用修改时，草稿保留，应用被禁用；先重置再继续。

未修改时、所有屏幕关闭时或没有有效模式时，“应用”不可用。不可编辑的配置行显示来源路径并置灰。重叠、VRR 支持、配置版本及输出组合等校验由 Clavis 后端完成，错误与还原失败详情显示在状态行。

## 依赖与维护

入口源码为 `configs/config/waybar/scripts/display-settings.py`，安装后运行 `~/.config/waybar/scripts/display-settings.py`。依赖 Python 的 `gi`/GTK3、niri，以及 Clavis 的 `niri_config.py`、`niri_outputs.py`、`display_preview.py`。后端按以下顺序查找完整脚本组：

1. `$QUICKSHELL_CONFIG_PATH/scripts/system`
2. `${XDG_CONFIG_HOME:-~/.config}/quickshell/clavis/scripts/system`

找不到后端时显示错误并禁用应用；outputs 片段不是 `ready` 时，先在 Clavis 设置中连接片段。这里直接使用 Clavis 后端，不复制脚本，也不手动写 `outputs.kdl`。

前端只提交发生变化的可编辑输出；表单未涉及的 `layout`、`hotCorners`、`focusAtStartup` 等已有策略随配置原样保留。Waybar 模块定义、位置及样式分别在 `modules.jsonc`、`bar-common.jsonc`、`style.css`，同步时保留现有亮度分组及其他本地配置。

亮度滑条的 `cffi/brightness.c` 修复了持续拖动时反复重置 150 ms 定时器导致写入一直延后的问题：从首次事件起计时，期间合并最新目标，已有异步调用结束后继续处理待写目标。150 ms 是调度等待，不是 DDC 硬件完成时间。

CFFI 由 `cffi/build.sh` 构建，既有 `desktop-shell` 启动 Waybar 时会调用它。同步并重建后，需要通过现有 `desktop-shell` 管理流程完整重启 Waybar 进程以加载新库；本次实测 USR2 重载仍保留旧库映射。此功能不修改 shell 启停所有者。

## 验证记录与边界

在仓库根目录执行：

```sh
python3 tests/test_waybar_displays.py
python3 tests/test_waybar_displays_gtk.py
python3 tests/test_brightness_ddc.py
bash tests/test_brightness.sh
bash tests/test_desktop_shell.sh
bash tests/test_waybar_brightness_latency.sh
```

11 项纯逻辑、5 项真实 GTK 控件配合模拟后端的流程测试、19 项现有 DDC 测试，以及亮度 shell 和 desktop-shell 回归均已通过。GTK 测试需要图形会话；亮度延迟测试使用慢速假 helper，不写真实硬件，已确认原实现失败、修复后通过，持续拖动期间发出写入且最终目标不丢失。

安装后的真实窗口已验证浮动、单实例再次激活关闭及 Esc。真实 GTK/Clavis 集成已验证保留后恢复基线、10 秒超时、显式还原与确认中关闭；这些事务仅调整原本关闭的 eDP-1 的缩放，未改变已启用显示器的模式。结束状态为 DP-8 开启、`2560x1440@99.946`，eDP-1 关闭。

仍需用户在场验收：DP-8 刷新率/缩放的可见切换；启用 eDP-1、自动并排及关闭窗口所在输出后的窗口迁移；QuickShell 控制中心显示值的一致性。真实 DDC 硬件延迟尚未测量，模拟 helper 的结果不能代替该测量。
