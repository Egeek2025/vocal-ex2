"""Shared paths and course data for the course tools.

The exercise list and video IDs are read from Sources/Core/Course.swift (Justin Stoney) and
Sources/Core/Peo.swift (Peo 老师) so the tools always match the app.
"""
import json
import os
import re
import shutil
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
# ffmpeg/ffprobe that mac.sh setup downloads when Homebrew has none (Intel Macs)
if (HERE / ".bin").is_dir():
    os.environ["PATH"] = str(HERE / ".bin") + os.pathsep + os.environ.get("PATH", "")
COURSE_SWIFT = ROOT / "Sources" / "Core" / "Course.swift"
PEO_SWIFT = ROOT / "Sources" / "Core" / "Peo.swift"
# downloaded videos, subtitles, chapter info (not in git); VOCAL_MEDIA puts them anywhere, e.g. ~/Movies/练声房视频
MEDIA = Path(os.environ.get("VOCAL_MEDIA") or HERE / "media").expanduser()
OUTPUT = HERE / "output"    # analysis results (not in git: they quote the videos' subtitles)

PLAYLIST = "https://www.youtube.com/playlist?list=PLpcARcDSTR0KZjKxP9ecy7qadkM3Hqk_j"

# where each teacher's videos are, and which Swift file holds the exercises and video table
TEACHERS = {
    "stoney": {"name": "Justin Stoney", "site": "youtube", "swift": COURSE_SWIFT, "table": "videoIDs",
               "home": PLAYLIST},
    "peo": {"name": "Peo 老师", "site": "bilibili", "swift": PEO_SWIFT, "table": "peoVideos",
            "home": "https://space.bilibili.com/3546774224505365/video"},
}


def video_ids(teacher="stoney"):
    """Episode number -> video id (YouTube id or Bilibili BV id) for a teacher."""
    t = TEACHERS[teacher]
    src = t["swift"].read_text(encoding="utf-8")
    block = src[src.index(f"static let {t['table']}"):]
    block = block[block.index("= [") + 3:]
    block = block[:block.index("]")]
    return {int(ep): vid.replace("live:", "") for ep, vid in re.findall(r'(\d+): "([^"]+)"', block)}


def video_url(teacher, vid):
    if TEACHERS[teacher]["site"] == "bilibili":
        return f"https://www.bilibili.com/video/{vid}/"
    return f"https://www.youtube.com/watch?v={vid}"


def exercises(teacher=None):
    """Exercises defined in the app, in order; every teacher's unless one is named."""
    pat = re.compile(r'Exercise\(id: "([^"]+)", ep: (\d+), t: (\d+), name: "([^"]+)", syl: "([^"]+)"(?:, pat: "([^"]+)")?(.*?)\),?\n', re.S)
    out = []
    for tid, t in TEACHERS.items():
        if teacher and tid != teacher:
            continue
        src = t["swift"].read_text(encoding="utf-8")
        vids = video_ids(tid)
        for m in pat.finditer(src):
            ex_id, ep, t_, name, syl, pattern, rest = m.groups()
            kind = re.search(r"kind: \.(\w+)", rest or "")
            out.append({
                "id": ex_id, "teacher": tid, "ep": int(ep), "t": int(t_), "name": name, "syl": syl,
                "pattern": pattern, "kind": kind.group(1) if kind else "pitch",
                "video": vids.get(int(ep)),
            })
    return out


MAJOR = {1: 0, 2: 2, 3: 4, 4: 5, 5: 7, 6: 9, 7: 11, 8: 12, 9: 14}


def app_patterns():
    """Pattern name -> (semitones of the sung notes, beats per note) as defined in Course.swift.

    Covers patterns written as deg([...], beat, last) or as inline Step(s:, b:) lists; notes marked
    ns (glides, grace notes) are left out, like the app's scoring. Patterns built by helper functions
    are missing and get no template.
    """
    src = COURSE_SWIFT.read_text(encoding="utf-8")
    block = src[src.index("static let patterns"):src.index("static let videoIDs")]  # shared by all teachers
    out = {}
    for m in re.finditer(r'"(\w+)": Pattern\(name: "[^"]*", steps: (.*?)bpm:', block, re.S):
        name, body = m.group(1), m.group(2)
        d = re.match(r"deg\(\[([^\]]*)\], ([\d.]+), ([\d.]+)", body)
        z = re.match(r"zip\(\[([^\]]*)\]", body)
        if d:
            out[name] = ([MAJOR[int(x)] for x in d.group(1).split(",")], float(d.group(2)))
        elif z:
            out[name] = ([int(x) for x in z.group(1).split(",")], 0.5 if "0.5" in body else 1.0)
        else:
            steps = [s for s in re.findall(r"Step\(s: (-?\d+), b: ([\d.]+)([^)]*)\)", body) if "ns: true" not in s[2]]
            if steps:
                out[name] = ([int(s[0]) for s in steps], float(steps[0][1]))
    return out


def media_dir(video_id):
    return MEDIA / video_id


def media_file(video_id):
    """The downloaded video or audio file for a video id, if any."""
    d = media_dir(video_id)
    if not d.exists():
        return None
    for ext in ("mp4", "mkv", "webm", "m4a", "mka", "opus", "mp3"):
        files = sorted(d.glob(f"{video_id}.{ext}"))
        if files:
            return files[0]
    return None


def info_json(video_id):
    p = media_dir(video_id) / f"{video_id}.info.json"
    if p.exists():
        return json.loads(p.read_text(encoding="utf-8"))
    return None


def subtitle_file(video_id):
    d = media_dir(video_id)
    if not d.exists():
        return None
    subs = sorted(d.glob(f"{video_id}*.vtt"))
    # prefer human-made English subtitles over automatic ones
    manual = [s for s in subs if ".en." in s.name and "orig" not in s.name]
    return (manual or subs or [None])[0]


def read_audio(path, start=None, end=None, sr=22050):
    """Decode (part of) a media file to mono float32 samples with ffmpeg."""
    import numpy as np
    cmd = ["ffmpeg", "-v", "error"]
    if start is not None:
        cmd += ["-ss", f"{start:.3f}"]
    if end is not None:
        cmd += ["-to", f"{end:.3f}"]
    cmd += ["-i", str(path), "-vn", "-ac", "1", "-ar", str(sr), "-f", "f32le", "-"]
    if not shutil.which("ffmpeg"):
        raise SystemExit("找不到 ffmpeg。运行：sudo apt install -y ffmpeg")
    raw = subprocess.run(cmd, check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).copy()
