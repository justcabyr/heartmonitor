import SwiftUI
import ThresholdEngine

struct StartView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var monitor: HeartRateMonitor
    @FocusState private var crownFocused: Bool
    @State private var showLive = false
    @State private var showSettings = false
    @State private var isStarting = false
    @State private var crownTarget = HeartRateSettings.startScreen.targetBPM

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
                .focusable()
                .focused($crownFocused)
                .digitalCrownRotation(
                    $crownTarget,
                    from: 60,
                    through: 230,
                    by: 1,
                    sensitivity: .medium,
                    isContinuous: false,
                    isHapticFeedbackEnabled: true
                )
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
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Alert settings")
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
            .sheet(isPresented: $showSettings) {
                AlertSettingsSheet(settings: monitor.settings)
            }
            .onAppear {
                crownTarget = monitor.settings.targetBPM.rounded()
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
            .onChange(of: showSettings) { _, isShowing in
                if !isShowing {
                    crownTarget = monitor.settings.targetBPM.rounded()
                    crownFocused = true
                }
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

private struct AlertSettingsSheet: View {
    @EnvironmentObject private var monitor: HeartRateMonitor
    @Environment(\.dismiss) private var dismiss
    @State private var warningPercent: Int
    @State private var saveToHealth: Bool

    init(settings: HeartRateSettings) {
        _warningPercent = State(initialValue: Int((settings.warningFraction * 100).rounded()))
        _saveToHealth = State(initialValue: settings.saveToHealth)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Stepper(value: $warningPercent, in: 50...99) {
                    Text("Warn at \(warningPercent)%")
                }
                Toggle("Save to Health", isOn: $saveToHealth)
                Button("Done") {
                    dismiss()
                }
            }
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
