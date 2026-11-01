# 课程视频分析工具

在你自己的电脑上运行（云端服务器的 IP 会被 YouTube 和 Bilibili 拦截），把老师的视频下载到本地，再从视频里分析出每个练习的音型、节奏和速度，结果用来校准应用里的练习。下载的视频也可以直接在应用里播放、跟着练（在应用「设置」里选择 `tools/course/media` 文件夹）。

支持两位老师：`--teacher stoney`（Justin Stoney，YouTube，默认）和 `--teacher peo`（Peo 老师，Bilibili）。

## 在 Mac 上直接下载（推荐）

在装了应用的那台 Mac 上运行 `mac.sh`，视频直接下到应用要读的文件夹（默认 `~/Movies/练声房视频`），不用再从别的电脑拷贝：

```bash
git clone https://github.com/Egeek2025/vocal-ex2.git && cd vocal-ex2
tools/course/mac.sh setup                                   # 一次：Homebrew 装 ffmpeg/python/node，建 venv
PROXY=http://127.0.0.1:7890 tools/course/mac.sh check       # 检查 YouTube（走代理）和 B 站登录
PROXY=http://127.0.0.1:7890 tools/course/mac.sh all         # 两位老师的视频都下载，1080p
```

- `PROXY` 只用于 YouTube；B 站默认直连，需要代理时另设 `BILI_PROXY`。
- B 站 1080p 用 Chrome 里的登录（`BROWSER=safari` 等可换浏览器）；第一次会弹窗问是否允许访问「Chrome Safe Storage」，选允许。
- 换存放位置：`MEDIA=/Volumes/外置盘/练声房视频 tools/course/mac.sh all`。
- 下载完在应用「设置」里选择这个文件夹；以后新下载了视频，点「重新查找」。

下面是 Ubuntu 上的用法（也适用于想在别的电脑上下载再拷贝的情况）。

## 准备（只需一次）

适用于 Ubuntu（在 Ubuntu 25 上使用 Python 自带的 venv）。在仓库根目录运行：

```bash
sudo apt update && sudo apt install -y ffmpeg python3-venv nodejs
tools/course/setup.sh
```

`setup.sh` 会在 `tools/course/.venv` 建一个 venv，装好 numpy 和 yt-dlp（含 YouTube 需要的 yt-dlp-ejs 组件）。缺少系统软件时它会提示要装什么。`nodejs` 是 yt-dlp 解析 YouTube 用的 JavaScript 运行环境；如果你已经装了 deno，可以不装 nodejs。

之后的命令都用 venv 里的 Python。下面写的是完整路径；也可以先 `source tools/course/.venv/bin/activate`，再用 `python` 代替 `tools/course/.venv/bin/python`。

## 1. 下载视频

```bash
PY=tools/course/.venv/bin/python
$PY tools/course/fetch.py                  # 课程播放列表里的全部视频
$PY tools/course/fetch.py --only-exercises # 只下载应用里有练习的那些集（约 50 个）
$PY tools/course/fetch.py --audio-only     # 只要音频，体积小很多，分析已经够用
$PY tools/course/fetch.py --episodes 5,101 # 指定集数
```

- 文件保存在 `tools/course/media/<视频 id>/`，包括视频、英文字幕（`.vtt`）和章节信息（`.info.json`）。这个目录不会提交到 git。
- 重复运行只会下载缺少的部分，中途断了可以直接再运行。
- 如果 YouTube 提示需要验证，加上 `--cookies-from-browser firefox`（或 `chrome`、`chromium`），使用这个浏览器的登录状态。Ubuntu 上用 snap 装的 Firefox 要写成 `--cookies-from-browser "firefox:$HOME/snap/firefox/common/.mozilla/firefox"`。
- yt-dlp 需要更新时（YouTube 改版后常见）：`tools/course/.venv/bin/python -m pip install -U "yt-dlp[default]"`。
- 默认按 **1080p** 下载（`--max-height 1440` 或 `2160` 可以更高）。网站只给 VP9/AV1 编码时，下载完会自动转成 H.264，保证 iPhone、iPad、Mac 都能播放（`--no-recode` 跳过）。1080p 每小时视频约 1–2 GB。
- 只做分析不看视频的话，`--audio-only` 体积小很多。
- 以前按 480p 下载的视频（YouTube 实际给的是 360p）可以升级：`$PY tools/course/fetch.py --only-exercises --upgrade` 会删掉低于 1080p 的视频并重新下载，字幕和章节信息保留。

### 已经下载的视频转成能播放的格式

```bash
$PY tools/course/transcode.py --dry-run          # 只列出哪些视频需要转换
$PY tools/course/transcode.py                    # 转换 tools/course/media 里的全部视频
$PY tools/course/transcode.py ~/Videos/某个文件夹  # 也可以转换别的文件夹或单个文件
```

只重新编码 VP9/AV1 这类苹果设备不一定能解码的视频，分辨率不变；本来就能播放的不动；转换成功后才替换原文件。

### Peo 老师（Bilibili）

最省事的方式是用 `peo.sh`，它把安装、登录检查、列表、下载、转换、分析串在一起，下载时用你 Chrome 里已经登录 B 站的状态拿 1080p：

```bash
tools/course/peo.sh setup      # 一次
tools/course/peo.sh check      # 确认能拿到 1080p
tools/course/peo.sh all        # 列表 + 下载练声类视频 + 分析
```

Chrome 用的不是默认账户时加 `BROWSER="chrome:Profile 1"`（在 `chrome://version` 看「个人资料路径」）。也可以分开运行，下面是对应的完整命令：

```bash
$PY tools/course/fetch.py --teacher peo --list                                   # 先列出她的全部视频（只要标题和时长，不下载）
$PY tools/course/fetch.py --teacher peo --match "练声|发声|音阶" --cookies-from-browser firefox   # 下载标题匹配的视频
$PY tools/course/fetch.py --teacher peo --ids BV1xxxx,BV1yyyy --cookies-from-browser firefox     # 下载指定视频
```

- `--list` 把视频列表写到 `tools/course/output/peo_catalog.json`。把它发给 Claude（只有标题、时长和 BV 号），可以一起挑出练声视频。
- Bilibili 不登录最高只给 480p/720p，要 1080p 需要加 `--cookies-from-browser`，用你登录 B 站的浏览器。登录信息只在你自己电脑上使用。
- 字幕会尝试下载 B 站的 AI 中文字幕（有的视频没有）。

## 2. 分析音型

```bash
$PY tools/course/analyze.py                 # 所有已下载视频的练习
$PY tools/course/analyze.py --only trill,ng # 指定练习（练习 id 见 Sources/Core/Course.swift）
```

做法：取每个练习时间点开始的那一章（视频没有章节时取 120 秒），检测音高，把唱的部分分成乐句。课程里同一个音型会一个调一个调往上重复，所以出现次数最多的音程序列就是这个练习的音型，跟起始调无关。

输出到 `tools/course/output/`：

- `report.md`：每个练习一节，包括识别出的简谱音型（以最低音为 1，`'` 表示高八度）、拍数、速度、一致度、第一个调的根音、其他出现过的音型，以及这一段的字幕原文（可从中找到 Justin 说的音节）。
- `patterns.json`：同样的内容，方便程序读取。

「一致度」是唱这个音型的乐句占全部乐句的比例。视频里有讲解、钢琴伴奏和学生示范时会混进别的乐句，一致度低于 0.5 的结果请对照视频核对。

## 3. 截取课程原声示范（可选）

```bash
$PY tools/course/clips.py                    # 每个练习截一段示范
$PY tools/course/clips.py --only trill --take 2   # 第一个调里有讲解声时，换用第 2 个调
```

从视频里截取每个练习完整唱一遍的原声示范，生成 `tools/course/media/demo-pack/`（每个练习一个 `.m4a`，加一个记录根音、速度和音型的 `manifest.json`）。截取按应用里已经确定的音型来做：

1. 在练习那一章的音高里找完整的一遍音型。3 个音以内的音型必须完全一致，4–5 个音允许 1 个音识别错，6 个音以上允许 2 个；音符间隔要均匀，避免拼到相邻的调。只唱一个长音的练习取第一个够长的音。
2. 找不到完整的一遍、分析只找到一部分（例如 8-5-3-1 只找到 5-3-1）时，按这部分在音型里的位置，用测出的速度把截取范围补到整个音型，前后再多留半个音。
3. 截完后重新分析片段，确认里面唱的是完整音型，并按完整音型重新计算根音。核对不通过的片段不会进应用，脚本会列出来，可以用 `--take 2` 换一遍、或加大 `--pad`（默认前后各留 0.5 秒）再试。

`demo-pack` 就在 `tools/course/media` 里：在应用「设置」里把课程视频文件夹设为 `tools/course/media`，应用会自动找到它，不用导入。之后这些练习的示范就是 Justin 的原声，并自动移到每个调、跟着你设置的速度变化。iPhone 上使用时，把整个 `media` 文件夹拷进「文件」App（例如 iCloud 云盘），再在应用「设置」里选择它。

## Peo 老师：找出视频里的练习

Peo 老师的视频没有练习列表和章节，用 `discover.py` 扫描整段视频：同一个音型一个调接一个调重复，就认为是一个练习。

```bash
$PY tools/course/discover.py --teacher peo                    # 所有已下载的 Peo 老师视频
$PY tools/course/discover.py --teacher peo --ids BV1xxxx      # 指定视频
```

输出 `tools/course/output/peo_report.md` 和 `peo_exercises.json`：每个视频里每个练习的时间段、简谱音型、拍数、速度、连续调数、第一个调的根音，以及开唱前钢琴弹的和弦。报告里**没有字幕原文**，可以直接整份发给 Claude，用来把应用里 Peo 老师的练习对应到视频（打开练习就跳到视频里这一段）、改成她实际用的音型。

## 4. 更新应用

`tools/course/output/` 不提交到仓库：`report.md` 里有课程字幕原文，仓库是公开的。需要更新应用时，把 `report.md` 里相关练习的音型、拍数、根音这几行（不用带字幕）贴给 Claude，让它更新 `Sources/Core/Course.swift` 里各练习的音型和音节。分析参数可以调整后重新运行，不需要重新下载视频。

## 版权

课程视频版权归各位老师所有（Justin Stoney / New York Vocal Coaching；Peo 老师）。下载视频也可能不符合 YouTube、Bilibili 的服务条款。这些文件只在本地供个人学习和分析使用，不要提交到仓库、放进应用或分享给他人。
