import Foundation

/// Parses TOML 1.0 the way Python's `tomllib` does, rule for rule, stopping at the first mistake with
/// its line and column and a name for what went wrong.
struct TOMLParser {
    /// A parsed document and what the claims about it need besides its value.
    struct Document {
        let value: TOMLValue
        /// The text each scalar was written as, by its path, for a value set with `key = value`.
        let raws: [[PathStep]: String]
        /// `key = 3.10`: unquoted floats written with a trailing zero, which load without it.
        let versionLikeFloats: [String]
        /// `3.10 = "x"`: dotted keys of digits, which make nested tables rather than one key.
        let numericDottedKeys: [String]
    }

    static let whitespace: Set<Character> = [" ", "\t"]

    let chars: [Character]
    var pos = 0
    let root = TableBox()
    var flags = Flags()
    var header: [String] = []
    var raws: [[PathStep]: String] = [:]
    var versionLike: [String] = []
    var numericKeys: [String] = []
    /// Where the last value started, to name a mistake found just after it.
    var valueStart: Int?

    init(_ text: String) {
        chars = Array(text.replacingOccurrences(of: "\r\n", with: "\n"))
    }

    static func parse(_ text: String) throws(Failure) -> Document {
        var parser = TOMLParser(text)
        return try parser.document()
    }

    var peek: Character? {
        pos < chars.count ? chars[pos] : nil
    }

    func at(_ text: String) -> Bool {
        let marks = Array(text)
        return pos + marks.count <= chars.count && Array(chars[pos..<(pos + marks.count)]) == marks
    }

    mutating func skipSpace() {
        while let char = peek, Self.whitespace.contains(char) { pos += 1 }
    }

    func problem(_ kind: TOMLProblem.Kind, at offset: Int? = nil, detail: String? = nil) -> Failure {
        let index = min(offset ?? pos, chars.count)
        let before = chars[..<index]
        let line = before.filter { $0 == "\n" }.count + 1
        let column = index - (before.lastIndex(of: "\n").map { $0 + 1 } ?? 0) + 1
        return .problem(TOMLProblem(kind: kind, detail: detail, line: line, column: column))
    }

    mutating func document() throws(Failure) -> Document {
        while true {
            skipSpace()
            guard let char = peek else { break }
            if char == "\n" {
                pos += 1
                continue
            }
            if Self.startsKey(char) {
                try keyValueRule()
            } else if char == "[" {
                flags.finalizePending()
                try tableHeader()
            } else if char != "#" {
                throw problem(.invalidStatement)
            }
            skipSpace()
            try skipComment()
            guard let next = peek else { break }
            guard next == "\n" else { throw afterValue(.textAfterValue) }
            pos += 1
        }
        return Document(value: root.value, raws: raws, versionLikeFloats: versionLike, numericDottedKeys: numericKeys)
    }

    mutating func skipComment() throws(Failure) {
        guard peek == "#" else { return }
        while let char = peek, char != "\n" {
            if char != "\t", Self.isControl(char) { throw problem(.controlCharacter, detail: "in a comment") }
            pos += 1
        }
    }

    static func isControl(_ char: Character) -> Bool {
        char.unicodeScalars.allSatisfy { $0.value < 0x20 || $0.value == 0x7F }
    }

    static func dotted(_ key: [String]) -> String {
        key.joined(separator: ".")
    }

    /// `key = value` in the current table.
    mutating func keyValueRule() throws(Failure) {
        let pair = try keyValuePair()
        let (key, value, raw) = (pair.key, pair.value, pair.raw)
        let stem = key[key.count - 1]
        let parent = header + key.dropLast()
        for length in 1..<key.count {
            let container = header + key.prefix(length)
            if flags.isSet(container, .explicitNest) {
                throw problem(.tableRedefined, detail: Self.dotted(container))
            }
            flags.pending.append((container, .explicitNest))
        }
        if flags.isSet(parent, .frozen) { throw problem(.immutable, detail: Self.dotted(parent)) }
        let (table, path) = try nest(parent, in: root)
        if table.entries[stem] != nil { throw problem(.duplicateKey, detail: Self.dotted(header + key)) }
        if value.isContainer { flags.set(header + key, .frozen, recursive: true) }
        table.set(stem, .value(value))
        guard !value.isContainer else { return }
        raws[path + [.key(stem)]] = raw
        if case .float = value, raw.wholeMatch(of: #/[+-]?[0-9]+\.[0-9]*[1-9][0-9]*0/#) != nil {
            versionLike.append("\(Self.dotted(key)) = \(raw)")
        }
    }

    /// `[table]` or `[[array.of.tables]]`.
    mutating func tableHeader() throws(Failure) {
        valueStart = nil
        let isArray = at("[[")
        pos += isArray ? 2 : 1
        skipSpace()
        let key = try parseKey()
        let name = Self.dotted(key)
        if flags.isSet(key, .frozen) { throw problem(.immutable, detail: name) }
        if isArray {
            flags.unsetAll(key)
            flags.set(key, .explicitNest, recursive: false)
            let (table, _) = try nest(Array(key.dropLast()), in: root)
            switch table.entries[key[key.count - 1]] {
            case nil: table.set(key[key.count - 1], .tables([TableBox()]))
            case let .tables(items)?: table.set(key[key.count - 1], .tables(items + [TableBox()]))
            default: throw problem(.duplicateKey, detail: name)
            }
            guard at("]]") else { throw problem(.unclosedHeader) }
            pos += 2
        } else {
            if flags.isSet(key, .explicitNest) { throw problem(.tableRedefined, detail: name) }
            flags.set(key, .explicitNest, recursive: false)
            _ = try nest(key, in: root)
            guard peek == "]" else { throw problem(.unclosedHeader) }
            pos += 1
        }
        header = key
    }

    /// The table at `key`, opened where it is missing; the last item of an array of tables stands for it.
    func nest(_ key: [String], in base: TableBox) throws(Failure) -> (TableBox, [PathStep]) {
        var table = base
        var path: [PathStep] = []
        for part in key {
            path.append(.key(part))
            switch table.entries[part] {
            case nil:
                let opened = TableBox()
                table.set(part, .table(opened))
                table = opened
            case let .table(inner)?:
                table = inner
            case let .tables(items)?:
                table = items[items.count - 1]
                path.append(.index(items.count - 1))
            case .value?:
                throw problem(.duplicateKey, detail: Self.dotted(key))
            }
        }
        return (table, path)
    }
}
