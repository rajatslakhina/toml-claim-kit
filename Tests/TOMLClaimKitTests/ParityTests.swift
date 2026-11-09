@testable import TOMLClaimKit
import XCTest

final class ParityTests: XCTestCase {
    /// Every text loads to what `tomllib` gives, rendered the way Python's `repr` shows it, and every text
    /// `tomllib` refuses is refused.
    func testParityWithTomllib() {
        var mismatches: [String] = []
        for (text, expected) in Parity.cases {
            let loaded: String? = switch TOMLValidator.load(text) {
            case let .value(value): value.pythonRepr
            default: nil
            }
            if loaded != expected {
                mismatches.append("\(text.debugDescription): got \(loaded ?? "an error"), want \(expected ?? "an error")")
            }
        }
        XCTAssertEqual(mismatches, [], mismatches.joined(separator: "\n"))
    }
}
