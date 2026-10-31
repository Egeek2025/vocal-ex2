import Foundation

enum Music {
    static let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    /// MIDI number -> note name, e.g. 60 -> "C4"
    static func name(_ m: Double) -> String {
        let r = Int(m.rounded())
        let pc = ((r % 12) + 12) % 12
        let octave = Int(floor(Double(r) / 12.0)) - 1
        return names[pc] + String(octave)
    }

    static func name(_ m: Int) -> String { name(Double(m)) }

    static func isNatural(_ m: Int) -> Bool { names[((m % 12) + 12) % 12].count == 1 }

    static func freq(_ m: Double) -> Double { 440 * pow(2, (m - 69) / 12) }

    static func midi(_ f: Double) -> Double { 69 + 12 * log2(f / 440) }

    /// Fold a cent offset into ±600 so an octave error does not count as a huge miss.
    static func fold(_ c: Double) -> Double {
        var c = c
        while c > 600 { c -= 1200 }
        while c < -600 { c += 1200 }
        return c
    }
}

extension Array where Element == Double {
    var mean: Double { isEmpty ? 0 : reduce(0, +) / Double(count) }
    var stdDev: Double {
        guard count > 1 else { return 0 }
        let m = mean
        return (map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(count)).squareRoot()
    }
    var median: Double { isEmpty ? 0 : sorted()[count / 2] }
}

func signedCents(_ c: Double) -> String {
    let r = Int(c.rounded())
    return r > 0 ? "+\(r)" : "\(r)"
}

/// One analysis frame from the microphone or a file.
struct Frame {
    var t: Double
    var f0: Double
    var clarity: Double
    var rms: Double
    var hi: Double?
    var voiced: Bool
    var midi: Double
}

struct VoiceRange: Codable, Hashable {
    var name: String
    var lo: Int
    var hi: Int

    static let presets: [(key: String, range: VoiceRange)] = [
        ("bass", VoiceRange(name: "男低音", lo: 40, hi: 64)),
        ("bari", VoiceRange(name: "男中音", lo: 45, hi: 67)),
        ("tenor", VoiceRange(name: "男高音", lo: 48, hi: 72)),
        ("alto", VoiceRange(name: "女低音", lo: 53, hi: 76)),
        ("mezzo", VoiceRange(name: "女中音", lo: 57, hi: 81)),
        ("sop", VoiceRange(name: "女高音", lo: 60, hi: 84)),
    ]
}

struct LogEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var date = Date()
    var ex: String
    var acc: Double? = nil
    var mean: Double? = nil
    var std: Double? = nil
    var keys: Int? = nil
    var hi: Double? = nil
    var vibRate: Double? = nil
    var vibExt: Double? = nil
    var sec: Double? = nil
    var rangeLo: Int? = nil
    var rangeHi: Int? = nil
}
