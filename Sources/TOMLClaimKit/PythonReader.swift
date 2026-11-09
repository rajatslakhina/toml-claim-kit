import Foundation

/// Reads Python snippets that load TOML with `tomllib` and show what comes out: a comment on the line,
/// comment lines after a `print`, or REPL output. `tomllib.load(f)` and a `loads` call whose argument is
/// not a string in the snippet (`f.read()`) read the TOML block shown before the snippet; the mode the file
/// was opened with decides whether `load` runs at all.
struct PythonReader {
    static let tags: Set<String> = ["python", "py", "python3", "py3", "pycon", "ipython"]
    static let textLoads = ["tomllib.loads", "tomli.loads", "loads"]
    static let fileLoads = ["tomllib.load", "tomli.load", "load"]
    static let dumpers = ["tomllib.dumps", "tomllib.dump", "tomli.dumps", "tomli.dump"]
    static let dedents = ["textwrap.dedent(", "dedent("]

    /// The TOML block shown before the snippet.
    let context: String?
    /// Names bound to an open file, and whether it was opened in binary mode.
    var files: [String: Bool] = [:]
    /// Names bound to a string literal.
    var strings: [String: String] = [:]
    /// Names bound to a load's result.
    var results: [String: Load] = [:]
    var claims: [TOMLClaim] = []

    struct Statement {
        let code: String
        let claimed: String?
    }

    static func isPython(tag: String, text: String) -> Bool {
        tags.contains(tag) || (tag.isEmpty && text.contains("import toml"))
    }

    static func claims(in lines: [String], context: String?) -> [TOMLClaim] {
        var reader = PythonReader(context: context)
        for statement in statements(lines) { reader.handle(statement) }
        return reader.claims
    }

    static func isPrompt(_ line: String) -> Bool {
        let trimmed = line.trimmed
        return trimmed == ">>>" || trimmed.hasPrefix(">>> ")
    }

    static func statements(_ lines: [String]) -> [Statement] {
        var statements: [Statement] = []
        var index = 0
        while index < lines.count {
            statements.append(isPrompt(lines[index]) ? repl(lines, &index) : script(lines, &index))
        }
        return statements
    }

    /// A prompt line, its `...` continuation lines, and the output under them.
    static func repl(_ lines: [String], _ index: inout Int) -> Statement {
        var source = String(lines[index].trimmed.dropFirst(3)).trimmed
        index += 1
        while index < lines.count, lines[index].trimmed.hasPrefix("...") {
            source += "\n" + String(lines[index].trimmed.dropFirst(3)).dropFirst(lines[index].trimmed.count > 3 ? 1 : 0)
            index += 1
        }
        let scan = PythonScanner.scan(source)
        let start = index
        while index < lines.count, !isPrompt(lines[index]), !lines[index].trimmed.isEmpty { index += 1 }
        let output = lines[start..<index].joined(separator: "\n").trimmed
        return Statement(code: scan.code.trimmed, claimed: output.isEmpty ? scan.comment : output)
    }

    /// Lines up to closed brackets and strings, with a trailing comment or the comment lines after a print.
    static func script(_ lines: [String], _ index: inout Int) -> Statement {
        var source = lines[index]
        index += 1
        var scan = PythonScanner.scan(source)
        while scan.depth > 0 || scan.openString, index < lines.count {
            source += "\n" + lines[index]
            index += 1
            scan = PythonScanner.scan(source)
        }
        let code = scan.code.trimmed
        guard scan.comment == nil, code.hasPrefix("print(") else { return Statement(code: code, claimed: scan.comment) }
        return Statement(code: code, claimed: commentLines(lines, &index))
    }

    /// Comment-only lines after a print, the `#` and one space removed, an `Output:` line dropped.
    static func commentLines(_ lines: [String], _ index: inout Int) -> String? {
        var output: [String] = []
        while index < lines.count, lines[index].trimmed.hasPrefix("#") {
            output.append(String(lines[index].trimmed.dropFirst()).trimmed)
            index += 1
        }
        if let first = output.first, first.lowercased().hasPrefix("output") {
            output[0] = Wording.dropLead(first)
            if output[0].isEmpty { output.removeFirst() }
        }
        return output.isEmpty ? nil : output.joined(separator: "\n")
    }
}

extension PythonReader {
    mutating func handle(_ statement: Statement) {
        let code = statement.code
        if let (expression, name) = Self.with(code) {
            if let binary = Self.openMode(expression) { files[name] = binary }
            return
        }
        if let (name, expression) = Self.assignment(code) {
            bind(name, expression, statement)
            return
        }
        let (inner, output) = Self.unwrapped(code)
        guard let load = load(inner, output: output) else { return }
        record(load, subject: code, statement.claimed)
    }

    /// `name = expression`.
    static func assignment(_ code: String) -> (String, String)? {
        let name = code.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
        let rest = code.dropFirst(name.count).trimmed
        guard !name.isEmpty, rest.hasPrefix("="), !rest.hasPrefix("==") else { return nil }
        return (String(name), String(rest.dropFirst()).trimmed)
    }

    /// `with open(...) as f:`: the opening expression and the name.
    static func with(_ code: String) -> (String, String)? {
        guard code.hasPrefix("with "), code.hasSuffix(":"),
              let range = code.range(of: " as ", options: .backwards) else { return nil }
        let expression = String(code[code.index(code.startIndex, offsetBy: 5)..<range.lowerBound]).trimmed
        return (expression, String(code[range.upperBound...].dropLast()).trimmed)
    }

    /// Whether `open(path, mode)` or `path.open(mode)` opens in binary mode; `nil` when it opens nothing.
    static func openMode(_ expression: String) -> Bool? {
        guard let range = expression.range(of: "open(") else { return nil }
        let isMethod = range.lowerBound != expression.startIndex
        guard !isMethod || expression[..<range.lowerBound].hasSuffix("."),
              let parts = PythonScanner.closing(expression, open: expression.distance(
                  from: expression.startIndex, to: range.upperBound) - 1) else { return nil }
        let arguments = PythonScanner.arguments(parts.inside)
        let keyword = arguments.first { $0.hasPrefix("mode=") }.map { String($0.dropFirst(5)) }
        let mode = keyword ?? arguments.filter { !$0.contains("=") }.dropFirst(isMethod ? 0 : 1).first
        guard let mode, case let .string(text)? = PythonLiteral.value(mode) else { return false }
        return text.contains("b")
    }

    mutating func bind(_ name: String, _ expression: String, _ statement: Statement) {
        if let text = string(expression) {
            strings[name] = text
            results[name] = nil
            return
        }
        if let context, expression.hasSuffix(".read()") || expression.hasSuffix(".read_text()") {
            strings[name] = context
            return
        }
        if let binary = Self.openMode(expression) {
            files[name] = binary
            return
        }
        guard let load = load(expression, output: .repr) else { return }
        if !load.call.alwaysRaises { results[name] = load }
        record(load, subject: expression, statement.claimed)
    }

    /// The expression inside `print(…)` and `type(…)`, and how its value is shown.
    static func unwrapped(_ code: String) -> (String, Load.Output) {
        var expression = code
        var output = Load.Output.repr
        if let inner = call(expression, "print") {
            expression = inner
            output = .print
        }
        if let inner = call(expression, "type") {
            expression = inner
            output = .type
        }
        return (expression, output)
    }

    /// The argument text of `name(…)` when the whole expression is that one call.
    static func call(_ expression: String, _ name: String) -> String? {
        guard expression.hasPrefix(name + "("), let parts = PythonScanner.closing(expression, open: name.count),
              parts.rest.trimmed.isEmpty else { return nil }
        return parts.inside.trimmed
    }

    /// A string literal, or `textwrap.dedent` of one, or a name bound to one.
    func string(_ expression: String) -> String? {
        if let dedent = Self.dedents.first(where: expression.hasPrefix),
           let inner = Self.call(expression, String(dedent.dropLast())) {
            return string(inner).map(Self.dedented)
        }
        if case let .string(text)? = PythonLiteral.value(expression) { return text }
        return strings[expression]
    }

    /// `textwrap.dedent`: the indentation every non-blank line shares, removed.
    static func dedented(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        let margins = lines.filter { !$0.trimmed.isEmpty }.map { $0.prefix { $0 == " " || $0 == "\t" }.count }
        let margin = margins.min() ?? 0
        return lines.map { $0.trimmed.isEmpty ? "" : String($0.dropFirst(margin)) }.joined(separator: "\n")
    }

    /// A load call this reader can run, or a name bound to one, with what is read out of it.
    func load(_ expression: String, output: Load.Output) -> Load? {
        if let load = call(expression, output: output) { return load }
        let name = expression.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
        let rest = String(expression.dropFirst(name.count))
        guard let bound = results[String(name)], let more = Accessors.read(rest) else {
            return nil
        }
        return Load(source: bound.source, call: bound.call, accessors: bound.accessors + more, output: output)
    }

    func call(_ expression: String, output: Load.Output) -> Load? {
        let names = Self.dumpers + Self.textLoads + Self.fileLoads
        guard let name = names.first(where: { expression.hasPrefix($0 + "(") }),
              let parts = PythonScanner.closing(expression, open: name.count),
              let accessors = Accessors.read(parts.rest.trimmed) else { return nil }
        let argument = PythonScanner.arguments(parts.inside).first ?? ""
        let call: Load.Call
        if Self.dumpers.contains(name) {
            call = .dumper(name)
        } else if Self.fileLoads.contains(name) {
            call = fileCall(argument)
        } else {
            guard let source = string(argument) ?? context else { return nil }
            return Load(source: source, call: .loads, accessors: accessors, output: output)
        }
        guard call.alwaysRaises || context != nil else { return nil }
        return Load(source: context ?? "", call: call, accessors: accessors, output: output)
    }

    /// What `tomllib.load` is given: a path (a string), a file opened in some mode, or a file the snippet
    /// does not show opening, taken to be binary.
    func fileCall(_ argument: String) -> Load.Call {
        if string(argument) != nil { return .path }
        guard let binary = Self.openMode(argument) ?? files[argument] else { return .binaryFile }
        return binary ? .binaryFile : .textFile
    }

    /// Adds the claim when the stated result reads as output; a comment that describes the line states none.
    /// A call that always raises is a claim on its own: the answer shows it as code that runs.
    mutating func record(_ load: Load, subject: String, _ claimed: String?) {
        if let claimed, let output = Wording.output(claimed, load.output) {
            claims.append(TOMLClaim(kind: .loading, subject: subject, claimed: output, task: .load(load)))
        } else if load.call.alwaysRaises {
            claims.append(TOMLClaim(kind: .loading, subject: subject, claimed: "code that runs", isExplicit: false,
                                    task: .load(load)))
        }
    }
}

/// Reads `["key"]`, `[0]` and `.get("key", default)` after a value.
enum Accessors {
    static func read(_ text: String) -> [Accessor]? {
        var rest = text.trimmed
        var accessors: [Accessor] = []
        while !rest.isEmpty {
            guard let (accessor, after) = next(rest) else { return nil }
            accessors.append(accessor)
            rest = after.trimmed
        }
        return accessors
    }

    static func next(_ text: String) -> (Accessor, String)? {
        if text.hasPrefix("["), let parts = PythonScanner.closing(text, open: 0),
           let key = PythonLiteral.value(parts.inside) {
            return (.subscripted(key), parts.rest)
        }
        guard text.hasPrefix(".get("), let parts = PythonScanner.closing(text, open: 4) else { return nil }
        let arguments = PythonScanner.arguments(parts.inside).map(PythonLiteral.value)
        guard let first = arguments.first, let key = first else { return nil }
        let fallback = arguments.count > 1 ? arguments[1] : .null
        guard let fallback else { return nil }
        return (.get(key, fallback: fallback), parts.rest)
    }
}

/// How an answer introduces a result, and whether a comment reads as one.
enum Wording {
    static let leads = ["output:", "output", "result:", "returns", "prints", "gives", "=>", "->", "\u{2192}"]
    /// Leads that always introduce a result; "prints the version" after `prints` may describe the line.
    static let arrows = ["output", "result:", "=>", "->", "\u{2192}"]
    static let typeNames: Set<String> = ["str", "int", "float", "bool", "NoneType", "list", "dict", "datetime.date",
                                         "datetime.time", "datetime.datetime"]

    /// A stated result without its lead-in (`Output:`, `->`, `returns`).
    static func dropLead(_ text: String) -> String {
        let trimmed = text.trimmed
        guard let lead = leads.first(where: { trimmed.lowercased().hasPrefix($0) }) else { return trimmed }
        return String(trimmed.dropFirst(lead.count)).trimmed
    }

    /// The stated result when the comment reads as one, `nil` when it describes the line instead.
    static func output(_ comment: String, _ output: Load.Output) -> String? {
        let text = dropLead(comment)
        guard !text.isEmpty else { return nil }
        if claimsError(text) { return text }
        switch output {
        case .type: return text.hasPrefix("<class '") || typeNames.contains(text) ? text : nil
        case .repr: return PythonLiteral.value(text) == nil ? nil : text
        case .print:
            let arrow = arrows.contains { comment.trimmed.lowercased().hasPrefix($0) }
            return arrow || !text.contains(" ") || PythonLiteral.value(text) != nil ? text : nil
        }
    }

    static func claimsError(_ text: String) -> Bool {
        text.contains("Error") || text.contains("Exception") || text.lowercased().hasPrefix("raises")
    }
}
