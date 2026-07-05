@testable import MicStreamer
import XCTest

final class AudioVolumeTests: XCTestCase {
    func testClampKeepsVolumeInSupportedRange() {
        XCTAssertEqual(AudioVolume.clamped(-0.5), 0.0)
        XCTAssertEqual(AudioVolume.clamped(0.75), 0.75)
        XCTAssertEqual(AudioVolume.clamped(3.0), 2.0)
        XCTAssertEqual(AudioVolume.clamped(Float(-1)), Float(0))
        XCTAssertEqual(AudioVolume.clamped(Float(3)), Float(2))
    }

    func testVolumeTitleUsesPercent() {
        XCTAssertEqual(AudioVolume.title(0), "0%")
        XCTAssertEqual(AudioVolume.title(1), "100%")
        XCTAssertEqual(AudioVolume.title(1.25), "125%")
    }

    func testIntegerScalingSaturatesInsteadOfOverflowing() {
        XCTAssertEqual(AudioVolume.scale(Int16(20_000), by: 2), Int16.max)
        XCTAssertEqual(AudioVolume.scale(Int16(-20_000), by: 2), Int16.min)
        XCTAssertEqual(AudioVolume.scale(Int32(1_500_000_000), by: 2), Int32.max)
        XCTAssertEqual(AudioVolume.scale(Int32(-1_500_000_000), by: 2), Int32.min)
    }
}
