#pragma once
// The drill schema (version 1), the same as the iPhone app's (ios/Practice/Library/Exercise.swift) and read from the
// same catalog the drill server serves (catalog/). A run is built a cycle at a time (RunBuilder), so the next cycle's
// tempo can follow the last result. Drills made of timed blocks (`segments`) are left out, as on the phone since 0.1.7.
#include <juce_core/juce_core.h>
#include "Scoring.h"
#include "TempoPlan.h"
#include <map>

namespace practice {

struct GridPosition {
    int beat = 0, step = 0, of = 1;
    double beats() const { return beat + (double) step / (double) std::max (1, of); }
};

struct NoteSpec {
    GridPosition at;
    int string = 0;      // 0: none
    int fret = -1;
    Pick pick = Pick::none;
    bool accent = false;
    bool x = true;       // an X note: any pitch counts ("x": true, "fret": "x", or no fret)
};

/// The guitar's tuning (Joe, 2026-11-24: "Let's also define the guitar's tuning"): MIDI per open string, string 1
/// (the high E) first; six or seven. The same presets and shape as the phone's Library/Tuning.swift; it follows him
/// through the drill server (/api/settings).
struct Tuning {
    juce::String id = "e", name = "E standard";
    std::vector<int> strings { 64, 59, 55, 50, 45, 40 };
    static const std::vector<Tuning>& presets();
    static Tuning standard() { return {}; }
    static std::optional<Tuning> preset (const juce::String& id);
    static Tuning custom (std::vector<int> strings);
    bool isCustom() const { return id == "custom"; }
    std::optional<int> pitch (int string, int fret) const;
    static juce::String noteName (int midi, bool octave = false, bool flats = false);
    juce::String lowToHigh() const;
    juce::String stringName (int s) const;
    juce::var toVar() const;
    static std::optional<Tuning> fromVar (const juce::var& v);
    bool operator== (const Tuning& o) const { return id == o.id && strings == o.strings; }
    bool operator!= (const Tuning& o) const { return ! (*this == o); }
};

struct TempoRule { int start = 100, min = 30, max = 300, stepOnPass = 4; };

/// How a run is shaped: cycles, a time, or endurance (hold the target accuracy over the last few cycles).
struct SessionSettings {
    enum class Kind { cycles, duration, endurance, challenge };
    enum class Accent { one, groups, off };
    enum class ClickSound { click, wood, beep, rim };
    Kind kind = Kind::cycles;
    int cycles = 4;
    int seconds = 60;
    int targetPercent = 85;
    double toleranceMs = 30;   // still read, no longer used (the windows belong to ScoringConfig)
    int windowCycles = 2;
    int ladderStep = 0;
    TempoPlan tempoPlan;           // ascending tempo (0.3.0)
    int capSeconds = 0;            // Challenge: no more than this in all (0: no cap)
    int countInBars = 1;
    Accent accent = Accent::one;
    ClickSound clickSound = ClickSound::click;
    double clickLevel = 1;
    int gapEvery = 0;              // the gap trainer: every Nth bar has no click (0: off)
    std::optional<Tuning> tuning;  // this drill's or block's own; none: the guitar's

    bool endsItself() const { return kind == Kind::endurance || kind == Kind::challenge; }
    static juce::String kindName (Kind k);
    static Kind kindFrom (const juce::String& s);
    static SessionSettings fromVar (const juce::var& v, SessionSettings base = {});
    juce::var toVar() const;
    bool operator== (const SessionSettings& o) const;
    static constexpr double enduranceCap = 20 * 60;
};

struct Level {
    juce::String name;
    int bpm = 0;
    std::optional<SessionSettings> session;
};

struct Drill {
    int schema = 1;
    int version = 1;
    juce::String id, name, detail, shortName, say, category = "Right hand";
    int beatsPerBar = 4;
    int cycleBeats = 1;
    std::vector<NoteSpec> notes;
    TempoRule tempo;
    ScoringRule scoring;
    SessionSettings session;
    std::vector<Level> levels;
    bool timedBlocks = false;   // a drill of timed blocks: not shown, as on the phone
    bool archived = false;      // kept in the catalog, not offered (2026-11-24: all but the triplets drill)
    bool pitchFree = false;     // "pitch": "x": every note is an X note
    bool hasPitchedNotes() const;

    /// Reads one drill; nullopt when it does not decode (the rest of its file still loads).
    static std::optional<Drill> fromVar (const juce::var& v);
    static std::vector<NoteSpec> expand (const std::vector<int>& groups, bool accentFirst);

    juce::String tableName() const { return shortName.isNotEmpty() ? shortName : name; }
    /// The pattern in a few characters: "16", "3→4", "16·rest", "mix".
    juce::String glyph() const;
    std::vector<Note> runNotes (double bpm, double start, double seconds) const;
    double shortestGap (double bpm) const;
    double window (double bpm) const;
    std::vector<int> groupSizes() const;

    static Drill fallback();
};

/// What the audio engine plays at a time: a click, a count-in, the guide guitar, the end bell.
enum class ClickKind { accent, beat, sub, countIn, change, rest, done, pluck, pluckAccent,
                       woodAccent, woodBeat, woodSub, beepAccent, beepBeat, beepSub, rimAccent, rimBeat, rimSub, chime };
constexpr int clickKindCount = (int) ClickKind::chime + 1;
/// A grid click (accent, beat, sub) in another sound.
ClickKind voiced (ClickKind k, SessionSettings::ClickSound s);

struct TimedEvent {
    double time = 0;
    ClickKind kind = ClickKind::beat;
    int beat = -1;
    int pitch = -1;      // a guide note's MIDI pitch
    bool up = false;
};

struct CycleSlot {
    int index = 0;
    double start = 0, duration = 0, bpm = 0;
    std::vector<Note> notes;
    std::vector<TimedEvent> events;
    double end() const { return start + duration; }
};

namespace RunBuilder {
    struct CountIn { std::vector<TimedEvent> events; double end; };
    CountIn countIn (int beats, double bpm);
    /// The click's options for a cycle: the accent, the gap trainer's muted bars, and the tuning for the notes' pitches.
    struct ClickOptions {
        SessionSettings::Accent accent = SessionSettings::Accent::one;
        int gapEvery = 0;
        Tuning tuning;
        bool pitchFree = false;
    };
    bool isGap (int bar, int every);
    CycleSlot cycle (const Drill& d, int index, double start, double bpm, bool guided, std::optional<double> limit = {},
                     const ClickOptions& options = {});
    std::optional<double> rolling (const std::vector<double>& perCycle, const std::vector<int>& noteCounts, int window);
    double nextBPM (double current, std::optional<bool> lastPassed, int step, int maxBPM);
}

/// The guide guitar's pitch for a string and fret (string 1 is high E); no string: the open G.
int guitarPitch (int string, int fret);

/// Tempo zones, like heart-rate zones: percentages of his max on a drill (catalog/zones.json).
struct TempoZones {
    struct Zone { juce::String id, name, title; double low = 0, high = 0; };
    std::vector<Zone> zones;
    std::map<juce::String, juce::String> suggest;
    double startAt = 0.5;

    static TempoZones standard();
    static std::optional<TempoZones> fromVar (const juce::var& v);
    const Zone* zone (const juce::String& id) const;
    const Zone* suggested (const SessionSettings& s) const;
    static std::pair<int, int> range (const Zone& z, int max);
    int start (const Zone& z, int max) const;
    const Zone* zoneFor (double bpm, int max) const;
};

std::optional<ScoringConfig> scoringFromVar (const juce::var& v);

} // namespace practice
