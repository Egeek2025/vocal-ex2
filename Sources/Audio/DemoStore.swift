import Foundation
import AVFoundation

/// A sung demo for one exercise (a teacher's or your own), recorded in the app or imported from a file.
struct DemoInfo: Codable, Equatable {
    /// root note the demo was sung on; playback shifts it to each key
    var root: Int
    /// tempo it was recorded at; nil for imported audio, which is played at its own speed
    var bpm: Double?
    var duration: Double
    var imported: Bool
    var date = Date()
    /// cut from the course video by tools/course/clips.py; the episode it came from
    var courseEpisode: Int? = nil
}

/// One entry of the demo pack's manifest.json written by tools/course/clips.py.
private struct PackEntry: Decodable {
    let file: String
    let root: Int
    let bpm: Double?
    let ep: Int?
    /// notes the analysis found in the clip, as jianpu
    let pattern: String?
}

/// Stores demos under Application Support/demos and renders them in other keys. A demo the user recorded
/// or imported wins; otherwise a clip from a demo pack inside the course video folder is used directly.
final class DemoStore {
    static let shared = DemoStore()

    private init() {}

    /// Clips of the demo packs (tools/course/clips.py) found in the course video folder, by exercise.
    private var folderClips: [String: (url: URL, entry: PackEntry)] = [:]
    private var folderInfo: [String: DemoInfo] = [:]
    private let packLock = NSLock()

    /// Use the demo packs found in the video folder: each manifest.json lists one clip per exercise.
    /// Only clips that sing the exercise's whole pattern are used. Returns how many exercises got one.
    @discardableResult
    func useFolderPacks(_ manifests: [URL]) -> Int {
        var found: [String: (url: URL, entry: PackEntry)] = [:]
        for m in manifests {
            guard let data = try? Data(contentsOf: m),
                  let entries = try? JSONDecoder().decode([String: PackEntry].self, from: data) else { continue }
            let dir = m.deletingLastPathComponent()
            for (id, e) in entries {
                guard let p = Course.byID[id]?.pattern, let j = e.pattern, Jianpu.matches(j, pattern: p) else { continue }
                found[id] = (dir.appendingPathComponent(e.file), e)
            }
        }
        packLock.lock()
        folderClips = found
        folderInfo = [:]
        packLock.unlock()
        return found.count
    }

    /// True when the exercise's demo comes from the video folder (not one the user saved).
    func isFromFolder(_ id: String) -> Bool {
        packLock.lock()
        defer { packLock.unlock() }
        return !FileManager.default.fileExists(atPath: audioURL(id).path) && folderClips[id] != nil
    }

    private func folderAudio(_ id: String) -> ([Float], Double)? {
        packLock.lock()
        let clip = folderClips[id]
        packLock.unlock()
        guard let clip, let decoded = try? Self.decodeMono(clip.url) else { return nil }
        return (Self.trimSilence(decoded.0, rate: decoded.1), decoded.1)
    }

    private func folderDemoInfo(_ id: String) -> DemoInfo? {
        packLock.lock()
        let cached = folderInfo[id], clip = folderClips[id]
        packLock.unlock()
        if let cached { return cached }
        guard let clip, let audio = folderAudio(id) else { return nil }
        let e = clip.entry
        let info = DemoInfo(root: e.root, bpm: e.bpm, duration: Double(audio.0.count) / audio.1, imported: true, courseEpisode: e.ep)
        packLock.lock()
        folderInfo[id] = info
        packLock.unlock()
        return info
    }

    private var dir: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("demos")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private func audioURL(_ id: String) -> URL { dir.appendingPathComponent("\(id).caf") }
    private func infoURL(_ id: String) -> URL { dir.appendingPathComponent("\(id).json") }

    func info(for id: String) -> DemoInfo? {
        if let data = try? Data(contentsOf: infoURL(id)), let info = try? JSONDecoder().decode(DemoInfo.self, from: data) {
            return info
        }
        return folderDemoInfo(id)
    }

    func setInfo(_ info: DemoInfo, for id: String) {
        if let data = try? JSONEncoder().encode(info) { try? data.write(to: infoURL(id), options: .atomic) }
    }

    func save(id: String, samples: [Float], rate: Double, info: DemoInfo) throws {
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(samples.count)),
              let ch = buf.floatChannelData?[0] else { throw CocoaError(.fileWriteUnknown) }
        buf.frameLength = AVAudioFrameCount(samples.count)
        for i in 0..<samples.count { ch[i] = samples[i] }
        try? FileManager.default.removeItem(at: audioURL(id))
        let file = try AVAudioFile(forWriting: audioURL(id), settings: fmt.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buf)
        setInfo(info, for: id)
    }

    func delete(id: String) {
        try? FileManager.default.removeItem(at: audioURL(id))
        try? FileManager.default.removeItem(at: infoURL(id))
    }

    func load(id: String) -> (samples: [Float], rate: Double, info: DemoInfo)? {
        guard let info = info(for: id) else { return nil }
        // a corrected root saved for a folder clip has an info file but no audio of its own
        if let x = try? Self.decodeMono(audioURL(id)) { return (x.0, x.1, info) }
        if let x = folderAudio(id) { return (x.0, x.1, info) }
        return nil
    }

    // MARK: audio helpers

    /// Decode any audio file Apple can read into mono float samples.
    static func decodeMono(_ url: URL, maxSeconds: Double = 60) throws -> ([Float], Double) {
        let file = try AVAudioFile(forReading: url)
        let fmt = file.processingFormat
        let n = AVAudioFrameCount(min(file.length, AVAudioFramePosition(fmt.sampleRate * maxSeconds)))
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
        return (x, fmt.sampleRate)
    }

    /// Cut silence at both ends (relative to the loudest part), keeping a few milliseconds of lead-in.
    static func trimSilence(_ x: [Float], rate: Double) -> [Float] {
        guard !x.isEmpty else { return x }
        let win = max(1, Int(rate * 0.01))
        var peak: Float = 0
        var levels: [Float] = []
        var i = 0
        while i < x.count {
            let j = min(x.count, i + win)
            var e: Float = 0
            for k in i..<j { e += x[k] * x[k] }
            let r = (e / Float(j - i)).squareRoot()
            levels.append(r)
            peak = max(peak, r)
            i = j
        }
        let thr = max(0.004, peak * 0.06)
        guard let a = levels.firstIndex(where: { $0 > thr }), let b = levels.lastIndex(where: { $0 > thr }) else { return x }
        let s = max(0, a * win - Int(rate * 0.02)), e = min(x.count, (b + 1) * win + Int(rate * 0.15))
        return Array(x[s..<e])
    }

    /// Guess the root a demo was sung on from its first steady note.
    static func detectRoot(_ x: [Float], rate: Double, pattern: Pattern) -> Int? {
        let anz = PitchAnalyzer(windowSize: 2048)
        let hop = Int(rate / 80)
        var run: [Double] = []
        var i = 0
        while i + 2048 < x.count {
            let r = anz.analyze(x, offset: i, sampleRate: rate)
            if r.f0 > 0 && r.clarity > 0.8 {
                let m = Music.midi(r.f0)
                if let last = run.last, abs(m - last) > 0.6 { run = [] }
                run.append(m)
                if Double(run.count * hop) / rate >= 0.15 {
                    let first = pattern.steps.first?.s ?? 0
                    return Int(run.median.rounded()) - first
                }
            } else {
                run = []
            }
            i += hop
        }
        return nil
    }

    /// Shift a demo by some semitones and change its speed without changing pitch, using Apple's time-pitch unit offline.
    static func render(_ x: [Float], rate: Double, semitones: Double, speed: Double) throws -> [Float] {
        if abs(semitones) < 0.01 && abs(speed - 1) < 0.001 { return x }
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let src = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(x.count)),
              let ch = src.floatChannelData?[0] else { throw CocoaError(.featureUnsupported) }
        src.frameLength = AVAudioFrameCount(x.count)
        for i in 0..<x.count { ch[i] = x[i] }

        let e = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let tp = AVAudioUnitTimePitch()
        tp.pitch = Float(semitones * 100)
        tp.rate = Float(speed)
        e.attach(player)
        e.attach(tp)
        e.connect(player, to: tp, format: fmt)
        e.connect(tp, to: e.mainMixerNode, format: fmt)
        try e.enableManualRenderingMode(.offline, format: fmt, maximumFrameCount: 4096)
        try e.start()
        player.scheduleBuffer(src, at: nil)
        player.play()

        let total = Int(Double(x.count) / speed + rate * 0.4)
        var out: [Float] = []
        out.reserveCapacity(total)
        guard let chunk = AVAudioPCMBuffer(pcmFormat: e.manualRenderingFormat, frameCapacity: e.manualRenderingMaximumFrameCount) else {
            throw CocoaError(.featureUnsupported)
        }
        while out.count < total {
            let n = AVAudioFrameCount(min(Int(chunk.frameCapacity), total - out.count))
            let status = try e.renderOffline(n, to: chunk)
            guard status == .success, let c = chunk.floatChannelData?[0] else { break }
            out.append(contentsOf: UnsafeBufferPointer(start: c, count: Int(chunk.frameLength)))
        }
        player.stop()
        e.stop()
        return trimSilence(out, rate: rate)
    }
}
