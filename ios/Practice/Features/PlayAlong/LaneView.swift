import SwiftUI

/// The play-along lane: notes scroll from the right to the hit line. Each note lights when it is played: teal when
/// tight, softer teal when close, amber when loose, red when missed. Played notes show as dots along the bottom,
/// so an early or late one sits ahead of or behind its note. The pick direction is under each note.
struct LaneView: View {
    let notes: [Exercise.Note]
    let played: [Onset]
    let states: [PlayAlong.NoteState]
    let now: Double
    let beat: Double

    private let past = 0.8      // seconds shown left of the hit line
    private let ahead = 2.4     // seconds shown right of it

    var body: some View {
        Canvas { ctx, size in
            let hitX = size.width * past / (past + ahead)
            let pps = size.width / (past + ahead)
            func x(_ t: Double) -> CGFloat { hitX + CGFloat(t - now) * pps }
            let mid = size.height * 0.45

            // Beat lines.
            if beat > 0 {
                var b = ((now - past) / beat).rounded(.down) * beat
                while b < now + ahead {
                    let bx = x(b)
                    ctx.fill(Path(CGRect(x: bx - 0.5, y: 8, width: 1, height: size.height - 16)), with: .color(Theme.line))
                    b += beat
                }
            }
            // The hit line.
            ctx.fill(Path(roundedRect: CGRect(x: hitX - 1.5, y: 0, width: 3, height: size.height), cornerRadius: 1.5), with: .color(Theme.lineStrong))

            // Notes.
            for (i, n) in notes.enumerated() where n.time > now - past - 0.1 && n.time < now + ahead + 0.1 {
                let nx = x(n.time)
                let h: CGFloat = n.accent ? 44 : 30
                let colour: Color
                switch i < states.count ? states[i] : .waiting {
                case .waiting: colour = Theme.faint
                case .tight: colour = Theme.accent
                case .close: colour = Theme.accent.opacity(0.55)
                case .loose: colour = Theme.warn
                case .missed: colour = Theme.danger.opacity(0.7)
                }
                let rect = CGRect(x: nx - 3, y: mid - h / 2, width: 6, height: h)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(colour))
                if let p = n.pick {
                    let label = Text(p == .down ? "\u{2193}" : "\u{2191}").font(.system(size: 10)).foregroundColor(Theme.faint)
                    ctx.draw(label, at: CGPoint(x: nx, y: mid + h / 2 + 10))
                }
            }

            // Played notes.
            let dotY = size.height - 18
            for o in played where o.time > now - past - 0.1 && o.time < now + 0.2 {
                let px = x(o.time)
                ctx.fill(Path(ellipseIn: CGRect(x: px - 3.5, y: dotY - 3.5, width: 7, height: 7)), with: .color(Theme.text))
            }
        }
        .background(Theme.side, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
