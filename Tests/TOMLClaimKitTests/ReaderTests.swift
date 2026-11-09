@testable import TOMLClaimKit
import XCTest

final class ReaderTests: XCTestCase {
    func testValiditySentencesAndBlocks() {
        let valid = "The block below is valid TOML:\n" + block("toml", "a = 1")
        XCTAssertEqual(findings(valid).map(\.outcome), [.exact])
        let invalid = block("", "a = hello") + "\nThe TOML above is not valid TOML."
        XCTAssertEqual(findings(invalid).map(\.outcome), [.exact])
        let parses = "This won't parse as TOML:\n" + block("toml", "a = 1")
        XCTAssertEqual(findings(parses).map(slip), [.parses])
        XCTAssertEqual(findings(parses)[0].explanation, "The text said not to be TOML parses.")
        let inline = "In TOML, `a = 1` is valid TOML. And `[tool]` is valid TOML too."
        XCTAssertEqual(findings(inline).count, 2)
        XCTAssertTrue(findings("Is `a = 1` valid TOML?").isEmpty)
        XCTAssertTrue(findings("This valid TOML has nothing next to it.").isEmpty)
        let following = "The following is valid TOML.\n" + block("toml", "a = 1") + "\nMore text."
        XCTAssertEqual(findings(following).map(\.claim.isExplicit), [true])
        let previous = block("text", "b = 2") + "\nThe previous TOML is valid TOML."
        XCTAssertEqual(findings(previous).map(\.outcome), [.exact])
        XCTAssertTrue(findings(block("toml", "   ")).isEmpty)
        XCTAssertTrue(findings("No mention here.\n" + block("toml", "a = 1"), policy: .lenient).isEmpty)
    }

    func testBlocksShownAsTOMLAndCaveats() {
        let shown = findings(block("toml", "version = 3.10\n3.10 = \"x\""))
        XCTAssertEqual(shown.map(\.outcome), [.caveat(.versionLikeFloats(["version = 3.10"]))])
        XCTAssertTrue(shown[0].explanation.contains("trailing zero"))
        let keys = findings(block("toml", "3.10 = \"x\""))
        XCTAssertEqual(keys.map(\.outcome), [.caveat(.numericDottedKeys(["3.10"]))])
        XCTAssertTrue(keys[0].explanation.contains("nested tables"))
        XCTAssertEqual(findings(block("toml", "v = 3.10"), policy: .lenient), [])
        XCTAssertEqual(findings("TOML:\n" + block("toml", "v = 3.10"), policy: TOMLPolicy(reportsCaveats: false))
            .map(\.outcome), [.exact])
        let broken = findings(block("toml", "a = 1\na = 2"))
        XCTAssertEqual(broken.map(slip), [.duplicateKey])
        XCTAssertTrue(broken[0].explanation.hasPrefix("The block shown as TOML does not parse: a key defined twice"))
        let big = findings(block("toml", "n = 99999999999999999999"))
        XCTAssertEqual(big.map(\.outcome), [.unchecked("an integer beyond 64 bits")])
        XCTAssertEqual(big[0].explanation, "`n = 99999999999999999999` was not checked: an integer beyond 64 bits.")
        XCTAssertEqual(findings(block("toml", "a = 1\n]")).map(slip), [.notTOML])
    }

    func testReadingClaims() {
        let text = """
        About TOML values:
        `version = 3.10` is read as the string "3.10". `x = 1e3` is not an integer. `on` is a boolean.
        `flag = true` becomes `True`. `d = 2024-01-02` is a datetime. `t = 07:30:00` is a time.
        `n = 1000` is the number 1000. `f = 2.5` is the float 2.5. `s = "8080"` is an integer.
        `w = yes` is a boolean. `a = [1, 2]` is an array. `e = 1e3` is 1000. `q = 'x'` isn't a string.
        tomllib reads `p = 0o17` as 15. `z = "a"` is the string "b". `k = 5` is not read as the integer 5.
        `plain` is a word. `hello` is a string. `m = 3` is fine. `v = 1979-05-27T07:32:00Z` is an offset date-time.
        `c = 1.5` is `datetime.time`. `y = 2` is `int`. `b = True` is not a boolean.
        """
        let results = findings(text)
        let byKind = results.map { "\($0.claim.subject)|\($0.severity)" }
        XCTAssertEqual(byKind, [
            "version = 3.10|wrong", "x = 1e3|holds", "on|wrong", "flag = true|holds", "d = 2024-01-02|wrong",
            "t = 07:30:00|holds", "n = 1000|holds", "f = 2.5|holds", "s = \"8080\"|wrong", "w = yes|wrong",
            "e = 1e3|wrong", "q = 'x'|wrong", "p = 0o17|holds", "z = \"a\"|wrong", "k = 5|wrong",
            "v = 1979-05-27T07:32:00Z|holds", "c = 1.5|wrong", "y = 2|holds", "b = True|holds"
        ])
        XCTAssertEqual(results.map(slip), [
            .trailingZeroDropped, nil, .bareString, nil, nil, nil, nil, nil, .staysString, .bareString, .numberType,
            nil, nil, nil, nil, nil, nil, nil, nil
        ])
        XCTAssertTrue(results[0].explanation.contains("tomllib reads it as the float 3.1"))
        XCTAssertEqual(findings("TOML: `n = 99999999999999999999` is an integer.").map(\.outcome),
                       [.unchecked("an integer beyond 64 bits")])
        XCTAssertEqual(findings("TOML: `u = 1.0` is the integer 1.").map(slip), [.numberType])
        XCTAssertEqual(findings("TOML: `u = 1` is the string \"1\".").map(slip), [.unquotedNumber])
        XCTAssertEqual(findings("TOML: `when = 2024-01-02` is a string.").map(slip), [.dateParsed])
        XCTAssertEqual(findings("TOML: `ok = true` is a string.").map(slip), [nil])
        XCTAssertEqual(findings("TOML: `true` is a boolean.").map(\.outcome), [.exact])
        XCTAssertEqual(findings("TOML: `flag = true` is `true`.").map(\.outcome), [.exact])
        XCTAssertTrue(findings("TOML: `n = 1` is a 1.").isEmpty)
    }

    func testProseHelpers() {
        XCTAssertEqual(ProseReader.sentences(["One. Two `a. b` three!", "  "]), ["One.", "Two `a. b` three!"])
        XCTAssertNil(ProseReader.inlineTOML("`plain` words"))
        XCTAssertEqual(ReadingReader.clause("the float 3.1, which is wrong."), "the float 3.1")
        XCTAssertNil(ReadingReader.subject("[1, 2]"))
        XCTAssertNil(ObjectReader.target("nothing here"))
        XCTAssertEqual(ObjectReader.target("`str`"), .type(.string))
        XCTAssertEqual(ObjectReader.target("the date 2024-01-02"), .type(.date))
        XCTAssertEqual(ObjectReader.target("\u{201C}text\u{201D}"), .value(.string("text")))
        XCTAssertEqual(ObjectReader.target("the number 2.5"), .number(2.5))
        XCTAssertEqual(ObjectReader.target("a float 2"), .value(.float(2)))
        XCTAssertNil(ObjectReader.target("a boolean 7"))
        XCTAssertEqual(ObjectReader.literal("None"), .value(.null))
        XCTAssertEqual(ObjectReader.literal("'q'"), .value(.string("q")))
        XCTAssertEqual(ObjectReader.literal("false"), .value(.bool(false)))
        XCTAssertEqual(Expectation.Target.number(2).value, .float(2))
        XCTAssertEqual(Expectation.Target.type(.integer).value, .int(0))
        XCTAssertFalse(Expectation(target: .number(1), negated: false).matches(.string("1")))
        XCTAssertTrue(Expectation(target: .number(1), negated: false).matches(.float(1)))
        for type in TypeClass.allCases { XCTAssertTrue(type.contains(type.representative), type.rawValue) }
        XCTAssertEqual(AnswerBlocks.split("```py\nx\n").first?.kind, .code("py"))
    }
}
