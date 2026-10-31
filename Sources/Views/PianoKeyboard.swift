import SwiftUI

/// A piano keyboard in real proportions that lights up the keys being played and the note to sing,
/// marks the note being sung, and plays a note when a key is tapped. It scrolls sideways and keeps
/// the current key in view.
struct PianoKeyboard: View {
    static let low = 36    // C2
    static let high = 95   // B6

    /// keys sounding now (chord, demo note)
    var playing: Set<Int> = []
    /// the note the singer should be on
    var target: Int? = nil
    /// the note being sung, rounded to the nearest key, and how far off it is in cents
    var sung: (key: Int, cents: Double)? = nil
    /// key to keep in the middle of the view; the keyboard scrolls when it changes
    var focus: Int = 60
    var height: CGFloat = 120
    var onTap: ((Int) -> Void)? = nil

    // a real piano: white keys about 23.5 x 150 mm, black keys about 13.7 x 95 mm
    private var whiteWidth: CGFloat { height * 23.5 / 150 }
    private var blackWidth: CGFloat { whiteWidth * 13.7 / 23.5 }
    private var blackHeight: CGFloat { height * 95 / 150 }
    private var whites: [Int] { (Self.low...Self.high).filter { Music.isNatural($0) } }

    var body: some View {
        let ww = whiteWidth
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    // one anchor per white key, so the view can scroll to a key
                    HStack(spacing: 0) {
                        ForEach(whites, id: \.self) { m in
                            Color.clear.frame(width: ww, height: 1).id(m)
                        }
                    }
                    Canvas { ctx, _ in
                        let keys = layout()
                        for k in keys where k.white { draw(k, in: &ctx) }
                        for k in keys where !k.white { draw(k, in: &ctx) }
                    }
                    .frame(width: ww * CGFloat(whites.count), height: height)
                    .gesture(SpatialTapGesture().onEnded { v in
                        if let m = key(at: v.location) { onTap?(m) }
                    })
                }
            }
            .onAppear { proxy.scrollTo(anchor(for: focus), anchor: .center) }
            .onChange(of: focus) { _, f in
                withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(anchor(for: f), anchor: .center) }
            }
        }
        .frame(height: height)
        .accessibilityLabel("钢琴键盘")
    }

    private struct Key {
        let midi: Int
        let white: Bool
        let rect: CGRect
    }

    private func anchor(for m: Int) -> Int {
        let k = min(Self.high, max(Self.low, m))
        return Music.isNatural(k) ? k : k - 1
    }

    private func layout() -> [Key] {
        var keys: [Key] = []
        for (i, m) in whites.enumerated() {
            let x = CGFloat(i) * whiteWidth
            keys.append(Key(midi: m, white: true, rect: CGRect(x: x, y: 0, width: whiteWidth, height: height)))
            let black = m + 1
            if black <= Self.high, !Music.isNatural(black) {
                keys.append(Key(midi: black, white: false,
                                rect: CGRect(x: x + whiteWidth - blackWidth / 2, y: 0, width: blackWidth, height: blackHeight)))
            }
        }
        return keys
    }

    private func key(at p: CGPoint) -> Int? {
        let keys = layout()
        if let k = keys.first(where: { !$0.white && $0.rect.contains(p) }) { return k.midi }
        return keys.first(where: { $0.white && $0.rect.contains(p) })?.midi
    }

    private func draw(_ k: Key, in ctx: inout GraphicsContext) {
        let r = k.rect.insetBy(dx: k.white ? 0.5 : 0, dy: 0)
        let shape = Path(roundedRect: r, cornerRadii: RectangleCornerRadii(bottomLeading: 3, bottomTrailing: 3))
        var fill: Color = k.white ? .white : Color(white: 0.12)
        if playing.contains(k.midi) {
            fill = .indigo
        } else if target == k.midi {
            fill = k.white ? Color.green.opacity(0.45) : Color.green.opacity(0.8)
        }
        ctx.fill(shape, with: .color(fill))
        ctx.stroke(shape, with: .color(.black.opacity(0.35)), lineWidth: 0.8)
        if let s = sung, s.key == k.midi {
            let d = min(r.width * 0.6, 12)
            let dot = CGRect(x: r.midX - d / 2, y: r.maxY - d - 6, width: d, height: d)
            ctx.fill(Path(ellipseIn: dot), with: .color(Color.cents(s.cents)))
        }
        if k.white && k.midi % 12 == 0 {
            ctx.draw(Text(Music.name(k.midi)).font(.system(size: 9, design: .monospaced)).foregroundColor(.gray),
                     at: CGPoint(x: r.midX, y: r.maxY - 22), anchor: .bottom)
        }
    }
}
