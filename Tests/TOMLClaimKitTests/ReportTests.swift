@testable import TOMLClaimKit
import XCTest

final class ReportTests: XCTestCase {
    func testVerdictsAndText() {
        let checker = TOMLClaimChecker()
        XCTAssertEqual(checker.check("Nothing about it.").verdict, .noClaims)
        XCTAssertEqual(checker.check("Nothing about it.").summary, "no claims about TOML")
        XCTAssertNil(checker.check("Nothing about it.").note)
        XCTAssertNil(checker.check("Nothing about it.").feedback)
        XCTAssertEqual(checker.check(block("toml", "a = 1")).verdict, .verified)
        XCTAssertEqual(checker.check(block("toml", "n = 99999999999999999999")).verdict, .unchecked)
        XCTAssertEqual(checker.check(block("toml", "n = 99999999999999999999")).summary,
                       "1 claim checked, 0 hold, 1 unchecked")
        XCTAssertEqual(checker.check(block("toml", "v = 3.10")).verdict, .caution)
        let wrong = checker.check(block("toml", "v = 3.10") + "\n" + block("toml", "a = hello"))
        XCTAssertEqual(wrong.verdict, .wrong)
        XCTAssertEqual(wrong.summary, "2 claims checked, 0 hold, 1 to check, 1 wrong")
        XCTAssertEqual(wrong.corrections.count, 2)
        XCTAssertTrue(wrong.note?.hasPrefix("TOML check: ") == true)
        XCTAssertTrue(wrong.feedback?.contains("run each snippet with tomllib") == true)
        XCTAssertEqual(checker.claims(in: block("toml", "a = 1")).first?.excerpt, "a = 1 is shown as TOML")
        XCTAssertEqual(TOMLClaim.shortened(String(repeating: "x", count: 70)).count, 60)
        let claim = checker.claims(in: block("python", "import tomllib\ntomllib.loads('a = 1')  # {'a': 1}"))[0]
        XCTAssertEqual(claim.excerpt, "tomllib.loads('a = 1') -> {'a': 1}")
        XCTAssertEqual(checker.judge(claim).outcome, .exact)
        XCTAssertEqual(TOMLFinding.quoted("`a`"), "`a`")
        XCTAssertTrue(TOMLFinding.Severity.holds < .wrong)
    }

    func testLedgerMarksRepeats() async {
        let ledger = TOMLLedger()
        let answer = block("toml", "a = hello")
        let first = await ledger.review(answer)
        XCTAssertEqual(first.repeatedCount, 0)
        let second = await ledger.review(answer)
        XCTAssertEqual(second.repeatedCount, 1)
        XCTAssertTrue(second.summary.hasSuffix("1 repeated"))
        XCTAssertTrue(second.note?.hasSuffix("stated again after a correction was asked for.") == true)
        await ledger.forget()
        let third = await ledger.review(answer)
        XCTAssertEqual(third.repeatedCount, 0)
        let statistics = await ledger.statistics
        XCTAssertEqual(statistics.reviews, 3)
        XCTAssertEqual(statistics.flagged, 3)
        XCTAssertEqual(statistics.repeated, 1)
    }

    func testEveryHintedSlipHasAHint() {
        let unhinted: Set<TOMLFinding.Slip> = [.notTOML, .parses, .raises, .doesNotRaise]
        for slip in TOMLFinding.Slip.allCases where !unhinted.contains(slip) {
            XCTAssertNotNil(TOMLFinding.hints[slip], slip.rawValue)
        }
        XCTAssertEqual(Slips.slip(for: .textAfterValue), .notTOML)
        XCTAssertEqual(Slips.slip(for: .trailingComma), .inlineTableSyntax)
        XCTAssertNil(Slips.classify(.bool(true), .int(1)))
        XCTAssertNil(Slips.textSlip("x", .int(1)))
        XCTAssertNil(Slips.classify(.array([.int(1)]), .array([.int(1), .int(2)])))
        XCTAssertNil(Slips.classify(.table([TOMLPair(key: "a", value: .int(1))]), .table([])))
    }

    func testSentencesWithoutAnActualValue() {
        let reading = TOMLClaim(kind: .reading, subject: "a = 1", claimed: "a string",
                                task: .read("1", Expectation(target: .type(.string), negated: false)))
        XCTAssertEqual(TOMLFinding(claim: reading, outcome: .wrong(nil)).explanation, "`a = 1` is not a string: .")
        let load = Load(source: "", call: .loads, accessors: [], output: .repr)
        let loading = TOMLClaim(kind: .loading, subject: "x", claimed: "1", task: .load(load))
        XCTAssertEqual(TOMLFinding(claim: loading, outcome: .wrong(nil)).explanation, "`x` gives , not 1.")
    }

    func testRunnerHelpers() {
        XCTAssertTrue(Runner.sameError("raises TOMLDecodeError", "tomllib.TOMLDecodeError: x"))
        XCTAssertFalse(Runner.sameError("raises KeyError", "tomllib.TOMLDecodeError: x"))
        XCTAssertTrue(Runner.sameError("it raises", "KeyError: 'a'"))
        XCTAssertFalse(Runner.sameError("ValueError", "KeyError: 'a'"))
        XCTAssertEqual(Runner.place(.int(2)), .key("2"))
        XCTAssertEqual(Runner.render(.int(1), .type), "<class 'int'>")
        XCTAssertFalse(Load.Call.loads.alwaysRaises)
        XCTAssertTrue(Load.Call.path.alwaysRaises)
    }
}
