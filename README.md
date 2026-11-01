# 练声房（VocalStudio）

配合 Justin Stoney「Voice Lessons To The World」12 周学习方案的原生 Apple 应用。一套 SwiftUI 代码，同时支持 iPhone、iPad 和 Mac。

## 功能

- **今日练习**：打开应用的第一页，按 12 周方案排好每天该练什么、按什么顺序：热身（唇颤音、NG）→ 本周内容（每周第 1–3 天学新练习、先看视频片段；第 4–5 天强化得分最低的练习；第 6 天做方案里的本周检验；第 7 天休息）→ 复习上周一个练习 → 用歌曲套用 → 放松。每完成一步自动打勾，显示本周进度；本周练习都练过、做完检验后进入下一周。
- **课程**：按 12 周课程浏览全部练习，随时单独练。每个练习的流程和声乐热身伴奏带一样：每个调先弹和弦定调，流程和声乐热身伴奏带一样：每个调先弹和弦定调，再听示范，数拍子后跟着节拍器唱，然后升半音进入下一个调。音高卷帘上实时画出你唱的音高，唱完给出音准、偏高偏低、换声点、最常唱错的音、明亮度和颤音的反馈，每个调都可以单独再练。
- **真人示范**：每个练习都可以录制或导入一段真人示范（老师或你自己按练习音节唱一遍），之后练习时用这段录音示范，并自动移到每个调；录制的示范还会跟着速度变化。没有录示范时，用钢琴弹一遍旋律示范（和课程一样）。每个调开始前先弹定调和弦。
- **课程原声示范**：用 `tools/course/` 里的脚本在你自己的电脑上下载课程视频、分析每个练习的音型、截取一段原声示范，再在应用里一次导入（见 [tools/course/README.md](tools/course/README.md)）。应用和仓库都不包含任何课程音视频，这些文件只留在你自己的设备上。
- **两位老师，可切换**：Justin Stoney 的「Voice Lessons To The World」12 周方案（YouTube），和 Peo 老师的欧美流行 / SLS 唱法课程（Bilibili，8 周）。在「设置」里切换老师，每位老师有自己的练习、周计划和进度。Peo 老师的练习目前按 SLS 体系的常用练习编排，标为「待核对」；用 `tools/course/discover.py` 分析她的视频后会改成她实际用的音型，并对应到视频。
- **跟视频练**：在「设置」里指定一次课程视频文件夹（例如 `tools/course/media`，所有老师的视频放在一起即可）。每个练习页都能点「跟视频练」，在练习页里直接播放对应视频并从这个练习开始；打开「开麦跟唱」后，键盘上实时显示你唱的音。同一集里的其他练习可以一键跳转。下载工具默认 1080p，并自动把苹果设备不一定能解码的编码转成 H.264。没找到本地视频时仍然打开 YouTube 或 Bilibili。
- **省电**：不用时自动关掉音频引擎和麦克风（停用约 20 秒后，或应用进入后台时），下次练习自动重新打开。
- **节拍器和提示音**：预备拍（2 或 4 拍，第一个调总是 4 拍，大号倒数显示）、唱时节拍器（强拍加重，可调音量）、定调和弦、可选的钢琴同步伴奏。节拍声漏进麦克风的那几帧不计入评分。
- **钢琴键盘**：音高卷帘下方的钢琴键盘跟着练习走：定调和弦和示范音按下对应的键，轮到你唱时目标音的键变绿，你正在唱的音用圆点标出（颜色表示准不准）。点按琴键可以弹出这个音。
- **呼吸**：嘶气和 SH-ZH 用麦克风自动计时；Farinelli 呼吸按拍数引导。
- **音域测试**：录最低音和最高音，之后的练习按你的音域安排起止调。
- **录音分析**：导入音频文件，画音高曲线，统计长音音准、颤音和明亮度。
- **练习记录**：保存在设备上，统计练习天数和连续天数。

## 运行

需要一台装了 **Xcode 16 或更新版本**的 Mac（工程使用 Xcode 16 的文件夹同步格式，`Sources` 里新增的文件会自动加入工程）。

1. 双击打开 `VocalStudio.xcodeproj`。
2. 在 Xcode 顶部选择运行目标：**My Mac** 运行 Mac 版，选模拟器或连接的 iPhone 运行手机版。
3. 点运行（⌘R）。

### 自动编译（GitHub Actions）

每次推送到 GitHub，`.github/workflows/build.yml` 会在 macOS 机器上：

- 运行核心逻辑的单元测试（`swift test`，测音高检测、颤音、课程数据和评分）；
- 分别编译 iOS 和 macOS 版本（不签名），编译产物可以在 Actions 页面下载：`VocalStudio-macOS.zip` 解压即可在 Mac 上运行（第一次需要右键 → 打开）；`VocalStudio-iOS-unsigned.ipa` 没有签名，不能直接装到 iPhone，装手机请按下面的步骤用 Xcode 安装。

### 发布可下载的应用（GitHub Releases）

`.github/workflows/release.yml` 会编译 Mac 和 iPhone 版并发布到仓库的 Releases 页面。两种触发方式：

- 在 GitHub 的 Actions → Release → Run workflow 里输入版本号（例如 `1.0.1`）；
- 或者推送版本标签：`git tag v1.0.1 && git push origin v1.0.1`。

每个版本会附带：

| 文件 | 说明 |
| --- | --- |
| `VocalStudio-版本-macOS.dmg` / `.zip` | Mac 版，打开 dmg 后拖进「应用程序」 |
| `VocalStudio-版本-iOS-unsigned.ipa` | iPhone/iPad 版，未签名，需要用 Sideloadly、AltStore 或 Xcode 用你的 Apple ID 签名后安装 |

没有配置证书时，Mac 版用临时签名，第一次打开需要右键 →「打开」。如果加入了 Apple Developer Program，可以在仓库 Settings → Secrets and variables → Actions 里添加下面这些 Secret，之后发布的 Mac 版会自动用 Developer ID 签名并经过 Apple 公证，下载后可直接打开：

| Secret | 内容 |
| --- | --- |
| `MAC_CERT_P12` | 「Developer ID Application」证书导出的 .p12 文件，做 base64 编码后的文本（`base64 -i cert.p12 \| pbcopy`） |
| `MAC_CERT_PASSWORD` | 导出 .p12 时设置的密码 |
| `APPLE_ID` | 开发者账号的 Apple ID 邮箱 |
| `APPLE_APP_PASSWORD` | 在 appleid.apple.com 生成的 App 专用密码 |
| `APPLE_TEAM_ID` | 开发者账号的 Team ID（10 位） |

### 装到自己的 iPhone

1. Xcode → Settings → Accounts 登录你的 Apple ID（免费账号即可）。
2. Target → Signing & Capabilities → Team 选你的账号，把 Bundle Identifier 改成你自己的，例如 `com.你的名字.vocalstudio`。
3. 用数据线连接 iPhone，在 iPhone 的「设置 → 隐私与安全性」里打开「开发者模式」。
4. 在 Xcode 顶部选择你的 iPhone，点运行。第一次需要在 iPhone 的「设置 → 通用 → VPN 与设备管理」里信任开发者。

免费账号装的应用 7 天后需要重新从 Xcode 安装。想长期使用、用 TestFlight 发给朋友，或上架 App Store，需要加入 Apple Developer Program（每年 99 美元）。

## 代码结构

| 目录 | 内容 |
| --- | --- |
| `Sources/Core` | 与平台无关的逻辑：音名换算、课程数据（练习、音型、12 周安排、视频时间点）、McLeod 音高检测（FFT 自相关）、练习计划、评分和反馈、录音分析 |
| `Sources/Audio` | `AudioEngine`：用 AVAudioEngine 合成示范音，用麦克风输入做逐帧音高分析。示范音和麦克风帧共用系统主机时钟，所以能把唱的音和当时该唱的目标音对上 |
| `Sources/App` | 应用入口和 `AppModel`（声部设置、周次、练习记录） |
| `Tests/VocalCoreTests` | 核心逻辑的单元测试，用 `swift test` 运行（`Package.swift` 只包含 `Sources/Core`） |
| `Sources/Resources` | 应用图标（`Assets.xcassets`）和钢琴采样（`PianoSamples/piano_36…96.m4a`），C2–C7 |
| `Sources/Views` | SwiftUI 界面：课程侧栏、练习页（简谱、音高卷帘、仪表、反馈）、呼吸、音域、录音分析、记录 |

## 说明

- 音高检测和评分逻辑是从网页版移植的，网页版的检测算法用合成音测过（82–988 Hz 误差在 0.3 音分以内）。Swift 代码由 GitHub Actions 在 macOS 上编译和测试，见上面的「自动编译」。
- iOS 上音频会话使用 `measurement` 模式，关掉系统的降噪和自动增益，让音量和明亮度的测量更真实。外放示范音时，麦克风可能会听到示范音；建议戴耳机练习。
- 练习的音节和音型按课程视频校准过：音节取自各集字幕；音型来自 Justin 在字幕里说出的音型，或由视频音频分析得出并与字幕核对。练习页会标明「音型已按课程视频核对」或「音型待核对」，后者暂用常用练声音型。
- 明亮度（2–4 kHz 与低频的能量比）受麦克风和距离影响，只适合和自己在同样条件下的录音比较。
- 内置钢琴采样来自 FluidR3 GM 音色库的 Acoustic Grand Piano（作者 Frank Wen，经 [gleitz/midi-js-soundfonts](https://github.com/gleitz/midi-js-soundfonts) 渲染），以 [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) 授权使用。每个半音一个采样。钢琴采样原本整体偏高 5–25 音分，播放时按测量值逐个校正。
- 课程视频的声音受版权保护，没有截取进应用。录制或导入示范时，请只使用你有权使用的录音（例如你自己或你的老师唱的）。
- 视频版权归 Justin Stoney / New York Vocal Coaching 所有。应用不包含视频内容：只链接到 YouTube，或播放你自己指定文件夹里的本地视频。
