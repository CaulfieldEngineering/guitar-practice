#pragma once
// Runs a routine as a guided session, the same as the phone's Features/Routines/RoutineRunner.swift: each block in
// turn behind a 3, 2, 1 (a tick each) and a chime; a warm-up or open practice plays the click at its tempo (or
// none), a break is quiet, a drill block runs the drill with the block's own setup and ends when its run does.
// Pause, Skip and Back work on the whole routine; when it ends (or is ended) it is kept as one session.
#include "Model.h"

namespace practice {

class RoutineRunner : public juce::ChangeBroadcaster, private juce::Timer {
public:
    explicit RoutineRunner (Model& m) : model (m) {}
    ~RoutineRunner() override { stopTimer(); }

    void start (const PracticeRoutine& r);
    void pause();
    void resume();
    void skip();
    void back();
    void endNow();
    void close();

    bool active() const { return routine.has_value() && ! record.has_value(); }
    bool open() const { return routine.has_value(); }
    std::optional<PracticeRoutine> routine;
    std::optional<RoutineRunRecord> record;
    RoutineClock clock;
    double now = 0;
    std::map<int, SessionResult> results;

    RoutineClock::State state() const { return clock.state (now); }
    const RoutineBlock* block() const;
    const RoutineBlock* nextBlock() const;
    std::vector<double> estimates() const;
    double fraction (int i) const;
    bool paused() const;

private:
    void timerCallback() override;
    double t() const { return juce::Time::getMillisecondCounterHiRes() / 1000.0 - base; }
    void handle (const std::vector<RoutineClock::Event>& events);
    void begin (int i);
    void end (int i);
    void stopDrill();
    void finish (bool completed);

    Model& model;
    double base = 0;
    int lastTick = -1;
    bool ending = false;
    juce::String runID;
    juce::Time started;
};

} // namespace practice
