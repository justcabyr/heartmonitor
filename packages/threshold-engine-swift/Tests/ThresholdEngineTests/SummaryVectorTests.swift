import XCTest
@testable import ThresholdEngine

final class SummaryVectorTests: XCTestCase {
    func testEveryAggregationVectorSummary() throws {
        let vectors = try VectorFixture.load([AggregationVector].self, name: "aggregation-test-vectors.json")
        XCTAssertFalse(vectors.isEmpty)
        let names = vectors.map(\.name)
        XCTAssertTrue(names.contains("1-minute buckets with a gap and a pause"))
        XCTAssertTrue(names.contains { $0.contains("avg") })
        XCTAssertTrue(names.contains { $0.contains("gap") })
        XCTAssertTrue(names.contains { $0.contains("pause") })
        XCTAssertTrue(names.contains { $0.contains("10-hour") })

        for vector in vectors {
            let started = Date()
            let samples = samples(for: vector)
            let events = (vector.events ?? []).map {
                SessionEvent(offset: $0.t, kind: SessionEventKind(rawValue: $0.kind) ?? .warning)
            }
            let summary = SummaryCalculator.calculate(
                samples: samples,
                events: events,
                endOffset: vector.summary.endOffset,
                warningBPM: vector.summary.warningBPM,
                targetBPM: vector.summary.targetBPM
            )
            let elapsed = Date().timeIntervalSince(started)
            let expected = vector.summary
            XCTAssertEqual(summary.sampleCount, expected.sampleCount, vector.name)
            VectorFixture.assertClose(summary.avgBPM, expected.avgBPM, name: vector.name, field: "avgBPM")
            VectorFixture.assertClose(summary.minBPM, expected.minBPM, name: vector.name, field: "minBPM")
            VectorFixture.assertClose(summary.maxBPM, expected.maxBPM, name: vector.name, field: "maxBPM")
            VectorFixture.assertClose(summary.activeSeconds, expected.activeSeconds, name: vector.name, field: "activeSeconds")
            VectorFixture.assertClose(summary.pausedSeconds, expected.pausedSeconds, name: vector.name, field: "pausedSeconds")
            VectorFixture.assertClose(
                summary.secondsAboveWarning,
                expected.secondsAboveWarning,
                name: vector.name,
                field: "secondsAboveWarning"
            )
            VectorFixture.assertClose(
                summary.secondsAboveTarget,
                expected.secondsAboveTarget,
                name: vector.name,
                field: "secondsAboveTarget"
            )
            VectorFixture.assertClose(summary.gapSeconds, expected.gapSeconds, name: vector.name, field: "gapSeconds")
            if vector.synthetic != nil {
                XCTAssertLessThan(elapsed, 1, "\(vector.name) summary took \(elapsed)s")
            }
        }
    }

    private func samples(for vector: AggregationVector) -> [HeartRateSample] {
        if let synthetic = vector.synthetic {
            let count = Int(synthetic.durationSeconds / synthetic.sampleEverySeconds) + 1
            return (0..<count).map { index in
                HeartRateSample(
                    offset: Double(index) * synthetic.sampleEverySeconds,
                    bpm: synthetic.baseBPM + Double(index % synthetic.bpmModulus)
                )
            }
        }
        return (vector.samples ?? []).map { HeartRateSample(offset: $0.t, bpm: $0.bpm) }
    }
}

private struct AggregationVector: Decodable {
    struct Sample: Decodable {
        let t: Double
        let bpm: Double
    }

    struct Event: Decodable {
        let t: Double
        let kind: String
    }

    struct Synthetic: Decodable {
        let durationSeconds: Double
        let sampleEverySeconds: Double
        let baseBPM: Double
        let bpmModulus: Int
    }

    struct Summary: Decodable {
        let endOffset: Double
        let warningBPM: Double
        let targetBPM: Double
        let avgBPM: Double
        let minBPM: Double
        let maxBPM: Double
        let sampleCount: Int
        let activeSeconds: Double
        let pausedSeconds: Double
        let secondsAboveWarning: Double
        let secondsAboveTarget: Double
        let gapSeconds: Double
    }

    let name: String
    let samples: [Sample]?
    let events: [Event]?
    let synthetic: Synthetic?
    let summary: Summary
}
