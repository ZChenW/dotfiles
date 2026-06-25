#!/usr/bin/env python3
import cv2
import numpy as np
import sys
import os

def stitch_video(video_path, output_path):
    if not os.path.exists(video_path):
        return

    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        print("❌ 无法打开视频")
        return

    frames = []
    ret, prev_frame = cap.read()
    if not ret: return

    frames.append(prev_frame)
    anchor_frame = prev_frame.copy()

    # ==========================
    # 核心参数 (手动滚动优化)
    # ==========================
    MIN_SCROLL = 2
    MATCH_CONFIDENCE = 0.5

    # 忽略上下边缘 (防止浏览器地址栏/状态栏干扰)
    IGNORE_Y_TOP = 0.15
    IGNORE_Y_BOTTOM = 0.15
    IGNORE_X = 0.15

    h, w, _ = anchor_frame.shape

    # 有效特征区
    x1 = int(w * IGNORE_X)
    x2 = int(w * (1 - IGNORE_X))
    y1 = int(h * IGNORE_Y_TOP)
    template_h = int(h * 0.2)

    print(f"⚡ 正在分析 (梯度匹配模式)...")

    last_shift = 0
    SEARCH_WINDOW = 50

    while True:
        ret, curr_frame = cap.read()
        if not ret: break

        # 1. 梯度处理 (解决白底黑字问题)
        curr_gray = cv2.cvtColor(curr_frame, cv2.COLOR_BGR2GRAY)
        anchor_gray = cv2.cvtColor(anchor_frame, cv2.COLOR_BGR2GRAY)

        curr_grad = cv2.Sobel(curr_gray, cv2.CV_8U, 0, 1, ksize=3)
        anchor_grad = cv2.Sobel(anchor_gray, cv2.CV_8U, 0, 1, ksize=3)

        # 2. 提取模板
        template = curr_grad[y1 : y1 + template_h, x1:x2]
        roi = anchor_grad[y1:, x1:x2]

        # 3. 匹配
        res = cv2.matchTemplate(roi, template, cv2.TM_CCOEFF_NORMED)

        # 4. 惯性约束
        if last_shift > 0:
            mask = np.zeros_like(res)
            target_y = last_shift
            y_min = max(0, target_y - SEARCH_WINDOW)
            y_max = min(res.shape[0], target_y + SEARCH_WINDOW)
            mask[y_min:y_max, :] = 1
            res = np.multiply(res, mask)

        min_val, max_val, min_loc, max_loc = cv2.minMaxLoc(res)
        shift = max_loc[1]

        # 5. 判定
        if max_val > MATCH_CONFIDENCE and shift > MIN_SCROLL and shift < (roi.shape[0] - 5):
            new_content_start_y = h - shift
            if new_content_start_y < h:
                new_part = curr_frame[new_content_start_y:, :, :]
                frames.append(new_part)
                anchor_frame = curr_frame.copy()

                if last_shift == 0: last_shift = shift
                else: last_shift = int(last_shift * 0.6 + shift * 0.4)

    cap.release()

    if len(frames) > 1:
        try:
            full_image = np.vstack(frames)
            cv2.imwrite(output_path, full_image, [cv2.IMWRITE_PNG_COMPRESSION, 3])
            print(f"🎉 处理完成")
        except Exception as e:
            print(f"❌ 保存失败: {e}")
    else:
        print("⚠️ 未检测到滚动，保存第一帧")
        cv2.imwrite(output_path, frames[0])

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python stitch.py <input_video> <output_image>")
    else:
        stitch_video(sys.argv[1], sys.argv[2])
