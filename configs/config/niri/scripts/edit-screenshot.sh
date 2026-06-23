#!/usr/bin/env bash

# 声明一个变量，值是根据 wl-paste 输出的当前剪贴版的数据计算出的哈希值
CLIPNOW=$(wl-paste | sha1sum)

# 启动 niri 截图
niri msg action screenshot

# 循环，不断地打印当前剪贴板数据计算哈希值，和之前声明的变量里的数据进行
while [ "$(wl-paste | sha1sum)" = "$CLIPNOW" ]; do
	sleep .05
done

# 将新的剪贴板内容的数据传给 satty 打开
wl-paste | satty -f -
