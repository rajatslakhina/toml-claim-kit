/// Reads what an answer says about TOML and checks every claim: the one call most callers need.
public struct TOMLClaimChecker: Sendable {
    public let policy: TOMLPolicy
    public let reader: TOMLClaimReader

    public init(policy: TOMLPolicy = .standard) {
        self.policy = policy
        reader = TOMLClaimReader(checksTOMLBlocks: policy.checksTOMLBlocks)
    }

    public func claims(in text: String) -> [TOMLClaim] {
        reader.claims(in: text)
    }

    public func judge(_ claim: TOMLClaim) -> TOMLFinding {
        TOMLEvaluator(policy: policy).judge(claim)
    }

    public func check(_ text: String) -> TOMLReport {
        TOMLReport(findings: claims(in: text).map(judge))
    }
}

/// Checks a conversation's answers one after another and remembers what it flagged, so a wrong claim
/// stated again after a correction was asked for is marked as repeated rather than new.
public actor TOMLLedger {
    public struct Statistics: Sendable, Hashable {
        public var reviews = 0
        public var claims = 0
        public var flagged = 0
        public var repeated = 0
    }

    public nonisolated let checker: TOMLClaimChecker
    public private(set) var statistics = Statistics()
    private var flaggedKeys: Set<String> = []

    public init(checker: TOMLClaimChecker = TOMLClaimChecker()) {
        self.checker = checker
    }

    public func review(_ text: String) -> TOMLReport {
        var findings = checker.check(text).findings
        var keys: Set<String> = []
        for index in findings.indices where findings[index].severity >= .caution {
            let key = findings[index].key
            findings[index].isRepeated = flaggedKeys.contains(key)
            keys.insert(key)
        }
        flaggedKeys.formUnion(keys)
        let report = TOMLReport(findings: findings)
        statistics.reviews += 1
        statistics.claims += findings.count
        statistics.flagged += report.flagged.count
        statistics.repeated += report.repeatedCount
        return report
    }

    /// Starts a new conversation: nothing flagged so far counts as a repeat.
    public func forget() {
        flaggedKeys.removeAll()
    }
}
