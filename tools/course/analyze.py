#!/usr/bin/env python3
"""Find each exercise's pattern in the downloaded course videos.

For every exercise in Course.swift it takes the video chapter that starts at the exercise's
timestamp, tracks the pitch, splits the singing into phrases, and looks for the interval
sequence that repeats most often (exercises go up a key at a time, so the same shape repeats
transposed). It writes:

    tools/course/output/patterns.json   machine-readable results
    tools/course/output/report.md       one section per exercise, with the subtitle text

    tools/course/.venv/bin/python tools/course/analyze.py                 # all exercises with a downloaded video
    tools/course/.venv/bin/python tools/course/analyze.py --only trill,ng # some exercises
    tools/course/.venv/bin/python tools/course/analyze.py --window 120    # seconds when a video has no chapters
"""
import argparse
import json
import re
import sys
from collections import defaultdict

import numpy as np

from common import OUTPUT, exercises, info_json, media_file, read_audio, subtitle_file
from pitch import notes as find_notes
from pitch import track

SR = 22050
DEGREE = {0: "1", 2: "2", 4: "3", 5: "4", 7: "5", 9: "6", 11: "7"}


def jianpu(semi):
    """Semitones above the root -> jianpu text: 8 = 1', 12 below = 1."""
    octave, pc = divmod(semi, 12)
    if pc in DEGREE:
        d = DEGREE[pc]
    else:
        d = "#" + DEGREE[pc - 1]
    return d + ("'" * octave if octave > 0 else "." * -octave)


def chapter_window(info, t, fallback):
    """The chapter starting at t (±5 s), else t .. t + fallback."""
    for ch in (info or {}).get("chapters") or []:
        if abs(ch.get("start_time", -99) - t) <= 5:
            return ch["start_time"], ch["end_time"], ch.get("title", "")
    return t, t + fallback, ""


def merge_repeats(ph):
    """Join consecutive notes on the same semitone (a held note broken by vibrato or a consonant)."""
    out = []
    for n in ph:
        if out and round(n["midi"]) == round(out[-1]["midi"]) and n["start"] - out[-1]["end"] < 0.12:
            out[-1] = {"start": out[-1]["start"], "end": n["end"], "midi": (out[-1]["midi"] + n["midi"]) / 2}
        else:
            out.append(dict(n))
    return out


def is_repeated(sig):
    """True when sig is two or more transposed copies of a shorter shape (two keys glued together)."""
    L = len(sig)
    for k in range(2, L // 2 + 1):
        if L % k:
            continue
        p = L // k
        base = [x - sig[0] for x in sig[:p]]
        if all([x - sig[j * p] for x in sig[j * p:(j + 1) * p]] == base for j in range(1, k)):
            return True
    return False


def contains(sig, part):
    """True when the shape `part` appears inside `sig` (at any transposition)."""
    n = len(part)
    for i in range(len(sig) - n + 1):
        if all(sig[i + j] - sig[i] == part[j] - part[0] for j in range(n)):
            return True
    return False


def find_pattern(ns, max_len=12, min_keys=3, keep=0.3):
    """The interval sequence that repeats key after key.

    Warm-up exercises sing one shape, then the same shape a semitone (sometimes a whole tone)
    higher or lower. Every run of notes is a candidate and is scored by the longest chain of its
    occurrences whose roots move steadily by 1-3 semitones. Short fragments chain most easily
    (a misheard note breaks a long shape but not its last two notes), so the best fragment is only
    a seed: the result is the longest shape that contains the seed, still repeats in at least
    `keep` of the seed's keys, and is no longer than the usual distance between two keys (so it
    cannot run on into the next key).
    """
    seq = merge_repeats(ns)
    if len(seq) < 3:
        return None
    pitch = [round(n["midi"]) for n in seq]
    occ = defaultdict(list)
    for L in range(2, max_len + 1):
        for i in range(len(seq) - L + 1):
            sig = tuple(p - pitch[i] for p in pitch[i:i + L])
            occ[sig].append(i)
    found = {}
    for sig, pos in occ.items():
        if len(pos) < min_keys or len(set(sig)) < 2 or is_repeated(sig):
            continue
        L = len(sig)
        chain_len = {}
        prev = {}
        for a in pos:
            chain_len[a], prev[a] = 1, None
            for b in pos:
                if b + L > a:
                    break
                step = pitch[a] - pitch[b]
                gap = seq[a]["start"] - seq[b + L - 1]["end"]
                if 1 <= abs(step) <= 3 and gap < 8 and chain_len[b] + 1 > chain_len[a]:
                    chain_len[a], prev[a] = chain_len[b] + 1, b
        end = max(chain_len, key=chain_len.get)
        keys = chain_len[end]
        if keys < min_keys:
            continue
        chain = [end]
        while prev[chain[-1]] is not None:
            chain.append(prev[chain[-1]])
        found[sig] = (keys, sorted(chain))
    if not found:
        return None
    seed = max(found, key=lambda s: (found[s][0] * len(s), len(s)))
    need = max(min_keys, keep * found[seed][0])
    seed_chain = found[seed][1]
    spacing = int(np.median(np.diff(seed_chain))) if len(seed_chain) > 1 else max_len
    grown = [s for s in found if found[s][0] >= need and len(s) <= spacing and contains(s, seed)] or [seed]
    sig = max(grown, key=lambda s: (len(s), found[s][0]))
    keys, chain = found[sig]
    L = len(sig)
    low = min(sig)
    semis = [x - low for x in sig]
    groups = [seq[i:i + L] for i in chain]
    onsets = np.median(np.array([[n["start"] - g[0]["start"] for n in g] for g in groups]), axis=0)
    durs = np.median(np.array([[n["end"] - n["start"] for n in g] for g in groups]), axis=0)
    iois = np.diff(onsets)
    beat = float(np.median(iois)) if len(iois) else float(np.median(durs))
    beats = [max(0.25, round(float(x) / beat * 4) / 4) if beat > 0 else 1 for x in np.append(iois, durs[-1])]
    roots = [pitch[i] - (sig[0] - low) for i in chain]
    direction = "上行" if roots[-1] > roots[0] else "下行" if roots[-1] < roots[0] else "不变"
    return {
        "semitones": semis,
        "jianpu": " ".join(jianpu(x) for x in semis),
        "beats": beats,
        "bpm": round(60 / beat) if beat > 0 else None,
        "keys_in_a_row": keys,
        "direction": direction,
        "roots": [int(r) for r in roots],
        "first_root_note": _name(roots[0]),
        "chain_starts": [round(g[0]["start"], 2) for g in groups],
        # every key of the chain as [start, end, root]; clips.py cuts a demo from these
        "takes": [[round(g[0]["start"], 2), round(g[-1]["end"], 2), int(r)] for g, r in zip(groups, roots)],
        "notes_total": len(seq),
        "coverage": round(keys * L / len(seq), 2),
    }


def _name(m):
    names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    return names[m % 12] + str(m // 12 - 1)


def piano_notes(x, sr, fmin=55.0, fmax=1500.0, top=14):
    """Notes sounding together in a short stretch of audio: (midi, strength), overtones removed.

    Spectral peaks are merged per semitone (the strongest peak stands for the key) and taken lowest
    first. Piano overtones are weak, so a peak on a whole-number multiple of a lower note counts as
    that note's overtone only when it is well below it; a real octave or fifth in the chord is louder.
    """
    if len(x) < sr * 0.3:
        return []
    spec = np.abs(np.fft.rfft(x * np.hanning(len(x)), 4 * len(x)))
    freqs = np.fft.rfftfreq(4 * len(x), 1 / sr)
    sel = np.where((freqs >= fmin) & (freqs <= fmax))[0]
    s, fs = spec[sel], freqs[sel]
    if not len(s):
        return []
    floor = 0.05 * s.max()
    keys = {}
    for i in range(1, len(s) - 1):
        if s[i] > floor and s[i] >= s[i - 1] and s[i] >= s[i + 1]:
            m = int(round(69 + 12 * np.log2(fs[i] / 440)))
            if m not in keys or s[i] > keys[m][1]:
                keys[m] = (fs[i], s[i])
    peaks = sorted(keys.values(), key=lambda p: -p[1])[:top]
    found = []
    for f, a in sorted(peaks):
        overtone = False
        for f0, a0 in found:
            k = round(f / f0)
            if k >= 2 and abs(1200 * np.log2(f / (k * f0))) < 35 and a < 0.4 * a0:
                overtone = True
                break
        if not overtone:
            found.append((f, a))
    return [(69 + 12 * np.log2(f / 440), a) for f, a in found]


def cue_chord(f, takes, max_keys=8, before=1.6):
    """What the piano plays just before each sung take, as semitones from that key's root.

    Returns the notes heard before at least half of the takes, with how often each was heard.
    """
    counts, used = defaultdict(int), 0
    for s, _, root in takes[:max_keys]:
        a, b = max(0.0, s - before), s - 0.12
        if b - a < 0.4:
            continue
        notes = piano_notes(read_audio(f, a, b, SR), SR)
        if not notes:
            continue
        used += 1
        strongest = max(n[1] for n in notes)
        for m, amp in notes:
            if amp >= 0.2 * strongest:
                counts[int(round(m)) - root] += 1
    if not used:
        return None
    offsets = sorted(o for o, c in counts.items() if c >= used / 2)
    return {"offsets": offsets, "takes": used, "counts": {str(o): c for o, c in sorted(counts.items())}}


def offset_name(o):
    """Semitones from the root as jianpu with octave marks, e.g. -12 -> 1. and 16 -> 3'."""
    return jianpu(o)


def transcript(vtt, a, b):
    """Subtitle text between two times, with the rolling repeats of auto captions removed."""
    if not vtt:
        return ""
    text = vtt.read_text(encoding="utf-8", errors="replace")
    lines, seen = [], set()
    for start, body in re.findall(r"(\d+:\d+:\d+\.\d+) --> [^\n]*\n(.*?)(?:\n\n|\Z)", text, re.S):
        h, m, s = start.split(":")
        t = int(h) * 3600 + int(m) * 60 + float(s)
        if t < a - 3 or t > b:
            continue
        for line in body.splitlines():
            line = re.sub(r"<[^>]+>", "", line).strip()
            if line and line not in seen:
                seen.add(line)
                lines.append(line)
    return " ".join(lines)


NUMBER_WORDS = {"one": "1", "two": "2", "three": "3", "four": "4", "five": "5", "six": "6",
                "seven": "7", "eight": "8", "nine": "9"}


def stated_patterns(text):
    """Patterns Justin says out loud, e.g. "on an 8-5-1" or "one three five eight"."""
    t = re.sub(r"\b(%s)\b" % "|".join(NUMBER_WORDS), lambda m: NUMBER_WORDS[m.group(1).lower()], text, flags=re.I)
    found = re.findall(r"\b([1-9](?:\s*[-–]\s*[1-9]){1,11})\b", t)
    found += [re.sub(r"\s+", "-", m) for m in re.findall(r"\b([1-9](?:\s+[1-9]){2,11})\b", t)]
    out = []
    for f in found:
        f = re.sub(r"\s*[-–]\s*", "-", f)
        if f not in out:
            out.append(f)
    return out


def sung_syllables(text):
    """What is sung between ♪ marks, e.g. "NG - AH - AH - AH"."""
    out = []
    for m in re.findall(r"♪\s*([^♪\[\]]{1,60}?)\s*♪", text):
        m = m.strip()
        if m and m not in out and not re.search(r"[a-z]{4,} [a-z]{4,} [a-z]{4,}", m):
            out.append(m)
    return out


def main():
    ap = argparse.ArgumentParser(description="从本地课程视频里分析每个练习的音型")
    ap.add_argument("--only", help="只分析这些练习 id，用逗号分隔，例如 trill,ng")
    ap.add_argument("--window", type=float, default=120, help="视频没有章节信息时，从练习时间点起分析多少秒（默认 120）")
    ap.add_argument("--max-window", type=float, default=240, help="一个练习最多分析多少秒（默认 240）")
    a = ap.parse_args()

    wanted = set(a.only.split(",")) if a.only else None
    results, missing = {}, []
    for ex in exercises():
        if wanted and ex["id"] not in wanted:
            continue
        if ex["kind"] != "pitch" or not ex["video"]:
            continue
        f = media_file(ex["video"])
        if not f:
            missing.append(f'Ep. {ex["ep"]} {ex["id"]}')
            continue
        info = info_json(ex["video"])
        start, end, title = chapter_window(info, ex["t"], a.window)
        end = min(end, start + a.max_window)
        print(f'分析 {ex["id"]:<10} Ep.{ex["ep"]:<4} {start:6.0f}–{end:6.0f}s  {title}', flush=True)
        x = read_audio(f, start, end, SR)
        times, m, c, r = track(x, SR)
        ns = find_notes(times + start, m, c)
        pat = find_pattern(ns)
        cue = cue_chord(f, pat["takes"]) if pat and pat.get("takes") else None
        text = transcript(subtitle_file(ex["video"]), start, end)
        results[ex["id"]] = {
            "ep": ex["ep"], "name": ex["name"], "app_syllable": ex["syl"], "app_pattern": ex["pattern"],
            "video": ex["video"], "chapter": title, "window": [round(start, 1), round(end, 1)],
            "notes_found": len(ns), "pattern": pat, "cue": cue,
            "stated_patterns": stated_patterns(text), "sung_syllables": sung_syllables(text),
            "transcript": text,
        }

    OUTPUT.mkdir(parents=True, exist_ok=True)
    (OUTPUT / "patterns.json").write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    write_report(results, missing)
    print(f"\n已写入 {OUTPUT / 'report.md'} 和 patterns.json")
    if missing:
        print("这些练习的视频还没下载：", "、".join(missing))


def write_report(results, missing):
    out = ["# 课程练习音型分析", "",
           "由 `tools/course/analyze.py` 从本地下载的课程视频自动生成。简谱以音型最低音为 1，`'` 表示高八度。",
           "「连续调数」是同一音型一个调接一个调重复的次数，越多越可信；3 次以下的结果请对照视频核对。",
           "「字幕里说的音型」和「唱的音节」直接取自字幕，比音频分析更可靠。", ""]
    cues = defaultdict(list)
    for ex_id, r in results.items():
        if r.get("cue") and r["cue"]["offsets"]:
            cues[tuple(r["cue"]["offsets"])].append(ex_id)
    if cues:
        out += ["## 开唱前的钢琴：全部练习汇总", "",
                "每个调开唱前约 1.5 秒里钢琴弹的音，相对这个调的根音（`.` 表示低八度，`'` 表示高八度）。", ""]
        for offs, ids in sorted(cues.items(), key=lambda kv: -len(kv[1])):
            out.append(f'- **{" ".join(offset_name(o) for o in offs)}**（半音 {list(offs)}）：{len(ids)} 个练习，{"、".join(ids)}')
        out.append("")
    for ex_id, r in results.items():
        p = r["pattern"]
        out.append(f'## {r["name"]}（`{ex_id}`，Ep. {r["ep"]}）')
        out.append(f'- 分析片段：{r["window"][0]:.0f}–{r["window"][1]:.0f} 秒' + (f'，章节「{r["chapter"]}」' if r["chapter"] else ""))
        out.append(f'- 应用里现在的设置：音节 `{r["app_syllable"]}`，音型 `{r["app_pattern"]}`')
        if r["stated_patterns"]:
            out.append("- 字幕里说的音型：" + "、".join(f"**{x}**" for x in r["stated_patterns"]))
        if r["sung_syllables"]:
            out.append("- 字幕里唱的音节：" + "；".join(f"`{x}`" for x in r["sung_syllables"]))
        if p:
            out.append(f'- 音频识别的音型：**{p["jianpu"]}**（半音：{p["semitones"]}，拍数：{p["beats"]}）')
            out.append(f'- 连续 {p["keys_in_a_row"]} 个调{p["direction"]}重复；速度约 {p["bpm"]} BPM；第一个调的根音 {p["first_root_note"]}；覆盖 {p["coverage"]:.0%} 的音')
        c = r.get("cue")
        if c and c["offsets"]:
            out.append(f'- 开唱前的钢琴（相对根音）：**{" ".join(offset_name(o) for o in c["offsets"])}**'
                       f'（{c["takes"]} 个调里统计，半音 {c["offsets"]}）')
        else:
            out.append("- 音频里没有找到一个调接一个调重复的音型，请对照视频核对。")
        if r["transcript"]:
            out.append(f'- 字幕：{r["transcript"][:1500]}')
        out.append("")
    if missing:
        out += ["## 未下载的视频", "", "、".join(missing), ""]
    (OUTPUT / "report.md").write_text("\n".join(out), encoding="utf-8")


if __name__ == "__main__":
    sys.exit(main())
