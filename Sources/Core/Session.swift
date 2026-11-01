import Foundation

// MARK: - Plan

struct PlannedStep {
    var t0: Double
    var t1: Double
    var m: Int
    var g: Int?
    var ns: Bool
    var l: String?
    var j: String
    var cue: Bool = false
}

struct Block {
    var root: Int
    var t0: Double
    /// key-setting chord played before anything else in this key
    var chord: ClosedRange<Double>?
    var listen: [PlannedStep]
    /// count-in beat times before singing
    var countIn: [Double]
    var s0: Double
    var sing: [PlannedStep]
    /// metronome beat times while singing
    var clicks: [Double]
    var t1: Double
}

struct PlanOptions {
    enum Demo: String, CaseIterable, Identifiable {
        case every, first, none
        var id: String { rawValue }
        var label: String {
            switch self {
            case .every: return "每个调都示范"
            case .first: return "只示范第一个调"
            case .none: return "不示范"
            }
        }
    }

    var bpm: Double
    var demo: Demo = .first
    /// length of a recorded demo in seconds; nil when the demo is played from the pattern
    var demoDuration: Double? = nil
    var chordCue = true
    /// beats counted in before singing; the first key always gets at least four
    var countIn = 2
    var metronome = true
    var listenOnly = false
    /// keys follow each other the way the teacher does it in the video: a one-beat chord, then straight into
    /// the singing, no count-in after the first key and no pause before the next
    var courseRhythm = false
}

struct Plan {
    enum Phase: Equatable {
        case waiting, chord, listen, countIn(Int), sing, rest
    }

    var blocks: [Block]
    var beat: Double
    var end: Double

    func block(at now: Double) -> Block? {
        var cur = blocks.first
        for b in blocks where now >= b.t0 { cur = b }
        return cur
    }

    /// Target pitch (MIDI, fractional during glides) at a moment of the singing phase.
    func target(at now: Double) -> Double? {
        for b in blocks {
            for s in b.sing where now >= s.t0 && now < s.t1 {
                if let g = s.g { return Double(s.m) + Double(g - s.m) * (now - s.t0) / (s.t1 - s.t0) }
                return Double(s.m)
            }
        }
        return nil
    }

    /// Which part of which key is playing at a moment.
    func phase(at now: Double) -> (Phase, Int) {
        guard let first = blocks.first, now >= first.t0 else { return (.waiting, 0) }
        var k = 0
        for (i, b) in blocks.enumerated() where now >= b.t0 { k = i }
        let b = blocks[k]
        if let c = b.chord, c.contains(now) { return (.chord, k) }
        if let l = b.listen.first, now >= l.t0, now < (b.listen.last?.t1 ?? l.t1) { return (.listen, k) }
        if let c0 = b.countIn.first, now >= c0, now < b.s0 {
            let left = b.countIn.count - Int((now - c0) / beat)
            return (.countIn(max(1, left)), k)
        }
        if let s = b.sing.first, now >= s.t0, now < (b.sing.last?.t1 ?? s.t1) { return (.sing, k) }
        return (.rest, k)
    }

    /// Every scheduled click, so scoring can ignore the frames a click may have leaked into.
    var allClicks: [Double] { blocks.flatMap { $0.countIn + $0.clicks }.sorted() }

    /// Keys to show pressed on the keyboard at a moment: the chord that sets the key, the demo note
    /// being played, and the note the singer should be on.
    func keys(at now: Double) -> (playing: Set<Int>, target: Int?) {
        guard let b = block(at: now) else { return ([], nil) }
        if let c = b.chord, c.contains(now) { return (Set(Course.cueChord.map { b.root + $0 }), nil) }
        for s in b.listen where now >= s.t0 && now < s.t1 {
            let m = s.g.map { Double(s.m) + Double($0 - s.m) * (now - s.t0) / (s.t1 - s.t0) } ?? Double(s.m)
            return ([Int(m.rounded())], nil)
        }
        if let t = target(at: now) { return ([], Int(t.rounded())) }
        return ([], nil)
    }
}

enum Planner {
    static func defaultRoots(_ ex: Exercise, _ p: Pattern, _ v: VoiceRange) -> (Int, Int) {
        if p.fixed {
            let r = Int((Double(v.lo) + Double(v.hi - v.lo) * 0.4).rounded())
            return (r, r)
        }
        var a = v.lo + 2 - p.minSemitone
        var b = v.hi - 1 - p.maxSemitone
        switch ex.zone {
        case .low: b = min(b, v.lo + 13 - p.maxSemitone)
        case .high:
            a = max(a, v.lo + 9)
            b = v.hi + 2 - p.maxSemitone
        case .full: break
        }
        if b < a { b = a }
        if b - a > 13 { b = a + 13 }
        return (a, b)
    }

    static func roots(_ p: Pattern, from a: Int, to b: Int, upDown: Bool) -> [Int] {
        if p.fixed { return [a] }
        let lo = min(a, b), hi = max(a, b), st = max(1, p.rootStep)
        var out = Array(stride(from: lo, through: hi, by: st))
        if upDown, let top = out.last {
            out += Array(stride(from: top - st, through: lo, by: -st))
        }
        return out
    }

    static func layout(_ steps: [Step], start: Double, beat: Double, root: Int) -> [PlannedStep] {
        var t = start
        return steps.map { s in
            let d = s.b * beat
            let o = PlannedStep(t0: t, t1: t + d, m: root + s.s, g: s.g.map { root + $0 }, ns: s.ns || s.g != nil, l: s.l, j: s.j)
            t += d
            return o
        }
    }

    /// Lay out a session the way a warm-up track runs: for each key a chord sets the key,
    /// the demo plays, a count-in leads in, and the singer sings over the metronome.
    /// The tempo at which one key (a one-beat chord plus the pattern) takes as long as in the video.
    static func courseBPM(_ p: Pattern, keySeconds: Double) -> Double {
        min(200, max(50, (60 * (1 + p.beats) / keySeconds).rounded()))
    }

    static func build(_ p: Pattern, roots: [Int], options o: PlanOptions, start: Double) -> Plan {
        let beat = 60 / o.bpm, pb = p.beats
        var t = start
        var blocks: [Block] = []
        for (k, root) in roots.enumerated() {
            let b0 = t
            var chord: ClosedRange<Double>? = nil
            if o.chordCue {
                let len = o.courseRhythm ? 1.0 : 2.0
                chord = t...(t + len * beat)
                t += len * beat
            }
            var listen: [PlannedStep] = []
            let demo = o.listenOnly || o.demo == .every || (o.demo == .first && k == 0)
            if demo {
                let natural = pb * beat
                let d = o.demoDuration ?? natural
                listen = layout(p.steps, start: t, beat: beat * d / natural, root: root)
                t += d + beat * 0.5
            } else if !o.chordCue {
                listen = [PlannedStep(t0: t, t1: t + beat * 1.5, m: root, g: nil, ns: true, l: nil, j: "1", cue: true)]
                t += beat * 1.5
            }
            var countIn: [Double] = [], sing: [PlannedStep] = [], clicks: [Double] = []
            let s0: Double
            if o.listenOnly {
                s0 = t
            } else {
                let n = k == 0 ? max(4, o.countIn) : (o.courseRhythm ? 0 : max(1, o.countIn))
                countIn = (0..<n).map { t + Double($0) * beat }
                t += Double(n) * beat
                s0 = t
                sing = layout(p.steps, start: t, beat: beat, root: root)
                if o.metronome { clicks = (0..<Int(pb.rounded(.up))).map { s0 + Double($0) * beat } }
                t += pb * beat
            }
            if !o.courseRhythm { t += beat * 0.75 }
            blocks.append(Block(root: root, t0: b0, chord: chord, listen: listen, countIn: countIn, s0: s0, sing: sing, clicks: clicks, t1: t))
        }
        return Plan(blocks: blocks, beat: beat, end: t)
    }
}

// MARK: - Scoring

struct CentPoint { var t: Double; var c: Double }

struct StepScore {
    var step: PlannedStep
    var vr: Double
    var sung: Bool
    var acc: Double
    var mean: Double
    var std: Double
    var hi: Double?
    var fr: [CentPoint]
}

struct BlockScore: Identifiable {
    var id: Int { root * 1000 + order }
    var order: Int
    var root: Int
    var steps: [StepScore]
    var acc: Double
    var mean: Double
    var std: Double
    var vr: Double
    var hi: Double?
}

struct Vibrato { var rate: Double; var ext: Double }

struct SessionResult {
    var rows: [BlockScore]
    var acc: Double
    var mean: Double
    var std: Double
    var vr: Double
    var hi: Double?
    var vib: Vibrato?
    var feedback: [String]
    var previous: LogEntry?
}

enum Scorer {
    static func scoreStep(_ s: PlannedStep, frames: [Frame], clicks: [Double] = []) -> StepScore? {
        if s.ns { return nil }
        let d = s.t1 - s.t0, a = s.t0 + max(0.12, 0.3 * d), z = s.t1 - 0.03
        let near = clicks.filter { $0 > a - 0.1 && $0 < z }
        var n = 0
        var cs: [Double] = [], his: [Double] = [], fr: [CentPoint] = []
        for f in frames where f.t >= a && f.t <= z {
            if near.contains(where: { f.t >= $0 - 0.01 && f.t < $0 + 0.09 }) { continue }
            n += 1
            if f.voiced {
                let c = Music.fold((f.midi - Double(s.m)) * 100)
                cs.append(c)
                fr.append(CentPoint(t: f.t, c: c))
                if let h = f.hi { his.append(h) }
            }
        }
        let vr = n > 0 ? Double(cs.count) / Double(n) : 0
        let ok = cs.filter { abs($0) <= 25 }.count
        let sung = vr >= 0.3
        return StepScore(step: s, vr: vr, sung: sung, acc: sung && !cs.isEmpty ? Double(ok) / Double(cs.count) : 0,
                         mean: cs.mean, std: cs.stdDev, hi: his.isEmpty ? nil : his.mean, fr: fr)
    }

    static func vibrato(_ fr: [CentPoint]) -> Vibrato? {
        guard fr.count >= 30, let first = fr.first, let last = fr.last else { return nil }
        let dur = last.t - first.t
        guard dur >= 1 else { return nil }
        let r: [Double] = fr.map { f in
            var s = 0.0, n = 0.0
            for g in fr where abs(g.t - f.t) <= 0.2 { s += g.c; n += 1 }
            return f.c - s / n
        }
        var cross = 0, lastSign = 0
        for v in r where abs(v) >= 3 {
            let g = v > 0 ? 1 : -1
            if lastSign != 0 && g != lastSign { cross += 1 }
            lastSign = g
        }
        let so = r.sorted()
        let p95 = so[Int(0.95 * Double(so.count - 1))], p5 = so[Int(0.05 * Double(so.count - 1))]
        return Vibrato(rate: Double(cross) / 2 / dur, ext: (p95 - p5) / 2)
    }

    static func score(plan: Plan, frames: [Frame], now: Double, exercise: Exercise, pattern: Pattern, previous: LogEntry?) -> SessionResult? {
        let blocks = plan.blocks.filter { !$0.sing.isEmpty && $0.sing[0].t0 < now }
        guard !blocks.isEmpty else { return nil }
        let clicks = plan.allClicks
        let rows: [BlockScore] = blocks.enumerated().map { i, b in
            let st = b.sing.compactMap { scoreStep($0, frames: frames, clicks: clicks) }
            let sung = st.filter { $0.sung }
            let his = sung.compactMap { $0.hi }
            return BlockScore(order: i, root: b.root, steps: st, acc: st.map { $0.acc }.mean, mean: sung.map { $0.mean }.mean,
                              std: sung.map { $0.std }.mean, vr: st.map { $0.vr }.mean, hi: his.isEmpty ? nil : his.mean)
        }
        let allSung = rows.flatMap { $0.steps.filter { $0.sung } }
        let acc = rows.map { $0.acc }.mean
        let mean = allSung.map { $0.mean }.mean
        let std = allSung.map { $0.std }.mean
        let vr = rows.map { $0.vr }.mean
        let his = allSung.compactMap { $0.hi }
        let hi: Double? = his.isEmpty ? nil : his.mean
        var vib: Vibrato? = nil
        if exercise.metric == .vibrato || exercise.metric == .straight {
            let vs = allSung.compactMap { vibrato($0.fr) }
            if !vs.isEmpty { vib = Vibrato(rate: vs.map { $0.rate }.mean, ext: vs.map { $0.ext }.mean) }
        }
        let fb = feedback(rows: rows, acc: acc, mean: mean, std: std, vr: vr, hi: hi, vib: vib, previous: previous, exercise: exercise, pattern: pattern)
        return SessionResult(rows: rows, acc: acc, mean: mean, std: std, vr: vr, hi: hi, vib: vib, feedback: fb, previous: previous)
    }

    static func feedback(rows: [BlockScore], acc: Double, mean: Double, std: Double, vr: Double, hi: Double?, vib: Vibrato?,
                         previous: LogEntry?, exercise: Exercise, pattern: Pattern) -> [String] {
        var f: [String] = []
        if vr < 0.4 {
            f.append("有不少音没有检测到声音。靠近麦克风一点、唱得稍响一点，或者检查输入设备是不是选对了。")
        }
        if acc >= 0.8 {
            f.append("音准很稳，大部分音都在 ±25 音分以内。可以试着提高速度，或者往上多走两个调。")
        } else if acc >= 0.6 {
            f.append("音准基本到位，还有一些音没唱准。看下面每个调的分数，找出开始变差的地方。")
        } else if vr >= 0.4 {
            f.append("音准还需要加强。先把速度调慢、只练最舒服的几个调，每个音先在心里听准再唱（参考 Ep. 34）。")
        }
        if mean > 15 {
            f.append("整体偏高约 \(Int(mean.rounded())) 音分。偏高常和喉头上提、用力过猛有关，试着放松下巴、降低一点音量（参考 Ep. 82、Ep. 116）。")
        } else if mean < -15 {
            f.append("整体偏低约 \(Int((-mean).rounded())) 音分。偏低常见于气息支持不够或音头没唱到位，起音时想着「从上面落到音上」（参考 Ep. 92、Ep. 34）。")
        }
        if rows.count >= 4 {
            let first = rows.prefix(2).map { $0.acc }.mean
            for r in rows.dropFirst(2) where r.acc < first - 0.2 && r.root > rows[0].root {
                f.append("从根音 \(Music.name(r.root)) 这个调开始准确率明显下降，最高音约在 \(Music.name(r.root + pattern.maxSemitone))。这一带可能是你的换声点，可以回看 Ep. 45 的换声点练习，在这里减轻音量、收窄元音。")
                break
            }
        }
        // weakest position in the pattern
        var accBy: [Int: [Double]] = [:], meanBy: [Int: [Double]] = [:], labelBy: [Int: PlannedStep] = [:]
        for r in rows {
            for (i, s) in r.steps.enumerated() {
                accBy[i, default: []].append(s.acc)
                if s.sung { meanBy[i, default: []].append(s.mean) }
                labelBy[i] = s.step
            }
        }
        if let worst = accBy.min(by: { $0.value.mean < $1.value.mean }), acc < 0.85, worst.value.mean < acc - 0.1, let st = labelBy[worst.key] {
            let m = (meanBy[worst.key] ?? []).mean
            f.append("音型里第 \(worst.key + 1) 个音（简谱「\(st.j)」\(st.l.map { "，" + $0 } ?? "")）最常唱不准，平均\(m >= 0 ? "偏高" : "偏低") \(Int(abs(m).rounded())) 音分。单独把这一步慢慢唱几遍。")
        }
        if std > 30 && exercise.metric != .vibrato && exercise.pat != "vib" {
            f.append("长音里的音高抖动比较大（平均波动 \(Int(std.rounded())) 音分）。保持气流稳定，不要在音中间推气。")
        }
        if exercise.metric == .bright, let hi {
            var t = String(format: "这次的明亮度平均 %.1f dB。", hi)
            if let p = previous?.hi {
                let d = hi - p
                t += abs(d) < 1 ? "和上次差不多。" : d > 0 ? String(format: "比上次亮了 %.1f dB。", d) : String(format: "比上次暗了 %.1f dB。", -d)
            }
            t += "这个值越高说明 2–4 kHz 的「穿透力」频段越强；只和自己在同样的麦克风和距离下比较才有意义。"
            f.append(t)
        }
        if let vib {
            if exercise.metric == .straight {
                f.append(vib.ext < 15 ? "直音保持得很好，颤动幅度约 \(Int(vib.ext.rounded())) 音分。"
                         : "长音里有约 \(Int(vib.ext.rounded())) 音分的颤动。直音练习的目标是把它压到 15 音分以内：气流保持平稳，不要摇喉咙。")
            } else {
                var t = String(format: "颤音频率约 %.1f 次/秒，幅度约 ±%d 音分。", vib.rate, Int(vib.ext.rounded()))
                if vib.ext < 15 { t += "几乎还没有颤音，先回到 Ep. 30 的交替音练习。" }
                else if vib.rate >= 4.5 && vib.rate <= 7.5 && vib.ext <= 100 { t += "频率和幅度都在常见的健康范围内。" }
                else if vib.rate < 4.5 { t += "频率偏慢，听起来会像「晃」，可以用交替音练习把速度提上去。" }
                else if vib.rate > 7.5 { t += "频率偏快，可能有些紧张，试着放松喉咙和下巴。" }
                else { t += "幅度偏大，可以试着让颤音更细一些。" }
                f.append(t)
            }
        }
        return f
    }
}

// MARK: - File analysis

struct NoteSegment: Identifiable {
    var id: Double { t0 }
    var t0: Double
    var t1: Double
    var m: Double
    var dev: Double
    var vib: Vibrato?
    var hi: Double?
}

struct FileReport {
    var duration: Double
    var frames: [Frame]
    var notes: [NoteSegment]
    var lo: Double
    var hi: Double
    var meanDev: Double
    var vibRate: Double?
    var vibExt: Double?
    var vibCount: Int
    var brightness: Double?
}

enum FileAnalyzer {
    static func analyze(samples x: [Float], sampleRate sr: Double, progress: (Double) -> Void) -> FileReport? {
        let w = 2048, hop = max(1, Int((sr / 80).rounded()))
        guard x.count > w else { return nil }
        let anz = PitchAnalyzer(windowSize: w)
        let total = (x.count - w) / hop
        var frames: [Frame] = []
        frames.reserveCapacity(total)
        for i in 0..<total {
            let r = anz.analyze(x, offset: i * hop, sampleRate: sr)
            let voiced = r.f0 > 0 && r.clarity > 0.8 && r.rms > 0.004
            frames.append(Frame(t: Double(i * hop + w / 2) / sr, f0: r.f0, clarity: r.clarity, rms: r.rms, hi: r.hi,
                                voiced: voiced, midi: voiced ? Music.midi(r.f0) : 0))
            if i % 400 == 0 { progress(Double(i) / Double(max(1, total))) }
        }
        let v = frames.filter { $0.voiced }
        guard v.count >= 20 else { return nil }
        let ms = v.map { $0.midi }.sorted()
        let lo = ms[Int(Double(ms.count) * 0.03)], hi = ms[min(ms.count - 1, Int(Double(ms.count) * 0.97))]
        let notes = segment(frames)
        let vibs = notes.compactMap { $0.vib }.filter { $0.ext >= 15 }
        let his = v.compactMap { $0.hi }
        return FileReport(duration: Double(x.count) / sr, frames: frames, notes: notes, lo: lo, hi: hi,
                          meanDev: notes.map { abs($0.dev) }.mean,
                          vibRate: vibs.isEmpty ? nil : vibs.map { $0.rate }.mean,
                          vibExt: vibs.isEmpty ? nil : vibs.map { $0.ext }.mean,
                          vibCount: vibs.count, brightness: his.isEmpty ? nil : his.mean)
    }

    /// Stable sung notes: runs of voiced frames that stay within ±50 cents, at least 0.3 s long.
    static func segment(_ fr: [Frame]) -> [NoteSegment] {
        var notes: [NoteSegment] = []
        var i = 0
        while i < fr.count {
            if !fr[i].voiced { i += 1; continue }
            var j = i
            var ms = [fr[i].midi]
            while j + 1 < fr.count && fr[j + 1].voiced && abs(fr[j + 1].midi - Array(ms.suffix(8)).median) < 0.5 {
                j += 1
                ms.append(fr[j].midi)
            }
            let dur = fr[j].t - fr[i].t
            if dur >= 0.3 {
                let md = ms.median
                let seg = Array(fr[i...j])
                let his = seg.compactMap { $0.hi }
                notes.append(NoteSegment(t0: fr[i].t, t1: fr[j].t, m: md, dev: (md - md.rounded()) * 100,
                                         vib: dur >= 1 ? Scorer.vibrato(seg.map { CentPoint(t: $0.t, c: ($0.midi - md) * 100) }) : nil,
                                         hi: his.isEmpty ? nil : his.mean))
            }
            i = j + 1
        }
        return notes
    }
}
