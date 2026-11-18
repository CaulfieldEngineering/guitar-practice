#include "OnsetDetector.h"
#include <algorithm>
#include <cfloat>
#include <cmath>

namespace practice {

OnsetDetector::OnsetDetector (double sr, double highPassHz) : sampleRate (sr)
{
    hop = std::max (32, (int) std::round (sr * 0.0025));
    const double rc = 1 / (2 * 3.14159265358979323846 * highPassHz), dt = 1 / sr;
    hpA = (float) (rc / (rc + dt));
    avgCoef = (float) std::exp (-(double) hop / (0.040 * sr));
    hopsPerBlock = std::max (1, (int) (0.2 * sr) / hop);
    hopBuf.assign ((size_t) hop, 0.0f);
    envelopeCoef = (float) std::exp (-(double) hop / (envelopeTau * sr));
    blockMins.fill (1e-6f);
    blockMin = FLT_MAX;
}

float OnsetDetector::noiseFloor() const
{
    return std::max (*std::min_element (blockMins.begin(), blockMins.end()), 1e-9f);
}

std::vector<Onset> OnsetDetector::process (const std::vector<float>& samples, double time)
{
    std::vector<Onset> out;
    process (samples.data(), (int) samples.size(), time, [&] (const Onset& o) { out.push_back (o); });
    return out;
}

bool OnsetDetector::endHop (Onset& finished)
{
    float e = 0, peak = 0;
    for (float v : hopBuf) { e += v * v; peak = std::max (peak, std::abs (v)); }
    e /= (float) hop;
    level_ = std::sqrt (e);
    bool done = false;
    if (hasPending)
    {
        pending.strength = std::max (pending.strength, e);
        pendingHops++;
        if (pendingHops >= 4) { finished = pending; done = true; hasPending = false; }
    }
    const bool isOnset = e > minEnergy && e > avg * jumpRatio && e > noiseFloor() * floorRatio
        && e > envelope * retriggerRatio
        && (lastOnset < 0 || hopStart - lastOnset >= refractory);
    if (isOnset)
    {
        // The attack inside the hop: the first sample at half the hop's peak.
        int k = 0;
        while (k < hop - 1 && std::abs (hopBuf[(size_t) k]) < peak * 0.5f) ++k;
        const double t = hopStart + (double) k / sampleRate;
        if (hasPending) { finished = pending; done = true; }
        pending = { t, e };
        hasPending = true;
        pendingHops = 0;
        lastOnset = t;
        envelope = e;
    }
    else if (hasPending)
    {
        envelope = std::max (envelope, e);
    }
    envelope *= envelopeCoef;
    avg = avgCoef * avg + (1 - avgCoef) * e;
    blockMin = std::min (blockMin, e);
    if (++blockHops >= hopsPerBlock)
    {
        blockMins[(size_t) blockIndex] = blockMin;
        blockIndex = (blockIndex + 1) % (int) blockMins.size();
        blockMin = FLT_MAX;
        blockHops = 0;
    }
    return done;
}

void OnsetDetector::reset()
{
    envelope = 0; x1 = y1 = 0; avg = 0;
    blockMins.fill (1e-6f); blockMin = FLT_MAX; blockHops = 0; blockIndex = 0;
    std::fill (hopBuf.begin(), hopBuf.end(), 0.0f); hopFill = 0;
    hopStart = 0; lastOnset = -1; hasPending = false; pendingHops = 0; level_ = 0;
}

bool OnsetDetector::flush (Onset& out)
{
    if (! hasPending) return false;
    out = pending;
    hasPending = false;
    return true;
}

} // namespace practice
