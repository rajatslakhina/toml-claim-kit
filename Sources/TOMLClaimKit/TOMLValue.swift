import Foundation

/// A value as Python's `tomllib` builds it, compared the way an answer's claim about it is: types must
/// match, a table's key order does not matter.
public indirect enum TOMLValue: Sendable, Hashable {
    case string(String)
    case int(Int)
    case float(Double)
    case bool(Bool)
    /// A local date, `2024-01-02`: a `datetime.date`.
    case date(TOMLDate)
    /// A local time, `10:30:00`: a `datetime.time`.
    case time(TOMLTime)
    /// A local or offset date-time: a `datetime.datetime`, with `tzinfo` when it has an offset.
    case dateTime(TOMLDateTime)
    case array([TOMLValue])
    case table([TOMLPair])
    /// Python's `None`. TOML has no null; this is what `.get` gives for a missing key, or what an answer
    /// claims.
    case null
}

public struct TOMLDate: Sendable, Hashable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }
}

public struct TOMLTime: Sendable, Hashable {
    public let hour: Int
    public let minute: Int
    public let second: Int
    /// `tomllib` keeps six digits of a fraction and drops the rest.
    public let microsecond: Int

    public init(hour: Int, minute: Int, second: Int, microsecond: Int = 0) {
        self.hour = hour
        self.minute = minute
        self.second = second
        self.microsecond = microsecond
    }
}

public struct TOMLDateTime: Sendable, Hashable {
    public let date: TOMLDate
    public let time: TOMLTime
    /// Minutes east of UTC; `nil` for a local date-time.
    public let offsetMinutes: Int?

    public init(date: TOMLDate, time: TOMLTime, offsetMinutes: Int? = nil) {
        self.date = date
        self.time = time
        self.offsetMinutes = offsetMinutes
    }
}

public struct TOMLPair: Sendable, Hashable {
    public let key: String
    public let value: TOMLValue

    public init(key: String, value: TOMLValue) {
        self.key = key
        self.value = value
    }
}

extension TOMLValue {
    /// The same value: types must match, a table's order does not matter, `nan` matches `nan`.
    func same(_ other: TOMLValue) -> Bool {
        switch (self, other) {
        case let (.array(left), .array(right)):
            return left.count == right.count && zip(left, right).allSatisfy { $0.same($1) }
        case let (.table(left), .table(right)):
            return left.count == right.count && left.allSatisfy { pair in
                right.contains { $0.key == pair.key && $0.value.same(pair.value) }
            }
        case let (.float(left), .float(right)):
            return left == right || (left.isNaN && right.isNaN)
        default:
            return self == other
        }
    }

    /// The value under `key` in a table, as Python's `dict[key]` finds it.
    func lookup(_ key: TOMLValue) -> TOMLValue? {
        guard case let .table(pairs) = self, case let .string(name) = key else { return nil }
        return pairs.first { $0.key == name }?.value
    }

    /// A table's pairs; nothing for any other value.
    var members: [TOMLPair] {
        if case let .table(pairs) = self { return pairs }
        return []
    }

    var isString: Bool {
        if case .string = self { return true }
        return false
    }

    var isContainer: Bool {
        switch self {
        case .array, .table: true
        default: false
        }
    }

    /// The value in words, for an explanation: `the string "3.10"`, `the float 3.1`.
    var described: String {
        switch self {
        case .null: "None"
        case let .bool(flag): "the boolean \(flag ? "true" : "false")"
        case let .int(number): "the integer \(number)"
        case let .float(number): "the float \(Self.pythonFloat(number))"
        case let .string(text): "the string \"\(text)\""
        case .date: "the date \(pythonStr)"
        case .time: "the time \(pythonStr)"
        case .dateTime: "the datetime \(pythonStr)"
        default: pythonRepr
        }
    }
}
