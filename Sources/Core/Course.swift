import Foundation

/// One note of an exercise pattern. `s` = semitones above the root, `b` = beats,
/// `j` = jianpu digit, `o` = upper-octave dot, `l` = lyric, `g` = glide target, `ns` = not scored.
struct Step: Hashable {
    var s: Int
    var b: Double
    var j: String
    var o: Bool = false
    var l: String? = nil
    var g: Int? = nil
    var ns: Bool = false
}

struct Pattern {
    var name: String
    var steps: [Step]
    var bpm: Double
    var fixed: Bool = false
    var rootStep: Int = 1

    var beats: Double { steps.reduce(0) { $0 + $1.b } }
    var maxSemitone: Int { steps.map { max($0.s, $0.g ?? -99) }.max() ?? 0 }
    var minSemitone: Int { min(0, steps.map { $0.s }.min() ?? 0) }
}

enum Zone: Hashable { case full, low, high }
enum Metric: Hashable { case none, bright, vibrato, straight, vowels }

struct Exercise: Identifiable, Hashable {
    enum Kind: Hashable { case pitch, breath, farinelli, range }

    let id: String
    let ep: Int
    let t: Int
    let name: String
    let syl: String
    var pat: String? = nil
    var kind: Kind = .pitch
    var zone: Zone = .full
    var fromTitle: Bool = false
    var metric: Metric = .none
    /// the pattern was checked against the course video (subtitles or audio analysis)
    var verified: Bool = false
    let tip: String

    var pattern: Pattern? { pat.flatMap { Course.patterns[$0] } }
    var videoURL: URL? { Course.videoURL(ep: ep, t: t) }
}

struct Week {
    let stage: String
    let focus: String
    let ex: [String]
}

enum Course {
    static let maj = [0, 2, 4, 5, 7, 9, 11, 12, 14]

    static func deg(_ seq: [Int], _ b: Double, _ last: Double, labels: [String]? = nil) -> [Step] {
        seq.enumerated().map { i, d in
            Step(s: maj[d - 1], b: i == seq.count - 1 ? last : b, j: String((d - 1) % 7 + 1), o: d > 7, l: labels?[i])
        }
    }

    static func vibSteps() -> [Step] {
        var s: [Step] = []
        for i in 0..<8 { s.append(Step(s: i % 2 == 1 ? 2 : 0, b: 0.5, j: i % 2 == 1 ? "2" : "1")) }
        for i in 0..<8 { s.append(Step(s: i % 2 == 1 ? 2 : 0, b: 0.25, j: i % 2 == 1 ? "2" : "1", ns: true)) }
        s.append(Step(s: 0, b: 2, j: "1"))
        return s
    }

    static func graceSteps() -> [Step] {
        var out: [Step] = []
        let ds = [1, 3, 5, 3, 1]
        for (i, d) in ds.enumerated() {
            let s = maj[d - 1]
            out.append(Step(s: s - 1, b: 0.25, j: "↗", ns: true))
            out.append(Step(s: s, b: i == ds.count - 1 ? 1.75 : 0.75, j: String(d)))
        }
        return out
    }

    static let patterns: [String: Pattern] = [
        "five": Pattern(name: "五音音阶", steps: deg([1, 2, 3, 4, 5, 4, 3, 2, 1], 1, 2), bpm: 110),
        "arp5": Pattern(name: "1-3-5 琶音", steps: deg([1, 3, 5, 3, 1], 1, 2), bpm: 96),
        "arp8": Pattern(name: "八度琶音", steps: deg([1, 3, 5, 8, 5, 3, 1], 1, 2), bpm: 96),
        "scale9": Pattern(name: "九度音阶", steps: deg([1, 2, 3, 4, 5, 6, 7, 8, 9, 8, 7, 6, 5, 4, 3, 2, 1], 0.5, 2), bpm: 96),
        "down8": Pattern(name: "8-5-3-1 下行琶音", steps: deg([8, 5, 3, 1], 1, 2), bpm: 84),
        "down5": Pattern(name: "5-4-3-2-1 下行音阶", steps: deg([5, 4, 3, 2, 1], 1, 2), bpm: 110),
        "p51": Pattern(name: "5-1", steps: deg([5, 1], 1, 2), bpm: 84),
        "p851": Pattern(name: "8-5-1", steps: deg([8, 5, 1], 1, 2), bpm: 84),
        "p6441": Pattern(name: "6-4-4-1 滑音", steps: deg([6, 4, 4, 1], 1, 2), bpm: 84),
        "p53421": Pattern(name: "5-3-4-2-1", steps: deg([5, 3, 4, 2, 1], 1, 2), bpm: 100),
        "p1355531": Pattern(name: "1-3-5-5-5-3-1", steps: deg([1, 3, 5, 5, 5, 3, 1], 1, 2), bpm: 100),
        "p1358888531": Pattern(name: "1-3-5-8-8-8-8-5-3-1", steps: deg([1, 3, 5, 8, 8, 8, 8, 5, 3, 1], 1, 2), bpm: 110),
        "p88851": Pattern(name: "8-8-8-5-1", steps: deg([8, 8, 8, 5, 1], 1, 2), bpm: 100),
        "p15151": Pattern(name: "1-5-1-5-1", steps: deg([1, 5, 1, 5, 1], 1, 2), bpm: 100),
        "p31": Pattern(name: "3-1", steps: deg([3, 1], 1, 2), bpm: 90),
        "p61": Pattern(name: "6-1", steps: deg([6, 1], 1, 2), bpm: 80),
        "p531": Pattern(name: "5-3-1", steps: deg([5, 3, 1], 1, 2), bpm: 100),
        "p1851": Pattern(name: "1-8-5-1", steps: deg([1, 8, 5, 1], 1, 2), bpm: 90),
        "p141": Pattern(name: "1-4-1", steps: deg([1, 4, 1], 1, 2), bpm: 100),
        "octJump": Pattern(name: "八度翻转", steps: deg([1, 8, 1, 8, 1], 1, 2), bpm: 90),
        "slide8": Pattern(name: "八度滑音（警笛）", steps: [
            Step(s: 0, b: 1, j: "1"),
            Step(s: 0, b: 2, j: "↗", g: 12, ns: true),
            Step(s: 12, b: 1, j: "1", o: true),
            Step(s: 12, b: 2, j: "↘", g: 0, ns: true),
            Step(s: 0, b: 1.5, j: "1"),
        ], bpm: 84),
        "sustain": Pattern(name: "长音", steps: [Step(s: 0, b: 6, j: "1")], bpm: 60, rootStep: 2),
        "vib": Pattern(name: "相邻音交替（颤音预备）", steps: vibSteps(), bpm: 72),
        // the course counts the five pentatonic notes "one to five" and back: 1-2-3-5-6-5-3-2-1
        "penta": Pattern(name: "五声音阶上下行", steps: zip([0, 2, 4, 7, 9, 7, 4, 2, 0], ["1", "2", "3", "5", "6", "5", "3", "2", "1"]).enumerated().map { i, p in
            Step(s: p.0, b: i == 8 ? 2 : 0.5, j: p.1)
        }, bpm: 84),
        "grace": Pattern(name: "倚音上滑", steps: graceSteps(), bpm: 80),
        "riff": Pattern(name: "三音转音", steps: [
            Step(s: 7, b: 0.5, j: "5"), Step(s: 4, b: 0.5, j: "3"), Step(s: 2, b: 0.5, j: "2"),
            Step(s: 4, b: 0.5, j: "3"), Step(s: 2, b: 0.5, j: "2"), Step(s: 0, b: 2.5, j: "1"),
        ], bpm: 80),
        "lalala": Pattern(name: "五音音阶（换辅音）", steps: deg([1, 2, 3, 4, 5, 4, 3, 2, 1], 1, 2, labels: ["LA", "LE", "LI", "LO", "LU", "LO", "LI", "LE", "LA"]), bpm: 100),
        "vowels": Pattern(name: "同一音高五个元音", steps: ["EE", "OH", "OO", "AY", "AH"].map { Step(s: 0, b: 3, j: "1", l: $0) }, bpm: 80, fixed: true),
    ]

    static let videoIDs: [Int: String] = [
        1: "mDQoMyPmg9s", 3: "UMPsoeYj67s", 5: "10zTYfosRoY", 12: "KHIU0jIJ3aw", 17: "y4OWZ8JYy74", 19: "Skc1IAUl__I",
        20: "31gNi8FIV2o", 27: "vkGBx7bIVtk", 30: "KN5368Aoxlk", 32: "cRFFZBykyto", 33: "pcFK4BvAOlY", 34: "n3yB3j_QhB0",
        35: "GOOQx8NTZ-4", 38: "YAOqF2lc57Q", 40: "CYEsGuldIQY", 45: "UUCu8FJwXKc", 54: "IKCe0_ukl8E", 58: "YxSKY0MsN54",
        61: "4MGTAjklUQ4", 62: "Wd8tHaAruiw", 64: "IhQ7g8Tnlhs", 66: "2GuvR1GlsRI", 67: "G2KoMjBTVs8", 70: "A8lPSYvmYUA",
        71: "_eIEsMtTLlk", 72: "vkOOxWSOBbs", 74: "PBbBM52ZcmI", 77: "1BLVrYKmwvc", 80: "6J4SuGEfU5U", 83: "teihdBE3O8U",
        86: "Rg2qjuzloKE", 87: "KaMJ9YvnUNw", 88: "obzz4a3tO4U", 89: "-rfwlXnRbzY", 92: "oDrhkt8KIA4", 96: "FSP1LF4c7uc",
        98: "1dPPo3MvTbc", 99: "9427xS0X1dM", 101: "h0SIEY_zNqU", 104: "J3Flsrn1L-A", 106: "tGY1UazyiiI", 111: "LauVoXN7iwY",
        114: "pYsO7HX84P8", 115: "RVYvo44kMms", 117: "KC6vNPLzftw", 120: "YOJTjSm7gvE", 128: "vIZSVTmyQIY", 129: "KfnxccMdi-A",
        130: "live:YLovaQ0gSwo",
    ]

    static func videoURL(ep: Int, t: Int) -> URL? {
        guard let id = videoIDs[ep] else { return nil }
        if id.hasPrefix("live:") {
            return URL(string: "https://www.youtube.com/live/\(id.dropFirst(5))" + (t > 0 ? "?t=\(t)s" : ""))
        }
        return URL(string: "https://www.youtube.com/watch?v=\(id)" + (t > 0 ? "&t=\(t)s" : ""))
    }

    static func mmss(_ t: Int) -> String { String(format: "%d:%02d", t / 60, t % 60) }

    static let exercises: [Exercise] = [
        Exercise(id: "trill", ep: 5, t: 205, name: "唇颤音", syl: "Brrr", pat: "down8", fromTitle: true, verified: true, tip: "嘴唇放松地颤动，像小马打响鼻；用手指轻推两颊能帮助起振。气流均匀，音高走得平滑。"),
        Exercise(id: "ng", ep: 101, t: 208, name: "NG 哼鸣", syl: "NG", pat: "down5", fromTitle: true, verified: true, tip: "舌根轻贴软腭，像英文 sing 的尾音。声音集中在鼻腔和脸的前方，喉咙不用力。"),
        Exercise(id: "ngah", ep: 101, t: 289, name: "NG 打开到 AH", syl: "NG-AH-AH-AH", pat: "p1851", fromTitle: true, verified: true, tip: "先在 NG 上找到集中的位置，再打开成 AH，打开时保持同样的位置和音量。"),
        Exercise(id: "ngv", ep: 101, t: 372, name: "NG 接各元音", syl: "NGING / NGENG / NGONG", pat: "arp5", fromTitle: true, verified: true, tip: "NG 之后接元音再收回 NG，例如 NGING、NGENG、NGONG。元音变了，共鸣位置不要跟着往下掉。"),
        Exercise(id: "range", ep: 106, t: 360, name: "找到你的音域", syl: "↕", kind: .range, fromTitle: true, tip: "到「音域」页记录你的最低音和最高音，之后每个练习的起止调会按你的音域安排。"),
        Exercise(id: "chest98", ep: 98, t: 502, name: "胸声练习", syl: "POW-ER", pat: "p51", zone: .low, fromTitle: true, tip: "像说话一样有力地喊出 POW-ER，胸口有振动感，只在胸声舒服的范围里唱，不要往上推。"),
        Exercise(id: "head98", ep: 98, t: 610, name: "头声/假声灵活度", syl: "YOO-HOO", pat: "p31", zone: .high, fromTitle: true, verified: true, tip: "轻而高的 YOO-HOO，往上走时不要挤，允许声音变轻、进入头声或假声。"),
        Exercise(id: "mix99", ep: 99, t: 296, name: "混声入门", syl: "GIHN-NIHN-NIHN-NIHN", pat: "down8", fromTitle: true, tip: "G 帮助闭合，N 和窄元音 IH 把声音放在前面，帮助胸声和头声连起来。"),
        Exercise(id: "str111", ep: 111, t: 321, name: "声音力量", syl: "Yeah", pat: "p61", fromTitle: true, verified: true, tip: "用健康、有力的舞台说话声说唱「Yeah」，声音要实，但不要喊。"),
        Exercise(id: "flex111", ep: 111, t: 485, name: "声音灵活度", syl: "HW", pat: "scale9", fromTitle: true, tip: "轻巧地走九度音阶，越往上越轻。"),
        Exercise(id: "hiss", ep: 20, t: 0, name: "嘶气比赛", syl: "SSS", kind: .breath, fromTitle: true, tip: "吸满气后发出均匀、细长的 SSS，看能坚持多久。肩膀不要上提，结尾不要挤。"),
        Exercise(id: "farinelli", ep: 92, t: 509, name: "Farinelli 呼吸", syl: "吸·停·呼", kind: .farinelli, fromTitle: true, tip: "吸气、保持、呼气各数相同的拍数，每轮加一拍。保持的时候靠肋骨和腹部撑住，不要关住喉咙。"),
        Exercise(id: "shzh", ep: 83, t: 366, name: "SH-ZH 气息练习", syl: "SH→ZH", kind: .breath, fromTitle: true, tip: "先发无声的 SH，再转成有声的 ZH，中间气流不断。计时看能持续多久。"),
        Exercise(id: "stamina62", ep: 62, t: 436, name: "气息耐力长音", syl: "MEM", pat: "sustain", fromTitle: true, metric: .straight, tip: "用 MEM 唱一条很长的音阶，连做五遍，练气息耐力。结尾不塌、不抖。"),
        Exercise(id: "jaw35", ep: 35, t: 300, name: "放松下巴", syl: "HUH", pat: "arp5", fromTitle: true, verified: true, tip: "用 HUH 唱 1-3-5-3-1，下巴自然下垂，不往前伸；可以把手指轻放在下巴上，检查有没有用力。"),
        Exercise(id: "ee33", ep: 33, t: 434, name: "EE 防舌根后缩", syl: "KE-KE-KE-KE-KE", pat: "down5", fromTitle: true, verified: true, tip: "舌尖轻抵下齿，舌面向前拱，不要往喉咙里缩。"),
        Exercise(id: "yoh", ep: 86, t: 508, name: "胸声 YOH", syl: "YOH", pat: "p51", zone: .low, fromTitle: true, verified: true, tip: "像在说话一样在音高上说出 YOH（5-1），饱满、有说话感，只在胸声舒服的范围里唱。"),
        Exercise(id: "vwohm", ep: 87, t: 550, name: "头声 VWOHM", syl: "VWOHM", pat: "p6441", zone: .high, fromTitle: true, verified: true, tip: "从高处轻轻往下带，V 让气流稳定，保持头声的轻和圆。"),
        Exercise(id: "fals89", ep: 89, t: 574, name: "假声与加强假声", syl: "HWOO", pat: "p851", zone: .high, fromTitle: true, verified: true, tip: "先唱带气的假声，再在同样的音高上加一点闭合，让声音更实。"),
        Exercise(id: "filter", ep: 19, t: 263, name: "Filter 过滤练习", syl: "Z", pat: "slide8", zone: .high, fromTitle: true, tip: "往上滑时逐渐减掉胸声的重量，像把声音过滤得更轻、更窄。"),
        Exercise(id: "larynx17", ep: 17, t: 317, name: "降低喉位", syl: "BUB", pat: "down5", fromTitle: true, verified: true, tip: "用有点傻气、低沉的 BUB 感受喉头放低，不要用舌根去压。"),
        Exercise(id: "mix40", ep: 40, t: 454, name: "混声练习", syl: "BUB", pat: "down8", fromTitle: true, metric: .bright, verified: true, tip: "用轻、有闭合、不费力的混声唱 BUB。往上走时不要推气、不要摊开，也尽量不要翻成假声；翻了也没关系，慢慢练。"),
        Exercise(id: "guun", ep: 88, t: 544, name: "GUUN-NUUN", syl: "GUUN-NUUN", pat: "p851", fromTitle: true, verified: true, tip: "G 和 N 帮助闭合与鼻腔共鸣，UU 元音窄而集中，适合用来走过换声点。"),
        Exercise(id: "yodel", ep: 114, t: 149, name: "约德尔声区翻转", syl: "OO", pat: "octJump", fromTitle: true, tip: "低音用胸声、高音用头声，故意让声音在两个声区之间翻转，练灵活度。"),
        Exercise(id: "comp114", ep: 114, t: 306, name: "声带闭合", syl: "MEHM", pat: "five", fromTitle: true, metric: .bright, tip: "MEHM 帮助声带闭合，声音实而不压。"),
        Exercise(id: "nasal115", ep: 115, t: 264, name: "鼻腔共鸣", syl: "NGAWNG", pat: "p141", fromTitle: true, metric: .bright, tip: "声音往前放在鼻腔和面部。可以捏住鼻子对比：有鼻腔共鸣时声音会明显变化。"),
        Exercise(id: "passaggio", ep: 45, t: 394, name: "跨越换声点", syl: "MA-AWN-NAWN-NAWN", pat: "down8", fromTitle: true, tip: "从 MA 打开，再用带鼻音的 AWN、NAWN 走过换声点：音量略减、元音稍收窄，让声区平滑衔接。"),
        Exercise(id: "crack12", ep: 12, t: 308, name: "平衡闭合（防破音）", syl: "GIG", pat: "down8", fromTitle: true, verified: true, tip: "用 GIG 让声带适度闭合，一路唱上去不挤、尽量不破音。破音多发生在换声点，别在高处突然加力。"),
        Exercise(id: "ee54", ep: 54, t: 366, name: "EE 元音", syl: "GWEEN", pat: "p53421", fromTitle: true, metric: .bright, verified: true, tip: "EE 自带明亮和闭合，练好后把这种集中感带到其他元音上。"),
        Exercise(id: "oh61", ep: 61, t: 456, name: "开口 OH", syl: "MWOHM", pat: "p1355531", fromTitle: true, metric: .bright, verified: true, tip: "嘴唇圆而不撅，口腔内部空间大，声音饱满。"),
        Exercise(id: "hoong", ep: 80, t: 368, name: "HOONG", syl: "HOONG", pat: "p851", fromTitle: true, metric: .bright, verified: true, tip: "嘴唇保持撅起的 OO 口型从上到下不变，NG 把声音带到前面，共鸣也上下一致。"),
        Exercise(id: "nyay", ep: 96, t: 534, name: "NYAY", syl: "NYAY", pat: "arp8", fromTitle: true, metric: .bright, tip: "NY 让舌头靠前，AY 明亮，适合找混声的穿透力。"),
        Exercise(id: "ah130", ep: 130, t: 346, name: "AH 元音", syl: "AH", pat: "five", fromTitle: true, metric: .bright, tip: "下巴放松，舌尖贴下齿，AH 不要撑成很大的「啊」。"),
        Exercise(id: "i38", ep: 38, t: 348, name: "I 元音", syl: "MWI", pat: "arp8", fromTitle: true, metric: .bright, verified: true, tip: "I 是双元音：长音停在 AH 上，最后再轻轻收到 EE。"),
        Exercise(id: "vowels117", ep: 117, t: 424, name: "元音统一检测", syl: "EE·OH·OO·AY·AH", pat: "vowels", metric: .vowels, tip: "在同一个音高上依次唱五个元音，比较每个元音的音准和明亮度。这是阶段 C 的检验项目。"),
        Exercise(id: "twang", ep: 77, t: 493, name: "Twang 明亮音色", syl: "NAAN", pat: "p1358888531", fromTitle: true, metric: .bright, verified: true, tip: "用 NAAN 唱出窄而亮、有穿透力的声音，像小鸭子叫或小孩撒娇那样。"),
        Exercise(id: "spread", ep: 32, t: 369, name: "中性口型", syl: "MA", pat: "arp8", fromTitle: true, metric: .bright, tip: "嘴角不要往两边咧，口型保持中性，避免声音发扁。"),
        Exercise(id: "l66", ep: 66, t: 408, name: "驯服 L", syl: "NLEHN", pat: "lalala", fromTitle: true, tip: "L 用舌尖轻点上齿龈后立刻离开，不要让舌根参与。"),
        Exercise(id: "r67", ep: 67, t: 281, name: "驯服 R", syl: "MRARM", pat: "five", fromTitle: true, tip: "R 尽量短，元音尽快回到打开的位置。"),
        Exercise(id: "comp104", ep: 104, t: 562, name: "声带闭合与力量", syl: "IH-GIHG-GIHG", pat: "p88851", fromTitle: true, metric: .bright, verified: true, tip: "声音实、清楚、不带气，但喉咙不挤。"),
        Exercise(id: "belt70", ep: 70, t: 463, name: "胸声 Belting", syl: "WHOA", pat: "arp5", zone: .low, fromTitle: true, tip: "像 Kings of Leon 歌里那样喊出 WHOA，把胸声往上带。只在舒服的范围内唱，宁可低一点也别拉过头。"),
        Exercise(id: "belt71", ep: 71, t: 414, name: "混声高音 Belting", syl: "HALLELUJAH", pat: "arp5", fromTitle: true, metric: .bright, tip: "偏胸声的混声，元音保持明亮，唱到高点时不要抬下巴。"),
        Exercise(id: "belt72", ep: 72, t: 505, name: "轻 Belting", syl: "MEOW", pat: "p15151", fromTitle: true, verified: true, tip: "力量和灵活结合，音量七分就够。"),
        Exercise(id: "low128", ep: 128, t: 201, name: "低音区", syl: "BAA（羊叫）", pat: "p531", zone: .low, fromTitle: true, verified: true, tip: "课程里的「羊怪兽」练习：先学普通小羊怯生生的叫声，再换成浑厚的「怪兽羊」叫声。低音不要压喉，放松让声音自然下沉。"),
        Exercise(id: "legato", ep: 58, t: 330, name: "Legato 连贯", syl: "BOH-GOH-DOH", pat: "scale9", fromTitle: true, tip: "换辅音也不断线：BOH、GOH、DOH 之间保持连贯，像画一条线。"),
        Exercise(id: "straight", ep: 74, t: 526, name: "直音", syl: "ZOON", pat: "sustain", fromTitle: true, metric: .straight, tip: "先用 Z 让声音稳定，再接 OON，保持一条平直的音高线，不带颤音。这里会测颤音幅度，越小越好。"),
        Exercise(id: "vib30", ep: 30, t: 386, name: "颤音第一步：交替音", syl: "ME", pat: "vib", fromTitle: true, tip: "在两个相邻音之间交替，先慢后快，最后放松成自然的颤动。"),
        Exercise(id: "vib64", ep: 64, t: 412, name: "自由颤音", syl: "HE", pat: "sustain", fromTitle: true, metric: .vibrato, verified: true, tip: "在一个音上，先唱短促的 HE（staccato），再放成带颤音的长音。常见的健康颤音大约每秒 5–7 次，幅度在半音以内。"),
        Exercise(id: "penta3", ep: 3, t: 296, name: "五声音阶 Riff", syl: "MAY", pat: "penta", fromTitle: true, verified: true, tip: "先慢后快，每个音都唱清楚，再提速。"),
        Exercise(id: "slash27", ep: 27, t: 346, name: "上滑装饰音", syl: "HEY", pat: "grace", fromTitle: true, tip: "从下方快速滑进目标音，滑音要短，落点要准。"),
        Exercise(id: "riff120", ep: 120, t: 301, name: "三音转音", syl: "OH", pat: "riff", tip: "把转音拆成三个音一组，慢速唱准后再加速。"),
        Exercise(id: "pitch34", ep: 34, t: 283, name: "放松找准音", syl: "MUM", pat: "arp5", fromTitle: true, verified: true, tip: "先在心里听到这个音，再轻松地唱出来，不要靠喉咙去「够」音。"),
        Exercise(id: "larynx129", ep: 129, t: 441, name: "喉位控制", syl: "GUH / NAY", pat: "arp8", metric: .bright, tip: "同一个音型交替用低喉位的 GUH 和高喉位的 NAY，感受音色的变化。"),
    ]

    static let byID: [String: Exercise] = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })

    /// Short daily warm-up shown above the weeks (plan: lip trills and humming, Ep. 5 and Ep. 101).
    static let warmup = ["trill", "ng"]

    /// Each exercise sits in the week its episode is scheduled in the 12-week plan; week 12 reviews earlier ones.
    static let weeks: [Week] = [
        Week(stage: "A", focus: "入门、热身、找到音域", ex: ["range", "chest98", "head98", "mix99"]),
        Week(stage: "A", focus: "呼吸方式、嘶气练习、常见错误", ex: ["hiss", "str111", "flex111"]),
        Week(stage: "A", focus: "气息支持，放松下巴和舌头", ex: ["farinelli", "shzh", "stamina62", "trill", "ng", "ngah", "ngv", "jaw35", "ee33"]),
        Week(stage: "B", focus: "找到胸声、头声、假声", ex: ["yoh", "vwohm", "fals89", "filter", "larynx17"]),
        Week(stage: "B", focus: "混声、换声点、处理破音", ex: ["mix40", "guun", "yodel", "comp114", "nasal115", "passaggio", "crack12"]),
        Week(stage: "C", focus: "五个元音的音色统一", ex: ["ee54", "oh61", "hoong", "nyay", "ah130", "i38", "vowels117"]),
        Week(stage: "C", focus: "向前唱、twang、口型、难唱的辅音", ex: ["twang", "spread", "l66", "r67"]),
        Week(stage: "D", focus: "声带闭合、安全的 belting", ex: ["comp104", "belt70", "belt71", "belt72"]),
        Week(stage: "D", focus: "耐力、低音、legato、直音", ex: ["low128", "legato", "straight"]),
        Week(stage: "D", focus: "颤音和 riff，从慢速开始", ex: ["vib30", "vib64", "penta3", "slash27", "riff120"]),
        Week(stage: "E", focus: "把技巧带进歌、选调", ex: ["pitch34", "larynx129"]),
        Week(stage: "E", focus: "复习和结业检验（前面各周的检验项目）", ex: ["passaggio", "vowels117", "vib64", "hiss"]),
    ]

    static let stageNames = ["A": "基础", "B": "声区与过渡", "C": "元音与共鸣", "D": "力量与技巧", "E": "应用"]

    /// Notes of the chord that sets each key, in semitones from the root (negative = below the root).
    /// The course plays a major triad over two octaves (1 3 5 1' 3' 5'), found by tools/course/analyze.py
    /// in the exercises where the piano is heard clearly (trill, oh61, ee33, yoh, mix40, low128, twang).
    static let cueChord = [0, 4, 7, 12, 16, 19]
}
