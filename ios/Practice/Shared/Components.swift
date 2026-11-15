import SwiftUI

// The components every screen is built from (the tokens are in Theme.swift). Quiet chrome, hairlines instead of
// boxes, one accent, one primary button per screen.

/// A 1 point line between rows.
struct Hairline: View {
    var body: some View { Rectangle().fill(Theme.line).frame(height: 1).accessibilityHidden(true) }
}

/// A section's label: small capitals in the muted colour.
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(Typo.label)
            .tracking(0.8)
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The one primary action of a screen.
struct PrimaryButton: View {
    let title: String
    var systemImage: String?
    let action: () -> Void
    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: Space.xs) {
                if let systemImage { Image(systemName: systemImage).imageScale(.medium) }
                Text(title).lineLimit(1).minimumScaleFactor(0.8)
            }
            .font(Typo.button)
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, Space.md)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .foregroundStyle(Theme.onAccent)
            .contentShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
        .buttonStyle(PressStyle())
    }
}

/// A quiet button: no border, a soft fill.
struct QuietButton: View {
    let title: String
    var systemImage: String?
    var height: CGFloat = 54
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.xs) {
                if let systemImage { Image(systemName: systemImage).imageScale(.medium) }
                if !title.isEmpty { Text(title).lineLimit(1).minimumScaleFactor(0.8) }
            }
            .font(Typo.bodyStrong)
            .frame(maxWidth: .infinity, minHeight: height)
            .padding(.horizontal, Space.sm)
            .background(Theme.hover, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .foregroundStyle(Theme.text)
            .contentShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
        .buttonStyle(PressStyle())
    }
}

/// A text button with no fill, for the least important action of a screen.
struct TextButton: View {
    let title: String
    var colour: Color = Theme.muted
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(Typo.sub).foregroundStyle(colour)
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
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A round icon button with a soft fill. `repeats` keeps stepping while it is held.
struct IconButton: View {
    let systemImage: String
    var size: CGFloat = Space.touch
    var label: String = ""
    var repeats = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.38, weight: .medium))
                .frame(width: size, height: size)
                .background(Theme.hover, in: Circle())
                .foregroundStyle(Theme.text)
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .buttonRepeatBehavior(repeats ? .enabled : .disabled)
        .accessibilityLabel(label.isEmpty ? systemImage : label)
    }
}

/// A line icon in the bar at the top of a screen: no fill, the muted colour.
struct BarIcon: View {
    let systemImage: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Theme.muted)
                .frame(width: Space.touch, height: Space.touch)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }
}

/// One row: a label on the left, the control on the right, at least 44 points high, a hairline under it.
struct Row<Content: View>: View {
    let label: String
    var detail: String? = nil
    var divider = true
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(Typo.body).foregroundStyle(Theme.text)
                    if let detail {
                        Text(detail).font(Typo.foot).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: Space.sm)
                content
            }
            .padding(.vertical, Space.xs)
            .frame(minHeight: 52)
            if divider { Hairline() }
        }
    }
}

/// A row whose value steps down and up: "Cycles   −  8  +". Holding a button keeps stepping. VoiceOver reads it as
/// one adjustable value.
struct StepperRow: View {
    let label: String
    var detail: String? = nil
    let value: String
    var canDecrement = true
    var canIncrement = true
    var divider = true
    let onStep: (Int) -> Void

    var body: some View {
        Row(label: label, detail: detail, divider: divider) {
            HStack(spacing: Space.xxs) {
                step("minus", -1, enabled: canDecrement)
                Text(value)
                    .font(Typo.figure(.body, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .frame(minWidth: 64)
                step("plus", 1, enabled: canIncrement)
            }
        }
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if canIncrement { onStep(1) }
            case .decrement: if canDecrement { onStep(-1) }
            @unknown default: break
            }
        }
    }

    private func step(_ image: String, _ by: Int, enabled: Bool) -> some View {
        Button { onStep(by) } label: {
            Image(systemName: image)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(Theme.hover, in: Circle())
                .foregroundStyle(enabled ? Theme.text : Theme.faint)
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .buttonRepeatBehavior(.enabled)
        .disabled(!enabled)
    }
}

/// A row with a switch.
struct ToggleRow: View {
    let label: String
    var detail: String? = nil
    var divider = true
    @Binding var isOn: Bool
    var body: some View {
        Row(label: label, detail: detail, divider: divider) {
            Toggle(label, isOn: $isOn).labelsHidden().tint(Theme.accent)
        }
    }
}

/// Segmented choice: one track, the chosen segment lifted, no lines between segments.
struct Segmented<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                let value = options[i].0
                let title = options[i].1
                let on = selection == value
                Button {
                    if selection != value { selection = value }
                } label: {
                    Text(title)
                        .font(on ? Typo.subStrong : Typo.sub)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(on ? Theme.raised : Color.clear, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).stroke(on ? Theme.lineStrong : Color.clear, lineWidth: 1))
                        .foregroundStyle(on ? Theme.text : Theme.muted)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(Theme.hover, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// A small capsule that names a state ("Solo · Z3 Tempo").
struct Chip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Typo.subStrong)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, Space.sm)
            .frame(minHeight: 28)
            .background(Theme.accentSoft, in: Capsule())
            .foregroundStyle(Theme.accentText)
    }
}

/// A number with a small label under it, to be read at a glance.
struct BigStat: View {
    let value: String
    let label: String
    var colour: Color = Theme.text
    var size: CGFloat = 44
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(Typo.number(size))
                .foregroundStyle(colour)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(label).font(Typo.foot).foregroundStyle(Theme.muted).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

/// A thin bar that fills from the left.
struct ProgressLine: View {
    let fraction: Double
    var colour: Color = Theme.accent
    var height: CGFloat = 4
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.line)
                Capsule().fill(colour).frame(width: g.size.width * CGFloat(min(1, max(0, fraction))))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// The beats of the bar as dots; the one playing is lit.
struct BeatDots: View {
    let beats: Int
    let current: Int
    var body: some View {
        HStack(spacing: Space.sm) {
            ForEach(0..<max(1, beats), id: \.self) { i in
                Circle()
                    .fill(i == current ? Theme.accent : Theme.lineStrong)
                    .frame(width: i == 0 ? 14 : 10, height: i == 0 ? 14 : 10)
                    .animation(.easeOut(duration: 0.06), value: current)
            }
        }
        .frame(height: 16)
        .accessibilityHidden(true)
    }
}

/// The tempo, big, with a minus and a plus. Drag on the number to scrub it (sideways, and up and down too where the
/// screen does not scroll); each step ticks. Holding the minus or the plus keeps stepping. The value is never set
/// here: every change goes out through `onChange`, and the owner clamps it (setting a tempo inside its own change
/// handler is what crashed 0.1.4).
struct TempoDial: View {
    let value: Int
    var caption: String = L.bpm
    var size: CGFloat = 96
    var step: Int = 1
    /// Off inside a scrolling screen, where an up and down drag belongs to the scroll.
    var vertical = true
    let onChange: (Int) -> Void
    @State private var dragStart: Int?

    var body: some View {
        HStack(spacing: Space.md) {
            IconButton(systemImage: "minus", size: 52, label: L.slower, repeats: true) { onChange(value - step) }
            VStack(spacing: 0) {
                Text("\(value)")
                    .font(Typo.number(size))
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(caption)
                    .font(Typo.foot)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(scrub)
            IconButton(systemImage: "plus", size: 52, label: L.faster, repeats: true) { onChange(value + step) }
        }
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.tempo)
        .accessibilityValue(L.beatsPerMinute(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
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
                let travel = vertical ? g.translation.width - g.translation.height : g.translation.width
                let target = (dragStart ?? value) + Int((travel / 5).rounded())
                if target != value { onChange(target) }
            }
            .onEnded { _ in dragStart = nil }
    }
}

/// The top of a tab's screen: its name, the Update capsule when there is one, the screen's own icons, Settings.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    let trailing: Trailing
    @EnvironmentObject var updater: Updater
    @State private var settings = false

    init(title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(title).font(Typo.screen).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Space.xs)
            if updater.available != nil {
                Button { updater.install() } label: {
                    Text(L.update).font(Typo.subStrong)
                        .padding(.horizontal, Space.sm).frame(height: 30)
                        .background(Theme.accent, in: Capsule()).foregroundStyle(Theme.onAccent)
                }
                .buttonStyle(PressStyle())
                .padding(.trailing, Space.xxs)
            }
            trailing
            BarIcon(systemImage: "gearshape", label: L.settings) { settings = true }
        }
        .padding(.leading, Space.page)
        .padding(.trailing, Space.xs)
        .frame(minHeight: 56)
        .sheet(isPresented: $settings) { SettingsView() }
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String) { self.init(title: title) { EmptyView() } }
}

/// The top of a pushed screen: back, its name, its own icons.
struct NavBar<Trailing: View>: View {
    let title: String
    var backEnabled = true
    let onBack: () -> Void
    let trailing: Trailing

    init(title: String, backEnabled: Bool = true, onBack: @escaping () -> Void, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.backEnabled = backEnabled
        self.onBack = onBack
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .frame(width: Space.touch, height: Space.touch)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .opacity(backEnabled ? 1 : 0.3)
            .disabled(!backEnabled)
            .accessibilityLabel(L.back)
            Text(title).font(Typo.title).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.75)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Space.xs)
            trailing
        }
        .padding(.horizontal, Space.xs)
        .frame(minHeight: 52)
    }
}

extension NavBar where Trailing == EmptyView {
    init(title: String, backEnabled: Bool = true, onBack: @escaping () -> Void) {
        self.init(title: title, backEnabled: backEnabled, onBack: onBack) { EmptyView() }
    }
}

/// A group of rows that stays folded until it is asked for: "Options   Ladder off, click on  ⌄".
struct Disclosure<Content: View>: View {
    let title: String
    var summary: String = ""
    @Binding var open: Bool
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) { open.toggle() }
            } label: {
                HStack(spacing: Space.sm) {
                    Text(title).font(Typo.body).foregroundStyle(Theme.text)
                    Spacer(minLength: Space.sm)
                    if !open && !summary.isEmpty {
                        Text(summary).font(Typo.sub).foregroundStyle(Theme.muted).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.faint)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel(title)
            .accessibilityValue(summary)
            Hairline()
            if open { content }
        }
    }
}
