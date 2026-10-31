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

/// Stores demos under Application Support/demos and renders them in other keys.
final class DemoStore {
    static let shared = DemoStore()

    private init() {}

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
        return nil
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
        guard let x = try? Self.decodeMono(audioURL(id)) else { return nil }
        return (x.0, x.1, info)
    }

    /// Import a demo pack folder (manifest.json plus one clip per exercise). Returns how many demos were imported.
    func importPack(folder: URL) throws -> (imported: [String], failed: [String]) {
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: folder.appendingPathComponent("manifest.json"))
        let entries = try JSONDecoder().decode([String: PackEntry].self, from: data)
        var ok: [String] = [], failed: [String] = []
        for (id, e) in entries.sorted(by: { $0.key < $1.key }) {
            // only clips that sing the exercise's whole pattern
            guard let p = Course.byID[id]?.pattern, let j = e.pattern, Jianpu.matches(j, pattern: p) else {
                if Course.byID[id] != nil { failed.append(id) }
                continue
            }
            do {
                let (raw, rate) = try Self.decodeMono(folder.appendingPathComponent(e.file))
                let x = Self.trimSilence(raw, rate: rate)
                guard Double(x.count) / rate > 0.3 else { failed.append(id); continue }
                let info = DemoInfo(root: e.root, bpm: e.bpm, duration: Double(x.count) / rate, imported: true, courseEpisode: e.ep)
                try save(id: id, samples: x, rate: rate, info: info)
                ok.append(id)
            } catch {
                failed.append(id)
            }
        }
        return (ok, failed)
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
