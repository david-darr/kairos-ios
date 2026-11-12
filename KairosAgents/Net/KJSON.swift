import Foundation

/// A JSON value of any shape, for the fields the desktop sends free-form.
nonisolated enum JSONValue: Decodable, Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "A JSON value of no known kind")
        }
    }

    var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var double: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    var int: Int? {
        if case .number(let value) = self { return Int(value) }
        return nil
    }

    var bool: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var array: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var object: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let value) = self { return value[key] }
        return nil
    }

    /// The value as short plain text, for showing a free-form detail.
    var plainText: String {
        switch self {
        case .null: return ""
        case .bool(let value): return value ? "yes" : "no"
        case .number(let value): return value == value.rounded() ? String(Int(value)) : String(value)
        case .string(let value): return value
        case .array(let values): return values.map(\.plainText).joined(separator: ", ")
        case .object(let values):
            return values.keys.sorted().map { "\($0): \(values[$0]?.plainText ?? "")" }.joined(separator: "\n")
        }
    }
}

/// A time the desktop sent either as epoch seconds or as ISO 8601 text.
nonisolated struct FlexibleDate: Decodable, Hashable, Sendable {
    var date: Date?

    init(date: Date?) { self.date = date }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            date = nil
        } else if let seconds = try? container.decode(Double.self) {
            date = Date(timeIntervalSince1970: seconds)
        } else if let text = try? container.decode(String.self) {
            date = FlexibleDate.parse(text)
        } else {
            date = nil
        }
    }

    static func parse(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: text) { return date }
        // A time with no zone is UTC by the contract.
        if let date = plain.date(from: text + "Z") { return date }
        return nil
    }
}

/// One decoder for everything the desktop sends. Keys arrive in snake_case (the routes) or camelCase
/// (the live stream) and both land in camelCase properties.
nonisolated enum KJSON {
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder().decode(type, from: data)
    }

    static func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        try decoder().decode(type, from: Data(text.utf8))
    }
}

/// One check of a bundled sample answer against its real decoder. There is no test target,
/// so the debug view `chat.decoders` runs these and shows a pass or fail list.
nonisolated struct DecodeCheck: Identifiable, Sendable {
    let id: String
    let run: @Sendable () throws -> String

    init(_ id: String, _ run: @escaping @Sendable () throws -> String) {
        self.id = id
        self.run = run
    }
}

/// A sample that decoded but did not hold what it should.
nonisolated struct SampleMismatch: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
