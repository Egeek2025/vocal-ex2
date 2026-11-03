import Foundation

/// One step of a day's practice.
struct RoutineStep: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case warmup, learn, drill, check, review, song, cooldown

        var label: String {
            switch self {
            case .warmup: return "热身"
            case .learn: return "新内容"
            case .drill: return "强化"
            case .check: return "本周检验"
            case .review: return "复习"
            case .song: return "唱歌"
            case .cooldown: return "放松"
            }
        }
    }

    let id: String
    let kind: Kind
    /// exercise to open; nil for steps the user marks done (song, cool-down, checks without an exercise)
    let exercise: String?
    let minutes: Int
    let title: String
    let detail: String
    /// fewer keys for short steps such as the warm-up
    var maxKeys: Int? = nil
    /// first time this week: watch the video section before practicing
    var watchFirst = false
}

struct DayPlan {
    let week: Int
    /// day of the course week, 1...7; past 7 the week keeps going with drill days
    let day: Int
    let headline: String
    let steps: [RoutineStep]

    var isRest: Bool { steps.isEmpty }
    var minutes: Int { steps.reduce(0) { $0 + $1.minutes } }
}

/// What the user has done, as the routine needs it.
struct PracticeSummary {
    /// sessions per exercise since the current course week started
    var thisWeek: [String: Int] = [:]
    /// latest pitch accuracy per exercise (0...1)
    var lastScore: [String: Double] = [:]
    /// sessions per exercise over all time
    var total: [String: Int] = [:]
}

/// The teacher's weekly plan as a daily routine: warm up, the week's material (learn on days 1-3,
/// drill on days 4-5, the week's check on day 6, rest on day 7), review one exercise from the
/// week before, apply it to a song, cool down.
enum Routine {
    /// The plan's weekly check ("本周检验") for the current teacher.
    static var checks: [(text: String, exercise: String?)] { Course.current.checks }

    /// Day of the course week counted from the day the week was started (1 = that day).
    static func day(since start: Date, now: Date = Date(), calendar: Calendar = .current) -> Int {
        let a = calendar.startOfDay(for: start), b = calendar.startOfDay(for: now)
        return max(1, (calendar.dateComponents([.day], from: a, to: b).day ?? 0) + 1)
    }

    /// Exercises of a week that are practiced in the routine (warm-ups are done every day anyway).
    static func material(week: Int) -> [String] {
        guard Course.weeks.indices.contains(week) else { return [] }
        return Course.weeks[week].ex.filter { !Course.warmup.contains($0) }
    }

    static func plan(week: Int, day: Int, summary: PracticeSummary) -> DayPlan {
        let w = min(max(0, week), Course.weeks.count - 1)
        let info = Course.weeks[w]
        let items = material(week: w)
        let stage = "阶段 \(info.stage) \(Course.stageNames[info.stage] ?? "")"

        if day == 7 {
            return DayPlan(week: w, day: day, headline: "第 \(w + 1) 周第 7 天 · 休息日：可以听歌，不练习，让嗓子恢复。", steps: [])
        }

        var steps: [RoutineStep] = Course.current.warmup.enumerated().map { i, w in
            RoutineStep(id: "warmup.\(w.id)", kind: .warmup, exercise: w.id, minutes: i == 0 ? 3 : 2,
                        title: (Course.byID[w.id]?.name ?? w.id) + "热身", detail: w.detail, maxKeys: 5)
        }

        let headline: String
        switch day {
        case 1...3:
            // split the week's material over three days, in course order
            let per = max(1, Int((Double(items.count) / 3).rounded(.up)))
            let part = Array(items.dropFirst((day - 1) * per).prefix(per))
            for id in part {
                guard let ex = Course.byID[id] else { continue }
                let first = (summary.thisWeek[id] ?? 0) == 0
                steps.append(RoutineStep(id: "learn.\(id)", kind: .learn, exercise: id, minutes: 6, title: ex.name,
                                         detail: first ? "先看视频里的讲解和示范，再跟着练。" : "跟着练一遍，注意上次反馈里提到的问题。",
                                         watchFirst: first))
            }
            headline = "第 \(w + 1) 周第 \(day) 天 · \(stage) · 学习本周新内容：\(info.focus)"
        case 6:
            let c = checks[w]
            steps.append(RoutineStep(id: "check.w\(w)", kind: .check, exercise: c.exercise, minutes: 10, title: "本周检验",
                                     detail: c.text + "。和上周的结果或录音对比。"))
            headline = "第 \(w + 1) 周第 6 天 · 本周检验和总结"
        default:
            // days 4-5, and any day after the week ran long: drill the weakest material
            for id in weakest(items, summary: summary, count: 2) {
                guard let ex = Course.byID[id] else { continue }
                let s = summary.lastScore[id].map { "上次音准 \(Int(($0 * 100).rounded()))%。" } ?? "本周还没练过。"
                steps.append(RoutineStep(id: "drill.\(id)", kind: .drill, exercise: id, minutes: 8, title: ex.name,
                                         detail: s + "把最难的调多唱几遍，可以放慢速度。"))
            }
            headline = day > 7
                ? "第 \(w + 1) 周已经练了 \(day - 1) 天 · 继续强化，准备好了就进入下一周"
                : "第 \(w + 1) 周第 \(day) 天 · 强化本周最难的练习"
        }

        if w > 0, let id = weakest(material(week: w - 1), summary: summary, count: 1, preferTotal: true).first,
           let ex = Course.byID[id] {
            steps.append(RoutineStep(id: "review.\(id)", kind: .review, exercise: id, minutes: 5, title: ex.name,
                                     detail: "复习上周的一个练习。", maxKeys: 6))
        }
        steps.append(RoutineStep(id: "song", kind: .song, exercise: nil, minutes: 8, title: "用歌曲套用",
                                 detail: "从下面「本周练习曲目」里选一首（或你熟悉的歌），把今天练的重点用进去，录下来听一遍。"))
        steps.append(RoutineStep(id: "cooldown", kind: .cooldown, exercise: nil, minutes: 2, title: "放松",
                                 detail: "轻柔地从高到低滑几次音，喝点水。"))
        return DayPlan(week: w, day: day, headline: headline, steps: steps)
    }

    /// Fixed sequences for a specific goal, done on any day besides the plan.
    enum Program: String, CaseIterable, Identifiable, Hashable {
        case quickWarmup, headVoice

        var id: String { rawValue }
        var title: String {
            switch self {
            case .quickWarmup: return "快速开嗓"
            case .headVoice: return "头声强化"
            }
        }
        var summary: String {
            switch self {
            case .quickWarmup: return "每天开唱前用。由轻到重、由低到高，最后才上强混。"
            case .headVoice: return "练出轻松、有力的头声，再把它连进混声，给高音留余地。"
            }
        }
    }

    static func steps(_ program: Program) -> [RoutineStep] {
        let p = program.rawValue
        func ex(_ id: String, _ kind: RoutineStep.Kind, _ minutes: Int, _ keys: Int, _ detail: String) -> RoutineStep {
            RoutineStep(id: "\(p).\(id)", kind: kind, exercise: id, minutes: minutes,
                        title: Course.byID[id]?.name ?? id, detail: detail, maxKeys: keys)
        }
        switch program {
        case .quickWarmup:
            return [
                RoutineStep(id: "\(p).speak", kind: .warmup, exercise: nil, minutes: 1, title: "喝水，用说话声说几句",
                            detail: "喝几口温水，用平常说话的音量说几句话，让声音醒过来。"),
                ex("trill", .warmup, 3, 6, "唇颤音在中低音区上下走，气流均匀，不用力。"),
                ex("ng", .warmup, 2, 5, "把声音放到脸的前方，音量小一点。"),
                ex("head98", .warmup, 2, 4, "轻轻地进入头声，允许声音变轻，不要挤。"),
                ex("guun", .drill, 3, 5, "中音区的混声，音量中等，用 G 帮助闭合。"),
                ex("crack12", .drill, 2, 4, "最后才上强混：先唱到 C5–D5，状态好再往 E5 走。"),
            ]
        case .headVoice:
            return [
                ex("trill", .warmup, 2, 4, "先用唇颤音放松。"),
                ex("head98", .learn, 2, 6, "YOO-HOO 轻松地翻进头声，越往上越轻。"),
                ex("filter", .learn, 2, 5, "滑上去时逐渐减掉胸声的重量，把声音过滤得更轻、更窄。"),
                ex("vwohm", .learn, 3, 6, "从高处用头声往下带，V 让气流稳定，保持声音圆而轻。"),
                ex("fals89", .drill, 3, 6, "先唱带气的假声，再在同样的音高上加一点闭合，变成更实的加强假声。"),
                ex("hoong", .drill, 3, 6, "OO 口型从上到下不变，把头声往下连到混声。"),
                ex("guun", .drill, 2, 5, "把头声的轻松带进混声，不要突然加重。"),
                RoutineStep(id: "\(p).song", kind: .song, exercise: nil, minutes: 3, title: "用歌曲套用",
                            detail: "选一首歌的副歌，先用头声轻唱一遍，再用混声唱一遍，听听两者能不能接得上。"),
            ]
        }
    }

    /// Exercises to drill: never practiced first, then lowest score, then least practiced.
    static func weakest(_ ids: [String], summary: PracticeSummary, count: Int, preferTotal: Bool = false) -> [String] {
        let practicable = ids.filter { id in
            guard let ex = Course.byID[id] else { return false }
            return ex.kind != .range
        }
        let counts = preferTotal ? summary.total : summary.thisWeek
        return practicable.sorted { a, b in
            let ca = counts[a] ?? 0, cb = counts[b] ?? 0
            if (ca == 0) != (cb == 0) { return ca == 0 }
            let sa = summary.lastScore[a] ?? 2, sb = summary.lastScore[b] ?? 2
            if sa != sb { return sa < sb }
            return ca < cb
        }.prefix(count).map { $0 }
    }

    /// Share of the week's material practiced at least once since the week started.
    static func progress(week: Int, summary: PracticeSummary) -> (done: Int, total: Int) {
        let m = material(week: week)
        return (m.filter { (summary.thisWeek[$0] ?? 0) > 0 }.count, m.count)
    }
}
