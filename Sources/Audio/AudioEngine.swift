import Foundation
import AVFoundation

/// A scheduled sound. Times are host-clock seconds (see `AudioEngine.now()`).
final class ToneNote {
    enum Kind { case synth, piano, tick, clip }

    let kind: Kind
    let m0: Double
    let m1: Double?
    let t0: Double
    let t1: Double
    let vol: Double
    /// recorded audio for `.clip` (mono) and its sample rate
    let clip: [Float]?
    let clipRate: Double

    // playback state (audio thread only)
    var phase: Double = 0
    var sample: SampleBank.Sample? = nil
    var sampleKey = 0
    var pos: Double = 0

    init(_ kind: Kind, m0: Double, m1: Double? = nil, t0: Double, t1: Double, vol: Double, clip: [Float]? = nil, clipRate: Double = 48000) {
        self.kind = kind
        self.m0 = m0
        self.m1 = m1
        self.t0 = t0
        self.t1 = t1
        self.vol = vol
        self.clip = clip
        self.clipRate = clipRate
    }

    /// Metronome click; `accent` marks the first beat of a bar.
    static func tick(at t: Double, accent: Bool = false, vol: Double = 0.12) -> ToneNote {
        ToneNote(.tick, m0: accent ? 91 : 84, t0: t, t1: t + 0.1, vol: accent ? vol * 1.3 : vol)
    }
}

/// Plays reference sounds and turns the microphone into pitch frames.
/// Both sides share the host clock, so a sung frame can be compared with the note that was scheduled for that moment.
final class AudioEngine {
    static let shared = AudioEngine()

    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private var outRate: Double = 48000

    private let noteLock = NSLock()
    private var notes: [ToneNote] = []

    private let frameLock = NSLock()
    private var frameStore: [Frame] = []

    let piano = SampleBank(.piano)

    private(set) var micEnabled = false
    private(set) var inputRate: Double = 48000
    private var sessionConfigured = false

    // touched only on the tap thread
    private let analyzer = PitchAnalyzer(windowSize: 2048)
    private var history: [Float] = []
    private var sinceHop = 0

    // raw microphone capture for recording demos
    private let captureLock = NSLock()
    private var capturing = false
    private var captured: [Float] = []
    private var captureStart: Double = 0

    // The engine and the microphone cost power even when silent, so they stop after a short idle spell
    // and start again on the next use. Main thread only.
    private var active = false
    private var lastUse: Double = 0
    private var idleTimer: Timer?
    private let idleAfter: Double = 20

    private init() {
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            guard let self, self.active else { return }
            if !self.engine.isRunning { try? self.engine.start() }
        }
    }

    func now() -> Double { AVAudioTime.seconds(forHostTime: mach_absolute_time()) }

    // MARK: setup

    #if os(iOS)
    private func configureSession() {
        guard !sessionConfigured else { return }
        let s = AVAudioSession.sharedInstance()
        do {
            // .measurement turns off the system's voice processing and automatic gain
            try s.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try s.setPreferredIOBufferDuration(0.01)
            try s.setActive(true)
            sessionConfigured = true
        } catch {
            print("Audio session error: \(error)")
        }
    }
    #endif

    private func setupSynth() {
        let sr = engine.outputNode.outputFormat(forBus: 0).sampleRate
        outRate = sr > 0 ? sr : 48000
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: outRate, channels: 1) else { return }
        let node = AVAudioSourceNode(format: fmt) { [unowned self] _, ts, frameCount, abl -> OSStatus in
            let t0: Double = ts.pointee.mFlags.contains(.hostTimeValid)
                ? AVAudioTime.seconds(forHostTime: ts.pointee.mHostTime) : self.now()
            self.render(abl, frames: Int(frameCount), t0: t0)
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: fmt)
        source = node
    }

    @discardableResult
    func ensureRunning() -> Bool {
        #if os(iOS)
        configureSession()
        #endif
        piano.load()
        if source == nil { setupSynth() }
        touch()
        if engine.isRunning { return true }
        engine.prepare()
        do {
            try engine.start()
            active = true
            startIdleTimer()
            return true
        } catch {
            print("Engine start error: \(error)")
            return false
        }
    }

    /// Before a course video plays: let go of the audio hardware if nothing is playing, and on iOS
    /// switch to movie playback so the video is heard with the silent switch on. The next practice
    /// sets the recording session up again.
    func prepareForVideo() {
        stopIfIdle(force: true)
        #if os(iOS)
        guard !active else { return }
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .moviePlayback)
        try? s.setActive(true)
        sessionConfigured = false
        #endif
    }

    /// Marks the engine as in use, which keeps it from going idle.
    private func touch() { lastUse = now() }

    private func startIdleTimer() {
        guard idleTimer == nil else { return }
        let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.stopIfIdle() }
        t.tolerance = 2
        RunLoop.main.add(t, forMode: .common)
        idleTimer = t
    }

    /// Stops the engine and the microphone once nothing is scheduled, nothing is being recorded
    /// and nobody has asked for sound or pitch for a while. With `force`, the wait is skipped
    /// (the app went to the background), but sounds still playing are not cut off.
    func stopIfIdle(force: Bool = false) {
        guard active else { return }
        let t = now()
        noteLock.lock()
        let pending = notes.contains { $0.t1 + 2 > t }
        noteLock.unlock()
        captureLock.lock()
        let recording = capturing
        captureLock.unlock()
        guard !pending, !recording, force || t - lastUse > idleAfter else { return }
        idleTimer?.invalidate()
        idleTimer = nil
        active = false
        if micEnabled {
            engine.inputNode.removeTap(onBus: 0)
            micEnabled = false
        }
        engine.stop()
        clearNotes()
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        sessionConfigured = false
        #endif
    }

    /// Ask for microphone permission and start listening. Returns false if refused or no input exists.
    func enableMic() async -> Bool {
        if micEnabled { return true }
        #if os(iOS)
        configureSession()
        let granted = await AVAudioApplication.requestRecordPermission()
        #else
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        #endif
        guard granted else { return false }
        return await MainActor.run { installMic() }
    }

    private func installMic() -> Bool {
        if micEnabled { return true }
        if source == nil { setupSynth() }
        let wasRunning = engine.isRunning
        if wasRunning { engine.stop() }
        let input = engine.inputNode
        let fmt = input.outputFormat(forBus: 0)
        guard fmt.sampleRate > 0, fmt.channelCount > 0 else {
            if wasRunning { try? engine.start() }
            return false
        }
        inputRate = fmt.sampleRate
        history.removeAll()
        sinceHop = 0
        input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buf, when in
            self?.process(buf, when)
        }
        micEnabled = true
        return ensureRunning()
    }

    // MARK: scheduled sounds

    func schedule(_ new: [ToneNote]) {
        touch()
        noteLock.lock()
        notes.append(contentsOf: new)
        noteLock.unlock()
    }

    func clearNotes() {
        noteLock.lock()
        notes.removeAll()
        noteLock.unlock()
    }

    private func render(_ abl: UnsafeMutablePointer<AudioBufferList>, frames n: Int, t0: Double) {
        let bufs = UnsafeMutableAudioBufferListPointer(abl)
        for buf in bufs {
            guard let p = buf.mData?.assumingMemoryBound(to: Float.self) else { continue }
            for i in 0..<n { p[i] = 0 }
        }
        var active: [ToneNote] = []
        if noteLock.try() {
            notes.removeAll { t0 > $0.t1 + 3 }
            let tEnd = t0 + Double(n) / outRate
            active = notes.filter { $0.t0 < tEnd && $0.t1 + ($0.kind == .piano ? 1.5 : 0.35) > t0 }
            noteLock.unlock()
        }
        guard !active.isEmpty, let first = bufs.first?.mData?.assumingMemoryBound(to: Float.self) else { return }
        let dt = 1.0 / outRate
        let twoPi = 2 * Double.pi
        for note in active {
            if note.kind == .piano && note.sample == nil {
                if let found = piano.sample(near: note.m0) {
                    note.sampleKey = found.0
                    note.sample = found.1
                }
            }
            for i in 0..<n {
                let t = t0 + Double(i) * dt
                if t < note.t0 { continue }
                let a = t - note.t0
                switch note.kind {
                case .tick:
                    if a > 0.1 { break }
                    note.phase += twoPi * Music.freq(note.m0) * dt
                    let env = note.vol * min(1, a / 0.005) * exp(-a / 0.025)
                    first[i] += Float(env * sin(note.phase))

                case .clip:
                    guard let clip = note.clip, note.pos < Double(clip.count - 2) else { break }
                    let k = Int(note.pos), f = Float(note.pos - Double(k))
                    var env = note.vol
                    let rel = note.t1 - 0.05
                    if t > rel { env *= exp(-(t - rel) / 0.05) }
                    first[i] += Float(env) * (clip[k] * (1 - f) + clip[k + 1] * f)
                    note.pos += note.clipRate / outRate

                case .piano, .synth:
                    let tail = note.kind == .piano ? 1.5 : 0.3
                    if t > note.t1 + tail { break }
                    var m = note.m0
                    if let m1 = note.m1 {
                        let k = min(1, max(0, (t - note.t0) / (note.t1 - note.t0)))
                        m = note.m0 + (m1 - note.m0) * k
                    }
                    if let smp = note.sample {
                        // resample the nearest recording to the exact (possibly gliding) pitch, correcting its tuning
                        let ratio = smp.rate / outRate * pow(2, (m - Double(note.sampleKey) - smp.cents / 100) / 12)
                        var env = note.vol * smp.gain * min(1, a / 0.01)
                        let rel = note.t1 - 0.04
                        if t > rel { env *= exp(-(t - rel) / (note.kind == .piano ? 0.25 : 0.06)) }
                        first[i] += Float(env) * SampleBank.value(smp, at: &note.pos)
                        note.pos += ratio
                    } else {
                        note.phase += twoPi * Music.freq(m) * dt
                        if note.phase > twoPi * 1000 { note.phase -= twoPi * 1000 }
                        var env = a < 0.015 ? note.vol * a / 0.015 : note.vol * (0.55 + 0.45 * exp(-(a - 0.015) / 0.3))
                        let rel = note.t1 - 0.04
                        if t > rel { env *= exp(-(t - rel) / 0.035) }
                        let tri = 2 / Double.pi * asin(sin(note.phase))
                        first[i] += Float(env * (tri + 0.22 * sin(2 * note.phase)))
                    }
                }
            }
        }
        for i in 0..<n { first[i] = Float(tanh(Double(first[i]))) }
        for buf in bufs.dropFirst() {
            guard let p = buf.mData?.assumingMemoryBound(to: Float.self) else { continue }
            for i in 0..<n { p[i] = first[i] }
        }
    }

    // MARK: microphone

    private func process(_ buf: AVAudioPCMBuffer, _ when: AVAudioTime) {
        guard let ch = buf.floatChannelData?[0] else { return }
        let n = Int(buf.frameLength), sr = buf.format.sampleRate
        guard n > 0, sr > 0 else { return }
        let start = when.isHostTimeValid ? AVAudioTime.seconds(forHostTime: when.hostTime) : now() - Double(n) / sr
        let chunk = UnsafeBufferPointer(start: ch, count: n)

        captureLock.lock()
        if capturing {
            if captured.isEmpty { captureStart = start }
            captured.append(contentsOf: chunk)
        }
        captureLock.unlock()

        history.append(contentsOf: chunk)
        let endTime = start + Double(n) / sr
        let hop = Int(sr / 60), w = analyzer.w
        sinceHop += n
        var out: [Frame] = []
        while sinceHop >= hop {
            sinceHop -= hop
            let endIdx = history.count - sinceHop
            guard endIdx >= w else { continue }
            let r = analyzer.analyze(history, offset: endIdx - w, sampleRate: sr)
            let t = endTime - Double(sinceHop) / sr - Double(w / 2) / sr
            let voiced = r.f0 > 0 && r.clarity > 0.78 && r.rms > 0.006
            out.append(Frame(t: t, f0: r.f0, clarity: r.clarity, rms: r.rms, hi: r.hi, voiced: voiced,
                             midi: voiced ? Music.midi(r.f0) : 0))
        }
        if history.count > w * 3 { history.removeFirst(history.count - w * 2) }
        guard !out.isEmpty else { return }
        frameLock.lock()
        frameStore.append(contentsOf: out)
        if frameStore.count > 40000 { frameStore.removeFirst(10000) }
        frameLock.unlock()
    }

    func startCapture() {
        captureLock.lock()
        captured.removeAll()
        capturing = true
        captureLock.unlock()
    }

    /// Stop capturing and return the samples between two host times.
    func stopCapture(from t0: Double, to t1: Double) -> [Float] {
        captureLock.lock()
        capturing = false
        let data = captured, start = captureStart
        captured.removeAll()
        captureLock.unlock()
        let a = max(0, Int((t0 - start) * inputRate)), b = min(data.count, Int((t1 - start) * inputRate))
        return b > a ? Array(data[a..<b]) : []
    }

    func frames(since t: Double) -> [Frame] {
        touch()
        frameLock.lock()
        defer { frameLock.unlock() }
        guard let idx = frameStore.lastIndex(where: { $0.t < t }) else { return frameStore }
        return Array(frameStore[(idx + 1)...])
    }

    func latest(_ count: Int = 1) -> [Frame] {
        touch()
        frameLock.lock()
        defer { frameLock.unlock() }
        return Array(frameStore.suffix(count))
    }

    func clearFrames() {
        frameLock.lock()
        frameStore.removeAll()
        frameLock.unlock()
    }
}
