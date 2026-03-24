#!/usr/bin/env bash
# 动画表情包生成脚本（基于 Sora 2）
# 用法:
#   generate_animated_sticker.sh text2video "<prompt>" "<output_dir>" "<filename>"
#   generate_animated_sticker.sh img2video "<prompt>" "<output_dir>" "<filename>" "<image_path>"
#
# 流程: 提交异步任务 → 轮询结果 → 下载视频 → 转换为 GIF
# 环境变量: PPIO_API_KEY (必需)

set -euo pipefail

MODE="$1"         # text2video 或 img2video
PROMPT="$2"        # 生成提示词
OUTPUT_DIR="$3"    # 输出目录
FILENAME="$4"      # 输出文件名（不含扩展名）
IMAGE_PATH="${5:-}" # 参考图片路径（仅 img2video 模式）

POLL_INTERVAL=10   # 轮询间隔（秒）
MAX_WAIT=600       # 最大等待时间（秒）

# ── 检查依赖 ──
if [[ -z "${PPIO_API_KEY:-}" ]]; then
    echo "ERROR: PPIO_API_KEY 环境变量未设置" >&2
    exit 1
fi

if ! command -v ffmpeg &>/dev/null; then
    echo "ERROR: 需要安装 ffmpeg 用于视频转 GIF (brew install ffmpeg)" >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

# ── Step 1: 提交异步任务 ──
if [[ "$MODE" == "text2video" ]]; then
    API_URL="https://api.ppio.com/v3/async/sora-2-text2video"
    BODY=$(jq -n \
        --arg prompt "$PROMPT" \
        '{
            prompt: $prompt,
            size: "720*1280",
            duration: 4,
            professional: false
        }')

elif [[ "$MODE" == "img2video" ]]; then
    API_URL="https://api.ppio.com/v3/async/sora-2-img2video"

    if [[ -z "$IMAGE_PATH" ]]; then
        echo "ERROR: img2video 模式需要提供图片路径" >&2
        exit 1
    fi

    # 图片转 base64，写入临时文件避免参数过长
    TMPFILE=$(mktemp)
    trap "rm -f $TMPFILE" EXIT
    base64 -i "$IMAGE_PATH" | tr -d '\n' > "$TMPFILE"

    BODY=$(jq -n \
        --arg prompt "$PROMPT" \
        --rawfile img "$TMPFILE" \
        '{
            prompt: $prompt,
            image: ($img | rtrimstr("\n")),
            resolution: "720p",
            duration: 4,
            professional: false
        }')
else
    echo "ERROR: 未知模式 '$MODE'，请使用 text2video 或 img2video" >&2
    exit 1
fi

echo "SUBMIT: 提交 $MODE 任务..."

# 将 body 写入临时文件，避免命令行参数过长
BODY_FILE=$(mktemp)
echo "$BODY" > "$BODY_FILE"

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$API_URL" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $PPIO_API_KEY" \
    -d @"$BODY_FILE" \
    --max-time 60)

rm -f "$BODY_FILE"

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" -ne 200 ]]; then
    echo "ERROR: 提交任务失败 HTTP $HTTP_CODE" >&2
    echo "$RESPONSE_BODY" >&2
    exit 1
fi

TASK_ID=$(echo "$RESPONSE_BODY" | jq -r '.task_id // empty')

if [[ -z "$TASK_ID" ]]; then
    echo "ERROR: 未获取到 task_id" >&2
    echo "$RESPONSE_BODY" >&2
    exit 1
fi

echo "TASK_ID: $TASK_ID"

# ── Step 2: 轮询任务结果 ──
ELAPSED=0

while [[ $ELAPSED -lt $MAX_WAIT ]]; do
    sleep $POLL_INTERVAL
    ELAPSED=$((ELAPSED + POLL_INTERVAL))

    POLL_RESPONSE=$(curl -s -X GET "https://api.ppio.com/v3/async/task-result?task_id=$TASK_ID" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $PPIO_API_KEY" \
        --max-time 15)

    STATUS=$(echo "$POLL_RESPONSE" | jq -r '.task.status // empty')
    PROGRESS=$(echo "$POLL_RESPONSE" | jq -r '.task.progress_percent // 0')
    ETA=$(echo "$POLL_RESPONSE" | jq -r '.task.eta // "?"')

    case "$STATUS" in
        TASK_STATUS_SUCCEED)
            echo "DONE: 任务完成！"

            # 提取视频 URL
            VIDEO_URL=$(echo "$POLL_RESPONSE" | jq -r '.videos[0].video_url // empty')

            if [[ -z "$VIDEO_URL" ]]; then
                echo "ERROR: 任务成功但未找到视频 URL" >&2
                echo "$POLL_RESPONSE" >&2
                exit 1
            fi

            # 下载视频
            VIDEO_FILE="$OUTPUT_DIR/${FILENAME}.mp4"
            curl -s -o "$VIDEO_FILE" "$VIDEO_URL" --max-time 120

            if [[ ! -f "$VIDEO_FILE" || ! -s "$VIDEO_FILE" ]]; then
                echo "ERROR: 视频下载失败" >&2
                exit 1
            fi

            echo "DOWNLOAD: $VIDEO_FILE"

            # 转换为 GIF（优化大小，适合表情包）
            GIF_FILE="$OUTPUT_DIR/${FILENAME}.gif"
            ffmpeg -y -i "$VIDEO_FILE" \
                -vf "fps=12,scale=240:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=128:stats_mode=diff[p];[s1][p]paletteuse=dither=bayer:bayer_scale=3" \
                -loop 0 \
                "$GIF_FILE" 2>/dev/null

            if [[ -f "$GIF_FILE" && -s "$GIF_FILE" ]]; then
                GIF_SIZE=$(du -h "$GIF_FILE" | cut -f1)
                echo "OK: $GIF_FILE ($GIF_SIZE)"
                # 清理 mp4 源文件
                rm -f "$VIDEO_FILE"
            else
                echo "ERROR: GIF 转换失败，保留视频文件 $VIDEO_FILE" >&2
                exit 1
            fi

            exit 0
            ;;

        TASK_STATUS_FAILED)
            REASON=$(echo "$POLL_RESPONSE" | jq -r '.task.reason // "未知原因"')
            echo "ERROR: 任务失败 - $REASON" >&2
            exit 1
            ;;

        TASK_STATUS_QUEUED|TASK_STATUS_PROCESSING)
            echo "POLL: ${STATUS#TASK_STATUS_} | 进度: ${PROGRESS}% | ETA: ${ETA}s | 已等待: ${ELAPSED}s"
            ;;

        *)
            echo "POLL: 状态: $STATUS | 已等待: ${ELAPSED}s"
            ;;
    esac
done

echo "ERROR: 等待超时（${MAX_WAIT}s），task_id: $TASK_ID" >&2
echo "你可以稍后手动查询: curl -s 'https://api.ppio.com/v3/async/task-result?task_id=$TASK_ID' -H 'Authorization: Bearer \$PPIO_API_KEY'" >&2
exit 1
