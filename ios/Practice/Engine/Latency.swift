import AVFoundation

// Latency, so every pick is scored against when the click was HEARD, not when it was made.
//
// The click is placed at a frame; it reaches the ears about outputLatency later (on Bluetooth headphones that is
// most of the delay, and iOS reports it), plus the IO buffer. A pick reaches the app about inputLatency after it was
// played. So the starting estimate is output + input + buffer. Calibration (play along to the clicks; the median of
// played minus click) measures the whole real delay on this route, and what is kept is the residual: measured minus
// the estimate at that moment. On later runs the offset is today's estimate plus that residual, so if iOS reports a
// different Bluetooth delay the next day, the offset follows it. Residuals are kept per route (the input and output
// ports), applied by themselves when that route is active.

struct RouteInfo: Equatable {
    var key: String               // "in:<uid>|out:<uid>"
    var input: String             // port names, for the screen
    var output: String
    var inputIsBuiltInMic: Bool
    var inputIsInterface: Bool     // USB, line in or a wired headset input
    var outputIsInterface: Bool    // the interface's own outputs (or wired headphones)
    var outputIsPhoneSpeaker: Bool
    var bluetoothOutput: Bool     // A2DP or LE: has a big output delay, fine for listening
    var handsFree: Bool           // HFP: the headphones are in call mode (low quality, their own mic)
    var phoneSpeakerAndMic: Bool { inputIsBuiltInMic && outputIsPhoneSpeaker }
    var name: String { input == output ? output : "\(input) in, \(output) out" }
}

struct Calibration: Codable, Equatable {
    var residual: Double          // seconds: measured minus the estimate when it was measured
    var measured: Double          // seconds, the whole offset that day
    var routeName: String
    var date: Date
}

enum Latency {
    static func estimate(output: Double, input: Double, ioBuffer: Double) -> Double {
        max(0, output) + max(0, input) + max(0, ioBuffer)
    }

    static func residual(measured: Double, estimate: Double) -> Double { measured - estimate }

    /// The offset to subtract from a pick's time: the estimate, corrected by this route's calibration if any.
    static func offset(estimate: Double, calibration: Calibration?) -> Double {
        estimate + (calibration?.residual ?? 0)
    }

    /// A played time moved onto the clock of what was heard.
    static func corrected(_ playedTime: Double, offset: Double) -> Double { playedTime - offset }

    static func routeKey(inputs: [String], outputs: [String]) -> String {
        "in:" + inputs.joined(separator: ",") + "|out:" + outputs.joined(separator: ",")
    }

    // MARK: The live session

    static func currentRoute() -> RouteInfo {
        let route = AVAudioSession.sharedInstance().currentRoute
        let ins = route.inputs, outs = route.outputs
        let bt: Set<AVAudioSession.Port> = [.bluetoothA2DP, .bluetoothLE]
        return RouteInfo(
            key: routeKey(inputs: ins.map(\.uid), outputs: outs.map(\.uid)),
            input: ins.first?.portName ?? "No input",
            output: outs.first?.portName ?? "No output",
            inputIsBuiltInMic: ins.first?.portType == .builtInMic,
            inputIsInterface: ins.contains { AudioEngine.interfacePorts.contains($0.portType) },
            outputIsInterface: outs.contains { ([.usbAudio, .lineOut, .headphones] as [AVAudioSession.Port]).contains($0.portType) },
            outputIsPhoneSpeaker: outs.contains { $0.portType == .builtInSpeaker || $0.portType == .builtInReceiver },
            bluetoothOutput: outs.contains { bt.contains($0.portType) },
            handsFree: outs.contains { $0.portType == .bluetoothHFP } || ins.contains { $0.portType == .bluetoothHFP })
    }

    static func currentEstimate() -> Double {
        let s = AVAudioSession.sharedInstance()
        return estimate(output: s.outputLatency, input: s.inputLatency, ioBuffer: s.ioBufferDuration)
    }
}

/// Calibrations by route, kept on the phone.
enum CalibrationStore {
    private static let key = "pa.calibrations"

    static func all() -> [String: Calibration] {
        guard let d = UserDefaults.standard.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: Calibration].self, from: d)) ?? [:]
    }

    static func get(_ route: String) -> Calibration? { all()[route] }

    static func set(_ c: Calibration, for route: String) {
        var a = all()
        a[route] = c
        if let d = try? JSONEncoder().encode(a) { UserDefaults.standard.set(d, forKey: key) }
    }
}
