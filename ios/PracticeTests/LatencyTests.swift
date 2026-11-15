import XCTest
@testable import Practice

final class LatencyTests: XCTestCase {
    func testEstimateIsOutputPlusInputPlusBuffer() {
        // Shokz-like Bluetooth output, the phone's mic, a 5 ms buffer.
        XCTAssertEqual(Latency.estimate(output: 0.180, input: 0.012, ioBuffer: 0.005), 0.197, accuracy: 1e-12)
        XCTAssertEqual(Latency.estimate(output: -1, input: 0.01, ioBuffer: 0), 0.01, accuracy: 1e-12)
    }

    func testCalibrationKeepsTheResidualAndFollowsANewEstimate() {
        let estimateThen = 0.197
        let measured = 0.231                     // he played along to the clicks; the median was 231 ms
        let r = Latency.residual(measured: measured, estimate: estimateThen)
        XCTAssertEqual(r, 0.034, accuracy: 1e-12)
        let c = Calibration(residual: r, measured: measured, routeName: "OpenRun", date: Date())
        XCTAssertEqual(Latency.offset(estimate: estimateThen, calibration: c), measured, accuracy: 1e-12)
        // Next day iOS reports 20 ms more Bluetooth delay: the offset follows it.
        XCTAssertEqual(Latency.offset(estimate: 0.217, calibration: c), 0.251, accuracy: 1e-12)
        // No calibration on this route: the estimate alone.
        XCTAssertEqual(Latency.offset(estimate: 0.217, calibration: nil), 0.217, accuracy: 1e-12)
    }

    func testAPerfectPlayerScoresPerfectlyAfterCompensation() {
        // Clicks heard 231 ms after they were made; he plays exactly on what he hears.
        let ex = Exercise(id: "t", name: "t", cycleBeats: 1, notes: Exercise.expand(groups: [4], accentFirst: false), tempo: TempoRule(start: 100))
        let notes = ex.notes(bpm: 100, start: 1, seconds: 6)
        let delay = 0.231
        let raw = notes.map { $0.time + delay }
        let calibration = Calibration(residual: delay - 0.2, measured: delay, routeName: "x", date: Date())
        let offset = Latency.offset(estimate: 0.2, calibration: calibration)
        let played = raw.map { Onset(time: Latency.corrected($0, offset: offset), strength: 1) }
        let r = Scoring.score(notes: notes, played: played, window: ex.window(bpm: 100))
        XCTAssertEqual(r.score, 100)
        XCTAssertEqual(r.meanError, 0, accuracy: 1e-6)
        // Uncompensated, the same playing is a quarter second late and scores nothing.
        let late = Scoring.score(notes: notes, played: raw.map { Onset(time: $0, strength: 1) }, window: ex.window(bpm: 100))
        XCTAssertLessThan(late.score, 20)
    }

    func testCalibrationMeasuresTheWholeDelay() {
        let clicks = (0..<12).map { 1 + Double($0) * 0.75 }
        let played = clicks.enumerated().map { $1 + 0.231 + ($0 % 2 == 0 ? 0.006 : -0.006) }
        XCTAssertEqual(Scoring.calibrate(clicks: clicks, played: played)!, 0.231, accuracy: 1e-9)
    }

    func testRouteKeysAndStorePerRoute() {
        let a = Latency.routeKey(inputs: ["Built-In Microphone"], outputs: ["AA:BB-tacl"])
        let b = Latency.routeKey(inputs: ["USB-1"], outputs: ["AA:BB-tacl"])
        XCTAssertNotEqual(a, b)
        let c = Calibration(residual: 0.03, measured: 0.23, routeName: "OpenRun", date: Date(timeIntervalSince1970: 0))
        CalibrationStore.set(c, for: "test-" + a)
        XCTAssertEqual(CalibrationStore.get("test-" + a), c)
        XCTAssertNil(CalibrationStore.get("test-" + b))
    }
}
