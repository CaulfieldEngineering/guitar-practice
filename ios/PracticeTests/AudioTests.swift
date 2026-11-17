import AVFoundation
import XCTest
@testable import Practice

/// The Audio screen's maths and words: levels in dBFS, the meter's hold and clip light, the channel picked from a
/// two-input interface, what is remembered per device, and the plain-words check.
final class LevelMathTests: XCTestCase {
    func testDecibels() {
        XCTAssertEqual(AudioLevel.dB(1), 0, accuracy: 1e-9)
        XCTAssertEqual(AudioLevel.dB(0.5), -6.0206, accuracy: 1e-3)
        XCTAssertEqual(AudioLevel.dB(0.001), -60, accuracy: 1e-6)
        XCTAssertEqual(AudioLevel.dB(0), -120)
        XCTAssertEqual(AudioLevel.dB(-1), -120)
    }

    func testMeterFraction() {
        XCTAssertEqual(AudioLevel.fraction(-60), 0)
        XCTAssertEqual(AudioLevel.fraction(-90), 0)
        XCTAssertEqual(AudioLevel.fraction(-30), 0.5, accuracy: 1e-9)
        XCTAssertEqual(AudioLevel.fraction(0), 1)
        XCTAssertEqual(AudioLevel.fraction(6), 1)
    }

    func testRmsAndPeakOfASine() {
        let s = (0..<4800).map { Float(0.5 * sin(2 * Double.pi * 440 * Double($0) / 48000)) }
        let m = AudioLevel.measure(s)
        XCTAssertEqual(m.peak, 0.5, accuracy: 1e-3)
        XCTAssertEqual(m.rms, 0.5 / Float(2).squareRoot(), accuracy: 1e-3)
        XCTAssertEqual(AudioLevel.measure([]).rms, 0)
    }

    func testReadingsAddUpAndClipOnlyAtTheTop() {
        var r = MeterReading()
        r.add([0.1, -0.2])
        r.add([0.3])
        XCTAssertEqual(r.frames, 3)
        XCTAssertEqual(r.peak, 0.3, accuracy: 1e-6)
        XCTAssertEqual(r.rms, Float(((0.01 + 0.04 + 0.09) / 3.0).squareRoot()), accuracy: 1e-6)
        XCTAssertFalse(r.clipped)
        r.add([-0.99])
        XCTAssertTrue(r.clipped)
        var raw = MeterReading()
        [Float(0.2), 1.0].withUnsafeBufferPointer { raw.addChannelPeak(1, $0) }
        XCTAssertEqual(raw.channelPeaks[1], 1)
        XCTAssertTrue(raw.clipped, "a raw channel at the top is clipping even when the mix is not")
    }

    func testChannelPick() {
        let one: [Float] = [0.1, 0.2, 0.3], two: [Float] = [0.5, 0.5, 0.9]
        XCTAssertEqual(InputChannel.mix([one, two], pick: .first), one)
        XCTAssertEqual(InputChannel.mix([one, two], pick: .second), two)
        let both = InputChannel.mix([one, two], pick: .both)
        XCTAssertEqual(both[0], 0.6, accuracy: 1e-6)
        XCTAssertEqual(both[2], 1, "the sum is held at full scale")
        // A mono interface: input 2 and both fall back to input 1.
        XCTAssertEqual(InputChannel.mix([one], pick: .second), one)
        XCTAssertEqual(InputChannel.mix([one], pick: .both), one)
        // The guitar on input 2 alone is heard with Both, the default.
        XCTAssertEqual(InputChannel.mix([[0, 0, 0], two], pick: .both), two)
        XCTAssertEqual(InputPrefs().channel, .both)
    }

    func testVerdicts() {
        XCTAssertEqual(LevelVerdict.from(recentPeakDB: -80, clipping: false), .noSignal)
        XCTAssertEqual(LevelVerdict.from(recentPeakDB: -35, clipping: false), .tooQuiet)
        XCTAssertEqual(LevelVerdict.from(recentPeakDB: -12, clipping: false), .good)
        XCTAssertEqual(LevelVerdict.from(recentPeakDB: -12, clipping: true), .clipping)
    }

    func testPeakHoldWaitsThenFalls() {
        var m = PeakMeter()
        m.update(peak: 0.5, clipped: false, dt: 1.0 / 30)
        let top = AudioLevel.dB(0.5)
        XCTAssertEqual(m.holdDB, top, accuracy: 1e-9)
        XCTAssertEqual(m.levelDB, top, accuracy: 1e-9)
        // Silence for a second: the bar falls, the tick holds.
        for _ in 0..<30 { m.update(peak: 0, clipped: false, dt: 1.0 / 30) }
        XCTAssertEqual(m.holdDB, top, accuracy: 1e-9)
        XCTAssertLessThan(m.levelDB, top - 30)
        // Past the hold time it falls at the release rate.
        for _ in 0..<30 { m.update(peak: 0, clipped: false, dt: 1.0 / 30) }
        XCTAssertLessThan(m.holdDB, top - 5)
        XCTAssertEqual(m.verdict, .good, "the readout remembers the last few seconds")
        for _ in 0..<120 { m.update(peak: 0, clipped: false, dt: 1.0 / 30) }
        XCTAssertEqual(m.verdict, .noSignal)
    }

    func testClipLightStaysOnForAMoment() {
        var m = PeakMeter()
        m.update(peak: 1, clipped: true, dt: 0.03)
        XCTAssertTrue(m.clipping)
        XCTAssertEqual(m.verdict, .clipping)
        for _ in 0..<30 { m.update(peak: 0.3, clipped: false, dt: 1.0 / 30) }
        XCTAssertTrue(m.clipping, "still lit after a second")
        for _ in 0..<45 { m.update(peak: 0.3, clipped: false, dt: 1.0 / 30) }
        XCTAssertFalse(m.clipping)
    }
}

final class AudioPrefsTests: XCTestCase {
    private var suite: UserDefaults!

    override func setUp() {
        suite = UserDefaults(suiteName: "audio-prefs-tests")
        suite.removePersistentDomain(forName: "audio-prefs-tests")
        AudioPrefs.defaults = suite
    }

    override func tearDown() { AudioPrefs.defaults = .standard }

    func testRememberedPerDevice() {
        XCTAssertEqual(AudioPrefs.input("usb-1"), InputPrefs())
        AudioPrefs.setInput(InputPrefs(channel: .second, gain: 0.7, dataSourceID: nil), for: "usb-1")
        AudioPrefs.setInput(InputPrefs(channel: .first), for: "usb-2")
        XCTAssertEqual(AudioPrefs.input("usb-1").channel, .second)
        XCTAssertEqual(AudioPrefs.input("usb-1").gain, 0.7)
        XCTAssertEqual(AudioPrefs.input("usb-2").channel, .first)
        AudioPrefs.setOutput(OutputPrefs(appVolume: 0.4, monitor: true, monitorLevel: 0.5), for: "shokz")
        XCTAssertEqual(AudioPrefs.output("shokz").appVolume, 0.4)
        XCTAssertTrue(AudioPrefs.output("shokz").monitor)
        XCTAssertFalse(AudioPrefs.output("interface").monitor)
        AudioPrefs.preferredInput = "usb-1"
        XCTAssertEqual(AudioPrefs.preferredInput, "usb-1")
        AudioPrefs.sawOutput("shokz", name: "OpenRun Pro by Shokz", type: AVAudioSession.Port.bluetoothA2DP.rawValue)
        XCTAssertEqual(AudioPrefs.seenOutputs["shokz"]?.name, "OpenRun Pro by Shokz")
    }
}

final class AudioDiagnosisTests: XCTestCase {
    private func kinds(_ f: AudioFacts) -> [AudioProblem.Kind] { AudioDiagnosis.problems(f).map(\.kind) }

    func testNoInterfaceGivesTheHardwareSteps() {
        let p = AudioDiagnosis.problems(AudioFacts(interfaceAvailable: false))
        XCTAssertEqual(p.first?.kind, .noInterface)
        XCTAssertTrue(p.first?.steps.contains(L.diagStepPower) ?? false)
        XCTAssertTrue(p.first?.steps.contains(L.diagStepClassCompliant) ?? false)
    }

    func testPermission() {
        XCTAssertEqual(kinds(AudioFacts(permission: .denied, interfaceAvailable: true, inputIsInterface: true)).first, .permissionDenied)
        let ask = AudioDiagnosis.problems(AudioFacts(permission: .undetermined, interfaceAvailable: true, inputIsInterface: true))
        XCTAssertEqual(ask.first?.action, .askPermission)
    }

    func testBluetoothLimitAndTheWorkaround() {
        let limit = AudioDiagnosis.problems(AudioFacts(interfaceAvailable: true, inputIsInterface: false, inputIsBuiltInMic: true, bluetoothOutput: true))
        XCTAssertEqual(limit.first?.kind, .bluetoothLimit)
        XCTAssertEqual(limit.first?.steps, [L.diagStepTransmitter])
        // The interface in and the Shokz out together is not a problem.
        XCTAssertFalse(kinds(AudioFacts(interfaceAvailable: true, inputIsInterface: true, bluetoothOutput: true)).contains(.bluetoothLimit))
    }

    func testSilentInterfaceChecklist() {
        var f = AudioFacts(interfaceAvailable: true, inputIsInterface: true, outputIsInterface: false, channels: 2, channel: .first,
                           listening: true, verdict: .noSignal, silentSeconds: 5)
        let p = AudioDiagnosis.problems(f)
        XCTAssertEqual(p.last?.kind, .noSignal)
        XCTAssertTrue(p.last?.steps.contains(L.diagStepBoth) ?? false, "input 1 picked on a two-input interface: try both")
        // Not yet: two seconds of quiet is just not playing.
        f.silentSeconds = 1
        XCTAssertFalse(kinds(f).contains(.noSignal))
        // The guitar is on input 2: say so, with the one tap that fixes it.
        f.signalOnOther = 2
        let other = AudioDiagnosis.problems(f).last
        XCTAssertEqual(other?.kind, .otherInput)
        XCTAssertEqual(other?.action, .useChannel(.second))
    }

    func testGainAndLevels() {
        let base = AudioFacts(interfaceAvailable: true, inputIsInterface: true, listening: true)
        var f = base; f.gainSettable = true; f.gain = 0; f.verdict = .noSignal
        XCTAssertTrue(kinds(f).contains(.gainZero))
        f = base; f.verdict = .clipping
        XCTAssertEqual(kinds(f).last, .clipping)
        f = base; f.verdict = .tooQuiet
        XCTAssertEqual(kinds(f).last, .tooQuiet)
        f = base; f.verdict = .good
        XCTAssertTrue(kinds(f).isEmpty)
    }

    func testAChoiceIOSDidNotTakeIsSaidInOneLine() {
        var c = ChoiceFacts(pickedInput: "usb", pickedInputName: "iRig", pickedInputConnected: false, inputUID: "mic", inputName: "iPhone Microphone")
        XCTAssertEqual(AudioDiagnosis.inputNote(c), L.fallbackInputMissing("iRig", "iPhone Microphone"))
        c.inputUID = "usb"
        XCTAssertNil(AudioDiagnosis.inputNote(c))

        var o = ChoiceFacts(inputIsInterface: true, pickedOutput: "shokz", pickedOutputName: "OpenRun Pro", pickedOutputIsBluetooth: true,
                            outputUID: "usb", outputName: "iRig", outputIsInterface: true)
        XCTAssertEqual(AudioDiagnosis.outputNote(o), L.fallbackBluetoothUSB("OpenRun Pro", "iRig"))
        o.outputUID = "shokz"
        XCTAssertNil(AudioDiagnosis.outputNote(o))
        o = ChoiceFacts(pickedOutput: AudioPrefs.speakerID, outputUID: "usb", outputName: "iRig", outputIsSpeaker: false)
        XCTAssertEqual(AudioDiagnosis.outputNote(o), L.fallbackSpeaker("iRig"))
        o.outputIsSpeaker = true
        XCTAssertNil(AudioDiagnosis.outputNote(o))
    }
}

/// The drill screen opens the record session when the audio input is on: in playback mode iOS lists no input at all,
/// which is what his phone showed on 2026-11-16 ("In: No input" with the interface plugged in).
@MainActor
final class InputSessionTests: XCTestCase {
    func testDrillScreenPutsTheSessionInRecordMode() throws {
        let s = AVAudioSession.sharedInstance()
        try s.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        let pa = PlayAlong(player: Player(), history: History(inMemory: true))
        pa.audioInput = true
        pa.prepareInput()
        XCTAssertEqual(s.category, .playAndRecord)
        XCTAssertEqual(s.mode, .measurement)
        XCTAssertTrue(s.categoryOptions.contains(.allowBluetoothA2DP))
        XCTAssertFalse(s.categoryOptions.contains(.allowBluetooth), "never hands-free: the Shokz stay in listening mode")
    }
}
