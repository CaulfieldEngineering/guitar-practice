#include "TempoPlan.h"
#include <cmath>

namespace practice {

static int clampInt (int x, int lo, int hi) { return std::min (std::max (x, lo), std::max (lo, hi)); }
static double round6 (double x) { return std::round (x * 1e6) / 1e6; }

TempoPlan TempoPlan::normalized() const
{
    TempoPlan n = *this;
    n.step = clampInt (step, 1, 40);
    n.every = clampInt (every, 1, 600);
    n.upPercent = clampInt (upPercent, 10, 100);
    n.downPercent = clampInt (downPercent, 5, n.upPercent - 5);
    n.breakPercent = clampInt (breakPercent, 0, n.downOn ? n.downPercent - 5 : n.upPercent - 10);
    n.upWindow = clampInt (upWindow, 1, 600);
    n.downWindow = clampInt (downWindow, 1, 600);
    n.breakWindow = clampInt (breakWindow, 1, 600);
    n.breakSeconds = clampInt (breakSeconds, 5, 300);
    n.cooldownLoops = clampInt (cooldownLoops, 0, 16);
    return n;
}

TempoPlan::Bounds TempoPlan::bounds (int start, int ruleMin, int ruleMax) const
{
    const int top = endBPM > 0 ? std::min (endBPM, ruleMax) : ruleMax;
    const int floor = minBPM > 0 ? std::max (ruleMin, std::min (minBPM, start)) : start;
    return { std::max (top, start), floor };
}

int TempoPlan::perLoopBPM (int start, int top, int k, double elapsed) const
{
    const int steps = everyUnit == Unit::seconds ? (int) std::floor ((elapsed + 1e-9) / every) : k / std::max (1, every);
    if (top <= start) return start;
    const int levels = (int) std::ceil ((double) (top - start) / step) + 1;
    const int i = atTop == AtTop::restart ? steps % levels : std::min (steps, levels - 1);
    return std::min (top, start + i * step);
}

TempoPlan::Zone TempoPlan::zone (double accuracy) const
{
    const double pct = accuracy * 100;
    if (pct >= upPercent) return Zone::up;
    if (downOn && pct >= downPercent) return Zone::hold;
    if (! downOn && (! breakOn || pct >= breakPercent)) return Zone::hold;
    if (breakOn && pct < breakPercent) return Zone::rest;
    return Zone::down;
}

juce::String TempoPlan::modeName (Mode m) { return m == Mode::perLoop ? "perLoop" : m == Mode::accuracy ? "accuracy" : "off"; }
juce::String TempoPlan::zoneName (Zone z) { return z == Zone::up ? "up" : z == Zone::hold ? "hold" : z == Zone::down ? "down" : "break"; }

TempoPlan TempoPlan::fromVar (const juce::var& v)
{
    TempoPlan p;
    if (! v.isObject()) return p;
    auto i = [&] (const char* k, int def) { return v.hasProperty (k) ? (int) v[k] : def; };
    auto b = [&] (const char* k, bool def) { return v.hasProperty (k) ? (bool) v[k] : def; };
    const auto m = v["mode"].toString();
    p.mode = m == "perLoop" ? Mode::perLoop : m == "accuracy" ? Mode::accuracy : Mode::off;
    p.endBPM = i ("endBPM", p.endBPM);
    p.step = i ("step", p.step);
    p.every = i ("every", p.every);
    p.everyUnit = v["everyUnit"].toString() == "seconds" ? Unit::seconds : Unit::loops;
    p.atTop = v["atTop"].toString() == "restart" ? AtTop::restart : AtTop::hold;
    p.windowUnit = v["windowUnit"].toString() == "seconds" ? Unit::seconds : Unit::loops;
    p.upPercent = i ("upPercent", p.upPercent);
    p.upWindow = i ("upWindow", p.upWindow);
    p.downOn = b ("downOn", p.downOn);
    p.downPercent = i ("downPercent", p.downPercent);
    p.downWindow = i ("downWindow", p.downWindow);
    p.breakOn = b ("breakOn", p.breakOn);
    p.breakPercent = i ("breakPercent", p.breakPercent);
    p.breakWindow = i ("breakWindow", p.breakWindow);
    p.breakSeconds = i ("breakSeconds", p.breakSeconds);
    p.slowerAfterBreak = b ("slowerAfterBreak", p.slowerAfterBreak);
    p.cooldownLoops = i ("cooldownLoops", p.cooldownLoops);
    p.minBPM = i ("minBPM", p.minBPM);
    return p;
}

juce::var TempoPlan::toVar() const
{
    auto* o = new juce::DynamicObject();
    o->setProperty ("mode", modeName (mode));
    o->setProperty ("endBPM", endBPM);
    o->setProperty ("step", step);
    o->setProperty ("every", every);
    o->setProperty ("everyUnit", everyUnit == Unit::seconds ? "seconds" : "loops");
    o->setProperty ("atTop", atTop == AtTop::restart ? "restart" : "hold");
    o->setProperty ("windowUnit", windowUnit == Unit::seconds ? "seconds" : "loops");
    o->setProperty ("upPercent", upPercent);
    o->setProperty ("upWindow", upWindow);
    o->setProperty ("downOn", downOn);
    o->setProperty ("downPercent", downPercent);
    o->setProperty ("downWindow", downWindow);
    o->setProperty ("breakOn", breakOn);
    o->setProperty ("breakPercent", breakPercent);
    o->setProperty ("breakWindow", breakWindow);
    o->setProperty ("breakSeconds", breakSeconds);
    o->setProperty ("slowerAfterBreak", slowerAfterBreak);
    o->setProperty ("cooldownLoops", cooldownLoops);
    o->setProperty ("minBPM", minBPM);
    return juce::var (o);
}

bool TempoPlan::operator== (const TempoPlan& o) const
{
    return juce::JSON::toString (toVar(), true) == juce::JSON::toString (o.toVar(), true);
}

juce::String TempoChange::kindName (Kind k) { return k == Kind::up ? "up" : k == Kind::down ? "down" : k == Kind::rest ? "break" : "loop"; }

juce::var TempoChange::toVar() const
{
    auto* o = new juce::DynamicObject();
    o->setProperty ("at", at); o->setProperty ("from", from); o->setProperty ("to", to); o->setProperty ("kind", kindName (kind));
    return juce::var (o);
}

TempoChange TempoChange::fromVar (const juce::var& v)
{
    TempoChange c;
    c.at = (double) v["at"]; c.from = (int) v["from"]; c.to = (int) v["to"];
    const auto k = v["kind"].toString();
    c.kind = k == "down" ? Kind::down : k == "break" ? Kind::rest : k == "loop" ? Kind::loop : Kind::up;
    return c;
}

juce::var TempoStep::toVar() const
{
    auto* o = new juce::DynamicObject();
    o->setProperty ("bpm", bpm); o->setProperty ("seconds", seconds);
    if (accuracy) o->setProperty ("accuracy", *accuracy);
    if (rest) o->setProperty ("rest", true);
    return juce::var (o);
}

TempoStep TempoStep::fromVar (const juce::var& v)
{
    TempoStep s;
    s.bpm = (int) v["bpm"]; s.seconds = (double) v["seconds"];
    if (v.hasProperty ("accuracy") && ! v["accuracy"].isVoid()) s.accuracy = (int) v["accuracy"];
    s.rest = (bool) v["rest"];
    return s;
}

std::vector<TempoStep> TempoStep::from (const std::vector<Loop>& loops, const std::vector<Break>& breaks)
{
    std::vector<TempoStep> out;
    double credit = 0, weight = 0;
    auto close = [&] {
        if (out.empty()) return;
        auto& last = out.back();
        if (! last.rest && weight > 0) last.accuracy = (int) std::round (credit / weight * 100);
        credit = 0; weight = 0;
    };
    for (size_t i = 0; i < loops.size(); ++i)
    {
        const auto& l = loops[i];
        if (out.empty() || out.back().bpm != l.bpm || out.back().rest)
        {
            close();
            out.push_back ({ l.bpm, 0, std::nullopt, false });
        }
        out.back().seconds += l.seconds;
        if (l.accuracy) { credit += *l.accuracy * l.seconds; weight += l.seconds; }
        for (auto& b : breaks)
            if (b.after == (int) i) { close(); out.push_back ({ l.bpm, b.seconds, std::nullopt, true }); }
    }
    close();
    return out;
}

// ---- the governor ----

TempoGovernor::TempoGovernor (const TempoPlan& plan, int start, int top_, int floor_)
    : top (top_), floor (floor_), plan_ (plan.normalized()), target_ (start) {}

std::optional<double> TempoGovernor::average (int n) const
{
    double covered = 0, credit = 0, weight = 0;
    for (auto it = loops.rbegin(); it != loops.rend(); ++it)
    {
        covered += plan_.windowUnit == TempoPlan::Unit::seconds ? it->seconds : 1;
        credit += it->accuracy * it->seconds;
        weight += it->seconds;
        if (covered >= n - 1e-9) return weight > 0 ? credit / weight : 0.0;
    }
    return std::nullopt;
}

double TempoGovernor::share (int n, int line, bool above) const
{
    double covered = 0, credit = 0, weight = 0;
    for (auto it = loops.rbegin(); it != loops.rend() && covered < n - 1e-9; ++it)
    {
        covered += plan_.windowUnit == TempoPlan::Unit::seconds ? it->seconds : 1;
        credit += it->accuracy * it->seconds;
        weight += it->seconds;
    }
    if (weight <= 0) return 0;
    const double pct = credit / weight * 100;
    if (above ? pct < line : pct >= line) return 0;
    return std::min (1.0, covered / n);
}

double TempoGovernor::progress() const
{
    if (target_ >= top) return 0;
    return share (plan_.upWindow, plan_.upPercent, true);
}

double TempoGovernor::progressDown (bool isBreak) const
{
    return isBreak ? share (plan_.breakWindow, plan_.breakPercent, false) : share (plan_.downWindow, plan_.downPercent, false);
}

std::optional<TempoGovernor::Change> TempoGovernor::judge (double accuracy, double seconds, int bpm)
{
    if (bpm != target_) return std::nullopt;
    if (cooldown > 0) { --cooldown; return std::nullopt; }
    loops.push_back ({ accuracy, seconds });
    const auto& p = plan_;
    const int from = target_;
    std::optional<Change> change;
    const auto b = p.breakOn ? average (p.breakWindow) : std::nullopt;
    const auto d = p.downOn ? average (p.downWindow) : std::nullopt;
    const auto u = average (p.upWindow);
    if (b && *b * 100 < p.breakPercent)
        change = Change { TempoChange::Kind::rest, from, p.slowerAfterBreak ? std::max (floor, from - p.step) : from };
    else if (d && *d * 100 < p.downPercent && from > floor)
        change = Change { TempoChange::Kind::down, from, std::max (floor, from - p.step) };
    else if (u && *u * 100 >= p.upPercent && from < top)
        change = Change { TempoChange::Kind::up, from, std::min (top, from + p.step) };
    if (change)
    {
        target_ = change->to;
        loops.clear();
        cooldown = p.cooldownLoops;
    }
    return change;
}

// ---- the challenge ----

ChallengeClock::ChallengeClock (double targetSeconds, int percent_, int window_, double capSeconds)
    : target (targetSeconds), cap (capSeconds), percent (percent_), window (std::max (1, window_)) {}

bool ChallengeClock::done() const { return earned >= target - 1e-9 || (cap > 0 && elapsed >= cap - 1e-9); }

ChallengeClock::Result ChallengeClock::judge (double accuracy, double seconds)
{
    if (done()) return Result::done;
    loops.push_back ({ accuracy, seconds });
    double credit = 0, weight = 0;
    const size_t from = loops.size() > (size_t) window ? loops.size() - (size_t) window : 0;
    for (size_t i = from; i < loops.size(); ++i) { credit += loops[i].accuracy * loops[i].seconds; weight += loops[i].seconds; }
    const double rolling = weight > 0 ? credit / weight : 0;
    elapsed = round6 (elapsed + seconds);
    inZone = rolling * 100 >= percent - 1e-9;
    if (inZone)
    {
        earned = round6 (std::min (target, earned + seconds));
        streak = round6 (streak + seconds);
        bestStreak = std::max (bestStreak, streak);
    }
    else
        streak = 0;
    return done() ? Result::done : (inZone ? Result::earned : Result::held);
}

} // namespace practice
