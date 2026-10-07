import ExpoModulesCore
import UIKit
import WatchConnectivity

public class WatchBridgeAppDelegate: ExpoAppDelegateSubscriber {
    public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        WatchSessionController.shared.activate()
        return true
    }
}

public class WatchBridgeModule: Module {
    public func definition() -> ModuleDefinition {
        Name("WatchBridge")

        Events("onRecordingReceived", "onStatusChange")

        OnCreate {
            WatchSessionController.shared.onRecordingReceived = { [weak self] in
                self?.sendEvent("onRecordingReceived")
            }
            WatchSessionController.shared.onStatusChange = { [weak self] in
                self?.sendEvent("onStatusChange", WatchSessionController.shared.status())
            }
        }

        AsyncFunction("isSupported") { () -> Bool in
            WCSession.isSupported()
        }

        AsyncFunction("getStatus") { () -> [String: Any?] in
            WatchSessionController.shared.status()
        }

        AsyncFunction("readInbox") { () throws -> [[String: String]] in
            try WatchInbox.shared.read()
        }

        AsyncFunction("removeInboxFile") { (name: String) throws in
            try WatchInbox.shared.remove(named: name)
        }

        AsyncFunction("takeLastError") { () -> String? in
            WatchInbox.shared.takeLastError()
        }
    }
}
