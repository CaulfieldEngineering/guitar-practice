#include "Scoring.h"
#include <algorithm>
#include <cfloat>
#include <cmath>
#include <map>
#include <set>
#include <tuple>

namespace practice {

static constexpr double kPi = 3.14159265358979323846;

// Swift's Double.rounded(): half away from zero.
static int roundHalfAway (double x) { return (int) std::round (x); }

bool ScoringConfig::isValid() const
{
    return fullFraction > 0 && zeroFraction > fullFraction && fullMinMs > 0 && fullMaxMs >= fullMinMs
        && zeroMinMs > 0 && zeroMaxMs >= zeroMinMs && extraWeight >= 0;
}

ScoringConfig::Windows ScoringConfig::windows (double gap) const
{
    const double ms = std::max (0.0, gap) * 1000;
    const double f = std::min (fullMaxMs, std::max (fullMinMs, fullFraction * ms));
    const double z = std::min (zeroMaxMs, std::max (zeroMinMs, zeroFraction * ms));
    return { f, std::max (z, f + 1) };
}

double ScoringConfig::credit (double errorMs, double gap) const
{
    const auto w = windows (gap);
    const double a = std::abs (errorMs);
    if (a <= w.full) return 1;
    if (a >= w.zero) return 0;
    const double x = (a - w.full) / (w.zero - w.full);
    return 0.5 * (1 + std::cos (kPi * x));
}

int ScoreResult::pct (int k) const
{
    return expected > 0 ? roundHalfAway (100.0 * k / expected) : 0;
}

namespace Scoring {

double window (double shortestGap) { return std::min (0.100, std::max (0.030, shortestGap * 0.45)); }

std::vector<std::optional<int>> match (const std::vector<double>& expected, const std::vector<double>& played, double window)
{
    struct Pair { double d; int e, p; };
    std::vector<Pair> pairs;
    size_t j0 = 0;
    for (size_t i = 0; i < expected.size(); ++i)
    {
        const double t = expected[i];
        while (j0 < played.size() && played[j0] < t - window) ++j0;
        for (size_t j = j0; j < played.size() && played[j] <= t + window; ++j)
            pairs.push_back ({ std::abs (played[j] - t), (int) i, (int) j });
    }
    std::sort (pairs.begin(), pairs.end(), [] (const Pair& a, const Pair& b)
               { return std::tie (a.d, a.e, a.p) < std::tie (b.d, b.e, b.p); });
    std::vector<std::optional<int>> out (expected.size());
    std::vector<char> used (played.size(), 0);
    for (const auto& p : pairs)
        if (! out[(size_t) p.e] && ! used[(size_t) p.p]) { out[(size_t) p.e] = p.p; used[(size_t) p.p] = 1; }
    return out;
}

std::vector<double> gaps (const std::vector<double>& times)
{
    std::vector<double> out (times.size(), 1.0);
    if (times.size() <= 1) return out;
    for (size_t i = 0; i < times.size(); ++i)
    {
        double g = DBL_MAX;
        if (i > 0) g = std::min (g, times[i] - times[i - 1]);
        if (i + 1 < times.size()) g = std::min (g, times[i + 1] - times[i]);
        out[i] = std::max (0.001, g);
    }
    return out;
}

double accuracy (const std::vector<std::optional<double>>& errors, const std::vector<double>& gapList,
                 size_t lo, size_t hi, int extras, const ScoringConfig& config)
{
    hi = std::min ({ hi, errors.size(), gapList.size() });
    if (hi <= lo) return 1;
    double c = 0;
    for (size_t i = lo; i < hi; ++i)
        if (errors[i]) c += config.credit (*errors[i], gapList[i]);
    const double count = (double) (hi - lo) + config.extraWeight * (double) std::max (0, extras);
    return count > 0 ? std::min (1.0, c / count) : 1.0;
}

bool pitchMatches (std::optional<int> expected, std::optional<double> heard)
{
    if (! expected || ! heard) return true;
    double d = std::fmod (*heard - (double) *expected, 12.0);
    if (d < 0) d += 12;
    return d < 0.5 || d > 11.5;
}

ScoreResult score (const std::vector<Note>& notes, const std::vector<Onset>& played, double window,
                   const ScoringRule& rule, const ScoringConfig& config)
{
    std::vector<double> exp, times;
    for (auto& n : notes) exp.push_back (n.time);
    for (auto& p : played) times.push_back (p.time);
    const auto m = match (exp, times, window);
    const auto gap = gaps (exp);
    ScoreResult r;
    r.passMark = rule.passMark;
    r.wrongNotes.assign (notes.size(), 0);
    double credit = 0, fullSum = 0, zeroSum = 0;
    std::vector<double> matched;
    for (size_t i = 0; i < m.size(); ++i)
    {
        const auto w = config.windows (gap[i]);
        fullSum += w.full;
        zeroSum += w.zero;
        if (! m[i]) { r.errors.push_back (std::nullopt); continue; }
        const double ms = (times[(size_t) *m[i]] - exp[i]) * 1000;
        r.errors.push_back (ms);
        matched.push_back (ms);
        r.hits++;
        const double a = std::abs (ms);
        const bool right = pitchMatches (notes[i].pitch, played[(size_t) *m[i]].pitch);
        if (! right) { r.wrongPitch++; r.wrongNotes[i] = 1; }
        const double c = right ? config.credit (ms, gap[i]) : 0.0;
        credit += c;
        if (c >= 0.999) r.full++;
        if (a <= rule.tightMs) r.within20++;
        if (a <= rule.closeMs) r.within40++;
    }
    if (! exp.empty())
    {
        const double first = exp.front(), last = exp.back();
        std::vector<char> used (times.size(), 0);
        for (auto& x : m) if (x) used[(size_t) *x] = 1;
        for (size_t j = 0; j < times.size(); ++j)
        {
            const double t = times[j];
            if (used[j] || t < first - window || t > last + window) continue;
            r.extra++;
            double near = exp[0];
            for (double e : exp) if (std::abs (e - t) < std::abs (near - t)) near = e;
            r.extraOffsets.push_back ((t - near) * 1000);
        }
    }
    double mean = 0;
    if (! matched.empty()) { for (double x : matched) mean += x; mean /= (double) matched.size(); }
    double spread = 0;
    if (matched.size() >= 2)
    {
        double s = 0;
        for (double x : matched) s += (x - mean) * (x - mean);
        spread = std::sqrt (s / (double) (matched.size() - 1));
    }
    r.meanError = mean;
    r.spread = spread;

    // Accents: on each beat with an accented note that was played, did it come out louder than the beat's others?
    if (std::any_of (notes.begin(), notes.end(), [] (const Note& n) { return n.accent; }))
    {
        int l = 0, b = 0;
        std::map<int, std::vector<std::pair<bool, float>>> byBeat;
        for (size_t i = 0; i < m.size(); ++i)
            if (m[i]) byBeat[notes[i].beat].push_back ({ notes[i].accent, played[(size_t) *m[i]].strength });
        for (auto& [beat, list] : byBeat)
        {
            const std::pair<bool, float>* acc = nullptr;
            for (auto& x : list) if (x.first) { acc = &x; break; }
            if (! acc) continue;
            float sum = 0; int count = 0;
            for (auto& x : list) if (! x.first) { sum += x.second; ++count; }
            if (count == 0) continue;
            ++b;
            if (acc->second > 1.4f * (sum / (float) count)) ++l;
        }
        r.accentsLanded = l;
        r.accentBeats = b;
    }

    const double n = (double) exp.size();
    const double count = n + config.extraWeight * (double) r.extra;
    const int s = exp.empty() || count <= 0 ? 0 : roundHalfAway (100 * credit / count);
    r.expected = (int) exp.size();
    r.missed = r.expected - r.hits;
    r.score = std::min (100, std::max (0, s));
    r.fullMs = exp.empty() ? 0 : fullSum / n;
    r.zeroMs = exp.empty() ? 0 : zeroSum / n;
    return r;
}

bool addPick (const Onset& o, std::vector<Onset>& played, double within, float ratio)
{
    if (played.empty() || ! (o.time - played.back().time < within) || ! (o.time >= played.back().time))
    {
        played.push_back (o);
        return true;
    }
    const Onset& last = played.back();
    if (o.strength < last.strength * ratio) return false;
    if (last.strength < o.strength * ratio) { played.back() = o; return false; }
    played.push_back (o);
    return true;
}

std::vector<Onset> dropDoubles (const std::vector<Onset>& list, double within, float ratio)
{
    std::vector<Onset> out;
    for (auto& o : list) addPick (o, out, within, ratio);
    return out;
}

std::string band (double spreadMs)
{
    if (spreadMs < 15) return "Locked";
    if (spreadMs < 25) return "Tight";
    if (spreadMs < 40) return "Good";
    if (spreadMs < 60) return "Loose";
    return "Rough";
}

std::optional<Calibration> calibration (const std::vector<double>& clicks, const std::vector<double>& played)
{
    const auto m = match (clicks, played, 0.25);
    std::vector<double> d;
    for (size_t i = 0; i < m.size(); ++i) if (m[i]) d.push_back (played[(size_t) *m[i]] - clicks[i]);
    std::sort (d.begin(), d.end());
    if (d.size() < 5) return std::nullopt;
    const size_t k = d.size();
    const double median = k % 2 == 1 ? d[k / 2] : (d[k / 2 - 1] + d[k / 2]) / 2;
    double mean = 0;
    for (double x : d) mean += x;
    mean /= (double) k;
    double s = 0;
    for (double x : d) s += (x - mean) * (x - mean);
    return Calibration { median, std::sqrt (s / (double) (k - 1)), (int) k };
}

} // namespace Scoring
} // namespace practice
