import Foundation
import Observation

/// A chapter of a course video as its uploader marked it (from the downloaded .info.json).
struct VideoChapter: Hashable {
    let title: String
    let start: Double
}

/// Course videos kept on the user's own disk, for every teacher. The app ships without them; the user
/// points it at one folder once (for example tools/course/media, where fetch.py saves media/<id>/<id>.mp4)
/// and it is remembered. A file belongs to an episode when its name contains that episode's video id
/// (YouTube id or Bilibili BV id).
@Observable
final class VideoLibrary {
    static let shared = VideoLibrary()
    static let extensions: Set<String> = ["mp4", "m4v", "mov"]

    private(set) var folderName: String?
    /// video id -> video file
    private(set) var files: [String: URL] = [:]
    /// video id -> title, chapters and length, from the .info.json the download tools save next to each video
    private(set) var titles: [String: String] = [:]
    private(set) var chapters: [String: [VideoChapter]] = [:]
    private(set) var durations: [String: Double] = [:]
    /// exercises that got a teacher's demo clip from a demo pack in the folder
    private(set) var demoClips = 0
    private(set) var scanning = false

    private var folder: URL?
    private let key = "videoFolderBookmark"

    private init() { restore() }

    func file(for exercise: Exercise) -> URL? {
        exercise.videoID.flatMap { files[$0] }
    }

    /// Episodes of a teacher's plan that have a video in the folder, out of those with a video at all.
    func found(_ teacher: Teacher) -> (found: Int, total: Int) {
        let ids = Set(teacher.exercises.compactMap(\.videoID))
        return (ids.filter { files[$0] != nil }.count, ids.count)
    }

    func choose(_ url: URL) {
        release()
        guard url.startAccessingSecurityScopedResource() || FileManager.default.isReadableFile(atPath: url.path) else { return }
        if let data = try? url.bookmarkData(options: Self.bookmarkOptions, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(data, forKey: key)
        }
        use(url)
    }

    func clear() {
        release()
        UserDefaults.standard.removeObject(forKey: key)
        folderName = nil
        files = [:]
        titles = [:]
        chapters = [:]
        durations = [:]
        demoClips = DemoStore.shared.useFolderPacks([])
    }

    func rescan() {
        if let folder { use(folder) }
    }

    #if os(macOS)
    private static let bookmarkOptions: URL.BookmarkCreationOptions = [.withSecurityScope, .securityScopeAllowOnlyReadAccess]
    private static let resolveOptions: URL.BookmarkResolutionOptions = [.withSecurityScope]
    #else
    private static let bookmarkOptions: URL.BookmarkCreationOptions = []
    private static let resolveOptions: URL.BookmarkResolutionOptions = []
    #endif

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: Self.resolveOptions, relativeTo: nil, bookmarkDataIsStale: &stale) else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        _ = url.startAccessingSecurityScopedResource()
        if stale, let fresh = try? url.bookmarkData(options: Self.bookmarkOptions, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: key)
        }
        use(url)
    }

    private func release() {
        folder?.stopAccessingSecurityScopedResource()
        folder = nil
    }

    private func use(_ url: URL) {
        folder = url
        folderName = url.lastPathComponent
        scanning = true
        let ids = Set(Course.teachers.flatMap { $0.videos.values.map(Teacher.plainID) })
        Task.detached(priority: .utility) {
            let r = Self.scan(url, ids: ids)
            let clips = DemoStore.shared.useFolderPacks(r.manifests)
            await MainActor.run {
                self.files = r.files
                self.titles = r.titles
                self.chapters = r.chapters
                self.durations = r.durations
                self.demoClips = clips
                self.scanning = false
            }
        }
    }

    private struct ScanResult {
        var files: [String: URL] = [:]
        var titles: [String: String] = [:]
        var chapters: [String: [VideoChapter]] = [:]
        var durations: [String: Double] = [:]
        var manifests: [URL] = []
    }

    /// Everything the app uses from the folder: videos by id, their titles and chapters, and demo pack manifests.
    private static func scan(_ root: URL, ids: Set<String>) -> ScanResult {
        var found: [String: URL] = [:], manifests: [URL] = []
        var r = ScanResult()
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                        options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return r }
        for case let url as URL in walk {
            if url.lastPathComponent == "manifest.json" {
                manifests.append(url)
                continue
            }
            guard extensions.contains(url.pathExtension.lowercased()) else { continue }
            let name = url.deletingPathExtension().lastPathComponent
            if ids.contains(name) {
                found[name] = url
            } else if let id = ids.first(where: { name.contains($0) }), found[id] == nil {
                found[id] = url
            }
        }
        for (id, url) in found {
            let info = url.deletingLastPathComponent().appendingPathComponent("\(id).info.json")
            guard let data = try? Data(contentsOf: info),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            r.titles[id] = obj["title"] as? String
            r.durations[id] = (obj["duration"] as? NSNumber)?.doubleValue
            let list = (obj["chapters"] as? [[String: Any]] ?? []).compactMap { c -> VideoChapter? in
                guard let t = c["title"] as? String, let start = (c["start_time"] as? NSNumber)?.doubleValue else { return nil }
                return VideoChapter(title: t, start: start)
            }
            if !list.isEmpty { r.chapters[id] = list }
        }
        r.files = found
        r.manifests = manifests
        return r
    }

    func title(for exercise: Exercise) -> String? { exercise.videoID.flatMap { titles[$0] } }
    func chapters(for exercise: Exercise) -> [VideoChapter] { exercise.videoID.flatMap { chapters[$0] } ?? [] }
    func duration(for exercise: Exercise) -> Double? { exercise.videoID.flatMap { durations[$0] } }
}
