import Foundation

enum ActiveSessionStore {
    private static let key = "activeSessionId"

    static func current() -> UUID? {
        guard let raw = UserDefaults.standard.string(forKey: key) else { return nil }
        guard let id = UUID(uuidString: raw) else {
            UserDefaults.standard.removeObject(forKey: key)
            return nil
        }
        return id
    }

    static func save(_ id: UUID) {
        UserDefaults.standard.set(id.uuidString.lowercased(), forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
