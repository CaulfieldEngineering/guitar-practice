#pragma once
// How timing becomes accuracy: the same rules as the iPhone app (ios/Practice/Scoring/Scoring.swift) and the shared
// reference (shared/scoring.mjs). The three are checked against one file of test vectors
// (shared/scoring-vectors.json): change a rule in all three together and make the vectors again
// (node scripts/make-scoring-vectors.mjs). The numbers live in catalog/scoring.json, served by the drill server.
#include <optional>
#include <string>
#include <vector>

namespace practice {

struct ScoringConfig {
    int schema = 1;
    double fullFraction = 0.12;   // full credit within this share of the gap to the nearest note
    double zeroFraction = 0.45;   // no credit from this share
    double fullMinMs = 12, fullMaxMs = 25;
    double zeroMinMs = 35, zeroMaxMs = 90;
    double extraWeight = 1;       // each extra note adds this much of a note to what the credit is divided by

    struct Windows { double full, zero; };
    bool isValid() const;
    Windows windows (double gap) const;
    double credit (double errorMs, double gap) const;
};

struct ScoringRule {
    int passMark = 85;
    double tightMs = 20, closeMs = 40;
    std::optional<double> windowMs;
};

struct Onset {
    double time = 0;     // seconds on the run's clock (calibration applied once it is in the run's list)
    float strength = 0;  // peak energy just after the attack
};

enum class Pick { none, down, up };

/// A note to play in a run, in seconds of plan time.
struct Note {
    double time = 0;
    bool accent = false;
    int beat = 0;        // whole beat of the run, for grouping accents
    Pick pick = Pick::none;
    int string = 0;      // 1 is high E; 0 when the drill names none
    int fret = -1;
};

struct ScoreResult {
    int expected = 0, hits = 0, within20 = 0, within40 = 0, missed = 0, extra = 0;
    std::vector<std::optional<double>> errors;   // ms, positive late; empty where missed
    double meanError = 0, spread = 0;
    std::optional<int> accentsLanded, accentBeats;
    int score = 0;
    int passMark = 85;
    int full = 0;
    double fullMs = 0, zeroMs = 0;
    std::vector<double> extraOffsets;

    int pct (int k) const;
    int pct20() const { return pct (within20); }
    int pct40() const { return pct (within40); }
    int pctFull() const { return pct (full); }
    bool passed() const { return score >= passMark; }
};

namespace Scoring {
    constexpr int passMark = 85;

    double window (double shortestGap);
    std::vector<std::optional<int>> match (const std::vector<double>& expected, const std::vector<double>& played, double window);
    std::vector<double> gaps (const std::vector<double>& times);
    /// The accuracy (0..1) of notes [lo, hi): their credit over the notes plus the extras.
    double accuracy (const std::vector<std::optional<double>>& errors, const std::vector<double>& gaps,
                     size_t lo, size_t hi, int extras, const ScoringConfig& config);
    ScoreResult score (const std::vector<Note>& notes, const std::vector<Onset>& played, double window,
                       const ScoringRule& rule = {}, const ScoringConfig& config = {});
    /// Adds a pick unless it is the same pick heard twice; false when it was folded into the one before.
    bool addPick (const Onset& o, std::vector<Onset>& played, double within, float weakerThan = 0.5f);
    std::vector<Onset> dropDoubles (const std::vector<Onset>& list, double within, float weakerThan = 0.5f);
    /// "Locked", "Tight", "Good", "Loose" or "Rough", from the spread in ms.
    std::string band (double spreadMs);

    struct Calibration { double offset, spread; int hits; };
    std::optional<Calibration> calibration (const std::vector<double>& clicks, const std::vector<double>& played);
}

} // namespace practice
