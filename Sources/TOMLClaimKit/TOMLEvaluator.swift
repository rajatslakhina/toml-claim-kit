/// Checks one claim: parses the TOML, reads the value, or runs the `tomllib` call.
struct TOMLEvaluator {
    let policy: TOMLPolicy

    func judge(_ claim: TOMLClaim) -> TOMLFinding {
        switch claim.task {
        case let .validate(claimsValid): validity(claim, claimsValid)
        case let .read(text, expectation): reading(claim, text, expectation)
        case let .load(load): loading(claim, load)
        }
    }

    func validity(_ claim: TOMLClaim, _ claimsValid: Bool) -> TOMLFinding {
        let document: TOMLParser.Document
        do throws(Failure) {
            document = try TOMLParser.parse(claim.subject)
        } catch {
            guard case let .problem(problem) = error else {
                return TOMLFinding(claim: claim, outcome: .unchecked(error.message))
            }
            let outcome: TOMLFinding.Outcome = claimsValid ? .wrong(Slips.slip(for: problem.kind)) : .exact
            return TOMLFinding(claim: claim, outcome: outcome, problem: problem)
        }
        guard claimsValid else { return TOMLFinding(claim: claim, outcome: .wrong(.parses)) }
        guard policy.reportsCaveats, let caveat = Self.caveat(document) else {
            return TOMLFinding(claim: claim, outcome: .exact)
        }
        return TOMLFinding(claim: claim, outcome: .caveat(caveat))
    }

    static func caveat(_ document: TOMLParser.Document) -> TOMLFinding.Caveat? {
        if !document.versionLikeFloats.isEmpty { return .versionLikeFloats(document.versionLikeFloats) }
        return document.numericDottedKeys.isEmpty ? nil : .numericDottedKeys(document.numericDottedKeys)
    }

    func reading(_ claim: TOMLClaim, _ text: String, _ expectation: Expectation) -> TOMLFinding {
        let value: TOMLValue
        do throws(Failure) {
            value = try TOMLValidator.scalar(text)
        } catch {
            guard case let .problem(problem) = error else {
                return TOMLFinding(claim: claim, outcome: .unchecked(error.message))
            }
            let words = "tomllib refuses it: \(problem.what)"
            let outcome: TOMLFinding.Outcome = expectation.negated ? .exact : .wrong(Slips.slip(for: problem.kind))
            return TOMLFinding(claim: claim, outcome: outcome, actual: words, problem: problem)
        }
        guard !expectation.holds(value) else { return TOMLFinding(claim: claim, outcome: .exact) }
        let words = "tomllib reads it as \(value.described)"
        let named: TOMLValue = expectation.target == .type(.string) ? .string(text) : expectation.target.value
        let slip = expectation.negated ? nil : Slips.classify(named, value)
        return TOMLFinding(claim: claim, outcome: .wrong(slip), actual: words)
    }

    func loading(_ claim: TOMLClaim, _ load: Load) -> TOMLFinding {
        switch Runner.run(load) {
        case let .unsupported(reason):
            return TOMLFinding(claim: claim, outcome: .unchecked(reason))
        case let .error(message, slip):
            guard Wording.claimsError(claim.claimed) else {
                return TOMLFinding(claim: claim, outcome: .wrong(slip), actual: message, raises: true)
            }
            let matches = Runner.sameError(claim.claimed, message)
            return TOMLFinding(claim: claim, outcome: matches ? .exact : .wrong(nil), actual: message, raises: true)
        case let .value(result):
            let shown = Runner.render(result.value, load.output)
            guard !Wording.claimsError(claim.claimed) else {
                return TOMLFinding(claim: claim, outcome: .wrong(.doesNotRaise), actual: shown)
            }
            return TOMLFinding(claim: claim, outcome: compare(claim.claimed, result, load.output), actual: shown)
        }
    }

    func compare(_ claimed: String, _ result: Runner.Loaded, _ output: Load.Output) -> TOMLFinding.Outcome {
        let value = result.value
        if claimed == Runner.render(value, output) { return .exact }
        switch output {
        case .type:
            let name = claimed.hasPrefix("<class '") ? String(claimed.dropFirst(8).dropLast(2)) : claimed
            if name == value.pythonType { return .equivalent }
            guard let type = ObjectReader.pythonTypes[name] else { return .wrong(nil) }
            return .wrong(Slips.classify(type == .string ? .string(result.raw) : type.representative, value))
        case .print where !value.isContainer:
            let readsAs = (try? TOMLValidator.scalar(claimed))?.same(value) == true
            let meant = claimed == result.raw || readsAs
                ? TOMLValue.string(claimed) : (PythonLiteral.value(claimed) ?? .string(claimed))
            return .wrong(Slips.classify(meant, value))
        default:
            guard let meant = PythonLiteral.value(claimed) else { return .wrong(nil) }
            if meant.same(value) { return policy.acceptsEquivalent ? .equivalent : .wrong(nil) }
            return .wrong(Slips.classify(meant, value))
        }
    }
}
