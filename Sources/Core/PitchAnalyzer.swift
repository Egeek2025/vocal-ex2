import Foundation

/// Iterative radix-2 complex FFT. Pure Swift so the analyzer has no platform dependency.
final class FFT {
    let n: Int
    private let cosT: [Double]
    private let sinT: [Double]
    private let rev: [Int]

    init(n: Int) {
        self.n = n
        cosT = (0..<n / 2).map { cos(2 * Double.pi * Double($0) / Double(n)) }
        sinT = (0..<n / 2).map { sin(2 * Double.pi * Double($0) / Double(n)) }
        let lev = Int(log2(Double(n)).rounded())
        rev = (0..<n).map { i in
            var r = 0, x = i
            for _ in 0..<lev { r = (r << 1) | (x & 1); x >>= 1 }
            return r
        }
    }

    func transform(_ re: inout [Double], _ im: inout [Double], inverse: Bool) {
        for i in 0..<n {
            let j = rev[i]
            if j > i { re.swapAt(i, j); im.swapAt(i, j) }
        }
        var size = 2
        while size <= n {
            let half = size / 2, step = n / size
            var i = 0
            while i < n {
                var k = 0
                for j in i..<(i + half) {
                    let l = j + half
                    let c = cosT[k], s = inverse ? sinT[k] : -sinT[k]
                    let tr = re[l] * c - im[l] * s
                    let ti = re[l] * s + im[l] * c
                    re[l] = re[j] - tr
                    im[l] = im[j] - ti
                    re[j] += tr
                    im[j] += ti
                    k += step
                }
                i += size
            }
            size *= 2
        }
    }
}

struct PitchResult {
    var f0: Double = 0
    var clarity: Double = 0
    var rms: Double = 0
    /// Energy 2–4 kHz relative to 50 Hz–2 kHz, in dB ("brightness").
    var hi: Double? = nil
    var centroid: Double = 0
}

/// McLeod pitch method (normalized square difference) computed through FFT autocorrelation.
final class PitchAnalyzer {
    let w: Int
    private let fft: FFT
    private let fftW: FFT
    private var re: [Double]
    private var im: [Double]
    private var nsdf: [Double]
    private var wr: [Double]
    private var wi: [Double]
    private let hann: [Double]

    init(windowSize w: Int = 2048) {
        self.w = w
        fft = FFT(n: w * 2)
        fftW = FFT(n: w)
        re = Array(repeating: 0, count: w * 2)
        im = Array(repeating: 0, count: w * 2)
        nsdf = Array(repeating: 0, count: w)
        wr = Array(repeating: 0, count: w)
        wi = Array(repeating: 0, count: w)
        hann = (0..<w).map { 0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(w - 1)) }
    }

    func analyze(_ x: [Float], offset: Int = 0, sampleRate sr: Double) -> PitchResult {
        let n = w * 2
        var e = 0.0
        for i in 0..<w { let v = Double(x[offset + i]); e += v * v }
        var out = PitchResult()
        out.rms = (e / Double(w)).squareRoot()
        if out.rms < 0.002 { return out }

        // brightness on a Hann-windowed frame
        for i in 0..<w { wr[i] = Double(x[offset + i]) * hann[i]; wi[i] = 0 }
        fftW.transform(&wr, &wi, inverse: false)
        var lo = 0.0, hi = 0.0, cs = 0.0, ps = 0.0
        let bw = sr / Double(w)
        for i in 1..<(w / 2) {
            let f = Double(i) * bw, p = wr[i] * wr[i] + wi[i] * wi[i]
            if f >= 50 && f < 2000 { lo += p } else if f >= 2000 && f < 4000 { hi += p }
            if f >= 50 && f < 5000 { cs += f * p; ps += p }
        }
        if lo > 0 && hi > 0 { out.hi = 10 * log10(hi / lo) }
        out.centroid = ps > 0 ? cs / ps : 0

        // autocorrelation r(τ) via |FFT|², then NSDF
        for i in 0..<n { re[i] = i < w ? Double(x[offset + i]) : 0; im[i] = 0 }
        fft.transform(&re, &im, inverse: false)
        for i in 0..<n { re[i] = re[i] * re[i] + im[i] * im[i]; im[i] = 0 }
        fft.transform(&re, &im, inverse: true)
        let maxLag = min(w - 2, Int(sr / 55)), minLag = max(2, Int(sr / 1500))
        var m = 2 * e
        for t in 0...maxLag {
            if t > 0 {
                let a = Double(x[offset + t - 1]), b = Double(x[offset + w - t])
                m -= a * a + b * b
            }
            nsdf[t] = m > 1e-9 ? 2 * (re[t] / Double(n)) / m : 0
        }

        // key maxima between positive zero crossings
        var t = 1
        while t < maxLag && nsdf[t] > 0 { t += 1 }
        var peaks: [Int] = []
        var maxP = 0.0
        while t < maxLag {
            while t < maxLag && nsdf[t] <= 0 { t += 1 }
            var pv = -1.0, pt = -1
            while t < maxLag && nsdf[t] > 0 {
                if nsdf[t] > pv { pv = nsdf[t]; pt = t }
                t += 1
            }
            if pt > 0 && t < maxLag {
                peaks.append(pt)
                if pv > maxP { maxP = pv }
            }
        }
        guard !peaks.isEmpty else { return out }
        let thr = 0.9 * maxP
        guard let sel = peaks.first(where: { $0 >= minLag && nsdf[$0] >= thr }) else { return out }
        let a = nsdf[sel - 1], b = nsdf[sel], c = nsdf[sel + 1]
        let den = a - 2 * b + c
        let sh = den != 0 ? (a - c) / (2 * den) : 0
        out.f0 = sr / (Double(sel) + sh)
        out.clarity = b - 0.25 * (a - c) * sh
        return out
    }
}
