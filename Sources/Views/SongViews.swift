import SwiftUI

/// The songs suggested for a week: what each is good for, and where to find it.
struct WeekSongs: View {
    let teacher: String
    let week: Int

    var body: some View {
        ForEach(Course.songs(teacher: teacher, week: week)) { song in
            SongRow(song: song)
        }
    }
}

struct SongRow: View {
    let song: SongPick

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "music.note").foregroundStyle(.tint).padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(song.title).font(.body.weight(.semibold))
                    Text(song.artist).font(.callout).foregroundStyle(.secondary)
                }
                Text(song.focus).font(.caption).foregroundStyle(.secondary)
                Text("难度 " + String(repeating: "●", count: song.level) + String(repeating: "○", count: 3 - song.level))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                if let bv = song.teacherVideo, let url = URL(string: "https://www.bilibili.com/video/\(bv)/") {
                    Link(destination: url) { Label("看老师的演唱", systemImage: "play.rectangle") }
                    Divider()
                }
                ForEach(song.searchLinks, id: \.name) { l in
                    Link(destination: l.url) { Text("在 \(l.name) 搜索") }
                }
            } label: {
                Image(systemName: "magnifyingglass.circle").imageScale(.large)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("查找这首歌")
        }
        .padding(.vertical, 2)
    }
}
