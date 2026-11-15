import AVFoundation
import os

/// A value shared between the audio thread and the app. The audio thread only ever try-locks, so it never waits.
final class Locked<T> {
    private let lock: UnsafeMutablePointer<os_unfair_lock_s>
    private var value: T

    init(_ value: T) {
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock_s())
        self.value = value
    }
    deinit { lock.deinitialize(count: 1); lock.deallocate() }

    func with<R>(_ body: (inout T) -> R) -> R {
        os_unfair_lock_lock(lock); defer { os_unfair_lock_unlock(lock) }
        return body(&value)
    }

    /// For the audio thread: does nothing if the lock is held.
    @discardableResult
    func tryWith(_ body: (inout T) -> Void) -> Bool {
        guard os_unfair_lock_trylock(lock) else { return false }
        defer { os_unfair_lock_unlock(lock) }
        body(&value)
        return true
    }

    var current: T { with { $0 } }
}

/// What the app sets while the clicks run.
struct EngineParams {
    var bpm: Double = 120
    var beatsPerBar = 4
    var subdivision = 1
    var accent = true
    /// Off: the grid clicks go quiet (count-ins, bells and the guided notes still sound).
    var gridClicks = true
}

/// What the audio thread reports back.
struct EngineReport {
    var frame: Int64 = 0            // frames rendered so far
    var anchorFrame: Int64 = 0      // a frame, and the host time it plays at
    var anchorHost: Double = 0
    var lastBeat = -1
    var lastBeatFrame: Int64 = 0
    var finished = false
}

/// Everything the audio thread touches. The app sets the sequencers before the engine starts and never while it
/// runs; parameters go through `params`.
final class RenderState {
    let sampleRate: Double
    var free: FreeSequencer?
    var routine: RoutineSequencer?
    var track: EventQueue?
    private(set) var frame: Int64 = 0

    private let paramsBox: Locked<EngineParams>
    private let reportBox: Locked<EngineReport>
    private var params = EngineParams()

    private let soundPtrs: [UnsafeMutablePointer<Float>]
    private let soundLens: [Int]
    private static let voices = 32
    private var vSound = [Int](repeating: -1, count: voices)
    private var vPos = [Int](repeating: 0, count: voices)
    private var vDelay = [Int](repeating: 0, count: voices)
    private var lastBeat = -1
    private var lastBeatFrame: Int64 = 0

    init(sampleRate: Double, params: Locked<EngineParams>, report: Locked<EngineReport>, sounds: SoundBank = SynthSounds()) {
        self.sampleRate = sampleRate
        paramsBox = params
        reportBox = report
        self.params = params.current
        var ptrs: [UnsafeMutablePointer<Float>] = [], lens: [Int] = []
        for raw in 0...ClickKind.pluckAccent.rawValue {
            let s = sounds.samples(for: ClickKind(rawValue: raw)!, sampleRate: sampleRate)
            let p = UnsafeMutablePointer<Float>.allocate(capacity: max(1, s.count))
            s.withUnsafeBufferPointer { p.initialize(from: $0.baseAddress!, count: s.count) }
            ptrs.append(p); lens.append(s.count)
        }
        soundPtrs = ptrs; soundLens = lens
        report.with { $0 = EngineReport() }
    }

    deinit { for p in soundPtrs { p.deallocate() } }

    private func start(_ sound: ClickKind, delay: Int) {
        for v in 0..<RenderState.voices where vSound[v] < 0 {
            vSound[v] = sound.rawValue; vPos[v] = 0; vDelay[v] = delay
            return
        }
    }

    private func trigger(_ e: ClickEvent, blockLength n: Int) {
        let delay = Int(min(max(0, e.frame - frame), Int64(n - 1)))
        if e.beat >= 0 { lastBeat = e.beat; lastBeatFrame = e.frame }
        switch e.kind {
        case .accent, .beat, .sub:
            if params.gridClicks { start(e.kind, delay: delay) }
        case .change:
            start(.change, delay: delay)
            if params.gridClicks { start(.accent, delay: delay) }
        default:
            start(e.kind, delay: delay)
        }
    }

    func render(_ n: Int, _ ts: UnsafePointer<AudioTimeStamp>, _ abl: UnsafeMutablePointer<AudioBufferList>) {
        paramsBox.tryWith { self.params = $0 }
        if free != nil {
            free!.bpm = params.bpm
            free!.beatsPerBar = params.beatsPerBar
            free!.subdivision = params.subdivision
            free!.accent = params.accent
        }
        free?.events(from: frame, count: n) { trigger($0, blockLength: n) }
        routine?.events(from: frame, count: n) { trigger($0, blockLength: n) }
        track?.events(from: frame, count: n) { trigger($0, blockLength: n) }

        let bufs = UnsafeMutableAudioBufferListPointer(abl)
        guard let out = bufs[0].mData?.assumingMemoryBound(to: Float.self) else { return }
        for i in 0..<n { out[i] = 0 }
        for v in 0..<RenderState.voices where vSound[v] >= 0 {
            let s = vSound[v], p = soundPtrs[s], len = soundLens[s]
            var pos = vPos[v], i = vDelay[v]
            while i < n && pos < len { out[i] += p[pos]; i += 1; pos += 1 }
            vDelay[v] = 0; vPos[v] = pos
            if pos >= len { vSound[v] = -1 }
        }
        if bufs.count > 1 {
            for b in 1..<bufs.count {
                if let o = bufs[b].mData?.assumingMemoryBound(to: Float.self) { for i in 0..<n { o[i] = out[i] } }
            }
        }

        let host = ts.pointee.mFlags.contains(.hostTimeValid) ? AVAudioTime.seconds(forHostTime: ts.pointee.mHostTime) : 0
        let start = frame
        frame += Int64(n)
        let finished = routine?.finished ?? false
        let lb = lastBeat, lbf = lastBeatFrame, now = frame
        reportBox.tryWith {
            $0.frame = now
            if host > 0 { $0.anchorFrame = start; $0.anchorHost = host }
            $0.lastBeat = lb; $0.lastBeatFrame = lbf
            $0.finished = finished
        }
    }
}

/// The audio engine: one source node that renders the clicks sample by sample from the sequencers, so timing is
/// exact to the frame and never depends on a UI timer. Plays alongside other apps and keeps going when the screen
/// locks (the audio background mode). With `record`, the input (an interface, or the phone's microphone) is tapped
/// for the play-along.
final class AudioEngine {
    let params = Locked(EngineParams())
    let report = Locked(EngineReport())
    private(set) var engine: AVAudioEngine?
    private(set) var state: RenderState?
    private(set) var recording = false
    /// Input samples, the host time (seconds) of the first one, and the input sample rate. Called off the main thread.
    var onInput: ((UnsafeBufferPointer<Float>, Double, Double) -> Void)?
    /// Called on the main thread when the system stopped the engine (a call, a route change).
    var onInterrupted: (() -> Void)?
    private var observers: [NSObjectProtocol] = []
    /// The clicks, bells and guide notes; swap in a sampled set here.
    var sounds: SoundBank = SynthSounds()

    var isRunning: Bool { engine?.isRunning ?? false }
    var sampleRate: Double { state?.sampleRate ?? 48000 }
    /// Frames of silence before plan time 0, so the first click is never cut.
    var leadIn: Double { 0.12 * sampleRate }

    enum Failure: LocalizedError {
        case noInput
        var errorDescription: String? { "No input is available. Plug in an interface or allow the microphone." }
    }

    init() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            guard let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            if self?.engine != nil { self?.onInterrupted?() }
        })
        observers.append(nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            if self?.engine != nil { self?.onInterrupted?() }
        })
    }

    /// Starts from scratch. `setup` puts the sequencers in place (sample rate known, lead-in known).
    func start(record: Bool, setup: (RenderState, Double) -> Void) throws {
        stop()
        let session = AVAudioSession.sharedInstance()
        if record {
            // A2DP only (never .allowBluetooth, which is hands-free): Bluetooth headphones stay in their listening
            // mode, and the input is the interface or the phone's microphone, never the headphones' own.
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP])
            try? session.setActive(true)
            AudioEngine.preferWiredInput(session)
        } else {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        }
        try? session.setPreferredIOBufferDuration(0.005)
        try session.setActive(true)

        let engine = AVAudioEngine()
        let outFormat = engine.outputNode.outputFormat(forBus: 0)
        let sr = outFormat.sampleRate > 0 ? outFormat.sampleRate : session.sampleRate
        let st = RenderState(sampleRate: sr, params: params, report: report, sounds: sounds)
        setup(st, 0.12 * sr)
        let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
        let node = AVAudioSourceNode(format: fmt) { _, ts, frameCount, abl in
            st.render(Int(frameCount), ts, abl)
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: fmt)

        if record {
            let input = engine.inputNode
            let inFormat = input.outputFormat(forBus: 0)
            guard inFormat.sampleRate > 0, inFormat.channelCount > 0 else { throw Failure.noInput }
            let inRate = inFormat.sampleRate
            input.installTap(onBus: 0, bufferSize: 512, format: inFormat) { [weak self] buffer, when in
                guard let ch = buffer.floatChannelData?[0] else { return }
                let host = when.isHostTimeValid ? AVAudioTime.seconds(forHostTime: when.hostTime) : 0
                self?.onInput?(UnsafeBufferPointer(start: ch, count: Int(buffer.frameLength)), host, inRate)
            }
        }
        observers.append(NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            if self?.engine === engine { self?.onInterrupted?() }
        })
        engine.prepare()
        try engine.start()
        self.engine = engine
        self.state = st
        recording = record
    }

    func stop() {
        guard let engine else { return }
        if recording { engine.inputNode.removeTap(onBus: 0) }
        engine.stop()
        self.engine = nil
        state = nil
        recording = false
    }

    /// Seconds of plan time played so far (frames rendered, less the lead-in, less the output latency).
    func planTime(origin: Double) -> Double {
        let f = Double(report.current.frame)
        let lat = AVAudioSession.sharedInstance().outputLatency
        return (f - origin) / sampleRate - lat
    }

    /// Host time (seconds) at which a frame plays, from the latest anchor.
    func hostTime(ofFrame f: Double) -> Double {
        let r = report.current
        return r.anchorHost + (f - Double(r.anchorFrame)) / sampleRate
    }

    /// The interface (USB or a wired headset input) when there is one, otherwise the phone's microphone.
    static func preferWiredInput(_ session: AVAudioSession) {
        let inputs = session.availableInputs ?? []
        let order: [AVAudioSession.Port] = [.usbAudio, .lineIn, .headsetMic, .builtInMic]
        for type in order {
            if let port = inputs.first(where: { $0.portType == type }) {
                if session.preferredInput?.uid != port.uid { try? session.setPreferredInput(port) }
                return
            }
        }
    }

    /// Before speaking with nothing running: the playback session, mixing with other apps. Leaves a running one alone.
    static func prepareSession() {
        let s = AVAudioSession.sharedInstance()
        if s.category != .playback && s.category != .playAndRecord {
            try? s.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        }
        try? s.setActive(true)
    }

}
