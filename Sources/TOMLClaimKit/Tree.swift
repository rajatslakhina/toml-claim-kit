/// A table as the parser builds it, keys in the order they first appear.
final class TableBox {
    var keys: [String] = []
    var entries: [String: Entry] = [:]

    func set(_ key: String, _ entry: Entry) {
        if entries[key] == nil { keys.append(key) }
        entries[key] = entry
    }

    var value: TOMLValue {
        .table(keys.compactMap { key in entries[key].map { TOMLPair(key: key, value: $0.value) } })
    }
}

enum Entry {
    /// A table opened by a header or a dotted key.
    case table(TableBox)
    /// An array of tables, one per `[[header]]`.
    case tables([TableBox])
    /// A value written after `=`, inline tables and arrays included.
    case value(TOMLValue)

    var value: TOMLValue {
        switch self {
        case let .table(table): table.value
        case let .tables(tables): .array(tables.map(\.value))
        case let .value(value): value
        }
    }
}

/// A step from the document to a value: a key, or an index into an array of tables.
enum PathStep: Hashable, Sendable {
    case key(String)
    case index(Int)
}

/// What `tomllib` remembers about each key path while it reads: whether a header or a dotted key declared
/// the table (so it cannot be declared again), and whether an inline value froze it.
struct Flags {
    enum Flag {
        case explicitNest
        case frozen
    }

    final class Node {
        var flags: Set<Flag> = []
        var recursive: Set<Flag> = []
        var nested: [String: Node] = [:]

        func child(_ key: String) -> Node {
            if let node = nested[key] { return node }
            let node = Node()
            nested[key] = node
            return node
        }
    }

    let root = Node()
    /// Tables that dotted keys opened, declared once the next header starts.
    var pending: [([String], Flag)] = []

    func isSet(_ key: [String], _ flag: Flag) -> Bool {
        guard let stem = key.last else { return false }
        var node = root
        for part in key.dropLast() {
            guard let inner = node.nested[part] else { return false }
            if inner.recursive.contains(flag) { return true }
            node = inner
        }
        guard let inner = node.nested[stem] else { return false }
        return inner.flags.contains(flag) || inner.recursive.contains(flag)
    }

    func set(_ key: [String], _ flag: Flag, recursive: Bool) {
        let node = key.reduce(root) { $0.child($1) }
        if recursive {
            node.recursive.insert(flag)
        } else {
            node.flags.insert(flag)
        }
    }

    /// Forgets everything under `key`: a new `[[key]]` item starts empty.
    func unsetAll(_ key: [String]) {
        var node = root
        for part in key.dropLast() {
            guard let inner = node.nested[part] else { return }
            node = inner
        }
        node.nested.removeValue(forKey: key[key.count - 1])
    }

    mutating func finalizePending() {
        for (key, flag) in pending { set(key, flag, recursive: false) }
        pending = []
    }
}
