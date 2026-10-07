import Foundation

/// Local queue of finished recordings waiting for the phone.
/// Phase 7 sends them with transferFile and then deletes acknowledged recordings beyond the newest 5.
enum RecordingTransfer {
    private static let key = "pendingRecordingTransferIds"

    static func queue(_ id: UUID) {
        var ids = UserDefaults.standard.stringArray(forKey: key) ?? []
        let token = id.uuidString.lowercased()
        guard !ids.contains(token) else { return }
        ids.append(token)
        UserDefaults.standard.set(ids, forKey: key)
    }

    static func pendingIds() -> [UUID] {
        let stored = UserDefaults.standard.stringArray(forKey: key) ?? []
        return stored.compactMap(UUID.init(uuidString:))
    }
}
