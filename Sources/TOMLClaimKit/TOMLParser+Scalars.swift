extension TOMLParser {
    /// `count` ASCII digits at `start` as a number.
    func digits(_ start: Int, _ count: Int) -> Int? {
        guard start + count <= chars.count else { return nil }
        let slice = chars[start..<(start + count)]
        guard slice.allSatisfy(Self.isDigit) else { return nil }
        return slice.compactMap(\.wholeNumberValue).reduce(0) { $0 * 10 + $1 }
    }

    /// Where a run of digits with single underscores between them ends; `start` when none begins there.
    func run(_ start: Int, _ accepts: (Character) -> Bool) -> Int {
        guard let first = char(start), accepts(first) else { return start }
        var end = start + 1
        while let next = char(end), accepts(next) || (next == "_" && char(end + 1).map(accepts) == true) {
            end += next == "_" ? 2 : 1
        }
        return end
    }

    /// An integer or a float as `tomllib`'s number pattern reads it; `nil` when none starts here.
    mutating func number() throws(Failure) -> TOMLValue? {
        if let value = try radixNumber() { return value }
        var end = pos
        if let sign = char(end), sign == "+" || sign == "-" { end += 1 }
        guard let first = char(end), Self.isDigit(first) else { return nil }
        end = first == "0" ? end + 1 : run(end, Self.isDigit)
        var isFloat = false
        if char(end) == ".", run(end + 1, Self.isDigit) > end + 1 {
            end = run(end + 1, Self.isDigit)
            isFloat = true
        }
        if let mark = char(end), mark == "e" || mark == "E" {
            var start = end + 1
            if let sign = char(start), sign == "+" || sign == "-" { start += 1 }
            if run(start, Self.isDigit) > start {
                end = run(start, Self.isDigit)
                isFloat = true
            }
        }
        let text = String(chars[pos..<end]).replacingOccurrences(of: "_", with: "")
        pos = end
        if isFloat, let value = Double(text) { return .float(value) }
        guard let value = Int(text) else { throw .unsupported("an integer beyond 64 bits") }
        return .int(value)
    }

    /// `0x1F`, `0o755` or `0b101`; `nil` when no digit follows the prefix.
    mutating func radixNumber() throws(Failure) -> TOMLValue? {
        guard char(pos) == "0", let radix = char(pos + 1).flatMap({ Self.radixes[$0] }) else { return nil }
        let end = run(pos + 2) { $0.isASCII && ($0.hexDigitValue.map { $0 < radix } == true) }
        guard end > pos + 2 else { return nil }
        let text = String(chars[(pos + 2)..<end]).replacingOccurrences(of: "_", with: "")
        guard let value = Int(text, radix: radix) else { throw .unsupported("an integer beyond 64 bits") }
        pos = end
        return .int(value)
    }

    /// `YYYY-MM-DD`, then optionally `T` or a space, a time, and an offset.
    mutating func dateTime() throws(Failure) -> TOMLValue? {
        guard let date = dateMatch(at: pos) else { return nil }
        var end = pos + 10
        var value = TOMLValue.date(date)
        if let mark = char(end), "Tt ".contains(mark), let (time, after) = timeMatch(at: end + 1) {
            end = after
            var minutes: Int?
            if let (offset, past) = offsetMatch(at: end) {
                minutes = offset
                end = past
            }
            value = .dateTime(TOMLDateTime(date: date, time: time, offsetMinutes: minutes))
        }
        guard Self.exists(date) else {
            throw problem(.invalidDate, detail: String(chars[pos..<end]))
        }
        pos = end
        return value
    }

    func dateMatch(at start: Int) -> TOMLDate? {
        guard let year = digits(start, 4), char(start + 4) == "-", let month = digits(start + 5, 2),
              char(start + 7) == "-", let day = digits(start + 8, 2),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        return TOMLDate(year: year, month: month, day: day)
    }

    /// `HH:MM:SS`, with a fraction of which six digits are kept.
    func timeMatch(at start: Int) -> (TOMLTime, Int)? {
        guard let hour = digits(start, 2), char(start + 2) == ":", let minute = digits(start + 3, 2),
              char(start + 5) == ":", let second = digits(start + 6, 2),
              hour < 24, minute < 60, second < 60 else { return nil }
        var end = start + 8
        var fraction = ""
        if char(end) == ".", let first = char(end + 1), Self.isDigit(first) {
            end += 1
            while let next = char(end), Self.isDigit(next) {
                fraction.append(next)
                end += 1
            }
        }
        let padded = String(fraction.prefix(6)).padding(toLength: 6, withPad: "0", startingAt: 0)
        let micro = padded.compactMap(\.wholeNumberValue).reduce(0) { $0 * 10 + $1 }
        return (TOMLTime(hour: hour, minute: minute, second: second, microsecond: micro), end)
    }

    /// `Z`, or `+HH:MM` / `-HH:MM`, as minutes east of UTC.
    func offsetMatch(at start: Int) -> (Int, Int)? {
        guard let mark = char(start) else { return nil }
        if mark == "Z" || mark == "z" { return (0, start + 1) }
        guard mark == "+" || mark == "-", let hours = digits(start + 1, 2), char(start + 3) == ":",
              let minutes = digits(start + 4, 2), hours < 24, minutes < 60 else { return nil }
        let total = hours * 60 + minutes
        return (mark == "-" ? -total : total, start + 6)
    }

    /// Whether the day exists in its month, as Python's `datetime.date` checks it.
    static func exists(_ date: TOMLDate) -> Bool {
        let leap = date.year % 4 == 0 && (date.year % 100 != 0 || date.year % 400 == 0)
        let lengths = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        return date.year >= 1 && date.day <= lengths[date.month - 1]
    }
}
