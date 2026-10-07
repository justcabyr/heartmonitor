import SwiftUI
import ThresholdEngine

struct StartView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var monitor: HeartRateMonitor
    @State private var showLive = false
    @State private var showSettings = false
    @State private var isStarting = false

    private var sessionIsOpen: Bool {
        monitor.sessionState == .running || monitor.sessionState == .paused
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                VStack(spacing: 4) {
                    Text("Alert at \(Int(monitor.settings.targetBPM.rounded())) BPM")
                    Text("warn at \(Int(monitor.settings.warningBPM.rounded()))")
                        .foregroundStyle(.secondary)
                }
                if monitor.isRecovering {
                    Text("Restoring session")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
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
                    .disabled(isStarting || monitor.isRecovering)
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
                Button("Settings") {
                    showSettings = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Alert settings")
            }
            .padding()
            .navigationDestination(isPresented: $showLive) {
                SessionScreen()
            }
            .sheet(isPresented: $showSettings) {
                AlertSettingsSheet(settings: monitor.settings)
            }
            .onAppear {
                presentRecoveredSession()
            }
            .onChange(of: monitor.openSessionScreen) { _, open in
                if open {
                    presentRecoveredSession()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    RecordingTransfer.sendFinishedRecordings()
                }
                if phase == .background {
                    monitor.flushRecording()
                }
            }
        }
    }

    private func presentRecoveredSession() {
        guard monitor.openSessionScreen else { return }
        showLive = true
        monitor.consumeOpenSessionScreen()
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

private struct AlertSettingsSheet: View {
    @EnvironmentObject private var monitor: HeartRateMonitor
    @Environment(\.dismiss) private var dismiss
    @FocusState private var crownFocused: Bool
    @State private var warningPercent: Int
    @State private var saveToHealth: Bool
    @State private var crownTarget: Double

    init(settings: HeartRateSettings) {
        _warningPercent = State(initialValue: Int((settings.warningFraction * 100).rounded()))
        _saveToHealth = State(initialValue: settings.saveToHealth)
        _crownTarget = State(initialValue: settings.targetBPM.rounded())
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                VStack(spacing: 2) {
                    Text("Alert at \(Int(crownTarget.rounded())) BPM")
                        .font(.body)
                    Text("warn at \(Int(monitor.settings.warningBPM.rounded()))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .focusable()
                .focused($crownFocused)
                .digitalCrownRotation(
                    $crownTarget,
                    from: 60,
                    through: 230,
                    by: 1,
                    sensitivity: .low,
                    isContinuous: false,
                    isHapticFeedbackEnabled: true
                )
                HStack(spacing: 6) {
                    Button {
                        warningPercent = max(50, warningPercent - 1)
                    } label: {
                        Image(systemName: "minus")
                    }
                    .accessibilityLabel("Lower warning")
                    Text("Warn at\n\(warningPercent)%")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity)
                    Button {
                        warningPercent = min(99, warningPercent + 1)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Raise warning")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Toggle("Save to Health", isOn: $saveToHealth)
                    .font(.footnote)
                Button("Done") {
                    dismiss()
                }
            }
        }
        .onAppear {
            crownFocused = true
        }
        .onChange(of: crownTarget) { _, newValue in
            let rounded = newValue.rounded()
            if rounded != newValue {
                crownTarget = rounded
                return
            }
            monitor.setTargetBPM(rounded)
        }
        .onChange(of: warningPercent) { _, percent in
            monitor.setWarningFraction(Double(percent) / 100)
        }
        .onChange(of: saveToHealth) { _, save in
            monitor.setSaveToHealth(save)
        }
    }
}

#Preview {
    StartView()
        .environmentObject(HeartRateMonitor())
}
