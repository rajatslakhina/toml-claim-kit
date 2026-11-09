extension TOMLParser {
    static let radixes: [Character: Int] = ["x": 16, "o": 8, "b": 2]
    static let specials: [(String, Double)] = [
        ("inf", .infinity), ("nan", .nan), ("+inf", .infinity), ("-inf", -.infinity), ("+nan", .nan), ("-nan", .nan)
    ]

    static func isBare(_ char: Character) -> Bool {
        char.isASCII && (char.isLetter || char.isNumber || char == "_" || char == "-")
    }

    static func startsKey(_ char: Character) -> Bool {
        isBare(char) || char == "\"" || char == "'"
    }

    static func isDigit(_ char: Character) -> Bool {
        char.isASCII && char.isNumber
    }

    func char(_ index: Int) -> Character? {
        index < chars.count ? chars[index] : nil
    }

    /// A dotted key: bare or quoted parts, with spaces allowed around the dots.
    mutating func parseKey() throws(Failure) -> [String] {
        let start = pos
        var parts: [String] = []
        var digitsOnly = true
        while true {
            let (part, bare) = try keyPart()
            parts.append(part)
            digitsOnly = digitsOnly && bare && part.allSatisfy(Self.isDigit)
            skipSpace()
            guard peek == "." else { break }
            pos += 1
            skipSpace()
        }
        if parts.count > 1, digitsOnly { numericKeys.append(String(chars[start..<pos]).trimmed) }
        return parts
    }

    /// One part of a key, and whether it was bare.
    mutating func keyPart() throws(Failure) -> (String, Bool) {
        guard let char = peek else { throw problem(.invalidKey) }
        if Self.isBare(char) {
            let start = pos
            while let next = peek, Self.isBare(next) { pos += 1 }
            return (String(chars[start..<pos]), true)
        }
        if char == "\"" {
            pos += 1
            return (try basicString(multiline: false), false)
        }
        if char == "'" { return (try literalString(), false) }
        throw problem(.invalidKey, detail: Self.isControl(char) ? nil : String(char))
    }

    /// A `key = value` line: the dotted key, the value, and the value's text as written.
    struct Pair {
        let key: [String]
        let value: TOMLValue
        let raw: String

        var parts: ([String], TOMLValue) {
            (key, value)
        }
    }

    mutating func keyValuePair() throws(Failure) -> Pair {
        let key = try parseKey()
        guard peek == "=" else { throw problem(.missingEquals, detail: Self.dotted(key)) }
        pos += 1
        skipSpace()
        let start = pos
        let value = try parseValue()
        valueStart = start
        return Pair(key: key, value: value, raw: String(chars[start..<pos]))
    }

    /// A string of any of TOML's four kinds; `nil` when no quote starts here.
    mutating func stringValue() throws(Failure) -> TOMLValue? {
        if at("\"\"\"") { return .string(try multilineString(literal: false)) }
        if at("'''") { return .string(try multilineString(literal: true)) }
        if peek == "\"" {
            pos += 1
            return .string(try basicString(multiline: false))
        }
        return peek == "'" ? .string(try literalString()) : nil
    }

    mutating func parseValue() throws(Failure) -> TOMLValue {
        let start = pos
        if let text = try stringValue() { return text }
        for (word, flag) in [("true", true), ("false", false)] where at(word) {
            pos += word.count
            return .bool(flag)
        }
        if peek == "[" { return try array() }
        if peek == "{" { return try inlineTable() }
        if let value = try dateTime() { return value }
        if let (time, end) = timeMatch(at: pos) {
            pos = end
            return .time(time)
        }
        if let value = try number() { return value }
        for (word, number) in Self.specials where at(word) {
            pos += word.count
            return .float(number)
        }
        let (kind, token) = invalidValue()
        throw problem(kind, at: start, detail: token)
    }

    mutating func array() throws(Failure) -> TOMLValue {
        pos += 1
        var items: [TOMLValue] = []
        try skipArraySpace()
        while peek != "]" {
            let start = pos
            items.append(try parseValue())
            valueStart = start
            try skipArraySpace()
            if peek == "]" { break }
            guard peek == "," else { throw afterValue(.unclosedArray) }
            pos += 1
            try skipArraySpace()
        }
        pos += 1
        return .array(items)
    }

    /// Spaces, line breaks and comments between an array's items.
    mutating func skipArraySpace() throws(Failure) {
        while let char = peek, char == "\n" || char == "#" || Self.whitespace.contains(char) {
            if char == "#" {
                try skipComment()
            } else {
                pos += 1
            }
        }
    }

    /// `{ key = value, ... }` on one line, with no trailing comma; it cannot be extended later.
    mutating func inlineTable() throws(Failure) -> TOMLValue {
        pos += 1
        let table = TableBox()
        let local = Flags()
        skipSpace()
        while peek != "}" {
            if peek == nil { throw problem(.unclosedInlineTable) }
            if peek == "\n" { throw problem(.newlineInInlineTable) }
            let (key, value) = try keyValuePair().parts
            let stem = key[key.count - 1]
            if local.isSet(key, .frozen) { throw problem(.immutable, detail: Self.dotted(key)) }
            let (nest, _) = try nest(Array(key.dropLast()), in: table)
            if nest.entries[stem] != nil { throw problem(.duplicateKey, detail: Self.dotted(key)) }
            nest.set(stem, .value(value))
            skipSpace()
            if peek == "}" { break }
            guard peek == "," else { throw afterValue(peek == "\n" ? .newlineInInlineTable : .unclosedInlineTable) }
            if value.isContainer { local.set(key, .frozen, recursive: true) }
            pos += 1
            skipSpace()
            if peek == "}" { throw problem(.trailingComma) }
        }
        pos += 1
        return table.value
    }
}
