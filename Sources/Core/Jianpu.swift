import Foundation

/// The jianpu text the course tools write ("1' 5 3 1", "#2 1") and comparison of note shapes.
enum Jianpu {
    private static let degree: [Character: Int] = ["1": 0, "2": 2, "3": 4, "4": 5, "5": 7, "6": 9, "7": 11]

    /// Semitones of a jianpu string: `'` raises an octave, `.` lowers one, `#` raises a semitone.
    static func semitones(_ text: String) -> [Int]? {
        var out: [Int] = []
        for token in text.split(separator: " ") {
            var s = 0
            var digit: Int? = nil
            for c in token {
                switch c {
                case "#": s += 1
                case "'": s += 12
                case ".": s -= 12
                default:
                    guard let d = degree[c], digit == nil else { return nil }
                    digit = d
                }
            }
            guard let d = digit else { return nil }
            out.append(s + d)
        }
        return out.isEmpty ? nil : out
    }

    /// A shape as the analysis sees it: repeated notes merged, lowest note at 0.
    static func shape(_ semis: [Int]) -> [Int] {
        var merged: [Int] = []
        for s in semis where merged.last != s { merged.append(s) }
        guard let low = merged.min() else { return [] }
        return merged.map { $0 - low }
    }

    /// True when a clip's analysed notes are the same shape as the exercise's pattern.
    static func matches(_ clip: String, pattern: Pattern) -> Bool {
        guard let s = semitones(clip) else { return false }
        let notes = pattern.steps.filter { !$0.ns }.map { $0.s }
        return shape(s) == shape(notes)
    }
}
