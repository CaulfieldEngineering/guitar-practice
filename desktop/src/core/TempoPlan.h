#pragma once
// Ascending tempo and the Challenge clock, line for line the same as shared/tempo-plan.mjs (the reference, with the
// shared vectors in shared/tempo-vectors.json) and the phone's ios/Practice/Scoring/TempoPlan.swift. Joe, 2026-11-24:
// "ascend either per loop, or threshold average accuracy sustained per x duration", "a slow down BPM based on average
// sustained poor accuracy. And a paused break when dropping below even lower threshold accuracy", and "some kind of
// 'Challenge' mode that counts duration but only counts towards the time when the accuracy is above a certain
// threshold".
#include <juce_core/juce_core.h>
#include <optional>
#include <vector>

namespace practice {

struct TempoPlan {
    enum class Mode { off, perLoop, accuracy };
    enum class Unit { loops, seconds };
    enum class AtTop { hold, restart };
    enum class Zone { up, hold, down, rest };

    Mode mode = Mode::off;
    int endBPM = 0;              // the top; 0 is the drill's max
    int step = 4;
    int every = 2;
    Unit everyUnit = Unit::loops;
    AtTop atTop = AtTop::hold;
    Unit windowUnit = Unit::loops;
    int upPercent = 90, upWindow = 4;
    bool downOn = true;
    int downPercent = 75, downWindow = 4;
    bool breakOn = false;
    int breakPercent = 50, breakWindow = 4, breakSeconds = 25;
    bool slowerAfterBreak = true;
    int cooldownLoops = 1;
    int minBPM = 0;              // the floor; 0 is the start

    /// Every number in range, the thresholds kept apart (down at least 5 under up, the break 5 under down).
    TempoPlan normalized() const;
    struct Bounds { int top, floor; };
    Bounds bounds (int start, int ruleMin, int ruleMax) const;
    int perLoopBPM (int start, int top, int loop, double elapsed) const;
    Zone zone (double accuracy) const;

    static TempoPlan fromVar (const juce::var& v);
    juce::var toVar() const;
    bool operator== (const TempoPlan& o) const;

    static juce::String modeName (Mode m);
    static juce::String zoneName (Zone z);
};

/// A change of tempo in a run (the tempo curve): seconds into the run, from, to, and why.
struct TempoChange {
    enum class Kind { up, down, rest, loop };
    double at = 0;
    int from = 0, to = 0;
    Kind kind = Kind::up;
    static juce::String kindName (Kind k);
    juce::var toVar() const;
    static TempoChange fromVar (const juce::var& v);
};

/// A stretch of a run at one tempo (or a break), for the result's table.
struct TempoStep {
    int bpm = 0;
    double seconds = 0;
    std::optional<int> accuracy;
    bool rest = false;
    juce::var toVar() const;
    static TempoStep fromVar (const juce::var& v);
    struct Loop { int bpm; double seconds; std::optional<double> accuracy; };
    struct Break { int after; double seconds; };
    static std::vector<TempoStep> from (const std::vector<Loop>& loops, const std::vector<Break>& breaks);
};

/// By accuracy: judges each loop as it is scored.
class TempoGovernor {
public:
    struct Change { TempoChange::Kind kind; int from, to; };
    TempoGovernor (const TempoPlan& plan, int start, int top, int floor);
    std::optional<Change> judge (double accuracy, double seconds, int bpm);
    std::optional<double> average (int n) const;
    double progress() const;
    double progressDown (bool isBreak) const;
    int target() const { return target_; }
    bool settling() const { return cooldown > 0; }
    const TempoPlan& plan() const { return plan_; }
    int top, floor;
private:
    struct Loop { double accuracy, seconds; };
    double share (int n, int line, bool above) const;
    TempoPlan plan_;
    int target_;
    std::vector<Loop> loops;
    int cooldown = 0;
};

/// Challenge: the earned time runs only while the rolling accuracy holds at or above the threshold.
class ChallengeClock {
public:
    enum class Result { earned, held, done };
    ChallengeClock (double targetSeconds = 300, int percent = 90, int window = 2, double capSeconds = 0);
    Result judge (double accuracy, double seconds);
    bool done() const;
    double share() const { return elapsed > 0 ? earned / elapsed : 0; }
    double target, cap;
    int percent, window;
    double earned = 0, elapsed = 0, streak = 0, bestStreak = 0;
    bool inZone = false;
private:
    struct Loop { double accuracy, seconds; };
    std::vector<Loop> loops;
};

} // namespace practice
