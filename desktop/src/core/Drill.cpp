#include "Drill.h"
#include <cmath>
#include <set>

namespace practice {

static int intOr (const juce::var& o, const char* key, int dflt)
{
    auto v = o.getProperty (key, juce::var());
    return v.isVoid() || ! (v.isInt() || v.isInt64() || v.isDouble()) ? dflt : (int) v;
}
static double numOr (const juce::var& o, const char* key, double dflt)
{
    auto v = o.getProperty (key, juce::var());
    return v.isVoid() || ! (v.isInt() || v.isInt64() || v.isDouble()) ? dflt : (double) v;
}
static juce::String strOr (const juce::var& o, const char* key, const juce::String& dflt = {})
{
    auto v = o.getProperty (key, juce::var());
    return v.isString() ? v.toString() : dflt;
}

juce::String SessionSettings::kindName (Kind k)
{
    switch (k) { case Kind::cycles: return "cycles"; case Kind::duration: return "duration"; case Kind::endurance: return "endurance"; }
    return "cycles";
}
SessionSettings::Kind SessionSettings::kindFrom (const juce::String& s)
{
    if (s == "duration") return Kind::duration;
    if (s == "endurance") return Kind::endurance;
    return Kind::cycles;
}

SessionSettings SessionSettings::fromVar (const juce::var& v, SessionSettings s)
{
    if (! v.isObject()) return s;
    if (v.hasProperty ("kind")) s.kind = kindFrom (v["kind"].toString());
    s.cycles = intOr (v, "cycles", s.cycles);
    s.seconds = intOr (v, "seconds", s.seconds);
    s.targetPercent = intOr (v, "targetPercent", s.targetPercent);
    s.toleranceMs = numOr (v, "toleranceMs", s.toleranceMs);
    s.windowCycles = intOr (v, "windowCycles", s.windowCycles);
    s.ladderStep = intOr (v, "ladderStep", s.ladderStep);
    return s;
}

juce::var SessionSettings::toVar() const
{
    auto* o = new juce::DynamicObject();
    o->setProperty ("kind", kindName (kind));
    o->setProperty ("cycles", cycles);
    o->setProperty ("seconds", seconds);
    o->setProperty ("targetPercent", targetPercent);
    o->setProperty ("toleranceMs", toleranceMs);
    o->setProperty ("windowCycles", windowCycles);
    o->setProperty ("ladderStep", ladderStep);
    return juce::var (o);
}

bool SessionSettings::operator== (const SessionSettings& o) const
{
    return kind == o.kind && cycles == o.cycles && seconds == o.seconds && targetPercent == o.targetPercent
        && windowCycles == o.windowCycles && ladderStep == o.ladderStep;
}

std::vector<NoteSpec> Drill::expand (const std::vector<int>& groups, bool accentFirst)
{
    std::vector<NoteSpec> out;
    bool down = true;
    for (size_t b = 0; b < groups.size(); ++b)
        for (int k = 0; k < groups[b]; ++k)
        {
            NoteSpec n;
            n.at = { (int) b, k, groups[b] };
            n.pick = down ? Pick::down : Pick::up;
            n.accent = accentFirst && k == 0;
            out.push_back (n);
            down = ! down;
        }
    return out;
}

std::optional<Drill> Drill::fromVar (const juce::var& v)
{
    if (! v.isObject() || ! v["id"].isString() || ! v["name"].isString()) return std::nullopt;
    Drill d;
    d.schema = intOr (v, "schema", 1);
    d.version = intOr (v, "version", 1);
    d.id = v["id"].toString();
    d.name = v["name"].toString();
    d.detail = strOr (v, "detail");
    d.shortName = strOr (v, "short");
    d.say = strOr (v, "say");
    d.timedBlocks = v["segments"].isArray() && v["segments"].size() > 0;
    d.category = strOr (v, "category", d.timedBlocks ? "Timed routines" : "Right hand");
    d.beatsPerBar = intOr (v, "beatsPerBar", 4);
    auto t = v["tempo"];
    if (! t.isObject() || ! (t["start"].isInt() || t["start"].isInt64() || t["start"].isDouble()))
    {
        if (! d.timedBlocks) return std::nullopt;
        d.tempo = { 100, 20, 400, 4 };
    }
    else
    {
        d.tempo.start = (int) t["start"];
        d.tempo.min = intOr (t, "min", 30);
        d.tempo.max = intOr (t, "max", 300);
        d.tempo.stepOnPass = intOr (t, "stepOnPass", 4);
    }
    if (auto sc = v["scoring"]; sc.isObject())
    {
        d.scoring.passMark = intOr (sc, "passMark", 85);
        d.scoring.tightMs = numOr (sc, "tightMs", 20);
        d.scoring.closeMs = numOr (sc, "closeMs", 40);
        if (sc.hasProperty ("windowMs") && ! sc["windowMs"].isVoid()) d.scoring.windowMs = (double) sc["windowMs"];
    }
    d.session = SessionSettings::fromVar (v["session"]);
    if (auto lv = v["levels"]; lv.isArray())
        for (auto& l : *lv.getArray())
        {
            if (! l["name"].isString()) continue;
            Level level { l["name"].toString(), intOr (l, "bpm", 0), std::nullopt };
            if (l["session"].isObject()) level.session = SessionSettings::fromVar (l["session"]);
            d.levels.push_back (level);
        }
    if (auto ns = v["notes"]; ns.isArray() && ns.size() > 0)
    {
        for (auto& n : *ns.getArray())
        {
            auto at = n["at"];
            if (! at.isObject()) return std::nullopt;
            NoteSpec s;
            s.at = { intOr (at, "beat", 0), intOr (at, "step", 0), intOr (at, "of", 1) };
            s.string = intOr (n, "string", 0);
            s.fret = intOr (n, "fret", -1);
            auto p = strOr (n, "pick");
            s.pick = p == "down" ? Pick::down : p == "up" ? Pick::up : Pick::none;
            s.accent = n["accent"].isBool() ? (bool) n["accent"] : false;
            d.notes.push_back (s);
        }
        std::stable_sort (d.notes.begin(), d.notes.end(), [] (const NoteSpec& a, const NoteSpec& b) { return a.at.beats() < b.at.beats(); });
        const int last = (int) std::floor (d.notes.back().at.beats()) + 1;
        d.cycleBeats = intOr (v, "cycleBeats", last);
    }
    else if (auto gs = v["groups"]; gs.isArray() && gs.size() > 0)
    {
        std::vector<int> groups;
        for (auto& g : *gs.getArray()) groups.push_back ((int) g);
        d.notes = expand (groups, strOr (v, "accent") == "first");
        d.cycleBeats = (int) groups.size();
    }
    else if (! d.timedBlocks)
        return std::nullopt;
    if (d.cycleBeats <= 0) return std::nullopt;
    return d;
}

std::vector<int> Drill::groupSizes() const
{
    std::vector<int> sizes ((size_t) std::max (1, cycleBeats), 0);
    for (auto& n : notes) if (n.at.beat >= 0 && n.at.beat < (int) sizes.size()) sizes[(size_t) n.at.beat]++;
    return sizes;
}

juce::String Drill::glyph() const
{
    auto sizes = groupSizes();
    for (auto& n : notes)
        if (n.at.of != sizes[(size_t) std::min ((int) sizes.size() - 1, std::max (0, n.at.beat))]) return "mix";
    std::vector<int> runs;
    for (int s : sizes) if (runs.empty() || runs.back() != s) runs.push_back (s);
    if (runs.size() > 1 && runs.front() == runs.back()) runs.pop_back();
    auto word = [] (int n) -> juce::String {
        switch (n) { case 0: return "rest"; case 1: return "4"; case 2: return "8"; case 3: return "3"; case 4: return "16"; default: return juce::String (n); }
    };
    if (runs.size() == 1) return word (runs[0]);
    juce::StringArray parts;
    const bool rest = std::find (runs.begin(), runs.end(), 0) != runs.end();
    for (int r : runs) parts.add (rest ? word (r) : juce::String (r));
    return parts.joinIntoString (rest ? juce::String (juce::CharPointer_UTF8 ("\xc2\xb7")) : juce::String (juce::CharPointer_UTF8 ("\xe2\x86\x92")));
}

std::vector<Note> Drill::runNotes (double bpm, double start, double seconds) const
{
    const double beat = 60 / std::max (1.0, bpm);
    const double totalBeats = seconds / beat;
    std::vector<Note> out;
    if (notes.empty()) return out;
    for (int cycle = 0; (double) (cycle * cycleBeats) < totalBeats - 1e-9; ++cycle)
    {
        for (auto& n : notes)
        {
            const double b = (double) (cycle * cycleBeats) + n.at.beats();
            if (b >= totalBeats - 1e-9) break;
            Note x;
            x.time = start + b * beat;
            x.accent = n.accent;
            x.beat = cycle * cycleBeats + n.at.beat;
            x.pick = n.pick;
            x.string = n.string;
            x.fret = n.fret;
            out.push_back (x);
        }
    }
    return out;
}

double Drill::shortestGap (double bpm) const
{
    const double beat = 60 / std::max (1.0, bpm);
    if (notes.size() <= 1) return beat * cycleBeats;
    double g = (double) cycleBeats - notes.back().at.beats() + notes.front().at.beats();
    for (size_t i = 1; i < notes.size(); ++i) g = std::min (g, notes[i].at.beats() - notes[i - 1].at.beats());
    return std::max (1e-3, g) * beat;
}

double Drill::window (double bpm) const
{
    if (scoring.windowMs) return *scoring.windowMs / 1000;
    return Scoring::window (shortestGap (bpm));
}

Drill Drill::fallback()
{
    Drill d;
    d.id = "alt8"; d.name = "Alternate picking, eighths"; d.detail = "Two notes a beat, down up.";
    d.cycleBeats = 1; d.notes = expand ({ 2 }, false); d.tempo = { 120, 30, 300, 4 };
    return d;
}

int guitarPitch (int string, int fret)
{
    static const int open[] = { 64, 59, 55, 50, 45, 40 };
    if (string < 1 || string > 6) return 55;
    return open[string - 1] + std::max (0, fret);
}

namespace RunBuilder {

CountIn countIn (int beats, double bpm)
{
    const double b = 60 / std::max (1.0, bpm);
    CountIn c;
    for (int i = 0; i < std::max (0, beats); ++i) c.events.push_back ({ i * b, ClickKind::countIn, i });
    c.end = std::max (0, beats) * b;
    return c;
}

CycleSlot cycle (const Drill& d, int index, double start, double bpm, bool guided, std::optional<double> limit)
{
    const double beat = 60 / std::max (1.0, bpm);
    const double duration = d.cycleBeats * beat;
    const double cap = limit ? *limit - start : duration;
    const double seconds = std::min (duration, cap);
    CycleSlot s;
    s.index = index; s.start = start; s.duration = seconds; s.bpm = bpm;
    s.notes = d.runNotes (bpm, start, seconds);
    for (auto& n : s.notes) n.beat += index * d.cycleBeats;
    const int beatsInRun = (int) std::ceil (seconds / beat - 1e-9);
    for (int b = 0; b < std::max (0, beatsInRun); ++b)
    {
        const int global = index * d.cycleBeats + b;
        const int inBar = global % std::max (1, d.beatsPerBar);
        s.events.push_back ({ start + b * beat, inBar == 0 ? ClickKind::accent : ClickKind::beat, inBar });
    }
    if (guided)
    {
        auto sizes = d.groupSizes();
        const int count = (int) sizes.size();
        for (auto& n : s.notes)
        {
            const int local = n.beat - index * d.cycleBeats;
            const int prev = sizes[(size_t) (((local - 1) % count + count) % count)];
            const bool first = n.time - start - local * beat < 1e-6;
            const bool changed = first && sizes[(size_t) (local % count)] != prev && prev > 0;
            TimedEvent e { n.time, n.accent || changed ? ClickKind::pluckAccent : ClickKind::pluck, -1,
                           guitarPitch (n.string, n.fret), n.pick == Pick::up };
            s.events.push_back (e);
        }
    }
    std::stable_sort (s.events.begin(), s.events.end(), [] (const TimedEvent& a, const TimedEvent& b) { return a.time < b.time; });
    return s;
}

std::optional<double> rolling (const std::vector<double>& perCycle, const std::vector<int>& noteCounts, int window)
{
    const size_t w = (size_t) std::max (1, window);
    if (perCycle.size() < w || perCycle.size() != noteCounts.size()) return std::nullopt;
    double sum = 0; int total = 0;
    for (size_t i = perCycle.size() - w; i < perCycle.size(); ++i) { sum += perCycle[i] * noteCounts[i]; total += noteCounts[i]; }
    if (total <= 0) return 1.0;
    return sum / total;
}

double nextBPM (double current, std::optional<bool> lastPassed, int step, int maxBPM)
{
    if (step <= 0 || lastPassed != true) return current;
    return std::min ((double) maxBPM, current + step);
}

} // namespace RunBuilder

TempoZones TempoZones::standard()
{
    TempoZones z;
    z.zones = { { "z1", "Z1", "Warm-up", 60, 70 }, { "z2", "Z2", "Cruise", 70, 80 }, { "z3", "Z3", "Tempo", 80, 90 },
                { "z4", "Z4", "Threshold", 90, 100 }, { "z5", "Z5", "Max", 100, 105 } };
    z.suggest = { { "endurance", "z2" }, { "duration", "z3" }, { "cycles", "z3" }, { "ladder", "z4" } };
    return z;
}

std::optional<TempoZones> TempoZones::fromVar (const juce::var& v)
{
    if (! v.isObject() || intOr (v, "schema", 1) > 1 || ! v["zones"].isArray()) return std::nullopt;
    TempoZones z;
    for (auto& e : *v["zones"].getArray())
    {
        Zone x { strOr (e, "id"), strOr (e, "name"), strOr (e, "title"), numOr (e, "low", 0), numOr (e, "high", 0) };
        if (x.id.isEmpty() || x.low >= x.high) return std::nullopt;
        z.zones.push_back (x);
    }
    if (z.zones.empty()) return std::nullopt;
    if (auto* s = v["suggest"].getDynamicObject())
        for (auto& p : s->getProperties()) z.suggest[p.name.toString()] = p.value.toString();
    z.startAt = numOr (v, "startAt", 0.5);
    return z;
}

const TempoZones::Zone* TempoZones::zone (const juce::String& id) const
{
    for (auto& z : zones) if (z.id == id) return &z;
    return nullptr;
}

const TempoZones::Zone* TempoZones::suggested (const SessionSettings& s) const
{
    const juce::String key = s.ladderStep > 0 ? "ladder" : SessionSettings::kindName (s.kind);
    auto it = suggest.find (key);
    if (it != suggest.end()) if (auto* z = zone (it->second)) return z;
    return zones.empty() ? nullptr : &zones.front();
}

std::pair<int, int> TempoZones::range (const Zone& z, int max)
{
    const int lo = (int) std::round (max * z.low / 100), hi = (int) std::round (max * z.high / 100);
    return { std::min (lo, hi), std::max (lo, hi) };
}

int TempoZones::start (const Zone& z, int max) const
{
    auto r = range (z, max);
    return r.first + (int) std::round ((r.second - r.first) * startAt);
}

const TempoZones::Zone* TempoZones::zoneFor (double bpm, int max) const
{
    if (max <= 0 || zones.empty()) return nullptr;
    const double pct = bpm / max * 100;
    const Zone* found = nullptr;
    for (auto& z : zones) if (pct >= z.low - 0.5) found = &z;
    return found ? found : &zones.front();
}

std::optional<ScoringConfig> scoringFromVar (const juce::var& v)
{
    if (! v.isObject()) return std::nullopt;
    ScoringConfig s;
    s.schema = intOr (v, "schema", 1);
    s.fullFraction = numOr (v, "fullFraction", s.fullFraction);
    s.zeroFraction = numOr (v, "zeroFraction", s.zeroFraction);
    s.fullMinMs = numOr (v, "fullMinMs", s.fullMinMs);
    s.fullMaxMs = numOr (v, "fullMaxMs", s.fullMaxMs);
    s.zeroMinMs = numOr (v, "zeroMinMs", s.zeroMinMs);
    s.zeroMaxMs = numOr (v, "zeroMaxMs", s.zeroMaxMs);
    s.extraWeight = numOr (v, "extraWeight", s.extraWeight);
    if (s.schema > 1 || ! s.isValid()) return std::nullopt;
    return s;
}

} // namespace practice
