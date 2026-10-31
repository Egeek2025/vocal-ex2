import SwiftUI

extension Color {
    static func stage(_ s: String) -> Color {
        switch s {
        case "A": return Color(red: 0.42, green: 0.50, blue: 0.62)
        case "B": return .teal
        case "C": return .purple
        case "D": return .orange
        default: return .green
        }
    }

    static func score(_ acc: Double) -> Color {
        acc >= 0.75 ? .green : acc >= 0.5 ? .orange : .red
    }

    static func cents(_ c: Double) -> Color {
        abs(c) <= 25 ? .green : abs(c) <= 50 ? .orange : .red
    }
}

/// Small labelled number used in result summaries.
struct Tile: View {
    let title: String
    let value: String
    var note: String = ""
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.title2, design: .monospaced).weight(.bold)).foregroundStyle(color)
            if !note.isEmpty { Text(note).font(.caption2).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
    }
}

let tileColumns = [GridItem(.adaptive(minimum: 130), spacing: 10)]

func dateLabel(_ d: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "M/d HH:mm"
    return f.string(from: d)
}
