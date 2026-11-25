import Foundation

// The engine's seams. Each piece behind a protocol so a better one drops in without touching the features:
// a sampled guide guitar for SoundBank, a spectral-flux or ML detector for OnsetDetecting, a MIDI guitar for NoteInput.

/// The sounds the engine plays: clicks, bells and the guide notes.
protocol SoundBank {
    func samples(for kind: ClickKind, sampleRate: Double) -> [Float]
}

/// Sounds made in code (ClickSounds): no files, any sample rate.
struct SynthSounds: SoundBank {
    func samples(for kind: ClickKind, sampleRate: Double) -> [Float] { ClickSounds.make(kind, sampleRate: sampleRate) }
}

/// Finds note starts in audio. Called on the input thread, one block at a time.
protocol OnsetDetecting {
    mutating func process(_ samples: UnsafeBufferPointer<Float>, time: Double) -> [Onset]
    mutating func flush() -> Onset?
    var level: Float { get }
}

extension OnsetDetector: OnsetDetecting {}

/// Where played notes come from, as onsets on the host clock (seconds).
protocol NoteInput: AnyObject {
    /// Whether the engine has to open the audio input (an interface or the microphone).
    var needsAudioInput: Bool { get }
    /// Called before the engine starts.
    func attach(to engine: AudioEngine)
    /// Notes found since the last call.
    func drain() -> [Onset]
    /// The run ended: anything still held back.
    func finish() -> [Onset]
    /// Input level, 0 to 1 (RMS), for the meter.
    var level: Float { get }
    /// Whether each onset should carry its pitch (a drill with pitched notes); set before `attach`.
    var wantsPitch: Bool { get set }
}

/// The guitar through the audio input, with an onset detector made for the input's sample rate.
final class AudioOnsetInput: NoteInput {
    private let makeDetector: (Double) -> any OnsetDetecting
    private let detector = Locked<(any OnsetDetecting)?>(nil)
    private let incoming = Locked<[Onset]>([])
    private let levelBox = Locked<Float>(0)
    private let tracker = Locked<PitchTracker?>(nil)
    var wantsPitch = false

    init(makeDetector: @escaping (Double) -> any OnsetDetecting = { OnsetDetector(sampleRate: $0) }) {
        self.makeDetector = makeDetector
    }

    var needsAudioInput: Bool { true }
    var level: Float { levelBox.current }

    func attach(to engine: AudioEngine) {
        detector.with { $0 = nil }
        incoming.with { $0.removeAll() }
        tracker.with { $0 = nil }
        let detector = detector, incoming = incoming, levelBox = levelBox, make = makeDetector, tracker = tracker
        let pitch = wantsPitch
        engine.onInput = { samples, host, rate in
            var found: [Onset] = []
            var lvl: Float = 0
            detector.with { d in
                if d == nil { d = make(rate) }
                found = d!.process(samples, time: host)
                lvl = d!.level
            }
            // A drill with pitched notes: each onset waits a few tens of ms for the samples that tell its pitch.
            if pitch {
                found = tracker.with { t in
                    if t == nil { t = PitchTracker(sampleRate: rate) }
                    return t!.process(samples, host: host, onsets: found)
                }
            }
            if !found.isEmpty { incoming.with { $0.append(contentsOf: found) } }
            levelBox.with { $0 = lvl }
        }
    }

    func drain() -> [Onset] { incoming.with { let l = $0; $0.removeAll(); return l } }

    func finish() -> [Onset] {
        var out = drain()
        out += tracker.with { $0?.flush() ?? [] }
        if let last = detector.with({ $0?.flush() }) { out.append(last) }
        return out
    }
}
