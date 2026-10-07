import SwiftUI
import WatchKit

@main
struct HeartThresholdWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate
    @StateObject private var monitor = HeartRateMonitor()

    var body: some Scene {
        WindowGroup {
            StartView()
                .environmentObject(monitor)
        }
    }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handleActiveWorkoutRecovery() {
        // Phase 6 recovers the HealthKit session and reopens the recording.
    }
}
