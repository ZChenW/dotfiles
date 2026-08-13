#!/usr/bin/env bash

# 2小时锁屏，3小时熄屏，4小时休眠
swayidle -w \
    timeout 7200 'swaylock -f' \
    timeout 10800 'niri msg action power-off-monitors' \
    resume      'niri msg action power-on-monitors' \
    timeout 14400 'systemctl suspend'
