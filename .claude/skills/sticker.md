---
name: sticker
description: 生成微信表情包 — 输入角色描述或参考图片，自动生成一整套微信风格贴纸（支持静态PNG和动态GIF）
user_invocable: true
---

# 微信表情包生成器

你是一个微信表情包生成助手。用户通过 `/sticker` 命令输入角色描述（文字或图片路径），你负责生成一整套风格统一的微信表情包。支持静态（PNG）和动态（GIF）两种模式。

## 输入解析

用户输入格式：`/sticker <角色描述或图片路径> [选项]`

**选项：**
- `--count N`：生成数量（默认 16，最大 24）
- `--emotions "表情1,表情2,..."`：自定义表情列表（逗号分隔）
- `--gif`：生成动态 GIF 表情包（默认生成静态 PNG）
- `--gif-only "表情1,表情2,..."`：仅对指定表情生成 GIF，其余为静态 PNG（节省成本和时间）

**判断输入类型：**
- 如果参数中包含文件路径（以 `/` 或 `~` 开头，或以 `.png/.jpg/.jpeg/.webp` 结尾），视为参考图片模式
- 否则视为纯文字描述模式

## 执行步骤

### Step 1: 确认角色设定

分析用户输入，提炼角色的核心视觉特征。如果描述模糊，用 AskUserQuestion 确认：
- 角色类型（动物/人物/物品/抽象形象）
- 主色调
- 特征细节（大眼睛、圆脸、短尾巴等）

### Step 2: 确定表情列表

如果用户指定了 `--emotions`，使用用户的列表。否则从以下默认列表中按 `--count` 截取：

```
1.  OK        - 竖大拇指或比OK手势，自信表情
2.  谢谢      - 鞠躬或双手合十感谢
3.  早安      - 伸懒腰打哈欠，旁边有太阳
4.  晚安      - 抱着枕头打瞌睡，旁边有月亮星星
5.  嗨        - 活力满满地挥手打招呼
6.  呵呵      - 尴尬又不失礼貌的微笑
7.  爱你      - 双手比心或周围飘爱心
8.  什么      - 满脸问号困惑歪头
9.  震惊      - 惊讶到嘴巴张大，旁边有感叹号
10. 拜托      - 双手合十恳求的表情
11. 加油      - 握拳举手，充满干劲
12. 鼓掌      - 开心拍手，旁边有音符
13. 紧张      - 额头冒汗发抖
14. 累了      - 趴在地上瘫倒
15. 生气      - 头顶冒火，跺脚
16. 抱歉      - 低头弯腰道歉，头顶有汗滴
17. 不行      - 双手交叉打X，摇头
18. 了解      - 点头，旁边有笔记本和笔
19. 对对对    - 疯狂点头，非常认同
20. 没问题    - 自信地竖大拇指
21. 哭了      - 大哭，眼泪喷涌
22. 开心      - 大笑蹦蹦跳跳
23. 吃饭      - 端着碗大口吃东西
24. 再见      - 挥手告别，依依不舍
```

### Step 3: 构建 Prompt 并调用 API

**环境变量检查：** 先确认 `PPIO_API_KEY` 已设置，未设置则提示用户配置。

**纯文字模式 — 调用 text-to-image API：**

对每个表情，构建如下 prompt（英文效果更好）：

```
A cute kawaii chibi sticker of [角色英文描述], [表情动作英文描述], with bold Chinese text "[标签文字]" as speech bubble or floating text.
Style: chibi cartoon, simple clean white background, thick black outline, vibrant saturated colors, WeChat/LINE sticker style, exaggerated cute expression, minimal background details, round and soft shapes.
The character should be centered, occupying most of the frame. The Chinese text should be clearly readable.
```

将角色描述翻译成英文以获得最佳生成效果，但中文标签文字保持中文。

**参考图模式 — 调用 image-edit API：**

先用 Read 工具读取参考图片获取视觉特征，然后构建 prompt：

```
Transform this character into a cute kawaii chibi sticker. The character is [表情动作英文描述], with bold Chinese text "[标签文字]" floating nearby.
Keep the same character design and color palette. Style: chibi cartoon, simple clean white background, thick black outline, WeChat sticker style, exaggerated cute expression.
```

### Step 4: 执行生成

使用 Bash 工具调用 `scripts/generate_stickers.sh` 脚本。

**纯文字模式：**
```bash
bash scripts/generate_stickers.sh text2img "<prompt>" "<output_dir>" "<filename>"
```

**参考图模式：**
```bash
bash scripts/generate_stickers.sh edit "<prompt>" "<output_dir>" "<filename>" "<image_path>"
```

**并发策略：** 每次最多同时启动 5 个后台生成任务，等待一批完成后再启动下一批。每批完成后向用户汇报进度。

### Step 5: 去除白色背景

生成完图片后，**必须**去除白色背景使其透明。使用 `scripts/remove_bg.sh`：

```bash
# 批量处理整个目录
bash scripts/remove_bg.sh "<output_dir>"

# 或处理单个文件
bash scripts/remove_bg.sh "<output_dir>/01_OK.png"
```

原理：ImageMagick floodfill 从图片四角向内填充透明，fuzz 20% 容差处理近白色像素。角色本身不受影响。

### Step 6: 保存和展示结果

- 图片保存到 `output/stickers/<pack-name>/` 目录，pack-name 基于角色描述自动生成
- 文件名格式：`{序号:02d}_{标签}.png`（如 `01_OK.png`）
- 所有图片已透明背景，可直接用于微信表情包
- 生成完成后，用 Read 工具逐个读取展示生成的图片
- 输出汇总信息：总数、保存路径、耗时

## 动态 GIF 模式（--gif）

当用户指定 `--gif` 时，使用 Sora 2 API 生成动态表情包。

### GIF 生成流程

有两种路径，根据情况自动选择：

**路径 A：先静后动（推荐，角色一致性更好）**
1. 先用 Gemini 3 Pro 生成静态表情 PNG（同静态模式）
2. 再用 Sora 2 img2video API 将静态图片动画化
3. ffmpeg 转换 mp4 → GIF

**路径 B：纯文字直接生成动画**
1. 直接用 Sora 2 text2video API 生成视频
2. ffmpeg 转换 mp4 → GIF
3. 适用于无参考图且不需要先出静态版的场景

**默认使用路径 A**，因为先生成静态图可以：
- 让用户先预览角色形象是否满意
- 保证动画版和静态版角色一致
- 如果用户对静态版不满意，可以及时调整，避免浪费视频生成的费用

### GIF 动画 Prompt 模板

基于静态图做动画化（img2video）：
```
Animate this cute sticker character. The character [动画动作英文描述].
Short seamless loop animation, smooth motion, keep the cute chibi style,
white background stays clean, character stays centered.
No camera movement, no background changes.
```

每个表情对应的动画动作描述：

```
1.  OK        - gives a thumbs up with a confident nod
2.  谢谢      - bows forward gently in gratitude
3.  早安      - stretches arms wide and yawns, sun rises beside
4.  晚安      - slowly nods off to sleep, eyes closing gradually
5.  嗨        - waves hand energetically side to side
6.  呵呵      - awkward smile with a small sweat drop appearing
7.  爱你      - makes a heart gesture, floating hearts pop up around
8.  什么      - tilts head in confusion, question marks bounce around
9.  震惊      - jaw drops open dramatically, exclamation marks appear
10. 拜托      - presses palms together pleadingly, bouncing slightly
11. 加油      - pumps fist in the air enthusiastically
12. 鼓掌      - claps hands rapidly with musical notes floating
13. 紧张      - trembles nervously with sweat drops flying off
14. 累了      - slowly melts and slumps down to the ground
15. 生气      - stomps feet angrily with steam puffing from head
16. 抱歉      - bows deeply in apology, sweat drops falling
17. 不行      - shakes head vigorously and waves hands in X gesture
18. 了解      - nods firmly with a small notepad appearing
19. 对对对    - nods head rapidly and enthusiastically
20. 没问题    - gives a confident OK sign with a wink
21. 哭了      - bursts into tears with teardrops splashing
22. 开心      - jumps up and down joyfully with sparkles
23. 吃饭      - munches food eagerly from a bowl, cheeks puffing
24. 再见      - waves goodbye slowly, turning away slightly
```

### GIF 生成执行

使用 `scripts/generate_animated_sticker.sh` 脚本：

**基于静态图动画化（路径 A）：**
```bash
bash scripts/generate_animated_sticker.sh img2video "<动画prompt>" "<output_dir>" "<filename>" "<static_image_path>"
```

**纯文字生成动画（路径 B）：**
```bash
bash scripts/generate_animated_sticker.sh text2video "<动画prompt>" "<output_dir>" "<filename>"
```

### GIF 并发策略

由于 Sora 2 是异步 API 且生成时间较长（通常 1~3 分钟/个），采用不同策略：
- 同时提交最多 3 个异步任务
- 每个任务独立轮询，间隔 10 秒
- 超时上限 10 分钟/个
- 每个任务完成后立即向用户展示结果并汇报总进度

### --gif-only 模式

用户可以用 `--gif-only "嗨,开心,再见"` 指定只对部分表情做动画：
- 指定的表情 → 生成 GIF（走动画流程）
- 其余表情 → 生成静态 PNG（走普通流程）
- 这样在混合使用时可以节省时间和 API 费用

## 错误处理

- API 返回错误：显示错误信息，跳过该表情继续生成其余的
- 图片下载失败：重试一次，仍失败则跳过并告知用户
- API Key 未设置：提示用户运行 `export PPIO_API_KEY=your_key`
- **GIF 专属**：
  - Sora 2 任务超时：输出 task_id 供用户后续手动查询
  - ffmpeg 未安装：提示用户 `brew install ffmpeg`
  - 视频转 GIF 失败：保留 mp4 源文件，告知用户手动转换

## 示例交互

### 示例 1：静态表情包
用户：`/sticker 一只圆滚滚的橘色小猫，大眼睛，短尾巴`

助手行为：
1. 确认角色：圆滚滚橘色小猫，大眼睛，短尾巴
2. 使用默认 16 张表情列表
3. 构建 16 个 prompt，英文描述角色 + 各表情动作
4. 分 4 批（每批 5 个）并发调用 Gemini API
5. 下载保存到 `output/stickers/orange-cat/`
6. 展示每张生成结果

### 示例 2：全套动态表情包
用户：`/sticker 一只绿色小恐龙 --gif --count 8`

助手行为：
1. 确认角色：绿色小恐龙
2. 取前 8 个表情
3. **Phase 1**：先用 Gemini 生成 8 张静态 PNG，展示给用户预览
4. 确认用户满意后进入 **Phase 2**
5. 用 Sora 2 img2video 将 8 张静态图逐一动画化
6. ffmpeg 转为 GIF，保存到 `output/stickers/green-dino/`
7. 最终展示所有 GIF 结果

### 示例 3：混合模式
用户：`/sticker 一只白色柴犬 --gif-only "嗨,开心,再见"`

助手行为：
1. 确认角色：白色柴犬
2. 使用默认 16 张表情列表
3. 生成 16 张静态 PNG
4. 对 "嗨""开心""再见" 三张额外生成 GIF 版本
5. 最终目录包含 16 个 PNG + 3 个 GIF
