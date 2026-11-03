import Foundation

/// A song to apply the week's technique to. Only the title and artist: the app has no recordings or lyrics,
/// it links to music services where the song can be found.
struct SongPick: Identifiable, Hashable {
    let title: String
    let artist: String
    /// what to practise with it this week
    let focus: String
    /// how demanding it is for a male pop voice: 1 easy, 2 medium, 3 hard
    let level: Int
    /// a video of the teacher singing it, when there is one (Bilibili BV id)
    var teacherVideo: String? = nil

    var id: String { "\(title)|\(artist)" }

    /// Places to look the song up, by name.
    var searchLinks: [(name: String, url: URL)] {
        let q = "\(title) \(artist)"
        let e = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        let raw: [(String, String)] = [
            ("Apple Music", "https://music.apple.com/search?term=\(e)"),
            ("QQ 音乐", "https://y.qq.com/n/ryqq/search?w=\(e)"),
            ("网易云音乐", "https://music.163.com/#/search/m/?s=\(e)"),
            ("Bilibili", "https://search.bilibili.com/all?keyword=\(e)"),
            ("YouTube", "https://www.youtube.com/results?search_query=\(e)"),
        ]
        return raw.compactMap { n, u in URL(string: u).map { (n, $0) } }
    }
}

/// Songs for each week of each teacher's plan, chosen for a male pop voice: the week's technique shows up
/// in them clearly. Sing them in a key that suits you (most apps and karaoke versions can shift the key).
extension Course {
    static func songs(teacher: String, week: Int) -> [SongPick] {
        let all = teacher == peo.id ? peoSongs : stoneySongs
        return all.indices.contains(week) ? all[week] : []
    }

    static let stoneySongs: [[SongPick]] = [
        // 1 入门、热身、找到音域
        [SongPick(title: "Let It Be", artist: "The Beatles", focus: "中音区为主、旋律平稳，用来检查热身后说话般自然的音色。", level: 1),
         SongPick(title: "Stand by Me", artist: "Ben E. King", focus: "音域窄、节奏稳，适合录一段作为第 0 周的基线。", level: 1),
         SongPick(title: "晴天", artist: "周杰伦", focus: "中音区叙事，练咬字清楚又不压喉。", level: 1)],
        // 2 呼吸方式、嘶气练习
        [SongPick(title: "Yesterday", artist: "The Beatles", focus: "短歌、乐句长度均匀，练一口气唱完一句、句尾不塌。", level: 1),
         SongPick(title: "Hallelujah", artist: "Jeff Buckley", focus: "慢速长乐句，练气息平稳地支撑长音。", level: 2)],
        // 3 气息支持、放松下巴和舌头
        [SongPick(title: "Can't Help Falling in Love", artist: "Elvis Presley", focus: "慢歌长音多，练下巴放松、元音打开时不往后缩。", level: 1),
         SongPick(title: "Thinking Out Loud", artist: "Ed Sheeran", focus: "中音区连贯的长句，配合唇颤音和 NG 的放松感去唱。", level: 1)],
        // 4 胸声、头声、假声
        [SongPick(title: "Creep", artist: "Radiohead", focus: "主歌胸声、副歌高处可以用假声或轻头声，正好练三种声区的区别。", level: 2),
         SongPick(title: "Fix You", artist: "Coldplay", focus: "主歌假声、后半段转为胸声，练两种声音的切换。", level: 2)],
        // 5 混声、换声点、处理破音
        [SongPick(title: "Yellow", artist: "Coldplay", focus: "旋律在换声点附近反复，练过渡时不加重、不断开。", level: 2),
         SongPick(title: "Just the Way You Are", artist: "Bruno Mars", focus: "副歌持续在中高音区，练轻一点的混声。", level: 2),
         SongPick(title: "十年", artist: "陈奕迅", focus: "副歌上到换声点附近，练不挤、不破音地过去。", level: 2)],
        // 6 五个元音的音色统一
        [SongPick(title: "All of Me", artist: "John Legend", focus: "长音落在不同元音上，练元音变化时音色保持一致。", level: 2),
         SongPick(title: "Say You Won't Let Go", artist: "James Arthur", focus: "叙事型旋律，逐个元音检查是否发扁或发闷。", level: 2)],
        // 7 向前唱、twang、口型、难唱的辅音
        [SongPick(title: "Treasure", artist: "Bruno Mars", focus: "明亮靠前的流行唱法，练 twang 带来的穿透力。", level: 2),
         SongPick(title: "Uptown Funk", artist: "Mark Ronson ft. Bruno Mars", focus: "快速、辅音密集，练咬字清楚而喉咙不紧。", level: 2)],
        // 8 声带闭合、安全的 belting
        [SongPick(title: "Use Somebody", artist: "Kings of Leon", focus: "课程 belting 练习里提到的乐队，副歌长音练胸声往上带。只在舒服的范围里唱。", level: 3),
         SongPick(title: "Livin' on a Prayer", artist: "Bon Jovi", focus: "高强度 belting，先降调唱，确认闭合好、不喊再升回原调。", level: 3)],
        // 9 耐力、低音、legato、直音
        [SongPick(title: "Your Song", artist: "Elton John", focus: "旋律连贯，练 legato：音和音之间不断开。", level: 1),
         SongPick(title: "Hello", artist: "Lionel Richie", focus: "低音区和直音较多，练低音不压、直音稳定。", level: 2)],
        // 10 颤音和 riff
        [SongPick(title: "Ain't No Sunshine", artist: "Bill Withers", focus: "慢速、长音，练句尾自然出现颤音。", level: 1),
         SongPick(title: "Lately", artist: "Stevie Wonder", focus: "经典 R&B 转音，先放慢速度把每个音唱准。", level: 3)],
        // 11 把技巧带进歌、选调
        [SongPick(title: "Sign of the Times", artist: "Harry Styles", focus: "高处用头声或轻混声，练在真实歌曲里选择用哪种声音。", level: 3),
         SongPick(title: "Billie Jean", artist: "Michael Jackson", focus: "节奏感强、音域适中，练把技巧放进律动里，并找到最适合自己的调。", level: 2)],
        // 12 复习和结业检验
        [SongPick(title: "Someone You Loved", artist: "Lewis Capaldi", focus: "副歌混声爆发，作为结业检验：录下来和第 1 周的基线对比。", level: 3),
         SongPick(title: "江南", artist: "林俊杰", focus: "高音区混声和转音都有，检验换声点和音色统一。", level: 3)],
    ]

    static let peoSongs: [[SongPick]] = [
        // 1 开嗓、测音域、气息
        [SongPick(title: "Let It Be", artist: "The Beatles", focus: "开嗓后先唱一首中音区的歌，确认声音醒了、不累。", level: 1),
         SongPick(title: "Stay With Me", artist: "Sam Smith", focus: "慢速长句，练气息平稳，录一段作为第 1 周的基线。", level: 2)],
        // 2 找到真实的声音和共鸣
        [SongPick(title: "Perfect", artist: "Ed Sheeran", focus: "用说话般真实的音色唱，不刻意加共鸣。", level: 1),
         SongPick(title: "Thinking Out Loud", artist: "Ed Sheeran", focus: "主歌放松、副歌稍亮，感受共鸣随音高自然变化。", level: 1)],
        // 3 稳住喉位，不挤卡
        [SongPick(title: "Photograph", artist: "Ed Sheeran", focus: "副歌往上时检查喉头有没有跟着提起来。", level: 2),
         SongPick(title: "十年", artist: "陈奕迅", focus: "副歌高处容易挤，先降调唱到不紧，再慢慢升回去。", level: 2)],
        // 4 解决破音，正确练咽音
        [SongPick(title: "Someone You Loved", artist: "Lewis Capaldi", focus: "副歌高音容易破，用 1-8-1 八度跳的感觉提前想好高音再上去。", level: 3),
         SongPick(title: "Shallow", artist: "Lady Gaga & Bradley Cooper", focus: "唱男声部分，练集中、明亮但不紧的声音。", level: 2)],
        // 5 头声和真假声切换
        [SongPick(title: "Creep", artist: "Radiohead", focus: "高处的长音试着用头声或假声，练切换时不突兀。", level: 2),
         SongPick(title: "Fix You", artist: "Coldplay", focus: "主歌假声轻唱，后面转实声，练真假声的衔接。", level: 2)],
        // 6 弱混
        [SongPick(title: "When I Was Your Man", artist: "Bruno Mars", focus: "副歌高音用轻而集中的弱混，不要唱成喊。", level: 3),
         SongPick(title: "Say You Won't Let Go", artist: "James Arthur", focus: "中高音区保持弱混的轻松，句尾不加重。", level: 2)],
        // 7 混声、换声点、强混
        [SongPick(title: "Grenade", artist: "Bruno Mars", focus: "副歌持续高音强混，先在弱混里稳住再加力量。", level: 3),
         SongPick(title: "Use Somebody", artist: "Kings of Leon", focus: "副歌长音，练强混的力量来自闭合而不是喊。", level: 3),
         SongPick(title: "江南", artist: "林俊杰", focus: "反复经过换声点，检验混声是否连贯。", level: 3)],
        // 8 R&B 风格和复习
        [SongPick(title: "Ain't No Sunshine", artist: "Bill Withers", focus: "R&B 的松弛感和句尾颤音。", level: 1),
         SongPick(title: "Adorn", artist: "Miguel", focus: "R&B 的装饰音和布鲁斯音（♭3），先慢后快。", level: 3),
         SongPick(title: "House Of The Rising Sun", artist: "The Animals", focus: "Peo 老师在频道里翻唱过这首，可以先看她的演唱再自己唱。", level: 2,
                  teacherVideo: "BV1puzQB1E51")],
    ]
}
