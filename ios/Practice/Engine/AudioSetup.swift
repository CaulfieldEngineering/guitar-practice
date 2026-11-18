import AVFoundation
import UIKit

/// The Audio screen's model: the inputs and outputs iOS offers, the one in use, the channel, gain and mic position,
/// a live level meter on the input, the latencies, monitoring, and what is wrong in plain words (Joe, 2026-11-16:
/// "a whole audio test area? to define the input, and the output and check levels etc", and the same night "i'm
/// struggling to get the guitar input, let alone the guitar in plus headphone out").
///
/// It listens only while the screen is open and nothing else is playing (Player's `check` mode), and only once the
/// microphone permission is granted. Route changes update it live; the engine carries on across them.
@MainActor
final class AudioSetup: ObservableObject {
    struct Port: Identifiable, Equatable {
        enum Kind { case interface, phoneMic, headset, bluetooth, other }
        var id: String          // the port's uid
        var name: String
        var kind: Kind
        var type: String        // the port type, for the details
        var sources: [Source]
    }
    struct Source: Identifiable, Equatable { var id: Int; var name: String }
    /// One line of the Input list: a device, and for a two-input interface one of its inputs.
    struct InputChoice: Identifiable, Hashable {
        var uid: String
        var channel: InputChannel?
        var name: String
        var id: String { uid + "|" + (channel?.rawValue ?? "") }
    }

    let player: Player
    let pa: PlayAlong

    @Published private(set) var inputs: [Port] = []
    @Published private(set) var input: Port?
    @Published private(set) var outputs: [Port] = []
    @Published private(set) var sourceID: Int?
    /// The channels the input offers now.
    @Published private(set) var channelCount = 1
    @Published private(set) var channel: InputChannel = .both
    @Published private(set) var gainSettable = false
    @Published private(set) var gain: Float = 1
    @Published private(set) var meter = PeakMeter()
    @Published private(set) var channelPeakDB: [Double] = [-120, -120]
    @Published private(set) var monitor = false
    @Published private(set) var monitorLevel = 0.8
    @Published private(set) var inputLatency = 0.0
    @Published private(set) var outputLatency = 0.0
    @Published private(set) var ioBuffer = 0.0
    @Published private(set) var sampleRate = 0.0
    @Published private(set) var permission: AudioFacts.Permission = .undetermined
    @Published private(set) var listening = false
    @Published private(set) var startError: String?
    @Published private(set) var problems: [AudioProblem] = []
    @Published private(set) var category = ""
    @Published private(set) var mode = ""
    @Published private(set) var options = ""
    @Published private(set) var route = Latency.currentRoute()
    /// The Input and Output lists, what is chosen in each, and one line when iOS uses something else.
    @Published private(set) var inputChoices: [InputChoice] = []
    @Published private(set) var inputChoiceID: String?
    @Published private(set) var outputChoices: [Port] = []
    @Published private(set) var outputChoiceID: String?
    @Published private(set) var inputNote: String?
    @Published private(set) var outputNote: String?
    /// Raised to open the system's list of outputs (for any output but the speaker, only iOS can switch).
    @Published private(set) var systemPicker = 0

    private var visible = false
    private var timer: Timer?
    private var lastTick = CACurrentMediaTime()
    private var silentSince: Double?
    private var observers: [NSObjectProtocol] = []

    init(player: Player, playAlong: PlayAlong) {
        self.player = player
        self.pa = playAlong
        observers.append(NotificationCenter.default.addObserver(forName: .practiceRouteChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.routeChanged() }
        })
    }

    // MARK: Open and close

    /// The screen appeared: the record session (so iOS lists the inputs at all), then listen.
    func open() {
        visible = true
        readPermission()
        AudioEngine.prepareRecordSession()
        AudioEngine.reassertInput(allowPhoneMic: pa.allowPhoneMic)
        refresh()
        startListening()
    }

    func close() {
        visible = false
        stopListening()
    }

    /// The app went to the background: stop listening, and listen again when it is back if the screen is still open.
    func pauseListening() {
        guard player.mode == .check else { return }
        stopListening()
    }

    func resumeIfVisible() {
        guard visible, player.mode == .idle else { return }
        open()
    }

    /// Listening needs the permission and nothing else playing; a run or the calibration takes the engine.
    func startListening() {
        guard visible, permission == .granted else { refresh(); return }
        guard player.mode == .idle || player.mode == .check else { refresh(); return }
        startError = nil
        if player.mode != .check {
            do {
                try player.startCheck()
            } catch {
                startError = error.localizedDescription
                listening = false
                refresh()
                return
            }
        }
        listening = player.mode == .check && player.audio.tapped
        meter.reset()
        silentSince = nil
        startTimer()
        refresh()
    }

    func stopListening() {
        timer?.invalidate(); timer = nil
        player.stopCheck()
        listening = false
        meter.reset()
        channelPeakDB = [-120, -120]
    }

    // MARK: Choices

    func selectInput(_ uid: String) {
        RouteHub.picked()
        AudioPrefs.preferredInput = uid
        let s = AVAudioSession.sharedInstance()
        if let port = s.availableInputs?.first(where: { $0.uid == uid }) {
            AudioPrefs.setInputName(port.portName, for: uid)
            // The phone's microphone picked by hand is allowed from then on (the switch under Advanced says so).
            if port.portType == .builtInMic && !pa.allowPhoneMic { pa.allowPhoneMic = true }
            // The speaker override holds the phone's microphone: an interface picked by hand takes it off.
            if port.portType != .builtInMic && AudioEngine.speakerOverridden { AudioEngine.applyOutputChoice(s) }
            if RouteHub.mayAsk(for: uid) { try? s.setPreferredInput(port) }
        }
        AudioEngine.applyInputPrefs(s)
        restartIfListening()
        refresh()
        pa.routeChanged()
    }

    func select(_ c: InputChoice) {
        selectInput(c.uid)
        if let ch = c.channel { setChannel(ch) }
        refresh()
    }

    /// The output picked by hand. The speaker the app sets itself; for another output iOS's own list opens, since
    /// only it can move the sound there, and the line under the row says if the sound ended up elsewhere.
    func selectOutput(_ id: String) {
        RouteHub.picked()
        AudioPrefs.preferredOutput = id
        let s = AVAudioSession.sharedInstance()
        if id == AudioPrefs.speakerID { AudioEngine.prepareRecordSession() }
        AudioEngine.applyOutputChoice(s)
        if id != AudioPrefs.speakerID && AudioEngine.outputUID(s) != id { systemPicker += 1 }
        refresh()
    }

    func selectSource(_ id: Int) {
        let s = AVAudioSession.sharedInstance()
        guard let port = s.currentRoute.inputs.first,
              let ds = port.dataSources?.first(where: { $0.dataSourceID.intValue == id }) else { return }
        try? port.setPreferredDataSource(ds)
        var p = AudioPrefs.input(port.uid)
        p.dataSourceID = id
        AudioPrefs.setInput(p, for: port.uid)
        refresh()
    }

    func setChannel(_ c: InputChannel) {
        let uid = AudioEngine.inputUID()
        guard !uid.isEmpty else { return }
        var p = AudioPrefs.input(uid)
        p.channel = c
        AudioPrefs.setInput(p, for: uid)
        channel = c
        restartIfListening()
    }

    func setGain(_ g: Float) {
        let s = AVAudioSession.sharedInstance()
        guard s.isInputGainSettable else { return }
        try? s.setInputGain(g)
        gain = s.inputGain
        let uid = AudioEngine.inputUID()
        var p = AudioPrefs.input(uid)
        p.gain = g
        AudioPrefs.setInput(p, for: uid)
    }

    func setMonitor(_ on: Bool) {
        let uid = AudioEngine.outputUID()
        var p = AudioPrefs.output(uid)
        p.monitor = on
        AudioPrefs.setOutput(p, for: uid)
        monitor = on
        restartIfListening()
    }

    func setMonitorLevel(_ v: Double) {
        let uid = AudioEngine.outputUID()
        var p = AudioPrefs.output(uid)
        p.monitorLevel = v
        AudioPrefs.setOutput(p, for: uid)
        monitorLevel = v
        player.audio.monitorVolume = Float(v)
    }

    func playTone() { player.playTestTone() }
    func playClicks() { player.playTestClicks() }

    func perform(_ action: AudioProblem.Action) {
        switch action {
        case .openSettings:
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        case .askPermission:
            AVAudioApplication.requestRecordPermission { ok in
                Task { @MainActor in
                    self.readPermission()
                    if ok { self.startListening() } else { self.refresh() }
                }
            }
        case .useChannel(let c):
            setChannel(c)
        }
    }

    /// The calibration takes the engine; listening comes back when it is over (the screen calls startListening).
    func calibrate() {
        stopListening()
        pa.startCalibration()
    }

    private func restartIfListening() {
        guard player.mode == .check else { return }
        player.audio.rebuild()
        listening = player.audio.tapped
        meter.reset()
        silentSince = nil
    }

    // MARK: Reading the session

    private func readPermission() {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: permission = .granted
        case .denied: permission = .denied
        default: permission = .undetermined
        }
    }

    private func routeChanged() {
        AudioEngine.reassertInput(allowPhoneMic: pa.allowPhoneMic)
        refresh()
        guard visible else { return }
        // The engine rebuilds itself on the new route; the meter starts over.
        meter.reset()
        silentSince = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.visible else { return }
            self.listening = self.player.mode == .check && self.player.audio.tapped
            if self.player.mode == .idle { self.startListening() }
            self.refresh()
        }
    }

    static func kind(_ t: AVAudioSession.Port) -> Port.Kind {
        switch t {
        case .usbAudio, .lineIn: return .interface
        case .headsetMic, .headphones: return .headset
        case .builtInMic: return .phoneMic
        case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP: return .bluetooth
        default: return .other
        }
    }

    private static func port(_ p: AVAudioSessionPortDescription) -> Port {
        Port(id: p.uid, name: p.portName, kind: kind(p.portType), type: p.portType.rawValue,
             sources: (p.dataSources ?? []).map { Source(id: $0.dataSourceID.intValue, name: $0.dataSourceName) })
    }

    func refresh() {
        let s = AVAudioSession.sharedInstance()
        let r = s.currentRoute
        inputs = (s.availableInputs ?? []).map(AudioSetup.port)
        input = r.inputs.first.map(AudioSetup.port)
        outputs = r.outputs.map(AudioSetup.port)
        sourceID = r.inputs.first?.selectedDataSource?.dataSourceID.intValue
        channelCount = max(r.inputs.first?.channels?.count ?? 0, s.inputNumberOfChannels)
        channel = AudioPrefs.input(AudioEngine.inputUID()).channel
        gainSettable = s.isInputGainSettable
        gain = s.inputGain
        let out = AudioPrefs.output(AudioEngine.outputUID())
        monitor = out.monitor
        monitorLevel = out.monitorLevel
        inputLatency = s.inputLatency
        outputLatency = s.outputLatency
        ioBuffer = s.ioBufferDuration
        sampleRate = s.sampleRate
        category = s.category.rawValue.replacingOccurrences(of: "AVAudioSessionCategory", with: "")
        mode = s.mode.rawValue.replacingOccurrences(of: "AVAudioSessionMode", with: "")
        options = AudioSetup.describe(s.categoryOptions)
        route = Latency.currentRoute()
        for o in r.outputs where o.portType != .builtInSpeaker && o.portType != .builtInReceiver {
            AudioPrefs.sawOutput(o.uid, name: o.portName, type: o.portType.rawValue)
        }
        buildChoices(s)
        problems = AudioDiagnosis.problems(facts)
    }

    private func buildChoices(_ s: AVAudioSession) {
        let current = s.currentRoute.inputs.first
        var list: [InputChoice] = []
        for p in s.availableInputs ?? [] {
            let n = p.uid == current?.uid ? channelCount : (p.channels?.count ?? 1)
            if n >= 2 {
                list.append(InputChoice(uid: p.uid, channel: .first, name: L.inputOf(p.portName, 1)))
                list.append(InputChoice(uid: p.uid, channel: .second, name: L.inputOf(p.portName, 2)))
                list.append(InputChoice(uid: p.uid, channel: .both, name: L.inputsBoth(p.portName)))
            } else {
                list.append(InputChoice(uid: p.uid, channel: nil, name: p.portName))
            }
        }
        inputChoices = list
        if let cur = current {
            let ch = channel
            inputChoiceID = list.first(where: { $0.uid == cur.uid && ($0.channel == nil || $0.channel == ch) })?.id
        } else {
            inputChoiceID = nil
        }

        var outs = [Port(id: AudioPrefs.speakerID, name: L.phoneSpeaker, kind: .other, type: AVAudioSession.Port.builtInSpeaker.rawValue, sources: [])]
        for (uid, o) in AudioPrefs.seenOutputs.sorted(by: { $0.value.name < $1.value.name }) {
            outs.append(Port(id: uid, name: o.name, kind: AudioSetup.kind(AVAudioSession.Port(rawValue: o.type)), type: o.type, sources: []))
        }
        outputChoices = outs
        let out = s.currentRoute.outputs.first
        if out?.portType == .builtInSpeaker || out?.portType == .builtInReceiver {
            outputChoiceID = AudioPrefs.speakerID
        } else {
            outputChoiceID = out?.uid
        }

        var c = ChoiceFacts()
        let picked = AudioPrefs.preferredInput
        c.pickedInput = picked
        let avail = s.availableInputs ?? []
        let pickedPort = avail.first(where: { $0.uid == picked })
        c.pickedInputConnected = pickedPort != nil
        c.pickedInputName = pickedPort?.portName ?? AudioPrefs.inputName(picked)
        c.inputUID = current?.uid
        c.inputName = current?.portName
        c.inputIsInterface = route.inputIsInterface
        c.pickedOutput = AudioPrefs.preferredOutput
        if let po = c.pickedOutput, let seen = AudioPrefs.seenOutputs[po] {
            c.pickedOutputName = seen.name
            c.pickedOutputIsBluetooth = AudioSetup.kind(AVAudioSession.Port(rawValue: seen.type)) == .bluetooth
        }
        c.outputUID = out?.uid
        c.outputName = out?.portName
        c.outputIsSpeaker = outputChoiceID == AudioPrefs.speakerID
        c.outputIsInterface = route.outputIsInterface
        c.recording = s.category == .playAndRecord
        inputNote = RouteHub.gaveUp(on: picked) && c.pickedInputConnected && picked != current?.uid
            ? L.replugInput(c.pickedInputName ?? L.pickedDevice) : AudioDiagnosis.inputNote(c)
        outputNote = RouteHub.note ?? AudioDiagnosis.outputNote(c)
    }

    var facts: AudioFacts {
        var f = AudioFacts()
        f.permission = permission
        f.interfaceAvailable = AudioEngine.interfaceInput() != nil
        f.inputIsInterface = route.inputIsInterface
        f.inputIsBuiltInMic = route.inputIsBuiltInMic
        f.bluetoothOutput = route.bluetoothOutput
        f.outputIsInterface = route.outputIsInterface
        f.handsFree = route.handsFree
        f.channels = channelCount
        f.channel = channel
        f.gainSettable = gainSettable
        f.gain = gain
        f.listening = listening
        f.verdict = meter.verdict
        f.silentSeconds = silentSince.map { CACurrentMediaTime() - $0 } ?? 0
        if channel != .both && channelCount >= 2 {
            let other = channel == .first ? 1 : 0
            if channelPeakDB[other] > LevelVerdict.tooQuietBelow { f.signalOnOther = other + 1 }
        }
        return f
    }

    static func describe(_ o: AVAudioSession.CategoryOptions) -> String {
        var words: [String] = []
        if o.contains(.mixWithOthers) { words.append("mix with others") }
        if o.contains(.defaultToSpeaker) { words.append("speaker by default") }
        if o.contains(.allowBluetoothA2DP) { words.append("Bluetooth A2DP") }
        if o.contains(.allowBluetooth) { words.append("Bluetooth hands-free") }
        if o.contains(.duckOthers) { words.append("duck others") }
        return words.isEmpty ? L.none : words.joined(separator: ", ")
    }

    // MARK: The meter

    private func startTimer() {
        timer?.invalidate()
        lastTick = CACurrentMediaTime()
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(0.25, now - lastTick)
        lastTick = now
        guard player.mode == .check else {
            // The calibration or a run took the engine.
            if listening { listening = false; meter.reset() }
            return
        }
        let r = player.audio.takeMeter()
        var m = meter
        m.update(peak: r.peak, clipped: r.clipped, dt: dt)
        meter = m
        // Each raw channel, held for a second so a note is seen.
        for k in 0..<2 {
            let db = AudioLevel.dB(r.channelPeaks[k])
            channelPeakDB[k] = db >= channelPeakDB[k] ? db : max(db, channelPeakDB[k] - 30 * dt)
        }
        if m.verdict == .noSignal { if silentSince == nil { silentSince = now } } else { silentSince = nil }
        let p = AudioDiagnosis.problems(facts)
        if p != problems { problems = p }
    }
}
