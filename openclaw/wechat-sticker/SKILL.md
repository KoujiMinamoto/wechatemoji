---
name: wechat-sticker
description: Generate a full set of WeChat-style emoji stickers from a character description or reference image. Supports static PNG and animated GIF output with transparent backgrounds.
---

# WeChat Sticker Generator

Generate a complete set of WeChat-style emoji stickers from a text description or reference image. Supports static PNG (Gemini 3 Pro) and animated GIF (Sora 2), with automatic transparent background processing.

## Setup

- Needs env: `PPIO_API_KEY` (get one at [ppio.com](https://ppio.com))
- Needs: `jq`, `imagemagick`, `ffmpeg` (for GIF mode)

```bash
brew install jq imagemagick ffmpeg
export PPIO_API_KEY=your_key
```

## Usage

```
/sticker <character description or image path> [options]
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--count N` | Number of stickers to generate | 16 |
| `--emotions "e1,e2,..."` | Custom emotion list (comma-separated) | built-in 24 |
| `--gif` | Generate animated GIF stickers | static PNG |
| `--gif-only "e1,e2,..."` | Only animate specific emotions | - |

### Examples

```bash
# Text description → static PNG stickers
/sticker a round chubby orange cat with big eyes and short tail

# Specify count
/sticker a green little dinosaur --count 8

# Animated GIF
/sticker a white shiba inu --gif --count 8

# Based on reference image
/sticker /path/to/character.png cute sticker style

# Custom emotions
/sticker a white puppy --emotions "happy,sad,angry,eating,sleeping,cute"

# Mixed mode: mostly static, animate specific ones
/sticker a blue whale --gif-only "hi,happy,bye"
```

## How It Works

### Input Parsing

- If the argument contains a file path (starts with `/` or `~`, or ends with `.png/.jpg/.jpeg/.webp`), use **reference image mode** (image-edit API)
- Otherwise use **text description mode** (text-to-image API)

### Generation Flow

```
User input → Parse character + options
    │
    ├── Static ──▶ Gemini 3 Pro text-to-image ──▶ PNG
    │                                              │
    └── Animated ──▶ Static PNG first ──▶ Sora 2 img2video ──▶ ffmpeg ──▶ GIF
                                                   │
                                                   ▼
                                        ImageMagick remove white background
                                                   │
                                                   ▼
                                           Transparent sticker ✓
```

### Step-by-Step Execution

#### Step 1: Confirm Character Design

Analyze user input and extract core visual features. If ambiguous, ask:
- Character type (animal/person/object/abstract)
- Primary colors
- Distinctive features (big eyes, round face, short tail, etc.)

#### Step 2: Determine Emotion List

If `--emotions` is specified, use the custom list. Otherwise pick from the default 24:

```
1.  OK        - thumbs up or OK gesture, confident expression
2.  谢谢      - bowing or hands together in gratitude
3.  早安      - stretching and yawning, sun beside
4.  晚安      - hugging pillow, drowsy, moon and stars
5.  嗨        - energetically waving hello
6.  呵呵      - awkward polite smile
7.  爱你      - making heart gesture, floating hearts
8.  什么      - confused head tilt, question marks
9.  震惊      - jaw dropping, exclamation marks
10. 拜托      - palms pressed together pleading
11. 加油      - fist pump, full of energy
12. 鼓掌      - clapping happily, musical notes
13. 紧张      - sweating and trembling
14. 累了      - collapsed on the ground
15. 生气      - steam from head, stomping
16. 抱歉      - bowing in apology, sweat drops
17. 不行      - arms crossed in X, shaking head
18. 了解      - nodding, notebook appears
19. 对对对    - nodding vigorously, strongly agreeing
20. 没问题    - confident thumbs up
21. 哭了      - crying with tears gushing
22. 开心      - laughing and bouncing joyfully
23. 吃饭      - eating from a bowl eagerly
24. 再见      - waving goodbye reluctantly
```

#### Step 3: Build Prompts and Call API

**Check environment:** Confirm `PPIO_API_KEY` is set.

**Text mode prompt template:**
```
A cute kawaii chibi sticker of [character description in English], [emotion/action in English],
with bold Chinese text "[label]" as speech bubble or floating text.
Style: chibi cartoon, simple clean white background, thick black outline, vibrant saturated colors,
WeChat/LINE sticker style, exaggerated cute expression, minimal background details, round and soft shapes.
The character should be centered, occupying most of the frame. The Chinese text should be clearly readable.
```

**Reference image mode prompt template:**
```
Transform this character into a cute kawaii chibi sticker. The character is [emotion/action in English],
with bold Chinese text "[label]" floating nearby.
Keep the same character design and color palette. Style: chibi cartoon, simple clean white background,
thick black outline, WeChat sticker style, exaggerated cute expression.
```

Translate character descriptions to English for best generation quality. Keep Chinese label text as-is.

#### Step 4: Execute Generation

Use the scripts in this skill's `scripts/` directory.

**Static generation:**
```bash
bash scripts/generate_stickers.sh text2img "<prompt>" "<output_dir>" "<filename>"
bash scripts/generate_stickers.sh edit "<prompt>" "<output_dir>" "<filename>" "<image_path>"
```

**Concurrency:** Max 5 parallel background tasks per batch. Report progress after each batch.

#### Step 5: Remove White Background

**Mandatory** — run after image generation to make backgrounds transparent:

```bash
# Batch process entire directory
bash scripts/remove_bg.sh "<output_dir>"

# Or single file
bash scripts/remove_bg.sh "<output_dir>/01_OK.png"
```

Uses ImageMagick floodfill from 4 corners with 20% fuzz tolerance.

#### Step 6: Save and Display Results

- Save to `output/stickers/<pack-name>/` directory
- Filename format: `{number:02d}_{label}.png` (e.g., `01_OK.png`)
- Display each generated image using Read tool
- Output summary: total count, save path, time elapsed

### Animated GIF Mode (`--gif`)

When `--gif` is specified, use Sora 2 API for animation.

**Flow (recommended path):**
1. Generate static PNG first with Gemini 3 Pro (user preview)
2. Animate with Sora 2 img2video API
3. Convert mp4 → GIF with ffmpeg

**Animation prompt template:**
```
Animate this cute sticker character. The character [animation action in English].
Short seamless loop animation, smooth motion, keep the cute chibi style,
white background stays clean, character stays centered.
No camera movement, no background changes.
```

**Animation actions per emotion:**

| Emotion | Animation |
|---------|-----------|
| OK | gives a thumbs up with a confident nod |
| 谢谢 | bows forward gently in gratitude |
| 早安 | stretches arms wide and yawns, sun rises beside |
| 晚安 | slowly nods off to sleep, eyes closing gradually |
| 嗨 | waves hand energetically side to side |
| 呵呵 | awkward smile with a small sweat drop appearing |
| 爱你 | makes a heart gesture, floating hearts pop up around |
| 什么 | tilts head in confusion, question marks bounce around |
| 震惊 | jaw drops open dramatically, exclamation marks appear |
| 拜托 | presses palms together pleadingly, bouncing slightly |
| 加油 | pumps fist in the air enthusiastically |
| 鼓掌 | claps hands rapidly with musical notes floating |
| 紧张 | trembles nervously with sweat drops flying off |
| 累了 | slowly melts and slumps down to the ground |
| 生气 | stomps feet angrily with steam puffing from head |
| 抱歉 | bows deeply in apology, sweat drops falling |
| 不行 | shakes head vigorously and waves hands in X gesture |
| 了解 | nods firmly with a small notepad appearing |
| 对对对 | nods head rapidly and enthusiastically |
| 没问题 | gives a confident OK sign with a wink |
| 哭了 | bursts into tears with teardrops splashing |
| 开心 | jumps up and down joyfully with sparkles |
| 吃饭 | munches food eagerly from a bowl, cheeks puffing |
| 再见 | waves goodbye slowly, turning away slightly |

**Animated generation:**
```bash
bash scripts/generate_animated_sticker.sh img2video "<animation prompt>" "<output_dir>" "<filename>" "<static_image_path>"
bash scripts/generate_animated_sticker.sh text2video "<animation prompt>" "<output_dir>" "<filename>"
```

**GIF concurrency:** Max 3 async tasks at once. Poll every 10s. Timeout 10 min per task.

### `--gif-only` Mode

Only animate specified emotions, keep the rest as static PNG:
- Listed emotions → generate GIF (animation flow)
- All others → generate static PNG (normal flow)
- Saves time and API cost in mixed usage

## Error Handling

- API error: show error, skip that emotion, continue with the rest
- Download failure: retry once, skip if still failing
- API key not set: prompt user to run `export PPIO_API_KEY=your_key`
- GIF-specific:
  - Sora 2 timeout: output task_id for manual query later
  - ffmpeg not installed: prompt `brew install ffmpeg`
  - Video to GIF failure: keep mp4 source file, tell user to convert manually

## Output

Stickers are saved to `output/stickers/<pack-name>/`:

```
output/stickers/orange-cat/
├── 01_OK.png
├── 02_谢谢.png
├── ...
├── 01_OK.gif      (if --gif)
└── ...
```

All images have transparent backgrounds, ready for WeChat sticker upload.
