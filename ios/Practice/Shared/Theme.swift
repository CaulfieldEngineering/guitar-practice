import SwiftUI
import UIKit

/// The house style's tokens (HQ/agent/app-design.md), light and dark, with the studio accent.
enum Theme {
    static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
    static let bg = dyn(0xFFFFFF, 0x1C1C1B)
    static let side = dyn(0xF7F7F5, 0x161615)
    static let raised = dyn(0xFFFFFF, 0x262625)
    static let text = dyn(0x1C1B19, 0xE4E3DF)
    static let muted = dyn(0x6A6964, 0xA3A29C)
    static let faint = dyn(0xA09F99, 0x6B6A65)
    static let line = dyn(0xEBEAE6, 0x2B2B29)
    static let lineStrong = dyn(0xDCDBD6, 0x3B3B38)
    static let hover = dyn(0xEDEDEA, 0x2A2A28)
    static let accent = Color(UIColor(hex: 0x6FB7A0))
    static let onAccent = Color(UIColor(hex: 0x0F1F1A))
    static let accentSoft = Color(UIColor(hex: 0x6FB7A0)).opacity(0.16)
    static let warn = Color(UIColor(hex: 0xD9A441))
    static let danger = dyn(0xC4402B, 0xE8796B)
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// 11px small-caps section label.
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .medium))
            .tracking(0.6)
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The one primary action of a view.
struct PrimaryButton: View {
    let title: String
    var systemImage: String?
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.system(size: 17, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(Theme.onAccent)
        }
        .buttonStyle(.plain)
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
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage) }
                if !title.isEmpty { Text(title) }
            }
            .font(.system(size: 16, weight: .medium))
            .frame(maxWidth: .infinity, minHeight: height)
            .background(Theme.hover, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(Theme.text)
        }
        .buttonStyle(.plain)
    }
}

/// A round icon button, 44 points.
struct IconButton: View {
    let systemImage: String
    var size: CGFloat = 44
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.4, weight: .medium))
                .frame(width: size, height: size)
                .background(Theme.hover, in: Circle())
                .foregroundStyle(Theme.text)
        }
        .buttonStyle(.plain)
    }
}

/// One row: a label on the left, the control on the right, 44 points high, a hairline under it.
struct Row<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(label).font(.system(size: 15)).foregroundStyle(Theme.text)
                Spacer(minLength: 12)
                content
            }
            .frame(minHeight: 44)
            Rectangle().fill(Theme.line).frame(height: 1)
        }
    }
}

/// The beats of the bar as dots; the one playing is lit.
struct BeatDots: View {
    let beats: Int
    let current: Int
    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<max(1, beats), id: \.self) { i in
                Circle()
                    .fill(i == current ? Theme.accent : Theme.lineStrong)
                    .frame(width: i == 0 ? 16 : 12, height: i == 0 ? 16 : 12)
                    .animation(.easeOut(duration: 0.06), value: current)
            }
        }
        .frame(height: 18)
    }
}

/// Segmented choice in the house style: one track, the chosen segment lifted.
struct Segmented<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                let (value, title) = options[i]
                Button { selection = value } label: {
                    Text(title)
                        .font(.system(size: 13, weight: selection == value ? .semibold : .regular))
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(selection == value ? Theme.raised : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(selection == value ? Theme.lineStrong : Color.clear, lineWidth: 1))
                        .foregroundStyle(selection == value ? Theme.text : Theme.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Theme.hover, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

let subdivisionOptions: [(Int, String)] = [(1, "Quarter"), (2, "Eighth"), (3, "Triplet"), (4, "16th")]
let meterOptions: [Int] = [2, 3, 4, 5, 6, 7]
