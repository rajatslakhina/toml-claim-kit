import Foundation

/// Reads a Python literal as an answer shows a result: a dict, a list or tuple, a string, a number,
/// `True`/`False`/`None`, `inf`/`nan`, or a `datetime.date`, `datetime.time` or `datetime.datetime` call.
/// Anything else reads as `nil`.
struct PythonLiteral {
    static let words: [String: TOMLValue] = [
        "True": .bool(true), "False": .bool(false), "None": .null, "inf": .float(.infinity), "nan": .float(.nan),
        "float('inf')": .float(.infinity), "float('nan')": .float(.nan), "math.inf": .float(.infinity),
        "math.nan": .float(.nan)
    ]
    static let escapes: [Character: String] = [
        "n": "\n", "t": "\t", "r": "\r", "\\": "\\", "'": "'", "\"": "\"", "0": "\u{00}", "a": "\u{07}",
        "b": "\u{08}", "f": "\u{0C}", "v": "\u{0B}", "\n": ""
    ]

    let characters: [Character]
    var offset = 0

    init(_ text: String) {
        characters = Array(text)
    }

    /// The whole text as one literal; `nil` when it is not one or something follows it.
    static func value(_ text: String) -> TOMLValue? {
        var parser = PythonLiteral(text.trimmed)
        guard let value = parser.value(), parser.atEnd else { return nil }
        return value
    }

    var peek: Character? {
        offset < characters.count ? characters[offset] : nil
    }

    var atEnd: Bool {
        mutating get {
            skipSpace()
            return peek == nil
        }
    }

    mutating func skipSpace() {
        while let character = peek, character.isWhitespace { offset += 1 }
    }

    mutating func value() -> TOMLValue? {
        skipSpace()
        guard let first = peek else { return nil }
        if first == "r" || first == "R", offset + 1 < characters.count, "'\"".contains(characters[offset + 1]) {
            offset += 1
            return string(raw: true)
        }
        switch first {
        case "{": return dict()
        case "[": return items(closing: "]")
        case "(": return items(closing: ")")
        case "\"", "'": return string()
        default: return word()
        }
    }

    mutating func items(closing: Character) -> TOMLValue? {
        offset += 1
        var items: [TOMLValue] = []
        skipSpace()
        while peek != closing {
            guard let item = value(), proceed(closing: closing) else { return nil }
            items.append(item)
            skipSpace()
        }
        offset += 1
        return .array(items)
    }

    /// After an item: steps over a comma, or stops before the closing bracket; `false` for anything else.
    mutating func proceed(closing: Character) -> Bool {
        skipSpace()
        guard peek == "," else { return peek == closing }
        offset += 1
        return true
    }

    mutating func dict() -> TOMLValue? {
        offset += 1
        var pairs: [TOMLPair] = []
        skipSpace()
        while peek != "}" {
            guard case let .string(key)? = value(), colon(), let value = value(), proceed(closing: "}") else {
                return nil
            }
            pairs.append(TOMLPair(key: key, value: value))
            skipSpace()
        }
        offset += 1
        return .table(pairs)
    }

    mutating func colon() -> Bool {
        skipSpace()
        guard peek == ":" else { return false }
        offset += 1
        return true
    }

    /// A quoted string, triple quotes included.
    mutating func string(raw: Bool = false) -> TOMLValue? {
        guard let quote = peek else { return nil }
        let width = repeats(quote, 3) ? 3 : 1
        offset += width
        var out = ""
        while let character = peek {
            if character == quote, repeats(quote, width) {
                offset += width
                return .string(out)
            }
            offset += 1
            guard character == "\\", !raw, let next = peek else {
                out.append(character)
                continue
            }
            offset += 1
            out += escape(next)
        }
        return nil
    }

    func repeats(_ quote: Character, _ count: Int) -> Bool {
        offset + count <= characters.count && characters[offset..<offset + count].allSatisfy { $0 == quote }
    }

    mutating func escape(_ code: Character) -> String {
        if let simple = Self.escapes[code] { return simple }
        let length = ["x": 2, "u": 4, "U": 8][code]
        guard let length, offset + length <= characters.count,
              let number = UInt32(String(characters[offset..<offset + length]), radix: 16),
              let scalar = Unicode.Scalar(number) else { return "\\" + String(code) }
        offset += length
        return String(scalar)
    }

    /// A number or a constant.
    mutating func word() -> TOMLValue? {
        if let call = call() { return call }
        let begin = offset
        while let character = peek, character.isLetter || character.isNumber || "_.+-".contains(character) {
            offset += 1
        }
        let text = String(characters[begin..<offset])
        if let constant = Self.words[text] { return constant }
        let unsigned = Self.words[String(text.dropFirst())]
        if text.hasPrefix("-"), case let .float(number)? = unsigned { return .float(-number) }
        return Self.number(text)
    }

    static let calls = ["datetime.datetime(", "datetime.date(", "datetime.time(", "float("]
    static let units = ["days": 86_400, "hours": 3_600, "minutes": 60, "seconds": 1]

    /// `datetime.date(2024, 1, 2)`, `datetime.time(10, 30)`, `datetime.datetime(…, tzinfo=…)` or `float('inf')`.
    mutating func call() -> TOMLValue? {
        let rest = String(characters[offset...])
        guard let name = Self.calls.first(where: rest.hasPrefix),
              let parts = PythonScanner.closing(rest, open: name.count - 1) else { return nil }
        offset += rest.count - parts.rest.count
        return Self.construct(name, PythonScanner.arguments(parts.inside))
    }

    static func construct(_ name: String, _ arguments: [String]) -> TOMLValue? {
        if name == "float(" { return words["float(\(arguments.joined()))"] }
        let positional = arguments.filter { !$0.contains("=") }
        let numbers = positional.compactMap { Int($0) }
        guard numbers.count == positional.count else { return nil }
        switch (name, numbers.count) {
        case ("datetime.date(", 3):
            return .date(TOMLDate(year: numbers[0], month: numbers[1], day: numbers[2]))
        case ("datetime.time(", 2...4):
            return .time(time(numbers))
        case ("datetime.datetime(", 5...7):
            var minutes: Int?
            if let zone = arguments.first(where: { $0.hasPrefix("tzinfo=") }) {
                guard let parsed = offset(String(zone.dropFirst(7))) else { return nil }
                minutes = parsed
            }
            let date = TOMLDate(year: numbers[0], month: numbers[1], day: numbers[2])
            return .dateTime(TOMLDateTime(date: date, time: time(Array(numbers.dropFirst(3))), offsetMinutes: minutes))
        default:
            return nil
        }
    }

    /// Hour and minute, then a second and a microsecond when they are given.
    static func time(_ numbers: [Int]) -> TOMLTime {
        let padded = numbers + [0, 0]
        return TOMLTime(hour: padded[0], minute: padded[1], second: padded[2], microsecond: padded[3])
    }

    /// `datetime.timezone.utc`, or `datetime.timezone(datetime.timedelta(...))` with keyword arguments,
    /// as minutes east of UTC.
    static func offset(_ text: String) -> Int? {
        if text.hasSuffix("timezone.utc") { return 0 }
        guard let open = text.range(of: "timedelta("), text.hasSuffix("))") else { return nil }
        var seconds = 0
        for argument in PythonScanner.arguments(String(text[open.upperBound...].dropLast(2))) {
            let parts = argument.split(separator: "=").map(\.trimmed)
            guard parts.count == 2, let number = Int(parts[1]), let unit = units[parts[0]] else { return nil }
            seconds += number * unit
        }
        return seconds / 60
    }

    static func number(_ text: String) -> TOMLValue? {
        let cleaned = text.replacingOccurrences(of: "_", with: "")
        if let integer = Int(cleaned) { return .int(integer) }
        guard cleaned.contains(where: { ".eE".contains($0) }), let float = Double(cleaned) else { return nil }
        return .float(float)
    }
}
