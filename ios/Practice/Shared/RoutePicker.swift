import AVKit
import SwiftUI

/// The system's audio output picker (the AirPlay and Bluetooth sheet), for choosing the interface or the Bluetooth
/// headphones as the output while the guitar stays on the interface's input.
struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = UIColor(Theme.muted)
        v.activeTintColor = UIColor(hex: 0x6FB7A0)
        v.prioritizesVideoDevices = false
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
