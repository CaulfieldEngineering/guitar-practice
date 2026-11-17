import AVKit
import SwiftUI

/// The system's audio output picker (the AirPlay and Bluetooth sheet), for choosing the interface or the Bluetooth
/// headphones as the output while the guitar stays on the interface's input. Only iOS can move the sound to an output
/// other than the speaker, so picking one in the app's Output list opens this sheet: raising `trigger` presses it.
struct RoutePicker: UIViewRepresentable {
    var trigger = 0

    final class Coordinator { var last = 0 }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = UIColor(Theme.muted)
        v.activeTintColor = UIColor(hex: 0x6FB7A0)
        v.prioritizesVideoDevices = false
        context.coordinator.last = trigger
        return v
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        guard trigger != context.coordinator.last else { return }
        context.coordinator.last = trigger
        if let button = RoutePicker.button(in: uiView) { button.sendActions(for: .touchUpInside) }
    }

    private static func button(in view: UIView) -> UIButton? {
        for v in view.subviews {
            if let b = v as? UIButton { return b }
            if let b = button(in: v) { return b }
        }
        return nil
    }
}

/// A short notice at the top when the audio device changed; the screen under it stays as it was. In debug builds
/// with `-debugRoute 1`, a small button in the corner fakes a route change for the UI test.
struct RouteNoticeModifier: ViewModifier {
    @EnvironmentObject var pa: PlayAlong

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let n = pa.routeNotice {
                    Text(n)
                        .font(Typo.foot)
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, Space.sm)
                        .padding(.vertical, Space.xs)
                        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
                        .padding(.top, Space.xxs)
                        .padding(.horizontal, Space.page)
                        .transition(.opacity)
                        .accessibilityIdentifier("route.notice")
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeOut(duration: 0.2), value: pa.routeNotice)
            #if DEBUG
            .overlay(alignment: .bottomLeading) {
                if UserDefaults.standard.bool(forKey: "debugRoute") {
                    Button { pa.simulateRouteChange() } label: {
                        Color.clear.frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .accessibilityLabel("Simulate route change")
                    .accessibilityIdentifier("debug.routeChange")
                    .padding(.bottom, 120)
                }
            }
            #endif
    }
}

extension View {
    func routeNotice() -> some View { modifier(RouteNoticeModifier()) }
}
