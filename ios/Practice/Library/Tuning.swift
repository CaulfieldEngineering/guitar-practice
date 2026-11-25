import Foundation

/// The guitar's tuning (Joe, 2026-11-24: "Let's also define the guitar's tuning"). Set for the guitar in Settings,
/// with an override per drill and per routine block. A note's pitch, its name and the tab's string names follow it.
/// `strings` is MIDI per string, the high string first (string 1 is the high E, as tab is written). It follows him
/// from device to device through the drill server (`/api/settings`).
struct Tuning: Codable, Equatable, Hashable, Identifiable {
    var id: String
    var name: String
    /// MIDI note of each open string, string 1 (the highest) first. Six or seven.
    var strings: [Int]

    static let standard = Tuning(id: "e", name: "E standard", strings: [64, 59, 55, 50, 45, 40])
    static let presets: [Tuning] = [
        standard,
        Tuning(id: "eb", name: "Eb standard", strings: [63, 58, 54, 49, 44, 39]),
        Tuning(id: "dropD", name: "Drop D", strings: [64, 59, 55, 50, 45, 38]),
        Tuning(id: "d", name: "D standard", strings: [62, 57, 53, 48, 43, 38]),
        Tuning(id: "dropC", name: "Drop C", strings: [62, 57, 53, 48, 43, 36]),
        Tuning(id: "c", name: "C standard", strings: [60, 55, 51, 46, 41, 36]),
        Tuning(id: "b", name: "B standard", strings: [59, 54, 50, 45, 40, 35]),
        Tuning(id: "seven", name: "7-string B", strings: [64, 59, 55, 50, 45, 40, 35]),
        Tuning(id: "dropA", name: "Drop A", strings: [64, 59, 55, 50, 45, 40, 33]),
    ]
    static func preset(_ id: String) -> Tuning? { presets.first { $0.id == id } }

    var isCustom: Bool { id == "custom" }

    /// A note's pitch on a string and fret; nil when the string is not on this guitar or the fret is not a number.
    func pitch(string: Int?, fret: Int?) -> Int? {
        guard let s = string, let f = fret, s >= 1, s <= strings.count, f >= 0 else { return nil }
        return strings[s - 1] + f
    }

    private static let sharps = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    private static let flats = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]

    /// "E", "F#", or with the octave, "E2". Flats where the tuning is written with flats (Eb standard, C standard).
    static func noteName(_ midi: Int, octave: Bool = false, flats: Bool = false) -> String {
        let pc = ((midi % 12) + 12) % 12
        let n = (flats ? Self.flats : Self.sharps)[pc]
        return octave ? "\(n)\(midi / 12 - 1)" : n
    }

    private var usesFlats: Bool { strings.contains { [1, 3, 6, 8, 10].contains((($0 % 12) + 12) % 12) } && ["eb", "c"].contains(id) }

    /// The open strings' names, low string first ("D A D G B E"), as the Tuning list shows them.
    var lowToHigh: String { strings.reversed().map { Tuning.noteName($0, flats: usesFlats) }.joined(separator: " ") }
    /// The name of string `s` for the tab's left edge.
    func stringName(_ s: Int) -> String {
        guard s >= 1, s <= strings.count else { return "" }
        let n = Tuning.noteName(strings[s - 1], flats: usesFlats)
        return s == 1 ? n.lowercased() : n
    }

    /// A custom tuning from these strings.
    static func custom(_ strings: [Int]) -> Tuning { Tuning(id: "custom", name: "Custom", strings: strings) }
}
