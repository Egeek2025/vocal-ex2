#!/usr/bin/env python3
"""Download the course videos with their subtitles and chapter info, for local analysis.

Files go to tools/course/media/<video id>/ and are not committed. Running it again only
fetches what is missing, so it can be resumed at any time.

    tools/course/setup.sh                                   # once: venv + dependencies
    tools/course/.venv/bin/python tools/course/fetch.py     # every video in the course playlist
    ... fetch.py --only-exercises                           # only the episodes the app has exercises for
    ... fetch.py --audio-only                               # much smaller; enough for analysis
"""
import argparse
import importlib.util
import shutil
import subprocess
import sys

from common import MEDIA, PLAYLIST, exercises, video_ids


def main():
    ap = argparse.ArgumentParser(description="下载课程视频、字幕和章节信息到本地")
    ap.add_argument("--only-exercises", action="store_true", help="只下载应用里有练习的那些集")
    ap.add_argument("--audio-only", action="store_true", help="只下载音频（体积小很多，分析已经够用）")
    ap.add_argument("--max-height", type=int, default=480, help="视频最高分辨率，默认 480")
    ap.add_argument("--cookies-from-browser", metavar="BROWSER",
                    help="YouTube 要求验证时，使用这个浏览器的登录状态，例如 firefox、chrome、chromium")
    ap.add_argument("--episodes", help="只下载指定集数，例如 5,101,86")
    ap.add_argument("--proxy", help="通过代理下载，例如 http://127.0.0.1:7890 或 socks5://127.0.0.1:1080；"
                                    "浏览器能打开但这里连不上时，用浏览器正在用的代理")
    ap.add_argument("--timeout", type=int, default=60, help="连接和读取超时（秒），默认 60")
    ap.add_argument("--ipv4", action="store_true", help="只用 IPv4 连接（IPv6 线路不通时常见的读取超时）")
    ap.add_argument("--chunk-size", default="10M", help="每次请求下载多大一段，默认 10M，和浏览器一样分段下载；设为 0 关闭")
    ap.add_argument("--client", default="default,web_safari,mweb,tv",
                    help="依次尝试的 YouTube 客户端，用逗号分隔（默认 default,web_safari,mweb,tv）。"
                         "不同客户端会分到不同的视频服务器，一个连不上就自动换下一个")
    a = ap.parse_args()

    ytdlp = yt_dlp_command()
    if not ytdlp:
        sys.exit("找不到 yt-dlp。先运行 tools/course/setup.sh，再用 tools/course/.venv/bin/python 运行本脚本。")
    if not shutil.which("ffmpeg"):
        sys.exit("找不到 ffmpeg。运行：sudo apt install -y ffmpeg")

    MEDIA.mkdir(parents=True, exist_ok=True)
    vids = video_ids()
    if a.episodes:
        wanted = {int(x) for x in a.episodes.split(",") if x.strip()}
        ids = [vids[e] for e in sorted(wanted) if e in vids]
        missing = sorted(wanted - set(vids))
        if missing:
            print("这些集数不在练习数据里，跳过：", missing)
        urls = [f"https://www.youtube.com/watch?v={v}" for v in ids]
    else:
        exercise_ids = sorted({e["video"] for e in exercises() if e["video"]})
        urls = [f"https://www.youtube.com/watch?v={v}" for v in exercise_ids]
        if not a.only_exercises:
            urls.insert(0, PLAYLIST)

    if a.audio_only:
        fmt = "bestaudio[ext=m4a]/bestaudio/best"
    else:
        h = a.max_height
        # H.264 first: the app plays these files with Apple's player, which cannot always decode VP9/AV1
        fmt = (f"bv*[height<={h}][vcodec^=avc1]+ba[ext=m4a]/bv*[height<={h}][ext=mp4]+ba[ext=m4a]"
               f"/b[height<={h}][ext=mp4]/bv*[height<={h}]+ba/b")

    cmd = ytdlp + [
        "--ignore-errors", "--no-overwrites", "--continue",
        "--download-archive", str(MEDIA / "archive.txt"),
        "-f", fmt,
        "--write-info-json",
        "--write-subs", "--write-auto-subs", "--sub-langs", "en","--sub-format", "vtt",
        "--sleep-requests", "1", "--sleep-interval", "2", "--max-sleep-interval", "6",
        # slow or flaky video servers: wait longer, retry more, back off between retries
        "--socket-timeout", str(a.timeout),
        "--retries", "5", "--fragment-retries", "5", "--retry-sleep", "exp=2:30",
        "-o", str(MEDIA / "%(id)s" / "%(id)s.%(ext)s"),
    ]
    if a.proxy:
        cmd += ["--proxy", a.proxy]
    if a.ipv4:
        cmd += ["--force-ipv4"]
    if a.chunk_size and a.chunk_size != "0":
        cmd += ["--http-chunk-size", a.chunk_size]
    if not a.audio_only:
        cmd += ["--merge-output-format", "mp4"]
    # YouTube needs a JavaScript runtime; yt-dlp uses deno by default, so point it at node if that is what is installed
    if not shutil.which("deno") and shutil.which("node"):
        cmd += ["--js-runtimes", "node"]
    if a.cookies_from_browser:
        cmd += ["--cookies-from-browser", a.cookies_from_browser]

    print(f"下载 {len(urls)} 个地址到 {MEDIA}（已下载的会跳过）")
    clients = [c.strip() for c in a.client.split(",") if c.strip()] or ["default"]
    rc = 1
    for i, client in enumerate(clients):
        extra = [] if client == "default" else ["--extractor-args", f"youtube:player_client={client}"]
        print(f"\n== 使用 YouTube 客户端：{client}")
        rc = subprocess.run(cmd + extra + urls).returncode
        if rc == 0:
            break
        if i + 1 < len(clients):
            print(f"有视频没下载成功，换用客户端 {clients[i + 1]} 重试（已完成的会跳过）")
    if rc != 0:
        print("\n仍有视频没下载成功。可以稍后再运行一次，或加 --proxy 走浏览器用的代理。")
    print(f"完成。接着运行：{sys.executable} tools/course/analyze.py")
    sys.exit(rc)


def yt_dlp_command():
    """Prefer the yt-dlp installed in the running Python (the venv), then one on PATH."""
    if importlib.util.find_spec("yt_dlp"):
        return [sys.executable, "-m", "yt_dlp"]
    exe = shutil.which("yt-dlp")
    return [exe] if exe else None


if __name__ == "__main__":
    main()
