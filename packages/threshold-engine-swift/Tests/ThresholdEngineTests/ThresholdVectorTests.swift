import XCTest
@testable import ThresholdEngine

final class ThresholdVectorTests: XCTestCase {
    func testEveryThresholdVector() throws {
        let vectors = try VectorFixture.load([ThresholdVector].self, name: "threshold-test-vectors.json")
        XCTAssertFalse(vectors.isEmpty)
        let names = vectors.map(\.name)
        XCTAssertTrue(names.contains("warning entry fires once, then cooldown suppresses"))
        XCTAssertTrue(names.contains { $0.contains("boundaries") })
        XCTAssertTrue(names.contains { $0.contains("hysteresis") })
        XCTAssertTrue(names.contains { $0.contains("cooldown") })
        XCTAssertTrue(names.contains { $0.contains("stale") })
        XCTAssertTrue(names.contains { $0.contains("settings change") })

        for vector in vectors {
            var engine = ThresholdEngine(settings: makeSettings(vector.settings))
            XCTAssertEqual(
                vector.samples.count,
                vector.expected.count,
                vector.name
            )
            for (step, expected) in zip(vector.samples, vector.expected) {
                if let replacement = step.settings {
                    engine.replaceSettings(makeSettings(replacement))
                }
                let now = Date(timeIntervalSince1970: step.t)
                let evaluation: ThresholdEvaluation
                if let bpm = step.bpm {
                    evaluation = engine.evaluate(bpm: bpm, at: now)
                } else {
                    evaluation = engine.advance(to: now)
                }
                let alert = evaluation.alert?.rawValue
                XCTAssertEqual(step.t, expected.t, vector.name)
                XCTAssertEqual(
                    evaluation.zone.rawValue,
                    expected.zone,
                    "\(vector.name) t=\(step.t) zone"
                )
                XCTAssertEqual(
                    alert,
                    expected.alert,
                    "\(vector.name) t=\(step.t) alert expected \(expected.alert ?? "nil") got \(alert ?? "nil")"
                )
            }
        }
    }

    func testMarkFreshRestartsTheStaleClockWithoutAlerting() {
        let settings = HeartRateSettings(
            targetBPM: 150,
            warningFraction: 0.9,
            warningCooldown: 60,
            thresholdCooldown: 30,
            hysteresisBPM: 5,
            staleTimeout: 10,
            batteryGuardLevel: 0.10,
            saveToHealth: false
        )
        var engine = ThresholdEngine(settings: settings)
        let start = Date(timeIntervalSince1970: 0)
        let first = engine.evaluate(bpm: 100, at: start)
        XCTAssertEqual(first.zone, .normal)
        XCTAssertNil(first.alert)

        let stale = engine.advance(to: start.addingTimeInterval(10))
        XCTAssertEqual(stale.zone, .stale)
        XCTAssertEqual(stale.alert, .stale)

        engine.markFresh(at: start.addingTimeInterval(12))
        let resumed = engine.advance(to: start.addingTimeInterval(13))
        XCTAssertEqual(resumed.zone, .normal)
        XCTAssertNil(resumed.alert)
    }

    private func makeSettings(_ settings: ThresholdVector.Settings) -> HeartRateSettings {
        HeartRateSettings(
            targetBPM: settings.targetBPM,
            warningFraction: settings.warningFraction,
            warningCooldown: settings.warningCooldown,
            thresholdCooldown: settings.thresholdCooldown,
            hysteresisBPM: settings.hysteresisBPM,
            staleTimeout: settings.staleTimeout ?? 10,
            batteryGuardLevel: 0.10,
            saveToHealth: false
        )
    }
}

private struct ThresholdVector: Decodable {
    struct Settings: Decodable {
        let targetBPM: Double
        let warningFraction: Double
        let warningCooldown: Double
        let thresholdCooldown: Double
        let hysteresisBPM: Double
        let staleTimeout: Double?
    }

    struct Step: Decodable {
        let t: Double
        let bpm: Double?
        let settings: Settings?
    }

    struct Expected: Decodable {
        let t: Double
        let zone: String
        let alert: String?
    }

    let name: String
    let settings: Settings
    let samples: [Step]
    let expected: [Expected]
}
