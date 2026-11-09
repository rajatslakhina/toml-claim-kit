@testable import TOMLClaimKit
import XCTest

final class ParserTests: XCTestCase {
    func testEveryProblemKindIsNamed() {
        let cases: [(String, TOMLProblem.Kind)] = [
            ("= 1", .invalidStatement), ("key with space = 1", .missingEquals), ("[]", .invalidKey),
            ("a.", .invalidKey), ("x =", .missingValue), ("x = hello", .bareString), ("x = True", .capitalizedBoolean),
            ("x = null", .noNull), ("x = 0755", .leadingZero), ("x = 1.2.3", .versionNumber), ("x = .5", .floatDot),
            ("x = 5.", .floatDot), ("x = 10:30", .dateFormat), ("x = 2023-02-30", .invalidDate),
            ("x = [,]", .invalidValue), ("x = +", .invalidValue), ("x = 1 y = 2", .textAfterValue),
            ("x = \"C:\\Users\"", .invalidEscape), ("x = \"a\u{01}\"", .controlCharacter),
            ("x = \"open", .unclosedString), ("x = [1 2]", .unclosedArray), ("x = [", .unclosedArray),
            ("x = {a = 1", .unclosedInlineTable), ("x = {", .unclosedInlineTable), ("x = {a = 1,}", .trailingComma),
            ("x = {a = 1,\n b = 2}", .newlineInInlineTable), ("[a", .unclosedHeader), ("[[a]", .unclosedHeader),
            ("a = 1\na = 2", .duplicateKey), ("[a]\n[a]", .tableRedefined), ("[a.b]\nc = 1\n[a]\nb.d = 2", .tableRedefined), ("a = []\n[[a]]", .immutable),
            ("a = {b = 1}\na.c = 2", .immutable), ("a = 1\n[[a]]", .duplicateKey), ("x = trueish", .bareString),
            ("x = {a = 1 b = 2}", .unclosedInlineTable), ("x = [0755]", .leadingZero)
        ]
        for (text, kind) in cases {
            XCTAssertEqual(refusal(text), kind, text.debugDescription)
        }
        XCTAssertEqual(Set(cases.map(\.1)), Set(TOMLProblem.Kind.allCases))
    }

    func testProblemPositionAndWording() {
        guard case let .invalid(problem) = TOMLValidator.validate("a = 1\nb = hello") else {
            return XCTFail("expected a refusal")
        }
        XCTAssertEqual(problem.line, 2)
        XCTAssertEqual(problem.column, 5)
        XCTAssertEqual(problem.what, "unquoted text where TOML needs a quoted string (hello)")
        XCTAssertEqual(problem.description, problem.what + " at line 2, column 5")
        let bare = TOMLProblem(kind: .unclosedHeader, line: 1, column: 3)
        XCTAssertEqual(bare.what, "a table header with no closing bracket")
    }

    func testValidatorResults() {
        XCTAssertEqual(TOMLValidator.validate("a = 1\nb = 2"), .valid(keys: 2))
        XCTAssertEqual(TOMLValidator.validate("x = 99999999999999999999"), .unsupported("an integer beyond 64 bits"))
        XCTAssertEqual(TOMLValidator.validate("x = 0xFFFFFFFFFFFFFFFFFF"), .unsupported("an integer beyond 64 bits"))
        XCTAssertEqual(TOMLValidator.load("x = 99999999999999999999"), .unsupported("an integer beyond 64 bits"))
        XCTAssertEqual(TOMLValidator.value("3.10"), .value(.float(3.1)))
        guard case let .error(message) = TOMLValidator.value("hello") else { return XCTFail("expected an error") }
        XCTAssertTrue(message.hasPrefix("tomllib.TOMLDecodeError: unquoted text"))
        XCTAssertEqual(TOMLValue.int(1).members, [])
    }

    func testRawTextAndCaveatsAreRecorded() throws {
        let document = try TOMLParser.parse("[[a]]\nv = 3.10\n[b]\n3.10 = \"x\"\nn = 2.0\n")
        XCTAssertEqual(document.raws[[.key("a"), .index(0), .key("v")]], "3.10")
        XCTAssertEqual(document.versionLikeFloats, ["v = 3.10"])
        XCTAssertEqual(document.numericDottedKeys, ["3.10"])
    }

    func testFlagsAndTree() {
        let flags = Flags()
        XCTAssertFalse(flags.isSet([], .frozen))
        flags.unsetAll(["missing", "child"])
        flags.set(["a"], .frozen, recursive: true)
        XCTAssertTrue(flags.isSet(["a", "b"], .frozen))
        XCTAssertFalse(flags.isSet(["c", "d"], .frozen))
        XCTAssertEqual(Entry.value(.int(1)).value, .int(1))
        XCTAssertEqual(Entry.tables([TableBox()]).value, .array([.table([])]))
    }
}
