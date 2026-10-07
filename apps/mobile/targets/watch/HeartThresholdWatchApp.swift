import SwiftUI
import WatchKit

@main
struct HeartThresholdWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            StartView()
                .environmentObject(appDelegate.monitor)
        }
    }
}

@MainActor
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    private var storedMonitor: HeartRateMonitor?

    var monitor: HeartRateMonitor {
        if let storedMonitor {
            return storedMonitor
        }
        let created = HeartRateMonitor()
        storedMonitor = created
        return created
    }

    func handleActiveWorkoutRecovery() {
        monitor.recoverAfterCrash()
    }

    func applicationDidFinishLaunching() {
        monitor.prepareForLaunchRecovery()
        Task { @MainActor in
            await Task.yield()
            monitor.recoverInterruptedSessionIfNeeded()
        }
    }
}
