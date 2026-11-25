import Foundation

/// One play-along run, as kept on the phone and sent to the drill server. Version 1 of the results schema.
struct SessionResult: Codable, Identifiable, Equatable, Hashable {
    var schema = 1
    var id: UUID
    var date: Date
    var exerciseID: String
    var exerciseVersion: Int
    var exerciseName: String
    var mode: String              // cycles, duration, endurance
    var ladderStep: Int
    var guided: Bool
    var startBPM: Int
    var topBPM: Int
    var seconds: Double           // time played (count-in not counted)
    var cycles: Int
    var notes: Int
    var hits: Int
    var missed: Int
    var extra: Int
    var pct20: Int                // within the tight window (the exercise's tightMs, 20 unless it says)
    var pct40: Int                // within the close window
    var tightMs: Double
    var closeMs: Double
    var meanErrorMs: Double       // positive is behind the click
    var spreadMs: Double
    var toleranceMs: Double       // since 0.1.6 (scoringVersion 2): the full-credit window, averaged over the run
    var targetPercent: Int
    var accuracyPercent: Int      // the graded accuracy (scoringVersion 2); before that, the share within toleranceMs
    var sustainedSeconds: Double? // endurance: how long the accuracy held
    var score: Int
    var passed: Bool
    var accentsPercent: Int?
    var offsetMs: Double?
    var appVersion: String
    /// 2: graded accuracy with windows scaled to the note spacing (ScoringConfig). Missing on runs before 0.1.6.
    var scoringVersion: Int? = nil
    /// The windows the notes were judged with, averaged over the run (ms).
    var fullMs: Double? = nil
    var zeroMs: Double? = nil
    /// 0.2.2: picks heard twice and folded into one, and each extra note's distance from its nearest note (ms).
    var doubles: Int? = nil
    var extraOffsetsMs: [Int]? = nil
    /// 0.3.0: how the tempo moved ("perLoop", "accuracy"; nil: it did not), and each change: the tempo curve.
    var tempoMode: String? = nil
    var tempoChanges: [TempoChange]? = nil
    /// Breaks the accuracy called for, and how long they were in all (seconds).
    var breaks: Int? = nil
    var breakSeconds: Double? = nil
    /// Challenge: the time earned at the accuracy, the time it took, and the longest stretch held.
    var earnedSeconds: Double? = nil
    var elapsedSeconds: Double? = nil
    var bestStreakSeconds: Double? = nil
    /// Pitched notes played on the wrong pitch, and the tuning they were judged in.
    var wrongPitch: Int? = nil
    var tuning: String? = nil
    /// The routine run this run was a block of.
    var routineRunID: UUID? = nil
    /// Each stretch at one tempo, in order, with its accuracy; a break is a step of its own (`rest`).
    var tempoSteps: [TempoStep]? = nil
    /// The device the run was played on (the desktop app names itself; the phone leaves it out).
    var device: String? = nil

    /// What "best" means for this run: time held for endurance, the score otherwise.
    var bestValue: Double {
        switch mode {
        case "endurance": return sustainedSeconds ?? 0
        case "challenge": return earnedSeconds ?? 0
        default: return Double(score)
        }
    }
}

/// Bests and progress, from any list of results (the phone's or the server's).
enum Stats {
    struct Best: Equatable, Hashable { var exerciseID: String; var mode: String; var bpm: Int; var value: Double; var runs: Int; var last: Date }

    /// The best solo run for each exercise, mode and tempo. Guided runs are kept but not counted as bests.
    static func bests(_ results: [SessionResult]) -> [Best] {
        var map: [String: Best] = [:]
        for r in results where !r.guided {
            let key = "\(r.exerciseID)|\(r.mode)|\(r.startBPM)"
            if var b = map[key] {
                b.value = max(b.value, r.bestValue); b.runs += 1; b.last = max(b.last, r.date); map[key] = b
            } else {
                map[key] = Best(exerciseID: r.exerciseID, mode: r.mode, bpm: r.startBPM, value: r.bestValue, runs: 1, last: r.date)
            }
        }
        return map.values.sorted { ($0.exerciseID, $0.mode, $0.bpm) < ($1.exerciseID, $1.mode, $1.bpm) }
    }

    static func best(_ results: [SessionResult], exerciseID: String, mode: String, bpm: Int) -> Double? {
        bests(results).first { $0.exerciseID == exerciseID && $0.mode == mode && $0.bpm == bpm }?.value
    }

    /// His level on a drill: the tempo he can be trusted to resume at. Rule 1 (the server's learnedTempo is the same,
    /// and the server's answer wins when it can be reached, so the rule can be tuned there): take his last 10 solo runs
    /// of the drill; the ones that passed (at the drill's target, e.g. 85% within 30 ms) give the tempo they reached;
    /// the level is the second highest of those, so one lucky run does not count. With a single pass, that tempo less
    /// one ladder step. None: no level yet.
    static func learnedTempo(_ results: [SessionResult], exerciseID: String, recent: Int = 10, step: Int = 4) -> Int? {
        let solo = results.filter { $0.exerciseID == exerciseID && !$0.guided }.sorted { $0.date > $1.date }.prefix(recent)
        let passed = solo.filter(\.passed).map(\.topBPM).sorted(by: >)
        if passed.count >= 2 { return passed[1] }
        if let one = passed.first { return max(20, one - step) }
        return nil
    }

    /// The fastest starting tempo with a passing solo run.
    static func fastestPass(_ results: [SessionResult], exerciseID: String) -> Int? {
        results.filter { $0.exerciseID == exerciseID && !$0.guided && $0.passed }.map(\.topBPM).max()
    }
}

/// A stretch of a run at one tempo (or a break), for the result's table.
struct TempoStep: Codable, Equatable, Hashable {
    var bpm: Int
    var seconds: Double
    var accuracy: Int?
    var rest: Bool? = nil

    /// The stretches of a run from its loops (tempo, length, accuracy or nil) and its breaks (after which loop, how long).
    static func from(loops: [(bpm: Int, seconds: Double, accuracy: Double?)], breaks: [(after: Int, seconds: Double)]) -> [TempoStep] {
        var out: [TempoStep] = []
        var credit = 0.0, weight = 0.0
        func close() {
            guard var last = out.popLast() else { return }
            if last.rest != true { last.accuracy = weight > 0 ? Int((credit / weight * 100).rounded()) : nil }
            out.append(last)
            credit = 0; weight = 0
        }
        for (i, l) in loops.enumerated() {
            if out.last?.bpm != l.bpm || out.last?.rest == true {
                close()
                out.append(TempoStep(bpm: l.bpm, seconds: 0, accuracy: nil))
            }
            out[out.count - 1].seconds += l.seconds
            if let a = l.accuracy { credit += a * l.seconds; weight += l.seconds }
            for b in breaks where b.after == i {
                close()
                out.append(TempoStep(bpm: l.bpm, seconds: b.seconds, accuracy: nil, rest: true))
            }
        }
        close()
        return out
    }
}

