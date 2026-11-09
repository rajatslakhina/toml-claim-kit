/// What a claim about TOML turned out to be once it was checked.
public struct TOMLFinding: Sendable, Hashable {
    public enum Outcome: Sendable, Hashable {
        case exact
        /// The same value shown another way: other spacing, key order or quotes.
        case equivalent
        /// Holds, with something a reader should know.
        case caveat(Caveat)
        case wrong(Slip?)
        /// Could not be checked, and why.
        case unchecked(String)
    }

    /// TOML that parses but that a reader should look at again.
    public enum Caveat: Sendable, Hashable {
        /// Unquoted floats written with a trailing zero (`python_version = 3.10`): they load as 3.1.
        case versionLikeFloats([String])
        /// Dotted keys made of digits (`3.10 = "x"`): they make nested tables `{"3": {"10": ...}}`.
        case numericDottedKeys([String])
    }

    /// A recognizable mistake behind a wrong claim.
    public enum Slip: String, Sendable, Hashable, CaseIterable {
        /// Said to be TOML (or shown as TOML) and it does not parse.
        case notTOML
        /// Said not to be TOML and it parses.
        case parses
        /// Text left unquoted, where TOML needs a quoted string.
        case bareString
        /// `True` or `TRUE`, where TOML's booleans are lowercase.
        case capitalizedBoolean
        /// `null`, `None` or `~`, which TOML does not have.
        case noNull
        /// `0755`, where TOML refuses a leading zero.
        case leadingZero
        /// `1.2.3` unquoted.
        case unquotedVersion
        /// `.5` or `5.`, where TOML needs digits on both sides of the dot.
        case floatDot
        /// A date without its zeros or a time without its seconds.
        case dateFormat
        /// A backslash in a double-quoted string that is not an escape (`"C:\Users"`).
        case backslash
        /// A key defined twice, which TOML refuses.
        case duplicateKey
        /// A table declared twice, which TOML refuses.
        case duplicateTable
        /// An inline table or array added to later.
        case inlineTableExtended
        /// An inline table across lines or with a trailing comma.
        case inlineTableSyntax
        /// `3.10` taken for the text "3.10" where TOML reads the float 3.1.
        case trailingZeroDropped
        /// An unquoted number taken for text.
        case unquotedNumber
        /// An unquoted date or time taken for text where `tomllib` gives a `datetime` object.
        case dateParsed
        /// An int shown for a float, or a float for an int.
        case numberType
        /// A quoted value taken for a number, boolean or date.
        case staysString
        /// `data["tool.poetry"]`, where the dotted key made nested tables.
        case dottedKeyLookup
        /// `tomllib.load` on a file opened in text mode.
        case textMode
        /// `tomllib.load` given a path instead of a file.
        case pathArgument
        /// `tomllib.dumps`, which does not exist.
        case noDumper
        /// A value shown where the code raises.
        case raises
        /// An error shown where the code returns.
        case doesNotRaise
    }

    public enum Severity: Int, Sendable, Hashable, Comparable {
        case holds
        case unchecked
        case caution
        case wrong

        public static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public let claim: TOMLClaim
    public let outcome: Outcome
    /// What checking it gives, as the explanation writes it; `nil` when there is nothing to show.
    public let actual: String?
    /// Why the text is not TOML, when that is what the claim is about.
    public let problem: TOMLProblem?
    /// Whether running the code raises (`actual` is then the error line).
    public let raises: Bool
    /// Flagged in an earlier review of the same conversation (set by `TOMLLedger`).
    public internal(set) var isRepeated = false

    init(claim: TOMLClaim, outcome: Outcome, actual: String? = nil, problem: TOMLProblem? = nil, raises: Bool = false) {
        self.claim = claim
        self.outcome = outcome
        self.actual = actual
        self.problem = problem
        self.raises = raises
    }

    public var severity: Severity {
        switch outcome {
        case .exact, .equivalent: .holds
        case .unchecked: .unchecked
        case .caveat: .caution
        case .wrong: .wrong
        }
    }

    /// Identifies the same claim across rewrites.
    var key: String {
        "\(claim.kind)|\(claim.subject)|\(claim.claimed)".lowercased()
    }
}
