import SwiftUI
import ThresholdEngine

struct LiveView: View {
    @EnvironmentObject private var monitor: HeartRateMonitor
    @Environment(\.dismiss) private var dismiss
    @State private var confirmEnd = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                Text(bpmText)
                    .font(.system(size: 48, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.6)
                Text("BPM")
                Text(monitor.stateTitle)
                    .foregroundStyle(.secondary)
                Text(Self.clock(monitor.elapsedTime(at: context.date)))
                    .font(.title3.monospacedDigit())
                if let errorMessage = monitor.errorMessage {
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
                Button(monitor.sessionState == .ended ? "Done" : "End") {
                    if monitor.sessionState == .ended {
                        dismiss()
                    } else {
                        confirmEnd = true
                    }
                }
            }
        }
        .confirmationDialog("End session?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End", role: .destructive) {
                Task {
                    await monitor.stopMonitoring(saveToHealth: HeartRateSettings.startScreen.saveToHealth)
                    if monitor.errorMessage == nil {
                        dismiss()
                    }
                }
            }
            Button("Keep going", role: .cancel) {}
        }
    }

    private var bpmText: String {
        guard let currentBPM = monitor.currentBPM else { return "--" }
        return String(Int(currentBPM.rounded()))
    }

    private static func clock(_ elapsed: TimeInterval) -> String {
        let total = max(0, Int(elapsed))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    LiveView()
        .environmentObject(HeartRateMonitor())
}
