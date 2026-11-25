import SwiftUI

// What every screen is built from (0.3.0). Forms and lists are the system's own (Form, List, LabeledContent,
// Toggle, Stepper, Picker as a navigation list), so setup reads as an iPhone app; the pieces below are the few the
// system has no part for: the transport buttons, the tempo block, the beat bar, the accuracy meter, the step line.

/// A 1 point line between rows.
struct Hairline: View {
    var body: some View { Rectangle().fill(Theme.line).frame(height: 1).accessibilityHidden(true) }
}

/// The one primary action of a screen: accent fill, 48 high, full width, at the bottom.
struct PrimaryButton: View {
    let title: String
    var systemImage: String?
    var enabled = true
    let action: () -> Void
    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: Space.xs) {
                if let systemImage { Image(systemName: systemImage).font(.system(size: 15, weight: .semibold)) }
                Text(title).lineLimit(1)
            }
            .font(Typo.button)
            .frame(maxWidth: .infinity, minHeight: Control.primary)
            .background(enabled ? Theme.accent : Theme.lineStrong, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .foregroundStyle(enabled ? Theme.onAccent : Theme.muted)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
    }
}

/// A quiet button: a soft fill, no border, 48 high.
struct QuietButton: View {
    let title: String
    var systemImage: String?
    var colour: Color = Theme.text
    let action: () -> Void
    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: Space.xs) {
                if let systemImage { Image(systemName: systemImage).font(.system(size: 17, weight: .regular)) }
                if !title.isEmpty { Text(title).lineLimit(1) }
            }
            .font(Typo.body)
            .frame(maxWidth: .infinity, minHeight: Control.primary)
            .background(Theme.hover, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .foregroundStyle(colour)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }
}

/// A text button: no fill, for the least of a screen's actions.
struct TextButton: View {
    let title: String
    var colour: Color = Theme.muted
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(Typo.body).foregroundStyle(colour)
                .frame(minHeight: Space.touch)
                .padding(.horizontal, Space.xs)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }
}

/// A pressed control dims a little and comes back.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// An icon button: a 20 point line symbol in a 44 point box, no fill. `repeats` keeps stepping while held.
struct IconButton: View {
    let systemImage: String
    var label: String = ""
    var repeats = false
    var colour: Color = Theme.text
    var size: CGFloat = 20
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(colour)
                .frame(width: Space.touch, height: Space.touch)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .buttonRepeatBehavior(repeats ? .enabled : .disabled)
        .accessibilityLabel(label.isEmpty ? systemImage : label)
    }
}

/// The settings gear, in the same place on every tab.
struct SettingsButton: View {
    @State private var open = false
    var body: some View {
        Button { open = true } label: { Image(systemName: "gearshape") }
            .accessibilityLabel(L.settings)
            .accessibilityIdentifier("settings")
            .sheet(isPresented: $open) { SettingsView() }
    }
}

/// The beats of the bar as equal segments across the width; the one playing is lit, the accented one is taller.
/// It lights with no animation, so it is on the click.
struct BeatBar: View {
    let beats: Int
    let current: Int
    var accented: Int = 0
    var body: some View {
        HStack(alignment: .center, spacing: Space.xxs) {
            ForEach(0..<max(1, beats), id: \.self) { i in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(i == current ? Theme.accent : Theme.lineStrong)
                    .frame(height: i == accented ? 10 : 6)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

/// A thin line that fills from the left.
struct ProgressLine: View {
    let fraction: Double
    var colour: Color = Theme.accent
    var track: Color = Theme.lineStrong
    var height: CGFloat = 4
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(track)
                RoundedRectangle(cornerRadius: 2).fill(colour)
                    .frame(width: g.size.width * CGFloat(min(1, max(0, fraction))))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// The tempo, big, left-aligned, with "bpm" on its baseline and minus and plus at the right. Drag sideways on the
/// number to scrub it. Every change goes out through `onChange`; the owner keeps it in range.
struct TempoBlock: View {
    let value: Int
    var font: Font = Typo.tempoHero
    var muted = false
    var step = 1
    let onChange: (Int) -> Void
    @State private var dragStart: Int?

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: Space.tiny) {
                Text("\(value)")
                    .font(font)
                    .foregroundStyle(muted ? Theme.muted : Theme.text)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(L.bpm).font(Typo.body).foregroundStyle(Theme.muted)
            }
            .contentShape(Rectangle())
            .gesture(scrub)
            Spacer(minLength: Space.xs)
            IconButton(systemImage: "minus", label: L.slower, repeats: true) { onChange(value - step) }
                .accessibilityIdentifier("tempo.minus")
            IconButton(systemImage: "plus", label: L.faster, repeats: true) { onChange(value + step) }
                .accessibilityIdentifier("tempo.plus")
        }
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.tempo)
        .accessibilityValue(L.beatsPerMinute(value))
        .accessibilityAdjustableAction { d in
            switch d {
            case .increment: onChange(value + step)
            case .decrement: onChange(value - step)
            @unknown default: break
            }
        }
    }

    private var scrub: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { g in
                if dragStart == nil { dragStart = value }
                let target = (dragStart ?? value) + Int((g.translation.width / 6).rounded())
                if target != value { onChange(target) }
            }
            .onEnded { _ in dragStart = nil }
    }
}

/// The accuracy meter: one bar, 12 high, from 50% at the left to 100% at the right, its background the bands split
/// at the thresholds (break, down, hold, up; or under and over the pass mark), and a mark at the accuracy now.
struct AccuracyMeter: View {
    /// 0 to 1, nil before a loop is judged.
    let accuracy: Double?
    /// The thresholds, in percent, low to high: [break, down, up], or [pass mark].
    let lines: [Int]
    let zone: TempoPlan.Zone?
    /// Whether the plan has zones (By accuracy); otherwise two bands and no zone word.
    var zoned = true

    private func x(_ pct: Double, _ w: CGFloat) -> CGFloat { w * CGFloat(min(1, max(0, (pct - 50) / 50))) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.tiny) {
            HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                Text(L.accuracy).font(Typo.foot).foregroundStyle(Theme.muted)
                Spacer(minLength: Space.xs)
                Text(accuracy.map { L.percent(Int(($0 * 100).rounded())) } ?? "–").font(Typo.stat).foregroundStyle(Theme.text)
                if zoned, let zone, accuracy != nil {
                    Text(L.zoneWord(zone)).font(Typo.subStrong).foregroundStyle(Theme.zoneMark(zone))
                        .frame(minWidth: 44, alignment: .leading)
                }
            }
            GeometryReader { g in
                let w = g.size.width
                let bands = bandEdges
                ZStack(alignment: .leading) {
                    ForEach(bands.indices, id: \.self) { i in
                        let b = bands[i]
                        Rectangle().fill(Theme.zone(b.zone).opacity(0.22))
                            .frame(width: max(0, x(b.hi, w) - x(b.lo, w)))
                            .offset(x: x(b.lo, w))
                    }
                    if let a = accuracy {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(zone.map(Theme.zoneMark) ?? Theme.text)
                            .frame(width: 3, height: 20)
                            .offset(x: max(0, min(w - 3, x(a * 100, w) - 1.5)))
                            .animation(.easeOut(duration: 0.12), value: a)
                    }
                }
                .frame(height: 20)
            }
            .frame(height: 20)
            .clipShape(RoundedRectangle(cornerRadius: 2))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.accuracy)
        .accessibilityValue(accuracy.map { L.percent(Int(($0 * 100).rounded())) } ?? L.none)
    }

    private struct Band { var lo: Double; var hi: Double; var zone: TempoPlan.Zone }

    private var bandEdges: [Band] {
        let l = lines.map(Double.init)
        if !zoned || l.count == 1 {
            let p = l.first ?? 85
            return [Band(lo: 0, hi: p, zone: .hold), Band(lo: p, hi: 100, zone: .up)]
        }
        // [break, down, up], [down, up] or [break, up]
        var out: [Band] = []
        var lo = 0.0
        let zones: [TempoPlan.Zone] = l.count == 3 ? [.rest, .down, .hold] : [.down, .hold]
        for (i, edge) in l.dropLast().enumerated() {
            out.append(Band(lo: lo, hi: edge, zone: zones[i]))
            lo = edge
        }
        out.append(Band(lo: lo, hi: l.last!, zone: .hold))
        out.append(Band(lo: l.last!, hi: 100, zone: .up))
        return out
    }
}

/// Where the tempo is going next: a caption line and a thin line filling toward the next step.
struct StepProgress: View {
    let info: PlayAlong.StepInfo
    var body: some View {
        VStack(alignment: .leading, spacing: Space.tiny) {
            HStack {
                Text(L.stepState(info.state)).font(Typo.foot).foregroundStyle(Theme.muted)
                Spacer()
                Text(info.measure).font(Typo.figure(.footnote)).foregroundStyle(Theme.muted)
            }
            ProgressLine(fraction: info.state == .top ? 1 : info.fraction, colour: colour)
        }
        .accessibilityElement(children: .combine)
    }
    private var colour: Color {
        switch info.state {
        case .down: return Theme.warn
        case .rest: return Theme.danger
        default: return Theme.accent
        }
    }
}

/// A table's column heads: small, faint, one line, 28 high.
struct ColumnHeads: View {
    let first: String
    let columns: [(String, CGFloat)]
    var body: some View {
        HStack(spacing: Space.xs) {
            Text(first).frame(maxWidth: .infinity, alignment: .leading)
            ForEach(columns.indices, id: \.self) { i in
                Text(columns[i].0).frame(width: columns[i].1, alignment: .trailing)
            }
        }
        .font(Typo.foot)
        .foregroundStyle(Theme.faint)
        .lineLimit(1)
        .frame(height: 28)
        .padding(.horizontal, Space.page)
        .accessibilityHidden(true)
    }
}

/// One row of a table: the name takes what is left, the values are fixed, right-aligned, in monospaced digits.
struct TableRow: View {
    let name: String
    var detail: String? = nil
    let values: [(String, CGFloat)]
    var faintValues = false
    var body: some View {
        HStack(spacing: Space.xs) {
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(Typo.body).foregroundStyle(Theme.text).lineLimit(1).truncationMode(.tail)
                if let detail { Text(detail).font(Typo.foot).foregroundStyle(Theme.faint).lineLimit(1) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(values.indices, id: \.self) { i in
                Text(values[i].0).font(Typo.figure(.body))
                    .foregroundStyle(i == 0 && !faintValues ? Theme.text : Theme.muted)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .frame(width: values[i].1, alignment: .trailing)
            }
        }
        .padding(.horizontal, Space.page)
        .frame(minHeight: Control.row)
        .contentShape(Rectangle())
    }
}

/// A list of choices with a checkmark on the chosen one, pushed from a value row.
struct ChoiceList<T: Hashable>: View {
    let title: String
    let options: [(T, String, String?)]
    @Binding var selection: T
    var footer: String? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                ForEach(options.indices, id: \.self) { i in
                    let o = options[i]
                    Button {
                        Haptics.tick()
                        selection = o.0
                        dismiss()
                    } label: {
                        HStack {
                            Text(o.1).foregroundStyle(Theme.text)
                            Spacer()
                            if let v = o.2 { Text(v).font(Typo.figure(.body)).foregroundStyle(Theme.muted) }
                            if selection == o.0 {
                                Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accentText)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .accessibilityAddTraits(selection == o.0 ? [.isSelected] : [])
                }
            } footer: { if let footer { Text(footer) } }
        }
        .houseForm()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension View {
    /// A system Form in the house colours: groups on `side`, rows on `raised`.
    func houseForm() -> some View {
        self.scrollContentBackground(.hidden)
            .background(Theme.side.ignoresSafeArea())
            .tint(Theme.accentText)
    }
}

/// A quiet bar under the title when something is playing on another tab, with Stop.
struct RunningBar: View {
    @EnvironmentObject var player: Player
    @EnvironmentObject var pa: PlayAlong
    @EnvironmentObject var runner: RoutineRunner
    /// The mode this screen makes itself; its own sound needs no bar.
    var own: Player.Mode = .idle

    private var drill: Bool { pa.runSetup == nil && (player.mode == .playAlong || pa.phase == .paused || pa.phase == .resting) }
    private var shows: Bool {
        if runner.active { return true }
        if drill { return own != .playAlong }
        return player.mode == .metronome && own != .metronome
    }

    var body: some View {
        if shows {
            HStack(spacing: Space.sm) {
                Circle().fill(Theme.accent).frame(width: 6, height: 6).accessibilityHidden(true)
                Text(text).font(Typo.sub).foregroundStyle(Theme.text).lineLimit(1)
                Spacer(minLength: Space.xs)
                if !runner.active {
                    Button {
                        Haptics.tap()
                        pa.leave()
                        player.stop()
                    } label: { Text(L.stop).font(Typo.subStrong).foregroundStyle(Theme.accentText).frame(minHeight: Space.touch) }
                    .accessibilityIdentifier("running.stop")
                }
            }
            .padding(.horizontal, Space.page)
            .frame(minHeight: Space.touch)
            .background(Theme.accentSoft)
        }
    }

    private var text: String {
        if runner.active { return L.routineRunning }
        if drill { return pa.phase == .paused ? L.drillPaused : L.drillRunning }
        return L.metronomeAt(player.bpm)
    }
}
