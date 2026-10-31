import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

// MARK: - Breath timer (hiss, SH-ZH)

struct BreathTimerView: View {
    @Environment(AppModel.self) private var model
    let exercise: Exercise
    @State private var phase = "准备"
    @State private var seconds = 0.0
    @State private var running = false
    @State private var resultText: String? = nil
    @State private var task: Task<Void, Never>? = nil
    @State private var manualStart: Date? = nil

    var body: some View {
        let best = model.best(of: exercise.id)
        VStack(spacing: 14) {
            Text(phase).font(.title2.weight(.bold))
            Text(String(format: "%.1f", seconds)).font(.system(size: 72, weight: .bold, design: .monospaced))
            ProgressView(value: min(1, seconds / max(best, 30)))
                .frame(maxWidth: 420)
            Text((AudioEngine.shared.micEnabled ? "点「开始」后吸满气，出声时自动开始计时，声音停下自动结束。" : "点「开始」会请求麦克风权限；没有麦克风时改为手动计时。")
                 + (best > 0 ? String(format: " 你的最好成绩是 %.1f 秒。", best) : ""))
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack {
                Button("开始") { begin() }.buttonStyle(.borderedProminent).disabled(running)
                Button("停止") { finishManually() }.buttonStyle(.bordered).disabled(!running)
            }
            if let r = resultText {
                Text(r).font(.callout).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical)
        .onDisappear { task?.cancel(); running = false }
    }

    private func begin() {
        running = true
        seconds = 0
        resultText = nil
        task = Task { @MainActor in
            let engine = AudioEngine.shared
            let micOK = await engine.enableMic()
            engine.ensureRunning()
            if !micOK {
                manualStart = Date()
                phase = "计时中（手动）"
                while running && !Task.isCancelled {
                    seconds = Date().timeIntervalSince(manualStart ?? Date())
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
                return
            }
            phase = "先安静 1 秒…"
            var floor: [Double] = []
            let t0 = engine.now()
            while engine.now() - t0 < 0.8 {
                if let f = engine.latest().last { floor.append(f.rms) }
                try? await Task.sleep(nanoseconds: 30_000_000)
            }
            let thr = max(0.006, floor.median * 3)
            phase = "吸满气，开始发声"
            var start: Double? = nil
            var quietSince: Double? = nil
            while running && !Task.isCancelled {
                let now = engine.now()
                let rms = engine.latest().last?.rms ?? 0
                if start == nil {
                    if rms > thr { start = now; phase = "计时中" }
                } else if let s = start {
                    if rms < thr * 0.8 {
                        if quietSince == nil { quietSince = now }
                        if let q = quietSince, now - q > 0.5 { complete(q - s); return }
                    } else {
                        quietSince = nil
                    }
                    seconds = now - s
                }
                try? await Task.sleep(nanoseconds: 30_000_000)
            }
        }
    }

    private func finishManually() {
        task?.cancel()
        if seconds > 0 { complete(seconds) } else { running = false; phase = "准备" }
    }

    private func complete(_ sec: Double) {
        let best = model.best(of: exercise.id)
        running = false
        seconds = sec
        phase = "完成"
        if sec >= 1 { model.add(LogEntry(ex: exercise.id, sec: sec)) }
        var t = String(format: "坚持了 %.1f 秒。", sec)
        if best > 0 {
            t += sec > best ? String(format: "刷新了你的最好成绩（之前 %.1f 秒）。", best) : String(format: "你的最好成绩是 %.1f 秒。", best)
        } else {
            t += "这是你的第一次记录，阶段结束时再测一次对比。"
        }
        t += "\n重点不只是时长：声音要从头到尾一样稳，结尾不要挤。肩膀和脖子保持放松。"
        resultText = t
    }
}

// MARK: - Farinelli breathing

struct FarinelliView: View {
    @Environment(AppModel.self) private var model
    let exercise: Exercise
    @State private var phase = "吸 · 停 · 呼"
    @State private var count = 4
    @State private var progress = 0.0
    @State private var running = false
    @State private var task: Task<Void, Never>? = nil

    var body: some View {
        VStack(spacing: 14) {
            Text(phase).font(.title2.weight(.bold))
            Text(running || progress >= 1 ? "\(count)" : "4").font(.system(size: 72, weight: .bold, design: .monospaced))
            ProgressView(value: progress).frame(maxWidth: 420)
            Text("从每段 4 拍开始，每轮加 1 拍，到 8 拍为止。每拍 1 秒，有提示音。")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack {
                Button("开始") { begin() }.buttonStyle(.borderedProminent).disabled(running)
                Button("停止") { task?.cancel(); running = false; phase = "吸 · 停 · 呼"; progress = 0 }
                    .buttonStyle(.bordered).disabled(!running)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical)
        .onDisappear { task?.cancel() }
    }

    private func begin() {
        running = true
        task = Task { @MainActor in
            let engine = AudioEngine.shared
            engine.ensureRunning()
            var seq: [(String, Int)] = []
            for n in 4...8 { seq += [("吸气", n), ("保持", n), ("呼气", n)] }
            for (i, s) in seq.enumerated() {
                for left in stride(from: s.1, through: 1, by: -1) {
                    if Task.isCancelled { return }
                    phase = "\(s.0) · 第 \(s.1 - 3) 轮（\(s.1) 拍）"
                    count = left
                    progress = Double(i + 1) / Double(seq.count)
                    engine.schedule([ToneNote.tick(at: engine.now() + 0.02, accent: left == s.1)])
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
            running = false
            phase = "完成 5 轮"
            count = 0
            model.add(LogEntry(ex: exercise.id))
        }
    }
}

// MARK: - Range test

struct RangeView: View {
    @Environment(AppModel.self) private var model
    @State private var lo: Int? = nil
    @State private var hi: Int? = nil
    @State private var recording: String? = nil
    @State private var message = "测完两个音后显示音域跨度和接近的声部。"

    var body: some View {
        Form {
            Section {
                Text("对应 Ep. 106 的 Find Your Range 挑战。用舒服、不挤的声音，分别唱一个你能稳定发出的最低音和最高音，各坚持 3 秒。测出的音域会用来安排每个练习的起止调。")
                    .font(.callout)
            }
            Section("最低音") { noteRow(which: "lo", value: $lo) }
            Section("最高音") { noteRow(which: "hi", value: $hi) }
            Section("结果") {
                Text(message)
                Button("设为我的音域") {
                    guard let l = lo, let h = hi, h - l >= 7 else { message = "先测出最低音和最高音（至少相差 7 个半音）。"; return }
                    model.setCustomRange(lo: l, hi: h)
                    message = "已设为你的音域 \(Music.name(l))–\(Music.name(h))，练习会按它安排起止调。"
                }
                .buttonStyle(.borderedProminent)
            }
            Section {
                Text("参考声部音域：男低 E2–E4，男中 A2–G4，男高 C3–C5，女低 F3–E5，女中 A3–A5，女高 C4–C6。音域只是安排练习的依据，不必和这些分类完全对上。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("音域测试")
        .onAppear {
            if let c = model.custom, lo == nil, hi == nil { lo = c.lo; hi = c.hi }
        }
    }

    private func noteRow(which: String, value: Binding<Int?>) -> some View {
        HStack {
            Text(value.wrappedValue.map { Music.name($0) } ?? "—")
                .font(.system(size: 34, weight: .bold, design: .monospaced))
                .frame(minWidth: 90, alignment: .leading)
            Spacer()
            Picker("手动选择", selection: value) {
                Text("—").tag(Int?.none)
                ForEach(33...91, id: \.self) { Text(Music.name($0)).tag(Int?.some($0)) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            Button(recording == which ? "录音中…" : "录 3 秒") { capture(which, into: value) }
                .buttonStyle(.bordered)
                .disabled(recording != nil)
        }
        .onChange(of: value.wrappedValue) { _, _ in describe() }
    }

    private func capture(_ which: String, into value: Binding<Int?>) {
        recording = which
        Task { @MainActor in
            let engine = AudioEngine.shared
            guard await engine.enableMic() else {
                recording = nil
                message = "没有麦克风权限，请用下拉框手动选择，或在系统设置里打开麦克风权限。"
                return
            }
            engine.ensureRunning()
            let t0 = engine.now()
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            let ms = engine.frames(since: t0).filter { $0.voiced && $0.clarity > 0.85 }.map { $0.midi }
            recording = nil
            if ms.count < 10 { message = "没有测到稳定的音高，靠近麦克风再试一次。"; return }
            value.wrappedValue = Int(ms.median.rounded())
            describe()
        }
    }

    private func describe() {
        guard let l = lo, let h = hi, h > l else { return }
        let span = h - l
        let best = VoiceRange.presets.min { abs($0.range.lo - l) + abs($0.range.hi - h) < abs($1.range.lo - l) + abs($1.range.hi - h) }
        message = "\(Music.name(l))–\(Music.name(h))，跨度 \(span) 个半音（约 \(String(format: "%.1f", Double(span) / 12)) 个八度），最接近\(best?.range.name ?? "")。"
    }
}

// MARK: - File analysis

struct AnalyzeView: View {
    @State private var importing = false
    @State private var status = ""
    @State private var report: FileReport? = nil
    @State private var fileName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("选择一段音频（最长分析前 5 分钟），会画出音高曲线，找出稳定的长音，并统计音准、颤音和明亮度。最好是干声；带伴奏的歌可以先用 Demucs、UVR 等工具分离人声。")
                    .font(.callout)
                HStack {
                    Button("选择音频文件") { importing = true }.buttonStyle(.borderedProminent)
                    Text(status).font(.callout).foregroundStyle(.secondary)
                }
                if let r = report { reportView(r) }
            }
            .padding()
            .frame(maxWidth: 900, alignment: .leading)
        }
        .navigationTitle("录音分析")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { res in
            if case .success(let url) = res { load(url) }
        }
    }

    private func load(_ url: URL) {
        status = "读取中…"
        report = nil
        fileName = url.lastPathComponent
        Task.detached(priority: .userInitiated) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let file = try AVAudioFile(forReading: url)
                let fmt = file.processingFormat
                let n = AVAudioFrameCount(min(file.length, AVAudioFramePosition(fmt.sampleRate * 300)))
                guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: n) else { throw CocoaError(.fileReadCorruptFile) }
                try file.read(into: buf, frameCount: n)
                let len = Int(buf.frameLength), chs = Int(fmt.channelCount)
                var x = [Float](repeating: 0, count: len)
                if let data = buf.floatChannelData {
                    for c in 0..<chs {
                        let p = data[c]
                        for i in 0..<len { x[i] += p[i] / Float(chs) }
                    }
                }
                let r = FileAnalyzer.analyze(samples: x, sampleRate: fmt.sampleRate) { p in
                    Task { @MainActor in status = "分析中 \(Int(p * 100))%" }
                }
                await MainActor.run {
                    report = r
                    status = r == nil ? "几乎没有检测到人声音高。确认是清楚的人声录音，或先分离掉伴奏。" : ""
                }
            } catch {
                await MainActor.run { status = "这个文件读不出来，换成 wav、m4a 或 mp3 再试。" }
            }
        }
    }

    @ViewBuilder
    private func reportView(_ r: FileReport) -> some View {
        LazyVGrid(columns: tileColumns, spacing: 10) {
            Tile(title: "时长", value: String(format: "%d:%02d", Int(r.duration) / 60, Int(r.duration) % 60), note: fileName)
            Tile(title: "常用音域", value: "\(Music.name(r.lo))–\(Music.name(r.hi))", note: "去掉最高和最低 3%")
            Tile(title: "稳定长音", value: "\(r.notes.count)", note: "≥ 0.3 秒")
            Tile(title: "长音平均偏离半音", value: "\(Int(r.meanDev.rounded()))¢",
                 note: r.meanDev < 15 ? "很准" : r.meanDev < 25 ? "较准" : "偏差较大")
            if let rate = r.vibRate, let ext = r.vibExt {
                Tile(title: "颤音", value: String(format: "%.1f/秒", rate), note: "幅度 ±\(Int(ext.rounded()))¢，\(r.vibCount) 个长音")
            }
            if let b = r.brightness { Tile(title: "明亮度", value: String(format: "%.1f", b), note: "dB（2–4k / 低频）") }
        }
        Text("「偏离半音」把每个长音和最近的半音比，适合检查清唱的音准；如果歌曲本身不是标准音高，这个值会偏大。")
            .font(.footnote).foregroundStyle(.secondary)
        ScrollView(.horizontal) {
            FilePitchTrack(report: r)
                .frame(width: max(600, CGFloat(r.duration) * 40), height: 260)
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))
        let top = r.notes.sorted { ($0.t1 - $0.t0) > ($1.t1 - $1.t0) }.prefix(25).sorted { $0.t0 < $1.t0 }
        Text("最长的 \(top.count) 个音").font(.headline)
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
            GridRow { Text("时间"); Text("音"); Text("偏离"); Text("时长"); Text("颤音") }
                .font(.caption).foregroundStyle(.secondary)
            ForEach(top) { n in
                GridRow {
                    Text(String(format: "%d:%04.1f", Int(n.t0) / 60, n.t0.truncatingRemainder(dividingBy: 60))).monospacedDigit()
                    Text(Music.name(n.m)).font(.body.monospaced())
                    Text(signedCents(n.dev) + "¢").foregroundStyle(abs(n.dev) <= 15 ? Color.green : abs(n.dev) <= 30 ? Color.orange : Color.red).monospacedDigit()
                    Text(String(format: "%.1f 秒", n.t1 - n.t0)).monospacedDigit()
                    Text(n.vib.flatMap { $0.ext >= 15 ? String(format: "%.1f/秒 ±%d¢", $0.rate, Int($0.ext.rounded())) : nil } ?? "—").monospacedDigit()
                }
            }
        }
        .font(.callout)
    }
}

struct FilePitchTrack: View {
    let report: FileReport

    var body: some View {
        Canvas { ctx, size in
            let lo = floor(report.lo) - 3, hi = ceil(report.hi) + 3
            let pxs: CGFloat = 40
            func X(_ t: Double) -> CGFloat { 40 + CGFloat(t) * pxs }
            func Y(_ m: Double) -> CGFloat { size.height - 14 - CGFloat((m - lo) / (hi - lo)) * (size.height - 28) }
            for m in Int(lo)...Int(hi) where Music.isNatural(m) {
                var p = Path()
                p.move(to: CGPoint(x: 40, y: Y(Double(m))))
                p.addLine(to: CGPoint(x: size.width, y: Y(Double(m))))
                ctx.stroke(p, with: .color(.secondary.opacity(0.2)), lineWidth: 1)
                ctx.draw(Text(Music.name(m)).font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary),
                         at: CGPoint(x: 4, y: Y(Double(m))), anchor: .leading)
            }
            var s = 0
            while Double(s) < report.duration {
                ctx.draw(Text(String(format: "%d:%02d", s / 60, s % 60)).font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary),
                         at: CGPoint(x: X(Double(s)), y: size.height - 2), anchor: .bottomLeading)
                s += 10
            }
            for n in report.notes {
                let r = CGRect(x: X(n.t0), y: Y(n.m.rounded()) - 4, width: max(2, X(n.t1) - X(n.t0)), height: 8)
                ctx.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(.indigo.opacity(0.3)))
            }
            var path = Path()
            var prev: Frame? = nil
            for f in report.frames {
                guard f.voiced, f.midi >= lo, f.midi <= hi else { prev = nil; continue }
                if let p = prev, f.t - p.t < 0.05 {
                    path.move(to: CGPoint(x: X(p.t), y: Y(p.midi)))
                    path.addLine(to: CGPoint(x: X(f.t), y: Y(f.midi)))
                }
                prev = f
            }
            ctx.stroke(path, with: .color(.indigo), lineWidth: 2)
        }
    }
}

// MARK: - Log

struct LogView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmClear = false

    var body: some View {
        let days = Set(model.log.map { Calendar.current.startOfDay(for: $0.date) })
        // steps the user ticked off in the daily routine count as practice days but are not listed
        let log = model.log.filter { !$0.ex.hasPrefix("routine.") }
        List {
            Section {
                LazyVGrid(columns: tileColumns, spacing: 10) {
                    Tile(title: "练习天数", value: "\(days.count)")
                    Tile(title: "连续天数", value: "\(streak(days))")
                    Tile(title: "记录条数", value: "\(log.count)")
                }
            } footer: {
                Text("记录保存在这台设备上。")
            }
            Section("最近") {
                if log.isEmpty {
                    Text("还没有记录。做完一次跟练、呼吸计时或音域测试后，这里会列出成绩。").foregroundStyle(.secondary)
                }
                ForEach(Array(log.suffix(200).reversed())) { e in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Course.byID[e.ex]?.name ?? e.ex)
                            Text(detail(e)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            score(e)
                            Text(dateLabel(e.date)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if !log.isEmpty {
                Section {
                    Button("清空记录", role: .destructive) { confirmClear = true }
                }
            }
        }
        .navigationTitle("练习记录")
        .confirmationDialog("清空所有练习记录？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("清空", role: .destructive) { model.clearLog() }
        }
    }

    private func streak(_ days: Set<Date>) -> Int {
        let cal = Calendar.current
        var d = cal.startOfDay(for: Date())
        if !days.contains(d) { d = cal.date(byAdding: .day, value: -1, to: d) ?? d }
        var n = 0
        while days.contains(d) {
            n += 1
            d = cal.date(byAdding: .day, value: -1, to: d) ?? d
        }
        return n
    }

    @ViewBuilder
    private func score(_ e: LogEntry) -> some View {
        if let a = e.acc {
            Text("\(Int((a * 100).rounded()))%").foregroundStyle(Color.score(a)).monospacedDigit()
        } else if let s = e.sec {
            Text(String(format: "%.1f 秒", s)).monospacedDigit()
        } else if let l = e.rangeLo, let h = e.rangeHi {
            Text("\(Music.name(l))–\(Music.name(h))").monospaced()
        } else {
            Text("完成")
        }
    }

    private func detail(_ e: LogEntry) -> String {
        guard e.acc != nil else { return "" }
        var t = signedCents(e.mean ?? 0) + "¢ · ±\(Int((e.std ?? 0).rounded()))¢ · \(e.keys ?? 0) 个调"
        if let h = e.hi { t += String(format: " · 明亮度 %.1f", h) }
        if let r = e.vibRate { t += String(format: " · 颤音 %.1f/秒", r) }
        return t
    }
}
