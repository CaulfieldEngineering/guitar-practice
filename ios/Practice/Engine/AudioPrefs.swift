import Foundation

// What the Audio screen sets, remembered per device (Joe, 2026-11-16: "to define the input, and the output and check
// levels"): for each input (by its port id) the channel, the gain and the mic position; for each output the level of
// the app's own sounds and whether the guitar is heard through the app. The engine reads them each time it is built,
// so plugging a device in brings back what was set for it.

struct InputPrefs: Codable, Equatable {
    var channel: InputChannel = .both
    /// 0 to 1, only where iOS lets the app set it.
    var gain: Float?
    /// The microphone position (front, back, bottom) on inputs that have several.
    var dataSourceID: Int?
}

struct OutputPrefs: Codable, Equatable {
    /// The clicks, the guide guitar, the voice and the test sounds, 0 to 1.
    var appVolume: Double?
    /// Hear the guitar through the app.
    var monitor = false
    var monitorLevel = 0.8
}

enum AudioPrefs {
    private static let inputsKey = "audio.inputs"
    private static let outputsKey = "audio.outputs"
    private static let preferredKey = "audio.preferredInput"
    static var defaults = UserDefaults.standard

    private static func load<T: Decodable>(_ key: String) -> [String: T] {
        guard let d = defaults.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: T].self, from: d)) ?? [:]
    }

    private static func save<T: Encodable>(_ value: [String: T], _ key: String) {
        if let d = try? JSONEncoder().encode(value) { defaults.set(d, forKey: key) }
    }

    static func input(_ uid: String) -> InputPrefs {
        let all: [String: InputPrefs] = load(inputsKey)
        return all[uid] ?? InputPrefs()
    }
    static func setInput(_ p: InputPrefs, for uid: String) {
        var all: [String: InputPrefs] = load(inputsKey)
        all[uid] = p
        save(all, inputsKey)
    }

    static func output(_ uid: String) -> OutputPrefs {
        let all: [String: OutputPrefs] = load(outputsKey)
        return all[uid] ?? OutputPrefs()
    }
    static func setOutput(_ p: OutputPrefs, for uid: String) {
        var all: [String: OutputPrefs] = load(outputsKey)
        all[uid] = p
        save(all, outputsKey)
    }

    /// An output seen on this phone, so it can be listed when it is not connected (iOS lists only the one in use).
    struct SeenOutput: Codable, Equatable { var name: String; var type: String }
    private static let seenKey = "audio.seenOutputs"
    private static let preferredOutputKey = "audio.preferredOutput"
    /// The phone's own speaker, which the app can choose by itself.
    static let speakerID = "speaker"

    static var seenOutputs: [String: SeenOutput] { load(seenKey) }
    static func sawOutput(_ uid: String, name: String, type: String) {
        guard !uid.isEmpty else { return }
        var all: [String: SeenOutput] = load(seenKey)
        let s = SeenOutput(name: name, type: type)
        guard all[uid] != s else { return }
        all[uid] = s
        save(all, seenKey)
    }

    /// The output picked by hand (a port id, or `speakerID`).
    static var preferredOutput: String? {
        get { defaults.string(forKey: preferredOutputKey) }
        set { defaults.set(newValue, forKey: preferredOutputKey) }
    }

    /// Input names by port id, so a picked input can be named while it is unplugged.
    static func inputName(_ uid: String?) -> String? {
        guard let uid else { return nil }
        return (defaults.dictionary(forKey: "audio.inputNames") as? [String: String])?[uid]
    }
    static func setInputName(_ name: String, for uid: String) {
        var all = defaults.dictionary(forKey: "audio.inputNames") as? [String: String] ?? [:]
        all[uid] = name
        defaults.set(all, forKey: "audio.inputNames")
    }

    /// The input picked by hand on the Audio screen, used whenever it is plugged in.
    static var preferredInput: String? {
        get { defaults.string(forKey: preferredKey) }
        set { defaults.set(newValue, forKey: preferredKey) }
    }
}

// MARK: What is wrong, in plain words

/// The facts the Audio screen's check works from (read from the session; plain values so it is unit tested).
struct AudioFacts: Equatable {
    enum Permission { case granted, denied, undetermined }
    var permission: Permission = .granted
    /// An interface (USB, line in, wired headset) is offered as an input.
    var interfaceAvailable = false
    var inputIsInterface = false
    var inputIsBuiltInMic = false
    var bluetoothOutput = false
    var outputIsInterface = false
    var handsFree = false
    /// The interface's inputs the app can see.
    var channels = 1
    var channel: InputChannel = .both
    var gainSettable = false
    var gain: Float = 1
    /// The input is being listened to (the meter is live).
    var listening = false
    var verdict: LevelVerdict = .noSignal
    /// Seconds the input has had no signal while listening.
    var silentSeconds: Double = 0
    /// The channel not listened to has a signal (1 or 2), when one is picked.
    var signalOnOther: Int?
}

struct AudioProblem: Identifiable, Equatable {
    enum Kind: String { case permissionDenied, permissionUndetermined, noInterface, bluetoothLimit, onInterfaceOutput,
                        callMode, gainZero, otherInput, noSignal, tooQuiet, clipping }
    enum Action: Equatable { case openSettings, askPermission, useChannel(InputChannel) }
    var kind: Kind
    var title: String
    /// Steps to try, in order, one short line each.
    var steps: [String] = []
    var action: Action?
    /// Bad (in amber) or only worth knowing.
    var warning = true
    var id: String { kind.rawValue }
}

enum AudioDiagnosis {
    /// What to tell him, most important first.
    static func problems(_ f: AudioFacts) -> [AudioProblem] {
        var out: [AudioProblem] = []
        switch f.permission {
        case .denied:
            out.append(AudioProblem(kind: .permissionDenied, title: L.diagPermissionOff, steps: [L.diagPermissionStep], action: .openSettings))
        case .undetermined:
            out.append(AudioProblem(kind: .permissionUndetermined, title: L.diagPermissionAsk, action: .askPermission, warning: false))
        case .granted: break
        }
        if !f.interfaceAvailable {
            out.append(AudioProblem(kind: .noInterface, title: L.diagNoInterface,
                                    steps: [L.diagStepPower, L.diagStepClassCompliant, L.diagStepReplug]))
        }
        if f.handsFree {
            out.append(AudioProblem(kind: .callMode, title: L.callMode))
        }
        if f.interfaceAvailable && f.bluetoothOutput && !f.inputIsInterface {
            // The known iOS limit: with the sound on Bluetooth, iOS took the input off the interface.
            out.append(AudioProblem(kind: .bluetoothLimit, title: L.diagBluetoothLimit, steps: [L.diagStepTransmitter]))
        } else if f.inputIsInterface && f.outputIsInterface {
            out.append(AudioProblem(kind: .onInterfaceOutput, title: L.diagOnInterface, steps: [L.diagStepPickShokz, L.diagStepTransmitter],
                                    warning: false))
        }
        guard f.listening, f.permission == .granted else { return out }
        if f.gainSettable && f.gain < 0.05 {
            out.append(AudioProblem(kind: .gainZero, title: L.diagGainZero, steps: [L.diagStepRaiseGain]))
        }
        if let other = f.signalOnOther, f.verdict == .noSignal || f.verdict == .tooQuiet {
            let pick: InputChannel = other == 2 ? .second : .first
            out.append(AudioProblem(kind: .otherInput, title: L.diagOtherInput(other), action: .useChannel(pick)))
            return out
        }
        switch f.verdict {
        case .noSignal where f.silentSeconds >= 3:
            var steps = [L.diagStepPlay, L.diagStepGain, L.diagStepInst, L.diagStepCable]
            if f.channels >= 2 && f.channel != .both { steps.insert(L.diagStepBoth, at: 1) }
            if !f.inputIsInterface && f.interfaceAvailable { steps.insert(L.diagStepPickInterface, at: 0) }
            out.append(AudioProblem(kind: .noSignal, title: L.diagNoSignal, steps: steps))
        case .tooQuiet:
            out.append(AudioProblem(kind: .tooQuiet, title: L.diagTooQuiet, steps: [L.diagStepGain]))
        case .clipping:
            out.append(AudioProblem(kind: .clipping, title: L.diagClipping, steps: [L.diagStepLower]))
        default: break
        }
        return out
    }
}

// MARK: The choice, and what iOS did with it

/// What was picked by hand and what iOS is using. Never ignored silently: when they differ the screen says why in one
/// line (Joe, 2026-11-16: "just allow me to pick input and output explicitly").
struct ChoiceFacts: Equatable {
    var pickedInput: String?
    var pickedInputName: String?
    var pickedInputConnected = false
    var inputUID: String?
    var inputName: String?
    var inputIsInterface = false
    var pickedOutput: String?
    var pickedOutputName: String?
    var pickedOutputIsBluetooth = false
    var outputUID: String?
    var outputName: String?
    var outputIsSpeaker = false
    var outputIsInterface = false
    /// The session has the input open (the speaker can be chosen only then).
    var recording = true
}

extension AudioDiagnosis {
    static func inputNote(_ c: ChoiceFacts) -> String? {
        guard let want = c.pickedInput, want != c.inputUID else { return nil }
        let name = c.pickedInputName ?? L.pickedDevice
        let now = c.inputName ?? L.noInputName
        return c.pickedInputConnected ? L.fallbackInputRefused(name, now) : L.fallbackInputMissing(name, now)
    }

    static func outputNote(_ c: ChoiceFacts) -> String? {
        guard let want = c.pickedOutput else { return nil }
        let now = c.outputName ?? L.noOutputName
        if want == AudioPrefs.speakerID {
            if c.outputIsSpeaker { return nil }
            return c.recording ? L.fallbackSpeaker(now) : L.fallbackSpeakerClosed(now)
        }
        guard want != c.outputUID else { return nil }
        let name = c.pickedOutputName ?? L.pickedDevice
        if c.pickedOutputIsBluetooth && c.inputIsInterface && c.outputIsInterface {
            // The known limit: recording from the interface, iOS keeps the sound on it.
            return L.fallbackBluetoothUSB(name, now)
        }
        return L.fallbackOutput(name, now)
    }
}
