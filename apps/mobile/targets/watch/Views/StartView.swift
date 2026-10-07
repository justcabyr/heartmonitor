import SwiftUI
import ThresholdEngine

struct StartView: View {
    private let settings = HeartRateSettings.startScreen

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("Alert at \(Int(settings.targetBPM)) BPM")
                Text("warn at \(Int(settings.warningBPM))")
                    .foregroundStyle(.secondary)
                NavigationLink("Start") {
                    LiveView()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
}
