import SwiftUI
import ThresholdEngine

struct LiveView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("--")
                .font(.system(size: 52, weight: .semibold, design: .rounded))
            Text("BPM")
            Text(HeartRateZone.stale.title)
                .foregroundStyle(.secondary)
        }
    }
}
