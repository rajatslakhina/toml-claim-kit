import Foundation

extension TOMLValue {
    /// What Python's `repr` shows: what the REPL echoes, and how items look inside a printed list or dict.
    public var pythonRepr: String {
        switch self {
        case .null: "None"
        case let .bool(flag): flag ? "True" : "False"
        case let .int(number): String(number)
        case let .float(number): Self.pythonFloat(number)
        case let .string(text): Self.pythonQuoted(text)
        case let .date(date): "datetime.date(\(date.year), \(date.month), \(date.day))"
        case let .time(time): "datetime.time(" + Self.clock(time).map(String.init).joined(separator: ", ") + ")"
        case let .dateTime(stamp): Self.dateTimeRepr(stamp)
        case let .array(items): "[" + items.map(\.pythonRepr).joined(separator: ", ") + "]"
        case let .table(pairs): "{" + pairs.map(Self.member).joined(separator: ", ") + "}"
        }
    }

    static func member(_ pair: TOMLPair) -> String {
        "\(pythonQuoted(pair.key)): \(pair.value.pythonRepr)"
    }

    /// The hour and minute, then the second and microsecond only as far as one of them is not zero.
    static func clock(_ time: TOMLTime) -> [Int] {
        if time.microsecond != 0 { return [time.hour, time.minute, time.second, time.microsecond] }
        return time.second != 0 ? [time.hour, time.minute, time.second] : [time.hour, time.minute]
    }

    static func dateTimeRepr(_ stamp: TOMLDateTime) -> String {
        let date = stamp.date
        var fields = [date.year, date.month, date.day].map(String.init) + clock(stamp.time).map(String.init)
        if let offset = stamp.offsetMinutes { fields.append("tzinfo=" + zone(offset)) }
        return "datetime.datetime(" + fields.joined(separator: ", ") + ")"
    }

    /// `datetime.timezone.utc`, or a timezone whose timedelta Python normalizes to days and seconds.
    static func zone(_ minutes: Int) -> String {
        guard minutes != 0 else { return "datetime.timezone.utc" }
        let seconds = minutes * 60
        let days = seconds < 0 ? -1 : 0
        let rest = seconds - days * 86_400
        let delta = days == 0 ? "seconds=\(rest)" : "days=-1, seconds=\(rest)"
        return "datetime.timezone(datetime.timedelta(\(delta)))"
    }

    /// What `print` shows for the value on its own: a string without quotes, a date as `2024-01-02`.
    public var pythonStr: String {
        switch self {
        case let .string(text): text
        case let .date(date): Self.isoDate(date)
        case let .time(time): Self.isoTime(time)
        case let .dateTime(stamp):
            Self.isoDate(stamp.date) + " " + Self.isoTime(stamp.time) + (stamp.offsetMinutes.map(Self.isoOffset) ?? "")
        default: pythonRepr
        }
    }

    static func isoDate(_ date: TOMLDate) -> String {
        String(format: "%04d-%02d-%02d", date.year, date.month, date.day)
    }

    static func isoTime(_ time: TOMLTime) -> String {
        let clock = String(format: "%02d:%02d:%02d", time.hour, time.minute, time.second)
        return time.microsecond == 0 ? clock : clock + String(format: ".%06d", time.microsecond)
    }

    static func isoOffset(_ minutes: Int) -> String {
        String(format: "%@%02d:%02d", minutes < 0 ? "-" : "+", abs(minutes) / 60, abs(minutes) % 60)
    }

    /// Python's name for the value's type, as `type()` shows it inside `<class '…'>`.
    public var pythonType: String {
        switch self {
        case .null: "NoneType"
        case .bool: "bool"
        case .int: "int"
        case .float: "float"
        case .string: "str"
        case .date: "datetime.date"
        case .time: "datetime.time"
        case .dateTime: "datetime.datetime"
        case .array: "list"
        case .table: "dict"
        }
    }

    /// Python's `repr` of a float: the shortest digits that round-trip, written out in full for decimal
    /// exponents from -4 to 15 and in exponent form (`1e+16`, `1e-05`) outside them.
    static func pythonFloat(_ number: Double) -> String {
        if number.isNaN { return "nan" }
        if number.isInfinite { return number < 0 ? "-inf" : "inf" }
        let sign = number.sign == .minus ? "-" : ""
        guard number != 0 else { return sign + "0.0" }
        let parts = "\(abs(number))".split(separator: "e")
        let exponent = parts.dropFirst().compactMap { Int($0) }.reduce(0, +)
        let pieces = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        var digits = pieces.joined()
        var point = pieces[0].count + exponent
        while digits.hasPrefix("0") {
            digits.removeFirst()
            point -= 1
        }
        while digits.hasSuffix("0") { digits.removeLast() }
        return sign + layout(digits, point: point)
    }

    /// Digits with the decimal point `point` places after the first one's position.
    static func layout(_ digits: String, point: Int) -> String {
        let power = point - 1
        if power < -4 || power >= 16 {
            let tail = digits.dropFirst()
            let mantissa = tail.isEmpty ? String(digits.prefix(1)) : "\(digits.prefix(1)).\(tail)"
            let magnitude = abs(power) < 10 ? "0\(abs(power))" : "\(abs(power))"
            return "\(mantissa)e\(power < 0 ? "-" : "+")\(magnitude)"
        }
        if point <= 0 { return "0." + String(repeating: "0", count: -point) + digits }
        if point >= digits.count { return digits + String(repeating: "0", count: point - digits.count) + ".0" }
        return digits.prefix(point) + "." + digits.dropFirst(point)
    }

    /// Python's `repr` of a string: single quotes unless the text has one and no double quote.
    static func pythonQuoted(_ text: String) -> String {
        let quote: Character = text.contains("'") && !text.contains("\"") ? "\"" : "'"
        var out = String(quote)
        for scalar in text.unicodeScalars {
            out += escaped(scalar, quote: quote)
        }
        return out + String(quote)
    }

    static func escaped(_ scalar: Unicode.Scalar, quote: Character) -> String {
        switch scalar {
        case "\\": return "\\\\"
        case "\n": return "\\n"
        case "\r": return "\\r"
        case "\t": return "\\t"
        default:
            if Character(scalar) == quote { return "\\" + String(quote) }
            if scalar.value < 0x20 || scalar.value == 0x7F { return String(format: "\\x%02x", scalar.value) }
            return String(scalar)
        }
    }
}
