import SwiftUI

/// The calibration, in two steps, the way a rhythm game does it (Joe, 2026-11-14: "there's a visual component that
/// needs to line up with the audible component plus the guitar pluck. Like the line passing through the center of
/// the screen").
///
/// 1. Display Sync. A click plays and marks scroll across a line in the middle of the screen. The slider moves
///    the marks until each one crosses the line exactly on the click he hears, through whatever the sound is coming
///    out of. That is the display offset for this output: the lane of a run is drawn that much later.
/// 2. Input. The same marks; he plays one note as each crosses the line. The median of what is heard is the
///    offset every pick is scored with on this setup, and the spread says how steady it was.
struct CalibrationView: View {
    @EnvironmentObject var pa: PlayAlong

    private var syncing: Bool { pa.phase == .syncing }
    private var offsetMs: Int { Int((pa.displayOffset * 1000).rounded()) }
    private var heard: Int { pa.errors.compactMap { $0 }.count }

    var body: some View {
        VStack(spacing: 0) {
            Chip(text: L.calibrationStep(syncing ? 1 : 2))
                .padding(.top, Space.sm)
            Text(syncing ? L.displaySync : L.inputSync)
                .font(Typo.screen).foregroundStyle(Theme.text)
                .padding(.top, Space.md)
            Text(syncing ? L.displaySyncHelp : L.inputSyncHelp)
                .font(Typo.callout).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.xs)
                .padding(.horizontal, Space.md)

            Spacer(minLength: Space.md)

            SyncLane(times: pa.notes.map(\.time), played: syncing ? [] : pa.played.map(\.time), now: pa.laneNow)
                .frame(height: 168)

            Spacer(minLength: Space.md)

            if syncing { sightControls } else { guitarReadout }
        }
        .padding(.horizontal, Space.page)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg.ignoresSafeArea())
    }

    private var sightControls: some View {
        VStack(spacing: 0) {
            Text(L.signedMs(offsetMs))
                .font(Typo.number(28)).foregroundStyle(Theme.text)
                .contentTransition(.numericText())
                .accessibilityHidden(true)
            HStack(spacing: Space.sm) {
                IconButton(systemImage: "minus", label: L.earlier, repeats: true) {
                    pa.setDisplayOffset(pa.displayOffset - 0.005)
                }
                Slider(value: Binding(get: { pa.displayOffset * 1000 },
                                      set: { pa.setDisplayOffset(($0 / 5).rounded() * 5 / 1000) }),
                       in: (DisplayOffsetStore.range.lowerBound * 1000)...(DisplayOffsetStore.range.upperBound * 1000))
                    .tint(Theme.accent)
                    .accessibilityLabel(L.displayOffset)
                    .accessibilityValue(L.milliseconds(offsetMs))
                    .accessibilityIdentifier("calibration.slider")
                IconButton(systemImage: "plus", label: L.later, repeats: true) {
                    pa.setDisplayOffset(pa.displayOffset + 0.005)
                }
            }
            .padding(.top, Space.xs)
            .sensoryFeedback(.selection, trigger: offsetMs)
            HStack(spacing: Space.xs) {
                Text(L.output(pa.route.output)).font(Typo.foot).foregroundStyle(Theme.faint)
                RoutePicker().frame(width: 32, height: 32).accessibilityLabel(L.chooseOutput)
            }
            .padding(.top, Space.xs)

            Spacer(minLength: Space.md)

            PrimaryButton(title: L.next, systemImage: "arrow.right") { pa.calibrateInput() }
                .accessibilityIdentifier("calibration.next")
            TextButton(title: L.done) { pa.stop() }
                .accessibilityIdentifier("calibration.done")
        }
    }

    private var guitarReadout: some View {
        VStack(spacing: 0) {
            BigStat(value: L.ofTotal(heard, PlayAlong.calibrationCount), label: pa.countingIn ? L.countIn : L.notes)
            HStack(spacing: Space.xs) {
                Text(L.input).font(Typo.caption).foregroundStyle(Theme.faint)
                ProgressLine(fraction: inputFraction, height: 3)
            }
            .padding(.top, Space.md)
            Text(L.route(pa.route.input, pa.route.output))
                .font(Typo.foot).foregroundStyle(Theme.faint)
                .multilineTextAlignment(.center)
                .padding(.top, Space.sm)

            Spacer(minLength: Space.md)

            QuietButton(title: L.stop, systemImage: "stop.fill") { pa.stop() }
                .accessibilityIdentifier("calibration.stop")
                .padding(.bottom, Space.md)
        }
    }

    private var inputFraction: Double {
        let db = 20 * log10(Double(max(pa.level, 1e-5)))
        return min(1, max(0, (db + 60) / 60))
    }
}

/// Marks scrolling from the right across a line in the middle. A mark lights as it crosses. Picks show as dots
/// under the marks, so one that came early sits left of its mark when it crosses and a late one right of it.
struct SyncLane: View {
    let times: [Double]
    let played: [Double]
    let now: Double

    private let span = 3.0      // seconds across the whole width

    var body: some View {
        Canvas { ctx, size in
            let mid = size.width / 2
            let pps = size.width / span
            func x(_ t: Double) -> CGFloat { mid + CGFloat(t - now) * pps }
            let y = size.height * 0.42

            for t in times where t > now - span / 2 - 0.1 && t < now + span / 2 + 0.1 {
                let near = abs(t - now) < 0.045
                let h: CGFloat = near ? 72 : 56
                let rect = CGRect(x: x(t) - 4, y: y - h / 2, width: 8, height: h)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(near ? Theme.accent : (t < now ? Theme.lineStrong : Theme.muted)))
            }
            // The line through the middle.
            ctx.fill(Path(roundedRect: CGRect(x: mid - 1.5, y: 4, width: 3, height: size.height - 8), cornerRadius: 1.5), with: .color(Theme.text))

            let dotY = size.height - 18
            for t in played where t > now - span / 2 - 0.1 && t < now + 0.2 {
                ctx.fill(Path(ellipseIn: CGRect(x: x(t) - 4, y: dotY - 4, width: 8, height: 8)), with: .color(Theme.accent))
            }
        }
        .background(Theme.side, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .accessibilityHidden(true)
    }
}
