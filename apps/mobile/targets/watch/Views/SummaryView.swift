import SwiftUI

struct SummaryView: View {
    @Environment(\.dismiss) private var dismiss

    let summary: MonitoringSummary

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                Text("Duration")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(SessionClock.string(from: summary.activeSeconds))
                    .font(.title3.monospacedDigit())
                Text("Avg \(bpm(summary.avgBPM))")
                Text("Min \(bpm(summary.minBPM))  Max \(bpm(summary.maxBPM))")
                    .font(.caption)
                Text("Above target \(SessionClock.string(from: summary.secondsAboveTarget))")
                    .font(.caption2)
                Text("Warnings \(summary.warningEvents)")
                    .font(.caption2)
                Text("Thresholds \(summary.thresholdEvents)")
                    .font(.caption2)
                if summary.endReason != .user {
                    Text(summary.endReason.title)
                        .font(.caption2)
                }
                Button("Done") {
                    dismiss()
                }
            }
        }
    }

    private func bpm(_ value: Double) -> String {
        String(Int(value.rounded()))
    }
}

#Preview {
    SummaryView(
        summary: MonitoringSummary(
            id: UUID(uuidString: "6f1b1c3e-8a2d-4e5b-9c11-2d4a6b8e0f31") ?? UUID(),
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 1800),
            activeSeconds: 1800,
            sampleCount: 1,
            avgBPM: 82,
            minBPM: 61,
            maxBPM: 140,
            warningEvents: 0,
            thresholdEvents: 0,
            secondsAboveWarning: 0,
            secondsAboveTarget: 45,
            gapSeconds: 0,
            endReason: .user
        )
    )
}
