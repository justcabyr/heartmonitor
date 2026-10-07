import SwiftUI
import ThresholdEngine

struct StartView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var monitor: HeartRateMonitor
    @State private var showLive = false
    @State private var isStarting = false

    private let settings = HeartRateSettings.startScreen
    private var sessionIsOpen: Bool {
        monitor.sessionState == .running || monitor.sessionState == .paused
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("Alert at \(Int(settings.targetBPM)) BPM")
                Text("warn at \(Int(settings.warningBPM))")
                    .foregroundStyle(.secondary)
                if sessionIsOpen {
                    Button("View session") {
                        showLive = true
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Start") {
                        Task { await start() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isStarting)
                }
                if let errorMessage = monitor.errorMessage {
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
                #if DEBUG
                NavigationLink("Recordings") {
                    RecordingsDebugView()
                }
                #endif
            }
            .padding()
            .navigationDestination(isPresented: $showLive) {
                SessionScreen()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    monitor.flushRecording()
                }
            }
        }
    }

    private func start() async {
        isStarting = true
        defer { isStarting = false }
        do {
            try await monitor.startMonitoring()
            showLive = true
        } catch {
            showLive = false
        }
    }
}

#Preview {
    StartView()
        .environmentObject(HeartRateMonitor())
}
