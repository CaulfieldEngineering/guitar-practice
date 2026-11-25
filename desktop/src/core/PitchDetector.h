#pragma once
// The pitch of a picked note (2026-11-24, for drills whose notes ask for a pitch; an X note never needs it): YIN over
// a short stretch just after the attack, the same as the phone's Engine/PitchDetector.swift. 50 to 1400 Hz; a stretch
// with no clear period (a muted chug, noise) gives nothing, which the scoring never holds against him.
#include <optional>
#include <vector>

namespace practice {

struct PitchDetector {
    double sampleRate = 48000;
    double minHz = 50, maxHz = 1400, threshold = 0.15;
    int window() const { return (int) (sampleRate * 0.046 + 0.5); }
    int skip() const { return (int) (sampleRate * 0.008 + 0.5); }
    int needed() const { return skip() + window() + (int) (sampleRate / minHz) + 2; }
    std::optional<double> hz (const float* x, int n) const;
    std::optional<double> midi (const float* x, int n) const;
};

} // namespace practice
