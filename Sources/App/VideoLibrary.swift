import Foundation
import Observation

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
            let found = Self.scan(url, ids: ids)
            await MainActor.run {
                self.files = found
                self.scanning = false
            }
        }
    }

    private static func scan(_ root: URL, ids: Set<String>) -> [String: URL] {
        var found: [String: URL] = [:]
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                        options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [:] }
        for case let url as URL in walk {
            guard extensions.contains(url.pathExtension.lowercased()) else { continue }
            let name = url.deletingPathExtension().lastPathComponent
            if ids.contains(name) {
                found[name] = url
            } else if let id = ids.first(where: { name.contains($0) }), found[id] == nil {
                found[id] = url
            }
        }
        return found
    }
}
