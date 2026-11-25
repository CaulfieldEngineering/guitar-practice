#include "RoutineClock.h"
#include <algorithm>
#include <cmath>

namespace practice {

static double round6 (double x) { return std::round (x * 1e6) / 1e6; }
using EK = RoutineClock::Event::Kind;

RoutineClock::RoutineClock (std::vector<std::optional<double>> b, double c) : blocks (std::move (b)), countdown (c), log_ (blocks.size()) {}

std::vector<RoutineClock::Event> RoutineClock::start (double t)
{
    if (phase_ == Phase::idle) enterCountdown (0, t);
    return tick (t);
}

void RoutineClock::enterCountdown (int i, double t)
{
    if (i >= (int) blocks.size()) { phase_ = Phase::done; index_ = (int) blocks.size(); return; }
    phase_ = Phase::countdown; index_ = i; since = t; used = 0;
}

std::vector<RoutineClock::Event> RoutineClock::tick (double t)
{
    std::vector<Event> events;
    for (int guard = 0; guard < 64; ++guard)
    {
        if (phase_ == Phase::countdown && run (t) >= countdown - 1e-9)
        {
            const double at = since + (countdown - used);
            phase_ = Phase::block; since = at; used = 0;
            events.push_back ({ EK::start, index_ });
            continue;
        }
        if (phase_ == Phase::block && blocks[(size_t) index_] && run (t) >= *blocks[(size_t) index_] - 1e-9)
        {
            const double s = *blocks[(size_t) index_];
            const double at = since + (s - used);
            log_[(size_t) index_].seconds = round6 (log_[(size_t) index_].seconds + s);
            log_[(size_t) index_].done = true;
            events.push_back ({ EK::end, index_ });
            enterCountdown (index_ + 1, at);
            if (phase_ == Phase::done) events.push_back ({ EK::done, 0 });
            continue;
        }
        break;
    }
    return events;
}

void RoutineClock::pause (double t)
{
    tick (t);
    if (phase_ != Phase::countdown && phase_ != Phase::block) return;
    used = run (t); held = phase_; phase_ = Phase::paused;
}

std::vector<RoutineClock::Event> RoutineClock::resume (double t)
{
    if (phase_ != Phase::paused || ! held) return {};
    phase_ = *held; held.reset(); since = t;
    return tick (t);
}

std::vector<RoutineClock::Event> RoutineClock::skip (double t)
{
    tick (t);
    const auto p = phase_ == Phase::paused ? held.value_or (Phase::idle) : phase_;
    if (p == Phase::countdown) { phase_ = Phase::block; since = t; used = 0; held.reset(); return { { EK::start, index_ } }; }
    if (p != Phase::block) return {};
    return finishBlock (t, true);
}

std::vector<RoutineClock::Event> RoutineClock::blockDone (double t)
{
    tick (t);
    if (! (phase_ == Phase::block || (phase_ == Phase::paused && held == Phase::block))) return {};
    return finishBlock (t, false);
}

std::vector<RoutineClock::Event> RoutineClock::finishBlock (double t, bool skipped)
{
    const double ran = phase_ == Phase::paused ? used : run (t);
    const int i = index_;
    log_[(size_t) i].seconds = round6 (log_[(size_t) i].seconds + ran);
    log_[(size_t) i].skipped = skipped;
    log_[(size_t) i].done = ! skipped;
    held.reset();
    std::vector<Event> events { { EK::end, i } };
    enterCountdown (i + 1, t);
    if (phase_ == Phase::done) events.push_back ({ EK::done, 0 });
    return events;
}

void RoutineClock::back (double t)
{
    tick (t);
    const auto p = phase_ == Phase::paused ? held.value_or (Phase::idle) : phase_;
    if (p != Phase::countdown && p != Phase::block && phase_ != Phase::done) return;
    const double ran = phase_ == Phase::paused ? used : (phase_ == Phase::done ? 0 : run (t));
    int i = index_;
    if (phase_ == Phase::done) i = (int) blocks.size() - 1;
    else if (p == Phase::countdown || ran < backGrace) i = std::max (0, i - 1);
    if (p == Phase::block && phase_ != Phase::done) log_[(size_t) index_].seconds = round6 (log_[(size_t) index_].seconds + ran);
    held.reset();
    enterCountdown (i, t);
}

RoutineClock::State RoutineClock::state (double t) const
{
    const auto p = phase_ == Phase::paused ? held.value_or (Phase::idle) : phase_;
    const double ran = phase_ == Phase::paused ? used : run (t);
    std::optional<double> left;
    if (p == Phase::countdown) left = std::max (0.0, countdown - ran);
    else if (p == Phase::block && index_ < (int) blocks.size() && blocks[(size_t) index_]) left = std::max (0.0, *blocks[(size_t) index_] - ran);
    std::optional<int> tick;
    if (p == Phase::countdown) tick = (int) std::ceil (std::max (0.0, countdown - ran) - 1e-9);
    return { phase_, index_, left ? std::optional<double> (round6 (*left)) : std::nullopt, phase_ == Phase::paused, tick };
}

double RoutineClock::ranInBlock (double t) const
{
    const auto p = phase_ == Phase::paused ? held.value_or (Phase::idle) : phase_;
    return p == Phase::block ? (phase_ == Phase::paused ? used : run (t)) : 0;
}

double RoutineClock::remaining (double t, const std::vector<double>& estimates) const
{
    if (phase_ == Phase::done) return 0;
    auto est = [&] (int i) { return i < (int) estimates.size() ? estimates[(size_t) i] : 0.0; };
    const auto s = state (t);
    double total = s.left ? *s.left : est (index_);
    const auto p = phase_ == Phase::paused ? held.value_or (Phase::idle) : phase_;
    if (p == Phase::countdown) total += blocks[(size_t) index_] ? *blocks[(size_t) index_] : est (index_);
    for (int i = index_ + 1; i < (int) blocks.size(); ++i) total += countdown + (blocks[(size_t) i] ? *blocks[(size_t) i] : est (i));
    return round6 (total);
}

} // namespace practice
