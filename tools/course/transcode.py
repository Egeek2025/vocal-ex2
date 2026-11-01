#!/usr/bin/env python3
"""Make downloaded videos playable in the app (Apple's player on iPhone, iPad and Mac).

Apple's player always decodes H.264 and HEVC; VP9 and AV1 depend on the device, so those are
re-encoded to H.264 (keeping the resolution), and audio that is not AAC is converted to AAC.
Files that are already fine are left alone; WebM/MKV containers with playable streams are remuxed
to MP4 without re-encoding. The original is replaced only after the new file is complete.

    tools/course/.venv/bin/python tools/course/transcode.py                 # everything under tools/course/media
    tools/course/.venv/bin/python tools/course/transcode.py ~/Videos/peo    # another folder or single files
    ... transcode.py --dry-run                                              # only list what would change
"""
import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

from common import MEDIA

VIDEO_EXT = {".mp4", ".m4v", ".mov", ".mkv", ".webm"}
APPLE_VIDEO = {"h264", "hevc"}
APPLE_AUDIO = {"aac", "alac", "mp3"}


def probe(path):
    """(video codec, audio codec, height) of a file."""
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=codec_type,codec_name,height",
                          "-of", "json", str(path)], capture_output=True, text=True)
    streams = json.loads(out.stdout or "{}").get("streams", [])
    v = next((s for s in streams if s.get("codec_type") == "video"), {})
    a = next((s for s in streams if s.get("codec_type") == "audio"), {})
    return v.get("codec_name"), a.get("codec_name"), v.get("height")


def plan(path):
    """What to do with a file: None (fine), 'remux', or 'encode'."""
    vc, ac, _ = probe(path)
    if vc is None:
        return None  # audio only
    if vc in APPLE_VIDEO and (ac is None or ac in APPLE_AUDIO):
        return None if path.suffix.lower() in {".mp4", ".m4v", ".mov"} else "remux"
    return "encode" if vc not in APPLE_VIDEO else "audio"


def convert(path, how, crf=20, preset="medium"):
    tmp = path.with_name(path.stem + ".converting.mp4")
    cmd = ["ffmpeg", "-v", "error", "-stats", "-y", "-i", str(path), "-map", "0:v:0", "-map", "0:a:0?"]
    if how == "encode":
        cmd += ["-c:v", "libx264", "-crf", str(crf), "-preset", preset, "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "160k"]
    elif how == "audio":
        cmd += ["-c:v", "copy", "-c:a", "aac", "-b:a", "160k"]
    else:
        cmd += ["-c", "copy"]
    cmd += ["-movflags", "+faststart", str(tmp)]
    if subprocess.run(cmd).returncode != 0 or not tmp.exists():
        tmp.unlink(missing_ok=True)
        print(f"  转换失败，保留原文件：{path}")
        return False
    final = path.with_suffix(".mp4")
    if path != final:
        path.unlink()
    tmp.replace(final)
    return True


def files(paths):
    for p in paths:
        p = Path(p).expanduser()
        if p.is_dir():
            yield from sorted(f for f in p.rglob("*") if f.suffix.lower() in VIDEO_EXT and ".converting." not in f.name)
        elif p.suffix.lower() in VIDEO_EXT:
            yield p


def convert_all(*paths, dry_run=False, crf=20, preset="medium"):
    if not shutil.which("ffprobe"):
        print("找不到 ffprobe（随 ffmpeg 安装），跳过编码检查。")
        return
    todo = [(f, how) for f in files(paths or [MEDIA]) if (how := plan(f))]
    if not todo:
        print("所有视频都能在 iPhone 和 Mac 上直接播放，不需要转换。")
        return
    label = {"encode": "重新编码为 H.264", "audio": "音频转为 AAC", "remux": "换成 MP4 封装"}
    print(f"\n{len(todo)} 个视频需要处理，才能在应用里播放：")
    for f, how in todo:
        vc, ac, h = probe(f)
        print(f"  {f.name}（{vc}/{ac}，{h}p）→ {label[how]}")
    if dry_run:
        return
    for i, (f, how) in enumerate(todo, 1):
        print(f"[{i}/{len(todo)}] {f.name}")
        convert(f, how, crf, preset)


def main():
    ap = argparse.ArgumentParser(description="把视频转成 iPhone/iPad/Mac 都能播放的 H.264 MP4")
    ap.add_argument("paths", nargs="*", help="文件或文件夹，默认 tools/course/media")
    ap.add_argument("--dry-run", action="store_true", help="只列出需要转换的文件")
    ap.add_argument("--crf", type=int, default=20, help="H.264 画质，越小越清晰、文件越大（默认 20）")
    ap.add_argument("--preset", default="medium", help="编码速度：faster 更快，slow 文件更小（默认 medium）")
    a = ap.parse_args()
    if not shutil.which("ffmpeg"):
        sys.exit("找不到 ffmpeg。运行：sudo apt install -y ffmpeg")
    convert_all(*a.paths, dry_run=a.dry_run, crf=a.crf, preset=a.preset)


if __name__ == "__main__":
    main()
