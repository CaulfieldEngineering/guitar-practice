import SwiftUI

/// The calibration, in two steps, the way a rhythm game does it (Joe, 2026-11-14: "there's a visual component that
/// needs to line up with the audible component plus the guitar pluck. Like the line passing through the center of
/// the screen").
///
/// 1. Line up the marks. A click plays and marks scroll across a line through the middle of the screen; the slider
///    moves the marks until each one crosses the line on the click he hears, through whatever the sound comes out
///    of. That is the display offset for this output: a run's lane is drawn that much later.
/// 2. Play on the line. He plays one note as each mark crosses; the median of what is heard is the offset every pick
///    is scored with on this setup.
struct CalibrationView: View {
    @EnvironmentObject var pa: PlayAlong

    private var syncing: Bool { pa.phase == .syncing }
    private var offsetMs: Int { Int((pa.displayOffset * 1000).rounded()) }
    private var heard: Int { pa.errors.compactMap { $0 }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(L.cancel) { pa.stop() }.foregroundStyle(Theme.accentText).frame(minHeight: Space.touch)
                    .accessibilityIdentifier("calibration.done")
                Spacer()
                Text(L.calibration).font(Typo.title).foregroundStyle(Theme.text)
                Spacer()
                Color.clear.frame(width: 56, height: 1)
            }

            Text(L.stepOf(syncing ? 1 : 2, 2)).font(Typo.foot).foregroundStyle(Theme.muted).padding(.top, Space.md)
            Text(syncing ? L.lineUpMarks : L.playOnTheLine).font(Typo.cue).foregroundStyle(Theme.text).padding(.top, Space.xxs)
            Text(syncing ? L.lineUpHelp : L.playOnLineHelp).font(Typo.sub).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true).padding(.top, Space.xxs)

            Spacer(minLength: Space.md)
            SyncLane(times: pa.notes.map(\.time), played: syncing ? [] : pa.played.map(\.time), now: pa.laneNow)
                .frame(height: 168)
                .padding(.horizontal, -Space.page)
            Spacer(minLength: Space.md)

            if syncing { sightControls } else { guitarReadout }
        }
        .padding(.horizontal, Space.page)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg.ignoresSafeArea())
    }

    private var sightControls: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: 0) {
                Text(L.signedMs(offsetMs)).font(Typo.stat).foregroundStyle(Theme.text)
                    .contentTransition(.numericText()).frame(width: 96, alignment: .leading)
                IconButton(systemImage: "minus", label: L.earlier, repeats: true) { pa.setDisplayOffset(pa.displayOffset - 0.005) }
                Slider(value: Binding(get: { pa.displayOffset * 1000 }, set: { pa.setDisplayOffset(($0 / 5).rounded() * 5 / 1000) }),
                       in: (DisplayOffsetStore.range.lowerBound * 1000)...(DisplayOffsetStore.range.upperBound * 1000))
                    .tint(Theme.accent)
                    .accessibilityLabel(L.displayOffset)
                    .accessibilityValue(L.milliseconds(offsetMs))
                    .accessibilityIdentifier("calibration.slider")
                IconButton(systemImage: "plus", label: L.later, repeats: true) { pa.setDisplayOffset(pa.displayOffset + 0.005) }
            }
            .sensoryFeedback(.selection, trigger: offsetMs)
            HStack(spacing: Space.xs) {
                Text(L.output(pa.route.output)).font(Typo.foot).foregroundStyle(Theme.muted)
                RoutePicker().frame(width: 32, height: 32).accessibilityLabel(L.chooseOutput)
            }
            Spacer(minLength: Space.md)
            PrimaryButton(title: L.next) { pa.calibrateInput() }
                .accessibilityIdentifier("calibration.next")
                .padding(.bottom, Space.sm)
        }
    }

    private var guitarReadout: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            LabeledContent(L.heard) { Text(L.ofTotal(heard, PlayAlong.calibrationCount)).font(Typo.figure(.body)) }
                .frame(minHeight: Control.row)
            ProgressLine(fraction: inputFraction, height: 3)
            Text(L.route(pa.route.input, pa.route.output)).font(Typo.foot).foregroundStyle(Theme.muted)
            if let m = pa.message { Text(m).font(Typo.foot).foregroundStyle(Theme.warn) }
            Spacer(minLength: Space.md)
            QuietButton(title: L.stop, systemImage: "stop.fill") { pa.stop() }
                .accessibilityIdentifier("calibration.stop")
                .padding(.bottom, Space.sm)
        }
    }

    private var inputFraction: Double {
        let db = 20 * log10(Double(max(pa.level, 1e-5)))
        return min(1, max(0, (db + 60) / 60))
    }
}

/// Marks scrolling from the right across a line through the middle. A mark lights as it crosses. Picks show as dots
/// under the marks.
struct SyncLane: View {
    let times: [Double]
    let played: [Double]
    let now: Double
    private let span = 3.0

    var body: some View {
        Canvas { ctx, size in
            let mid = size.width / 2
            let pps = size.width / span
            func x(_ t: Double) -> CGFloat { mid + CGFloat(t - now) * pps }
            let y = size.height * 0.42
            for t in times where t > now - span / 2 - 0.1 && t < now + span / 2 + 0.1 {
                let near = abs(t - now) < 0.045
                let h: CGFloat = near ? 64 : 48
                ctx.fill(Path(roundedRect: CGRect(x: x(t) - 3, y: y - h / 2, width: 6, height: h), cornerRadius: 2),
                         with: .color(near ? Theme.accent : (t < now ? Theme.lineStrong : Theme.muted)))
            }
            ctx.fill(Path(CGRect(x: mid - 1, y: 0, width: 2, height: size.height)), with: .color(Theme.accent))
            let dotY = size.height - 16
            for t in played where t > now - span / 2 - 0.1 && t < now + 0.2 {
                ctx.fill(Path(ellipseIn: CGRect(x: x(t) - 3, y: dotY - 3, width: 6, height: 6)), with: .color(Theme.text))
            }
        }
        .overlay(alignment: .top) { Hairline() }
        .overlay(alignment: .bottom) { Hairline() }
        .accessibilityHidden(true)
    }
}
