import SwiftUI
import ThresholdEngine

struct LiveView: View {
    @EnvironmentObject private var monitor: HeartRateMonitor

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(monitor.zone.tint)
                Text(bpmText)
                    .font(.system(size: 48, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(bpmColor)
                Text("BPM")
                    .foregroundStyle(bpmColor)
                Text(statusText)
                    .foregroundStyle(monitor.sessionState == .paused ? Color.secondary : monitor.zone.tint)
                Text(SessionClock.string(from: monitor.elapsedTime(at: context.date)))
                    .font(.title3.monospacedDigit())
                Text("Alert \(targetText) · warn \(warningText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let errorMessage = monitor.errorMessage {
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private var statusText: String {
        if monitor.sessionState == .paused {
            return "Paused"
        }
        return monitor.zone.title
    }

    private var bpmText: String {
        guard let currentBPM = monitor.currentBPM else { return "--" }
        return String(Int(currentBPM.rounded()))
    }

    private var bpmColor: Color {
        monitor.zone == .stale ? .gray : .primary
    }

    private var targetText: String {
        String(Int(monitor.settings.targetBPM.rounded()))
    }

    private var warningText: String {
        String(Int(monitor.settings.warningBPM.rounded()))
    }
}

extension HeartRateZone {
    var tint: Color {
        switch self {
        case .normal:
            return .green
        case .warning:
            return .orange
        case .threshold:
            return .red
        case .stale:
            return .gray
        }
    }
}

#Preview {
    LiveView()
        .environmentObject(HeartRateMonitor())
}
