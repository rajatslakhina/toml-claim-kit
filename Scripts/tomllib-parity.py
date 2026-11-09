#!/usr/bin/env python3
"""Writes Tests/TOMLClaimKitTests/Parity.swift from Python's own tomllib.

Run from the package root: python3 -I Scripts/tomllib-parity.py > Tests/TOMLClaimKitTests/Parity.swift
"""
import sys
import tomllib

CASES = [
 # scalars
 'x = 1', 'x = +1', 'x = -0', 'x = 0', 'x = 00', 'x = 01', 'x = 0755', 'x = 0o755', 'x = 0xFF', 'x = 0xff_ff',
 'x = 0b101', 'x = 0x', 'x = -0x1', 'x = 1_000', 'x = 1__000', 'x = 1_', 'x = _1', 'x = 9223372036854775807',
 'x = 3.10', 'x = 1.0', 'x = -0.0', 'x = 0.1_0', 'x = 1e3', 'x = 1E+3', 'x = 1e-05', 'x = 1e1_0', 'x = 0e0',
 'x = 1e16', 'x = 1e15', 'x = 123456789.125', 'x = 6.02e23', 'x = .5', 'x = 5.', 'x = 1.2.3', 'x = 1.e3',
 'x = inf', 'x = +inf', 'x = -inf', 'x = nan', 'x = -nan', 'x = Inf', 'x = true', 'x = false', 'x = True',
 'x = TRUE', 'x = null', 'x = ~', 'x = None', 'x = hello', 'x =', 'x = 1 y = 2', 'x = 1 # c', 'x=1#c',
 # strings
 'x = "a"', "x = 'a'", 'x = ""', 'x = "tab\there"', 'x = "a\\tb"', 'x = "q\\"q"', 'x = "\\u00e9"',
 'x = "\\U0001F600"', 'x = "\\ud800"', 'x = "C:\\Users"', "x = 'C:\\Users'", 'x = "\\e"', 'x = "\\x41"',
 'x = "open', "x = 'open", 'x = "a\nb"', 'x = """\nhello"""', 'x = """a\\\n   b"""', 'x = """a""""',
 'x = """a"""""', "x = '''a''''", "x = '''\nraw\\n'''", 'x = """\n  one\n  two\n"""', 'x = """a\\ \n b"""',
 "x = 'it''s'", 'x = "it\'s"',
 # dates
 'x = 2024-01-02', 'x = 2024-1-2', 'x = 2023-02-30', 'x = 2024-02-29', 'x = 10:30:00', 'x = 10:30',
 'x = 07:32:00.123456789', 'x = 07:32:00.5', 'x = 2024-01-02T10:30:00', 'x = 2024-01-02 10:30:00',
 'x = 2024-01-02t10:30:00z', 'x = 2024-01-02T10:30:00Z', 'x = 2024-01-02T10:30:00+05:30',
 'x = 1979-05-27T00:32:00.999999-07:00', 'x = 2024-01-02T10:30', 'x = 24:00:00',
 # arrays / inline tables
 'x = []', 'x = [ ]', 'x = [1, 2]', 'x = [1,2,]', 'x = [1 2]', 'x = [\n1,\n# c\n2,\n]', 'x = [1, "a", [2]]',
 'x = [,]', 'x = {}', 'x = {a = 1}', 'x = {a = 1,}', 'x = {a = 1,\n b = 2}', 'x = { a.b = 1, a.c = 2 }',
 'x = { a = 1, a = 2 }', 'x = {a = {b = 1}, a.c = 2}', 'x = [{a = 1}, {a = 2}]', 'x = {a = [1]}',
 # keys
 '"quoted key" = 1', '"" = 1', "'lit' = 1", 'a."b.c" = 1', 'a . b = 1', '3.10 = "x"', 'key with space = 1',
 'a-b_c = 1', '1234 = 1', '= 1', 'a.b.c = 1\na.b.d = 2', 'a.b = 1\na.b.c = 2', 'a = 1\na = 2', 'a = 1\nA = 2',
 # tables
 '[a]\nx = 1\n[a]\ny = 2', '[a.b]\nc = 1\n[a]\nd = 2', '[a]\nb = 1\n[a.b]', 'a = 1\n[a]', 'a.b = 1\n[a]\nc = 2',
 '[a]\nx.y = 1\n[a.x]', '[a]\nx.y = 1\n[a.x.z]\nw = 1', 'a = {b = 1}\n[a.c]\nd = 1', 'a = []\n[[a]]',
 '[[a]]\nb = 1\n[[a]]\nb = 2', '[a]\n[[a]]', '[[a]]\n[a]', '[[a]]\nb = 1\n[a.c]\nd = 2', '[[a.b]]\n[a]\nc = 1',
 '[ a . b ]\nc = 1', '["a b"]\nc = 1', '[a]]', '[a', '[[a]', '[]', '[a]\n\n# c\nb = 1\n\n[c]\nd = 2',
 '[x]\n[x.y]\n[x.y.z]\nw = 1', '[[fruit]]\nname = "apple"\n[fruit.physical]\ncolor = "red"\n[[fruit.variety]]\nname = "red"\n[[fruit]]\nname = "banana"',
 # whole documents
 '', '   ', '# only a comment', '\n\n', 'x = 1\n', '\tx\t=\t1', 'x = 1\r\ny = 2',
 '[project]\nname = "demo"\nversion = "0.1.0"\nrequires-python = ">=3.10"\ndependencies = [\n  "requests>=2.31",\n]\n\n[tool.mypy]\npython_version = 3.10\n',
 '[tool.poetry]\nname = "x"\n[tool.poetry.dependencies]\npython = "^3.10"\n',
 '[tool.poetry]\nname = "x"\n[tool.poetry.dependencies]\npython = ^3.10\n',
]
CASES += [
 'x = 1e400', 'x = "\\', 'x = """a\\ b"""', 'x = """a\\  \n  b"""', 'x = "a\x01"', 'x = 1 # bell \x07', '[a.]', 'a.', 'x = [1,',
 'x = [', 'x = {', 'x = {a = 1', 'x = {a = 1 b = 2}', 'x = {\n}', 'x = 0o8', 'x = 0000-01-01', 'x = 2024-01-02T10:30:00.123+01:00',
 'x = 2024-01-02T10:30:00-00:30', 'x = 2024-01-02 # date', 'x = {a = 1, b.c = 2, b.d = 3}', 'x = {a.b = 1, a = 2}',
 'x = {a = 1, a.b = 2}', 'a = {b = 1}\na.c = 2', '[a]\nb.c = 1\n[a.b.d]\ne = 1', 'x = trueish', 'x = true false',
 'x = [0755]', 'x = [1 # c\n]', "x = 'a\x01'", "x = '''a\x01'''", "x = '''open", 'x = """open', 'x = "\\U00110000"',
 'x = "\\u12"', 'x = "\\uZZZZ"', 'x = """\\\n\n  b"""', "x = 'line\nbreak'", 'x = "a\x7f"', '"a\nb" = 1', 'x = [1, 2, [3, [4]]]',
 'x = {a = {b = {c = 1}}}', 'x = 2024-02-30', 'x = 1900-02-29', 'x = 2000-02-29', 'x = 10:30:00Z', 'x = +0', 'x = 0.0',
 'x = 1e+16', 'x = 0.0001', 'x = 0.00001', 'x = 12345678901234567.0', 'x = 3.14159', 'x = 5e-324', 'x = 1.7976931348623157e308',
 'x = "\\b\\f\\r\\n\\t\\"\\\\"', 'x = "é😀"', '﻿x = 1', 'x = 1\n[a]\n', '[a]\n[a.b]\n[a.b.c]\n[a.b]',
 'name = "x"\ntags = ["a", "b"]\n[owner]\nname = "y"\ndob = 1979-05-27T07:32:00-08:00',
]

def lit(s):
    out = []
    for ch in s:
        if ch == '\\': out.append('\\\\')
        elif ch == '"': out.append('\\"')
        elif ch == '\n': out.append('\\n')
        elif ch == '\t': out.append('\\t')
        elif ch == '\r': out.append('\\r')
        elif ord(ch) < 0x20 or ord(ch) == 0x7f or ord(ch) > 0x7e: out.append('\\u{%x}' % ord(ch))
        else: out.append(ch)
    return '"' + ''.join(out) + '"'
lines = []
seen = set()
for c in CASES:
    if c in seen: continue
    seen.add(c)
    try:
        exp = lit(repr(tomllib.loads(c)))
    except Exception:
        exp = 'nil'
    lines.append(f'        ({lit(c)}, {exp}),')
print('// Generated from Python 3.14 `tomllib.loads` on this Mac: each text, and `repr` of what it returns, or')
print('// `nil` where it raises `TOMLDecodeError`. Regenerate: python3 -I Scripts/tomllib-parity.py > Tests/TOMLClaimKitTests/Parity.swift')
print('enum Parity {')
print('    static let cases: [(String, String?)] = [')
print('\n'.join(lines))
print('    ]')
print('}')
print(len(lines), file=sys.stderr)
