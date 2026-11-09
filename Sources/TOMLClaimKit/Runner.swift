/// Runs a `tomllib` call as Python would and reads the accessed part out of what it returns.
enum Runner {
    struct Loaded {
        let value: TOMLValue
        /// The text the accessed value was written as, when it is a scalar set with `key = value`; empty
        /// otherwise.
        let raw: String
    }

    enum Outcome {
        case value(Loaded)
        /// Python's error line, and the slip behind showing a value instead.
        case error(String, TOMLFinding.Slip)
        case unsupported(String)
    }

    struct StepError: Error {
        let message: String
        let slip: TOMLFinding.Slip
    }

    static let binaryMode = "TypeError: File must be opened in binary mode, e.g. use `open('foo.toml', 'rb')`"

    static func run(_ load: Load) -> Outcome {
        switch load.call {
        case .textFile: return .error(binaryMode, .textMode)
        case .path: return .error("AttributeError: 'str' object has no attribute 'read'", .pathArgument)
        case let .dumper(name):
            let parts = name.split(separator: ".")
            return .error("AttributeError: module '\(parts[0])' has no attribute '\(parts[1])'", .noDumper)
        case .loads, .binaryFile: break
        }
        let document: TOMLParser.Document
        do throws(Failure) {
            document = try TOMLParser.parse(load.source)
        } catch {
            switch error {
            case let .unsupported(reason): return .unsupported(reason)
            case let .problem(problem): return .error(error.message, Slips.slip(for: problem.kind))
            }
        }
        var value = document.value
        var path: [PathStep] = []
        for accessor in load.accessors {
            switch step(value, accessor) {
            case let .success((next, place)):
                value = next
                path.append(place)
            case let .failure(error):
                return .error(error.message, error.slip)
            }
        }
        return .value(Loaded(value: value, raw: document.raws[path] ?? ""))
    }

    /// One `[key]`, `[index]` or `.get(key, default)`, as Python evaluates it.
    static func step(_ value: TOMLValue, _ accessor: Accessor) -> Result<(TOMLValue, PathStep), StepError> {
        switch (accessor, value) {
        case let (.get(key, fallback), .table):
            return .success((value.lookup(key) ?? fallback, place(key)))
        case (.get, _):
            return .failure(StepError(message: "AttributeError: '\(value.pythonType)' object has no attribute 'get'",
                                      slip: .raises))
        case let (.subscripted(key), .table):
            guard let found = value.lookup(key) else {
                return .failure(StepError(message: "KeyError: \(key.pythonRepr)", slip: missingKeySlip(key, value)))
            }
            return .success((found, place(key)))
        case let (.subscripted(.int(index)), .array(items)):
            let position = index < 0 ? items.count + index : index
            guard items.indices.contains(position) else {
                return .failure(StepError(message: "IndexError: list index out of range", slip: .raises))
            }
            return .success((items[position], .index(position)))
        case let (.subscripted(key), .array):
            return .failure(StepError(message: "TypeError: list indices must be integers or slices, not "
                                      + key.pythonType, slip: .raises))
        default:
            return .failure(StepError(message: "TypeError: '\(value.pythonType)' object is not subscriptable",
                                      slip: .raises))
        }
    }

    static func place(_ key: TOMLValue) -> PathStep {
        guard case let .string(name) = key else { return .key(key.pythonRepr) }
        return .key(name)
    }

    /// `data["tool.poetry"]`: a missing key whose dotted parts lead somewhere one level at a time.
    static func missingKeySlip(_ key: TOMLValue, _ table: TOMLValue) -> TOMLFinding.Slip {
        guard case let .string(name) = key, name.contains(".") else { return .raises }
        var current: TOMLValue? = table
        for part in name.split(separator: ".") { current = current?.lookup(.string(String(part))) }
        return current == nil ? .raises : .dottedKeyLookup
    }

    static func render(_ value: TOMLValue, _ output: Load.Output) -> String {
        switch output {
        case .repr: value.pythonRepr
        case .print: value.pythonStr
        case .type: "<class '\(value.pythonType)'>"
        }
    }

    /// Whether a claimed error names the one raised: any TOML error for a decode error, the class otherwise.
    static func sameError(_ claimed: String, _ message: String) -> Bool {
        let raised = String(message.prefix { $0 != ":" })
        if raised.hasSuffix("TOMLDecodeError") {
            return claimed.contains("TOMLDecodeError") || claimed.contains("TOML")
        }
        let named = claimed.split { !$0.isLetter }.first { $0.hasSuffix("Error") || $0.hasSuffix("Exception") }
        return named.map { raised.hasSuffix($0) } ?? true
    }
}
