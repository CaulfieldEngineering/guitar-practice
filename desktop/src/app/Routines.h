#pragma once
// Routines (Joe, 2026-11-24: "let's build a Routines section where we can interval out warm ups, drills, breaks,
// etc."), the same shape as the phone's Library/PracticeRoutine.swift and the drill server's /api/routines: a routine
// is blocks in order (a warm-up, a drill with its own setup, a break, open practice, or one of his own naming). Kept
// in %APPDATA%\Practice\routines.json and on the drill server; the newer edit of a routine wins, a delete too. The
// routines he has run are kept as one session each (routine-runs.json) until the server has them.
#include "../core/Drill.h"
#include "../core/RoutineClock.h"
#include <mutex>
#include <set>

namespace practice {

struct DrillSetup {
    int bpm = 100;
    bool guided = false, audioInput = true;
    SessionSettings session;
    juce::var toVar() const;
    static DrillSetup fromVar (const juce::var& v);
};

struct RoutineBlock {
    enum class Kind { warmup, drill, rest, free, custom };
    juce::String id = juce::Uuid().toDashedString();
    Kind kind = Kind::warmup;
    juce::String name;
    int seconds = 180;
    bool click = false;
    int bpm = 80;
    juce::String drillID;
    std::optional<DrillSetup> drill;

    static juce::String kindName (Kind k);
    static juce::String kindTitle (Kind k);
    juce::String title (const std::vector<Drill>& drills = {}) const;
    std::optional<double> fixedSeconds() const { return kind == Kind::drill ? std::nullopt : std::optional<double> (std::max (1, seconds)); }
    double estimate (const std::vector<Drill>& drills) const;
    juce::var toVar() const;
    static RoutineBlock fromVar (const juce::var& v);
    static RoutineBlock make (Kind k, const std::vector<Drill>& drills);
};

struct PracticeRoutine {
    juce::String id = juce::Uuid().toDashedString();
    juce::String name;
    std::vector<RoutineBlock> blocks;
    juce::Time updatedAt = juce::Time::getCurrentTime();
    bool deleted = false, starter = false;

    double estimate (const std::vector<Drill>& drills) const;
    PracticeRoutine duplicate() const;
    juce::var toVar() const;
    static std::optional<PracticeRoutine> fromVar (const juce::var& v);
    /// The newer edit of each wins (a delete too); a saved routine stands for the starter of the same id.
    static std::vector<PracticeRoutine> merge (const std::vector<PracticeRoutine>& a, const std::vector<PracticeRoutine>& b);
};

/// A routine as it was run: one session in Progress.
struct RoutineRunRecord {
    struct Block { juce::String kind, name; double seconds = 0; bool skipped = false; juce::String sessionID;
                   std::optional<int> accuracy, startBPM, topBPM; };
    juce::String id = juce::Uuid().toDashedString().toUpperCase();
    juce::Time date;
    juce::String routineID, routineName, device, appVersion;
    double seconds = 0;
    bool completed = false;
    std::vector<Block> blocks;
    juce::var toVar() const;
    static std::optional<RoutineRunRecord> fromVar (const juce::var& v);
};

/// His routines and the runs of them, thread-safe: the screens on the message thread, the sync on its worker.
class RoutineStore {
public:
    RoutineStore (juce::File dataFolder, juce::File bundledCatalog);
    std::vector<PracticeRoutine> routines() const;            // without the deleted ones
    std::optional<PracticeRoutine> routine (const juce::String& id) const;
    void save (PracticeRoutine r);
    void remove (const juce::String& id);
    std::optional<PracticeRoutine> duplicate (const juce::String& id);
    PracticeRoutine newRoutine (const std::vector<Drill>& drills);

    void addRun (const RoutineRunRecord& r);
    std::vector<RoutineRunRecord> runs() const;                // newest first

    /// One sync pass (the sync worker's thread): send what changed here, take what changed elsewhere; send the runs
    /// not yet held; take every device's runs. True when the server answered.
    bool sync (const juce::String& base);
    juce::Time lastSync() const { std::lock_guard<std::mutex> g (lock); return synced; }

private:
    void persist() const;
    juce::File file, runsFile, bundled;
    mutable std::mutex lock;
    std::vector<PracticeRoutine> all;
    std::set<juce::String> dirty;
    std::vector<RoutineRunRecord> runList;
    std::set<juce::String> sent;
    juce::Time synced;
};

} // namespace practice
