#!/usr/bin/env python3
"""Cut one sung take of each exercise from your downloaded course videos, as a demo pack for the app.

The exercise's pattern is already known from Course.swift, so each clip is cut around one complete
take of that pattern:

1. look for the whole pattern in the pitch track of the exercise's chapter, allowing one misheard
   note (an exercise sung on a single note takes the first long note);
2. when the analysis only found part of the pattern, place that part inside the pattern and widen
   the cut by the missing notes' length at the measured tempo;
3. analyse the cut clip again and keep it only if the whole pattern is in it.

Writes tools/course/media/demo-pack/<exercise id>.m4a and manifest.json (root note, tempo, notes).
Import that folder in the app. The clips are Justin Stoney's recordings: keep them on your own
devices for your own practice, never commit or publish them.

    tools/course/.venv/bin/python tools/course/clips.py
    tools/course/.venv/bin/python tools/course/clips.py --only trill --take 2
"""
import argparse
import json
import re
import shutil
import subprocess
import sys

import numpy as np

from analyze import jianpu, merge_repeats
from common import COURSE_SWIFT, MEDIA, OUTPUT, app_patterns, media_file, read_audio
from pitch import notes as find_notes
from pitch import track

PACK = MEDIA / "demo-pack"
SR = 22050
SKIP = {"vowels"}   # the app's own five-vowel check, not a pattern sung in the course


def shape(semis):
    merged = []
    for s in semis:
        if not merged or merged[-1] != s:
            merged.append(s)
    low = min(merged)
    return [s - low for s in merged]


def matches(seq, target, allow_miss=None, max_gap=1.5):
    """Places where seq (merged notes) sings target: list of (index, misses, root).

    Short patterns must match exactly (one wrong note in three could splice two keys together);
    four or five notes may have one misheard note, six or more two. The notes must also be evenly
    spaced, which keeps a match inside one key.
    """
    L, out = len(target), []
    if allow_miss is None:
        allow_miss = 2 if L >= 6 else 1 if L >= 4 else 0
    for i in range(len(seq) - L + 1):
        part = seq[i:i + L]
        if any(part[j + 1]["start"] - part[j]["end"] > max_gap for j in range(L - 1)):
            continue
        iois = [part[j + 1]["start"] - part[j]["start"] for j in range(L - 1)]
        if L >= 3 and max(iois) > 3 * min(iois):
            continue
        root = float(np.median([n["midi"] - t for n, t in zip(part, target)]))
        misses = sum(abs(n["midi"] - (root + t)) > 0.6 for n, t in zip(part, target))
        if misses <= allow_miss:
            out.append((i, misses, int(round(root))))
    return out


def notes_in(f, start, end):
    x = read_audio(f, start, end, SR)
    times, m, c, _ = track(x, SR)
    return merge_repeats(find_notes(times + (start or 0.0), m, c))


def locate(sub, target):
    """Where a fragment's shape sits inside the target shape, or None."""
    n = len(sub)
    for k in range(len(target) - n + 1):
        if [t - target[k] for t in target[k:k + n]] == [s - sub[0] for s in sub]:
            return k
    return None


def cut(f, ex_id, start, end):
    out = PACK / f"{ex_id}.m4a"
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", f"{start:.3f}", "-to", f"{end:.3f}", "-i", str(f),
                    "-vn", "-ac", "1", "-ar", "44100", "-c:a", "aac", "-b:a", "128k", str(out)], check=True)
    return out


def contains_pattern(path, target):
    """Analyse a cut clip again: does it sing the whole pattern?"""
    seq = notes_in(path, None, None)
    if len(target) == 1:
        return any(n["end"] - n["start"] >= 1.0 for n in seq)
    if matches(seq, target):
        return True
    # relaxed: the pattern's notes in order, with passing notes (slides, consonants) between them
    for i, n in enumerate(seq):
        root, j = n["midi"] - target[0], 1
        for m in seq[i + 1:]:
            if j == len(target):
                break
            if abs(m["midi"] - (root + target[j])) <= 0.6:
                j += 1
        if j == len(target):
            return True
    return False


def candidates(seq, target, beat_len, analysis):
    """Takes to try, best first: (how, start, end, root, bpm).

    Whole takes of the pattern come first (exact ones before ones with a misheard note, each in
    time order); then the analysis' fragments widened to the whole pattern.
    """
    out = []
    if len(target) == 1:
        for n in seq:
            if n["end"] - n["start"] >= 1.5:
                out.append(("whole", n["start"], n["end"], int(round(n["midi"])), None))
        return out
    for i, _, root in sorted(matches(seq, target), key=lambda m: (m[1], m[0])):
        part = seq[i:i + len(target)]
        starts = [n["start"] for n in part]
        iois = np.diff(starts[:-1]) if len(part) > 2 else np.diff(starts)
        bpm = round(60 / (float(np.median(iois)) / beat_len)) if len(iois) and np.median(iois) > 0 else None
        out.append(("whole", part[0]["start"], part[-1]["end"], root, bpm))
    frag, takes, fbpm = analysis.get("semitones"), analysis.get("takes") or [], analysis.get("bpm")
    k = locate(shape(frag), target) if frag else None
    if k is not None and fbpm:
        note = 60 / fbpm
        # the missing notes' length, plus half a note of headroom on each side
        before, after = k + 0.5, len(target) - k - len(shape(frag)) + 0.5
        low_pos = k + shape(frag).index(0)          # the fragment's lowest note inside the pattern
        for s, e, frag_root in takes:
            out.append(("widened", s - before * note, e + after * note, int(frag_root) - target[low_pos], round(fbpm * beat_len)))
    return out


def exercise_patterns():
    """Exercise id -> pattern name, from Course.swift."""
    src = COURSE_SWIFT.read_text(encoding="utf-8")
    return dict(re.findall(r'Exercise\(id: "([^"]+)"[^\n]*?pat: "(\w+)"', src))


def main():
    ap = argparse.ArgumentParser(description="按应用里的音型，从本地课程视频截取每个练习完整的一遍示范")
    ap.add_argument("--only", help="只处理这些练习 id，用逗号分隔")
    ap.add_argument("--take", type=int, default=1,
                    help="用找到的第几遍（默认 1；第一遍里有讲解声或钢琴前奏时，换成 2 或 3）")
    ap.add_argument("--pad", type=float, default=0.5, help="片段前后各多留几秒（默认 0.5，宁可多留也不漏音）")
    ap.add_argument("--tries", type=int, default=6, help="核对不通过时，最多换几遍再试（默认 6）")
    a = ap.parse_args()

    if not shutil.which("ffmpeg"):
        sys.exit("找不到 ffmpeg。运行：sudo apt install -y ffmpeg")
    src = OUTPUT / "patterns.json"
    if not src.exists():
        sys.exit("还没有分析结果。先运行 analyze.py。")
    results = json.loads(src.read_text(encoding="utf-8"))
    wanted = set(a.only.split(",")) if a.only else None
    pats, ex_pat = app_patterns(), exercise_patterns()

    PACK.mkdir(parents=True, exist_ok=True)
    manifest_path = PACK / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.exists() else {}
    report = {"whole": [], "widened": [], "rejected": [], "skipped": []}

    for ex_id, r in results.items():
        if wanted and ex_id not in wanted:
            continue
        name = ex_pat.get(ex_id)
        if name in SKIP or name not in pats:
            report["skipped"].append(f"{ex_id}（没有可用的音型模板）")
            continue
        f = media_file(r["video"])
        if not f:
            report["skipped"].append(f"{ex_id}（视频没下载）")
            continue
        semis, beat_len = pats[name]
        target = shape(semis)
        w0, w1 = r["window"]
        seq = notes_in(f, w0, w1)
        cands = candidates(seq, target, beat_len, r.get("pattern") or {})
        if not cands:
            report["rejected"].append(f"{ex_id}（视频里没找到这个音型）")
            continue
        # start at --take, then try the following takes until one passes the check
        tries = cands[a.take - 1:] + cands[:a.take - 1]
        ok, attempt = False, 0
        for attempt, (how, start, end, root, bpm) in enumerate(tries[:a.tries], 1):
            start, end = max(0.0, start - a.pad), end + a.pad + 0.3
            out = cut(f, ex_id, start, end)
            ok = contains_pattern(out, target)
            if ok:
                break
        manifest[ex_id] = {
            "file": out.name, "root": root, "bpm": bpm, "ep": r["ep"], "video": r["video"],
            "start": round(start, 2), "end": round(end, 2),
            # the app uses a clip only when this matches the exercise's pattern
            "pattern": " ".join(jianpu(x) for x in target) if ok else "",
            "verified": ok, "how": how,
        }
        line = f"{ex_id:<10} Ep.{r['ep']:<4} {start:7.1f}–{end:7.1f}s  根音 {root}  音型 {' '.join(jianpu(x) for x in target)}"
        tried = f"（第 {attempt} 次尝试）" if attempt > 1 else ""
        if ok:
            report[how].append(ex_id)
            print(("截取 " if how == "whole" else "补全 ") + line + tried)
        else:
            report["rejected"].append(f"{ex_id}（试了 {attempt} 遍都核对不到完整音型）")
            print("未通过 " + line + f"（试了 {attempt} 遍）")

    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\n完整找到 {len(report['whole'])} 个，按音型补全 {len(report['widened'])} 个，保存在 {PACK}")
    for key, label in (("rejected", "没通过核对"), ("skipped", "跳过")):
        if report[key]:
            print(f"{label}：" + "；".join(report[key]))
    if report["rejected"]:
        print("没通过的可以换一遍再试，例如：--only 练习id --take 2，或加大 --pad。")
    print("在应用里点「导入课程原声示范」，选择这个文件夹。片段只留在你自己的设备上，不要提交到仓库。")


if __name__ == "__main__":
    main()
