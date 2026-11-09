import Foundation

extension TOMLParser {
    static let escapes: [Character: String] = [
        "b": "\u{08}", "t": "\t", "n": "\n", "f": "\u{0C}", "r": "\r", "\"": "\"", "\\": "\\"
    ]
    static let nulls: Set<String> = ["null", "none", "nil", "~", "undefined"]

    /// A basic string's text after its opening quote (after `"""` for a multi-line one), up to its close.
    mutating func basicString(multiline: Bool) throws(Failure) -> String {
        var result = ""
        while let char = peek {
            if char == "\"", !multiline || at("\"\"\"") {
                pos += multiline ? 3 : 1
                return result
            }
            if char == "\\" {
                result += try escape(multiline: multiline)
                continue
            }
            if char == "\n", !multiline { throw problem(.unclosedString, detail: "a line break in a one-line string") }
            if char != "\t", char != "\n", Self.isControl(char) { throw problem(.controlCharacter) }
            result.append(char)
            pos += 1
        }
        throw problem(.unclosedString)
    }

    /// The text a backslash stands for; in a multi-line string, a backslash ending a line joins the next.
    mutating func escape(multiline: Bool) throws(Failure) -> String {
        let start = pos
        pos += 1
        let code = peek
        pos += 1
        if multiline, let code, code == " " || code == "\t" || code == "\n" {
            if code != "\n" {
                skipSpace()
                guard peek == "\n" || peek == nil else {
                    throw problem(.invalidEscape, at: start, detail: "\\ followed by a space")
                }
            }
            while let next = peek, next == "\n" || Self.whitespace.contains(next) { pos += 1 }
            return ""
        }
        if code == "u" || code == "U" { return try hex(code == "u" ? 4 : 8, start: start) }
        guard let code, let simple = Self.escapes[code] else {
            throw problem(.invalidEscape, at: start, detail: "\\" + (code.map(String.init) ?? ""))
        }
        return simple
    }

    /// `\uXXXX` or `\UXXXXXXXX`: the hex digits after `pos`, as one Unicode scalar.
    mutating func hex(_ length: Int, start: Int) throws(Failure) -> String {
        let end = min(pos + length, chars.count)
        let text = String(chars[pos..<end])
        let detail = "\\" + String(chars[start + 1]) + text.prefix { $0.isASCII && $0.isHexDigit }
        guard text.count == length, text.allSatisfy({ $0.isASCII && $0.isHexDigit }),
              let number = UInt32(text, radix: 16), let scalar = Unicode.Scalar(number) else {
            throw problem(.invalidEscape, at: start, detail: detail)
        }
        pos = end
        return String(scalar)
    }

    /// `'text'`: no escapes, closed on its line.
    mutating func literalString() throws(Failure) -> String {
        pos += 1
        let start = pos
        while let char = peek, char != "'" {
            if char == "\n" { throw problem(.unclosedString, detail: "a line break in a one-line string") }
            if char != "\t", Self.isControl(char) { throw problem(.controlCharacter) }
            pos += 1
        }
        guard peek == "'" else { throw problem(.unclosedString) }
        pos += 1
        return String(chars[start..<(pos - 1)])
    }

    /// `"""text"""` or `'''text'''`: a line break right after the opening is dropped, and up to two quotes
    /// before the closing three belong to the text.
    mutating func multilineString(literal: Bool) throws(Failure) -> String {
        pos += 3
        if peek == "\n" { pos += 1 }
        var result: String
        if literal {
            let start = pos
            while !at("'''") {
                guard let char = peek else { throw problem(.unclosedString) }
                if char != "\t", char != "\n", Self.isControl(char) { throw problem(.controlCharacter) }
                pos += 1
            }
            result = String(chars[start..<pos])
            pos += 3
        } else {
            result = try basicString(multiline: true)
        }
        let quote: Character = literal ? "'" : "\""
        for _ in 0..<2 where peek == quote {
            result.append(quote)
            pos += 1
        }
        return result
    }

    func token(from start: Int) -> String {
        String(chars[start...].prefix { !" \t\n,]}#".contains($0) })
    }

    /// Names what stands where a value should start and none does.
    func invalidValue() -> (TOMLProblem.Kind, String?) {
        let token = token(from: pos)
        guard !token.isEmpty else {
            if chars[..<pos].last(where: { !Self.whitespace.contains($0) }) == "=" { return (.missingValue, nil) }
            return (peek == nil ? .unclosedArray : .invalidValue, nil)
        }
        let lower = token.lowercased()
        if lower == "true" || lower == "false" { return (.capitalizedBoolean, token) }
        if Self.nulls.contains(lower) { return (.noNull, token) }
        if token.wholeMatch(of: #/\.[0-9]+/#) != nil { return (.floatDot, token) }
        if let first = token.first, "+-0123456789".contains(first) { return (.invalidValue, token) }
        return (.bareString, token)
    }

    /// The mistake found right after a value: named from the value's text when parsing stopped inside it
    /// (`0755`, `1.2.3`, `5.`, `10:30`, `hello`), `fallback` otherwise.
    func afterValue(_ fallback: TOMLProblem.Kind) -> Failure {
        guard let start = valueStart else { return problem(fallback) }
        let token = token(from: start)
        guard pos < start + token.count, let kind = Self.trailingKind(token) else { return problem(fallback) }
        return problem(kind, at: start, detail: token)
    }

    static func trailingKind(_ token: String) -> TOMLProblem.Kind? {
        if token.first?.isLetter == true { return .bareString }
        if token.wholeMatch(of: #/[+-]?0[0-9_]+([.eE].*)?/#) != nil { return .leadingZero }
        if token.wholeMatch(of: #/[0-9]+(\.[0-9]+){2,}/#) != nil { return .versionNumber }
        if token.wholeMatch(of: #/[+-]?[0-9_]+\.([eE][+-]?[0-9_]*)?/#) != nil { return .floatDot }
        if token.contains(":") || token.wholeMatch(of: #/[0-9]{4}-.*/#) != nil { return .dateFormat }
        return nil
    }
}

extension StringProtocol {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
