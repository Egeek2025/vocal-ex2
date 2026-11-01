import SwiftUI

/// A piano keyboard that lights up the keys being played and the note to sing, marks the note being sung,
/// and plays a note when a key is pressed, by touch, mouse or the computer keyboard.
///
/// Keys never get narrower than a real piano's (white keys about 23.5 x 150 mm); when there is room they
/// widen to fill the width, and when there is not the keyboard scrolls sideways and keeps the current key
/// in view.
struct PianoKeyboard: View {
    static let low = 36    // C2
    static let high = 95   // B6
    /// computer keys in the layout of GarageBand's Musical Typing: home row = white keys, row above = black keys
    static let typing: [Character] = ["a", "w", "s", "e", "d", "f", "t", "g", "y", "h", "u", "j", "k", "o", "l", "p", ";", "'"]

    /// keys sounding now (chord, demo note)
    var playing: Set<Int> = []
    /// the note the singer should be on
    var target: Int? = nil
    /// the note being sung, rounded to the nearest key, and how far off it is in cents
    var sung: (key: Int, cents: Double)? = nil
    /// key to keep in the middle of the view; the keyboard scrolls when it changes
    var focus: Int = 60
    var height: CGFloat = 120
    /// plays a key; nil makes the keyboard display only
    var onTap: ((Int) -> Void)? = nil

    /// keys held down or just clicked, drawn as pressed
    @State private var pressed: Set<Int> = []
    /// C of the octave the computer keys start at; follows `focus` until Z/X moves it
    @State private var typingBase: Int? = nil
    @FocusState private var focused: Bool

    private var whites: [Int] { (Self.low...Self.high).filter { Music.isNatural($0) } }
    private var realWhiteWidth: CGFloat { height * 23.5 / 150 }
    private var base: Int { typingBase ?? max(Self.low, min(Self.high - 17, focus / 12 * 12)) }

    var body: some View {
        GeometryReader { g in
            let ww = max(realWhiteWidth, g.size.width / CGFloat(whites.count))
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
                            let keys = layout(ww)
                            for k in keys where k.white { draw(k, in: &ctx) }
                            for k in keys where !k.white { draw(k, in: &ctx) }
                        }
                        .frame(width: ww * CGFloat(whites.count), height: height)
                        .gesture(SpatialTapGesture().onEnded { v in
                            guard onTap != nil, let m = key(at: v.location, ww) else { return }
                            focused = true
                            press(m, flash: true)
                        })
                    }
                }
                .onAppear { proxy.scrollTo(anchor(for: focus), anchor: .center) }
                .onChange(of: focus) { _, f in
                    withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(anchor(for: f), anchor: .center) }
                }
            }
        }
        .frame(height: height)
        .focusable(onTap != nil)
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(phases: [.down, .up]) { k in handle(k) }
        .accessibilityLabel("钢琴键盘")
    }

    // MARK: playing

    private func press(_ m: Int, flash: Bool) {
        onTap?(m)
        pressed.insert(m)
        if flash {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { pressed.remove(m) }
        }
    }

    /// Computer keys: A–' play a bit more than an octave from `base`, Z/X move it down/up an octave.
    private func handle(_ k: KeyPress) -> KeyPress.Result {
        guard onTap != nil, !k.modifiers.contains(.command), let c = k.characters.lowercased().first else { return .ignored }
        if c == "z" || c == "x" {
            if k.phase == .down {
                typingBase = max(Self.low, min(Self.high - 17, base + (c == "z" ? -12 : 12)))
            }
            return .handled
        }
        guard let i = Self.typing.firstIndex(of: c) else { return .ignored }
        let m = base + i
        guard m <= Self.high else { return .handled }
        if k.phase == .down {
            if !pressed.contains(m) { press(m, flash: false) }
        } else {
            pressed.remove(m)
        }
        return .handled
    }

    // MARK: layout and drawing

    private struct Key {
        let midi: Int
        let white: Bool
        let rect: CGRect
    }

    private func anchor(for m: Int) -> Int {
        let k = min(Self.high, max(Self.low, m))
        return Music.isNatural(k) ? k : k - 1
    }

    private func layout(_ ww: CGFloat) -> [Key] {
        let bw = realWhiteWidth * 13.7 / 23.5 * min(1.25, ww / realWhiteWidth)
        let bh = height * 95 / 150
        var keys: [Key] = []
        for (i, m) in whites.enumerated() {
            let x = CGFloat(i) * ww
            keys.append(Key(midi: m, white: true, rect: CGRect(x: x, y: 0, width: ww, height: height)))
            let black = m + 1
            if black <= Self.high, !Music.isNatural(black) {
                keys.append(Key(midi: black, white: false, rect: CGRect(x: x + ww - bw / 2, y: 0, width: bw, height: bh)))
            }
        }
        return keys
    }

    private func key(at p: CGPoint, _ ww: CGFloat) -> Int? {
        let keys = layout(ww)
        if let k = keys.first(where: { !$0.white && $0.rect.contains(p) }) { return k.midi }
        return keys.first(where: { $0.white && $0.rect.contains(p) })?.midi
    }

    private func draw(_ k: Key, in ctx: inout GraphicsContext) {
        let r = k.rect.insetBy(dx: k.white ? 0.5 : 0, dy: 0)
        let shape = Path(roundedRect: r, cornerRadii: RectangleCornerRadii(bottomLeading: 3, bottomTrailing: 3))
        var fill: Color = k.white ? .white : Color(white: 0.12)
        if pressed.contains(k.midi) {
            fill = k.white ? Color.orange.opacity(0.75) : Color.orange
        } else if playing.contains(k.midi) {
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
        // the computer key that plays this one, while the keyboard has focus
        if focused, onTap != nil {
            let i = k.midi - base
            if i >= 0, i < Self.typing.count {
                let label = String(Self.typing[i]).uppercased()
                ctx.draw(Text(label).font(.system(size: 9, weight: .semibold)).foregroundColor(k.white ? .secondary : .white.opacity(0.8)),
                         at: CGPoint(x: r.midX, y: k.white ? r.maxY - 36 : r.maxY - 8), anchor: .bottom)
            }
        }
    }
}
