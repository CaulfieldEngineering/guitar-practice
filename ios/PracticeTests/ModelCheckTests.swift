import XCTest
@testable import Practice

/// The model checks (ModelChecks.swift), one test each: ascending tempo, the Challenge clock, the routine runner's
/// timing, the drill catalog filter, X notes and pitch, the click options, the pitch detector and routines.
final class ModelCheckTests: XCTestCase {
    private func run(_ name: String) {
        guard let check = ModelChecks.all.first(where: { $0.0 == name }) else { return XCTFail("no check \(name)") }
        var c = ModelChecks()
        check.1(&c)
        XCTAssertGreaterThan(c.count, 0, name)
        for f in c.failures { XCTFail("\(name): \(f)") }
    }

    func testTempoPerLoop() { run("tempo per loop") }
    func testTempoByAccuracy() { run("tempo by accuracy") }
    func testTempoZonesAndBounds() { run("tempo zones and bounds") }
    func testChallengeClock() { run("challenge clock") }
    func testRoutineClock() { run("routine clock") }
    func testDrillCatalogFilter() { run("drill catalog filter") }
    func testXNotesAndPitch() { run("X notes and pitch") }
    func testClickOptions() { run("click options") }
    func testPitchDetector() { run("pitch detector") }
    func testRoutines() { run("routines") }
}
