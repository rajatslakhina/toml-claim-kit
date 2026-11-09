import TOMLClaimKit

/// Prints a report the same way for every scenario.
enum Printer {
    static func marker(_ finding: TOMLFinding) -> String {
        switch finding.severity {
        case .holds: "ok   "
        case .unchecked: "skip "
        case .caution: "check"
        case .wrong: "WRONG"
        }
    }

    static func slip(_ finding: TOMLFinding) -> String {
        switch finding.outcome {
        case let .wrong(slip?): " [\(slip.rawValue)]"
        case let .caveat(caveat): " [\(name(caveat))]"
        default: ""
        }
    }

    static func name(_ caveat: TOMLFinding.Caveat) -> String {
        switch caveat {
        case .versionLikeFloats: "versionLikeFloats"
        case .numericDottedKeys: "numericDottedKeys"
        }
    }

    static func show(_ report: TOMLReport, label: String) {
        print("    \(label): \(report.verdict.rawValue) (\(report.summary))")
        for finding in report.findings {
            print("      \(marker(finding)) \(finding.claim.kind.rawValue): \(finding.claim.excerpt)\(slip(finding))")
            if finding.severity >= .caution { print("            \(finding.explanation)") }
        }
    }

    static func scenario(_ number: Int, _ title: String) {
        print("")
        print("[\(number)] \(title)")
    }
}
