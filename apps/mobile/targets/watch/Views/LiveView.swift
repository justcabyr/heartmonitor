import SwiftUI

struct LiveView: View {
    @EnvironmentObject private var monitor: HeartRateMonitor

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
                Text(SessionClock.string(from: monitor.elapsedTime(at: context.date)))
                    .font(.title3.monospacedDigit())
                if let errorMessage = monitor.errorMessage {
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private var bpmText: String {
        guard let currentBPM = monitor.currentBPM else { return "--" }
        return String(Int(currentBPM.rounded()))
    }
}

#Preview {
    LiveView()
        .environmentObject(HeartRateMonitor())
}
