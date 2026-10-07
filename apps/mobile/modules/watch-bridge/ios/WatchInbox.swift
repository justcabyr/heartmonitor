import Foundation
import WatchConnectivity

enum WatchInboxError: LocalizedError {
    case missingSessionId
    case unreadableFile
    case outsideInbox

    var errorDescription: String? {
        switch self {
        case .missingSessionId:
            return "A recording arrived without a session id and will be sent again."
        case .unreadableFile:
            return "A recording could not be saved on this iPhone and will be sent again."
        case .outsideInbox:
            return "A recording path was rejected."
        }
    }
}

/// Phone-side inbox. The received WatchConnectivity file is moved here before
/// `session(_:didReceive:)` returns, because iOS deletes the temporary file after that.
final class WatchInbox: NSObject {
    static let shared = WatchInbox()

    private let lock = NSLock()
    private let errorKey = "watchBridge.lastReceiveError"

    func note(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        UserDefaults.standard.set(message, forKey: errorKey)
    }

    func takeLastError() -> String? {
        lock.lock()
        defer { lock.unlock() }
        let message = UserDefaults.standard.string(forKey: errorKey)
        UserDefaults.standard.removeObject(forKey: errorKey)
        return message
    }

    /// Moves `file` into Documents/inbox and acknowledges only after the move succeeds.
    func store(_ file: WCSessionFile, session: WCSession) {
        lock.lock()
        defer { lock.unlock() }
        do {
            let sessionId = try sessionId(from: file)
            let inbox = try inboxDirectory()
            let destination = try fileURL(sessionId: sessionId, in: inbox)
            let incoming = inbox.appendingPathComponent(".incoming-\(sessionId).json")
            if FileManager.default.fileExists(atPath: incoming.path) {
                try FileManager.default.removeItem(at: incoming)
            }
            try FileManager.default.moveItem(at: file.fileURL, to: incoming)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: incoming, to: destination)
            session.transferUserInfo(["ackSessionId": sessionId])
        } catch {
            UserDefaults.standard.set(error.localizedDescription, forKey: errorKey)
        }
    }

    func read() throws -> [[String: String]] {
        lock.lock()
        defer { lock.unlock() }
        let inbox = try inboxDirectory()
        guard FileManager.default.fileExists(atPath: inbox.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(
            at: inbox,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        var files: [[String: String]] = []
        for url in urls {
            let name = url.lastPathComponent
            guard sessionId(fromFileName: name) != nil else { continue }
            do {
                let json = try String(contentsOf: url, encoding: .utf8)
                files.append(["name": name, "json": json])
            } catch {
                UserDefaults.standard.set(
                    "A recording in the inbox could not be read.",
                    forKey: errorKey
                )
            }
        }
        return files.sorted { ($0["name"] ?? "") < ($1["name"] ?? "") }
    }

    func remove(named name: String) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let sessionId = sessionId(fromFileName: name) else {
            throw WatchInboxError.outsideInbox
        }
        let inbox = try inboxDirectory()
        let destination = try fileURL(sessionId: sessionId, in: inbox)
        guard FileManager.default.fileExists(atPath: destination.path) else { return }
        try FileManager.default.removeItem(at: destination)
    }

    private func sessionId(from file: WCSessionFile) throws -> String {
        if let raw = file.metadata?["sessionId"] as? String, let id = UUID(uuidString: raw) {
            return id.uuidString.lowercased()
        }
        if let id = sessionId(fromFileName: file.fileURL.lastPathComponent) {
            return id
        }
        throw WatchInboxError.missingSessionId
    }

    private func sessionId(fromFileName name: String) -> String? {
        let prefix = "session-"
        let suffix = ".json"
        guard name.hasPrefix(prefix), name.hasSuffix(suffix), !name.contains(".."), !name.contains("/") else {
            return nil
        }
        let start = name.index(name.startIndex, offsetBy: prefix.count)
        let end = name.index(name.endIndex, offsetBy: -suffix.count)
        guard start <= end else { return nil }
        let token = String(name[start..<end])
        guard token == token.lowercased(), UUID(uuidString: token) != nil else { return nil }
        return token
    }

    private func inboxDirectory() throws -> URL {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw WatchInboxError.unreadableFile
        }
        let inbox = documents.appendingPathComponent("inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        return inbox
    }

    private func fileURL(sessionId: String, in inbox: URL) throws -> URL {
        let destination = inbox.appendingPathComponent("session-\(sessionId).json")
        let inboxPath = inbox.resolvingSymlinksInPath().standardizedFileURL.path
        let destinationPath = destination.resolvingSymlinksInPath().standardizedFileURL.path
        let prefix = inboxPath.hasSuffix("/") ? inboxPath : inboxPath + "/"
        guard destinationPath.hasPrefix(prefix) else {
            throw WatchInboxError.outsideInbox
        }
        return destination
    }
}
