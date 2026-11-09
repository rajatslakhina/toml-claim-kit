extension TOMLFinding {
    static let hints: [Slip: String] = [
        .bareString: "TOML strings need quotes: \"...\" or '...'",
        .capitalizedBoolean: "TOML booleans are lowercase true and false",
        .noNull: "TOML has no null; leave the key out instead",
        .leadingZero: "TOML refuses a decimal number with a leading zero; write 0o755 for octal, or quote it",
        .unquotedVersion: "a version with two dots is not a number; quote it",
        .floatDot: "TOML floats need digits on both sides of the dot, as in 0.5 and 5.0",
        .dateFormat: "TOML dates are YYYY-MM-DD and times HH:MM:SS, seconds included",
        .backslash: "a double-quoted string reads a backslash as an escape; use a single-quoted string or double it",
        .duplicateKey: "tomllib raises on a key defined twice rather than keeping either value",
        .duplicateTable: "TOML refuses a table declared twice; keep its keys under one header",
        .inlineTableExtended: "an inline table or array is complete as written; nothing can be added to it later",
        .inlineTableSyntax: "in TOML 1.0 an inline table stays on one line, with no trailing comma",
        .trailingZeroDropped: "an unquoted 3.10 is the float 3.1; quote it to keep the text",
        .unquotedNumber: "an unquoted number is a number; quote it to keep the text",
        .dateParsed: "tomllib turns an unquoted date or time into a datetime object",
        .numberType: "a dot or an exponent makes a float, and digits alone an int",
        .staysString: "a quoted value stays a string",
        .dottedKeyLookup: "a dotted key makes nested tables, so index one level at a time: data[\"tool\"][\"poetry\"]",
        .textMode: "tomllib.load needs a file opened in binary mode: open(path, \"rb\")",
        .pathArgument: "tomllib.load takes a file opened with open(path, \"rb\"), not a path",
        .noDumper: "tomllib only reads TOML; write it with the tomli-w package (tomli_w.dumps)"
    ]

    /// One sentence saying what is wrong or what to look at; a holding claim gets a short confirmation.
    public var explanation: String {
        switch outcome {
        case .exact, .equivalent: return "\(Self.quoted(claim.subject)) holds."
        case let .unchecked(reason): return "\(Self.quoted(claim.subject)) was not checked: \(reason)."
        case let .caveat(caveat): return Self.caveatSentence(caveat)
        case let .wrong(slip): return wrongSentence(slip)
        }
    }

    static func quoted(_ text: String) -> String {
        let short = TOMLClaim.shortened(text)
        return short.contains("`") ? short : "`\(short)`"
    }

    static func caveatSentence(_ caveat: Caveat) -> String {
        switch caveat {
        case let .versionLikeFloats(values):
            return "The TOML has unquoted numbers written with a trailing zero, which load without it: "
                + values.joined(separator: ", ") + "; quote any that must stay text, such as a version."
        case let .numericDottedKeys(keys):
            return "The TOML has keys made of digits and dots, which become nested tables rather than one key: "
                + keys.joined(separator: ", ") + "; quote the key to keep it whole."
        }
    }

    func wrongSentence(_ slip: Slip?) -> String {
        let hint = slip.flatMap { Self.hints[$0] }.map { " (\($0))" } ?? ""
        switch claim.kind {
        case .validity:
            guard let problem else { return "The text said not to be TOML parses." }
            let what = claim.isExplicit ? "The text said to be valid TOML" : "The block shown as TOML"
            return "\(what) does not parse: \(problem)\(hint)."
        case .reading:
            return "\(Self.quoted(claim.subject)) is not \(claim.claimed): \(actual ?? "")\(hint)."
        case .loading:
            return loadingSentence(slip, hint)
        }
    }

    func loadingSentence(_ slip: Slip?, _ hint: String) -> String {
        let subject = Self.quoted(claim.subject)
        let shown = actual ?? ""
        if raises {
            let shows = claim.isExplicit ? "the answer shows \(claim.claimed)" : "the answer uses it as if it runs"
            return "\(subject) raises \(shown); \(shows)\(hint)."
        }
        if slip == .doesNotRaise { return "\(subject) does not raise: it gives \(shown)." }
        return "\(subject) gives \(shown), not \(claim.claimed)\(hint)."
    }
}
