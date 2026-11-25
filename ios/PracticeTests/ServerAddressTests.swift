import XCTest
@testable import Practice

/// The drill server's address as typed in Settings or carried by the build (DrillServer.url(from:)): nothing in the
/// source names Joe's server, so every way it is written has to come out as one URL, and nonsense as none.
final class ServerAddressTests: XCTestCase {
    func testBlanksAndUnsetBuildSettingsAreNothing() {
        XCTAssertNil(DrillServer.url(from: nil))
        XCTAssertNil(DrillServer.url(from: ""))
        XCTAssertNil(DrillServer.url(from: "   \n"))
        XCTAssertNil(DrillServer.url(from: "$(PRACTICE_SERVER_URL)"))
        XCTAssertNil(DrillServer.url(from: "ftp://host:4700"))
    }

    func testHostAloneGetsSchemeAndPort() {
        XCTAssertEqual(DrillServer.url(from: "10.0.0.5")?.absoluteString, "http://10.0.0.5:4700")
        XCTAssertEqual(DrillServer.url(from: "drills.example:8080")?.absoluteString, "http://drills.example:8080")
    }

    func testFullAddressIsKeptWithoutTrailingSlash() {
        XCTAssertEqual(DrillServer.url(from: " http://10.0.0.5:4700/ ")?.absoluteString, "http://10.0.0.5:4700")
        XCTAssertEqual(DrillServer.url(from: "https://drills.example")?.absoluteString, "https://drills.example:4700")
    }

    func testSettingsWinOverTheBuildAndPathsAppend() {
        let d = UserDefaults.standard
        let before = d.string(forKey: DrillServer.addressKey)
        defer { d.set(before, forKey: DrillServer.addressKey) }
        d.set("10.1.2.3", forKey: DrillServer.addressKey)
        XCTAssertEqual(DrillServer.base.absoluteString, "http://10.1.2.3:4700")
        XCTAssertEqual(DrillServer.base.appendingPathComponent("api/routines").absoluteString, "http://10.1.2.3:4700/api/routines")
        d.removeObject(forKey: DrillServer.addressKey)
        // The test build carries no address, so it falls back to this device.
        XCTAssertEqual(DrillServer.base, DrillServer.fallback)
    }
}
