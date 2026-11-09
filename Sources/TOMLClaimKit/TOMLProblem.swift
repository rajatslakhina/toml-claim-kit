/// Why a text is not TOML, and where: the first mistake a TOML 1.0 parser stops at.
public struct TOMLProblem: Sendable, Hashable, CustomStringConvertible {
    public enum Kind: String, Sendable, Hashable, CaseIterable {
        case invalidStatement = "a line that is not a key, a table header or a comment"
        case missingEquals = "a key with no `=` after it"
        case invalidKey = "a key that starts with a character keys cannot start with"
        case missingValue = "a key with no value after its `=`"
        case bareString = "unquoted text where TOML needs a quoted string"
        case capitalizedBoolean = "a boolean that is not lowercase `true` or `false`"
        case noNull = "a null value, which TOML does not have"
        case leadingZero = "a decimal number with a leading zero"
        case versionNumber = "an unquoted version number with more than one dot"
        case floatDot = "a float without digits on both sides of its dot"
        case dateFormat = "a date or time not written as YYYY-MM-DD or HH:MM:SS"
        case invalidDate = "a date that does not exist"
        case invalidValue = "a value TOML does not have"
        case textAfterValue = "text after a value on the same line"
        case invalidEscape = "an escape TOML's double-quoted strings do not have"
        case controlCharacter = "a control character"
        case unclosedString = "a string that is never closed"
        case unclosedArray = "an array that is never closed"
        case unclosedInlineTable = "an inline table that is never closed"
        case trailingComma = "a trailing comma in an inline table"
        case newlineInInlineTable = "a line break inside an inline table"
        case unclosedHeader = "a table header with no closing bracket"
        case duplicateKey = "a key defined twice"
        case tableRedefined = "a table defined twice"
        case immutable = "a table or array written inline that is extended later"
    }

    public let kind: Kind
    /// What stands there (`\U`, the key, the value's text), when naming it helps.
    public let detail: String?
    /// Counted from 1.
    public let line: Int
    /// Counted from 1, in characters.
    public let column: Int

    public init(kind: Kind, detail: String? = nil, line: Int, column: Int) {
        self.kind = kind
        self.detail = detail
        self.line = line
        self.column = column
    }

    /// The kind and what stands there, without the position.
    public var what: String {
        kind.rawValue + (detail.map { " (\($0))" } ?? "")
    }

    public var description: String {
        "\(what) at line \(line), column \(column)"
    }
}

/// What stops a text from being parsed.
enum Failure: Error, Sendable, Hashable {
    /// The text is not TOML.
    case problem(TOMLProblem)
    /// The text is TOML this checker does not model (an integer beyond 64 bits).
    case unsupported(String)

    /// The line Python's traceback would end with, or the reason for an unsupported text.
    var message: String {
        switch self {
        case let .problem(problem): "tomllib.TOMLDecodeError: \(problem)"
        case let .unsupported(reason): reason
        }
    }
}
