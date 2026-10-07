import Foundation
import XCTest

enum VectorFixture {
    static func url(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("contracts")
            .appendingPathComponent(name)
    }

    static func load<T: Decodable>(_ type: T.Type, name: String) throws -> T {
        let file = url(name)
        let data = try Data(contentsOf: file)
        return try JSONDecoder().decode(T.self, from: data)
    }

    static func assertClose(
        _ actual: Double,
        _ expected: Double,
        name: String,
        field: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            actual,
            expected,
            accuracy: 0.000_001,
            "\(name) \(field) expected \(expected) got \(actual)",
            file: file,
            line: line
        )
    }
}
