from typing import Any
from kitty.boss import Boss
from kitty.window import Window

FOCUSED = "1.0"  # 聚焦时
UNFOCUSED = "0.6"  # 失焦时（更透明）


def on_focus_change(boss: Boss, window: Window, data: dict[str, Any]) -> None:
    # data 里有 focused: True/False 这个字段 :contentReference[oaicite:3]{index=3}
    opacity = FOCUSED if data.get("focused") else UNFOCUSED
    # set-background-opacity 会作用到该 OS window（同一个顶层窗口）里的所有 kitty windows :contentReference[oaicite:4]{index=4}
    boss.call_remote_control(window, ("set-background-opacity", opacity))
