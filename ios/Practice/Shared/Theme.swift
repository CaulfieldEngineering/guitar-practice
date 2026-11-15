import SwiftUI
import UIKit

// The design system (HQ/agent/app-design.md, the house style after Blocks): colour tokens for dark and light, one
// spacing scale, one family of corner radii, a type ramp that follows Dynamic Type, and haptics. The components
// built from these are in Components.swift. Every screen takes its values from here; nothing is a one-off.

/// Colour tokens. Dark is the first design; light comes from the same names.
enum Theme {
    static func ui(_ light: UInt32, _ dark: UInt32) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) }
    }
    static func dyn(_ light: UInt32, _ dark: UInt32) -> Color { Color(ui(light, dark)) }

    /// Content.
    static let bg = dyn(0xFFFFFF, 0x1C1C1B)
    /// A quiet surface under a group (the lane, a stat tile).
    static let side = dyn(0xF7F7F5, 0x161615)
    /// What floats or is lifted (the chosen segment).
    static let raised = dyn(0xFFFFFF, 0x2C2C2A)
    static let text = dyn(0x1C1B19, 0xE4E3DF)
    static let muted = dyn(0x6A6964, 0xA3A29C)
    /// Hints and glyphs only.
    static let faint = dyn(0xA09F99, 0x6B6A65)
    static let line = dyn(0xEBEAE6, 0x2B2B29)
    static let lineStrong = dyn(0xDCDBD6, 0x3B3B38)
    /// The fill of a quiet control.
    static let hover = dyn(0xF0F0ED, 0x272726)
    /// The one accent, as a fill (the primary button, the lit beat, a note on the click).
    static let accent = Color(UIColor(hex: 0x6FB7A0))
    /// The accent as text or a glyph: darker in light, so it reads on white.
    static let accentText = dyn(0x2F7F69, 0x7CC4AD)
    static let onAccent = Color(UIColor(hex: 0x0F1F1A))
    static let accentSoft = dyn(0xE3F1EC, 0x24332E)
    static let warn = dyn(0xA9781C, 0xD9A441)
    static let danger = dyn(0xC4402B, 0xE8796B)

    static let uiBg = ui(0xFFFFFF, 0x1C1C1B)
    static let uiLine = ui(0xEBEAE6, 0x2B2B29)
    static let uiMuted = ui(0x6A6964, 0xA3A29C)
    static let uiAccentText = ui(0x2F7F69, 0x7CC4AD)
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// The spacing scale, on a 4 point grid. Paddings and gaps come from here only.
enum Space {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 40
    /// The side margin of every screen.
    static let page: CGFloat = 20
    /// The smallest height of anything tapped.
    static let touch: CGFloat = 44
}

/// One family of corner radii, always continuous.
enum Radius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
}

/// The type ramp: SF Pro for words, following Dynamic Type; SF Pro Rounded with fixed-width digits for numbers.
enum Typo {
    /// The name of a tab's screen.
    static let screen = Font.system(.title2, design: .default, weight: .bold)
    /// The name of a pushed screen, a row's name.
    static let title = Font.system(.headline, design: .default, weight: .semibold)
    static let body = Font.system(.body)
    static let bodyStrong = Font.system(.body, design: .default, weight: .medium)
    static let callout = Font.system(.callout)
    static let sub = Font.system(.subheadline)
    static let subStrong = Font.system(.subheadline, design: .default, weight: .semibold)
    static let foot = Font.system(.footnote)
    static let caption = Font.system(.caption)
    /// Section labels: small, medium weight, set in capitals with tracking.
    static let label = Font.system(.caption, design: .default, weight: .medium)
    /// The one primary button.
    static let button = Font.system(.body, design: .default, weight: .semibold)

    /// A number meant to be read from across the room. A fixed size (it scales down to fit, never up past it).
    static func number(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        Font.system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
    /// A number inside a line of text, in the text's own size.
    static func figure(_ style: Font.TextStyle = .body, weight: Font.Weight = .regular) -> Font {
        Font.system(style, design: .rounded, weight: weight).monospacedDigit()
    }
}

/// Haptics: a tick for each step of a value, a tap for a press that starts or stops something.
@MainActor
enum Haptics {
    private static let selection = UISelectionFeedbackGenerator()
    private static let impact = UIImpactFeedbackGenerator(style: .medium)
    private static let notify = UINotificationFeedbackGenerator()

    static func tick() { selection.selectionChanged() }
    static func tap() { impact.impactOccurred() }
    static func done() { notify.notificationOccurred(.success) }
}

let subdivisionOptions: [(Int, String)] = [(1, "Quarter"), (2, "Eighth"), (3, "Triplet"), (4, "16th")]
let meterOptions: [Int] = [2, 3, 4, 5, 6, 7]

/// "2:05" from seconds, and "12 min" or "1 h 20 min" for the minutes kept.
func formatMinutes(_ seconds: Double) -> String {
    let m = Int((seconds / 60).rounded())
    if m < 1 { return "under a minute" }
    if m < 60 { return "\(m) min" }
    return m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60) min"
}
