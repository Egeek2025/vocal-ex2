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

/// Owns the player for a local course video and seeks it to exercises.
@Observable
final class CourseVideo {
    let player = AVPlayer()
    var current: String

    init(exercise: Exercise, file: URL) {
        current = exercise.id
        player.replaceCurrentItem(with: AVPlayerItem(url: file))
        seek(exercise, play: false)
    }

    func seek(_ e: Exercise, play: Bool = true) {
        current = e.id
        seek(to: e.t, play: play)
    }

    func seek(to t: Int, play: Bool = true) {
        player.seek(to: CMTime(seconds: Double(t), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        if play { player.play() }
    }

    func close() {
        player.pause()
        player.replaceCurrentItem(with: nil)
    }
}

/// Plays a local course video from the exercise's place in it, with the episode's other exercises as jump points.
struct CourseVideoPlayer: View {
    @Environment(\.dismiss) private var dismiss
    let exercise: Exercise
    @State private var video: CourseVideo

    init(exercise: Exercise, file: URL) {
        self.exercise = exercise
        _video = State(initialValue: CourseVideo(exercise: exercise, file: file))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VideoPlayer(player: video.player)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .background(.black)
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
        #if os(macOS)
        .frame(minWidth: 720, minHeight: 600)
        #endif
        .onAppear {
            AudioEngine.shared.prepareForVideo()
            video.player.play()
        }
        .onDisappear { video.close() }
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
    let exercise: Exercise
    @State private var video: CourseVideo
    @State private var listening = false
    @State private var micMissing = false

    init(exercise: Exercise, file: URL) {
        self.exercise = exercise
        _video = State(initialValue: CourseVideo(exercise: exercise, file: file))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VideoPlayer(player: video.player)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button { video.seek(exercise) } label: { Label("回到本练习 \(Course.mmss(exercise.t))", systemImage: "arrow.uturn.backward") }
                        .buttonStyle(.borderedProminent)
                    ForEach(jumpPoints(exercise).filter { $0.id != exercise.id }) { p in
                        Button("\(Course.mmss(p.t)) \(p.name)") { video.seek(p) }
                            .buttonStyle(.bordered)
                    }
                }
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
        .onDisappear {
            listening = false
            video.close()
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
