#pragma once
// The routine runner's clock, line for line the same as shared/routine-clock.mjs (the reference; its vectors are
// shared/routine-vectors.json) and the phone's ios/Practice/Library/RoutineClock.swift. A countdown of 3 before each
// block; a block with seconds ends by itself; one without (a drill) ends when the app says so. Pause holds the clock;
// Skip ends the block now (in a countdown, it starts the block); Back starts the block again, or in its first 3
// seconds or in a countdown, goes to the block before. Time is passed in.
#include <optional>
#include <vector>

namespace practice {

class RoutineClock {
public:
    enum class Phase { idle, countdown, block, paused, done };
    struct Event { enum class Kind { start, end, done } kind; int index; bool operator== (const Event& o) const { return kind == o.kind && index == o.index; } };
    struct Log { double seconds = 0; bool skipped = false, done = false; };
    struct State { Phase phase; int index; std::optional<double> left; bool paused; std::optional<int> countdownTick; };

    static constexpr double countdownSeconds = 3, backGrace = 3;

    explicit RoutineClock (std::vector<std::optional<double>> blocks = {}, double countdown = countdownSeconds);
    std::vector<Event> start (double t);
    std::vector<Event> tick (double t);
    void pause (double t);
    std::vector<Event> resume (double t);
    std::vector<Event> skip (double t);
    std::vector<Event> blockDone (double t);
    void back (double t);
    State state (double t) const;
    double ranInBlock (double t) const;
    double remaining (double t, const std::vector<double>& estimates = {}) const;

    Phase phase() const { return phase_; }
    int index() const { return index_; }
    const std::vector<Log>& log() const { return log_; }
    size_t size() const { return blocks.size(); }

private:
    void enterCountdown (int i, double t);
    double run (double t) const { return used + std::max (0.0, t - since); }
    std::vector<Event> finishBlock (double t, bool skipped);
    std::vector<std::optional<double>> blocks;
    double countdown;
    Phase phase_ = Phase::idle;
    std::optional<Phase> held;
    int index_ = 0;
    double since = 0, used = 0;
    std::vector<Log> log_;
};

} // namespace practice
