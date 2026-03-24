#!/usr/bin/env bash
# 表情包去白背景脚本（ImageMagick floodfill 从四角填充透明）
# 用法:
#   remove_bg.sh <文件路径>          # 处理单个 PNG 或 GIF
#   remove_bg.sh <目录路径>          # 批量处理目录下所有 PNG 和 GIF
#   remove_bg.sh <目录路径> --fuzz 25  # 自定义 fuzz 容差（默认 20%）

set -euo pipefail

TARGET="$1"
FUZZ="${3:-20}"

if ! command -v magick &>/dev/null; then
    echo "ERROR: 需要安装 ImageMagick (brew install imagemagick)" >&2
    exit 1
fi

remove_bg_png() {
    local file="$1"
    local W H Wm Hm
    W=$(magick identify -format "%w" "$file")
    H=$(magick identify -format "%h" "$file")
    Wm=$((W-1))
    Hm=$((H-1))
    magick "$file" -alpha set -fuzz "${FUZZ}%" \
        -fill none -draw "color 0,0 floodfill" \
        -fill none -draw "color ${Wm},0 floodfill" \
        -fill none -draw "color 0,${Hm} floodfill" \
        -fill none -draw "color ${Wm},${Hm} floodfill" \
        "$file"
}

remove_bg_gif() {
    local file="$1"
    local TMPDIR
    TMPDIR=$(mktemp -d)

    # 拆帧
    magick "$file" -coalesce "$TMPDIR/frame_%04d.png"

    # 获取原始帧延迟
    local DELAY
    DELAY=$(magick identify -format "%T," "$file" | cut -d',' -f1)
    [ -z "$DELAY" ] && DELAY=8

    # 每帧去白
    for frame in "$TMPDIR"/frame_*.png; do
        remove_bg_png "$frame"
    done

    # 重组 GIF
    magick -delay "$DELAY" -loop 0 -dispose Background "$TMPDIR"/frame_*.png "$file"

    rm -rf "$TMPDIR"
}

process_file() {
    local file="$1"
    local ext="${file##*.}"
    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')

    case "$ext" in
        png)
            remove_bg_png "$file"
            echo "OK: $file"
            ;;
        gif)
            local FRAME_COUNT
            FRAME_COUNT=$(magick identify "$file" | wc -l | tr -d ' ')
            echo "处理 $file ($FRAME_COUNT 帧)..."
            remove_bg_gif "$file"
            echo "OK: $file"
            ;;
        *)
            echo "SKIP: $file (不支持的格式)"
            ;;
    esac
}

if [[ -d "$TARGET" ]]; then
    for f in "$TARGET"/*.png "$TARGET"/*.gif; do
        [[ -f "$f" ]] && process_file "$f"
    done
elif [[ -f "$TARGET" ]]; then
    process_file "$TARGET"
else
    echo "ERROR: $TARGET 不存在" >&2
    exit 1
fi
