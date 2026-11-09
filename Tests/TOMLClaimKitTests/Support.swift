@testable import TOMLClaimKit
import XCTest

/// Checks an answer and returns its findings.
func findings(_ text: String, policy: TOMLPolicy = .standard) -> [TOMLFinding] {
    TOMLClaimChecker(policy: policy).check(text).findings
}

/// The slip of a wrong finding, or `nil`.
func slip(_ finding: TOMLFinding) -> TOMLFinding.Slip? {
    if case let .wrong(slip) = finding.outcome { return slip }
    return nil
}

/// A fenced block.
func block(_ tag: String, _ body: String) -> String {
    "```\(tag)\n\(body)\n```"
}

/// The value `tomllib.loads` gives for a text, or `nil` when it raises.
func loaded(_ text: String) -> TOMLValue? {
    if case let .value(value) = TOMLValidator.load(text) { return value }
    return nil
}

/// The problem kind a text is refused for.
func refusal(_ text: String) -> TOMLProblem.Kind? {
    if case let .invalid(problem) = TOMLValidator.validate(text) { return problem.kind }
    return nil
}
