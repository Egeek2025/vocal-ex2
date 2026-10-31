import SwiftUI
import AVKit

/// Opens the course video at this exercise: the local copy when the video folder has it, otherwise YouTube.
struct CourseVideoButton: View {
    @Environment(VideoLibrary.self) private var videos
    let exercise: Exercise
    let title: String
    @State private var showing = false

    var body: some View {
        if let file = videos.file(ep: exercise.ep) {
            Button { showing = true } label: { Label(title, systemImage: "play.rectangle.fill") }
                .buttonStyle(.borderless)
                .sheet(isPresented: $showing) { CourseVideoPlayer(exercise: exercise, file: file) }
        } else if let url = exercise.videoURL {
            Link(destination: url) { Label(title, systemImage: "play.rectangle") }
        }
    }
}

/// Plays a local course video from the exercise's place in it, with the episode's other exercises as jump points.
struct CourseVideoPlayer: View {
    @Environment(\.dismiss) private var dismiss
    let exercise: Exercise
    let file: URL
    @State private var player = AVPlayer()
    @State private var current: String

    init(exercise: Exercise, file: URL) {
        self.exercise = exercise
        self.file = file
        _current = State(initialValue: exercise.id)
    }

    private var points: [Exercise] {
        Course.exercises.filter { $0.ep == exercise.ep }.sorted { $0.t < $1.t }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VideoPlayer(player: player)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .background(.black)
                List {
                    Section {
                        ForEach(points) { p in
                            Button {
                                current = p.id
                                seek(p.t)
                            } label: {
                                HStack {
                                    Text(Course.mmss(p.t)).monospacedDigit().foregroundStyle(.secondary)
                                    Text(p.name)
                                    Text(p.syl).foregroundStyle(.secondary).lineLimit(1)
                                    Spacer()
                                    if p.id == current { Image(systemName: "speaker.wave.2.fill").foregroundStyle(.tint) }
                                }
                            }
                            .buttonStyle(.borderless)
                        }
                        Button { seek(0) } label: { Label("从头看", systemImage: "backward.end") }
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
            player.replaceCurrentItem(with: AVPlayerItem(url: file))
            seek(exercise.t)
        }
        .onDisappear {
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
    }

    private func seek(_ t: Int) {
        player.seek(to: CMTime(seconds: Double(t), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()
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
            return "应用不带视频。选择存放课程视频的文件夹（例如 tools/course/media），练习里的视频链接就会直接在应用里播放，并跳到这个练习的位置。"
        }
        if videos.scanning { return "正在查找「\(name)」里的视频…" }
        let total = Set(Course.exercises.map(\.ep)).count
        return "「\(name)」：找到 \(videos.episodesFound)/\(total) 集课程视频。没找到的集仍然打开 YouTube。"
    }
}
