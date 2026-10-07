import Foundation

@propertyWrapper
struct RecordingUUID: Codable, Equatable, Hashable {
    var wrappedValue: UUID

    init(wrappedValue: UUID) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let id = UUID(uuidString: value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a UUID"
            )
        }
        wrappedValue = id
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue.uuidString.lowercased())
    }
}
