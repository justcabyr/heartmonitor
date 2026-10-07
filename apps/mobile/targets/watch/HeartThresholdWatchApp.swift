import SwiftUI
import WatchKit

@main
struct HeartThresholdWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            StartView()
        }
    }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handleActiveWorkoutRecovery() {
        // Phase 6 recovers the HealthKit session and reopens the recording.
    }
}
