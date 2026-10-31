import Foundation
import AVFoundation

/// Recorded piano notes, one sample per semitone from C2 to C7, from the FluidR3 GM soundfont
/// (CC BY 3.0, via gleitz/midi-js-soundfonts), "Acoustic Grand Piano".
final class SampleBank {
    enum Kind: String { case piano }

    struct Sample {
        let data: [Float]
        /// file sample rate
        let rate: Double
        /// tuning error of the recording in cents, corrected at playback
        let cents: Double
        /// gain that brings every note to the same loudness
        let gain: Double
        /// sustained sounds loop their steady part; piano notes just decay
        let loops: Bool
    }

    static let range = 36...96
    // seconds from the trimmed start: the steady part used to sustain long voice notes
    static let loopStart = 0.6
    static let loopEnd = 2.6
    static let crossfade = 0.12

    let kind: Kind
    private(set) var samples: [Int: Sample] = [:]

    init(_ kind: Kind) { self.kind = kind }

    var isLoaded: Bool { !samples.isEmpty }

    /// Decode all samples from the app bundle. Call before scheduling notes that use them.
    func load() {
        guard samples.isEmpty else { return }
        let table = Self.pianoTable
        let target = 0.35
        var out: [Int: Sample] = [:]
        for m in Self.range {
            guard let url = Bundle.main.url(forResource: "\(kind.rawValue)_\(m)", withExtension: "m4a"),
                  let file = try? AVAudioFile(forReading: url),
                  let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
                  (try? file.read(into: buf)) != nil,
                  let ch = buf.floatChannelData?[0] else { continue }
            let n = Int(buf.frameLength)
            var lead = 0
            while lead < n && abs(ch[lead]) < 0.002 { lead += 1 }
            lead = max(0, lead - Int(0.003 * file.processingFormat.sampleRate))
            let data = Array(UnsafeBufferPointer(start: ch + lead, count: n - lead))
            let t = table[m] ?? (0, target)
            out[m] = Sample(data: data, rate: file.processingFormat.sampleRate, cents: t.0,
                            gain: target / max(0.005, t.1), loops: false)
        }
        samples = out
    }

    /// Nearest recorded note for a pitch.
    func sample(near m: Double) -> (Int, Sample)? {
        let k = min(Self.range.upperBound, max(Self.range.lowerBound, Int(m.rounded())))
        guard let s = samples[k] else { return nil }
        return (k, s)
    }

    /// Value at a fractional position. Looping samples crossfade their steady part so notes can last any length.
    static func value(_ s: Sample, at pos: inout Double) -> Float {
        let ls = loopStart * s.rate, le = loopEnd * s.rate, xf = crossfade * s.rate, len = le - ls
        let canLoop = s.loops && Double(s.data.count) > le + 2
        if canLoop {
            while pos >= le { pos -= len }
        } else if pos >= Double(s.data.count - 2) {
            return 0
        }
        func at(_ p: Double) -> Float {
            let i = Int(p), f = Float(p - Double(i))
            return s.data[i] * (1 - f) + s.data[i + 1] * f
        }
        var v = at(pos)
        if canLoop && pos > le - xf {
            let k = Float((pos - (le - xf)) / xf)
            v = v * (1 - k) + at(pos - len) * k
        }
        return v
    }

    // measured tuning (cents) and peak RMS of each piano recording
    static let pianoTable: [Int: (Double, Double)] = [
        36: (13.4, 0.0284),
        37: (12.5, 0.0279),
        38: (11.9, 0.0285),
        39: (11.9, 0.0423),
        40: (11.8, 0.0393),
        41: (11.6, 0.0395),
        42: (12.9, 0.0381),
        43: (13.5, 0.0432),
        44: (12.8, 0.0425),
        45: (13.2, 0.0432),
        46: (15.1, 0.0427),
        47: (12.8, 0.031),
        48: (12.9, 0.0319),
        49: (12.7, 0.0312),
        50: (13.1, 0.0308),
        51: (8.6, 0.0401),
        52: (9, 0.0386),
        53: (8.1, 0.037),
        54: (7.9, 0.0381),
        55: (15.4, 0.0294),
        56: (15.3, 0.028),
        57: (12.8, 0.0279),
        58: (14, 0.0272),
        59: (16.5, 0.0291),
        60: (15.5, 0.0284),
        61: (15.8, 0.0283),
        62: (14.6, 0.0282),
        63: (23.6, 0.0137),
        64: (23.6, 0.0135),
        65: (23, 0.0134),
        66: (22.7, 0.0131),
        67: (4.7, 0.0376),
        68: (4.6, 0.0371),
        69: (4.8, 0.0361),
        70: (4.6, 0.0357),
        71: (20.7, 0.0187),
        72: (21.2, 0.0175),
        73: (19.6, 0.0171),
        74: (19.2, 0.0165),
        75: (22.6, 0.014),
        76: (22.7, 0.0136),
        77: (21, 0.0126),
        78: (20.2, 0.0121),
        79: (25.9, 0.0107),
        80: (23.6, 0.0106),
        81: (25, 0.0102),
        82: (23.3, 0.01),
        83: (23.1, 0.0093),
        84: (22.3, 0.0092),
        85: (5.5, 0.0211),
        86: (6.8, 0.02),
        87: (5.7, 0.0187),
        88: (4.8, 0.0174),
        89: (6.3, 0.0161),
        90: (4.9, 0.0146),
        91: (7.8, 0.0217),
        92: (7.8, 0.0206),
        93: (7.8, 0.0193),
        94: (8.1, 0.0179),
        95: (8.1, 0.0017),
        96: (0, 0.0015),
    ]
}
