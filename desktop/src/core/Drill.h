#pragma once
// The drill schema (version 1), the same as the iPhone app's (ios/Practice/Library/Exercise.swift) and read from the
// same catalog the drill server serves (catalog/). A run is built a cycle at a time (RunBuilder), so the next cycle's
// tempo can follow the last result. Drills made of timed blocks (`segments`) are left out, as on the phone since 0.1.7.
#include <juce_core/juce_core.h>
#include "Scoring.h"
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
};

struct TempoRule { int start = 100, min = 30, max = 300, stepOnPass = 4; };

/// How a run is shaped: cycles, a time, or endurance (hold the target accuracy over the last few cycles).
struct SessionSettings {
    enum class Kind { cycles, duration, endurance };
    Kind kind = Kind::cycles;
    int cycles = 4;
    int seconds = 60;
    int targetPercent = 85;
    double toleranceMs = 30;   // still read, no longer used (the windows belong to ScoringConfig)
    int windowCycles = 2;
    int ladderStep = 0;

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
enum class ClickKind { accent, beat, sub, countIn, change, rest, done, pluck, pluckAccent };

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
    CycleSlot cycle (const Drill& d, int index, double start, double bpm, bool guided, std::optional<double> limit = {});
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
