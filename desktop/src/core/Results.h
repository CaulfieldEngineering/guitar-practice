#pragma once
// One play-along run, in the iPhone app's shape (SessionResult, schema 1, ios/Practice/Persistence/History.swift), so
// the drill server keeps runs from both apps in one list and each app's Progress reads the other's. Dates go out as
// ISO 8601 with no fraction of a second ("2026-11-17T22:11:22Z"): the phone's decoder refuses a fraction.
// Plus the catalog folder reader (index.json and the files it names), the same rules as Library in Catalog.swift.
#include "Drill.h"

namespace practice {

struct SessionResult {
    int schema = 1;
    juce::String id;          // a UUID, upper case like the phone's
    juce::Time date;
    juce::String exerciseID;
    int exerciseVersion = 1;
    juce::String exerciseName;
    juce::String mode;        // cycles, duration, endurance
    int ladderStep = 0;
    bool guided = false;
    int startBPM = 0, topBPM = 0;
    double seconds = 0;
    int cycles = 0, notes = 0, hits = 0, missed = 0, extra = 0, pct20 = 0, pct40 = 0;
    double tightMs = 20, closeMs = 40, meanErrorMs = 0, spreadMs = 0, toleranceMs = 0;
    int targetPercent = 85, accuracyPercent = 0;
    std::optional<double> sustainedSeconds;
    int score = 0;
    bool passed = false;
    std::optional<int> accentsPercent;
    std::optional<double> offsetMs;
    juce::String appVersion;
    std::optional<int> scoringVersion;
    std::optional<double> fullMs, zeroMs;
    std::optional<int> doubles;
    std::vector<int> extraOffsetsMs;
    juce::String device;      // desktop only: which computer ("JPC", "MINI-PC"); the phone ignores it
    // 0.3.0: the tempo plan and its curve, breaks, Challenge, wrong pitches, the routine run it was a block of
    juce::String tempoMode;   // "perLoop", "accuracy"; empty: the tempo did not move by plan
    std::vector<TempoChange> tempoChanges;
    std::vector<TempoStep> tempoSteps;
    std::optional<int> breaks;
    std::optional<double> breakSeconds, earnedSeconds, elapsedSeconds, bestStreakSeconds;
    std::optional<int> wrongPitch;
    juce::String tuning, routineRunID;

    double bestValue() const
    {
        if (mode == "endurance") return sustainedSeconds.value_or (0);
        if (mode == "challenge") return earnedSeconds.value_or (0);
        return (double) score;
    }
    juce::var toVar() const;
    static std::optional<SessionResult> fromVar (const juce::var& v);
    static juce::String isoDate (juce::Time t);
    static std::optional<juce::Time> parseDate (const juce::String& s);
    static juce::String newID();
};

namespace Stats {
    struct Best { juce::String exerciseID, mode; int bpm; double value; int runs; juce::Time last; };
    std::vector<Best> bests (const std::vector<SessionResult>& results);
    std::optional<double> best (const std::vector<SessionResult>& results, const juce::String& id, const juce::String& mode, int bpm);
    std::optional<int> learnedTempo (const std::vector<SessionResult>& results, const juce::String& id, int recent = 10, int step = 4);
    std::optional<int> fastestPass (const std::vector<SessionResult>& results, const juce::String& id);
}

struct CatalogContents {
    int version = 0;
    std::vector<Drill> drills;
    std::optional<TempoZones> zones;
    std::optional<ScoringConfig> scoring;
};

namespace Library {
    constexpr int supportedSchema = 1;
    /// The drills in a file this app understands; a newer file is refused (nullopt), a drill that does not decode or
    /// asks for a newer schema is skipped alone.
    std::optional<std::vector<Drill>> decodeDrills (const juce::var& file, bool includeArchived = false);
    /// The drill catalog filter: what is offered (archived drills stay in the file, with his runs, to come back).
    std::vector<Drill> active (const std::vector<Drill>& list);
    /// Reads one catalog folder; nullopt when its index is missing or unreadable.
    std::optional<CatalogContents> read (const juce::File& folder);
    /// The bundled catalog, then the cached one pulled from the drill server, then the user folder; the same id later
    /// replaces the earlier one. Never empty (the fallback drill).
    CatalogContents load (const juce::File& bundled, const juce::File& cached, const juce::File& user);
}

} // namespace practice
