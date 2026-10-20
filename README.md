# 图片分拣工具 · 完整使用手册

按「工作时间规则 + 图片属性」筛选图片：把**非工作时间**拍摄、且**符合指定比例和位置**的照片，挑选出来复制/移动/硬链接/软链接到一个单独目录，或者仅输出一份路径列表供看图软件直接浏览。

适合整理相机、手机导出的照片，把节假日、周末、下班后拍的、特定构图或地点的照片单独归档。

---

## 目录

- [功能概览](#功能概览)
- [工作流程](#工作流程)
- [运行环境与依赖](#运行环境与依赖)
- [快速上手](#快速上手)
- [规则编辑器](#规则编辑器)
  - [常规周规则](#常规周规则)
  - [具体日期规则](#具体日期规则)
  - [文件名时间提取](#文件名时间提取)
  - [比例筛选](#比例筛选)
  - [GPS 位置筛选](#gps-位置筛选)
  - [运行设置](#运行设置)
  - [规则 JSON](#规则-json)
- [命令行脚本](#命令行脚本)
  - [用法](#用法)
  - [参数说明](#参数说明)
  - [三种运行模式](#三种运行模式)
- [只看不搬：输出文件列表](#只看不搬输出文件列表)
  - [配合看图软件](#配合看图软件)
- [筛选逻辑与优先级](#筛选逻辑与优先级)
- [四种文件处理模式](#四种文件处理模式)
- [日志](#日志)
- [常见问题](#常见问题)
- [性能与注意事项](#性能与注意事项)
- [文件说明](#文件说明)
- [快速参考卡片](#快速参考卡片)

---

## 功能概览

| 功能 | 说明 |
|------|------|
| 时间筛选 | 常规周规则（星期 + 时段）+ 具体日期规则（节假日/调休/半天假） |
| 文件名时间提取 | 无 EXIF 时从文件名解析拍摄时间，支持自动识别和模板 |
| 比例筛选 | 按图片宽高比筛选，自动根据 EXIF Orientation 校正横竖 |
| GPS 位置筛选 | 按经纬度 + 半径筛选拍摄地点，坐标支持十进制度和度分秒输入 |
| 元数据读取 | 优先 EXIF，缺失时可回退文件名或文件修改时间 |
| 四种处理模式 | 复制 / 移动 / 硬链接 / 软链接 |
| **文件列表输出** | **生成含时间戳的路径列表，可直接被 feh / sxiv / swayimg 等看图软件导入** |
| 日志 | 每张图片的处理记录，含时间戳和源/目标路径 |
| 预演 | `--dry-run` 只列清单，不写任何文件 |
| 只看模式 | `--list-only` 仅生成路径列表，不做任何文件操作 |
| 幂等重跑 | 目标已存在时默认跳过，重复运行不会产生重复 |
| 按需读取 | 只用到的元数据才会读取，开启文件名优先 + 无比例/GPS 时不调用 exiftool |
| 批量加速 | exiftool 单次调用（`-@` 文件列表），几百张图片几秒内读完 |

---

## 工作流程

```
┌──────────────────────┐
│ 1. rules_editor.html │  浏览器打开，编辑规则、填运行设置
│                       │  点「下载 rules.json」
└──────────┬───────────┘
           │
           ▼
      rules.json              规则文件（含时间、比例、GPS、文件名提取）
           │
           ▼
┌──────────────────────┐
│ 2. 生成命令           │  在 HTML 里点「生成命令」→「复制命令」
│                       │  得到一条完整的终端命令
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ 3. 终端粘贴运行        │  ./sort_photos.sh -s ... -d ...
│                       │
│ 三种模式：             │
│  · 正式执行           │  -d 目标 -m copy
│  · 预演               │  --dry-run
│  · 只看（生成列表）    │  --list-only
└──────────┬───────────┘
           │
           ├──▶ 目标目录 / 日志
           └──▶ matched_YYYYMMDD_HHMMSS.txt
                     │
                     ▼
              feh -f 列表文件
              （直接浏览筛选结果）
```

---

## 运行环境与依赖

| 组件 | 是否必需 | 说明 |
|------|---------|------|
| Linux / macOS | 必需 | 脚本用 bash |
| `bash` 4.0+ | 必需 | 需要关联数组 |
| `jq` | 必需 | 解析规则 JSON |
| `exiftool` | 可选但强烈建议 | 读 EXIF 时间、宽高、GPS；**比例和 GPS 筛选必须依赖它** |
| `feh` / `sxiv` / `swayimg` | 可选 | 查看生成的路径列表 |

### 安装依赖

**Ubuntu / Debian**

```bash
sudo apt install jq libimage-exiftool-perl feh
```

**Fedora / RHEL**

```bash
sudo dnf install jq perl-Image-ExifTool feh
```

**Arch Linux**

```bash
sudo pacman -S jq perl-image-exiftool feh
```

**macOS**

```bash
brew install jq exiftool bash feh
```

验证：

```bash
jq --version
exiftool -ver
```

两个命令都能返回版本号就装好了。

---

## 快速上手

1. **下载两个文件到同一目录**

   ```
   photo_sorter/
   ├── sort_photos.sh       # 主脚本
   ├── rules_editor.html    # 规则编辑器
   └── rules.json           # 首次导出后生成
   ```

2. **赋予执行权限**

   ```bash
   chmod +x sort_photos.sh
   ```

3. **打开规则编辑器**

   用浏览器打开 `rules_editor.html`。

4. **编辑规则**

   在页面上添加周规则、日期规则，需要时开启比例、GPS、文件名时间提取。

5. **填写运行设置，生成命令**

   在「运行设置」里填源目录、目标目录、处理模式等，点「生成命令」→「复制命令」。

6. **终端粘贴运行**

   ```bash
   cd ~/photo_sorter
   # 粘贴刚才复制的命令，例如：
   ./sort_photos.sh -s /home/user/Pictures -d /home/user/NonWork -m copy --dry-run
   ```

7. **确认后正式运行**

   去掉 `--dry-run` 再跑一遍。

8. **如果只想看不想搬**

   用 `--list-only`，生成一份路径列表，交给看图软件直接翻看（见下文）。

---

## 规则编辑器

用浏览器打开 `rules_editor.html`，分以下几个区域。

### 常规周规则

按「星期 + 时间段」定义工作时间。命中任意一条即视为工作时间。

- 每一行是一条规则。
- 点星期复选框选择生效的星期（周一 = 0，周日 = 6）。
- 开始、结束时间用 `HH:MM` 24 小时制，区间是左闭右开。

示例：

| 场景 | 规则 |
|------|------|
| 周一至周六 8:00–17:00 | 勾选周一到周六，`08:00` – `17:00` |
| 工作日晚上加班 | 再添加一行：勾选周一到周五，`19:00` – `21:00` |

### 具体日期规则

针对特定日期的例外，**优先于周规则**。

每行是一条日期规则，包含：

- 开始日期、结束日期（同日则填一样）
- 类型：**非工作** / **工作**
- 全天复选框：勾选表示整天生效；取消可填具体时段

示例：

| 场景 | 配置 |
|------|------|
| 国庆整周休假 | `2026-10-01` ~ `2026-10-07` / 非工作 / 全天 |
| 周六调休上班 | `2026-10-10` / 工作 / 全天 |
| 工作日只请上午假 | `2026-10-15` / 非工作 / 09:00–12:00 |
| 周六只上上午班 | 两条：先「非工作 / 全天」，再「工作 / 08:00–12:00」 |

### 文件名时间提取

很多相机、手机把拍摄时间编入文件名（如 `IMG_20231015_143022.jpg`）。启用后，在 EXIF 时间不可用时，尝试从文件名解析时间。

配置项：

| 项 | 说明 |
|----|------|
| 启用 | 是否开启此功能 |
| 优先级 | **EXIF 优先，文件名兜底**（默认）或 **文件名优先** |
| 解析方式 | **自动识别** 或 **使用模板** |
| 文件名模板 | 仅模板模式使用，如 `%Y%m%d_%H%M%S` |

#### 自动识别支持的格式

- `YYYYMMDD_HHMMSS`、`YYYY-MM-DD_HH-MM-SS`、`YYYY-MM-DD_HH:MM:SS`
- `YYYYMMDDHHMMSS`（无分隔符）
- 仅日期 `YYYY-MM-DD`、`YYYYMMDD`（时间补 `00:00:00`）
- Unix 时间戳（10 位秒 / 13 位毫秒）

#### 模板占位符

| 占位符 | 含义 |
|--------|------|
| `%Y` | 年（4 位） |
| `%m` | 月（2 位） |
| `%d` | 日（2 位） |
| `%H` | 时（2 位，24 小时制） |
| `%M` | 分（2 位） |
| `%S` | 秒（2 位） |
| `*` | 匹配任意字符 |

匹配是**子串匹配**，前缀（如 `IMG_`）和后缀会被自动忽略，所以模板只要写时间部分即可。

例如模板 `%Y%m%d_%H%M%S` 能匹配：

- `IMG_20231015_143022.jpg`
- `Screenshot_20231015_143022.png`
- `DSC00012_20231015_143022.JPG`

如需限定前缀（只想匹配 `IMG_` 开头的），可以写 `IMG_%Y%m%d_%H%M%S`。

### 比例筛选

按图片宽高比筛选。**仅对非工作时间拍摄的图片生效。**

配置项：

| 项 | 说明 |
|----|------|
| 启用 | 是否开启 |
| 模式 | **白名单**（只保留匹配的）或 **黑名单**（排除匹配的） |
| 容差 | 允许的比例偏差百分比，默认 2% |
| 比例列表 | 每行一条，包含名称、宽、高 |

页面提供常用比例快捷按钮：4:3、3:4、16:9、9:16、1:1、3:2、2:3。

**方向处理**：脚本会自动读取 EXIF `Orientation`，遇到值 6 或 8（旋转 90 度）时交换宽高。所以竖图（无论像素层是否横着）都会被正确识别成竖比例。

### GPS 位置筛选

按拍摄地点筛选。**仅对非工作时间拍摄的图片生效。**

配置项：

| 项 | 说明 |
|----|------|
| 启用 | 是否开启 |
| 模式 | **白名单**（只保留范围内的）或 **黑名单**（排除范围内的） |
| 地点列表 | 每行包含名称、格式、纬度、经度、半径（米） |

#### 两种坐标输入格式

每个地点可以在 **十进制度** 和 **度分秒** 之间自由切换。切换时数值不会丢失，界面会自动换算。

| 格式 | 示例 | 说明 |
|------|------|------|
| 十进制度 | `39.9075` / `116.3881` | 直接填数字，南纬/西经为负数 |
| 度分秒 | `39°54′27″ N` / `116°23′17″ E` | 度/分/秒分开填，方向下拉选 `N`/`S`/`E`/`W` |

度分秒模式下：

- 度、分、秒各有一个输入框，秒支持小数（如 `27.5″`）。
- 方向下拉选 `N`/`S`（纬度）或 `E`/`W`（经度）。
- 南纬、西经在方向下拉选 `S`/`W`，度分秒数值本身填正值。
- 秒满 60 会自动进位到分，分满 60 进位到度。

**无论界面用哪种格式，`rules.json` 里始终以十进制度存储**，脚本按十进制度做 haversine 计算。

距离用 haversine 公式计算，误差在米级以内。

> ⚠ **重要**：比例筛选和 GPS 筛选都依赖 exiftool。未安装时脚本会**直接报错退出**，不会静默降级。

### 运行设置

填写源目录、目标目录、脚本类型、处理模式、选项、日志文件。设置会保存在浏览器 localStorage，下次自动恢复。

点击「生成命令」后，下方文本区会显示可粘贴到终端的完整命令。点「复制命令」即可复制到剪贴板。

### 规则 JSON

底部文本区实时显示当前所有规则的 JSON。

- 表格里的改动会自动同步到 JSON。
- 也可直接改 JSON，点「应用 JSON」回填到表格。
- 点「下载 rules.json」保存到本地。
- 点「导入 rules.json」载入已有规则继续编辑。

---

## 命令行脚本

### 用法

```bash
./sort_photos.sh -s <源目录> -d <目标目录> [选项]
./sort_photos.sh -s <源目录> --list-only [选项]
```

### 参数说明

| 参数 | 说明 | 默认 |
|------|------|------|
| `-s <dir>` | 源目录（递归扫描） | 必填 |
| `-d <dir>` | 目标目录（不存在会自动创建） | 正式执行时必填；`--list-only` 时可省略 |
| `-r <file>` | 规则文件路径 | 脚本同目录的 `rules.json` |
| `-m <mode>` | `copy` / `move` / `hardlink` / `symlink` | `copy` |
| `--flat` | 不保留子目录结构，全部平铺 | 保留结构 |
| `--overwrite` | 目标已存在时覆盖 | 跳过 |
| `--dry-run` | 只列清单，不写文件 | 否 |
| `--list [file]` | 输出匹配文件的完整路径列表，默认带时间戳命名 | 关闭 |
| `--list-only [file]` | 只输出列表，不执行任何文件操作（隐含 `--list`） | 关闭 |
| `--log <file>` | 日志文件路径 | 脚本同目录的 `sort_photos.log` |
| `--no-log` | 关闭日志 | 否 |
| `-h` / `--help` | 显示帮助 | — |

### 三种运行模式

| 模式 | 生成列表 | 执行文件操作 | `-d` 必填 | 典型场景 |
|------|---------|-------------|-----------|---------|
| 默认（正式执行） | 否 | 是 | 是 | 真正搬迁/复制图片 |
| `--dry-run` | 否 | 否（只输出到 stdout） | 是 | 检查筛选结果是否符合预期 |
| `--list-only` | 是 | 否 | **否** | 只想浏览，不想搬迁 |

### 示例

```bash
# 预演：只列清单，不写文件
./sort_photos.sh -s ~/Pictures -d ~/NonWork --dry-run

# 复制，保留目录结构
./sort_photos.sh -s ~/Pictures -d ~/NonWork -m copy

# 硬链接，平铺到目标目录
./sort_photos.sh -s ~/Pictures -d ~/NonWork -m hardlink --flat

# 移动，目标已存在则覆盖
./sort_photos.sh -s ~/Pictures -d ~/NonWork -m move --overwrite

# 使用自定义规则文件
./sort_photos.sh -s ~/Pictures -d ~/NonWork -r ~/rules-2026.json

# 关闭日志
./sort_photos.sh -s ~/Pictures -d ~/NonWork --no-log

# 只看不搬：生成路径列表
./sort_photos.sh -s ~/Pictures --list-only

# 生成列表 + 正常执行
./sort_photos.sh -s ~/Pictures -d ~/NonWork -m hardlink --list

# 指定列表文件路径
./sort_photos.sh -s ~/Pictures --list-only ~/my_filtered.txt
```

---

## 只看不搬：输出文件列表

日常使用时，很多时候只是想**看看**筛出来的是哪些照片，并不想真的复制或移动它们。这时用 `--list-only` 最合适：

```bash
./sort_photos.sh -s ~/Pictures --list-only
```

输出类似：

```
已加载规则：周规则 1 条，日期规则 1 条，比例 1 条，GPS 0 条
扫描目录: /home/user/Pictures
找到 478 张图片
读取图片元数据（exiftool -@ 单次调用）...
  元数据读取完成
[LIST] 2026-10-01 17:08:14  /home/user/Pictures/IMG_0001.jpg
[LIST] 2026-10-05 09:14:34  /home/user/Pictures/IMG_0002.jpg
...
文件列表已输出: /home/user/matched_20261020_143022.txt （88 个文件）
==============================================
图片总数        : 478
工作时间（排除）: 208
比例不符（跳过）: 182
位置不符（跳过）: 0
非工作时间（匹配）: 88
失败            : 0
输出目录        : (未指定)
文件列表        : /home/user/matched_20261020_143022.txt
```

生成的 `.txt` 文件里，每行是一个图片的**完整路径**，可以被看图软件直接读取。

### 列表文件命名

不指定文件名时，自动生成：

```
matched_YYYYMMDD_HHMMSS.txt
```

`YYYYMMDD_HHMMSS` 是运行时刻的时间戳，存放在**当前工作目录**（即运行命令时所在的目录）。同一秒多次运行会覆盖同名文件，跨秒则生成新文件，方便保留历史记录。

可以用 `--list-only <路径>` 指定文件名：

```bash
./sort_photos.sh -s ~/Pictures --list-only ~/tmp/today_list.txt
```

### 配合看图软件

生成的路径列表可以直接喂给多种看图工具。

#### feh（Linux / X11，推荐）

最经典、最轻量的选择：

```bash
feh -f /home/user/matched_20261020_143022.txt
```

常用组合：

```bash
# 缩略图模式
feh -t -f matched_20261020_143022.txt

# 全屏幻灯片
feh -F -f matched_20261020_143022.txt

# 幻灯片每 3 秒切换
feh -D 3 -f matched_20261020_143022.txt
```

#### sxiv（Linux / X11）

极简风格，从 stdin 读取文件列表：

```bash
sxiv -i < matched_20261020_143022.txt
```

#### swayimg（Linux / Wayland）

适合 Sway / Hyprland 等 Wayland 环境：

```bash
swayimg -f matched_20261020_143022.txt
```

#### 一图流：筛选 + 查看

可以合并成一条命令：

```bash
./sort_photos.sh -s ~/Pictures --list-only --no-log --list /tmp/m.txt && feh -f /tmp/m.txt
```

### 与「正式执行」并行

用 `--list` 可以在正常执行复制/移动的同时也生成列表：

```bash
./sort_photos.sh -s ~/Pictures -d ~/NonWork -m hardlink --list
```

这样一份图片被硬链接到目标目录，同时列表里也记录了所有匹配项，之后既能用文件管理器打开目标目录，也能用 feh 快速翻看。

---

## 筛选逻辑与优先级

图片依次经过以下筛选，**任一步不通过即被跳过**（不输出、不加入列表）：

1. **时间规则**
   - 先看具体日期规则
   - 命中「全天」规则 → 直接决定，不再看周规则
   - 命中「时段」规则 → 只在该时段内覆盖，其余时间继续检查其它日期规则，最终回落到周规则
   - 同一天多条日期规则时，**列表中靠下的覆盖靠上的**
2. **比例筛选**（启用时）
3. **GPS 筛选**（启用时）
4. 通过全部筛选 → 按所选模式处理文件、加入列表

### 时间取值优先级

| `filename_time.priority` | 顺序 |
|--------------------------|------|
| `after_exif`（默认） | EXIF → 文件名 → 文件修改时间 |
| `before_exif` | 文件名 → EXIF → 文件修改时间 |

### 比例和 GPS 的“无信息”处理

| 情况 | 白名单模式 | 黑名单模式 |
|------|-----------|-----------|
| 无宽高信息 | 视为不匹配 → 跳过 | 视为不匹配 → 保留 |
| 无 GPS 信息 | 视为不匹配 → 跳过 | 视为不匹配 → 保留 |

白名单模式下，只有能确认符合的图片才会被输出，更安全。

---

## 四种文件处理模式

| 模式 | 参数 | 占用额外空间 | 源文件 | 说明 |
|------|------|-------------|--------|------|
| 复制 | `-m copy` | 是 | 保留 | 最安全，推荐首次使用；用 `cp -p` 保留时间戳 |
| 移动 | `-m move` | 否 | 被移走 | 速度快，不可逆；建议先用 `--dry-run` |
| 硬链接 | `-m hardlink` | 否 | 保留 | 需源和目标在同一磁盘分区；跨分区时自动退化为复制 |
| 软链接 | `-m symlink` | 否 | 保留 | 只是快捷方式；系统不支持时自动退化为复制 |

### 关于日期保留

- **复制**：使用 `cp -p`，保留修改时间、访问时间、权限。
- **移动**：同分区是重命名，天然保留；跨分区会自动复制并保留。
- **硬链接**：与源文件共享同一份数据，日期就是源文件的。
- **软链接**：链接本身有创建时间，指向的目标仍是源文件。

EXIF 拍摄时间不受影响，因为它存在图片内容里。

---

## 日志

默认写入脚本同目录的 `sort_photos.log`，采用**追加**方式，方便历史审计。

每行格式：

```
时间戳 | 操作 | 源路径 -> 目标路径
```

### 操作标记

| 标记 | 含义 |
|------|------|
| `INFO` | 运行开始/结束、参数摘要、统计汇总 |
| `COPY` | 复制成功 |
| `MOVE` | 移动成功 |
| `HARDLINK` | 硬链接成功 |
| `SYMLINK` | 软链接成功 |
| `COPY(fallback)` | 硬/软链接失败，自动降级为复制 |
| `SKIP-EXISTS` | 目标已存在，按规则跳过 |
| `SKIP-ASPECT` | 比例不符，跳过 |
| `SKIP-GPS` | 位置不符，跳过 |
| `OVERWRITE` | 目标已存在且启用覆盖 |
| `FAIL` | 处理失败 |
| `DRY-xxx` | 预演模式下的操作（未真正执行） |

### 样例

```
2026-10-20 09:15:03 | INFO         | ================ 运行开始 ================
2026-10-20 09:15:03 | INFO         | 源目录   : /home/user/Pictures
2026-10-20 09:15:03 | INFO         | 目标目录 : /home/user/NonWork
2026-10-20 09:15:03 | INFO         | 模式     : hardlink
2026-10-20 09:15:04 | HARDLINK     | /home/user/Pictures/IMG_0001.jpg -> /home/user/NonWork/IMG_0001.jpg
2026-10-20 09:15:05 | SKIP-EXISTS  | /home/user/Pictures/IMG_0002.jpg -> /home/user/NonWork/IMG_0002.jpg
2026-10-20 09:15:20 | INFO         | 图片总数        : 478
2026-10-20 09:15:20 | INFO         | 工作时间（排除）: 208
2026-10-20 09:15:20 | INFO         | 非工作时间（匹配）: 88
2026-10-20 09:15:20 | INFO         | 文件列表: /home/user/matched_20261020_091520.txt （88 个文件）
2026-10-20 09:15:20 | INFO         | ================ 运行结束 ================
```

用 `--no-log` 可关闭本次运行的日志。

---

## 常见问题

### Q1：运行后什么都没发生，也没输出

检查脚本是否用 `set -e` 和 `(( ... )) && ...` 混用。这个组合在条件为假时返回 1，会被 `set -e` 静默终止。本脚本已全部规避，若你改过脚本，注意这一点。

### Q2：提示「值对于底数而言过大」

这是 bash 把 `08`、`09` 当八进制解析。本脚本对日期用字符串比较、对时间用 `10#` 前缀，不会出现此问题。自行改动时避免把日期段直接放进 `$(( ))`。

### Q3：图片的拍摄时间不准

优先用 EXIF。若没装 exiftool，会退回文件修改时间，可能是复制、编辑、下载的时间。建议安装 exiftool，或在规则里启用「文件名时间提取」。

### Q4：比例筛选没挑出竖图

脚本已按 EXIF `Orientation` 校正宽高。如果仍有问题，用这条命令检查：

```bash
exiftool -q -q -m -s3 -n -ImageWidth -ImageHeight -Orientation your_photo.jpg
```

`Orientation=6` 或 `8` 表示需要旋转 90 度（竖图）。

### Q5：GPS 坐标想用度分秒输入

在编辑器的 GPS 表格里，把「格式」列切换到「度分秒」，会出现度/分/秒三个输入框和方向下拉。填完保存时，`rules.json` 里存的仍然是十进制度，脚本不变。

### Q6：目标目录里有旧文件，会被覆盖吗

默认不覆盖，会跳过。要覆盖加 `--overwrite`。

### Q7：源目录里有个子目录就是目标目录，会被重复扫描吗

不会。脚本在扫描时会排除目标目录自身。

### Q8：硬链接模式提示跨分区

硬链接要求源和目标在**同一文件系统**。跨分区时会自动退化为复制。要彻底避免，改用 `-m copy`。

### Q9：想给不同的图库用不同的规则

规则文件可以放在任意位置，用 `-r` 指定：

```bash
./sort_photos.sh -s ~/Photos -d ~/Out -r ~/rules-personal.json
```

### Q10：中途想终止

脚本在前台运行，直接 `Ctrl+C`。已处理的文件不会回滚。

### Q11：想在定时任务里跑

用命令行参数模式，例如每天凌晨 3 点复制一次：

```cron
0 3 * * * /home/user/photo_sorter/sort_photos.sh -s /home/user/Pictures -d /home/user/NonWork -m copy >> /home/user/photo_sorter/run.log 2>&1
```

### Q12：比例或 GPS 筛选启用后，脚本报错退出

需要安装 exiftool。安装方式见「运行环境与依赖」。

### Q13：文件名时间提取和 EXIF 冲突时以哪个为准

由 `filename_time.priority` 决定：

- `after_exif`：EXIF 优先，文件名只在 EXIF 缺失时使用。
- `before_exif`：文件名优先。

### Q14：列表文件路径写在哪里

不指定时，列表文件写到**当前工作目录**（运行时你所在的目录）。想指定，用 `--list-only <路径>`：

```bash
./sort_photos.sh -s ~/Pictures --list-only ~/tmp/filtered.txt
```

### Q15：生成的列表能不能被 Windows 看图软件用

列表是纯文本、每行一个完整路径、UTF-8 编码。Linux 上的 feh / sxiv / swayimg 可直接读。Windows 上可以配合 IrfanView 的 `/filelist` 参数，但 IrfanView 对含中文路径的兼容性可能不佳。

---

## 性能与注意事项

### 元数据读取

- 脚本启动时**按需**决定读哪些元数据（时间 / 宽高 / GPS）。
- 用 `exiftool -j ... -@ 文件列表` 一次调用处理所有图片，避免逐张启动 exiftool。
- 路径写入临时文件，不受命令行长度限制。
- 临时文件在脚本退出时自动删除（`trap ... EXIT`）。

### 无 exiftool 时的优化

| 场景 | 是否调用 exiftool |
|------|------------------|
| 未启用比例/GPS + 未启用文件名提取 | 是（读时间） |
| 未启用比例/GPS + 文件名提取 + `before_exif` | 否，完全不调用 |
| 启用比例或 GPS | 是（读需要的字段） |

### 幂等性

- 默认跳过已存在目标，重复运行不会产生重复。
- 用 `--overwrite` 时可以强制覆盖。
- `--list-only` 不做文件操作，天然幂等。

### 边界情况

- 文件名里含换行符时，临时文件的行分隔会出错，实际极少见。
- 元数据缺失的图片会回退到文件修改时间。
- 空目录时脚本直接退出，不会创建临时文件。
- 列表为空时仍会写出一个空文件，方便后续流程判断。

---

## 文件说明

| 文件 | 作用 |
|------|------|
| `sort_photos.sh` | 主处理脚本 |
| `rules_editor.html` | 可视化规则编辑器 |
| `rules.json` | 规则文件，由编辑器生成，脚本读取 |
| `sort_photos.log` | 运行日志（自动追加） |
| `matched_YYYYMMDD_HHMMSS.txt` | 生成的文件路径列表（`--list` / `--list-only` 时产生） |

### 数据流

```
rules_editor.html  ──▶  rules.json  ──▶  sort_photos.sh
   （编辑规则）           （规则文件）        （执行分拣）
                                            │
                                            ├──▶ 目标目录 / sort_photos.log
                                            └──▶ matched_*.txt ──▶ feh / sxiv / swayimg
```

### 规则文件结构

```json
{
  "weekly_rules": [
    { "days": [0,1,2,3,4,5], "start": "08:00", "end": "17:00" }
  ],
  "date_rules": [
    { "start_date": "2026-10-01", "end_date": "2026-10-07",
      "type": "off", "start_time": null, "end_time": null }
  ],
  "filename_time": {
    "enabled": false,
    "mode": "auto",
    "template": "",
    "priority": "after_exif"
  },
  "aspect_rules": {
    "enabled": false,
    "mode": "whitelist",
    "tolerance": 0.02,
    "ratios": [
      { "name": "3:4", "w": 3, "h": 4 }
    ]
  },
  "gps_rules": {
    "enabled": false,
    "mode": "whitelist",
    "points": [
      { "name": "家", "lat": 31.75, "lon": 120.76, "radius_m": 5000 }
    ]
  }
}
```

注意：`gps_rules.points` 里的 `lat` / `lon` 永远是十进制度，界面上的度分秒输入只是显示层的换算，不改变 JSON 结构。

---

## 一条完整的处理流程

```bash
# 1. 用浏览器打开 rules_editor.html，编辑规则并下载 rules.json 到脚本目录

# 2. 赋予脚本执行权限（首次）
chmod +x sort_photos.sh

# 3. 只看不搬：生成路径列表，交给看图软件确认
./sort_photos.sh -s ~/Pictures --list-only
feh -f matched_*.txt

# 4. 确认筛选逻辑符合预期，预演一次
./sort_photos.sh -s ~/Pictures -d ~/NonWork --dry-run

# 5. 正式复制
./sort_photos.sh -s ~/Pictures -d ~/NonWork -m copy

# 6. 之后每天增量跑一次（已存在的会跳过）
./sort_photos.sh -s ~/Pictures -d ~/NonWork -m copy

# 7. 查看日志
tail -50 sort_photos.log
```

---

## 快速参考卡片

### 依赖检查

```bash
jq --version
exiftool -ver
```

### 一次性准备

```bash
chmod +x sort_photos.sh
```

### 最简流程

```bash
# 1. 浏览器打开 rules_editor.html，编辑规则并下载 rules.json 到脚本目录
# 2. 只想看：生成列表并用 feh 浏览
./sort_photos.sh -s <源目录> --list-only && feh -f matched_*.txt
# 3. 正式运行
./sort_photos.sh -s <源目录> -d <目标目录> -m copy
```

### 命令速查

```bash
# 复制（最安全）
./sort_photos.sh -s ~/Pictures -d ~/Out -m copy

# 移动（源文件被转移）
./sort_photos.sh -s ~/Pictures -d ~/Out -m move

# 硬链接（同分区不占空间）
./sort_photos.sh -s ~/Pictures -d ~/Out -m hardlink

# 软链接（快捷方式）
./sort_photos.sh -s ~/Pictures -d ~/Out -m symlink

# 平铺，不保留子目录结构
./sort_photos.sh -s ~/Pictures -d ~/Out -m copy --flat

# 目标已存在时覆盖
./sort_photos.sh -s ~/Pictures -d ~/Out -m copy --overwrite

# 使用自定义规则文件
./sort_photos.sh -s ~/Pictures -d ~/Out -r ~/rules-trip.json

# 指定日志文件
./sort_photos.sh -s ~/Pictures -d ~/Out --log ~/sort.log

# 不写日志
./sort_photos.sh -s ~/Pictures -d ~/Out --no-log

# 只看不搬
./sort_photos.sh -s ~/Pictures --list-only

# 生成列表 + 正常执行
./sort_photos.sh -s ~/Pictures -d ~/Out -m hardlink --list

# 指定列表文件名
./sort_photos.sh -s ~/Pictures --list-only ~/my_list.txt

# 显示帮助
./sort_photos.sh -h
```

### 参数速查

| 参数 | 取值 | 默认 |
|------|------|------|
| `-s` | 源目录 | 必填 |
| `-d` | 目标目录 | 正式执行必填，`--list-only` 可省略 |
| `-r` | 规则文件 | `./rules.json` |
| `-m` | copy / move / hardlink / symlink | `copy` |
| `--flat` | 平铺 | 保留结构 |
| `--overwrite` | 覆盖已存在 | 跳过 |
| `--dry-run` | 预演 | 否 |
| `--list` | 输出列表 | 关闭 |
| `--list-only` | 只输出列表 | 关闭 |
| `--log` | 日志路径 | `./sort_photos.log` |
| `--no-log` | 关闭日志 | 否 |

### 三种运行模式

| 模式 | 生成列表 | 执行文件操作 | `-d` 必填 |
|------|---------|-------------|-----------|
| 默认 | 否 | 是 | 是 |
| `--dry-run` | 否 | 否 | 是 |
| `--list-only` | 是 | 否 | 否 |

### 时间取值优先级

| 配置 | 顺序 |
|------|------|
| `after_exif`（默认） | EXIF → 文件名 → 文件修改时间 |
| `before_exif` | 文件名 → EXIF → 文件修改时间 |

### 筛选顺序

```
时间规则（日期规则 > 周规则）
   ↓ 通过
比例筛选（如启用）
   ↓ 通过
GPS 筛选（如启用）
   ↓ 通过
按所选模式处理文件 / 加入列表
```

### 操作标记（日志）

| 标记 | 含义 |
|------|------|
| `COPY` / `MOVE` / `HARDLINK` / `SYMLINK` | 处理成功 |
| `COPY(fallback)` | 硬/软链接失败，自动降为复制 |
| `SKIP-EXISTS` | 目标已存在，跳过 |
| `SKIP-ASPECT` | 比例不符，跳过 |
| `SKIP-GPS` | 位置不符，跳过 |
| `OVERWRITE` | 覆盖已存在 |
| `FAIL` | 处理失败 |
| `DRY-xxx` | 预演，未真正执行 |

### 模板占位符

| 占位符 | 含义 |
|--------|------|
| `%Y` | 年（4 位） |
| `%m` | 月 |
| `%d` | 日 |
| `%H` | 时（24 小时制） |
| `%M` | 分 |
| `%S` | 秒 |
| `*` | 任意字符 |

常用模板：

| 文件名样例 | 模板 |
|------------|------|
| `IMG_20231015_143022.jpg` | `%Y%m%d_%H%M%S` |
| `2023-10-15_14-30-22.jpg` | `%Y-%m-%d_%H-%M-%S` |
| `20231015.jpg` | `%Y%m%d` |

### 常用比例

| 名称 | 宽 | 高 |
|------|----|----|
| 4:3 | 4 | 3 |
| 3:4 | 3 | 4 |
| 16:9 | 16 | 9 |
| 9:16 | 9 | 16 |
| 1:1 | 1 | 1 |
| 3:2 | 3 | 2 |
| 2:3 | 2 | 3 |

### 查看生成的文件列表

```bash
# feh（X11）
feh -f matched_20261020_143022.txt
feh -t -f matched_20261020_143022.txt        # 缩略图
feh -F -f matched_20261020_143022.txt        # 全屏
feh -D 3 -f matched_20261020_143022.txt      # 3 秒切换

# sxiv（X11）
sxiv -i < matched_20261020_143022.txt

# swayimg（Wayland）
swayimg -f matched_20261020_143022.txt
```

### 查看日志

```bash
# 最近 50 行
tail -50 sort_photos.log

# 只看输出成功的文件
grep 'COPY\|MOVE\|HARDLINK\|SYMLINK' sort_photos.log

# 只看被比例筛掉的
grep 'SKIP-ASPECT' sort_photos.log

# 只看失败的
grep 'FAIL' sort_photos.log
```

### 常见问题一分钟定位

| 现象 | 可能原因 | 处理 |
|------|---------|------|
| 一张都没输出 | 规则太严，或时间/比例/GPS 全没通过 | 加 `--dry-run` 看统计 |
| 比例筛选全被跳过 | 目录里主要是另一种比例 | 用 `exiftool -ImageWidth -ImageHeight` 抽查 |
| 竖图没被识别 | 缺 Orientation 校正或 EXIF 缺失 | 检查 `exiftool -Orientation` |
| GPS 全被跳过 | 图片无 GPS 信息 | 检查 `exiftool -GPSLatitude -GPSLongitude` |
| 报错「未检测到 exiftool」 | 开了比例/GPS 但没装 | `sudo apt install libimage-exiftool-perl` |
| 时间不准 | 无 EXIF，用了文件修改时间 | 装 exiftool 或启用文件名提取 |
| 重复运行后跳过一堆 | 正常，目标已存在 | 加 `--overwrite` 可强制覆盖 |
| 列表文件不知道在哪 | 默认在当前工作目录 | 用 `--list-only <路径>` 指定 |
| 列表不能用 feh 打开 | 路径含换行/编码异常 | 检查 `file matched_*.txt`，应为 UTF-8 文本 |

### 一条命令做完整检查

```bash
./sort_photos.sh -s ~/Pictures --list-only --no-log --list /tmp/m.txt && \
  echo "---- 汇总 ----" && wc -l /tmp/m.txt && feh -t -f /tmp/m.txt
```

先看列表和汇总数字是否符合预期，再决定是否切换到正式执行模式。