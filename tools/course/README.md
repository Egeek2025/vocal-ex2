# 课程视频分析工具

在你自己的电脑上运行（云端服务器的 IP 会被 YouTube 拦截），把课程视频下载到本地，再从视频里分析出每个练习的音型、节奏和速度，结果用来校准应用里的练习。

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
- 全部视频按 480p 下载大约需要几 GB 空间；可以用 `--max-height 360` 或 `--audio-only` 减小体积。

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

在应用的课程侧栏点「导入课程原声示范」，选择 `demo-pack` 文件夹。之后这些练习的示范就是 Justin 的原声，并自动移到每个调、跟着你设置的速度变化。iPhone 上使用时，先把 `demo-pack` 文件夹拷进「文件」App（例如 iCloud 云盘），再在应用里选择它。

## 4. 更新应用

`tools/course/output/` 不提交到仓库：`report.md` 里有课程字幕原文，仓库是公开的。需要更新应用时，把 `report.md` 里相关练习的音型、拍数、根音这几行（不用带字幕）贴给 Claude，让它更新 `Sources/Core/Course.swift` 里各练习的音型和音节。分析参数可以调整后重新运行，不需要重新下载视频。

## 版权

课程视频版权归 Justin Stoney / New York Vocal Coaching 所有，下载 YouTube 视频也不符合 YouTube 的服务条款。这些文件只在本地供个人分析使用，不要提交到仓库、放进应用或分享给他人。
