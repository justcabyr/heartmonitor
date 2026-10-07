import SwiftUI
import ThresholdEngine

struct LiveView: View {
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @EnvironmentObject private var monitor: HeartRateMonitor

    var body: some View {
        Group {
            if isLuminanceReduced {
                liveContent(elapsed: monitor.displayedElapsed)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    liveContent(elapsed: monitor.elapsedTime(at: context.date))
                }
            }
        }
        .transaction { transaction in
            if isLuminanceReduced {
                transaction.disablesAnimations = true
            }
        }
        .onChange(of: isLuminanceReduced, initial: true) { _, reduced in
            monitor.setWristDown(reduced)
        }
    }

    private func liveContent(elapsed: TimeInterval) -> some View {
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
            Text(SessionClock.string(from: elapsed))
                .font(.title3.monospacedDigit())
            Text("Alert \(targetText) · warn \(warningText)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let batteryText {
                Text(batteryText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            if let errorMessage = monitor.errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
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

    private var batteryText: String? {
        guard let level = monitor.batteryLevel, level >= 0 else { return nil }
        let percent = Int((level * 100).rounded())
        guard let remaining = monitor.batterySecondsRemaining else {
            return "\(percent)%"
        }
        return "\(percent)% · \(SessionClock.string(from: remaining)) left"
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
