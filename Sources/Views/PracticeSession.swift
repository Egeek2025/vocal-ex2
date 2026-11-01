import Foundation
import Observation

/// State of one exercise screen: settings, the running plan, the exercise's recorded demo and the last result.
@Observable
final class PracticeSession {
    enum Mode { case practice, listen, record }

    let exercise: Exercise
    let pattern: Pattern
    var rootA: Int
    var rootB: Int
    var upDown = false
    var bpm: Double

    private(set) var running = false
    private(set) var mode: Mode = .practice
    private(set) var plan: Plan
    private(set) var result: SessionResult? = nil
    private(set) var demo: DemoInfo?
    private(set) var preparing = false
    var notice: String? = nil

    @ObservationIgnored private var loopTask: Task<Void, Never>? = nil
    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var recordWindow: (Double, Double) = (0, 0)

    /// - Parameter maxKeys: limit the number of keys, for short steps of the daily routine
    init(exercise: Exercise, voice: VoiceRange, maxKeys: Int? = nil) {
        self.exercise = exercise
        let p = exercise.pattern ?? Course.patterns["five"]!
        pattern = p
        let r = Planner.defaultRoots(exercise, p, voice)
        rootA = r.0
        rootB = maxKeys.map { min(r.1, r.0 + ($0 - 1) * max(1, p.rootStep)) } ?? r.1
        bpm = p.bpm
        plan = Planner.build(p, roots: [r.0], options: PlanOptions(bpm: p.bpm), start: 0)
        demo = DemoStore.shared.info(for: exercise.id)
    }

    var roots: [Int] { Planner.roots(pattern, from: rootA, to: rootB, upDown: upDown) }

    func preview(_ prefs: PracticePrefs) -> Plan {
        Planner.build(pattern, roots: roots, options: options(prefs, listenOnly: false), start: 0)
    }

    private func options(_ prefs: PracticePrefs, listenOnly: Bool) -> PlanOptions {
        var o = PlanOptions(bpm: bpm)
        o.demo = prefs.demoMode
        o.chordCue = prefs.chordCue
        o.countIn = prefs.countIn
        o.metronome = prefs.metronome
        o.listenOnly = listenOnly
        if prefs.useRecordedDemo, let d = demo { o.demoDuration = d.duration / speed(for: d) }
        return o
    }

    /// Recorded demos follow the session tempo; imported ones keep their own.
    private func speed(for d: DemoInfo) -> Double {
        guard let b = d.bpm, b > 0 else { return 1 }
        return min(2, max(0.5, bpm / b))
    }

    // MARK: running

    /// Runs on the main thread: as a plain async method it would run on a background thread, and the
    /// state it sets (running, preparing, notice) would not reach the screen.
    @MainActor
    func start(_ mode: Mode, model: AppModel) async {
        guard !running, !preparing else { return }
        self.model = model
        let engine = AudioEngine.shared
        var micOK = engine.micEnabled
        if mode != .listen && !micOK { micOK = await engine.enableMic() }
        guard engine.ensureRunning() else {
            notice = "音频没有启动成功，请检查输出设备后再试。"
            return
        }
        if mode == .record && !micOK {
            notice = "录示范需要麦克风权限，请在系统设置的隐私与安全性里打开。"
            return
        }
        notice = (mode == .practice && !micOK) ? "没有麦克风权限，这次只能听示范和跟唱，不会评分。可以在系统设置的隐私与安全性里打开麦克风权限。" : nil

        let prefs = model.prefs
        var o = options(prefs, listenOnly: mode == .listen)
        var roots = self.roots
        if mode == .record {
            // one key, no demo, a four-beat count-in, then the take
            roots = [rootA]
            o.demo = .none
            o.demoDuration = nil
            o.countIn = 4
            o.metronome = false
        }

        // pitch-shift the recorded demo into every key before starting
        var clips: [Int: [Float]] = [:]
        var clipRate = 48000.0
        if mode != .record, prefs.useRecordedDemo, let d = demo, o.demo != .none || mode == .listen {
            preparing = true
            let id = exercise.id, sp = speed(for: d)
            let keys = Array(Set(roots.map { $0 - d.root }))
            let rendered: ([Int: [Float]], Double)? = await Task.detached(priority: .userInitiated) {
                guard let src = DemoStore.shared.load(id: id) else { return nil }
                var out: [Int: [Float]] = [:]
                for k in keys { out[k] = (try? DemoStore.render(src.samples, rate: src.rate, semitones: Double(k), speed: sp)) ?? [] }
                return (out, src.rate)
            }.value
            preparing = false
            if let r = rendered { clips = r.0; clipRate = r.1 } else { o.demoDuration = nil }
        }

        let t0 = engine.now() + 0.4
        plan = Planner.build(pattern, roots: roots, options: o, start: t0)
        let tickVol = 0.06 + 0.2 * prefs.metronomeVolume
        var notes: [ToneNote] = []
        for b in plan.blocks {
            if let c = b.chord {
                for (i, s) in Course.cueChord.enumerated() {
                    notes.append(ToneNote(.piano, m0: Double(b.root + s), t0: c.lowerBound + Double(i) * 0.04, t1: c.upperBound, vol: 0.6 / Double(Course.cueChord.count)))
                }
            }
            if let first = b.listen.first, let last = b.listen.last {
                if let d = demo, let clip = clips[b.root - d.root], !clip.isEmpty {
                    notes.append(ToneNote(.clip, m0: 0, t0: first.t0, t1: last.t1 + 0.3, vol: 1, clip: clip, clipRate: clipRate))
                } else {
                    for s in b.listen {
                        // demo on the piano, the way the course plays the pattern before the singer
                        notes.append(ToneNote(.piano, m0: Double(s.m), m1: s.g.map { Double($0) }, t0: s.t0, t1: s.t1, vol: 0.3))
                    }
                }
            }
            for (i, t) in b.countIn.enumerated() { notes.append(.tick(at: t, accent: i == 0, vol: max(0.12, tickVol))) }
            for (i, t) in b.clicks.enumerated() { notes.append(.tick(at: t, accent: i % 4 == 0, vol: tickVol)) }
            if prefs.accompany && mode == .practice {
                for s in b.sing { notes.append(ToneNote(.piano, m0: Double(s.m), m1: s.g.map { Double($0) }, t0: s.t0, t1: s.t1, vol: 0.12)) }
            }
        }
        engine.clearNotes()
        engine.clearFrames()
        engine.schedule(notes)
        if mode == .record, let b = plan.blocks.first {
            recordWindow = (b.s0 - 0.15, b.s0 + pattern.beats * plan.beat + 0.8)
            engine.startCapture()
        }
        self.mode = mode
        result = nil
        running = true

        let end = mode == .record ? recordWindow.1 : plan.end
        loopTask = Task { @MainActor [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard let self, self.running else { return }
                if engine.now() > end + 0.1 { self.stop(score: true) }
            }
        }
    }

    func stop(score: Bool) {
        guard running else { return }
        running = false
        loopTask?.cancel()
        let engine = AudioEngine.shared
        engine.clearNotes()
        switch mode {
        case .record:
            let raw = engine.stopCapture(from: recordWindow.0, to: recordWindow.1)
            guard score else { notice = "录音已取消。"; return }
            saveTake(raw, rate: engine.inputRate)
        case .listen:
            break
        case .practice:
            guard score, engine.micEnabled, let first = plan.blocks.first else { return }
            let frames = engine.frames(since: first.t0)
            let prev = model?.last(of: exercise.id)
            guard let r = Scorer.score(plan: plan, frames: frames, now: engine.now(), exercise: exercise, pattern: pattern, previous: prev) else { return }
            result = r
            if r.vr > 0.15 {
                model?.add(LogEntry(ex: exercise.id, acc: r.acc, mean: r.mean, std: r.std, keys: r.rows.count, hi: r.hi,
                                    vibRate: r.vib?.rate, vibExt: r.vib?.ext))
            }
        }
    }

    // MARK: demos

    private func saveTake(_ raw: [Float], rate: Double) {
        let x = DemoStore.trimSilence(raw, rate: rate)
        guard Double(x.count) / rate > 0.5 else {
            notice = "没有录到声音。靠近麦克风，在数完拍子后跟着节奏唱，再试一次。"
            return
        }
        let info = DemoInfo(root: rootA, bpm: bpm, duration: Double(x.count) / rate, imported: false)
        do {
            try DemoStore.shared.save(id: exercise.id, samples: x, rate: rate, info: info)
            demo = info
            notice = "示范已保存。之后练习时，示范会用这段录音，并自动移到每个调。"
        } catch {
            notice = "示范没有保存成功：\(error.localizedDescription)"
        }
    }

    func importDemo(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let (raw, rate) = try DemoStore.decodeMono(url)
            let x = DemoStore.trimSilence(raw, rate: rate)
            guard Double(x.count) / rate > 0.5 else { notice = "这个文件里几乎没有声音。"; return }
            let root = DemoStore.detectRoot(x, rate: rate, pattern: pattern) ?? rootA
            let info = DemoInfo(root: root, bpm: nil, duration: Double(x.count) / rate, imported: true)
            try DemoStore.shared.save(id: exercise.id, samples: x, rate: rate, info: info)
            demo = info
            notice = "已导入示范，识别出的根音是 \(Music.name(root))。如果不对，请在下面改正。"
        } catch {
            notice = "这个文件读不出来，换成 m4a、wav 或 mp3 再试。"
        }
    }

    func setDemoRoot(_ root: Int) {
        guard var d = demo else { return }
        d.root = root
        DemoStore.shared.setInfo(d, for: exercise.id)
        demo = d
    }

    func deleteDemo() {
        DemoStore.shared.delete(id: exercise.id)
        // a clip from the video folder's demo pack takes over again when there is one
        demo = DemoStore.shared.info(for: exercise.id)
        notice = demo == nil ? "已删除你的示范，示范改回钢琴。" : "已删除你的示范，示范改回视频文件夹里的老师原声。"
    }

    /// Text and kind for the phase pill at a given moment.
    func phaseText(at now: Double) -> (String, Plan.Phase) {
        guard running else {
            return (preparing ? "正在准备示范…" : "准备好后点「开始练习」", .waiting)
        }
        let (ph, k) = plan.phase(at: now)
        let b = plan.blocks[k]
        let lab = "第 \(k + 1)/\(plan.blocks.count) 个调 · 根音 \(Music.name(b.root))"
        switch ph {
        case .waiting: return ("准备…", ph)
        case .chord: return ("听和弦，进入新的调 · " + lab, ph)
        case .listen: return ((b.listen.first?.cue == true ? "听起始音" : "听示范") + " · " + lab, ph)
        case .countIn(let n): return (mode == .record ? "\(n) · 数完开始录，唱「\(exercise.syl)」" : "\(n) · 预备", ph)
        case .sing: return (mode == .record ? "录音中 · 唱「\(exercise.syl)」" : "跟着唱「\(exercise.syl)」 · " + lab, ph)
        case .rest: return (lab, ph)
        }
    }
}
