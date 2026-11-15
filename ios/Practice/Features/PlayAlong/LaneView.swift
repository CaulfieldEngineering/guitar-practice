import SwiftUI

/// The run as scrolling tablature (Joe, 2026-11-14: "can we actually have the interface be tablature of sorts? So
/// that we can eventually implement left hand exercises?"). Six string lines, the high E on top as tab is written.
/// Each note is its fret number on its string, scrolling from the right to a fixed line; above the strings the
/// rhythm as it was (a bar for each note, taller where it is accented, grouped by the beat lines) with the pick
/// direction over each. A note takes its colour where it is when it is played: teal on the beat, softer teal when
/// close, amber when loose, red when missed. The picks themselves show as dots along the bottom, so an early or late
/// one sits ahead of or behind its note.
///
/// The string and the fret come from the drill's data (`string`, `fret`), so a left-hand drill shows its real
/// notes; a right-hand drill, which names neither, is an open G. `now` is the lane's clock (PlayAlong.laneNow),
/// already moved by the display offset, so a note reaches the line when it is heard.
struct TabLane: View {
    let notes: [Exercise.Note]
    let played: [Onset]
    let states: [PlayAlong.NoteState]
    let now: Double
    var beatsPerBar = 4

    private let past = 0.8      // seconds shown left of the hit line
    private let ahead = 2.4     // seconds shown right of it
    private static let stringNames = ["e", "B", "G", "D", "A", "E"]

    var body: some View {
        Canvas { ctx, size in
            let hitX = size.width * past / (past + ahead)
            let pps = size.width / (past + ahead)
            func x(_ t: Double) -> CGFloat { hitX + CGFloat(t - now) * pps }

            // The rows: pick marks, the rhythm, six strings, the picks that were heard.
            let arrowY: CGFloat = 12
            let rhythmY: CGFloat = 44
            let top: CGFloat = 84
            let dotY = size.height - 12
            let gap = max(10, (dotY - 22 - top) / 5)
            func stringY(_ s: Int) -> CGFloat { top + CGFloat(min(5, max(0, s - 1))) * gap }

            // The strings.
            for s in 1...6 {
                ctx.fill(Path(CGRect(x: 0, y: stringY(s) - 0.5, width: size.width, height: 1)), with: .color(Theme.lineStrong))
            }

            // Beat and bar lines: at the first note of each beat.
            var lastBeat = Int.min
            for n in notes where n.time > now - past - 0.1 && n.time < now + ahead + 0.1 {
                guard n.beat != lastBeat else { continue }
                lastBeat = n.beat
                let bar = n.beat % max(1, beatsPerBar) == 0
                let bx = x(n.time) - 9
                ctx.fill(Path(CGRect(x: bx - 0.5, y: bar ? 22 : 30, width: bar ? 1.5 : 1, height: stringY(6) - (bar ? 22 : 30))),
                         with: .color(bar ? Theme.faint : Theme.line))
            }

            // The line the notes are played on.
            ctx.fill(Path(roundedRect: CGRect(x: hitX - 1.5, y: 4, width: 3, height: size.height - 8), cornerRadius: 1.5), with: .color(Theme.muted))

            for (i, n) in notes.enumerated() where n.time > now - past - 0.1 && n.time < now + ahead + 0.1 {
                let nx = x(n.time)
                let state = i < states.count ? states[i] : .waiting
                let colour: Color
                switch state {
                case .waiting: colour = n.time < now ? Theme.faint : Theme.text
                case .tight: colour = Theme.accent
                case .close: colour = Theme.accent.opacity(0.6)
                case .loose: colour = Theme.warn
                case .missed: colour = Theme.danger
                }

                // The rhythm: a bar a note, and its pick direction above.
                let h: CGFloat = n.accent ? 34 : 22
                let bar = CGRect(x: nx - 2.5, y: rhythmY - h / 2, width: 5, height: h)
                ctx.fill(Path(roundedRect: bar, cornerRadius: 2.5), with: .color(state == .waiting ? Theme.faint : colour))
                if let p = n.pick {
                    let mark = Text(p == .down ? "\u{2193}" : "\u{2191}").font(.system(size: 11, weight: .medium)).foregroundColor(Theme.muted)
                    ctx.draw(mark, at: CGPoint(x: nx, y: arrowY))
                }

                // The note: its fret on its string.
                let y = stringY(n.string ?? 3)
                let label = "\(max(0, n.fret ?? 0))"
                let w: CGFloat = label.count > 1 ? 20 : 14
                ctx.fill(Path(roundedRect: CGRect(x: nx - w / 2, y: y - 8, width: w, height: 16), cornerRadius: 4), with: .color(Theme.side))
                let fret = Text(label).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundColor(colour)
                ctx.draw(fret, at: CGPoint(x: nx, y: y))
            }

            // The picks that were heard.
            for o in played where o.time > now - past - 0.1 && o.time < now + 0.2 {
                let px = x(o.time)
                ctx.fill(Path(ellipseIn: CGRect(x: px - 3, y: dotY - 3, width: 6, height: 6)), with: .color(Theme.text))
            }

            // The strings' names, at the left edge.
            ctx.fill(Path(CGRect(x: 0, y: top - 12, width: 18, height: stringY(6) - top + 24)), with: .color(Theme.side))
            for s in 1...6 {
                let name = Text(TabLane.stringNames[s - 1]).font(.system(size: 10, weight: .medium)).foregroundColor(Theme.faint)
                ctx.draw(name, at: CGPoint(x: 8, y: stringY(s)))
            }
        }
        .background(Theme.side, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// A drill's pattern at a glance: one cell a beat, a tick for each note in it, taller where it is accented.
struct PatternStrip: View {
    let exercise: Exercise

    var body: some View {
        let sizes = RunBuilder.groupSizes(exercise)
        Canvas { ctx, size in
            // A short pattern is shown a few times over, so the strip is at least four beats long.
            let cycle = max(1, exercise.cycleBeats)
            let repeats = cycle >= 4 ? 1 : Int((4.0 / Double(cycle)).rounded(.up))
            let beats = cycle * repeats
            let cell = size.width / CGFloat(beats)
            for b in 1..<max(2, beats) where beats > 1 {
                ctx.fill(Path(CGRect(x: CGFloat(b) * cell - 0.5, y: 2, width: 1, height: size.height - 4)), with: .color(Theme.line))
            }
            for r in 0..<repeats {
                for n in exercise.notes {
                    let pos = n.at.beats + Double(r * cycle)
                    let x = CGFloat(pos) * cell + cell * 0.08 + 1.5
                    let h: CGFloat = n.accent ? size.height - 6 : size.height * 0.5
                    let rect = CGRect(x: x, y: (size.height - h) / 2, width: 3, height: h)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(n.accent ? Theme.accent : Theme.muted))
                }
            }
        }
        .frame(height: 28)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.columnPattern)
        .accessibilityValue(sizes.map { $0 == 0 ? L.rest : "\($0)" }.joined(separator: ", ") + " " + L.notesPerBeat)
    }
}
