import Foundation

/// Peo 老师（Bilibili「Peo老师欧美流行」）: pop singing in the SLS (Speech Level Singing) tradition.
///
/// Built from tools/course/discover.py on 18 of her lessons: each exercise sits at the place in a video
/// where she sings it key after key. `verified` marks patterns found clearly there (three or more notes,
/// several keys in a row, a steady tempo); the others link to the right part of the video, but their
/// pattern is a suggestion until checked by ear. Syllables are suggestions: follow the video.
extension Course {
    /// episode number -> Bilibili BV id, numbered in publishing order
    static let peoVideos: [Int: String] = [
        1: "BV12drSBpEeU",   // 找到你自己真实的声音
        2: "BV1r76jB7E4U",   // 一口气讲清楚所有腔体
        3: "BV1pXFLzAE9V",   // 关于喉位的所有问题
        4: "BV1DHcszMExr",   // 唱歌到底怎样使用气息
        5: "BV1MewWzNELk",   // 百分百找到混声的方法
        6: "BV1eSAczUEwQ",   // 破音、挤卡：一个万能技术
        7: "BV1TyDZBKEmf",   // 8 分钟教会你头声
        8: "BV1wu9QBmEL7",   // R&B 演变史 - 唱法教学
        9: "BV17E5e6FELf",   // 千万别瞎练咽音
        10: "BV1M5V46REwK",  // 别再挤卡了
        11: "BV1Gpjd6XEFw",  // 测出真实音域
        12: "BV1MtMw63Ees",  // 别瞎唱摇滚
        13: "BV18vNd6sE2A",  // 8 分钟喉咙开启全盛状态
        14: "BV1Hnun6QEqp",  // 真假声断层
        15: "BV1tY8b6ME5V",  // 百分百找到弱混的方法
        16: "BV1XNew6jERm",  // 百分百找到强混的方法
        17: "BV1wqHD6iExK",  // 换声点
        18: "BV1pBxe6vEs9",  // 四个坏习惯
    ]

    static let peoExercises: [Exercise] = [
        // warm-up from her 8-minute warm-up video: a five-note scale over 11 keys, then 3-2-1 over 10 keys
        Exercise(id: "peo.scale", ep: 13, t: 164, name: "五音音阶开嗓", syl: "MA", pat: "five", verified: true, teacher: "peo",
                 tip: "跟着视频一个调一个调往上走。音量中等，像说话一样轻松，先让声音醒过来，不追求高音。"),
        Exercise(id: "peo.321", ep: 13, t: 431, name: "3-2-1 下行放松", syl: "HM", pat: "p321", verified: true, teacher: "peo",
                 tip: "短的下行音型，一个调接一个调，越往上越轻。用来收尾，让喉咙保持放松。"),
        Exercise(id: "peo.range", ep: 11, t: 309, name: "测出真实音域", syl: "↕", kind: .range, teacher: "peo",
                 tip: "按视频里的方法找最低和最高能稳定唱住的音，再到「音域」页记下来，之后的起止调按你的音域安排。"),
        Exercise(id: "peo.hiss", ep: 4, t: 0, name: "气息", syl: "SSS", kind: .breath, teacher: "peo",
                 tip: "这一期讲气息的用法，没有固定音型。看完后用均匀细长的 SSS 练出气，肩膀不动，越到最后越稳。"),
        Exercise(id: "peo.voice", ep: 1, t: 428, name: "找到真实的声音", syl: "AH", pat: "down5", verified: true, teacher: "peo",
                 tip: "5-4-3-2-1 从上往下，用平时说话的位置起音，不压、不装。这是后面所有练习的基础音色。"),
        Exercise(id: "peo.arp8", ep: 2, t: 842, name: "八度琶音找共鸣", syl: "MA", pat: "arp8", verified: true, teacher: "peo",
                 tip: "1-3-5-8-5-3-1，上行时别去「找腔体」用力，声音位置保持一致，让共鸣自己跟着音高变化。"),
        Exercise(id: "peo.larynx", ep: 3, t: 575, name: "稳住喉位", syl: "GUH", pat: "p12321", teacher: "peo",
                 tip: "视频这一段连续换了二十多个调。上行时喉头不跟着往上提，感觉发紧就退回低一点的调。"),
        Exercise(id: "peo.loose", ep: 10, t: 511, name: "不挤卡的八度琶音", syl: "NAY", pat: "arp8", verified: true, teacher: "peo",
                 tip: "到顶音时声音变轻、变窄，不往上推。听到自己在挤，就降低音量再唱一遍。"),
        Exercise(id: "peo.oct", ep: 6, t: 437, name: "1-8-1 八度跳", syl: "WOO", pat: "p181", verified: true, teacher: "peo",
                 tip: "视频里连续 15 个调。跳上八度时提前想好高音，轻轻落上去，再稳稳回到低音，破音和挤卡都靠它解决。"),
        Exercise(id: "peo.yan", ep: 9, t: 533, name: "咽音 1-3-5-3-1", syl: "NYA", pat: "arp5", verified: true, teacher: "peo",
                 tip: "先看完前面的讲解再练。声音集中、明亮，但喉咙不能紧，一紧就停下。"),
        Exercise(id: "peo.head", ep: 7, t: 374, name: "头声滑音", syl: "WOO", pat: "glide131", zone: .high, teacher: "peo",
                 tip: "在高音区轻轻地滑上去再滑下来，视频里一路换了十几个调。声音空、轻、连贯，不加力量。"),
        Exercise(id: "peo.flip", ep: 14, t: 221, name: "真假声切换", syl: "OO", pat: "octJump", teacher: "peo",
                 tip: "在换声的音高附近来回切换，先允许它断开，再慢慢让两边的音色靠近，直到听不出接缝。"),
        Exercise(id: "peo.weak", ep: 15, t: 644, name: "弱混：顶音延长", syl: "MUM", pat: "arp8hold", verified: true, teacher: "peo",
                 tip: "八度琶音唱到顶音时停住四拍，保持轻而集中的弱混音色，不要越唱越重。"),
        Exercise(id: "peo.weakoct", ep: 15, t: 487, name: "弱混：八度往下", syl: "OO", pat: "p81", verified: true, teacher: "peo",
                 tip: "从高八度的轻声起音往下落，把高处轻松的感觉带到低音，中间不换挡。"),
        Exercise(id: "peo.mix", ep: 5, t: 213, name: "混声", syl: "NAY", pat: "arp5", teacher: "peo",
                 tip: "跟视频这一段找混声：带一点鼻音让声音集中，音量中等，过换声点时不加重。"),
        Exercise(id: "peo.passaggio", ep: 17, t: 323, name: "过换声点", syl: "NAY", pat: "arp8", teacher: "peo",
                 tip: "在自己的换声点上下来回练。接近换声点时让声音变窄、变轻，过去之后再慢慢加回力量。"),
        Exercise(id: "peo.belt", ep: 16, t: 205, name: "强混", syl: "YEAH", pat: "arp5", metric: .bright, teacher: "peo",
                 tip: "在弱混稳定之后再练。声音更实、更亮，但仍然靠闭合和集中，不靠喊。"),
        Exercise(id: "peo.rnb", ep: 8, t: 607, name: "R&B 布鲁斯音", syl: "OH", pat: "blues", teacher: "peo",
                 tip: "R&B 常用的 ♭3 和 4。先慢慢唱准每个音，再加滑音和装饰，最后才加速度。"),
    ]

    /// seconds from one key to the next in her videos (discover.py: span of the takes / number of keys)
    static let peoKeySeconds: [String: Double] = [
        "peo.321": 5.14, "peo.arp8": 6.58, "peo.loose": 5.22, "peo.oct": 3.82, "peo.scale": 7.04,
        "peo.voice": 6.33, "peo.weak": 5.63, "peo.weakoct": 5.33, "peo.yan": 6.43,
    ]

    static let peoWeeks: [Week] = [
        Week(stage: "A", focus: "开嗓、测音域、气息", ex: ["peo.range", "peo.hiss", "peo.scale", "peo.321"]),
        Week(stage: "A", focus: "找到真实的声音和共鸣", ex: ["peo.voice", "peo.arp8"]),
        Week(stage: "B", focus: "稳住喉位，不挤卡", ex: ["peo.larynx", "peo.loose"]),
        Week(stage: "B", focus: "解决破音，正确练咽音", ex: ["peo.oct", "peo.yan"]),
        Week(stage: "C", focus: "头声和真假声切换", ex: ["peo.head", "peo.flip"]),
        Week(stage: "C", focus: "弱混", ex: ["peo.weak", "peo.weakoct"]),
        Week(stage: "D", focus: "混声、换声点、强混", ex: ["peo.mix", "peo.passaggio", "peo.belt"]),
        Week(stage: "D", focus: "R&B 风格和复习", ex: ["peo.rnb", "peo.weak", "peo.oct", "peo.hiss"]),
    ]

    static let peoChecks: [(text: String, exercise: String?)] = [
        ("测出音域，记录嘶气时长作为基线", "peo.range"),
        ("录一段 5-4-3-2-1，听是不是平时说话的音色", "peo.voice"),
        ("八度琶音唱到顶音时喉头不上提、不发紧", "peo.loose"),
        ("1-8-1 八度跳连续唱 8 个调不破音", "peo.oct"),
        ("头声滑音轻松连贯，没有台阶", "peo.head"),
        ("弱混顶音稳定地保持四拍", "peo.weak"),
        ("录一段混声高音，检查是否发紧", nil),
        ("重唱第一周录的歌，写下三处具体变化", nil),
    ]

    static let peo = Teacher(
        id: "peo", name: "Peo 老师", about: "欧美流行 · SLS 唱法（Bilibili）",
        platform: .bilibili, home: URL(string: "https://space.bilibili.com/3546774224505365")!,
        exercises: peoExercises,
        warmup: [("peo.scale", "跟着视频唱 5 个调，音量中等，不追求高音。"), ("peo.321", "唱 5 个调，越往上越轻。")],
        weeks: peoWeeks,
        stageNames: ["A": "基础", "B": "放松与稳定", "C": "头声与弱混", "D": "混声与风格"],
        checks: peoChecks, videos: peoVideos,
        // her piano before each key, where it is heard clearly: the major triad, often with the octave
        cueChord: [0, 4, 7, 12], hasPrograms: false)
}
