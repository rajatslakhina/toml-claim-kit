/// Whether a text parses as TOML.
public enum TOMLValidation: Sendable, Hashable {
    /// It parses, with this many top-level keys.
    case valid(keys: Int)
    case invalid(TOMLProblem)
    /// It is TOML this checker does not model; the reason says which part.
    case unsupported(String)
}

/// What loading a text gives.
public enum TOMLLoadResult: Sendable, Hashable {
    case value(TOMLValue)
    /// The error loading raises, as Python's last traceback line shows it.
    case error(String)
    case unsupported(String)
}

/// Parses and loads TOML on its own, without reading an answer.
public enum TOMLValidator {
    public static func validate(_ text: String) -> TOMLValidation {
        do throws(Failure) {
            return .valid(keys: try TOMLParser.parse(text).value.members.count)
        } catch {
            if case let .problem(problem) = error { return .invalid(problem) }
            return .unsupported(error.message)
        }
    }

    /// What `tomllib.loads` returns.
    public static func load(_ text: String) -> TOMLLoadResult {
        result { () throws(Failure) in try TOMLParser.parse(text).value }
    }

    /// What one value written after `key = ` reads as: `3.10` is the float 3.1, `hello` raises.
    public static func value(_ text: String) -> TOMLLoadResult {
        result { () throws(Failure) in try scalar(text) }
    }

    static func scalar(_ text: String) throws(Failure) -> TOMLValue {
        try TOMLParser.parse("x = " + text).value.members[0].value
    }

    static func result(_ body: () throws(Failure) -> TOMLValue) -> TOMLLoadResult {
        do throws(Failure) {
            return .value(try body())
        } catch {
            if case let .unsupported(reason) = error { return .unsupported(reason) }
            return .error(error.message)
        }
    }
}
