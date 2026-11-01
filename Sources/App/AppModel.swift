import Foundation
import Observation

enum AppTab: Hashable { case today, practice, range, analyze, log }

/// How a practice session runs. Defaults follow common vocal warm-up practice:
/// a chord sets each key, the first key is demonstrated, a count-in leads in, a metronome keeps time.
struct PracticePrefs: Codable, Equatable {
    var demo: String = PlanOptions.Demo.first.rawValue
    var chordCue = true
    var countIn = 2
    var metronome = true
    var metronomeVolume = 0.5
    /// play the pattern on the piano while singing (needs headphones, or the mic hears it)
    var accompany = false
    /// use the exercise's recorded demo when there is one
    var useRecordedDemo = true
    /// tempo and the flow from key to key as in the teacher's video, where it was measured
    var courseRhythm = true

    var demoMode: PlanOptions.Demo { PlanOptions.Demo(rawValue: demo) ?? .first }

    init() {}

    /// Settings saved by an older version miss newer fields; those keep their defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PracticePrefs()
        demo = try c.decodeIfPresent(String.self, forKey: .demo) ?? d.demo
        chordCue = try c.decodeIfPresent(Bool.self, forKey: .chordCue) ?? d.chordCue
        countIn = try c.decodeIfPresent(Int.self, forKey: .countIn) ?? d.countIn
        metronome = try c.decodeIfPresent(Bool.self, forKey: .metronome) ?? d.metronome
        metronomeVolume = try c.decodeIfPresent(Double.self, forKey: .metronomeVolume) ?? d.metronomeVolume
        accompany = try c.decodeIfPresent(Bool.self, forKey: .accompany) ?? d.accompany
        useRecordedDemo = try c.decodeIfPresent(Bool.self, forKey: .useRecordedDemo) ?? d.useRecordedDemo
        courseRhythm = try c.decodeIfPresent(Bool.self, forKey: .courseRhythm) ?? d.courseRhythm
    }
}

@Observable
final class AppModel {
    var tab: AppTab = .today
    /// the teacher whose course the app follows; each teacher keeps its own week and progress
    private(set) var teacherID: String
    /// week shown in the course browser
    private(set) var week: Int
    /// week of the teacher's plan the user is on, and the day it was started
    private(set) var courseWeek: Int
    private(set) var weekStart: Date
    private(set) var voiceKey: String
    private(set) var custom: VoiceRange? = nil
    private(set) var log: [LogEntry] = []
    private(set) var prefs: PracticePrefs

    private let defaults = UserDefaults.standard

    init() {
        let t = Course.teacher(defaults.string(forKey: "teacher") ?? Course.stoney.id)
        Course.current = t
        teacherID = t.id
        week = 0
        courseWeek = 0
        weekStart = Date()
        voiceKey = defaults.string(forKey: "voice") ?? "bari"
        prefs = defaults.data(forKey: "practicePrefs").flatMap { try? JSONDecoder().decode(PracticePrefs.self, from: $0) } ?? PracticePrefs()
        if let data = defaults.data(forKey: "customRange") {
            custom = try? JSONDecoder().decode(VoiceRange.self, from: data)
        }
        log = loadLog()
        loadProgress()
    }

    var teacher: Teacher { Course.teacher(teacherID) }

    func setTeacher(_ id: String) {
        guard id != teacherID else { return }
        let t = Course.teacher(id)
        Course.current = t
        teacherID = t.id
        defaults.set(t.id, forKey: "teacher")
        loadProgress()
    }

    /// Settings keys for the current teacher; Justin Stoney's keep their original names.
    private func key(_ base: String) -> String { teacherID == Course.stoney.id ? base : "\(base).\(teacherID)" }

    private func loadProgress() {
        let n = Course.weeks.count
        let w = defaults.integer(forKey: key("week"))
        week = (0..<n).contains(w) ? w : 0
        let cw = defaults.integer(forKey: key("courseWeek"))
        courseWeek = (0..<n).contains(cw) ? cw : 0
        let start = defaults.object(forKey: key("weekStart")) as? Date ?? Date()
        defaults.set(start, forKey: key("weekStart"))
        weekStart = start
    }

    var voice: VoiceRange {
        if voiceKey == "custom", let c = custom { return c }
        return VoiceRange.presets.first { $0.key == voiceKey }?.range ?? VoiceRange.presets[1].range
    }

    func setVoice(_ key: String) {
        voiceKey = key
        defaults.set(key, forKey: "voice")
    }

    func setPrefs(_ p: PracticePrefs) {
        prefs = p
        if let d = try? JSONEncoder().encode(p) { defaults.set(d, forKey: "practicePrefs") }
    }

    func setWeek(_ w: Int) {
        week = w
        defaults.set(w, forKey: key("week"))
    }

    // MARK: daily routine

    /// Move to a week of the plan (normally the next one); its day 1 is today.
    func startCourseWeek(_ w: Int) {
        courseWeek = min(max(0, w), Course.weeks.count - 1)
        weekStart = Date()
        defaults.set(courseWeek, forKey: key("courseWeek"))
        defaults.set(weekStart, forKey: key("weekStart"))
        setWeek(courseWeek)
    }

    var courseDay: Int { Routine.day(since: weekStart) }

    var summary: PracticeSummary {
        var s = PracticeSummary()
        for e in log where !e.ex.hasPrefix("routine.") {
            s.total[e.ex, default: 0] += 1
            if e.date >= Calendar.current.startOfDay(for: weekStart) { s.thisWeek[e.ex, default: 0] += 1 }
            if let a = e.acc { s.lastScore[e.ex] = a }
        }
        return s
    }

    var todayPlan: DayPlan { Routine.plan(week: courseWeek, day: courseDay, summary: summary) }

    /// A step is done when its exercise was practiced today, or the user marked it done.
    func isDone(_ step: RoutineStep) -> Bool {
        let today = Calendar.current.startOfDay(for: Date())
        let key = "routine.\(step.id)"
        return log.contains { $0.date >= today && ($0.ex == key || (step.exercise != nil && $0.ex == step.exercise)) }
    }

    func markDone(_ step: RoutineStep) {
        add(LogEntry(ex: "routine.\(step.id)"))
    }

    func setCustomRange(lo: Int, hi: Int) {
        let r = VoiceRange(name: "我的音域", lo: lo, hi: hi)
        custom = r
        if let data = try? JSONEncoder().encode(r) { defaults.set(data, forKey: "customRange") }
        setVoice("custom")
        add(LogEntry(ex: "range", rangeLo: lo, rangeHi: hi))
    }

    // MARK: practice log

    func add(_ e: LogEntry) {
        log.append(e)
        if log.count > 3000 { log.removeFirst(log.count - 3000) }
        saveLog()
    }

    func last(of id: String) -> LogEntry? { log.last { $0.ex == id } }

    func best(of id: String) -> Double { log.filter { $0.ex == id }.compactMap { $0.sec }.max() ?? 0 }

    func clearLog() {
        log.removeAll()
        saveLog()
    }

    private var logURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("practice-log.json")
    }

    private func loadLog() -> [LogEntry] {
        guard let data = try? Data(contentsOf: logURL) else { return [] }
        return (try? JSONDecoder().decode([LogEntry].self, from: data)) ?? []
    }

    private func saveLog() {
        if let data = try? JSONEncoder().encode(log) { try? data.write(to: logURL, options: .atomic) }
    }
}
