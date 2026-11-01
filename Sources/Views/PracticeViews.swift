import SwiftUI
import UniformTypeIdentifiers

struct PracticeRoot: View {
    @Environment(AppModel.self) private var model
    @State private var selection: String?

    var body: some View {
        NavigationSplitView {
            CourseSidebar(selection: $selection)
                .navigationTitle("练声房")
                .toolbar { ToolbarItem { SettingsButton() } }
        } detail: {
            if let id = selection, let ex = Course.byID[id] {
                let v = model.voice
                ExerciseView(exercise: ex, voice: v)
                    .id("\(id)-\(v.lo)-\(v.hi)")
            } else {
                ContentUnavailableView("选一个练习", systemImage: "music.note",
                                       description: Text("按周列出了 Justin Stoney 课程里的练习。"))
            }
        }
    }
}

struct CourseSidebar: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: String?

    var body: some View {
        // the teacher's weeks, read once per draw: the list changes length when the teacher changes
        let weeks = model.teacher.weeks
        let week = weeks[min(max(0, model.week), weeks.count - 1)]
        List(selection: $selection) {
            Section {
                TeacherPicker()
                Picker("声部", selection: Binding(get: { model.voiceKey }, set: { model.setVoice($0) })) {
                    ForEach(0..<VoiceRange.presets.count, id: \.self) { i in
                        Text(VoiceRange.presets[i].range.name).tag(VoiceRange.presets[i].key)
                    }
                    if let c = model.custom {
                        Text("我的音域（\(Music.name(c.lo))–\(Music.name(c.hi))）").tag("custom")
                    }
                }
                WeekGrid()
            } header: {
                Text("\(model.teacher.name) · \(weeks.count) 周课程")
            } footer: {
                Text("在「设置」里切换老师、指定课程视频文件夹。")
            }
            Section {
                CourseVideosButton()
            }
            Section("每日热身") {
                ForEach(Course.warmup, id: \.self) { id in
                    if let ex = Course.byID[id] {
                        ExerciseRow(exercise: ex).tag(id)
                    }
                }
            }
            Section {
                ForEach(week.ex, id: \.self) { id in
                    if let ex = Course.byID[id] {
                        ExerciseRow(exercise: ex).tag(id)
                    }
                }
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("第 \(model.week + 1) 周 · 阶段 \(week.stage) \(Course.stageNames[week.stage] ?? "")")
                    Text(week.focus).font(.headline).foregroundStyle(.primary).textCase(nil)
                }
            }
        }
    }
}

struct WeekGrid: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // iterate the weeks themselves, never index into them: switching teacher changes how many there are
        let weeks = Array(model.teacher.weeks.enumerated())
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
            ForEach(weeks, id: \.offset) { i, w in
                Button {
                    model.setWeek(i)
                } label: {
                    VStack(spacing: 3) {
                        Text("\(i + 1)").font(.system(.subheadline, design: .monospaced).weight(.semibold))
                        Capsule().fill(Color.stage(w.stage)).frame(width: 16, height: 3)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).strokeBorder(i == model.week ? Color.primary : Color.secondary.opacity(0.3), lineWidth: i == model.week ? 2 : 1))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.primary)
                .accessibilityLabel("第 \(i + 1) 周")
            }
        }
        .padding(.vertical, 4)
    }
}

struct ExerciseRow: View {
    @Environment(AppModel.self) private var model
    let exercise: Exercise

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name).font(.body.weight(.semibold))
                Text("Ep. \(exercise.ep)" + (exercise.t > 0 ? " · " + Course.mmss(exercise.t) : ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VideoQuickButton(exercise: exercise)
            VStack(alignment: .trailing, spacing: 2) {
                Text(exercise.syl).font(.system(.caption, design: .monospaced).weight(.semibold)).foregroundStyle(.tint)
                if let last = model.last(of: exercise.id) {
                    Group {
                        if let a = last.acc { Text("\(Int((a * 100).rounded()))%").foregroundStyle(Color.score(a)) }
                        else if let s = last.sec { Text(String(format: "%.1f 秒", s)) }
                        else { Text("已练") }
                    }
                    .font(.caption.monospacedDigit())
                }
            }
        }
    }
}

struct ExerciseView: View {
    @Environment(AppModel.self) private var model
    @Environment(VideoLibrary.self) private var videos
    let exercise: Exercise
    /// set when opened from the daily routine: what this step is for
    let step: RoutineStep?
    @State private var session: PracticeSession
    @State private var withVideo = false

    init(exercise: Exercise, voice: VoiceRange, step: RoutineStep? = nil) {
        self.exercise = exercise
        self.step = step
        _session = State(initialValue: PracticeSession(exercise: exercise, voice: voice, maxKeys: step?.maxKeys))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let step {
                    RoutineBanner(step: step, exercise: exercise)
                }
                header
                videoTraining
                Text(exercise.tip).font(.callout)
                switch exercise.kind {
                case .pitch:
                    PitchPracticeView(session: session)
                case .breath:
                    BreathTimerView(exercise: exercise)
                case .farinelli:
                    FarinelliView(exercise: exercise)
                case .range:
                    Button("去测音域") { model.tab = .range }.buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .frame(maxWidth: 900, alignment: .leading)
        }
        .navigationTitle(exercise.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onDisappear { session.stop(score: false) }
    }

    /// The course video inside the exercise, starting where this exercise is taught.
    @ViewBuilder
    private var videoTraining: some View {
        if let file = videos.file(for: exercise) {
            Button { withVideo.toggle() } label: {
                Label(withVideo ? "收起视频" : "跟视频练（从 \(Course.mmss(exercise.t)) 开始）",
                      systemImage: withVideo ? "chevron.up" : "play.rectangle.on.rectangle")
            }
            .buttonStyle(.bordered)
            if withVideo {
                VideoTrainingPanel(exercise: exercise, file: file)
            }
        } else if exercise.videoID != nil && videos.folderName == nil {
            Text("在「设置」里指定课程视频文件夹后，可以在这里直接跟着视频练。").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(exercise.syl)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(.tint)
                .minimumScaleFactor(0.5)
                .lineLimit(2)
            HStack(spacing: 10) {
                CourseVideoButton(exercise: exercise,
                                  title: "Ep. \(exercise.ep)" + (exercise.t > 0 ? " · 从 \(Course.mmss(exercise.t)) 开始看" : ""))
                if let p = exercise.pattern { Text(p.name).foregroundStyle(.secondary) }
            }
            .font(.subheadline)
            Text((exercise.fromTitle ? "音节出自课程视频" : "音节为建议") + " · " + (exercise.verified ? "音型已按课程视频核对" : "音型待核对（暂用常用练声音型）"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

extension AppModel {
    /// Binding to one practice preference, saved when it changes.
    func pref<T>(_ kp: WritableKeyPath<PracticePrefs, T>) -> Binding<T> {
        Binding(get: { self.prefs[keyPath: kp] }, set: { v in
            var p = self.prefs
            p[keyPath: kp] = v
            self.setPrefs(p)
        })
    }
}

struct PitchPracticeView: View {
    @Environment(AppModel.self) private var model
    @Bindable var session: PracticeSession
    @State private var showSettings = false
    @State private var importing = false

    var body: some View {
        let v = model.voice
        let noteRange = Array((v.lo - 5)...(v.hi + 5))
        let busy = session.running || session.preparing
        VStack(alignment: .leading, spacing: 14) {
            JianpuView(pattern: session.pattern)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Picker("起始根音", selection: $session.rootA) {
                        ForEach(noteRange, id: \.self) { Text(Music.name($0)).tag($0) }
                    }
                    if !session.pattern.fixed {
                        Picker("最高根音", selection: $session.rootB) {
                            ForEach(noteRange, id: \.self) { Text(Music.name($0)).tag($0) }
                        }
                    }
                }
                .pickerStyle(.menu)
                HStack {
                    Text("速度 \(Int(session.bpm))").font(.callout.monospacedDigit()).frame(width: 80, alignment: .leading)
                    Slider(value: $session.bpm, in: 50...140, step: 2)
                }
                if !session.pattern.fixed { Toggle("上行后再下行", isOn: $session.upDown) }
                DisclosureGroup("示范、节拍器和提示音", isExpanded: $showSettings) {
                    PracticeSettingsView()
                        .padding(.top, 6)
                }
            }
            .disabled(busy)

            HStack {
                Button {
                    if session.running { session.stop(score: session.mode != .record) }
                    else { Task { await session.start(.practice, model: model) } }
                } label: {
                    Label(session.running && session.mode == .practice ? "停止" : "开始练习",
                          systemImage: session.running && session.mode == .practice ? "stop.fill" : "mic.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(session.preparing || (session.running && session.mode != .practice))

                Button {
                    if session.running { session.stop(score: false) }
                    else { Task { await session.start(.listen, model: model) } }
                } label: {
                    Label(session.running && session.mode == .listen ? "停止示范" : "只听示范", systemImage: "speaker.wave.2")
                }
                .buttonStyle(.bordered)
                .disabled(session.preparing || (session.running && session.mode != .listen))
            }

            if let n = session.notice {
                Text(n).font(.callout).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
            }

            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !session.running)) { _ in
                let engine = AudioEngine.shared
                let now = session.running ? engine.now() : -1
                let plan = session.running ? session.plan : session.preview(model.prefs)
                let block = plan.block(at: now) ?? plan.blocks[0]
                let ph = session.phaseText(at: now)
                let countLeft: Int? = {
                    if case .countIn(let n) = ph.1 { return n }
                    return nil
                }()
                VStack(alignment: .leading, spacing: 8) {
                    Text(ph.0)
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.1)))
                        .foregroundStyle(phaseColor(ph.1))
                    PianoRoll(block: block, frames: session.running ? engine.frames(since: block.t0) : [], now: now)
                        .frame(height: 240)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            if let n = countLeft {
                                Text("\(n)")
                                    .font(.system(size: 96, weight: .heavy, design: .rounded))
                                    .foregroundStyle(.orange)
                                    .shadow(color: .black.opacity(0.15), radius: 6)
                                    .transition(.scale)
                            }
                        }
                    keyboard(block: block, plan: plan, now: now)
                }
            }

            MetersView(session: session)

            if let r = session.result {
                ResultsView(result: r, exercise: session.exercise) { root in
                    session.rootA = root
                    session.rootB = root
                    Task { await session.start(.practice, model: model) }
                }
            }

            DemoPanel(session: session, importing: $importing)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { res in
            if case .success(let url) = res { session.importDemo(from: url) }
        }
    }

    /// Keyboard under the piano roll: chord and demo keys light up, the note to sing shows in green,
    /// a dot marks the note being sung; tapping a key plays it.
    private func keyboard(block: Block, plan: Plan, now: Double) -> some View {
        var notes = (block.listen + block.sing).flatMap { s in [s.m] + (s.g.map { [$0] } ?? []) }
        if block.chord != nil { notes += [block.root, block.root + 7] }
        let keys = session.running ? plan.keys(at: now) : (playing: Set<Int>(), target: Int?.none)
        var sung: (key: Int, cents: Double)? = nil
        if session.running, let f = AudioEngine.shared.latest(1).last, f.voiced {
            let k = Int(f.midi.rounded())
            sung = (k, keys.target.map { Music.fold((f.midi - Double($0)) * 100) } ?? (f.midi - Double(k)) * 100)
        }
        // keep the middle of this key's notes in view; scroll by hand to see the rest
        let focus = ((notes.min() ?? 48) + (notes.max() ?? 60)) / 2
        return PianoKeyboard(playing: keys.playing, target: keys.target, sung: sung, focus: focus) { m in
            let engine = AudioEngine.shared
            engine.ensureRunning()
            let t = engine.now() + 0.02
            engine.schedule([ToneNote(.piano, m0: Double(m), t0: t, t1: t + 0.9, vol: 0.25)])
        }
    }

    private func phaseColor(_ p: Plan.Phase) -> Color {
        switch p {
        case .sing: return .green
        case .listen, .chord: return .purple
        case .countIn: return .orange
        default: return .secondary
        }
    }
}

/// Session settings shared by all exercises.
struct PracticeSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("示范", selection: model.pref(\.demo)) {
                ForEach(PlanOptions.Demo.allCases) { Text($0.label).tag($0.rawValue) }
            }
            Toggle("每个调开始前弹和弦定调", isOn: model.pref(\.chordCue))
            Picker("预备拍", selection: model.pref(\.countIn)) {
                Text("2 拍").tag(2)
                Text("4 拍").tag(4)
            }
            .pickerStyle(.segmented)
            Toggle("唱的时候开节拍器", isOn: model.pref(\.metronome))
            if model.prefs.metronome {
                HStack {
                    Text("节拍器音量").font(.callout)
                    Slider(value: model.pref(\.metronomeVolume), in: 0...1)
                }
            }
            Toggle("唱的时候钢琴同步弹旋律（请戴耳机）", isOn: model.pref(\.accompany))
            Text("第一个调总是先数 4 拍。外放时节拍器和伴奏会被麦克风收进去：节拍声已在评分时排除，钢琴伴奏会干扰评分，所以只建议戴耳机时打开。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Record or import a sung demo for this exercise; it replaces the piano demo and is moved to every key.
struct DemoPanel: View {
    @Environment(AppModel.self) private var model
    @Bindable var session: PracticeSession
    @Binding var importing: Bool
    @State private var confirmDelete = false

    var body: some View {
        let busy = session.running || session.preparing
        VStack(alignment: .leading, spacing: 10) {
            Text("真人示范").font(.headline)
            if let d = session.demo {
                HStack(spacing: 12) {
                    Label(d.courseEpisode.map { "课程原声示范（Ep. \($0)）" } ?? (d.imported ? "已导入示范" : "已录制示范"), systemImage: "person.wave.2")
                    Text(String(format: "%.1f 秒", d.duration)).foregroundStyle(.secondary)
                    if let b = d.bpm { Text("速度 \(Int(b))").foregroundStyle(.secondary) }
                }
                .font(.callout)
                Picker("示范的根音", selection: Binding(get: { d.root }, set: { session.setDemoRoot($0) })) {
                    ForEach(28...84, id: \.self) { Text(Music.name($0)).tag($0) }
                }
                .pickerStyle(.menu)
                Toggle("练习时使用这段示范", isOn: model.pref(\.useRecordedDemo))
            } else {
                Text("可以请老师（或你自己）按这个练习的音节「\(session.exercise.syl)」唱一遍示范。之后每个调都会用这段真人录音示范，自动移调，录制的示范还会跟着速度变化。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Button {
                    if session.running && session.mode == .record { session.stop(score: false) }
                    else { Task { await session.start(.record, model: model) } }
                } label: {
                    Label(session.running && session.mode == .record ? "取消录音" : (session.demo == nil ? "录制示范" : "重新录制"), systemImage: "record.circle")
                }
                .buttonStyle(.bordered)
                .disabled(session.preparing || (session.running && session.mode != .record))
                Button { importing = true } label: { Label("导入音频", systemImage: "square.and.arrow.down") }
                    .buttonStyle(.bordered)
                    .disabled(busy)
                if session.demo != nil && !DemoStore.shared.isFromFolder(session.exercise.id) {
                    Button(role: .destructive) { confirmDelete = true } label: { Label("删除", systemImage: "trash") }
                        .buttonStyle(.bordered)
                        .disabled(busy)
                }
            }
            Text("录制时：先听和弦，数 4 拍后，在根音 \(Music.name(session.rootA))、速度 \(Int(session.bpm)) 上按画面唱一遍。导入时会自动识别根音，可以在上面改正。请只使用你有权使用的录音。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
        .confirmationDialog("删除这个练习的示范录音？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) { session.deleteDemo() }
        }
    }
}

struct JianpuView: View {
    let pattern: Pattern

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .bottom, spacing: 2) {
                Text("简谱 1 = 根音").font(.caption).foregroundStyle(.secondary).padding(.trailing, 6)
                ForEach(Array(pattern.steps.enumerated()), id: \.offset) { _, s in
                    VStack(spacing: 2) {
                        Circle().fill(s.o ? Color.primary : Color.clear).frame(width: 4, height: 4)
                        Text(s.j).font(.system(.title3, design: .monospaced).weight(.semibold))
                        if let l = s.l { Text(l).font(.system(size: 9)).foregroundStyle(.secondary) }
                        Rectangle().fill(Color.indigo.opacity(0.35)).frame(height: 2)
                    }
                    .frame(minWidth: max(14, min(64, s.b * 22)))
                }
            }
            .padding(10)
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))
    }
}

/// Piano-roll: bars are target notes, the line is what was sung (green = within 25 cents).
struct PianoRoll: View {
    let block: Block
    let frames: [Frame]
    let now: Double

    var body: some View {
        Canvas { ctx, size in
            let all = block.listen + block.sing
            guard !all.isEmpty else { return }
            var lo = 999.0, hi = -999.0
            for s in all {
                lo = min(lo, Double(s.m), Double(s.g ?? s.m))
                hi = max(hi, Double(s.m), Double(s.g ?? s.m))
            }
            lo -= 3
            hi += 3
            let padL: CGFloat = 40, W = size.width, H = size.height
            let t0 = block.t0, t1 = block.t1
            func X(_ t: Double) -> CGFloat { padL + CGFloat((t - t0) / (t1 - t0)) * (W - padL - 6) }
            func Y(_ m: Double) -> CGFloat { H - 12 - CGFloat((m - lo) / (hi - lo)) * (H - 24) }

            if let l0 = block.listen.first?.t0, let l1 = block.listen.last?.t1 {
                ctx.fill(Path(CGRect(x: X(l0), y: 0, width: X(l1) - X(l0), height: H)), with: .color(.purple.opacity(0.07)))
            }
            if let c = block.chord {
                ctx.fill(Path(CGRect(x: X(c.lowerBound), y: 0, width: X(c.upperBound) - X(c.lowerBound), height: H)), with: .color(.blue.opacity(0.06)))
                ctx.draw(Text("和弦").font(.caption).foregroundColor(.secondary), at: CGPoint(x: X(c.lowerBound) + 6, y: 10), anchor: .leading)
            }
            for (i, c) in block.countIn.enumerated() {
                let r = CGRect(x: X(c) - 4, y: H - 10, width: 8, height: 8)
                ctx.fill(Path(ellipseIn: r), with: .color(.orange.opacity(i == 0 ? 0.9 : 0.6)))
            }

            for m in Int(lo.rounded(.up))...Int(hi.rounded(.down)) {
                let y = Y(Double(m)), nat = Music.isNatural(m)
                var p = Path()
                p.move(to: CGPoint(x: padL, y: y))
                p.addLine(to: CGPoint(x: W, y: y))
                ctx.stroke(p, with: .color(.secondary.opacity(nat ? 0.25 : 0.12)), lineWidth: nat ? 1 : 0.5)
                if nat {
                    ctx.draw(Text(Music.name(m)).font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary),
                             at: CGPoint(x: 4, y: y), anchor: .leading)
                }
            }
            if let l = block.listen.first {
                ctx.draw(Text(l.cue ? "起始音" : "示范").font(.caption).foregroundColor(.secondary),
                         at: CGPoint(x: X(l.t0) + 6, y: 10), anchor: .leading)
            }
            if !block.sing.isEmpty {
                ctx.draw(Text("你唱").font(.caption).foregroundColor(.secondary), at: CGPoint(x: X(block.s0) + 6, y: 10), anchor: .leading)
            }

            func bars(_ steps: [PlannedStep], _ color: Color) {
                let h = Y(-0.4) - Y(0.4)
                for s in steps {
                    if let g = s.g {
                        var p = Path()
                        p.move(to: CGPoint(x: X(s.t0), y: Y(Double(s.m))))
                        p.addLine(to: CGPoint(x: X(s.t1), y: Y(Double(g))))
                        ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    } else {
                        let r = CGRect(x: X(s.t0) + 1, y: Y(Double(s.m)) - h / 2, width: max(2, X(s.t1) - X(s.t0) - 2), height: h)
                        ctx.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(s.ns ? color.opacity(0.5) : color))
                    }
                    if let l = s.l {
                        ctx.draw(Text(l).font(.system(size: 9, design: .monospaced)).foregroundColor(.primary),
                                 at: CGPoint(x: X(s.t0) + 2, y: Y(Double(s.m)) - h / 2 - 2), anchor: .bottomLeading)
                    }
                }
            }
            bars(block.listen, .indigo.opacity(0.35))
            bars(block.sing, .indigo)

            if now >= 0 {
                var prev: (t: Double, m: Double)? = nil
                for f in frames {
                    guard f.t >= t0, f.t <= t1, f.voiced else { prev = nil; continue }
                    var target: Int? = nil
                    for s in block.sing where f.t >= s.t0 && f.t < s.t1 && s.g == nil { target = s.m; break }
                    var mm = f.midi
                    if let tg = target { mm = Double(tg) + Music.fold((f.midi - Double(tg)) * 100) / 100 }
                    guard mm >= lo - 1, mm <= hi + 1 else { prev = nil; continue }
                    let color: Color = target.map { Color.cents((mm - Double($0)) * 100) } ?? .secondary
                    if let p0 = prev, f.t - p0.t < 0.08 {
                        var p = Path()
                        p.move(to: CGPoint(x: X(p0.t), y: Y(p0.m)))
                        p.addLine(to: CGPoint(x: X(f.t), y: Y(mm)))
                        ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    }
                    prev = (f.t, mm)
                }
                var ph = Path()
                ph.move(to: CGPoint(x: X(now), y: 0))
                ph.addLine(to: CGPoint(x: X(now), y: H))
                ctx.stroke(ph, with: .color(.primary.opacity(0.5)), lineWidth: 1)
            } else {
                ctx.draw(Text("开始后，你唱的音高会画成曲线：绿 = 准，橙 = 稍偏，红 = 偏得多").font(.caption).foregroundColor(.secondary),
                         at: CGPoint(x: padL + 6, y: H - 14), anchor: .bottomLeading)
            }
        }
        .accessibilityLabel("音高卷帘")
    }
}

struct MetersView: View {
    let session: PracticeSession

    var body: some View {
        // redraws only while practising, so the meters cost nothing when the exercise sits open
        TimelineView(.animation(minimumInterval: 0.05, paused: !session.running)) { _ in
            let engine = AudioEngine.shared
            let recent = engine.latest(3)
            let last = recent.last
            let voiced = recent.filter { $0.voiced }
            let m: Double? = (last?.voiced ?? false) ? voiced.map { $0.midi }.median : nil
            let target = session.running ? session.plan.target(at: engine.now()) : nil
            let cents: Double? = m.map { mm in target.map { Music.fold((mm - $0) * 100) } ?? (mm - mm.rounded()) * 100 }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                meter("当前音高", m.map { Music.name($0) } ?? "—",
                      sub: last.map { $0.voiced ? String(format: "%.1f Hz", $0.f0) : " " } ?? (engine.micEnabled ? " " : "麦克风未连接"))
                VStack(alignment: .leading, spacing: 4) {
                    Text("偏差（音分，±25 内算准）").font(.caption).foregroundStyle(.secondary)
                    Text(cents.map { signedCents($0) } ?? "—").font(.system(.title2, design: .monospaced).weight(.bold))
                        .foregroundStyle(cents.map { Color.cents($0) } ?? .primary)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(LinearGradient(colors: [.red, .orange, .green, .green, .orange, .red], startPoint: .leading, endPoint: .trailing))
                                .frame(height: 8)
                            Capsule().fill(Color.primary).frame(width: 3, height: 16)
                                .offset(x: g.size.width * CGFloat(0.5 + max(-50, min(50, cents ?? 0)) / 100) - 1.5)
                        }
                        .frame(maxHeight: .infinity)
                    }
                    .frame(height: 16)
                }
                .padding(10).background(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                meter("明亮度（2–4 kHz 能量比）", (last?.hi).map { String(format: "%.1f dB", $0) } ?? "—", sub: "越高越有穿透力")
                meter("音量", last.map { $0.rms > 0.002 ? "\(Int((20 * log10($0.rms)).rounded())) dB" : "—" } ?? "—", sub: " ")
            }
        }
    }

    private func meter(_ title: String, _ value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.title2, design: .monospaced).weight(.bold))
            Text(sub).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
    }
}

struct ResultsView: View {
    let result: SessionResult
    let exercise: Exercise
    var retry: ((Int) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("这次练习的反馈").font(.title3.weight(.bold))
            LazyVGrid(columns: tileColumns, spacing: 10) {
                Tile(title: "音准（±25 音分内）", value: "\(Int((result.acc * 100).rounded()))%",
                     note: result.previous?.acc.map { "上次 \(Int(($0 * 100).rounded()))%" } ?? "第一次记录", color: .score(result.acc))
                Tile(title: "平均偏差", value: signedCents(result.mean) + "¢", note: result.mean > 15 ? "偏高" : result.mean < -15 ? "偏低" : "居中")
                Tile(title: "长音稳定度", value: "±\(Int(result.std.rounded()))¢", note: "每个音内部的波动")
                Tile(title: "检测到声音", value: "\(Int((result.vr * 100).rounded()))%", note: "\(result.rows.count) 个调")
                if let hi = result.hi { Tile(title: "明亮度", value: String(format: "%.1f", hi), note: "dB（2–4k / 低频）") }
                if let v = result.vib { Tile(title: "颤音", value: String(format: "%.1f/秒", v.rate), note: "幅度 ±\(Int(v.ext.rounded()))¢") }
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(result.feedback.enumerated()), id: \.offset) { _, t in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                        Text(t).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(.callout)

            if exercise.metric == .vowels, let row = result.rows.first {
                vowelTable(row)
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("根音"); Text("音准"); Text("平均偏差"); Text("波动"); Text("明亮度"); Text("")
                }
                .font(.caption).foregroundStyle(.secondary)
                Divider()
                ForEach(result.rows) { r in
                    GridRow {
                        Text(Music.name(r.root)).font(.body.monospaced())
                        HStack(spacing: 6) {
                            Capsule().fill(Color.score(r.acc)).frame(width: max(2, 70 * r.acc), height: 8)
                            Text("\(Int((r.acc * 100).rounded()))%").monospacedDigit()
                        }
                        Text(signedCents(r.mean) + "¢").monospacedDigit()
                        Text("±\(Int(r.std.rounded()))¢").monospacedDigit()
                        Text(r.hi.map { String(format: "%.1f", $0) } ?? "—").monospacedDigit()
                        if let retry {
                            Button("再练这个调") { retry(r.root) }
                                .buttonStyle(.borderless)
                                .font(.caption)
                        } else {
                            Text("")
                        }
                    }
                }
            }
            .font(.callout)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
    }

    @ViewBuilder
    private func vowelTable(_ row: BlockScore) -> some View {
        let his = row.steps.compactMap { $0.hi }
        let mn = his.min() ?? 0, mx = his.max() ?? 0
        VStack(alignment: .leading, spacing: 6) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow { Text("元音"); Text("音准"); Text("偏差"); Text("明亮度") }
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(Array(row.steps.enumerated()), id: \.offset) { _, s in
                    GridRow {
                        Text(s.step.l ?? "").font(.body.monospaced())
                        Text("\(Int((s.acc * 100).rounded()))%").foregroundStyle(Color.score(s.acc)).monospacedDigit()
                        Text(s.sung ? signedCents(s.mean) + "¢" : "—").monospacedDigit()
                        HStack(spacing: 6) {
                            if let h = s.hi {
                                Capsule().fill(Color.indigo).frame(width: 20 + 60 * (mx > mn ? (h - mn) / (mx - mn) : 0.5), height: 8)
                                Text(String(format: "%.1f dB", h)).monospacedDigit()
                            } else { Text("—") }
                        }
                    }
                }
            }
            if his.count >= 3 {
                Text(String(format: "五个元音的明亮度相差 %.1f dB。阶段 C 的目标是同一个音高上各元音音色接近，这个差距越小越好；最暗的元音可以借最亮元音的位置来唱（Ep. 117）。", mx - mn))
                    .font(.callout)
            }
        }
    }
}
