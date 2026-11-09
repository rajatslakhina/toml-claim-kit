/// Finds sentences that say what a value reads as: "`python_version = 3.10` is read as the string "3.10"",
/// "tomllib loads `2024-01-02` as a date", "`1e3` is not an integer".
enum ReadingReader {
    struct Phrase: Sendable {
        let text: String
        let negated: Bool
        /// "is a" / "is an": only a type may follow.
        let typeOnly: Bool
    }

    static let passive = ["read as", "parsed as", "loaded as", "interpreted as", "treated as", "resolved as",
                          "resolved to", "converted to", "kept as", "seen as", "deserialized as"]
    static let active = [("becomes", "become"), ("turns into", "turn into"), ("stays", "stay"), ("remains", "remain"),
                         ("resolves to", "resolve to"), ("loads as", "load as"), ("parses as", "parse as"),
                         ("comes back as", "come back as"), ("evaluates to", "evaluate to")]
    static let transitive: Set<String> = ["reads", "parses", "loads", "interprets", "treats", "resolves", "sees",
                                          "turns", "converts", "keeps", "read", "parse", "load", "interpret",
                                          "treat", "resolve", "see", "turn", "convert", "keep"]
    static let links = [" as ", " into ", " to "]
    /// Words another format reads as more than text, worth a claim even though TOML refuses them unquoted.
    static let valueWords: Set<String> = ["True", "False", "TRUE", "FALSE", "null", "None", "nil", "~", "yes", "no",
                                          "on", "off", "Yes", "No"]

    /// Every verb phrase that can follow the value, longest first.
    static let phrases: [Phrase] = {
        var phrases: [Phrase] = []
        for verb in passive {
            phrases += ["is", "gets", "will be", "would be"].map {
                Phrase(text: "\($0) \(verb)", negated: false, typeOnly: false)
            }
            phrases += ["is not", "isn't", "won't be", "will not be", "is never"].map {
                Phrase(text: "\($0) \(verb)", negated: true, typeOnly: false)
            }
        }
        for (third, base) in active {
            phrases += [third, "will \(base)"].map { Phrase(text: $0, negated: false, typeOnly: false) }
            let negations = ["does not \(base)", "doesn't \(base)", "won't \(base)", "will not \(base)",
                             "never \(third)"]
            phrases += negations.map {
                Phrase(text: $0, negated: true, typeOnly: false)
            }
        }
        phrases += ["is a", "is an"].map { Phrase(text: $0, negated: false, typeOnly: true) }
        // "is the integer 493", "is 493": the object must be a typed value, never plain text.
        phrases += [Phrase(text: "is", negated: false, typeOnly: false)]
        phrases += ["is not", "isn't"].map { Phrase(text: $0, negated: true, typeOnly: false) }
        phrases += ["is not a", "is not an", "isn't a", "isn't an"].map {
            Phrase(text: $0, negated: true, typeOnly: true)
        }
        return phrases.sorted { $0.text.count > $1.text.count }
    }()

    static func claims(in lines: [String]) -> [TOMLClaim] {
        ProseReader.sentences(lines).compactMap(claim)
    }

    static func claim(_ sentence: String) -> TOMLClaim? {
        let parts = sentence.components(separatedBy: "`")
        guard parts.count >= 3, let value = subject(parts[1]) else { return nil }
        let after = parts.dropFirst(2).joined(separator: "`")
        guard let (expectation, object) = expectation(before: parts[0].lowercased(), after: after) else { return nil }
        return TOMLClaim(kind: .reading, subject: parts[1], claimed: clause(object), task: .read(value, expectation))
    }

    /// The value a sentence is about: what follows `=` in `key = value`, or a value alone. Without a key it
    /// must be something a parser could read as more than text, or be quoted.
    static func subject(_ span: String) -> String? {
        var text = span.trimmed
        let assigned = text.contains("=")
        if let equals = text.firstIndex(of: "=") { text = String(text[text.index(after: equals)...]).trimmed }
        guard let first = text.first, text.count <= 40, first != "[", first != "{" else { return nil }
        if assigned || first == "\"" || first == "'" || valueWords.contains(text) || "+-.0123456789".contains(first) {
            return text
        }
        guard case let .value(value) = TOMLValidator.value(text), !value.isString else { return nil }
        return text
    }

    /// What the words after the value (or around it, for "tomllib reads `x` as …") say it reads as.
    static func expectation(before: String, after: String) -> (Expectation, String)? {
        let lead = after.prefix { $0 == " " }.count
        let rest = after.dropFirst(lead)
        let lower = rest.lowercased()
        if let phrase = phrases.first(where: { lower.hasPrefix($0.text + " ") }) {
            let object = String(rest.dropFirst(phrase.text.count + 1))
            guard let target = ObjectReader.target(object), !phrase.typeOnly || target.isType else { return nil }
            return (Expectation(target: target, negated: phrase.negated), object)
        }
        let words = before.split(separator: " ")
        guard let verb = words.last.map(String.init), transitive.contains(verb),
              let link = links.first(where: { after.lowercased().hasPrefix($0) }) else { return nil }
        let object = String(after.dropFirst(link.count))
        guard let target = ObjectReader.target(object) else { return nil }
        let negated = words.dropLast().last.map { ["not", "doesn't", "won't", "never"].contains(String($0)) } == true
        return (Expectation(target: target, negated: negated), object)
    }

    /// The object without what follows it in the sentence: a clause, a parenthesis, the final stop.
    static func clause(_ object: String) -> String {
        var text = object.trimmed
        for stop in [", ", "; ", " (", " because ", " so ", " which ", " when ", " unless ", " in ", " under "] {
            if let range = text.range(of: stop) { text = String(text[..<range.lowerBound]) }
        }
        while let last = text.last, ".!:".contains(last) { text.removeLast() }
        return text
    }
}

extension Expectation.Target {
    var isType: Bool {
        if case .type = self { return true }
        return false
    }
}

/// Reads what a sentence says a value becomes: `` `3.1` ``, "the string "3.10"", "a boolean", "false".
enum ObjectReader {
    /// Longest first, so "datetime" is found before "date" and "integer" before "int".
    static let typeWords: [(String, TypeClass)] = [
        ("floating-point number", .float), ("floating point number", .float), ("offset date-time", .datetime),
        ("local date-time", .datetime), ("date-time", .datetime), ("datetime", .datetime), ("timestamp", .datetime),
        ("local date", .date), ("local time", .time), ("inline table", .table), ("dictionary", .table),
        ("string", .string), ("str", .string), ("text", .string), ("boolean", .boolean), ("bool", .boolean),
        ("integer", .integer), ("int", .integer), ("float", .float), ("number", .number), ("date", .date),
        ("time", .time), ("array", .array), ("list", .array), ("table", .table), ("dict", .table)
    ].sorted { $0.0.count > $1.0.count }
    static let pythonTypes: [String: TypeClass] = [
        "str": .string, "bool": .boolean, "int": .integer, "float": .float, "datetime.date": .date,
        "datetime.time": .time, "datetime.datetime": .datetime, "list": .array, "dict": .table
    ]
    static let quotes: [Character: Character] = ["\"": "\"", "'": "'", "\u{201C}": "\u{201D}", "\u{2018}": "\u{2019}"]

    static func target(_ object: String) -> Expectation.Target? {
        var text = Substring(object.trimmed)
        for article in ["the ", "an ", "a "] where text.lowercased().hasPrefix(article) {
            text = text.dropFirst(article.count)
        }
        if let (token, isCode) = token(text) { return isCode ? code(token) : .value(.string(token)) }
        let lower = text.lowercased()
        guard let (word, type) = typeWords.first(where: { lower.hasPrefix($0.0) }) else {
            guard let (word, _) = bare(text), case let .value(value) = literal(word), !value.isString else {
                return nil
            }
            return .value(value)
        }
        let rest = text.dropFirst(word.count).drop { $0 == " " }
        guard let (value, _) = token(rest) ?? bare(rest) else { return .type(type) }
        return typed(value, type)
    }

    /// A code span or a quoted text at the start, and whether it was code.
    static func token(_ text: Substring) -> (String, Bool)? {
        guard let first = text.first else { return nil }
        let close: Character? = first == "`" ? "`" : quotes[first]
        guard let close, let end = text.dropFirst().firstIndex(of: close) else { return nil }
        return (String(text[text.index(after: text.startIndex)..<end]), first == "`")
    }

    /// A bare word or number at the start: `false`, `493`.
    static func bare(_ text: Substring) -> (String, Bool)? {
        var token = String(text.prefix { !" ,;)".contains($0) })
        while token.last == "." || token.last == ":" { token.removeLast() }
        return token.isEmpty ? nil : (token, false)
    }

    static func code(_ text: String) -> Expectation.Target {
        if let type = pythonTypes[text] { return .type(type) }
        return PythonLiteral.value(text).map { .value($0) } ?? literal(text)
    }

    static func typed(_ value: String, _ type: TypeClass) -> Expectation.Target? {
        switch (type, literal(value)) {
        case (.string, _): .value(.string(value))
        case (.date, _), (.time, _), (.datetime, _): .type(type)
        case let (.number, .value(.int(number))): .number(Double(number))
        case let (.number, .value(.float(number))): .number(number)
        case let (.float, .value(.int(number))): .value(.float(Double(number)))
        case let (_, target): type.contains(target.value) ? target : nil
        }
    }

    /// A value as an answer writes it, in Python or TOML spelling.
    static func literal(_ text: String) -> Expectation.Target {
        switch text {
        case "True", "true": return .value(.bool(true))
        case "False", "false": return .value(.bool(false))
        case "None", "null", "nil": return .value(.null)
        default: break
        }
        if let first = text.first, text.count >= 2, first == text.last, first == "\"" || first == "'" {
            return .value(.string(String(text.dropFirst().dropLast())))
        }
        if let number = Int(text) { return .value(.int(number)) }
        if text.contains(where: { ".eE".contains($0) }), let number = Double(text) { return .value(.float(number)) }
        return .value(.string(text))
    }
}

extension Expectation.Target {
    /// The value a literal target holds; a type or number target holds none.
    var value: TOMLValue {
        switch self {
        case let .value(value): value
        case let .number(number): .float(number)
        case let .type(type): type.representative
        }
    }
}
