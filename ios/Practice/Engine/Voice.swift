import AVFoundation
import SwiftUI

/// The spoken intro before a drill and the short cues during one, with the phone's own voices (AVSpeechSynthesizer,
/// on the device, no network). The best installed English voice is picked by itself (Premium, then Enhanced, then
/// the default); Settings can choose another. It speaks through the app's audio session, so it mixes with the click
/// and other apps' audio instead of stopping them.
@MainActor
final class Voice: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    @Published var introOn: Bool { didSet { UserDefaults.standard.set(introOn, forKey: "voice.intro") } }
    @Published var cuesOn: Bool { didSet { UserDefaults.standard.set(cuesOn, forKey: "voice.cues") } }
    @Published var voiceID: String? { didSet { UserDefaults.standard.set(voiceID, forKey: "voice.id") } }
    @Published private(set) var speaking = false
    /// English voices, best first; filled once in the background.
    @Published private(set) var voices: [VoiceChoice] = []
    private var chosen: AVSpeechSynthesisVoice?

    private let synth = AVSpeechSynthesizer()
    private var onDone: (() -> Void)?
    // The recorded voice (VoiceClips): the clips still to play, the one playing, and a count that changes whenever
    // what is being said changes, so a clip that ends late does not carry on a line that was dropped.
    private var clipQueue: [Data] = []
    private var clipPlayer: AVAudioPlayer?
    private var clipVolume: Float = 1
    private var clipTurn = 0

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
    /// Says a line made of parts, in the recorded voice when there is a clip for every part (a pause between
    /// them), otherwise in the phone's own voice. Then calls `done`.
    func speak(parts: [IntroText.Part], cue: Bool = false, always: Bool = false, done: (() -> Void)? = nil) {
        let on = always || (cue ? cuesOn : introOn)
        guard on, !parts.isEmpty else { done?(); return }
        var clips: [Data] = []
        for p in parts {
            guard let d = VoiceClips.shared.clip(p.key, text: p.text) else { clips = []; break }
            clips.append(d)
        }
        guard !clips.isEmpty else {
            speak(parts.map(\.text).joined(separator: " "), cue: cue, always: always, done: done)
            return
        }
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        stopClips()
        let finished = onDone
        onDone = nil
        finished?()
        AudioEngine.prepareSession()
        clipQueue = clips
        clipVolume = cue ? 0.85 : 1
        onDone = done
        speaking = true
        playNextClip(turn: clipTurn)
    }

    private func stopClips() {
        clipTurn += 1
        clipQueue = []
        clipPlayer?.stop()
        clipPlayer = nil
    }

    private func playNextClip(turn: Int) {
        guard turn == clipTurn else { return }
        guard !clipQueue.isEmpty else {
            clipPlayer = nil
            speaking = false
            let d = onDone
            onDone = nil
            d?()
            return
        }
        let data = clipQueue.removeFirst()
        guard let p = try? AVAudioPlayer(data: data) else { playNextClip(turn: turn); return }
        p.delegate = self
        p.volume = clipVolume
        clipPlayer = p
        if !p.play() { playNextClip(turn: turn) }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            let turn = self.clipTurn
            // A short breath between the parts of a line.
            try? await Task.sleep(nanoseconds: 140_000_000)
            if let p = self.clipPlayer, p.isPlaying { return }
            self.playNextClip(turn: turn)
        }
    }

    func speak(_ text: String, cue: Bool = false, always: Bool = false, done: (() -> Void)? = nil) {
        let on = always || (cue ? cuesOn : introOn)
        guard on, !text.isEmpty else { done?(); return }
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        stopClips()
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
        stopClips()
        speaking = false
    }

    /// Ends the intro early and goes straight on.
    func skip() {
        let d = onDone
        onDone = nil
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        stopClips()
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
    /// One part of a spoken line: the words, and the key of the recorded clip that says them (VoiceClips).
    struct Part: Equatable {
        var key: String
        var text: String
    }

    /// A drill's intro, short and plain (Joe, 2026-11-14: "simpler voice intro. Don't need to say keep the motions
    /// small etc"): the name and the pattern, the tempo, the goal. "Triplets to sixteenths. Four and four. 120.
    /// 8 cycles." Coaching is in the drill's description on the screen, never spoken. The keys and the words are the
    /// ones scripts/make-voice.mjs records.
    static func parts(_ ex: Exercise, bpm: Int, session s: SessionSettings, scored: Bool = true) -> [Part] {
        var out = [Part(key: "say.\(ex.id)", text: ex.say.isEmpty ? "\(ex.name)." : ex.say)]
        out.append(Part(key: "bpm.\(bpm)", text: "\(bpm)."))
        switch s.kind {
        case .cycles:
            out.append(Part(key: "cycles.\(s.cycles)", text: s.cycles == 1 ? "1 cycle." : "\(s.cycles) cycles."))
        case .duration:
            out.append(Part(key: "time.\(s.seconds)", text: spokenTime(Double(s.seconds)) + "."))
        case .routine:
            out.append(Part(key: "rounds.\(s.cycles)", text: s.cycles == 1 ? "1 round." : "\(s.cycles) rounds."))
        case .endurance:
            out.append(scored ? Part(key: "endurance", text: "Endurance.") : Part(key: "open", text: "Open."))
        }
        return out
    }

    /// The same intro as one line of words.
    static func exercise(_ ex: Exercise, bpm: Int, session s: SessionSettings, guided: Bool = true, scored: Bool = true) -> String {
        parts(ex, bpm: bpm, session: s, scored: scored).map(\.text).joined(separator: " ")
    }

    /// A cue in a run: the notes a beat that are coming ("Triplets."), or a new tempo ("124.").
    static func cue(group n: Int) -> Part {
        let word: String
        switch n {
        case 0: word = "Rest."
        case 2: word = "Eighths."
        case 3: word = "Triplets."
        case 4: word = "Sixteenths."
        default: word = "\(n)."
        }
        return Part(key: "cue.\(n)", text: word)
    }

    static func cue(bpm: Int) -> Part { Part(key: "bpm.\(bpm)", text: "\(bpm).") }

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
