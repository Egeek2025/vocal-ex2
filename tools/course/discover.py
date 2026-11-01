#!/usr/bin/env python3
"""Find the vocal exercises in a teacher's downloaded videos when there is no exercise list yet.

Peo 老师's videos have no chapter list, so each whole video is scanned: the pitch track is cut into
overlapping windows, each window is searched for a shape that is sung key after key (the way warm-up
exercises are sung), and windows that found the same shape are merged into one exercise. For each
exercise it reports where it is in the video, the pattern as jianpu, beats, tempo, direction, the
first key and the piano chord heard before each key.

Writes, without any subtitle text, so the report can be shared:

    tools/course/output/<teacher>_exercises.json
    tools/course/output/<teacher>_report.md

    tools/course/.venv/bin/python tools/course/discover.py --teacher peo
    ... discover.py --teacher peo --ids BV1xxxx,BV1yyyy     # only these videos
"""
import argparse
import json
import sys

import numpy as np

from analyze import SR, cue_chord, find_pattern, offset_name
from common import MEDIA, OUTPUT, TEACHERS, info_json, media_file, read_audio
from pitch import notes as find_notes
from pitch import track

CHUNK = 300.0   # seconds of audio tracked at a time


def teacher_videos(teacher):
    """Ids of downloaded videos that belong to a teacher (by site)."""
    site = TEACHERS[teacher]["site"]
    out = []
    for d in sorted(MEDIA.iterdir()) if MEDIA.exists() else []:
        if not d.is_dir() or not media_file(d.name):
            continue
        info = info_json(d.name) or {}
        extractor = (info.get("extractor_key") or info.get("extractor") or "").lower()
        if (site == "bilibili" and ("bili" in extractor or d.name.startswith("BV"))) or \
           (site == "youtube" and "youtube" in extractor):
            out.append(d.name)
    return out


def all_notes(path, duration):
    """Notes of the whole video, tracked a few minutes at a time."""
    ns, t = [], 0.0
    while duration is None or t < duration:
        x = read_audio(path, t, t + CHUNK, SR)
        if len(x) < SR:
            break
        times, m, c, _ = track(x, SR)
        ns += find_notes(times + t, m, c)
        t += CHUNK
    return ns


def segments(ns, window, hop, min_keys):
    """Exercises found in overlapping windows, merged when neighbouring windows found the same shape."""
    if not ns:
        return []
    end = ns[-1]["end"]
    found = []
    t = 0.0
    while t < end:
        part = [n for n in ns if t <= n["start"] < t + window]
        p = find_pattern(part, min_keys=min_keys) if len(part) >= 6 else None
        if p and p["keys_in_a_row"] >= min_keys:
            found.append(p)
        t += hop
    merged = []
    for p in sorted(found, key=lambda p: p["takes"][0][0]):
        last = merged[-1] if merged else None
        if last and last["semitones"] == p["semitones"] and p["takes"][0][0] <= last["takes"][-1][1] + 10:
            seen = {round(tk[0], 1) for tk in last["takes"]}
            last["takes"] += [tk for tk in p["takes"] if round(tk[0], 1) not in seen]
            last["takes"].sort()
            last["keys_in_a_row"] = len(last["takes"])
        else:
            merged.append(dict(p))
    return merged


def mmss(t):
    return f"{int(t // 60)}:{int(t % 60):02d}"


def main():
    ap = argparse.ArgumentParser(description="在老师的本地视频里找出练声练习（没有练习列表时用）")
    ap.add_argument("--teacher", choices=sorted(TEACHERS), default="peo")
    ap.add_argument("--ids", help="只分析这些视频 id，用逗号分隔")
    ap.add_argument("--window", type=float, default=150, help="每次分析多少秒（默认 150）")
    ap.add_argument("--hop", type=float, default=60, help="窗口每次往后移多少秒（默认 60）")
    ap.add_argument("--min-keys", type=int, default=3, help="至少连续几个调重复才算一个练习（默认 3）")
    a = ap.parse_args()

    ids = [x.strip() for x in a.ids.split(",")] if a.ids else teacher_videos(a.teacher)
    if not ids:
        sys.exit(f"tools/course/media 里没有 {TEACHERS[a.teacher]['name']} 的视频。先运行 fetch.py --teacher {a.teacher}。")

    results = []
    for vid in ids:
        f = media_file(vid)
        if not f:
            print(f"跳过 {vid}：没有下载")
            continue
        info = info_json(vid) or {}
        title, duration = info.get("title", vid), info.get("duration")
        print(f"分析 {vid}  {title}", flush=True)
        ns = all_notes(f, duration)
        segs = segments(ns, a.window, a.hop, a.min_keys)
        exs = []
        for p in segs:
            takes = p["takes"]
            cue = cue_chord(f, takes)
            exs.append({
                "start": round(takes[0][0], 1), "end": round(takes[-1][1], 1),
                "jianpu": p["jianpu"], "semitones": p["semitones"], "beats": p["beats"], "bpm": p["bpm"],
                "keys": len(takes), "direction": p["direction"], "first_root": p["first_root_note"],
                "cue": cue["offsets"] if cue else None,
            })
            print(f"  {mmss(takes[0][0])}–{mmss(takes[-1][1])}  {p['jianpu']}  {len(takes)} 个调{p['direction']}")
        results.append({"id": vid, "title": title, "duration": duration, "exercises": exs})

    OUTPUT.mkdir(parents=True, exist_ok=True)
    base = OUTPUT / f"{a.teacher}_exercises.json"
    base.write_text(json.dumps(results, ensure_ascii=False, indent=1), encoding="utf-8")
    write_report(a.teacher, results)
    print(f"\n已写入 {base} 和 {a.teacher}_report.md。报告里没有字幕原文，可以直接发给 Claude。")


def write_report(teacher, results):
    out = [f"# {TEACHERS[teacher]['name']}：视频里的练声练习", "",
           "由 `tools/course/discover.py` 从本地视频自动找出：同一个音型一个调接一个调地重复，就算一个练习。",
           "简谱以音型最低音为 1，`'` 表示高八度；连续调数越多越可信。", ""]
    chords = {}
    for v in results:
        for e in v["exercises"]:
            if e["cue"]:
                chords.setdefault(tuple(e["cue"]), []).append(v["id"])
    if chords:
        out += ["## 开唱前的钢琴（全部汇总）", ""]
        for offs, vids in sorted(chords.items(), key=lambda kv: -len(kv[1])):
            out.append(f'- **{" ".join(offset_name(o) for o in offs)}**（半音 {list(offs)}）：{len(vids)} 次')
        out.append("")
    for v in results:
        d = v["duration"]
        out.append(f'## {v["title"]}（`{v["id"]}`' + (f'，{mmss(d)}' if d else "") + "）")
        if not v["exercises"]:
            out.append("- 没有找到一个调接一个调重复的音型（可能是讲解、歌曲示范或问答）。")
        for e in v["exercises"]:
            line = (f'- {mmss(e["start"])}–{mmss(e["end"])}：**{e["jianpu"]}**（半音 {e["semitones"]}，拍数 {e["beats"]}），'
                    f'{e["keys"]} 个调{e["direction"]}，约 {e["bpm"]} BPM，第一个调根音 {e["first_root"]}')
            if e["cue"]:
                line += f'，开唱前钢琴 {" ".join(offset_name(o) for o in e["cue"])}'
            out.append(line)
        out.append("")
    (OUTPUT / f"{teacher}_report.md").write_text("\n".join(out), encoding="utf-8")


if __name__ == "__main__":
    sys.exit(main())
