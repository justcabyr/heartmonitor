import Foundation
import WatchConnectivity

final class WatchSessionController: NSObject, WCSessionDelegate {
    static let shared = WatchSessionController()

    var onRecordingReceived: (() -> Void)?
    var onStatusChange: (() -> Void)?

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        if session.activationState != .activated {
            session.activate()
        }
    }

    func status() -> [String: Any?] {
        guard WCSession.isSupported() else {
            return inactiveStatus()
        }
        let session = WCSession.default
        guard session.activationState == .activated else {
            return inactiveStatus()
        }
        return [
            "platform": "watchos",
            "paired": session.isPaired,
            "appInstalled": session.isWatchAppInstalled,
            "reachable": session.isReachable,
        ]
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            WatchInbox.shared.note(error.localizedDescription)
        }
        DispatchQueue.main.async {
            self.onStatusChange?()
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.onStatusChange?()
        }
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        WatchInbox.shared.store(file, session: session)
        DispatchQueue.main.async {
            self.onRecordingReceived?()
        }
    }

    private func inactiveStatus() -> [String: Any?] {
        [
            "platform": "watchos",
            "paired": false,
            "appInstalled": false,
            "reachable": false,
        ]
    }
}
