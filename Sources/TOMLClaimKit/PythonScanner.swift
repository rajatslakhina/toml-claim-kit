/// Brackets, strings (triple-quoted ones too) and comments in Python source.
enum PythonScanner {
    struct Scan {
        /// The source with its comments removed.
        var code = ""
        var depth = 0
        /// Whether a string is still open at the end.
        var openString = false
        /// A comment on the last line, without its `#`.
        var comment: String?
    }

    static func scan(_ text: String) -> Scan {
        var scan = Scan()
        let characters = Array(text)
        var index = 0
        var quote: (Character, Int)?
        while index < characters.count {
            let character = characters[index]
            if quote != nil {
                index += stepString(characters, index, &quote, &scan)
                continue
            }
            if character == "#" {
                let end = characters[index...].firstIndex(of: "\n") ?? characters.count
                scan.comment = String(characters[(index + 1)..<end]).trimmed
                index = end
                continue
            }
            if character == "\n" { scan.comment = nil }
            if character == "\"" || character == "'" {
                let width = index + 2 < characters.count && characters[index + 1] == character
                    && characters[index + 2] == character ? 3 : 1
                quote = (character, width)
                scan.code += String(repeating: character, count: width)
                index += width
                continue
            }
            scan.depth += "([{".contains(character) ? 1 : (")]}".contains(character) ? -1 : 0)
            scan.code.append(character)
            index += 1
        }
        scan.openString = quote != nil
        return scan
    }

    /// One step inside a string; returns how far it moved and closes the string at its quote.
    static func stepString(_ characters: [Character], _ index: Int, _ quote: inout (Character, Int)?,
                           _ scan: inout Scan) -> Int {
        guard let (mark, width) = quote else { return 1 }
        let character = characters[index]
        if character == "\\", index + 1 < characters.count {
            scan.code += String(characters[index...(index + 1)])
            return 2
        }
        let closes = character == mark && index + width <= characters.count
            && characters[index..<(index + width)].allSatisfy { $0 == mark }
        guard closes else {
            scan.code.append(character)
            return 1
        }
        quote = nil
        scan.code += String(repeating: mark, count: width)
        return width
    }

    /// The text up to the bracket that closes the one at `open`, and the rest after it.
    static func closing(_ text: String, open: Int) -> (inside: String, rest: String)? {
        let characters = Array(text)
        var index = open + 1
        var depth = 1
        while index < characters.count {
            let character = characters[index]
            if character == "\"" || character == "'" {
                index = skipString(characters, from: index)
                continue
            }
            depth += "([{".contains(character) ? 1 : (")]}".contains(character) ? -1 : 0)
            index += 1
            if depth == 0 {
                return (String(characters[(open + 1)..<(index - 1)]), String(characters[index...]))
            }
        }
        return nil
    }

    /// The index after the string starting at `index`.
    static func skipString(_ characters: [Character], from index: Int) -> Int {
        let quote = characters[index]
        let tripled = index + 2 < characters.count && characters[index + 1] == quote && characters[index + 2] == quote
        let width = tripled ? 3 : 1
        var position = index + width
        while position < characters.count {
            if characters[position] == "\\" {
                position += 2
                continue
            }
            if characters[position] == quote, position + width <= characters.count,
               characters[position..<(position + width)].allSatisfy({ $0 == quote }) {
                return position + width
            }
            position += 1
        }
        return characters.count
    }

    /// Splits at commas outside brackets and strings.
    static func arguments(_ text: String) -> [String] {
        let characters = Array(text)
        var parts: [String] = []
        var depth = 0
        var start = 0
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\"" || character == "'" {
                index = skipString(characters, from: index)
                continue
            }
            depth += "([{".contains(character) ? 1 : (")]}".contains(character) ? -1 : 0)
            if character == ",", depth == 0 {
                parts.append(String(characters[start..<index]))
                start = index + 1
            }
            index += 1
        }
        parts.append(String(characters[start...]))
        return parts.map(\.trimmed).filter { !$0.isEmpty }
    }
}
