#!/usr/bin/env bash
# 微信表情包生成脚本
# 用法:
#   generate_stickers.sh text2img "<prompt>" "<output_dir>" "<filename>"
#   generate_stickers.sh edit "<prompt>" "<output_dir>" "<filename>" "<image_path>"

set -euo pipefail

MODE="$1"        # text2img 或 edit
PROMPT="$2"       # 生成提示词
OUTPUT_DIR="$3"   # 输出目录
FILENAME="$4"     # 输出文件名（不含扩展名）
IMAGE_PATH="${5:-}" # 参考图片路径（仅 edit 模式）

# 检查 API Key
if [[ -z "${PPIO_API_KEY:-}" ]]; then
    echo "ERROR: PPIO_API_KEY 环境变量未设置" >&2
    exit 1
fi

# 确保输出目录存在
mkdir -p "$OUTPUT_DIR"

# 构建请求
if [[ "$MODE" == "text2img" ]]; then
    API_URL="https://api.ppio.com/v3/gemini-3-pro-image-text-to-image"
    BODY=$(jq -n \
        --arg prompt "$PROMPT" \
        '{
            prompt: $prompt,
            size: "1K",
            aspect_ratio: "1:1",
            output_format: "image/png"
        }')
elif [[ "$MODE" == "edit" ]]; then
    API_URL="https://api.ppio.com/v3/gemini-3-pro-image-edit"

    if [[ -z "$IMAGE_PATH" ]]; then
        echo "ERROR: edit 模式需要提供参考图片路径" >&2
        exit 1
    fi

    # 将图片转为 base64，写入临时文件避免参数过长
    TMPFILE=$(mktemp)
    trap "rm -f $TMPFILE" EXIT
    base64 -i "$IMAGE_PATH" | tr -d '\n' > "$TMPFILE"

    BODY=$(jq -n \
        --arg prompt "$PROMPT" \
        --rawfile img "$TMPFILE" \
        '{
            prompt: $prompt,
            image_base64s: [($img | rtrimstr("\n"))],
            size: "1K",
            aspect_ratio: "1:1"
        }')
else
    echo "ERROR: 未知模式 '$MODE'，请使用 text2img 或 edit" >&2
    exit 1
fi

# 调用 API
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$API_URL" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $PPIO_API_KEY" \
    -d "$BODY" \
    --max-time 120)

# 分离响应体和状态码
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" -ne 200 ]]; then
    echo "ERROR: API 返回 HTTP $HTTP_CODE" >&2
    echo "$RESPONSE_BODY" >&2
    exit 1
fi

# 提取图片 URL
IMAGE_URL=$(echo "$RESPONSE_BODY" | jq -r '.image_urls[0] // empty')

if [[ -z "$IMAGE_URL" ]]; then
    echo "ERROR: API 响应中未找到图片 URL" >&2
    echo "$RESPONSE_BODY" >&2
    exit 1
fi

# 下载图片
OUTPUT_FILE="$OUTPUT_DIR/${FILENAME}.png"
curl -s -o "$OUTPUT_FILE" "$IMAGE_URL" --max-time 60

if [[ -f "$OUTPUT_FILE" && -s "$OUTPUT_FILE" ]]; then
    echo "OK: $OUTPUT_FILE"
else
    echo "ERROR: 图片下载失败 $OUTPUT_FILE" >&2
    exit 1
fi
