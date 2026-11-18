#pragma once
// Finds pick attacks in a guitar signal: the iPhone app's detector (ios/Practice/Engine/OnsetDetector.swift), the
// same maths in the same 32-bit floats, so a pick is found at the same moment on both. A gentle high-pass, energy in
// 2.5 ms hops, and an onset where a hop jumps well above the recent average, the noise floor and the last attack's
// fading energy. Runs on the audio thread: no allocation after construction.
#include "Scoring.h"
#include <array>
#include <vector>

namespace practice {

class OnsetDetector {
public:
    explicit OnsetDetector (double sampleRate, double highPassHz = 800);

    float jumpRatio = 2.5f;
    float floorRatio = 4.0f;
    float minEnergy = 2e-7f;
    double refractory = 0.040;
    float retriggerRatio = 0.3f;
    double envelopeTau = 0.040;

    /// Feeds samples whose first was captured at `time` seconds; calls `found` for each onset finished.
    template <typename Fn>
    void process (const float* samples, int count, double time, Fn&& found)
    {
        for (int i = 0; i < count; ++i)
        {
            if (hopFill == 0) hopStart = time + (double) i / sampleRate;
            const float x = samples[i];
            const float y = hpA * (y1 + x - x1);
            x1 = x; y1 = y;
            hopBuf[(size_t) hopFill++] = y;
            if (hopFill == hop)
            {
                hopFill = 0;
                Onset o;
                if (endHop (o)) found (o);
            }
        }
    }

    std::vector<Onset> process (const std::vector<float>& samples, double time);
    /// The onset still waiting for its strength, if any (call at the end of a run).
    bool flush (Onset& out);
    /// Back to silence, without allocating (the audio thread calls it when a run starts).
    void reset();
    float level() const { return level_; }
    double rate() const { return sampleRate; }

private:
    bool endHop (Onset& finished);
    float noiseFloor() const;

    double sampleRate;
    int hop;
    float envelope = 0, envelopeCoef = 1;
    float hpA, x1 = 0, y1 = 0, avg = 0, avgCoef;
    std::array<float, 10> blockMins;
    float blockMin;
    int blockHops = 0, blockIndex = 0, hopsPerBlock;
    std::vector<float> hopBuf;
    int hopFill = 0;
    double hopStart = 0, lastOnset = -1;
    bool hasPending = false;
    Onset pending;
    int pendingHops = 0;
    float level_ = 0;
};

} // namespace practice
