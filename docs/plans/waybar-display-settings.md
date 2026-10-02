# 计划：Waybar 显示器调整器

交给实现者（Codex）的独立任务说明。读完本文件即可开工，不需要其他上下文。

## 1. 目标

在 Waybar 模式下提供一个显示器设置入口，功能对齐 QuickShell（Clavis）控制中心的
“显示配置”页：启用/关闭屏幕、分辨率、刷新率、缩放、旋转、位置、VRR，带
“预览 → 10 秒内确认保留，否则自动还原”的安全流程。

用户的日常用法是“只亮一块屏”（当前 `eDP-1` 关闭、`DP-8` 开启），所以
**启用开关是最重要的控件**，必须一眼可见、一步可达。

非目标：

- 不做 Clavis 那种可拖拽的屏幕排布画布，位置用 X/Y 数字输入加“自动并排”。
- 不编辑每屏的 `layout` / `hot-corners` / `focus-at-startup`，但**必须原样保留**这些已有设置（见 5.3）。
- 不新写 KDL 读写器，不直接改 `outputs.kdl`。
- 不改 `configs/local-bin/desktop-shell` 的启动/停止/切换路径。

## 2. 环境事实（已核实）

- 合成器：niri 26.04。Waybar 与 QuickShell 由 `desktop-shell` 二选一运行。
- 仓库：`~/Projects/dotfiles`，Waybar 配置源在 `configs/config/waybar/`，安装后位于
  `~/.config/waybar/`（普通文件，不是符号链接）。**先读仓库里的安装脚本确认同步方式**，
  改动以仓库为准，再同步到 `~/.config`。
- 仓库当前有未提交改动（`brightness.sh`、`tests/test_brightness_ddc.py`、
  `bar-common.jsonc`、`modules.jsonc`、`libniri_taskbar.so` 等），**不要还原或覆盖**。
- `AGENTS.md` 约束：不得同步/推送/提 PR 到 QuickShell 仓库；涉及 shell 启停的改动要过
  `bash tests/test_desktop_shell.sh`。本任务不应触碰这些路径。
- Clavis 检出：`~/Projects/clavis-personal`，通过 `~/.config/quickshell/clavis` 符号链接访问。
  后端脚本在 `scripts/system/`：`niri_config.py`、`niri_outputs.py`、`display_preview.py`。
  注意 `~/.local/share/quickshell/clavis/scripts/system/` 里**没有** `display_preview.py`，不要用那个路径。
- niri 主配置 `~/.config/niri/config.kdl` 已 `include optional=true "clavis/outputs.kdl"`，
  `niri_config.py status` 返回 `fragments.outputs.state == "ready"`。
- Python 侧 `gi`（Gtk 3.24、GtkLayerShell 0.1）可用。
- 现有 Waybar 文案是中文，图标用 Nerd Font，自定义模块样式见 `style.css` 中
  `#custom-colorpicker` 一组选择器。

## 3. 方案概述

1. Waybar 新增 `custom/displays` 图标模块，点击运行
   `~/.config/waybar/scripts/display-settings.py`。
2. 该脚本是单实例 GTK3 应用（`Gtk.Application`，固定 application id，例如
   `io.github.zchenw.WaybarDisplays`）。再次点击图标 = 关闭已打开的窗口。
3. 窗口是**普通 xdg toplevel、不可调整大小**（不是 layer-shell）。原因：关闭窗口所在的
   输出时，layer surface 会被合成器关掉，进程退出会触发后端自动还原；普通窗口会被 niri
   挪到剩余的输出上。
   - 待验证：niri 是否自动把固定尺寸窗口设为浮动。若不是，在 niri 配置的 window-rule
     里按 app-id 加 `open-floating true`（放到仓库里对应的 niri 配置源文件）。
4. 所有读写经由 Clavis 后端脚本，以子进程方式调用（参数是一个 JSON 字符串，stdout 是 JSON）。

## 4. 后端接口

脚本目录解析顺序：`$QUICKSHELL_CONFIG_PATH/scripts/system` →
`${XDG_CONFIG_HOME:-~/.config}/quickshell/clavis/scripts/system`。
找不到 `display_preview.py` 时窗口只显示错误说明，禁用“应用”。

### 4.1 读取已保存配置

```
python3 niri_config.py '{"operation":"status"}'
```

用到的字段：

- `main`：主配置路径
- `revision`：配置图的版本哈希，应用时原样传回
- `fragments.outputs.state`：必须是 `"ready"`，否则提示“请先在 Clavis 设置里连接 outputs 片段”并禁用应用
- `outputs`：数组，元素形如
  `{identifier, source, managed, editable, settings}`，`settings` 可含
  `enabled`(仅为 false 时出现)、`mode`("2560x1440@99.946")、`scale`、`transform`、
  `position`({x,y})、`vrr`("on"|"on-demand")、`focusAtStartup`、`hotCorners`、以及 layout 相关键

### 4.2 读取实时状态

```
niri msg -j outputs
```

返回 `{连接器名: {name, make, model, serial, modes:[{width,height,refresh_rate,is_preferred}],
current_mode(索引或 null), vrr_supported, vrr_enabled, logical:{x,y,width,height,scale,transform} 或 null}}`。
`refresh_rate` 单位是 mHz。`logical.transform` 取值 `Normal/90/180/270/Flipped/Flipped90/Flipped180/Flipped270`。
实现前先实际跑一次确认字段名。

### 4.3 预览事务

```
python3 display_preview.py '<request json>'
```

| operation | 请求 | 响应 |
|---|---|---|
| `start` | `{operation, revision, main, outputs:[patch…]}` | `{schemaVersion:1, token}`，立即返回，后台守护进程接管 |
| `status` | `{operation, token}` | `{phase, remaining?, error?, restoreErrors?}` |
| `keep` / `revert` | `{operation, token}` | `{schemaVersion:1}` |
| `cleanup` | `{operation, token}` | 仅在 phase 为 `kept`/`reverted` 后调用 |

patch 形如：

```json
{"identifier": "DP-8",
 "identity": {"name": "DP-8", "make": "...", "model": "...", "serial": "..."},
 "settings": {"enabled": true, "mode": "2560x1440@99.946", "scale": 1,
              "transform": "normal", "position": {"x": 0, "y": 0}, "vrr": "off"},
 "delete": false}
```

phase 流转：`validating → applying → confirming(remaining 秒) → saving → kept`，
任何失败/超时/还原都落到 `reverted`（带 `error`，可能带 `restoreErrors`）。

关键行为（来自 `display_preview.py`，不要改它）：

- 守护进程以**调用 `start` 的进程的父进程**（即本 GTK 应用）是否存活作为心跳，
  应用退出即自动还原。所以预览期间进程必须活着。
- 确认窗口 10 秒；全局 25 秒 / 45 秒硬超时。
- 后端自行校验：至少一块屏启用、逻辑矩形不重叠、模式存在、VRR 受支持、revision 未变、
  连接的显示器组合未变。错误以 `reverted` + `error` 返回。
- 同时只允许一个预览（文件锁），冲突时 `start` 直接报错（退出码非 0，stdout 仍是带 `error` 的 JSON）。
- 非 0 退出码时也要解析 stdout 的 `error` 字段展示。

## 5. 数据模型（对齐 `Common/functions/DisplayConfiguration.js` 的 `rows()`）

### 5.1 行的构建

对每个已连接输出：

- `identity(o)` = `make model serial` 以空格连接，缺失项记为 `Unknown`。
- 匹配已保存配置：`identifier` 忽略大小写等于连接器名或 identity。
- `identifier`：有匹配配置就用它的；否则 serial 已知且 identity 在已连接输出中唯一时用
  identity，其他情况用连接器名。
- `editable`：无匹配配置，或匹配配置 `managed && editable`；且匹配到的配置块不超过 1 个。
  不可编辑的行整栏置灰，并显示来源文件路径。

### 5.2 默认值填充

以已保存 `settings` 的深拷贝为底，缺什么补什么：

- `enabled`：`current_mode is not None`
- `mode`：当前模式；没有则首个 `is_preferred`，再没有取第一个。格式 `"{w}x{h}@{mHz/1000:.3f}"`
- `scale`：`logical.scale` 或 1
- `transform`：`Normal→normal`，`Flipped→flipped`，`Flipped90→flipped-90`，
  `Flipped180→flipped-180`，`Flipped270→flipped-270`，`90/180/270` 原样
- `position`：启用时取 `logical.x/y`，否则 `{x:0,y:0}`
- `vrr`：`"off"`

### 5.3 保留未知键

`settings` 里表单不涉及的键（`focusAtStartup`、`hotCorners`、`gaps`、
`default-column-width`、`preset-column-widths`、`always-center-single-column`）必须随 patch 原样带回，
否则后端重写该输出块时会把它们删掉。

### 5.4 生成 patch

只提交相对基线有变化的、可编辑的行。比较用规范化 JSON（键排序）。没有变化时“应用”禁用。

## 6. 界面

窗口标题“显示器设置”。从上到下：

1. 每个已连接输出一个卡片，标题 `型号 · 连接器`（型号未知时只显示连接器）：
   - 启用：`Gtk.Switch`
   - 分辨率：下拉，去重后的 `宽x高`，按面积降序
   - 刷新率：下拉，随分辨率联动，显示 `99.946 Hz`，降序；切换分辨率时尽量保留最接近的刷新率
   - 缩放：`Gtk.SpinButton`，0.5–3.0，步进 0.05，两位小数
   - 旋转：下拉，`正常 / 90° / 180° / 270° / 翻转 / 翻转 90° / 翻转 180° / 翻转 270°`
   - VRR：下拉 `关闭 / 开启 / 按需`，仅 `vrr_supported` 时显示
   - 位置：X、Y 两个整数 SpinButton
   - 关闭的输出：除开关外其余控件保持可编辑（方便先调好再开），视觉上弱化
2. “自动并排”按钮：把启用的输出按当前 X 顺序从 x=0 起左右紧贴排列，y=0，
   宽度用逻辑尺寸（见下）。
3. 状态行：错误/提示文字，可换行。
4. 按钮行：
   - 空闲：`重置`（回到基线）、`应用`
   - 确认中：`还原`、`保留更改（N）`，N 为剩余秒数
   - 应用中/保存中：按钮禁用并显示“正在应用…/正在保存…”

逻辑尺寸：`ceil(宽/scale)`、`ceil(高/scale)`，`scale` 先取 `round(scale*120)/120`；
旋转为 90/270 及其翻转形式时宽高互换。

前端只做两项即时校验并在状态行提示、禁用“应用”：没有任何启用的输出；模式为空。
重叠等其余校验交给后端。

键盘：Esc 关闭窗口；确认中按 Esc = 还原。

## 7. 状态机

```
idle ──应用──> start ──token──> 每 400ms 轮询 status
  validating/applying → 显示“正在应用…”
  confirming          → 显示倒计时，可 保留 / 还原
  saving              → 显示“正在保存…”
  kept                → cleanup → 重新加载(4.1+4.2) → 提示“已保存”
  reverted            → cleanup → 重新加载 → 提示（见下）
```

- `reverted` 且 `error == "Changes reverted"` 且无 `restoreErrors`：提示“已还原”。
- `error == "Display preview timed out"`：提示“超时未确认，已自动还原”。
- 其他：原样显示 `error`，`restoreErrors` 逐行追加。
- 预览进行中关闭窗口：先发 `revert`，再退出（即使发送失败，守护进程也会因父进程退出而还原）。
- 空闲且无未应用修改时，监听输出变化并自动重新加载：最简单是每 2 秒比较一次
  `niri msg -j outputs` 的连接器+identity 组合；有未应用修改时不覆盖，只提示“显示器已变化，请重置后再应用”。
- 子进程调用不要阻塞 GTK 主循环太久：`status` 轮询和 `start` 用
  `Gio.Subprocess` 异步或短超时同步均可，但同一时刻只允许一个后端调用在跑。

## 8. Waybar 接入

- `configs/config/waybar/modules.jsonc` 新增：

  ```jsonc
  "custom/displays": {
    "format": "󰍹",
    "tooltip-format": "左键：显示器设置",
    "on-click": "~/.config/waybar/scripts/display-settings.py"
  }
  ```

- `configs/config/waybar/bar-common.jsonc` 的 `modules-center` 中，放在
  `"custom/colorpicker"` 与 `"power-profiles-daemon"` 之间。
- `configs/config/waybar/style.css`：把 `#custom-displays` 加进 `#custom-colorpicker` 所在的选择器组。
- 注意 Waybar include 是“先写入者生效”，`group/ddcutil` 相关文件不要动。
- 脚本加可执行位，shebang `#!/usr/bin/env python3`。

## 9. 代码组织

`configs/config/waybar/scripts/display-settings.py`，单文件，分两层：

- 纯逻辑（不 import gi）：identity、行构建、默认值、模式分组、逻辑尺寸、自动并排、
  规范化比较、patch 生成、状态消息映射。函数接收/返回普通 dict，便于测试。
- GTK 层：`gi` 的 import 放在 `main()` 内或 `if __name__ == '__main__'` 路径上，
  保证测试可以 import 纯逻辑而不需要显示环境。

风格跟仓库现有脚本一致，注释只写“为什么”。

## 10. 测试

新增 `tests/test_waybar_displays.py`（unittest，参照 `tests/test_brightness_ddc.py` 的写法，
用 importlib 按路径加载脚本）。至少覆盖：

1. 行构建：已保存配置按连接器名和按 identity 都能匹配；无配置时 identifier 的选择规则。
2. 默认值：关闭的输出（`current_mode: null`、`logical: null`）得到 `enabled=false`、首选模式、
   `position {0,0}`。
3. 未知键保留：`hotCorners` / `focusAtStartup` 等在 patch 中原样存在。
4. patch 只包含改动的行；无改动时为空。
5. 模式字符串格式 `2560x1440@99.946`，以及分辨率→刷新率分组和排序。
6. 逻辑尺寸在 scale=1.4、旋转 90 时正确；自动并排结果不重叠。
7. 后端失败响应（非 0 退出 + `{"error":…}`）被转成可显示的消息。

用真实数据做夹具：当前机器的 `niri msg -j outputs` 输出和 `niri_config.py status` 的 `outputs` 字段。

## 11. 手动验收（在真实会话里做，需要用户在场）

1. 点击图标弹出窗口，浮动、不占平铺列；再点一次关闭；Esc 关闭。
2. 仅改 DP-8 刷新率 → 应用 → 倒计时内点“保留” → `~/.config/niri/clavis/outputs.kdl` 更新，
   重新打开窗口显示新值。
3. 改缩放 → 应用 → 不操作 → 10 秒后自动还原，提示“超时未确认，已自动还原”。
4. 应用后点“还原” → 立即还原。
5. 打开 eDP-1 并“自动并排” → 应用 → 保留；再关闭 eDP-1 → 应用 → 保留
   （回到用户习惯的单屏状态）。期间窗口不应消失。
6. 把两块屏都关掉 → “应用”被禁用并有提示。
7. 预览确认中直接关窗口 → 配置还原。
8. 切到 QuickShell，控制中心“显示配置”页显示的值与刚才保存的一致。
9. `outputs.kdl` 中 eDP-1 原有的其他子节点没有丢失。

**结束时必须恢复为：DP-8 `2560x1440@99.946` 开启、eDP-1 关闭。**

## 12. 完成标准

- `python3 tests/test_waybar_displays.py` 通过。
- 现有测试不回退：`python3 tests/test_brightness_ddc.py`、`bash tests/test_brightness.sh`、
  `bash tests/test_desktop_shell.sh`。
- 仓库源文件与 `~/.config/waybar` 已同步，Waybar 重载后图标出现且样式与相邻模块一致。
- 第 11 节逐项通过，或明确列出哪项因环境限制没做。
- 不提交、不推送，除非用户另行要求。

## 13. 已定的取舍（用户未否决，按此实现；如需改动先问用户）

1. 直接依赖 Clavis 检出里的后端脚本，不在 dotfiles 里复制一份。
2. 图标放中间区 `colorpicker` 与 `power-profiles-daemon` 之间。
3. 位置用数字输入加“自动并排”，不做拖拽画布。
