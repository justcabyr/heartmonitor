import SwiftUI

struct SessionScreen: View {
    @EnvironmentObject private var monitor: HeartRateMonitor
    @Environment(\.dismiss) private var dismiss
    @State private var page = 1

    var body: some View {
        Group {
            if let summary = monitor.finishedSummary {
                SummaryView(summary: summary)
            } else if monitor.sessionState == .ended {
                VStack(spacing: 8) {
                    Text(monitor.errorMessage ?? "The recording could not be saved.")
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                    Button("Done") {
                        dismiss()
                    }
                }
            } else {
                TabView(selection: $page) {
                    ControlsView()
                        .tag(0)
                    LiveView()
                        .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
            }
        }
        .navigationBarBackButtonHidden(monitor.finishedSummary != nil || monitor.sessionState == .ended)
        .onAppear {
            if monitor.finishedSummary == nil && monitor.sessionState != .ended {
                page = 1
            }
        }
    }
}
