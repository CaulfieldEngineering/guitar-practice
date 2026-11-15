import AVFoundation
import SwiftUI

/// The spoken intro before a drill and the short cues during one, with the phone's own voices (AVSpeechSynthesizer,
/// on the device, no network). The best installed English voice is picked by itself (Premium, then Enhanced, then
/// the default); Settings can choose another. It speaks through the app's audio session, so it mixes with the click
/// and other apps' audio instead of stopping them.
@MainActor
final class Voice: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var introOn: Bool { didSet { UserDefaults.standard.set(introOn, forKey: "voice.intro") } }
    @Published var cuesOn: Bool { didSet { UserDefaults.standard.set(cuesOn, forKey: "voice.cues") } }
    @Published var voiceID: String? { didSet { UserDefaults.standard.set(voiceID, forKey: "voice.id") } }
    @Published private(set) var speaking = false
    /// English voices, best first; filled once in the background.
    @Published private(set) var voices: [VoiceChoice] = []
    private var chosen: AVSpeechSynthesisVoice?

    private let synth = AVSpeechSynthesizer()
    private var onDone: (() -> Void)?

    override init() {
        let d = UserDefaults.standard
        introOn = d.object(forKey: "voice.intro") as? Bool ?? true
        cuesOn = d.object(forKey: "voice.cues") as? Bool ?? false
        voiceID = d.string(forKey: "voice.id")
        super.init()
        synth.delegate = self
        synth.usesApplicationAudioSession = true
        Task.detached(priority: .utility) {
            let list = Voice.englishVoices
            let choices = list.map { VoiceChoice(id: $0.identifier, name: $0.name, quality: Voice.qualityName($0.quality)) }
            let best = list.first
            await MainActor.run {
                self.voices = choices
                self.fallback = best
            }
        }
    }

    private var fallback: AVSpeechSynthesisVoice?

    /// English voices, best first.
    nonisolated static var englishVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }.sorted { a, b in
            if rank(a.quality) != rank(b.quality) { return rank(a.quality) > rank(b.quality) }
            if (a.language == "en-US") != (b.language == "en-US") { return a.language == "en-US" }
            return a.name < b.name
        }
    }

    nonisolated static func rank(_ q: AVSpeechSynthesisVoiceQuality) -> Int {
        switch q { case .premium: return 3; case .enhanced: return 2; default: return 1 }
    }

    nonisolated static func qualityName(_ q: AVSpeechSynthesisVoiceQuality) -> String {
        switch q { case .premium: return "Premium"; case .enhanced: return "Enhanced"; default: return "Standard" }
    }

    var voice: AVSpeechSynthesisVoice? {
        if let c = chosen, c.identifier == voiceID { return c }
        if let id = voiceID, let v = AVSpeechSynthesisVoice(identifier: id) { chosen = v; return v }
        return fallback ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    /// The voice in use, for the picker (the chosen one, else the best found).
    var selectedID: String { voiceID ?? fallback?.identifier ?? voices.first?.id ?? "" }

    /// Speaks, then calls `done` (at once if the voice is off or there is nothing to say).
    func speak(_ text: String, cue: Bool = false, always: Bool = false, done: (() -> Void)? = nil) {
        let on = always || (cue ? cuesOn : introOn)
        guard on, !text.isEmpty else { done?(); return }
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        let finished = onDone
        onDone = nil
        finished?()
        AudioEngine.prepareSession()
        let u = AVSpeechUtterance(string: text)
        u.voice = voice
        u.rate = cue ? 0.52 : 0.5
        u.prefersAssistiveTechnologySettings = false
        u.volume = cue ? 0.8 : 1
        onDone = done
        speaking = true
        synth.speak(u)
    }

    /// Stops speaking; a pending `done` is dropped (the run it would start was called off).
    func stop() {
        onDone = nil
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        speaking = false
    }

    /// Ends the intro early and goes straight on.
    func skip() {
        let d = onDone
        onDone = nil
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        speaking = false
        d?()
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in
            self.speaking = false
            let d = self.onDone
            self.onDone = nil
            d?()
        }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        Task { @MainActor in self.speaking = false }
    }
}

struct VoiceChoice: Identifiable, Hashable { var id: String; var name: String; var quality: String }

/// The words of an intro: the drill's own text from its data, then the tempo and the goal.
enum IntroText {
    static func exercise(_ ex: Exercise, bpm: Int, session s: SessionSettings, guided: Bool, scored: Bool = true) -> String {
        let what = ex.intro.isEmpty ? "\(ex.name). \(ex.detail)" : ex.intro
        let goal: String
        switch s.kind {
        case .cycles: goal = "\(s.cycles) times through."
        case .duration: goal = "For \(spokenTime(Double(s.seconds)))."
        case .routine:
            var r = ex.routine
            r.rounds = max(1, s.cycles)
            r.stepBPM = s.ladderStep
            r.countInBeats = 0
            goal = (s.cycles > 1 ? "\(s.cycles) rounds, " : "") + "\(spokenTime(r.plan.total)) in all."
        case .endurance:
            goal = scored ? "Endurance: keep your accuracy at \(s.targetPercent) percent or better for as long as you can."
                : "Keep going until you stop it."
        }
        let ladder = s.kind == .routine ? (s.ladderStep != 0 && s.cycles > 1 ? " \(abs(s.ladderStep)) \(s.ladderStep > 0 ? "faster" : "slower") each round." : "")
            : s.ladderStep > 0 ? (scored ? " Up \(s.ladderStep) each time you pass a cycle." : " Up \(s.ladderStep) each cycle.") : ""
        let mode = guided ? "Guided: play along with the guitar." : "Solo: just the click."
        let unscored = scored ? "" : " The audio input is off, so nothing is scored."
        return "\(what) \(bpm) beats per minute. \(goal)\(ladder) \(mode)\(unscored) Here is the count."
    }

    static func routine(_ r: Routine) -> String {
        let what = r.intro.isEmpty ? (r.notes.isEmpty ? r.name + "." : "\(r.name). \(r.notes)") : r.intro
        return "\(what) \(spokenTime(r.plan.total)) in all."
    }

    static func spokenTime(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        let m = s / 60, r = s % 60
        if m == 0 { return "\(r) seconds" }
        let mins = m == 1 ? "1 minute" : "\(m) minutes"
        return r == 0 ? mins : "\(mins) \(r) seconds"
    }

    /// A short cue at the start of a routine interval.
    static func cue(_ s: Segment, next: Segment? = nil) -> String {
        switch s.kind {
        case .play: return s.title == "Play" ? "\(Int(s.bpm))" : "\(s.title), \(Int(s.bpm))"
        case .rest: return next.map { $0.kind == .play ? "Rest. Next, \(Int($0.bpm))." : "Rest." } ?? "Rest."
        case .motion: return s.title
        case .countIn: return ""
        }
    }
}
