/// One thing an answer says about TOML that can be checked by parsing or loading it.
public struct TOMLClaim: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable, CaseIterable {
        /// That a text is (or is not) TOML: said in a sentence, or shown by a block labeled `toml`.
        case validity
        /// What a value reads as: "`python_version = 3.10` is read as the string "3.10"".
        case reading
        /// What `tomllib.load` or `tomllib.loads` returns, or a value read out of it, as a Python snippet shows.
        case loading
    }

    public let kind: Kind
    /// The TOML text, the value, or the Python expression the claim is about.
    public let subject: String
    /// What the answer says: `valid TOML`, `the string "3.10"`, or the stated output.
    public let claimed: String
    /// Said in words or shown as output; `false` for a block that only presents itself as TOML, or code
    /// that is shown as if it runs.
    public let isExplicit: Bool
    let task: Task

    init(kind: Kind, subject: String, claimed: String, isExplicit: Bool = true, task: Task) {
        self.kind = kind
        self.subject = subject
        self.claimed = claimed
        self.isExplicit = isExplicit
        self.task = task
    }

    /// One line for a list: the subject and the claim.
    public var excerpt: String {
        let subject = Self.shortened(self.subject)
        switch kind {
        case .validity: return "\(subject) is \(claimed)"
        default: return "\(subject) -> \(Self.shortened(claimed))"
        }
    }

    static func shortened(_ text: String) -> String {
        let flat = text.split(whereSeparator: \.isNewline).map(\.trimmed).joined(separator: " ")
        return flat.count > 60 ? String(flat.prefix(57)) + "..." : flat
    }
}

/// What checking a claim takes.
enum Task: Sendable, Hashable {
    case validate(claimsValid: Bool)
    /// A value as written after `=`, and what the sentence says it reads as.
    case read(String, Expectation)
    case load(Load)
}

/// A `tomllib` call, what is read out of its result, and how the answer shows that.
struct Load: Sendable, Hashable {
    enum Call: Sendable, Hashable {
        /// `tomllib.loads(text)`.
        case loads
        /// `tomllib.load(f)` on a file opened with `"rb"` (or one whose mode the snippet does not show).
        case binaryFile
        /// `tomllib.load(f)` on a file opened in text mode, which raises `TypeError`.
        case textFile
        /// `tomllib.load("pyproject.toml")`: a path, which raises `AttributeError`.
        case path
        /// `tomllib.dumps(...)`, which does not exist; the name as written.
        case dumper(String)

        /// Whether the call raises before any TOML is read.
        var alwaysRaises: Bool {
            switch self {
            case .loads, .binaryFile: false
            case .textFile, .path, .dumper: true
            }
        }
    }

    enum Output: Sendable, Hashable {
        /// What the REPL echoes, or a comment after the expression: Python's `repr`.
        case repr
        /// What `print` shows: a string without quotes.
        case print
        /// What `type(...)` shows: `<class 'float'>`.
        case type
    }

    let source: String
    let call: Call
    let accessors: [Accessor]
    let output: Output
}

/// A step from a loaded value to a part of it: `["tool"]`, `[0]`, `.get("tags", [])`.
enum Accessor: Sendable, Hashable {
    case subscripted(TOMLValue)
    case get(TOMLValue, fallback: TOMLValue)
}

/// What a sentence says a value reads as.
struct Expectation: Sendable, Hashable {
    enum Target: Sendable, Hashable {
        case type(TypeClass)
        case value(TOMLValue)
        /// "the number 1000": an integer or a float equal to it.
        case number(Double)
    }

    let target: Target
    let negated: Bool

    func holds(_ value: TOMLValue) -> Bool {
        matches(value) != negated
    }

    func matches(_ value: TOMLValue) -> Bool {
        switch (target, value) {
        case let (.type(type), _): type.contains(value)
        case let (.value(expected), _): expected.same(value)
        case let (.number(expected), .int(number)): Double(number) == expected
        case let (.number(expected), .float(number)): number == expected
        default: false
        }
    }
}

enum TypeClass: String, Sendable, Hashable, CaseIterable {
    case string, boolean, integer, float, number, date, time, datetime, array, table

    func contains(_ value: TOMLValue) -> Bool {
        switch (self, value) {
        case (.string, .string), (.boolean, .bool), (.integer, .int), (.float, .float), (.date, .date),
             (.time, .time), (.datetime, .dateTime), (.array, .array), (.table, .table), (.number, .int),
             (.number, .float):
            true
        default:
            false
        }
    }

    var representative: TOMLValue {
        switch self {
        case .string: .string("")
        case .boolean: .bool(true)
        case .integer: .int(0)
        case .float, .number: .float(0)
        case .date: .date(TOMLDate(year: 2000, month: 1, day: 1))
        case .time: .time(TOMLTime(hour: 0, minute: 0, second: 0))
        case .datetime: .dateTime(TOMLDateTime(date: TOMLDate(year: 2000, month: 1, day: 1),
                                               time: TOMLTime(hour: 0, minute: 0, second: 0)))
        case .array: .array([])
        case .table: .table([])
        }
    }
}
