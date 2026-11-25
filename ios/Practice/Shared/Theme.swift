import SwiftUI
import UIKit

// The design system (HQ/agent/app-design.md, the house style), as redrawn for 0.3.0 (Joe, 2026-11-24: "Can we
// completely overhaul and modernize the UI? The premise is great but it looks a little AI slop now"). The design
// pass is in the repo's docs/design-0.3.md. Colour tokens for dark and light, one spacing scale, one small family of
// radii, the system font in its default design with monospaced digits for every number (the rounded design was the
// main thing that read as generated), and haptics. Components are in Components.swift; nothing is a one-off.

/// Colour tokens. Light and dark from the same names.
enum Theme {
    static func ui(_ light: UInt32, _ dark: UInt32) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) }
    }
    static func dyn(_ light: UInt32, _ dark: UInt32) -> Color { Color(ui(light, dark)) }
    static func dynA(_ light: UIColor, _ dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    /// Flat screens: Metronome, Run, the runner, tables, Result.
    static let bg = dyn(0xFFFFFF, 0x1C1C1B)
    /// Behind groups: setup, editors, Settings, choice lists.
    static let side = dyn(0xF7F7F5, 0x161615)
    /// A group, a sheet, the lifted segment.
    static let raised = dyn(0xFFFFFF, 0x262625)
    static let text = dyn(0x1C1B19, 0xE4E3DF)
    static let muted = dyn(0x6A6964, 0xA3A29C)
    /// Chevrons, column heads, glyphs only; never body text.
    static let faint = dyn(0xA09F99, 0x6B6A65)
    static let line = dyn(0xEBEAE6, 0x2B2B29)
    /// Tracks, unlit beat segments, the lane's strings.
    static let lineStrong = dyn(0xDCDBD6, 0x3B3B38)
    /// A quiet button's fill.
    static let hover = dynA(UIColor(red: 55 / 255, green: 53 / 255, blue: 47 / 255, alpha: 0.055),
                            UIColor(red: 1, green: 1, blue: 250 / 255, alpha: 0.055))
    /// Pressed; the segmented track.
    static let active = dynA(UIColor(red: 55 / 255, green: 53 / 255, blue: 47 / 255, alpha: 0.09),
                             UIColor(red: 1, green: 1, blue: 250 / 255, alpha: 0.09))
    /// The one accent, as a fill: the primary button, the lit beat, a switch, the meter's mark in the up zone.
    static let accent = Color(UIColor(hex: 0x6FB7A0))
    /// The accent as text or a glyph (darker in light, so it reads on white at 4.5:1).
    static let accentText = dyn(0x2F7F69, 0x7CC4AD)
    static let onAccent = Color(UIColor(hex: 0x10201B))
    static let accentSoft = Color(UIColor(hex: 0x6FB7A0)).opacity(0.14)
    static let warn = dyn(0xA9781C, 0xD9A441)
    static let danger = dyn(0xC4402B, 0xE8796B)

    static let uiBg = ui(0xFFFFFF, 0x1C1C1B)
    static let uiSide = ui(0xF7F7F5, 0x161615)
    static let uiLine = ui(0xEBEAE6, 0x2B2B29)
    static let uiMuted = ui(0x6A6964, 0xA3A29C)
    static let uiAccentText = ui(0x2F7F69, 0x7CC4AD)

    /// The four zones of the accuracy meter: up, hold, down, break.
    static func zone(_ z: TempoPlan.Zone) -> Color {
        switch z {
        case .up: return accent
        case .hold: return lineStrong
        case .down: return warn
        case .rest: return danger
        }
    }
    /// The zone's mark and word: hold is drawn in the text colour.
    static func zoneMark(_ z: TempoPlan.Zone) -> Color { z == .hold ? text : zone(z) }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// The spacing scale: 2, 4, 6, 8, 12, 16, 24, 32. Paddings and gaps come from here only.
enum Space {
    static let hair: CGFloat = 2
    static let xxs: CGFloat = 4
    static let tiny: CGFloat = 6
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    /// The side margin of every screen.
    static let page: CGFloat = 16
    /// The smallest height of anything tapped.
    static let touch: CGFloat = 44
}

/// One small family of radii (Joe, 2026-11-14: "not a fan of how big and rounded many elements are"): 4 for a
/// segment or a tag, 6 for a button or a field, 10 for a group or a sheet. Nothing is a capsule.
enum Radius {
    static let sm: CGFloat = 4
    static let md: CGFloat = 6
    static let lg: CGFloat = 10
}

enum Control {
    /// A row of a list or a setting.
    static let row: CGFloat = 44
    /// The primary button, full width at the bottom of a screen.
    static let primary: CGFloat = 48
    static let height: CGFloat = 48
    static let square: CGFloat = 32
}

/// The type ramp: the system font, default design, two weights; numbers in monospaced digits. Fixed sizes only for
/// the four big numerals; everything else follows Dynamic Type.
enum Typo {
    static let body = Font.body
    static let bodyStrong = Font.body.weight(.semibold)
    static let callout = Font.callout
    static let sub = Font.subheadline
    static let subStrong = Font.subheadline.weight(.semibold)
    static let foot = Font.footnote
    static let caption = Font.caption
    static let button = Font.body.weight(.semibold)
    /// The pattern now, a block's name.
    static let cue = Font.title3.weight(.semibold)
    /// Accuracy on the run screen, time left.
    static let stat = Font.title2.weight(.semibold).monospacedDigit()
    static let title = Font.headline

    /// The Metronome's tempo, countdowns and the break: 88.
    static let tempoHero = Font.system(size: 88, weight: .regular).monospacedDigit()
    /// The run screen's tempo: 64.
    static let tempoRun = Font.system(size: 64, weight: .regular).monospacedDigit()
    /// The drill setup's tempo: 44.
    static let tempoSetup = Font.system(size: 44, weight: .regular).monospacedDigit()
    /// The result's number: 44, semibold.
    static let statLarge = Font.system(size: 44, weight: .semibold).monospacedDigit()

    /// A number inside a line of text, in the text's own size.
    static func figure(_ style: Font.TextStyle = .body, weight: Font.Weight = .regular) -> Font {
        Font.system(style).weight(weight).monospacedDigit()
    }
}

/// Haptics, one per kind of event (the design pass's table). None on beats: it would fight the click and the pick.
@MainActor
enum Haptics {
    private static let selection = UISelectionFeedbackGenerator()
    private static let impact = UIImpactFeedbackGenerator(style: .medium)
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let softImpact = UIImpactFeedbackGenerator(style: .soft)
    private static let notify = UINotificationFeedbackGenerator()

    /// A step of a value, a pick from a list.
    static func tick() { selection.selectionChanged() }
    /// Start, Pause, Resume, Stop, Skip, Back.
    static func tap() { impact.impactOccurred() }
    /// Tap tempo.
    static func tapTempo() { light.impactOccurred() }
    /// 3, 2, 1.
    static func count() { rigid.impactOccurred() }
    /// A block ends, a break begins.
    static func soft() { softImpact.impactOccurred() }
    static func done() { notify.notificationOccurred(.success) }
    static func warning() { notify.notificationOccurred(.warning) }
}

let subdivisionOptions: [(Int, String)] = [(1, "Quarter"), (2, "Eighth"), (3, "Triplet"), (4, "16th")]
let meterOptions: [Int] = [2, 3, 4, 5, 6, 7]

/// "12 min" or "1 h 20 min" for the minutes kept.
func formatMinutes(_ seconds: Double) -> String {
    let m = Int((seconds / 60).rounded())
    if m < 1 { return "under a minute" }
    if m < 60 { return "\(m) min" }
    return m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60) min"
}
