import Foundation

/// Peo 老师（Bilibili「Peo老师欧美流行」）: pop singing in the SLS (Speech Level Singing) tradition.
///
/// The exercises start from the SLS method her channel names and are marked unchecked until
/// tools/course/discover.py has analysed her videos; then each gets its video (`ep` indexes
/// `peoVideos`), start time, syllable and pattern from the analysis.
extension Course {
    /// episode number -> Bilibili BV id, filled in from tools/course/fetch.py --teacher peo --list
    static let peoVideos: [Int: String] = [:]

    static let peoExercises: [Exercise] = [
        Exercise(id: "peo.range", ep: 0, t: 0, name: "测出音域", syl: "↕", kind: .range, teacher: "peo",
                 tip: "到「音域」页记录最低音和最高音，之后每个练习的起止调按你的音域安排。"),
        Exercise(id: "peo.hiss", ep: 0, t: 0, name: "稳定出气", syl: "SSS", kind: .breath, teacher: "peo",
                 tip: "吸气到腰腹一圈，发出均匀细长的 SSS。肩膀不动，越到最后越要稳。"),
        Exercise(id: "peo.bubble", ep: 0, t: 0, name: "唇颤音", syl: "BRR", pat: "arp8", teacher: "peo",
                 tip: "嘴唇放松地颤，走八度琶音。气流稳住，声带就能不用力地跨过换声点，这是 SLS 最常用的起步练习。"),
        Exercise(id: "peo.hum", ep: 0, t: 0, name: "哼鸣", syl: "MM", pat: "five", teacher: "peo",
                 tip: "闭嘴哼，嘴唇和鼻梁有轻微的振动感。音量放小，找到不压喉的说话位置。"),
        Exercise(id: "peo.mum", ep: 0, t: 0, name: "MUM 八度重复", syl: "MUM", pat: "p1358888531", teacher: "peo",
                 tip: "在八度上重复几次，胸声和头声之间不换挡、不断开。像说话一样轻松，不追求音量。"),
        Exercise(id: "peo.ng", ep: 0, t: 0, name: "NG 警笛", syl: "NG", pat: "slide8", teacher: "peo",
                 tip: "保持 NG 的位置从低滑到高再滑回来，像警笛一样连贯，中间不要有台阶。"),
        Exercise(id: "peo.nay", ep: 0, t: 0, name: "NAY 闭合", syl: "NAY", pat: "arp8", metric: .bright, teacher: "peo",
                 tip: "带一点顽皮的鼻音（twang），声带闭合更好，混声能更有力地往上走。不要喊。"),
        Exercise(id: "peo.gee", ep: 0, t: 0, name: "GEE 过换声", syl: "GEE", pat: "five", teacher: "peo",
                 tip: "G 帮助闭合，EE 是窄元音，过换声点更容易。到高处让声音变轻，不要往上推。"),
        Exercise(id: "peo.goog", ep: 0, t: 0, name: "GOOG 稳喉位", syl: "GOOG", pat: "arp8", teacher: "peo",
                 tip: "用有点傻气、低沉的声音唱，喉头不跟着音高往上跑。高音挤的时候就回到这个练习。"),
        Exercise(id: "peo.wee", ep: 0, t: 0, name: "WEE 头声", syl: "WEE", pat: "slide8", zone: .high, teacher: "peo",
                 tip: "像小狗呜咽一样轻轻滑上去，找到轻松、靠前的头声，再慢慢加一点实。"),
        Exercise(id: "peo.ah", ep: 0, t: 0, name: "AH 开口元音", syl: "AH", pat: "five", metric: .bright, teacher: "peo",
                 tip: "开口元音最容易散。保持前面几个练习的位置，下巴放松，声音不要往后缩。"),
        Exercise(id: "peo.vib", ep: 0, t: 0, name: "颤音", syl: "AH", pat: "vib", metric: .vibrato, teacher: "peo",
                 tip: "先慢慢地在相邻两个音之间交替，再逐渐加快，让它自然变成颤音。"),
        Exercise(id: "peo.riff", ep: 0, t: 0, name: "五声音阶 riff", syl: "OH", pat: "penta", teacher: "peo",
                 tip: "欧美流行的转音大多在五声音阶里。先慢、每个音都清楚，再加速度。"),
    ]

    static let peoWeeks: [Week] = [
        Week(stage: "A", focus: "测音域、稳定出气、放松起声", ex: ["peo.range", "peo.hiss", "peo.bubble", "peo.hum"]),
        Week(stage: "A", focus: "胸声和头声连起来，不断开", ex: ["peo.mum", "peo.ng"]),
        Week(stage: "B", focus: "声带闭合，把混声往上带", ex: ["peo.nay", "peo.gee"]),
        Week(stage: "B", focus: "稳住喉位，找到轻松的头声", ex: ["peo.goog", "peo.wee"]),
        Week(stage: "C", focus: "开口元音的音色统一", ex: ["peo.ah", "peo.mum"]),
        Week(stage: "C", focus: "混声的力量和高度", ex: ["peo.nay", "peo.goog", "peo.gee"]),
        Week(stage: "D", focus: "颤音和转音", ex: ["peo.vib", "peo.riff"]),
        Week(stage: "D", focus: "复习和检验", ex: ["peo.mum", "peo.nay", "peo.riff", "peo.hiss"]),
    ]

    static let peoChecks: [(text: String, exercise: String?)] = [
        ("测出音域，记录嘶气时长作为基线", "peo.range"),
        ("八度重复唱过换声点时不断开", "peo.mum"),
        ("录一段 NAY 琶音，听声音是否集中、不发虚", "peo.nay"),
        ("唱到自己的高音区时喉头不上提", "peo.goog"),
        ("同一个音高上录 AH，和前几周对比是否更通透", "peo.ah"),
        ("录一段混声高音，检查是否发紧", nil),
        ("录一段慢速、准确的 riff", "peo.riff"),
        ("重唱第一周录的歌，写下三处具体变化", nil),
    ]

    static let peo = Teacher(
        id: "peo", name: "Peo 老师", about: "欧美流行 · SLS 唱法（Bilibili）",
        platform: .bilibili, home: URL(string: "https://space.bilibili.com/3546774224505365")!,
        exercises: peoExercises,
        warmup: [("peo.bubble", "唱 5 个调，气流均匀，不用力。"), ("peo.hum", "唱 5 个调，振动感放在脸的前方。")],
        weeks: peoWeeks,
        stageNames: ["A": "放松与连接", "B": "混声", "C": "音色", "D": "流行风格"],
        checks: peoChecks, videos: peoVideos,
        // to be matched to her piano from discover.py's cue analysis; a plain triad until then
        cueChord: [0, 4, 7, 12], hasPrograms: false)
}
