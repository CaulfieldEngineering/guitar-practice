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
    /// Raised by one to play a second of test tone (the Audio screen).
    var toneSerial = 0
    /// The click's sound and level (0.3.0, set on a drill before Start).
    var clickSound: SessionSettings.ClickSound = .click
    var clickLevel: Float = 1
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
    private var vGain = [Float](repeating: 1, count: voices)
    private var lastBeat = -1
    private var lastBeatFrame: Int64 = 0

    // The guide guitar: recorded notes, each played at its own speed to be in tune. One string's worth: a new note
    // damps the one before it.
    private let guitar: GuitarBank?
    private let guitarRatio: Double
    private static let strings = 8
    private var gSample = [Int](repeating: -1, count: strings)
    private var gPos = [Double](repeating: 0, count: strings)
    private var gStep = [Double](repeating: 1, count: strings)
    private var gDelay = [Int](repeating: 0, count: strings)
    private var gGain = [Float](repeating: 1, count: strings)
    private var gFade = [Bool](repeating: false, count: strings)

    // The test tone: an A at 440 Hz, -12 dBFS, one second with short fades.
    private var lastToneSerial = 0
    private var toneLeft = 0
    private var tonePhase = 0.0

    init(sampleRate: Double, params: Locked<EngineParams>, report: Locked<EngineReport>, sounds: SoundBank = SynthSounds(),
         guitar: GuitarBank? = GuitarBank.shared) {
        self.sampleRate = sampleRate
        self.guitar = guitar
        guitarRatio = (guitar?.sampleRate ?? sampleRate) / max(1, sampleRate)
        paramsBox = params
        reportBox = report
        self.params = params.current
        lastToneSerial = self.params.toneSerial
        var ptrs: [UnsafeMutablePointer<Float>] = [], lens: [Int] = []
        for raw in 0...ClickKind.last.rawValue {
            let s = sounds.samples(for: ClickKind(rawValue: raw)!, sampleRate: sampleRate)
            let p = UnsafeMutablePointer<Float>.allocate(capacity: max(1, s.count))
            s.withUnsafeBufferPointer { p.initialize(from: $0.baseAddress!, count: s.count) }
            ptrs.append(p); lens.append(s.count)
        }
        soundPtrs = ptrs; soundLens = lens
        report.with { $0 = EngineReport() }
    }

    deinit { for p in soundPtrs { p.deallocate() } }

    private func start(_ sound: ClickKind, delay: Int, gain: Float = 1) {
        for v in 0..<RenderState.voices where vSound[v] < 0 {
            vSound[v] = sound.rawValue; vPos[v] = 0; vDelay[v] = delay; vGain[v] = gain
            return
        }
    }

    private func trigger(_ e: ClickEvent, blockLength n: Int) {
        let delay = Int(min(max(0, e.frame - frame), Int64(n - 1)))
        if e.beat >= 0 { lastBeat = e.beat; lastBeatFrame = e.frame }
        switch e.kind {
        case .accent, .beat, .sub:
            if params.gridClicks { start(e.kind.voiced(params.clickSound), delay: delay, gain: params.clickLevel) }
        case .countIn:
            start(.countIn, delay: delay, gain: max(0.3, params.clickLevel))
        case .change:
            start(.change, delay: delay)
            if params.gridClicks { start(ClickKind.accent.voiced(params.clickSound), delay: delay, gain: params.clickLevel) }
        default:
            if e.sample >= 0, let g = guitar, e.sample < g.ptrs.count {
                pluck(e, delay: delay)
            } else {
                start(e.kind, delay: delay)
            }
        }
    }

    /// A note of the guide guitar. The note still sounding is damped, as it is when one string is picked again.
    private func pluck(_ e: ClickEvent, delay: Int) {
        for v in 0..<RenderState.strings where gSample[v] >= 0 { gFade[v] = true }
        for v in 0..<RenderState.strings where gSample[v] < 0 {
            gSample[v] = e.sample; gPos[v] = 0; gStep[v] = max(0.25, min(4, e.step)) * guitarRatio
            gDelay[v] = delay; gGain[v] = 0.9; gFade[v] = false
            return
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
            let g = vGain[v]
            while i < n && pos < len { out[i] += p[pos] * g; i += 1; pos += 1 }
            vDelay[v] = 0; vPos[v] = pos
            if pos >= len { vSound[v] = -1 }
        }
        if let g = guitar {
            for v in 0..<RenderState.strings where gSample[v] >= 0 {
                let p = g.ptrs[gSample[v]], len = g.lengths[gSample[v]]
                let step = gStep[v], fade = gFade[v]
                var pos = gPos[v], gain = gGain[v], i = gDelay[v]
                var ended = false
                while i < n {
                    let k = Int(pos)
                    if k + 1 >= len || gain < 0.0005 { ended = true; break }
                    let f = Float(pos - Double(k))
                    out[i] += (p[k] + (p[k + 1] - p[k]) * f) * gain
                    if fade { gain *= 0.995 }
                    pos += step
                    i += 1
                }
                gDelay[v] = 0; gPos[v] = pos; gGain[v] = gain
                if ended { gSample[v] = -1 }
            }
        }
        if params.toneSerial != lastToneSerial {
            lastToneSerial = params.toneSerial
            toneLeft = Int(sampleRate)
            tonePhase = 0
        }
        if toneLeft > 0 {
            let total = Int(sampleRate), fade = max(1, Int(sampleRate * 0.01))
            let step = 2 * Double.pi * 440 / sampleRate
            var i = 0
            while i < n && toneLeft > 0 {
                let done = total - toneLeft
                let env = Float(min(1, Double(min(done, toneLeft)) / Double(fade)))
                out[i] += Float(sin(tonePhase)) * 0.25 * env
                tonePhase += step
                if tonePhase > 2 * Double.pi { tonePhase -= 2 * Double.pi }
                toneLeft -= 1
                i += 1
            }
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
/// for the play-along and the meter, on the channel picked on the Audio screen, and can be heard through the app.
///
/// A route change (an interface plugged in, Bluetooth headphones connecting, another output picked) rebuilds the
/// engine in place on the new route with the same render state, so the clicks, the run and the screen carry on
/// (Joe, 2026-11-16: "when I swap the audio device it closes that current window"). Only a call or a reset of the
/// audio system stops it.
final class AudioEngine {
    let params = Locked(EngineParams())
    let report = Locked(EngineReport())
    private(set) var engine: AVAudioEngine?
    private(set) var state: RenderState?
    private(set) var recording = false
    /// Whether the input is tapped now (a record engine on a route with no input runs without it).
    private(set) var tapped = false
    /// Input samples (the picked channel), the host time (seconds) of the first one, and the input sample rate.
    /// Called off the main thread.
    var onInput: ((UnsafeBufferPointer<Float>, Double, Double) -> Void)?
    /// What the input tap saw since the meter last took it.
    let meter = Locked(MeterReading())
    /// The input's channel count and the channel listened to, as built.
    private(set) var inputChannels = 0
    private(set) var listening: InputChannel = .both
    /// Called on the main thread when the system stopped the engine (a call, a reset) and it could not go on.
    var onInterrupted: (() -> Void)?
    /// Called on the main thread after the engine was rebuilt on a new route and carries on.
    var onRerouted: (() -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var configObserver: NSObjectProtocol?
    private var rebuildScheduled = false
    private var source: AVAudioSourceNode?
    private var monitorMixer: AVAudioMixerNode?
    /// The clicks, bells and guide notes; swap in a sampled set here.
    var sounds: SoundBank = SynthSounds()

    /// The app's own sounds against the guitar, 0 to 1 (the Audio screen's App Sounds).
    var appVolume: Float = 1 { didSet { source?.volume = appVolume } }
    /// The guitar heard through the app, 0 to 1, when monitoring is on for this output.
    var monitorVolume: Float = 0.8 { didSet { monitorMixer?.outputVolume = monitorVolume } }

    var isRunning: Bool { engine?.isRunning ?? false }
    var isMonitoring: Bool { monitorMixer != nil }
    var sampleRate: Double { state?.sampleRate ?? 48000 }
    /// Frames of silence before plan time 0, so the first click is never cut.
    var leadIn: Double { 0.12 * sampleRate }

    enum Failure: LocalizedError {
        case noInput, noInterface
        var errorDescription: String? {
            switch self {
            case .noInput: return L.noAudioInput
            case .noInterface: return L.connectInterface
            }
        }
    }
    /// The testing switch: let the phone's microphone stand in for the interface.
    var allowPhoneMic = false

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
        try AudioEngine.configure(session, record: record, allowPhoneMic: allowPhoneMic)

        let engine = AVAudioEngine()
        let outFormat = engine.outputNode.outputFormat(forBus: 0)
        let sr = outFormat.sampleRate > 0 ? outFormat.sampleRate : session.sampleRate
        let st = RenderState(sampleRate: sr, params: params, report: report, sounds: sounds)
        setup(st, 0.12 * sr)
        try build(engine, state: st, record: record, requireInput: record)
    }

    /// The session for a run, a check or the metronome. Recording: play and record, A2DP only (never .allowBluetooth,
    /// which is hands-free), so Bluetooth headphones stay in their listening mode and the input is the interface (or
    /// the phone's microphone when allowed), never the headphones' own; measurement mode, so iOS adds no processing
    /// or gain control to the guitar. Then the input picked on the Audio screen, its channels, gain and mic position.
    static func configure(_ session: AVAudioSession, record: Bool, allowPhoneMic: Bool) throws {
        if record {
            try session.setCategory(.playAndRecord, mode: .measurement, options: recordOptions)
            try? session.setActive(true)
            try preferInterface(session, allowPhoneMic: allowPhoneMic)
        } else {
            try session.setCategory(.playback, mode: .default, options: playOptions)
        }
        try? session.setPreferredIOBufferDuration(0.005)
        try session.setActive(true)
        if record { applyInputPrefs(session) }
        applyOutputChoice(session)
    }

    /// The output picked by hand. iOS lets an app choose only the phone's speaker by itself (and only while the
    /// input is open); any other output is chosen in the system's list, and the Audio screen says when iOS put the
    /// sound somewhere else. Applied when the session is set up and on a pick, never in answer to a route change:
    /// each override is a route change of its own, and answering them froze 0.2.0 (Joe, 2026-11-17).
    ///
    /// The speaker override is iOS's "speaker and built-in microphone": it drops an interface's input (Joe, the same
    /// evening: "ios kept iphone microphone instead of momix-cab"). So with an interface as the input it is never
    /// used: an interface with no output of its own already leaves the sound on the speaker (`.defaultToSpeaker`),
    /// and one with an output keeps the sound, which the screen says.
    static func applyOutputChoice(_ session: AVAudioSession = .sharedInstance()) {
        guard session.category == .playAndRecord else { return }
        let wantSpeaker = AudioPrefs.preferredOutput == AudioPrefs.speakerID
        let wanted = pickedInput(session) ?? interfaceInput(session)
        let interfaceIn = wanted.map { interfacePorts.contains($0.portType) } ?? false
        if wantSpeaker && !interfaceIn {
            if !speakerOverridden {
                try? session.overrideOutputAudioPort(.speaker)
                speakerOverridden = true
            }
        } else if speakerOverridden {
            try? session.overrideOutputAudioPort(.none)
            speakerOverridden = false
        }
    }
    /// Whether this app set the speaker override (only then is it taken off again).
    private(set) static var speakerOverridden = false

    /// Wires the engine: the source node (at the render state's own rate, so a new route's rate is converted by the
    /// mixer and the frame clock never jumps), the input tap on the picked channel, and the monitor path.
    private func build(_ engine: AVAudioEngine, state st: RenderState, record: Bool, requireInput: Bool) throws {
        let fmt = AVAudioFormat(standardFormatWithSampleRate: st.sampleRate, channels: 1)!
        let node = AVAudioSourceNode(format: fmt) { _, ts, frameCount, abl in
            st.render(Int(frameCount), ts, abl)
            return noErr
        }
        node.volume = appVolume
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: fmt)
        engine.mainMixerNode.outputVolume = 1

        var didTap = false
        var mixer: AVAudioMixerNode?
        if record {
            let input = engine.inputNode
            let inFormat = input.outputFormat(forBus: 0)
            if inFormat.sampleRate > 0 && inFormat.channelCount > 0 {
                installTap(on: input, format: inFormat)
                didTap = true
                let route = Latency.currentRoute()
                let out = AudioPrefs.output(AudioEngine.outputUID())
                // Not on the phone's own speaker and microphone: it would feed back.
                if AudioPrefs.monitorOn(out, bluetooth: route.bluetoothOutput) && !route.phoneSpeakerAndMic {
                    let m = AVAudioMixerNode()
                    engine.attach(m)
                    engine.connect(input, to: m, format: inFormat)
                    // Mono out of the monitor, so a guitar on one input is heard in both ears.
                    engine.connect(m, to: engine.mainMixerNode,
                                   format: AVAudioFormat(standardFormatWithSampleRate: inFormat.sampleRate, channels: 1))
                    monitorVolume = Float(out.monitorLevel)
                    m.outputVolume = monitorVolume
                    mixer = m
                }
            } else if requireInput {
                throw Failure.noInput
            }
        }
        configObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            if self?.engine === engine { self?.scheduleRebuild() }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            if didTap { engine.inputNode.removeTap(onBus: 0) }
            if let o = configObserver { NotificationCenter.default.removeObserver(o); configObserver = nil }
            throw error
        }
        self.engine = engine
        self.state = st
        self.source = node
        self.monitorMixer = mixer
        recording = record
        tapped = didTap
    }

    private func installTap(on input: AVAudioInputNode, format inFormat: AVAudioFormat) {
        let inRate = inFormat.sampleRate
        let chans = Int(inFormat.channelCount)
        let pick = AudioPrefs.input(AudioEngine.inputUID()).channel
        inputChannels = chans
        listening = pick
        let meter = self.meter
        let scratch = Scratch()
        meter.with { $0 = MeterReading() }
        input.installTap(onBus: 0, bufferSize: 512, format: inFormat) { [weak self] buffer, when in
            guard let data = buffer.floatChannelData else { return }
            let n = Int(buffer.frameLength)
            guard n > 0 else { return }
            let host = when.isHostTimeValid ? AVAudioTime.seconds(forHostTime: when.hostTime) : 0
            let ptrs = (0..<min(chans, 2)).map { UnsafePointer(data[$0]) }
            let out = scratch.buffer(n)
            InputChannel.mix(ptrs, frames: n, pick: pick, into: out)
            let picked = UnsafeBufferPointer(start: UnsafePointer(out), count: n)
            meter.with { m in
                m.add(picked)
                for (k, p) in ptrs.enumerated() { m.addChannelPeak(k, UnsafeBufferPointer(start: p, count: n)) }
            }
            self?.onInput?(picked, host, inRate)
        }
    }

    /// The meter's reading since it was last taken.
    func takeMeter() -> MeterReading { meter.with { let r = $0; $0 = MeterReading(); return r } }

    /// Route changes come in bursts: rebuild once, a moment after the last.
    private func scheduleRebuild() {
        guard !rebuildScheduled else { return }
        rebuildScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + (RouteHub.quiet ? 1.0 : 0.3)) { [weak self] in
            guard let self else { return }
            self.rebuildScheduled = false
            self.rebuild()
        }
    }

    #if DEBUG
    /// For the UI test of route changes: what a real AVAudioEngineConfigurationChange does.
    func simulateConfigurationChange() { if engine != nil { scheduleRebuild() } }
    #endif

    /// The engine again, on the route there is now, carrying on from the same frame (the Audio screen calls it too,
    /// after the channel or monitoring changes).
    func rebuild() {
        guard let old = engine, let st = state else { return }
        let record = recording
        if tapped { old.inputNode.removeTap(onBus: 0) }
        old.stop()
        if let o = configObserver { NotificationCenter.default.removeObserver(o); configObserver = nil }
        engine = nil; source = nil; monitorMixer = nil; tapped = false
        let session = AVAudioSession.sharedInstance()
        if record {
            try? AudioEngine.preferInterface(session, allowPhoneMic: allowPhoneMic)
            try? session.setActive(true)
            AudioEngine.applyInputPrefs(session)
        } else {
            try? session.setActive(true)
        }
        do {
            // A run whose interface was unplugged goes on without its input (the screen says why).
            try build(AVAudioEngine(), state: st, record: record, requireInput: false)
            onRerouted?()
        } catch {
            state = nil
            recording = false
            onInterrupted?()
        }
    }

    func stop() {
        if let o = configObserver { NotificationCenter.default.removeObserver(o); configObserver = nil }
        guard let engine else { state = nil; recording = false; return }
        if tapped { engine.inputNode.removeTap(onBus: 0) }
        engine.stop()
        self.engine = nil
        state = nil
        source = nil
        monitorMixer = nil
        recording = false
        tapped = false
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

    /// The guitar comes in through an audio interface (Joe, 2026-11-14: "Won't be using the mic"). The phone's
    /// microphone only when the testing switch allows it.
    static let interfacePorts: [AVAudioSession.Port] = [.usbAudio, .lineIn, .headsetMic]

    static func interfaceInput(_ session: AVAudioSession = .sharedInstance()) -> AVAudioSessionPortDescription? {
        let inputs = (session.availableInputs ?? []) + session.currentRoute.inputs
        for type in interfacePorts { if let p = inputs.first(where: { $0.portType == type }) { return p } }
        return nil
    }

    /// The input picked by hand on the Audio screen, if it is plugged in.
    static func pickedInput(_ session: AVAudioSession = .sharedInstance()) -> AVAudioSessionPortDescription? {
        guard let uid = AudioPrefs.preferredInput else { return nil }
        return (session.availableInputs ?? []).first { $0.uid == uid }
    }

    /// The input to ask for: the one picked by hand when it is here (the phone's microphone only when allowed),
    /// else the interface.
    static func wantedInput(_ session: AVAudioSession, allowPhoneMic: Bool) -> AVAudioSessionPortDescription? {
        if let p = pickedInput(session), p.portType != .builtInMic || allowPhoneMic { return p }
        return interfaceInput(session)
    }

    static func preferInterface(_ session: AVAudioSession, allowPhoneMic: Bool) throws {
        if let port = wantedInput(session, allowPhoneMic: allowPhoneMic) {
            if session.preferredInput?.uid != port.uid { try? session.setPreferredInput(port) }
            return
        }
        guard allowPhoneMic, let mic = (session.availableInputs ?? []).first(where: { $0.portType == .builtInMic }) else {
            throw Failure.noInterface
        }
        try? session.setPreferredInput(mic)
    }

    /// After a route change with the session recording: iOS can move the input off the interface (to the phone's
    /// microphone) when Bluetooth headphones are picked for the output. Ask for the interface again, at most once
    /// every 2 s and 3 times in 10 s (RouteHub): each ask is a route change of its own. Whether iOS keeps it is read
    /// back from the route (the Audio screen says so when it does not).
    static func reassertInput(_ session: AVAudioSession = .sharedInstance(), allowPhoneMic: Bool) {
        guard session.category == .playAndRecord, !RouteHub.quiet else { return }
        guard let want = wantedInput(session, allowPhoneMic: allowPhoneMic) else { return }
        if session.currentRoute.inputs.contains(where: { $0.uid == want.uid }) { return }
        // The speaker override takes the input to the phone's microphone; take it off first.
        if speakerOverridden && want.portType != .builtInMic {
            try? session.overrideOutputAudioPort(.none)
            speakerOverridden = false
        }
        if RouteHub.mayAsk(for: want.uid) { try? session.setPreferredInput(want) }
    }

    /// Both of a two-input interface's channels (iOS can open one unless asked), then the remembered gain and mic
    /// position for the input in use. Needs an active session.
    static func applyInputPrefs(_ session: AVAudioSession) {
        if session.maximumInputNumberOfChannels >= 2 && session.inputNumberOfChannels < 2 {
            try? session.setPreferredInputNumberOfChannels(2)
        }
        guard let port = session.currentRoute.inputs.first else { return }
        let p = AudioPrefs.input(port.uid)
        if let id = p.dataSourceID, let ds = port.dataSources?.first(where: { $0.dataSourceID.intValue == id }),
           port.selectedDataSource?.dataSourceID != ds.dataSourceID {
            try? port.setPreferredDataSource(ds)
        }
        if let g = p.gain, session.isInputGainSettable { try? session.setInputGain(g) }
    }

    static func inputUID(_ session: AVAudioSession = .sharedInstance()) -> String {
        session.currentRoute.inputs.first?.uid ?? ""
    }

    static func outputUID(_ session: AVAudioSession = .sharedInstance()) -> String {
        session.currentRoute.outputs.first?.uid ?? ""
    }

    /// Puts the session in record mode (A2DP only), so the interface's input is listed. Leaves a running engine alone.
    static func prepareRecordSession() {
        let s = AVAudioSession.sharedInstance()
        if s.category != .playAndRecord {
            try? s.setCategory(.playAndRecord, mode: .measurement, options: recordOptions)
        }
        try? s.setActive(true)
    }

    /// The click plays alongside other apps' sound, unless lock-screen controls are switched on in Settings: iOS
    /// only shows an app on the lock screen and in Control Center, and only sends it pause and stop from there,
    /// when its sound is not mixed with others'.
    static var mixesWithOthers: Bool { !UserDefaults.standard.bool(forKey: "audio.lockScreen") }
    static var playOptions: AVAudioSession.CategoryOptions { mixesWithOthers ? [.mixWithOthers] : [] }
    static var recordOptions: AVAudioSession.CategoryOptions {
        mixesWithOthers ? [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP] : [.defaultToSpeaker, .allowBluetoothA2DP]
    }

    /// Before speaking with nothing running: the playback session, mixing with other apps. Leaves a running one alone.
    static func prepareSession() {
        let s = AVAudioSession.sharedInstance()
        if s.category != .playback && s.category != .playAndRecord {
            try? s.setCategory(.playback, mode: .default, options: playOptions)
        }
        try? s.setActive(true)
    }
}

/// A reusable buffer for the input tap (which runs on its own thread, one block at a time).
private final class Scratch {
    private var ptr: UnsafeMutablePointer<Float>
    private var capacity: Int
    init() { capacity = 4096; ptr = .allocate(capacity: capacity) }
    deinit { ptr.deallocate() }
    func buffer(_ n: Int) -> UnsafeMutablePointer<Float> {
        if n > capacity { ptr.deallocate(); capacity = n; ptr = .allocate(capacity: n) }
        return ptr
    }
}
