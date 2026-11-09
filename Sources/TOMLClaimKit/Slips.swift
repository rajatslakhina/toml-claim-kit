/// Names the mistake behind a wrong claim from what the answer says and what loading gives.
enum Slips {
    static let problemSlips: [TOMLProblem.Kind: TOMLFinding.Slip] = [
        .bareString: .bareString, .capitalizedBoolean: .capitalizedBoolean, .noNull: .noNull,
        .leadingZero: .leadingZero, .versionNumber: .unquotedVersion, .floatDot: .floatDot, .dateFormat: .dateFormat,
        .invalidEscape: .backslash, .duplicateKey: .duplicateKey, .tableRedefined: .duplicateTable,
        .immutable: .inlineTableExtended, .trailingComma: .inlineTableSyntax, .newlineInInlineTable: .inlineTableSyntax
    ]

    /// The slip behind a text that does not parse.
    static func slip(for kind: TOMLProblem.Kind) -> TOMLFinding.Slip {
        problemSlips[kind] ?? .notTOML
    }

    static func classify(_ claimed: TOMLValue, _ actual: TOMLValue) -> TOMLFinding.Slip? {
        switch (claimed, actual) {
        case let (.table(pairs), .table):
            for pair in pairs {
                if let found = actual.lookup(.string(pair.key)), !found.same(pair.value) {
                    return classify(pair.value, found)
                }
            }
            return nil
        case let (.array(claimedItems), .array(actualItems)) where claimedItems.count == actualItems.count:
            return zip(claimedItems, actualItems).first { !$0.0.same($0.1) }.flatMap { classify($0.0, $0.1) }
        case let (.string(text), _) where !actual.isString:
            return textSlip(text, actual)
        case (_, .string) where !claimed.isContainer && !claimed.isString:
            return .staysString
        case (.int, .float), (.float, .int):
            return .numberType
        default:
            return nil
        }
    }

    /// The text the answer kept, which TOML reads as the value loading gave.
    static func textSlip(_ text: String, _ actual: TOMLValue) -> TOMLFinding.Slip? {
        guard (try? TOMLValidator.scalar(text))?.same(actual) == true else { return nil }
        switch actual {
        case .float:
            return text.wholeMatch(of: #/[-+]?[0-9_]*\.[0-9_]*0/#) != nil ? .trailingZeroDropped : .unquotedNumber
        case .int:
            return .unquotedNumber
        case .date, .time, .dateTime:
            return .dateParsed
        default:
            return nil
        }
    }
}
