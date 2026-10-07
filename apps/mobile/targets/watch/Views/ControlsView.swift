import SwiftUI
import ThresholdEngine

struct ControlsView: View {
    @EnvironmentObject private var monitor: HeartRateMonitor
    @State private var confirmEnd = false

    private var canControl: Bool {
        monitor.sessionState == .running || monitor.sessionState == .paused
    }

    var body: some View {
        VStack(spacing: 12) {
            Button(monitor.sessionState == .paused ? "Resume" : "Pause") {
                if monitor.sessionState == .paused {
                    monitor.resume()
                } else {
                    monitor.pause()
                }
            }
            .buttonStyle(.bordered)
            .disabled(!canControl)
            Button("End", role: .destructive) {
                confirmEnd = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canControl)
            if let errorMessage = monitor.errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .confirmationDialog("End session?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End", role: .destructive) {
                Task {
                    await monitor.stopMonitoring(saveToHealth: HeartRateSettings.startScreen.saveToHealth)
                }
            }
            Button("Keep going", role: .cancel) {}
        }
    }
}

#Preview {
    ControlsView()
        .environmentObject(HeartRateMonitor())
}
