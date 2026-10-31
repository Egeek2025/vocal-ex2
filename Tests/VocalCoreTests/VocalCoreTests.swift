import XCTest
@testable import VocalCore

final class PitchAnalyzerTests: XCTestCase {
    private let sr = 48000.0

    /// A voice-like tone: fundamental plus nine harmonics, optional vibrato.
    private func tone(_ f: Double, count: Int, vibHz: Double = 0, vibCents: Double = 0) -> [Float] {
        var x = [Float](repeating: 0, count: count)
        var ph = 0.0
        for i in 0..<count {
            let t = Double(i) / sr
            let ff = f * pow(2, vibCents * sin(2 * Double.pi * vibHz * t) / 1200)
            ph += 2 * Double.pi * ff / sr
            var s = 0.0
            for k in 1...10 { s += sin(Double(k) * ph) / Double(k) * (k == 1 ? 0.6 : 1) }
            x[i] = Float(0.2 * s)
        }
        return x
    }

    func testDetectsPitchAcrossVocalRange() {
        let a = PitchAnalyzer(windowSize: 2048)
        for f in [82.4, 110, 196, 261.6, 440, 659, 988] {
            let r = a.analyze(tone(f, count: 2048), sampleRate: sr)
            let cents = (Music.midi(r.f0) - Music.midi(f)) * 100
            XCTAssertLessThan(abs(cents), 2, "f=\(f) detected \(r.f0)")
            XCTAssertGreaterThan(r.clarity, 0.9)
        }
    }

    func testSilenceIsUnvoiced() {
        let r = PitchAnalyzer().analyze([Float](repeating: 0, count: 2048), sampleRate: sr)
        XCTAssertEqual(r.f0, 0)
    }

    func testVibratoRateAndExtent() {
        let a = PitchAnalyzer(windowSize: 2048)
        let x = tone(220, count: Int(sr * 3) + 2048, vibHz: 5.5, vibCents: 50)
        var fr: [CentPoint] = []
        var t = 0.0
        while t < 3 {
            let r = a.analyze(x, offset: Int(t * sr), sampleRate: sr)
            fr.append(CentPoint(t: t, c: (Music.midi(r.f0) - Music.midi(220)) * 100))
            t += 1.0 / 60
        }
        let v = Scorer.vibrato(fr)
        XCTAssertNotNil(v)
        XCTAssertEqual(v!.rate, 5.5, accuracy: 0.5)
        XCTAssertEqual(v!.ext, 45, accuracy: 15)
    }
}

final class CourseTests: XCTestCase {
    func testEveryWeekExerciseExists() {
        for w in Course.weeks {
            for id in w.ex { XCTAssertNotNil(Course.byID[id], id) }
        }
        for id in Course.warmup { XCTAssertNotNil(Course.byID[id], id) }
    }

    func testExercisesAreNotRepeatedAcrossWeeks() {
        // week 12 is the review week and may repeat earlier exercises
        let ids = Course.weeks.dropLast().flatMap { $0.ex }
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testPatternsStatedInTheCourse() {
        // patterns Justin states in the episode subtitles
        let expected: [String: [Int]] = [
            "yoh": [7, 0], "vwohm": [9, 5, 5, 0], "fals89": [12, 7, 0], "guun": [12, 7, 0], "hoong": [12, 7, 0],
            "ee54": [7, 4, 5, 2, 0], "oh61": [0, 4, 7, 7, 7, 4, 0], "twang": [0, 4, 7, 12, 12, 12, 12, 7, 4, 0],
            "comp104": [12, 12, 12, 7, 0], "belt72": [0, 7, 0, 7, 0], "jaw35": [0, 4, 7, 4, 0],
            // "one - two - three - four - five, four - three - two - one" on the pentatonic scale
            "penta3": [0, 2, 4, 7, 9, 7, 4, 2, 0],
            // syllable count in the subtitles plus the shape repeated in the audio
            "ng": [7, 5, 4, 2, 0], "larynx17": [7, 5, 4, 2, 0], "ee33": [7, 5, 4, 2, 0],
            "mix40": [12, 7, 4, 0], "crack12": [12, 7, 4, 0], "head98": [4, 0], "low128": [7, 4, 0],
            "ngah": [0, 12, 7, 0], "str111": [9, 0],
        ]
        for (id, semis) in expected {
            let ex = Course.byID[id]!
            XCTAssertTrue(ex.verified, id)
            XCTAssertEqual(ex.pattern!.steps.map { $0.s }, semis, id)
        }
    }

    func testLipTrillFollowsCourse() {
        XCTAssertEqual(Course.byID["trill"]!.pattern!.steps.map { $0.s }, [12, 7, 4, 0])
    }

    func testPitchExercisesHavePatternsAndVideos() {
        for e in Course.exercises {
            if e.kind == .pitch { XCTAssertNotNil(e.pattern, e.id) }
            XCTAssertNotNil(e.videoURL, e.id)
        }
    }

    func testPlanTimeline() {
        let p = Course.patterns["five"]!
        var o = PlanOptions(bpm: 120)
        o.demo = .first
        let plan = Planner.build(p, roots: [48, 49], options: o, start: 10)
        XCTAssertEqual(plan.blocks.count, 2)
        let b = plan.blocks[0]
        XCTAssertEqual(b.sing.count, 9)
        XCTAssertEqual(b.sing[4].m, 48 + 7)
        XCTAssertEqual(b.chord?.lowerBound, 10)
        XCTAssertGreaterThan(b.listen.first!.t0, b.chord!.upperBound - 0.001)
        XCTAssertEqual(b.countIn.count, 4)
        XCTAssertEqual(b.s0, b.countIn.last! + plan.beat, accuracy: 1e-9)
        XCTAssertEqual(b.clicks.count, 10)
        XCTAssertEqual(plan.target(at: b.sing[2].t0 + 0.01), Double(52))
        // the second key has no demo and a two-beat count-in
        XCTAssertTrue(plan.blocks[1].listen.isEmpty)
        XCTAssertEqual(plan.blocks[1].countIn.count, 2)
        XCTAssertEqual(plan.phase(at: b.countIn[1] + 0.01).0, .countIn(3))
        XCTAssertEqual(plan.phase(at: b.sing[0].t0 + 0.01).0, .sing)
        XCTAssertEqual(plan.phase(at: 10.01).0, .chord)
    }

    func testRecordedDemoStretchesListenPhase() {
        let p = Course.patterns["arp5"]!
        var o = PlanOptions(bpm: 90)
        o.demoDuration = 7
        o.chordCue = false
        let plan = Planner.build(p, roots: [50], options: o, start: 0)
        let l = plan.blocks[0].listen
        XCTAssertEqual(l.last!.t1 - l.first!.t0, 7, accuracy: 1e-9)
    }

    func testKeyboardFollowsThePlan() {
        let p = Course.patterns["down8"]!   // 8-5-3-1
        var o = PlanOptions(bpm: 60)
        o.demo = .first
        let plan = Planner.build(p, roots: [48], options: o, start: 0)
        let b = plan.blocks[0]
        XCTAssertEqual(plan.keys(at: b.chord!.lowerBound + 0.1).playing, [48, 52, 55, 60, 64, 67])
        XCTAssertEqual(plan.keys(at: b.listen[0].t0 + 0.1).playing, [60])
        XCTAssertEqual(plan.keys(at: b.listen[2].t0 + 0.1).playing, [52])
        let sing = plan.keys(at: b.sing[1].t0 + 0.1)
        XCTAssertTrue(sing.playing.isEmpty)
        XCTAssertEqual(sing.target, 55)
        XCTAssertNil(plan.keys(at: b.countIn[0] + 0.1).target)
    }

    func testScoringPerfectSinging() {
        let p = Course.patterns["arp5"]!
        let ex = Course.byID["ngah"]!
        let plan = Planner.build(p, roots: [50], options: PlanOptions(bpm: 90), start: 0)
        var frames: [Frame] = []
        var t = 0.0
        while t < plan.end {
            if let m = plan.target(at: t) {
                frames.append(Frame(t: t, f0: Music.freq(m), clarity: 0.95, rms: 0.05, hi: -20, voiced: true, midi: m))
            }
            t += 1.0 / 60
        }
        let r = Scorer.score(plan: plan, frames: frames, now: plan.end, exercise: ex, pattern: p, previous: nil)
        XCTAssertNotNil(r)
        XCTAssertEqual(r!.acc, 1, accuracy: 0.001)
        XCTAssertEqual(r!.mean, 0, accuracy: 0.001)
    }

    func testClickFramesAreIgnored() {
        let p = Course.patterns["arp5"]!
        let ex = Course.byID["ngah"]!
        let plan = Planner.build(p, roots: [50], options: PlanOptions(bpm: 90), start: 0)
        let clicks = plan.allClicks
        var frames: [Frame] = []
        var t = 0.0
        while t < plan.end {
            if let m = plan.target(at: t) {
                // a metronome click leaking into the mic reads as a wrong, high note
                let leak = clicks.contains { t >= $0 && t < $0 + 0.06 }
                let mm = leak ? 84.0 : m
                frames.append(Frame(t: t, f0: Music.freq(mm), clarity: 0.95, rms: 0.05, hi: -20, voiced: true, midi: mm))
            }
            t += 1.0 / 60
        }
        let r = Scorer.score(plan: plan, frames: frames, now: plan.end, exercise: ex, pattern: p, previous: nil)
        XCTAssertEqual(r!.acc, 1, accuracy: 0.001)
    }
}

final class RoutineTests: XCTestCase {
    func testDayIsCountedFromWeekStart() {
        let cal = Calendar(identifier: .gregorian)
        let start = cal.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 22))!
        let later = cal.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 7))!
        XCTAssertEqual(Routine.day(since: start, now: start, calendar: cal), 1)
        XCTAssertEqual(Routine.day(since: start, now: later, calendar: cal), 3)
    }

    func testDailyStructure() {
        let p = Routine.plan(week: 2, day: 1, summary: PracticeSummary())
        XCTAssertEqual(p.steps.first?.kind, .warmup)
        XCTAssertEqual(p.steps.filter { $0.kind == .warmup }.map { $0.exercise }, ["trill", "ng"])
        XCTAssertTrue(p.steps.contains { $0.kind == .learn && $0.watchFirst })
        XCTAssertTrue(p.steps.contains { $0.kind == .review })
        XCTAssertEqual(p.steps.suffix(2).map { $0.kind }, [.song, .cooldown])
    }

    func testFirstThreeDaysCoverTheWeek() {
        for w in 0..<Course.weeks.count {
            let learned = (1...3).flatMap { d in
                Routine.plan(week: w, day: d, summary: PracticeSummary()).steps.filter { $0.kind == .learn }.compactMap { $0.exercise }
            }
            XCTAssertEqual(learned, Routine.material(week: w), "week \(w + 1)")
        }
    }

    func testNoReviewInTheFirstWeekAndRestOnDaySeven() {
        XCTAssertFalse(Routine.plan(week: 0, day: 2, summary: PracticeSummary()).steps.contains { $0.kind == .review })
        XCTAssertTrue(Routine.plan(week: 4, day: 7, summary: PracticeSummary()).isRest)
    }

    func testDrillPicksUnpracticedThenWeakest() {
        var s = PracticeSummary()
        // week 6: every exercise practiced except nyay; hoong scored lowest
        for id in Routine.material(week: 5) where id != "nyay" { s.thisWeek[id] = 1; s.lastScore[id] = 0.9 }
        s.lastScore["hoong"] = 0.4
        let drill = Routine.plan(week: 5, day: 4, summary: s).steps.filter { $0.kind == .drill }.compactMap { $0.exercise }
        XCTAssertEqual(drill, ["nyay", "hoong"])
    }

    func testWeeklyCheckUsesItsExercise() {
        let check = Routine.plan(week: 5, day: 6, summary: PracticeSummary()).steps.first { $0.kind == .check }
        XCTAssertEqual(check?.exercise, "vowels117")
        XCTAssertEqual(Routine.checks.count, Course.weeks.count)
    }

    func testProgressCountsPracticedMaterial() {
        var s = PracticeSummary()
        s.thisWeek["yoh"] = 2
        s.thisWeek["trill"] = 3   // warm-up, not part of the week's material
        let p = Routine.progress(week: 3, summary: s)
        XCTAssertEqual(p.done, 1)
        XCTAssertEqual(p.total, Routine.material(week: 3).count)
    }
}

final class JianpuTests: XCTestCase {
    func testParse() {
        XCTAssertEqual(Jianpu.semitones("1' 5 3 1"), [12, 7, 4, 0])
        XCTAssertEqual(Jianpu.semitones("#2 1 5."), [3, 0, -5])
        XCTAssertNil(Jianpu.semitones("x"))
    }

    func testClipMustSingTheWholePattern() {
        let trill = Course.byID["trill"]!.pattern!     // 8-5-3-1
        XCTAssertTrue(Jianpu.matches("1' 5 3 1", pattern: trill))
        XCTAssertFalse(Jianpu.matches("5 3 1", pattern: trill))      // fragment
        // repeated notes merge in the analysis: 1-3-5-5-5-3-1 shows as 1 3 5 3 1
        XCTAssertTrue(Jianpu.matches("1 3 5 3 1", pattern: Course.byID["oh61"]!.pattern!))
        // transposition does not matter
        XCTAssertTrue(Jianpu.matches("5' 2' 5", pattern: Course.byID["fals89"]!.pattern!))
    }
}

final class ProgramTests: XCTestCase {
    func testProgramsUseExistingExercisesAndUniqueSteps() {
        for program in Routine.Program.allCases {
            let steps = Routine.steps(program)
            XCTAssertFalse(steps.isEmpty)
            XCTAssertEqual(Set(steps.map { $0.id }).count, steps.count, program.title)
            for s in steps {
                if let id = s.exercise { XCTAssertNotNil(Course.byID[id], id) }
            }
        }
    }

    func testQuickWarmupGoesFromLightToStrongMix() {
        let ids = Routine.steps(.quickWarmup).compactMap { $0.exercise }
        XCTAssertEqual(ids.first, "trill")
        XCTAssertEqual(ids.last, "crack12")
    }
}
