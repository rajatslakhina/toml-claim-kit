import TOMLClaimKit

print("TOMLClaimKit demo: checking what LLM answers say about TOML")
print("Each block is parsed and each snippet run as Python's tomllib (TOML 1.0) would.")

let checker = TOMLClaimChecker()
let pairs: [Scenario] = [
    Scenario(title: "python_version = 3.10 in pyproject.toml, said to stay \"3.10\"", answer: Scenarios.mypy,
             rewrite: Scenarios.mypyFixed),
    Scenario(title: "tomllib.load on a text-mode file, and a dotted key looked up whole",
             answer: Scenarios.textMode, rewrite: Scenarios.textModeFixed),
    Scenario(title: "Poetry dependencies with a bare version and True", answer: Scenarios.poetry,
             rewrite: Scenarios.poetryFixed),
    Scenario(title: "A table declared twice, a repeated key, and tomllib.dumps", answer: Scenarios.tables,
             rewrite: Scenarios.tablesFixed)
]
for (number, scenario) in pairs.enumerated() {
    Printer.scenario(number + 1, scenario.title)
    let report = checker.check(scenario.answer)
    Printer.show(report, label: "answer")
    if number == 0, let feedback = report.feedback {
        print("    feedback sent back to the model:")
        for line in feedback.split(separator: "\n") { print("      | \(line)") }
    }
    Printer.show(checker.check(scenario.rewrite), label: "rewrite")
}

Printer.scenario(5, "What values read as: six sentences, three of them wrong")
Printer.show(checker.check(Scenarios.readings), label: "answer")
Printer.show(TOMLClaimChecker(policy: .lenient).check(Scenarios.poetry), label: "lenient policy, same Poetry answer")

Printer.scenario(6, "A conversation: the same wrong claim after a correction was asked for")
let ledger = TOMLLedger()
let first = await ledger.review(Scenarios.mypy)
print("    turn 1: \(first.summary)")
let second = await ledger.review(Scenarios.mypy)
print("    turn 2: \(second.summary)")
if let note = second.note { print("    note: \(note)") }
let stats = await ledger.statistics
print("    ledger: \(stats.reviews) reviews, \(stats.claims) claims, \(stats.flagged) flagged, "
      + "\(stats.repeated) repeated")

print("")
print("Validator on its own:")
for text in ["version = 1.2.3", "path = \"C:\\Users\\me\"", "a = {b = 1,}", "when = 1979-05-27T07:32:00-08:00"] {
    print("    \(text.debugDescription) -> \(TOMLValidator.validate(text))")
    switch TOMLValidator.load(text) {
    case let .value(value): print("      tomllib.loads: \(value.pythonRepr)")
    case let .error(message): print("      tomllib.loads raises \(message)")
    case let .unsupported(reason): print("      not checked: \(reason)")
    }
}
