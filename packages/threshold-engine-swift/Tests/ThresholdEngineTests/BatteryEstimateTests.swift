import XCTest
@testable import ThresholdEngine

final class BatteryEstimateTests: XCTestCase {
    func testDrainOverFifteenMinutesUntilTheGuard() {
        let start = Date(timeIntervalSince1970: 0)
        let readings = [
            BatteryEstimate.Reading(date: start, level: 0.50),
            BatteryEstimate.Reading(date: start.addingTimeInterval(15 * 60), level: 0.40),
        ]
        let remaining = BatteryEstimate.secondsRemaining(
            readings: readings,
            now: start.addingTimeInterval(15 * 60),
            until: 0.10
        )
        XCTAssertEqual(remaining ?? -1, 2_700, accuracy: 1)
    }

    func testSpanShorterThanSixtySecondsIsNotAnEstimate() {
        let start = Date(timeIntervalSince1970: 0)
        let readings = [
            BatteryEstimate.Reading(date: start, level: 0.50),
            BatteryEstimate.Reading(date: start.addingTimeInterval(59), level: 0.40),
        ]
        XCTAssertNil(
            BatteryEstimate.secondsRemaining(
                readings: readings,
                now: start.addingTimeInterval(59),
                until: 0.10
            )
        )
    }

    func testSpanOfExactlySixtySecondsIsAnEstimate() {
        let start = Date(timeIntervalSince1970: 0)
        let readings = [
            BatteryEstimate.Reading(date: start, level: 0.80),
            BatteryEstimate.Reading(date: start.addingTimeInterval(60), level: 0.79),
        ]
        let remaining = BatteryEstimate.secondsRemaining(
            readings: readings,
            now: start.addingTimeInterval(60),
            until: 0.10
        )
        XCTAssertEqual(remaining ?? -1, 4_140, accuracy: 1)
    }

    func testChargingOrFlatIsNotAnEstimate() {
        let start = Date(timeIntervalSince1970: 0)
        let now = start.addingTimeInterval(120)
        XCTAssertNil(
            BatteryEstimate.secondsRemaining(
                readings: [
                    BatteryEstimate.Reading(date: start, level: 0.40),
                    BatteryEstimate.Reading(date: now, level: 0.50),
                ],
                now: now,
                until: 0.10
            )
        )
        XCTAssertNil(
            BatteryEstimate.secondsRemaining(
                readings: [
                    BatteryEstimate.Reading(date: start, level: 0.40),
                    BatteryEstimate.Reading(date: now, level: 0.40),
                ],
                now: now,
                until: 0.10
            )
        )
    }

    func testReadingsOlderThanFifteenMinutesAreDropped() {
        let start = Date(timeIntervalSince1970: 0)
        let now = start.addingTimeInterval(20 * 60)
        let remaining = BatteryEstimate.secondsRemaining(
            readings: [
                BatteryEstimate.Reading(date: start, level: 0.90),
                BatteryEstimate.Reading(date: start.addingTimeInterval(10 * 60), level: 0.50),
                BatteryEstimate.Reading(date: now, level: 0.40),
            ],
            now: now,
            until: 0.10
        )
        XCTAssertEqual(remaining ?? -1, 1_800, accuracy: 1)
    }

    func testAlreadyAtTheGuardReturnsZero() {
        let start = Date(timeIntervalSince1970: 0)
        let now = start.addingTimeInterval(120)
        let remaining = BatteryEstimate.secondsRemaining(
            readings: [
                BatteryEstimate.Reading(date: start, level: 0.20),
                BatteryEstimate.Reading(date: now, level: 0.10),
            ],
            now: now,
            until: 0.10
        )
        XCTAssertEqual(remaining, 0)
    }

    func testTinyDrainIsNotShownAsAHugeCountdown() {
        let start = Date(timeIntervalSince1970: 0)
        let now = start.addingTimeInterval(15 * 60)
        XCTAssertNil(
            BatteryEstimate.secondsRemaining(
                readings: [
                    BatteryEstimate.Reading(date: start, level: 0.50),
                    BatteryEstimate.Reading(date: now, level: 0.499),
                ],
                now: now,
                until: 0.10
            )
        )
    }
}
