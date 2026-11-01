#!/usr/bin/env python3
"""Download a teacher's videos with subtitles and chapter info, for practice and local analysis.

Files go to tools/course/media/<video id>/ and are not committed. Running it again only
fetches what is missing, so it can be resumed at any time. Videos are fetched at 1080p
(or the best below that) and converted to H.264 when the site only offers codecs that
Apple's player cannot always decode, so the app can play every file.

    tools/course/setup.sh                                          # once: venv + dependencies
    tools/course/.venv/bin/python tools/course/fetch.py            # Justin Stoney: every video in the playlist
    ... fetch.py --only-exercises                                  # only the episodes the app has exercises for
    ... fetch.py --teacher peo --list                              # Peo 老师: list her videos, download nothing
    ... fetch.py --teacher peo --match "练声|发声|音阶"              # her videos whose title matches
    ... fetch.py --teacher peo --cookies-from-browser firefox      # Bilibili gives 1080p only when logged in
    ... fetch.py --audio-only                                      # much smaller; enough for analysis
"""
import argparse
import importlib.util
import json
import shutil
import subprocess
import sys
import time

from common import MEDIA, OUTPUT, PLAYLIST, TEACHERS, exercises, video_ids, video_url
import transcode


def main():
    ap = argparse.ArgumentParser(description="下载老师的视频、字幕和章节信息到本地")
    ap.add_argument("--teacher", choices=sorted(TEACHERS), default="stoney",
                    help="哪位老师：stoney = Justin Stoney（YouTube，默认），peo = Peo 老师（Bilibili）")
    ap.add_argument("--list", action="store_true",
                    help="只列出老师的全部视频（标题、时长、id），写到 output/<老师>_catalog.json，不下载")
    ap.add_argument("--match", metavar="REGEX", help="只下载标题匹配这个正则的视频，例如 \"练声|发声|音阶\"")
    ap.add_argument("--ids", help="只下载这些视频 id（YouTube id 或 BV 号），用逗号分隔")
    ap.add_argument("--only-exercises", action="store_true", help="只下载应用里有练习的那些集")
    ap.add_argument("--episodes", help="只下载指定集数，例如 5,101,86")
    ap.add_argument("--audio-only", action="store_true", help="只下载音频（体积小很多，分析已经够用，但应用里不能看视频）")
    ap.add_argument("--max-height", type=int, default=1080,
                    help="视频分辨率上限，默认 1080；有 1440、2160 也可以设得更高")
    ap.add_argument("--upgrade", action="store_true",
                    help="把以前下载的低分辨率视频（低于 --max-height）删掉重新下载，例如早先默认 480p 时下的 360p")
    ap.add_argument("--no-recode", action="store_true",
                    help="下载后不转换编码（默认会把 VP9/AV1 转成 H.264，保证 iPhone 和 Mac 都能播放）")
    ap.add_argument("--cookies-from-browser", metavar="BROWSER",
                    help="使用这个浏览器的登录状态，例如 firefox、chrome、chromium。"
                         "YouTube 要求验证时需要；Bilibili 不登录最高只有 480p/720p，登录后才有 1080p")
    ap.add_argument("--proxy", help="通过代理下载，例如 http://127.0.0.1:7890 或 socks5://127.0.0.1:1080；"
                                    "浏览器能打开但这里连不上时，用浏览器正在用的代理；--proxy \"\" 表示不走任何代理直接连接")
    ap.add_argument("--timeout", type=int, default=60, help="连接和读取超时（秒），默认 60")
    ap.add_argument("--ipv4", action="store_true", help="只用 IPv4 连接（IPv6 线路不通时常见的读取超时）")
    ap.add_argument("--chunk-size", default="10M", help="每次请求下载多大一段，默认 10M，和浏览器一样分段下载；设为 0 关闭")
    ap.add_argument("--client", default="default,web_safari,mweb,tv",
                    help="（只用于 YouTube）依次尝试的客户端，用逗号分隔。不同客户端会分到不同的视频服务器，一个连不上就自动换下一个")
    a = ap.parse_args()

    ytdlp = yt_dlp_command()
    if not ytdlp:
        sys.exit("找不到 yt-dlp。先运行 tools/course/setup.sh，再用 tools/course/.venv/bin/python 运行本脚本。")
    if not shutil.which("ffmpeg"):
        sys.exit("找不到 ffmpeg。运行：sudo apt install -y ffmpeg")

    teacher = TEACHERS[a.teacher]
    youtube = teacher["site"] == "youtube"
    common_args = network_args(a)

    if a.list:
        return list_videos(ytdlp, a.teacher, common_args)

    MEDIA.mkdir(parents=True, exist_ok=True)
    started = time.time()
    if a.upgrade and not a.audio_only:
        drop_low_resolution(a.teacher, a.max_height)
    urls = wanted_urls(a)
    if not urls:
        sys.exit("没有要下载的视频。")

    if a.audio_only:
        fmt = "bestaudio[ext=m4a]/bestaudio/best"
    else:
        h = a.max_height
        # 1080p H.264 first, then the best video up to the limit in any codec (converted below), then anything
        fmt = (f"bv*[height<={h}][vcodec^=avc1]+ba[ext=m4a]/bv*[height<={h}][vcodec^=avc]+ba"
               f"/bv*[height<={h}]+ba/b[height<={h}]/bv*+ba/b")

    cmd = ytdlp + common_args + [
        "--ignore-errors", "--no-overwrites", "--continue",
        "--download-archive", str(MEDIA / "archive.txt"),
        "-f", fmt,
        # sort so that, among equal heights, the higher one and H.264 win
        "-S", f"res:{a.max_height},vcodec:avc,acodec:aac" if not a.audio_only else "acodec:aac",
        "--write-info-json",
        "--write-subs", "--write-auto-subs",
        "--sub-langs", "en" if youtube else "ai-zh,zh-Hans,zh-CN,zh",
        "--sub-format", "vtt/srt/best", "--convert-subs", "vtt",
        "--sleep-requests", "1", "--sleep-interval", "2", "--max-sleep-interval", "6",
        "--retries", "5", "--fragment-retries", "5", "--retry-sleep", "exp=2:30",
        "-o", str(MEDIA / "%(id)s" / "%(id)s.%(ext)s"),
    ]
    if a.match:
        cmd += ["--match-filters", f"title~='{a.match}'"]
    if not a.audio_only:
        cmd += ["--merge-output-format", "mp4"]

    print(f"下载 {teacher['name']} 的 {len(urls)} 个地址到 {MEDIA}（已下载的会跳过；目标 {a.max_height}p）")
    clients = [c.strip() for c in a.client.split(",") if c.strip()] if youtube else ["default"]
    rc = 1
    for i, client in enumerate(clients or ["default"]):
        extra = [] if client == "default" else ["--extractor-args", f"youtube:player_client={client}"]
        if youtube:
            print(f"\n== 使用 YouTube 客户端：{client}")
        rc = subprocess.run(cmd + extra + urls).returncode
        if rc == 0:
            break
        if i + 1 < len(clients):
            print(f"有视频没下载成功，换用客户端 {clients[i + 1]} 重试（已完成的会跳过）")
    if rc != 0:
        print("\n仍有视频没下载成功。可以稍后再运行一次，或加 --proxy 走浏览器用的代理。")
    if not youtube and not a.cookies_from_browser and not a.audio_only:
        print("提示：Bilibili 不登录最高只给 480p/720p。要 1080p，加 --cookies-from-browser firefox（或你登录 B 站用的浏览器）。")

    if not a.audio_only and not a.no_recode:
        transcode.convert_all(MEDIA, newer_than=started)   # only what this run downloaded
    nxt = "analyze.py" if youtube else "discover.py --teacher peo"
    print(f"完成。接着运行：{sys.executable} tools/course/{nxt}")
    sys.exit(rc)


def drop_low_resolution(teacher, max_height):
    """Delete this teacher's videos below the wanted height and forget them in the download archive,
    so this run fetches them again. Subtitles and info files are kept."""
    want = min(max_height, 1080) - 60
    bili = TEACHERS[teacher]["site"] == "bilibili"
    archive = MEDIA / "archive.txt"
    dropped = []
    for d in sorted(p for p in MEDIA.iterdir() if p.is_dir()):
        if d.name.startswith("BV") != bili:
            continue
        for f in d.glob(f"{d.name}.*"):
            if f.suffix.lower() not in transcode.VIDEO_EXT:
                continue
            _, _, h = transcode.probe(f)
            if h and h < want:
                print(f"  {f.name}：{h}p，删除后重新下载")
                f.unlink()
                dropped.append(d.name)
    if dropped and archive.exists():
        keep = [line for line in archive.read_text(encoding="utf-8").splitlines()
                if not any(line.endswith(" " + vid) for vid in dropped)]
        archive.write_text("\n".join(keep) + ("\n" if keep else ""), encoding="utf-8")
    print(f"{len(set(dropped))} 个低分辨率视频会重新下载。" if dropped else "没有低于目标分辨率的视频。")


def network_args(a):
    out = ["--socket-timeout", str(a.timeout)]
    if a.proxy is not None:
        out += ["--proxy", a.proxy]   # an empty value means connect directly, ignoring proxy settings
    if a.ipv4:
        out += ["--force-ipv4"]
    if a.chunk_size and a.chunk_size != "0":
        out += ["--http-chunk-size", a.chunk_size]
    if a.cookies_from_browser:
        out += ["--cookies-from-browser", a.cookies_from_browser]
    # YouTube needs a JavaScript runtime; yt-dlp uses deno by default, so point it at node if that is what is installed
    if not shutil.which("deno") and shutil.which("node"):
        out += ["--js-runtimes", "node"]
    return out


def wanted_urls(a):
    if a.ids:
        return [video_url(a.teacher, v.strip()) for v in a.ids.split(",") if v.strip()]
    vids = video_ids(a.teacher)
    if a.episodes:
        wanted = {int(x) for x in a.episodes.split(",") if x.strip()}
        missing = sorted(wanted - set(vids))
        if missing:
            print("这些集数不在练习数据里，跳过：", missing)
        return [video_url(a.teacher, vids[e]) for e in sorted(wanted) if e in vids]
    used = sorted({e["video"] for e in exercises(a.teacher) if e["video"]})
    urls = [video_url(a.teacher, v) for v in used]
    if not a.only_exercises:
        urls.insert(0, TEACHERS[a.teacher]["home"] if a.teacher != "stoney" else PLAYLIST)
    return urls


def list_videos(ytdlp, teacher, common_args):
    """Write the teacher's video list (id, title, duration, date) without downloading anything."""
    home = TEACHERS[teacher]["home"]
    print(f"列出 {TEACHERS[teacher]['name']} 的视频：{home}")
    sep = "␟"
    fields = sep.join(["%(id)s", "%(title)s", "%(duration)s", "%(upload_date)s", "%(view_count)s"])
    rows = []
    for flat in (True, False):
        cmd = ytdlp + common_args + ["--ignore-errors", "--skip-download", "--print", fields]
        if flat:
            cmd.insert(len(ytdlp), "--flat-playlist")
        out = subprocess.run(cmd + [home], capture_output=True, text=True)
        rows = [line.split(sep) for line in out.stdout.splitlines() if line.count(sep) == 4]
        # the flat listing of some sites has no titles; then read every video page (slower)
        if rows and any(r[1] not in ("NA", "") for r in rows):
            break
        if flat:
            print("快速列表没有标题，改为逐个读取视频页面（会慢一些）…")
    if not rows:
        print(out.stderr[-2000:])
        sys.exit("没有拿到视频列表。可以加 --cookies-from-browser firefox 或 --proxy 再试。")
    videos = [{"id": r[0], "title": r[1], "duration": num(r[2]), "date": r[3], "views": num(r[4])} for r in rows]
    OUTPUT.mkdir(parents=True, exist_ok=True)
    path = OUTPUT / f"{teacher}_catalog.json"
    path.write_text(json.dumps(videos, ensure_ascii=False, indent=1), encoding="utf-8")
    for v in videos:
        d = v["duration"]
        print(f"{v['id']}  {int(d // 60) if d else 0:>3}:{int(d % 60) if d else 0:02d}  {v['date']}  {v['title']}")
    print(f"\n共 {len(videos)} 个视频，已写入 {path}")
    print("把这个列表（只有标题和时长）发给 Claude，用来挑出练声视频、对应到应用里的练习。")


def num(x):
    try:
        return float(x)
    except (TypeError, ValueError):
        return None


def yt_dlp_command():
    """Prefer the yt-dlp installed in the running Python (the venv), then one on PATH."""
    if importlib.util.find_spec("yt_dlp"):
        return [sys.executable, "-m", "yt_dlp"]
    exe = shutil.which("yt-dlp")
    return [exe] if exe else None


if __name__ == "__main__":
    main()
