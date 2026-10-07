import Foundation
import WatchConnectivity

/// Sends finished recordings to the iPhone and deletes acknowledged copies beyond the newest few.
@MainActor
enum RecordingTransfer {
    private static let pendingKey = "pendingRecordingTransferIds"
    private static let acknowledgedKey = "acknowledgedRecordingIds"
    private static var handedOff = Set<String>()
    private static var statusNote: String?
    private static var onError: ((String) -> Void)?

    static func bind(onError: @escaping (String) -> Void) {
        self.onError = onError
    }

    static func start() {
        guard WCSession.isSupported() else {
            report("This watch cannot send recordings to the iPhone.")
            return
        }
        let session = WCSession.default
        session.delegate = WatchTransferDelegate.shared
        sendFinishedRecordings()
        if session.activationState != .activated {
            session.activate()
        }
    }

    /// Queues every saved recording that the iPhone has not acknowledged, then sends what it can.
    static func sendFinishedRecordings() {
        rememberFinishedRecordings()
        flushPending()
    }

    static func statusText() -> String? {
        if let statusNote {
            return statusNote
        }
        guard !pendingIds().isEmpty else { return nil }
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else {
            return "Waiting to reach the iPhone…"
        }
        return "Sending to iPhone…"
    }

    static func queue(_ id: UUID) {
        var ids = UserDefaults.standard.stringArray(forKey: pendingKey) ?? []
        let token = id.uuidString.lowercased()
        if !ids.contains(token) {
            ids.append(token)
            UserDefaults.standard.set(ids, forKey: pendingKey)
        }
        flushPending()
    }

    static func pendingIds() -> [UUID] {
        let stored = UserDefaults.standard.stringArray(forKey: pendingKey) ?? []
        return stored.compactMap(UUID.init(uuidString:))
    }

    static func activationFinished(state: WCSessionActivationState, errorMessage: String?) {
        if let errorMessage {
            report(errorMessage)
        }
        if state == .activated {
            sendFinishedRecordings()
        }
    }

    static func noteFinished(sessionId: String?, errorMessage: String?) {
        if let sessionId {
            handedOff.remove(sessionId.lowercased())
        } else {
            handedOff.removeAll()
        }
        guard let errorMessage else { return }
        report(errorMessage)
    }

    static func acknowledge(_ id: UUID) {
        let token = id.uuidString.lowercased()
        var pending = UserDefaults.standard.stringArray(forKey: pendingKey) ?? []
        pending.removeAll { $0 == token }
        UserDefaults.standard.set(pending, forKey: pendingKey)
        var acknowledged = UserDefaults.standard.stringArray(forKey: acknowledgedKey) ?? []
        if !acknowledged.contains(token) {
            acknowledged.append(token)
            UserDefaults.standard.set(acknowledged, forKey: acknowledgedKey)
        }
        handedOff.remove(token)
        if pending.isEmpty {
            statusNote = nil
        }
        pruneStoredAcknowledgements()
    }

    static func flushPending() {
        pruneStoredAcknowledgements()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        guard session.isCompanionAppInstalled else {
            report("HeartThreshold is not installed on the iPhone.")
            return
        }

        let outstanding = Set(
            session.outstandingFileTransfers.compactMap { transfer -> String? in
                (transfer.file.metadata?["sessionId"] as? String)?.lowercased()
            }
        )
        let store = RecordingStore()
        var sentAny = false
        var failed = false
        for id in pendingIds() {
            let token = id.uuidString.lowercased()
            if outstanding.contains(token) || handedOff.contains(token) {
                continue
            }
            do {
                let url = try store.bundleFile(for: id)
                guard FileManager.default.fileExists(atPath: url.path) else {
                    failed = true
                    report("A finished recording is missing, so it was not sent to the iPhone.")
                    continue
                }
                session.transferFile(
                    url,
                    metadata: [
                        "sessionId": token,
                        "schemaVersion": AppConstants.schemaVersion,
                    ]
                )
                handedOff.insert(token)
                sentAny = true
            } catch {
                failed = true
                report(error.localizedDescription)
            }
        }
        if sentAny && !failed {
            statusNote = nil
        }
    }

    private static func rememberFinishedRecordings() {
        do {
            let acknowledged = Set(acknowledgedIDs())
            var pending = UserDefaults.standard.stringArray(forKey: pendingKey) ?? []
            var changed = false
            for id in try RecordingStore().finalizedIDs() where !acknowledged.contains(id) {
                let token = id.uuidString.lowercased()
                if !pending.contains(token) {
                    pending.append(token)
                    changed = true
                }
            }
            if changed {
                UserDefaults.standard.set(pending, forKey: pendingKey)
            }
        } catch {
            report(error.localizedDescription)
        }
    }

    private static func acknowledgedIDs() -> [UUID] {
        let stored = UserDefaults.standard.stringArray(forKey: acknowledgedKey) ?? []
        return stored.compactMap(UUID.init(uuidString:))
    }

    private static func pruneStoredAcknowledgements() {
        let acknowledged = UserDefaults.standard.stringArray(forKey: acknowledgedKey) ?? []
        let ids = Set(acknowledged.compactMap(UUID.init(uuidString:)))
        guard !ids.isEmpty else { return }
        do {
            try RecordingStore().pruneAcknowledged(ids)
        } catch {
            report(error.localizedDescription)
        }
    }

    private static func report(_ message: String) {
        statusNote = message
        onError?(message)
    }
}

final class WatchTransferDelegate: NSObject, WCSessionDelegate {
    static let shared = WatchTransferDelegate()

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let message = error?.localizedDescription
        Task { @MainActor in
            RecordingTransfer.activationFinished(state: activationState, errorMessage: message)
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let raw = userInfo["ackSessionId"] as? String, let id = UUID(uuidString: raw) else {
            return
        }
        Task { @MainActor in
            RecordingTransfer.acknowledge(id)
        }
    }

    func session(
        _ session: WCSession,
        didFinish fileTransfer: WCSessionFileTransfer,
        error: Error?
    ) {
        let sessionId = fileTransfer.file.metadata?["sessionId"] as? String
        let message = error?.localizedDescription
        Task { @MainActor in
            RecordingTransfer.noteFinished(sessionId: sessionId, errorMessage: message)
        }
    }
}
