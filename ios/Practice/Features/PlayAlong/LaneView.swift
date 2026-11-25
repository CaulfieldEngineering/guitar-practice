import SwiftUI

/// The run as scrolling tablature (Joe, 2026-11-14: "can we actually have the interface be tablature of sorts?").
/// One line a string of the tuning in use, the high string on top, its name at the left edge. A pitched note is its
/// fret number; an X note (any pitch counts) is a ×, as a muted string is written in tab. Notes scroll from the right
/// to the hit line, a third of the way in (the calibration line), and take their colour as they are judged: on the
/// click, close, loose, missed, or the wrong pitch (outlined, with the note heard under it). Above the strings the
/// rhythm (a mark a note, taller on an accent) and the pick direction; the picks heard are dots along the bottom.
/// `now` is the lane's clock, already moved by the display offset, so a note crosses the line when it is heard.
struct TabLane: View {
    let notes: [Exercise.Note]
    let played: [Onset]
    let states: [PlayAlong.NoteState]
    let now: Double
    var beatsPerBar = 4
    var tuning: Tuning = .standard
    /// The pitch heard for each note played on the wrong pitch (MIDI), by note index.
    var heard: [Int: Double] = [:]

    private let past = 1.2      // seconds left of the hit line
    private let ahead = 2.4     // seconds right of it

    var body: some View {
        Canvas { ctx, size in
            let hitX = size.width * past / (past + ahead)
            let pps = size.width / (past + ahead)
            func x(_ t: Double) -> CGFloat { hitX + CGFloat(t - now) * pps }
            let strings = max(1, tuning.strings.count)
            let arrowY: CGFloat = 10
            let rhythmY: CGFloat = 32
            let top: CGFloat = 60
            let dotY = size.height - 10
            let bottom = dotY - 26
            let gap = max(9, (bottom - top) / CGFloat(max(1, strings - 1)))
            func stringY(_ s: Int) -> CGFloat { top + CGFloat(min(strings - 1, max(0, s - 1))) * gap }
            let glyph = Font.callout.weight(.semibold).monospacedDigit()

            for s in 1...strings {
                ctx.fill(Path(CGRect(x: 18, y: stringY(s) - 0.5, width: size.width - 18, height: 1)), with: .color(Theme.lineStrong))
            }

            // Bar lines and beat lines at the first note of each beat.
            var lastBeat = Int.min
            for n in notes where n.time > now - past - 0.1 && n.time < now + ahead + 0.1 {
                guard n.beat != lastBeat else { continue }
                lastBeat = n.beat
                let bar = n.beat % max(1, beatsPerBar) == 0
                let bx = x(n.time) - 9
                let y0: CGFloat = bar ? 18 : 24
                ctx.fill(Path(CGRect(x: bx - 0.5, y: y0, width: 1, height: stringY(strings) - y0)),
                         with: .color(bar ? Theme.faint.opacity(0.6) : Theme.line))
            }

            // The hit line: the calibration line, 2 px in the accent, the whole height.
            ctx.fill(Path(CGRect(x: hitX - 1, y: 0, width: 2, height: size.height)), with: .color(Theme.accent))

            for (i, n) in notes.enumerated() where n.time > now - past - 0.1 && n.time < now + ahead + 0.1 {
                let nx = x(n.time)
                let state = i < states.count ? states[i] : .waiting
                let colour: Color
                switch state {
                case .waiting: colour = n.time < now ? Theme.faint : Theme.text
                case .tight: colour = Theme.accent
                case .close: colour = Theme.accent.opacity(0.6)
                case .loose: colour = Theme.warn
                case .missed, .wrong: colour = Theme.danger
                }

                let h: CGFloat = n.accent ? 22 : 14
                ctx.fill(Path(roundedRect: CGRect(x: nx - 1.5, y: rhythmY - h / 2, width: 3, height: h), cornerRadius: 1.5),
                         with: .color(state == .waiting ? Theme.faint : colour))
                if let p = n.pick {
                    ctx.draw(Text(p == .down ? "\u{2193}" : "\u{2191}").font(.caption2).foregroundColor(Theme.muted), at: CGPoint(x: nx, y: arrowY))
                }

                // The note on its string: its fret, or × when any pitch counts. A right-hand drill names no string:
                // its × sits on the middle string.
                let y = stringY(n.string ?? (strings + 1) / 2)
                let label = n.pitch == nil ? "\u{00D7}" : "\(max(0, n.fret ?? 0))"
                let w: CGFloat = label.count > 1 ? 22 : 16
                ctx.fill(Path(roundedRect: CGRect(x: nx - w / 2, y: y - 9, width: w, height: 18), cornerRadius: 4), with: .color(Theme.bg))
                if state == .wrong {
                    ctx.stroke(Path(roundedRect: CGRect(x: nx - 10, y: y - 10, width: 20, height: 20), cornerRadius: 4),
                               with: .color(Theme.danger), lineWidth: 1)
                    if let m = heard[i] {
                        ctx.draw(Text(Tuning.noteName(Int(m.rounded()))).font(.footnote).foregroundColor(Theme.danger),
                                 at: CGPoint(x: nx, y: bottom + 10))
                    }
                }
                ctx.draw(Text(label).font(glyph).foregroundColor(colour), at: CGPoint(x: nx, y: y))
            }

            for o in played where o.time > now - past - 0.1 && o.time < now + 0.2 {
                ctx.fill(Path(ellipseIn: CGRect(x: x(o.time) - 2.5, y: dotY - 2.5, width: 5, height: 5)), with: .color(Theme.muted))
            }

            // The strings' names, in the tuning, high string on top.
            ctx.fill(Path(CGRect(x: 0, y: 0, width: 18, height: size.height)), with: .color(Theme.bg))
            for s in 1...strings {
                ctx.draw(Text(tuning.stringName(s)).font(.caption2).foregroundColor(Theme.faint), at: CGPoint(x: 8, y: stringY(s)))
            }
        }
        .overlay(alignment: .top) { Hairline() }
        .overlay(alignment: .bottom) { Hairline() }
        .accessibilityHidden(true)
    }
}

/// A drill's pattern at a glance: one cell a beat, a tick for each note in it, taller where it is accented.
struct PatternStrip: View {
    let exercise: Exercise

    var body: some View {
        let sizes = RunBuilder.groupSizes(exercise)
        Canvas { ctx, size in
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
                    let x = CGFloat(pos) * cell + cell * 0.08 + 1
                    let h: CGFloat = n.accent ? size.height - 8 : size.height * 0.45
                    let rect = CGRect(x: x, y: (size.height - h) / 2, width: 2, height: h)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(n.accent ? Theme.accent : Theme.muted))
                }
            }
        }
        .frame(minHeight: 28)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.columnPattern)
        .accessibilityValue(sizes.map { $0 == 0 ? L.rest : "\($0)" }.joined(separator: ", ") + " " + L.notesPerBeat)
    }
}
