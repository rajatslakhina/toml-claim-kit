@testable import TOMLClaimKit
import XCTest

final class PythonTests: XCTestCase {
    let pyproject = block("toml", "[tool.poetry]\nname = \"app\"\nversion = \"0.1.0\"\n[tool.mypy]\npython_version = 3.10\n"
        + "released = 2024-01-02\nports = [80, 443]\nratio = 2.5")

    func check(_ snippet: String, tag: String = "python") -> [TOMLFinding] {
        findings(pyproject + "\n" + block(tag, snippet)).filter { $0.claim.kind == .loading }
    }

    func testFileModesAndCalls() {
        XCTAssertEqual(check("with open(\"p.toml\") as f:\n    d = tomllib.load(f)").map(slip), [.textMode])
        XCTAssertEqual(check("with open(\"p.toml\", \"rb\") as f:\n    d = tomllib.load(f)\nprint(d[\"tool\"][\"poetry\"][\"name\"])  # app")
            .map(\.outcome), [.exact])
        XCTAssertEqual(check("f = open(\"p.toml\", mode=\"r\")\nd = tomllib.load(f)").map(slip), [.textMode])
        XCTAssertEqual(check("with Path(\"p\").open(\"rb\") as f:\n    d = tomllib.load(f)\nd[\"tool\"][\"mypy\"][\"ratio\"]  # 2.5")
            .map(\.outcome), [.exact])
        XCTAssertEqual(check("d = tomllib.load(open(\"p.toml\"))").map(slip), [.textMode])
        XCTAssertEqual(check("d = tomllib.load(\"pyproject.toml\")").map(slip), [.pathArgument])
        XCTAssertEqual(check("path = \"p.toml\"\nd = tomllib.load(path)").map(slip), [.pathArgument])
        XCTAssertEqual(check("print(tomllib.dumps({}))").map(slip), [.noDumper])
        XCTAssertEqual(check("tomli.dump(d, f)  # writes the file").map(slip), [.noDumper])
        XCTAssertEqual(check("d = tomllib.load(unknown)\nd[\"tool\"][\"poetry\"][\"version\"]  # '0.1.0'").map(\.outcome),
                       [.exact])
        XCTAssertEqual(check("with open(\"p\") as f:\n    text = f.read()\nd = tomllib.loads(text)\nd[\"tool\"][\"mypy\"][\"ports\"]  # [80, 443]")
            .map(\.outcome), [.exact])
        XCTAssertEqual(check("with open(x) as f, other:\n    pass").count, 0)
        XCTAssertEqual(check("with lock:\n    pass").count, 0)
        XCTAssertEqual(check("tomllib.load(open(\"p.toml\"))  # TypeError: File must be opened in binary mode")
            .map(\.outcome), [.exact])
        let noBlock = findings(block("python", "import tomllib\nd = tomllib.load(open(\"x\", \"rb\"))\nd[\"a\"]  # 1"))
        XCTAssertTrue(noBlock.isEmpty)
        let raising = findings(block("", "import tomllib\nd = tomllib.load(open(\"x\"))"))
        XCTAssertEqual(raising.map(slip), [.textMode])
        XCTAssertEqual(raising[0].claim.claimed, "code that runs")
    }

    func testOutputsAndSlips() {
        let base = "with open(\"p.toml\", \"rb\") as f:\n    d = tomllib.load(f)\n"
        let cases: [(String, TOMLFinding.Slip?)] = [
            ("print(d[\"tool\"][\"mypy\"][\"python_version\"])  # 3.10", .trailingZeroDropped),
            ("d[\"tool\"][\"mypy\"][\"python_version\"]  # '3.10'", .trailingZeroDropped),
            ("type(d[\"tool\"][\"mypy\"][\"python_version\"])  # <class 'str'>", .trailingZeroDropped),
            ("type(d[\"tool\"][\"mypy\"][\"ratio\"])  # <class 'int'>", .numberType),
            ("type(d[\"tool\"][\"mypy\"][\"ratio\"])  # <class 'complex'>", nil),
            ("d[\"tool\"][\"mypy\"][\"released\"]  # '2024-01-02'", .dateParsed),
            ("print(d[\"tool\"][\"poetry\"][\"version\"])  # 1.0", .staysString),
            ("d[\"tool\"][\"mypy\"]  # {'python_version': '3.10'}", .trailingZeroDropped),
            ("d[\"tool\"][\"mypy\"][\"ports\"]  # [80, 8080]", nil),
            ("d[\"tool.mypy\"]  # {}", .dottedKeyLookup),
            ("d[\"tool\"][\"nope\"]  # 1", .raises),
            ("d[\"tool.nope\"]  # 1", .raises),
            ("d[\"tool\"][\"mypy\"][\"ports\"][5]  # 1", .raises),
            ("d[\"tool\"][\"mypy\"][\"ports\"][\"a\"]  # 1", .raises),
            ("d[\"tool\"][\"mypy\"][\"ratio\"][0]  # 1", .raises),
            ("d[\"tool\"][\"mypy\"][\"ratio\"].get(\"a\")  # 1", .raises),
            ("d[\"tool\"][\"poetry\"][\"name\"]  # KeyError: 'name'", .doesNotRaise),
            ("d[\"tool\"][\"nope\"]  # TypeError: no", nil),
            ("d[\"tool\"][\"mypy\"][\"ports\"]  # [80, 443, 1]", nil)
        ]
        for (line, expected) in cases {
            let result = check(base + line)
            XCTAssertEqual(result.count, 1, line)
            XCTAssertEqual(result.map(slip), [expected], line)
            XCTAssertEqual(result.first?.severity, .wrong, line)
            let sentence = result.first?.explanation ?? ""
            XCTAssertTrue(sentence.contains(" raises ") || sentence.contains(" gives ") || sentence.contains("does not"),
                          sentence)
        }
        let other = check(base + "print(d[\"tool\"][\"poetry\"][\"name\"])  # app-x")
        XCTAssertEqual(other.map(slip), [nil])
        XCTAssertEqual(other[0].explanation, "`print(d[\"tool\"][\"poetry\"][\"name\"])` gives app, not app-x.")
        let holds: [String] = [
            "d[\"tool\"][\"mypy\"].get(\"missing\", 7)  # 7", "d.get(\"tool\")[\"poetry\"][\"name\"]  # 'app'",
            "d[\"tool\"][\"mypy\"][\"ports\"][-1]  # 443", "type(d[\"tool\"][\"mypy\"][\"ratio\"])  # float",
            "d[\"tool\"][\"nope\"]  # KeyError: 'nope'", "d[\"tool\"][\"mypy\"][\"released\"]  # datetime.date(2024, 1, 2)",
            "d[\"tool\"][\"poetry\"]  # {\"version\": \"0.1.0\", \"name\": \"app\"}", "d.get(\"x\")  # None"
        ]
        for line in holds {
            XCTAssertEqual(check(base + line).first?.severity, .holds, line)
        }
        XCTAssertEqual(findings(pyproject + "\n" + block("python", base + "d[\"tool\"][\"poetry\"]  # {'version': '0.1.0', 'name': 'app'}"),
                                policy: .strict).last.map(slip), .some(nil))
        let raising = check(base + "d[\"tool\"][\"nope\"]  # 1")[0]
        XCTAssertTrue(raising.raises)
        XCTAssertTrue(raising.explanation.contains("raises KeyError: 'nope'; the answer shows 1"))
        let doesNot = check(base + "d[\"tool\"][\"poetry\"][\"name\"]  # KeyError: 'name'")[0]
        XCTAssertEqual(doesNot.explanation, "`d[\"tool\"][\"poetry\"][\"name\"]` does not raise: it gives 'app'.")
    }

    func testLoadsSnippetsAndRepl() {
        let continued = block("pycon", ">>> import tomllib\n>>> tomllib.loads(\n...     'a = 1'\n... )\n{'a': 2}")
        XCTAssertEqual(findings(continued).map(\.severity), [.wrong])
        let escaped = block("python", "import tomllib\ntomllib.loads('a = \"it\\'s\"')  # {'a': \"it's\"}")
        XCTAssertEqual(findings(escaped).map(\.severity), [.holds])
        let blank = block("python", "import tomllib, textwrap\ntomllib.loads(textwrap.dedent(\"   \"))  # {}")
        XCTAssertEqual(findings(blank).map(\.outcome), [.exact])
        let unbalanced = block("python", "import tomllib\ntomllib.loads('a = 1'")
        XCTAssertTrue(findings(unbalanced).isEmpty)
        XCTAssertEqual(PythonScanner.arguments("'a\\'b', \"c"), ["'a\\'b'", "\"c"])
        XCTAssertEqual(PythonScanner.skipString(Array("'abc"), from: 0), 4)
        let repl = block("pycon", ">>> import tomllib\n>>> tomllib.loads('a = 3.10')\n{'a': '3.10'}\n>>> tomllib.loads(\"b = 1\")['b']\n1")
        let results = findings(repl)
        XCTAssertEqual(results.map(\.severity), [.wrong, .holds])
        let script = block("python", "import tomllib, textwrap\ntext = textwrap.dedent(\"\"\"\n    a = 1\n    b = [\n      2,\n    ]\n    \"\"\")\n"
            + "data = tomllib.loads(text)\nprint(data)\n# Output: {'a': 1, 'b': [2]}\nprint(data[\"a\"])  # prints the a value")
        XCTAssertEqual(findings("TOML\n" + script).map(\.outcome), [.exact])
        let broken = block("python", "import tomllib\ntomllib.loads('a = hello')  # {'a': 'hello'}")
        XCTAssertEqual(findings(broken).map(slip), [.bareString])
        let decode = block("python", "import tomllib\ntomllib.loads('a = hello')  # raises tomllib.TOMLDecodeError")
        XCTAssertEqual(findings(decode).map(\.outcome), [.exact])
        let big = block("python", "import tomllib\ntomllib.loads('a = 99999999999999999999')  # {'a': 1}")
        XCTAssertEqual(findings(big).map(\.outcome), [.unchecked("an integer beyond 64 bits")])
        let empty = block("python", "import tomllib\ntomllib.loads()  # {}")
        XCTAssertTrue(findings(empty).isEmpty)
        let accessorJunk = block("python", "import tomllib\ntomllib.loads('a = 1').keys()  # ['a']")
        XCTAssertTrue(findings(accessorJunk).isEmpty)
        let unbound = block("python", "import tomllib\nprint(other[\"a\"])  # 1\nx == 2")
        XCTAssertTrue(findings(unbound).isEmpty)
    }

    func testRendering() {
        let time = TOMLTime(hour: 7, minute: 32, second: 5, microsecond: 0)
        XCTAssertEqual(TOMLValue.time(time).pythonRepr, "datetime.time(7, 32, 5)")
        XCTAssertEqual(TOMLValue.time(time).pythonStr, "07:32:05")
        XCTAssertEqual(TOMLValue.time(time).described, "the time 07:32:05")
        let stamp = TOMLDateTime(date: TOMLDate(year: 2024, month: 1, day: 2), time: time, offsetMinutes: 330)
        XCTAssertEqual(TOMLValue.dateTime(stamp).pythonStr, "2024-01-02 07:32:05+05:30")
        XCTAssertEqual(TOMLValue.dateTime(stamp).described, "the datetime 2024-01-02 07:32:05+05:30")
        XCTAssertEqual(TOMLValue.dateTime(stamp).pythonType, "datetime.datetime")
        let local = TOMLDateTime(date: TOMLDate(year: 2024, month: 1, day: 2), time: time)
        XCTAssertEqual(TOMLValue.dateTime(local).pythonStr, "2024-01-02 07:32:05")
        XCTAssertEqual(TOMLValue.time(time).pythonType, "datetime.time")
        XCTAssertEqual(TOMLValue.date(TOMLDate(year: 2024, month: 1, day: 2)).pythonType, "datetime.date")
        XCTAssertEqual(TOMLValue.null.pythonType, "NoneType")
        XCTAssertEqual(TOMLValue.null.described, "None")
        XCTAssertEqual(TOMLValue.bool(true).described, "the boolean true")
        XCTAssertEqual(TOMLValue.int(3).described, "the integer 3")
        XCTAssertEqual(TOMLValue.array([.int(1)]).described, "[1]")
        XCTAssertEqual(TOMLValue.array([]).pythonType, "list")
        XCTAssertEqual(TOMLValue.table([]).pythonType, "dict")
        XCTAssertEqual(TOMLValue.bool(false).pythonType, "bool")
        XCTAssertEqual(TOMLValue.string("it's").pythonRepr, "\"it's\"")
        XCTAssertEqual(TOMLValue.string("a'b\"c\r\u{01}").pythonRepr, "'a\\'b\"c\\r\\x01'")
        XCTAssertEqual(TOMLValue.float(-0.0).pythonRepr, "-0.0")
        XCTAssertEqual(TOMLValue.float(0.00012).pythonRepr, "0.00012")
        XCTAssertEqual(TOMLValue.float(1.5e300).pythonRepr, "1.5e+300")
        XCTAssertEqual(TOMLValue.float(-.infinity).pythonRepr, "-inf")
        XCTAssertFalse(TOMLValue.array([.int(1)]).same(.array([.int(2)])))
        XCTAssertTrue(TOMLValue.float(.nan).same(.float(.nan)))
        XCTAssertNil(TOMLValue.int(1).lookup(.string("a")))
    }

    func testPythonLiterals() {
        XCTAssertEqual(PythonLiteral.value("datetime.time(10, 30, 0, 5)"),
                       .time(TOMLTime(hour: 10, minute: 30, second: 0, microsecond: 5)))
        XCTAssertEqual(PythonLiteral.value("datetime.datetime(2024, 1, 2, 10, 30, tzinfo=datetime.timezone.utc)"),
                       .dateTime(TOMLDateTime(date: TOMLDate(year: 2024, month: 1, day: 2),
                                              time: TOMLTime(hour: 10, minute: 30, second: 0), offsetMinutes: 0)))
        let zone = "datetime.datetime(2024, 1, 2, 10, 30, tzinfo=datetime.timezone(datetime.timedelta(days=-1, seconds=84600)))"
        XCTAssertEqual(PythonLiteral.value(zone).map { TOMLValue.dateTime(TOMLDateTime(
            date: TOMLDate(year: 2024, month: 1, day: 2), time: TOMLTime(hour: 10, minute: 30, second: 0),
            offsetMinutes: -30)) == $0 }, true)
        XCTAssertNil(PythonLiteral.value("datetime.datetime(2024, 1, 2, 10, 30, tzinfo=pytz.utc)"))
        XCTAssertNil(PythonLiteral.value("datetime.datetime(2024, 1, 2, 10, 30, tzinfo=datetime.timezone(datetime.timedelta(3)))"))
        XCTAssertNil(PythonLiteral.value("datetime.date(2024, x, 2)"))
        XCTAssertNil(PythonLiteral.value("datetime.date(2024, 1)"))
        XCTAssertEqual(PythonLiteral.value("float('inf')"), .float(.infinity))
        XCTAssertEqual(PythonLiteral.value("-inf"), .float(-.infinity))
        XCTAssertEqual(PythonLiteral.value("r'a\\b'"), .string("a\\b"))
        XCTAssertEqual(PythonLiteral.value("'\\x41\\u00e9\\q'"), .string("A\u{e9}\\q"))
        XCTAssertEqual(PythonLiteral.value("(1, 2)"), .array([.int(1), .int(2)]))
        XCTAssertEqual(PythonLiteral.value("1_000"), .int(1000))
        XCTAssertNil(PythonLiteral.value("{1: 2}"))
        XCTAssertNil(PythonLiteral.value("[1 2]"))
        XCTAssertNil(PythonLiteral.value("{'a' 1}"))
        XCTAssertNil(PythonLiteral.value("'open"))
        XCTAssertNil(PythonLiteral.value("abc"))
        XCTAssertNil(PythonLiteral.value(""))
        XCTAssertNil(PythonLiteral.value("1 2"))
    }
}
