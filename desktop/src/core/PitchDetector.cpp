#include "PitchDetector.h"
#include <cmath>

namespace practice {

std::optional<double> PitchDetector::hz (const float* x, int n) const
{
    const int maxLag = (int) (sampleRate / minHz);
    const int minLag = std::max (2, (int) (sampleRate / maxHz));
    const int w = window();
    if (n < w + maxLag + 1) return std::nullopt;
    float energy = 0;
    for (int i = 0; i < w; ++i) energy += x[i] * x[i];
    if (energy / (float) w <= 1e-7f) return std::nullopt;
    std::vector<double> d ((size_t) maxLag + 1, 0.0), cmnd ((size_t) maxLag + 1, 1.0);
    for (int tau = 1; tau <= maxLag; ++tau)
    {
        double s = 0;
        for (int i = 0; i < w; ++i) { const double v = (double) (x[i] - x[i + tau]); s += v * v; }
        d[(size_t) tau] = s;
    }
    double running = 0;
    for (int tau = 1; tau <= maxLag; ++tau)
    {
        running += d[(size_t) tau];
        cmnd[(size_t) tau] = running > 0 ? d[(size_t) tau] * tau / running : 1;
    }
    int found = -1;
    for (int tau = minLag; tau <= maxLag; ++tau)
        if (cmnd[(size_t) tau] < threshold)
        {
            while (tau + 1 <= maxLag && cmnd[(size_t) tau + 1] < cmnd[(size_t) tau]) ++tau;
            found = tau;
            break;
        }
    if (found < 0) return std::nullopt;
    double period = found;
    if (found > 1 && found < maxLag)
    {
        const double a = cmnd[(size_t) found - 1], b = cmnd[(size_t) found], c = cmnd[(size_t) found + 1];
        const double den = a - 2 * b + c;
        if (std::abs (den) > 1e-12) period += 0.5 * (a - c) / den;
    }
    const double f = sampleRate / period;
    if (f < minHz || f > maxHz) return std::nullopt;
    return f;
}

std::optional<double> PitchDetector::midi (const float* x, int n) const
{
    if (auto f = hz (x, n)) return 69 + 12 * std::log2 (*f / 440.0);
    return std::nullopt;
}

} // namespace practice
