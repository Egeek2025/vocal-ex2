import SwiftUI
import AVKit
import Observation
import UniformTypeIdentifiers

/// Opens the course video at this exercise: the local copy when the video folder has it, otherwise online.
struct CourseVideoButton: View {
    @Environment(VideoLibrary.self) private var videos
    let exercise: Exercise
    let title: String
    @State private var showing = false

    var body: some View {
        if let file = videos.file(for: exercise) {
            Button { showing = true } label: { Label(title, systemImage: "play.rectangle.fill") }
                .buttonStyle(.borderless)
                .sheet(isPresented: $showing) { CourseVideoPlayer(exercise: exercise, file: file) }
        } else if let url = exercise.videoURL {
            Link(destination: url) { Label(title, systemImage: "play.rectangle") }
        }
    }
}

/// A small play button for exercise rows: opens the local course video at this exercise.
/// Shows nothing when the folder has no copy of the video.
struct VideoQuickButton: View {
    @Environment(VideoLibrary.self) private var videos
    let exercise: Exercise
    @State private var showing = false

    var body: some View {
        if let file = videos.file(for: exercise) {
            Button { showing = true } label: {
                Image(systemName: "play.rectangle.fill").imageScale(.large)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("看视频跟练")
            .sheet(isPresented: $showing) { CourseVideoPlayer(exercise: exercise, file: file) }
        }
    }
}

/// Every course video of the current teacher, in plan order, with its exercises as chapters.
struct CourseVideosView: View {
    @Environment(AppModel.self) private var model
    @Environment(VideoLibrary.self) private var videos
    @State private var playing: (exercise: Exercise, file: URL)?

    private struct Episode: Identifiable {
        let ep: Int
        let exercises: [Exercise]
        var id: Int { ep }
    }

    private var episodes: [Episode] {
        let t = model.teacher
        var order: [Int] = []
        for id in t.weeks.flatMap(\.ex) + t.exercises.map(\.id) {
            if let e = Course.byID[id], e.videoID != nil, !order.contains(e.ep) { order.append(e.ep) }
        }
        return order.map { ep in Episode(ep: ep, exercises: t.exercises.filter { $0.ep == ep }.sorted { $0.t < $1.t }) }
    }

    var body: some View {
        List {
            if videos.folderName == nil {
                Section {
                    Text("还没有指定课程视频文件夹。在「设置」里选择后，这里的每一集都能直接播放。").font(.callout)
                    VideoFolderSetting()
                }
            }
            ForEach(episodes) { item in
                Section {
                    ForEach(item.exercises) { e in
                        chapterRow(e)
                    }
                } header: {
                    Text("Ep. \(item.ep)" + (item.exercises.first.flatMap { videos.title(for: $0) }.map { " · \($0)" } ?? ""))
                        .textCase(nil)
                }
            }
        }
        .navigationTitle("\(model.teacher.name)的课程视频")
        .sheet(isPresented: Binding(get: { playing != nil }, set: { if !$0 { playing = nil } })) {
            if let p = playing { CourseVideoPlayer(exercise: p.exercise, file: p.file) }
        }
    }

    @ViewBuilder
    private func chapterRow(_ e: Exercise) -> some View {
        let label = HStack {
            Text(Course.mmss(e.t)).monospacedDigit().foregroundStyle(.secondary)
            Text(e.name)
            Spacer()
            Text(e.syl).font(.caption.monospaced()).foregroundStyle(.secondary)
        }
        if let file = videos.file(for: e) {
            Button { playing = (e, file) } label: {
                HStack { Image(systemName: "play.fill").foregroundStyle(.tint); label }
            }
            .buttonStyle(.borderless)
        } else if let url = e.videoURL {
            Link(destination: url) {
                HStack { Image(systemName: "safari").foregroundStyle(.secondary); label }
            }
        } else {
            label
        }
    }
}

/// Opens the list of course videos.
struct CourseVideosButton: View {
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: { Label("全部课程视频", systemImage: "film.stack") }
            .sheet(isPresented: $showing) {
                NavigationStack {
                    CourseVideosView()
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showing = false } } }
                }
                #if os(macOS)
                .frame(minWidth: 560, minHeight: 600)
                #endif
            }
    }
}

/// The exercises of the same episode, in video order: places to jump to.
private func jumpPoints(_ exercise: Exercise) -> [Exercise] {
    Course.teacher(exercise.teacher).exercises
        .filter { $0.ep == exercise.ep && $0.videoID != nil }
        .sorted { $0.t < $1.t }
}

/// Owns the player for a local course video and seeks it to exercises. Seeks wait until the file has
/// loaded; a file the player cannot open is reported instead of being played.
@Observable
final class CourseVideo {
    let player = AVPlayer()
    var current: String
    /// why the file cannot be played, when it cannot
    var failure: String?
    /// playback position and length in seconds, for the marker timeline
    var time: Double = 0
    var duration: Double = 0
    @ObservationIgnored private var status: NSKeyValueObservation?
    @ObservationIgnored private var pending: (t: Int, play: Bool)?
    @ObservationIgnored private var timeToken: Any?
    @ObservationIgnored private var practiceObserver: NSObjectProtocol?

    init(exercise: Exercise, file: URL, autoplay: Bool) {
        current = exercise.id
        pending = (exercise.t, autoplay)
        let item = AVPlayerItem(url: file)
        status = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            let s = item.status, error = item.error?.localizedDescription, d = item.duration.seconds
            DispatchQueue.main.async { self?.statusChanged(s, error, d) }
        }
        player.replaceCurrentItem(with: item)
        timeToken = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] t in
            self?.time = t.seconds
        }
        // starting a practice pauses the video: it would be heard through the microphone and over the piano
        practiceObserver = NotificationCenter.default.addObserver(forName: .practiceWillStart, object: nil, queue: .main) { [weak self] _ in
            self?.player.pause()
        }
    }

    private func statusChanged(_ s: AVPlayerItem.Status, _ error: String?, _ d: Double) {
        switch s {
        case .readyToPlay:
            if d.isFinite, d > 0 { duration = d }
            if let p = pending {
                pending = nil
                seek(to: p.t, play: p.play)
            }
        case .failed:
            failure = error ?? "未知错误"
        default:
            break
        }
    }

    func seek(_ e: Exercise, play: Bool = true) {
        current = e.id
        seek(to: e.t, play: play)
    }

    func seek(to t: Int, play: Bool = true) {
        guard player.currentItem?.status == .readyToPlay else {
            pending = (t, play)
            return
        }
        player.seek(to: CMTime(seconds: Double(t), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        if play { player.play() }
    }

    func close() {
        status?.invalidate()
        status = nil
        if let t = timeToken { player.removeTimeObserver(t) }
        timeToken = nil
        if let o = practiceObserver { NotificationCenter.default.removeObserver(o) }
        practiceObserver = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
    }
}

/// AVKit's own player view: the native controls, without SwiftUI's VideoPlayer wrapper.
#if os(macOS)
struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.player = player
        v.controlsStyle = .inline
        v.showsFullScreenToggleButton = true
        return v
    }

    func updateNSView(_ v: AVPlayerView, context: Context) {
        if v.player !== player { v.player = player }
    }

    static func dismantleNSView(_ v: AVPlayerView, coordinator: ()) {
        v.player = nil
    }
}
#else
struct PlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let c = AVPlayerViewController()
        c.player = player
        return c
    }

    func updateUIViewController(_ c: AVPlayerViewController, context: Context) {
        if c.player !== player { c.player = player }
    }

    static func dismantleUIViewController(_ c: AVPlayerViewController, coordinator: ()) {
        c.player = nil
    }
}
#endif

/// A place to jump to in a course video: an exercise of the app, or a chapter the uploader marked.
private struct VideoMarker: Identifiable {
    let id: String
    let time: Double
    let title: String
    let exercise: Exercise?
}

private func markers(_ exercise: Exercise, chapters: [VideoChapter]) -> [VideoMarker] {
    let ex = jumpPoints(exercise).map { VideoMarker(id: "ex." + $0.id, time: Double($0.t), title: $0.name, exercise: $0) }
    let ch = chapters.enumerated().map { VideoMarker(id: "ch.\($0.offset)", time: $0.element.start, title: $0.element.title, exercise: nil) }
    return (ex + ch).sorted { $0.time < $1.time }
}

/// The video's length as a bar: the played part filled, a tall tick per exercise, a short one per chapter.
/// Clicking or tapping the bar jumps there.
private struct MarkerTimeline: View {
    let video: CourseVideo
    let marks: [VideoMarker]
    let length: Double

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let x: (Double) -> CGFloat = { CGFloat(min(1, max(0, $0 / max(1, length)))) * w }
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.18)).frame(height: 6)
                Capsule().fill(Color.accentColor.opacity(0.5)).frame(width: x(video.time), height: 6)
                ForEach(marks) { m in
                    Rectangle()
                        .fill(m.exercise == nil ? Color.secondary : Color.accentColor)
                        .frame(width: 2, height: m.exercise == nil ? 10 : 18)
                        .offset(x: x(m.time) - 1)
                }
            }
            .frame(height: 22)
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { v in
                video.seek(to: Int(Double(v.location.x / max(1, w)) * length))
            })
        }
        .frame(height: 22)
        .accessibilityLabel("视频进度和标记")
    }
}

/// The markers as buttons, in video order; the exercise being practised stands out.
private struct MarkerButtons: View {
    let video: CourseVideo
    let marks: [VideoMarker]
    let exercise: Exercise

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(marks) { m in
                    let mine = m.exercise?.id == exercise.id
                    Button {
                        if let e = m.exercise { video.seek(e) } else { video.seek(to: Int(m.time)) }
                    } label: {
                        Label("\(Course.mmss(Int(m.time))) \(m.title)", systemImage: m.exercise == nil ? "bookmark" : "music.mic")
                            .lineLimit(1)
                    }
                    .buttonStyle(.bordered)
                    .tint(mine ? Color.accentColor : (m.exercise == nil ? Color.secondary : Color.primary))
                }
            }
        }
    }
}

/// The player, or why the file cannot be played.
private struct VideoSurface: View {
    let video: CourseVideo

    var body: some View {
        if let f = video.failure {
            VStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle").font(.title2)
                Text("这个视频无法播放：\(f)").font(.callout)
                Text("可以在下载视频的电脑上运行 tools/course/transcode.py 转换后再试。").font(.caption).foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding()
            .frame(maxWidth: .infinity)
            .aspectRatio(16 / 9, contentMode: .fit)
            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
        } else {
            PlayerView(player: video.player)
                .frame(maxWidth: .infinity)
                .aspectRatio(16 / 9, contentMode: .fit)
                .background(.black)
        }
    }
}

/// Plays a local course video from the exercise's place in it, with the episode's other exercises as jump points.
struct CourseVideoPlayer: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(VideoLibrary.self) private var videos
    let exercise: Exercise
    let file: URL
    @State private var video: CourseVideo? = nil

    var body: some View {
        NavigationStack {
            if let video {
                content(video)
            } else {
                ProgressView()
            }
        }
        #if os(macOS)
        .frame(minWidth: 720, minHeight: 600)
        #endif
        .onAppear {
            AudioEngine.shared.prepareForVideo()
            // created once here, not in init: SwiftUI runs a view's init on every redraw
            if video == nil { video = CourseVideo(exercise: exercise, file: file, autoplay: true) }
        }
        .onDisappear { video?.close() }
    }

    private func content(_ video: CourseVideo) -> some View {
            VStack(spacing: 0) {
                VideoSurface(video: video)
                MarkerTimeline(video: video, marks: markers(exercise, chapters: videos.chapters(for: exercise)),
                               length: video.duration > 0 ? video.duration : (videos.duration(for: exercise) ?? 1))
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                List {
                    Section {
                        ForEach(jumpPoints(exercise)) { p in
                            JumpRow(point: p, current: video.current == p.id) { video.seek(p) }
                        }
                        Button { video.seek(to: 0) } label: { Label("从头看", systemImage: "backward.end") }
                            .buttonStyle(.borderless)
                    } header: {
                        Text("这一集里的练习")
                    }
                    let chapters = videos.chapters(for: exercise)
                    if !chapters.isEmpty {
                        Section {
                            ForEach(Array(chapters.enumerated()), id: \.offset) { _, c in
                                Button { video.seek(to: Int(c.start)) } label: {
                                    HStack {
                                        Text(Course.mmss(Int(c.start))).monospacedDigit().foregroundStyle(.secondary)
                                        Text(c.title)
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.borderless)
                            }
                        } header: {
                            Text("视频章节")
                        }
                    }
                }
            }
            .navigationTitle("Ep. \(exercise.ep) · \(exercise.name)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("关闭") { dismiss() } }
            }
    }
}

private struct JumpRow: View {
    let point: Exercise
    let current: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(Course.mmss(point.t)).monospacedDigit().foregroundStyle(.secondary)
                Text(point.name)
                Text(point.syl).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                if current { Image(systemName: "speaker.wave.2.fill").foregroundStyle(.tint) }
            }
        }
        .buttonStyle(.borderless)
    }
}

/// Practise along with the course video inside the exercise: the video starts at this exercise, and with
/// the microphone on, the note being sung shows on a keyboard as you sing with the teacher.
struct VideoTrainingPanel: View {
    @Environment(VideoLibrary.self) private var videos
    let exercise: Exercise
    let file: URL
    @State private var video: CourseVideo? = nil
    @State private var listening = false
    @State private var micMissing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let video {
                VideoSurface(video: video)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                let marks = markers(exercise, chapters: videos.chapters(for: exercise))
                MarkerTimeline(video: video, marks: marks,
                               length: video.duration > 0 ? video.duration : (videos.duration(for: exercise) ?? 1))
                HStack {
                    Button { video.seek(exercise) } label: { Label("回到本练习 \(Course.mmss(exercise.t))", systemImage: "arrow.uturn.backward") }
                        .buttonStyle(.borderedProminent)
                    Text("长刻度 = 练习，短刻度 = 视频章节").font(.caption).foregroundStyle(.secondary)
                }
                MarkerButtons(video: video, marks: marks, exercise: exercise)
            } else {
                ProgressView().frame(maxWidth: .infinity).aspectRatio(16 / 9, contentMode: .fit)
            }
            Toggle(isOn: $listening) {
                Text("开麦跟唱：在键盘上显示你唱的音")
            }
            .onChange(of: listening) { _, on in
                guard on else { return }
                Task {
                    let engine = AudioEngine.shared
                    let ok = await engine.enableMic()
                    engine.ensureRunning()
                    if !ok { listening = false; micMissing = true }
                }
            }
            if micMissing {
                Text("没有麦克风权限，或者没有找到麦克风。").font(.caption).foregroundStyle(.orange)
            }
            if listening {
                LivePitchStrip()
                Text("请戴耳机：外放时麦克风会把视频里老师的声音也当成你的。").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
        .onAppear {
            // created once here, not in init: SwiftUI runs a view's init on every redraw
            if video == nil { video = CourseVideo(exercise: exercise, file: file, autoplay: false) }
        }
        .onDisappear {
            listening = false
            video?.close()
            video = nil
        }
    }
}

/// The note being sung right now, on a keyboard that follows the voice.
struct LivePitchStrip: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05)) { _ in
            let f = AudioEngine.shared.latest(1).last
            let m: Double? = (f?.voiced ?? false) ? f?.midi : nil
            let key = m.map { Int($0.rounded()) }
            let sung: (key: Int, cents: Double)? = m.map { v in (Int(v.rounded()), (v - v.rounded()) * 100) }
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(m.map { Music.name($0) } ?? "—").font(.title2.monospacedDigit().weight(.bold))
                    if let m, let key {
                        Text(signedCents((m - Double(key)) * 100)).font(.callout.monospacedDigit())
                            .foregroundStyle(Color.cents((m - Double(key)) * 100))
                        Text(String(format: "%.1f Hz", f?.f0 ?? 0)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                PianoKeyboard(sung: sung, focus: key ?? 60, height: 90)
            }
        }
    }
}

/// Settings that apply everywhere: the teacher, where the videos are, demo packs.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                Picker("老师", selection: Binding(get: { model.teacherID }, set: { model.setTeacher($0) })) {
                    ForEach(Course.teachers) { t in
                        Text(t.name).tag(t.id)
                    }
                }
                Text(model.teacher.about + "。每位老师有自己的练习、周计划和进度，切换不会丢失另一位老师的进度。")
                    .font(.caption).foregroundStyle(.secondary)
                Link(destination: model.teacher.home) { Label("打开 \(model.teacher.name) 的频道", systemImage: "safari") }
            } header: {
                Text("课程")
            }
            Section {
                VideoFolderSetting()
            } header: {
                Text("课程视频和原声示范")
            } footer: {
                Text("一个文件夹放两位老师的全部视频即可。每个练习、今日练习的每一步、课程视频列表里都能直接打开对应视频跟着练；文件夹里有 clips.py 生成的 demo-pack 时，练习的示范自动换成老师原声，不用逐个导入。")
            }
            Section {
                Text("钢琴采样来自 FluidR3 GM 音色库（Frank Wen，CC BY 3.0）。")
                Text("课程视频和原声版权归各位老师所有。应用不包含任何课程音视频，只播放你自己设备上的文件或打开原网站。")
            } header: {
                Text("说明")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .navigationTitle("设置")
    }
}

/// Switches the teacher right where the course is shown; each teacher keeps their own progress.
struct TeacherPicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Picker("老师", selection: Binding(get: { model.teacherID }, set: { model.setTeacher($0) })) {
            ForEach(Course.teachers) { t in
                Text(t.name).tag(t.id)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

/// Toolbar button that opens the settings.
struct SettingsButton: View {
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: { Label("设置", systemImage: "gearshape") }
            .sheet(isPresented: $showing) {
                NavigationStack {
                    SettingsView()
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showing = false } } }
                }
                #if os(macOS)
                .frame(minWidth: 520, minHeight: 520)
                #endif
            }
    }
}

/// Where the course videos are kept on this device.
struct VideoFolderSetting: View {
    @Environment(VideoLibrary.self) private var videos
    @State private var picking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button { picking = true } label: {
                    Label(videos.folderName == nil ? "选择课程视频文件夹" : "更换视频文件夹", systemImage: "film.stack")
                }
                .buttonStyle(.borderless)
                if videos.folderName != nil {
                    Spacer()
                    Button("重新查找") { videos.rescan() }.buttonStyle(.borderless)
                    Button("移除", role: .destructive) { videos.clear() }.buttonStyle(.borderless)
                }
            }
            Text(status).font(.caption).foregroundStyle(.secondary)
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { res in
            if case .success(let url) = res { videos.choose(url) }
        }
    }

    private var status: String {
        guard let name = videos.folderName else {
            return "应用不带视频。选择存放课程视频的文件夹（例如 tools/course/media），之后所有练习都能直接打开对应视频，从这个练习的位置开始跟着练。"
        }
        if videos.scanning { return "正在查找「\(name)」里的视频…" }
        let lines = Course.teachers.map { t -> String in
            let r = videos.found(t)
            return r.total == 0 ? "\(t.name)：练习还没对应到视频" : "\(t.name)：\(r.found)/\(r.total) 集"
        }
        let demos = videos.demoClips > 0 ? "老师原声示范 \(videos.demoClips) 个练习。" : ""
        return "「\(name)」：" + lines.joined(separator: "；") + "。" + demos + "没找到的集仍然打开网站。"
    }
}
