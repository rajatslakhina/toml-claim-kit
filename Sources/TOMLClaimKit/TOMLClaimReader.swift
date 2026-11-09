/// Finds what an answer says about TOML: sentences that call a text valid or invalid TOML, blocks labeled
/// `toml`, sentences that say what a value reads as, and Python snippets that show what `tomllib` returns.
public struct TOMLClaimReader: Sendable {
    /// Whether a block labeled `toml` counts as a claim that its text is TOML.
    public let checksTOMLBlocks: Bool

    public init(checksTOMLBlocks: Bool = true) {
        self.checksTOMLBlocks = checksTOMLBlocks
    }

    public func claims(in text: String) -> [TOMLClaim] {
        let blocks = AnswerBlocks.split(text)
        let mentionsTOML = text.lowercased().contains("toml")
        let (stated, consumed) = mentionsTOML ? statedClaims(blocks) : ([:], [])
        var claims: [TOMLClaim] = []
        var context: String?
        for (index, block) in blocks.enumerated() {
            guard case let .code(tag) = block.kind else {
                claims += stated[index, default: []]
                claims += mentionsTOML ? ReadingReader.claims(in: block.lines) : []
                continue
            }
            if tag == "toml" {
                context = block.text
                guard checksTOMLBlocks, !consumed.contains(index), !block.text.trimmed.isEmpty else { continue }
                claims.append(Self.validity(block.text, true, explicit: false))
            } else if PythonReader.isPython(tag: tag, text: block.text) {
                claims += PythonReader.claims(in: block.lines, context: context)
            }
        }
        return claims
    }

    /// Claims made in sentences, by the prose block they are in, and the code blocks they are about.
    func statedClaims(_ blocks: [AnswerBlock]) -> ([Int: [TOMLClaim]], Set<Int>) {
        var stated: [Int: [TOMLClaim]] = [:]
        var consumed: Set<Int> = []
        for (index, block) in blocks.enumerated() where block.kind == .prose {
            let sentences = ProseReader.sentences(block.lines)
            for (position, sentence) in sentences.enumerated() {
                guard let claimsValid = ProseReader.statement(sentence) else { continue }
                if let inline = ProseReader.inlineTOML(sentence) {
                    stated[index, default: []].append(Self.validity(inline, claimsValid))
                    continue
                }
                let forward = ProseReader.pointsForward(sentence, isLast: position == sentences.count - 1)
                guard let target = Self.target(blocks, from: index, forward: forward, skipping: consumed) else {
                    continue
                }
                consumed.insert(target)
                stated[index, default: []].append(Self.validity(blocks[target].text, claimsValid))
            }
        }
        return (stated, consumed)
    }

    /// The code block a sentence is about: next to its prose block, on the side it points to, or else
    /// on the other side.
    static func target(_ blocks: [AnswerBlock], from index: Int, forward: Bool, skipping consumed: Set<Int>) -> Int? {
        let order = forward ? [index + 1, index - 1] : [index - 1, index + 1]
        return order.first { candidate in
            guard blocks.indices.contains(candidate), !consumed.contains(candidate),
                  case let .code(tag) = blocks[candidate].kind else { return false }
            return ProseReader.blockTags.contains(tag)
        }
    }

    static func validity(_ text: String, _ claimsValid: Bool, explicit: Bool = true) -> TOMLClaim {
        let claimed = explicit ? (claimsValid ? "valid TOML" : "not valid TOML") : "shown as TOML"
        return TOMLClaim(kind: .validity, subject: text, claimed: claimed, isExplicit: explicit,
                         task: .validate(claimsValid: claimsValid))
    }
}

/// Finds sentences that say a text is or is not TOML, and the text they are about.
enum ProseReader {
    static let negative = [
        "not valid toml", "isn't valid toml", "is invalid toml", "not a valid toml", "isn't a valid toml",
        "invalid toml", "not well-formed toml", "won't parse", "will not parse", "fails to parse", "fail to parse",
        "does not parse", "doesn't parse", "malformed toml", "is not toml", "isn't toml", "toml is not valid",
        "toml isn't valid", "toml is invalid", "won't load", "will not load", "fails to load", "toml syntax error"
    ]
    static let positive = [
        "valid toml", "well-formed toml", "will parse", "parses as toml", "parses cleanly", "parses fine",
        "proper toml", "legal toml", "parses without error", "loads without error", "loads fine", "toml is valid",
        "toml above is valid", "toml below is valid"
    ]
    static let blockTags: Set<String> = ["", "toml", "text"]

    /// Whether a sentence calls its text valid TOML (`true`), invalid (`false`), or neither; questions
    /// make no claim.
    static func statement(_ sentence: String) -> Bool? {
        let lower = sentence.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        guard !sentence.trimmed.hasSuffix("?") else { return nil }
        if negative.contains(where: lower.contains) { return false }
        return positive.contains(where: lower.contains) ? true : nil
    }

    static func sentences(_ lines: [String]) -> [String] {
        var sentences: [String] = []
        for line in lines {
            var current = ""
            let characters = Array(line)
            for (index, character) in characters.enumerated() {
                current.append(character)
                // A stop ends a sentence only before a space or the end of the line: `3.10` stays whole.
                let ends = index + 1 == characters.count || characters[index + 1].isWhitespace
                if ".!?".contains(character), ends, !insideCode(current) {
                    sentences.append(current)
                    current = ""
                }
            }
            if !current.trimmed.isEmpty { sentences.append(current) }
        }
        return sentences.map(\.trimmed).filter { !$0.isEmpty }
    }

    /// Whether the text so far ends inside an inline code span.
    static func insideCode(_ text: String) -> Bool {
        text.filter { $0 == "`" }.count % 2 == 1
    }

    static func spans(_ sentence: String) -> [String] {
        sentence.components(separatedBy: "`").enumerated().filter { $0.offset % 2 == 1 }.map(\.element)
    }

    /// An inline code span in the sentence that looks like TOML: `key = value` or a `[header]`.
    static func inlineTOML(_ sentence: String) -> String? {
        spans(sentence).first { span in
            span.contains("=") || (span.hasPrefix("[") && span.hasSuffix("]"))
        }
    }

    /// Whether the sentence points to the block after it rather than the one before it.
    static func pointsForward(_ sentence: String, isLast: Bool) -> Bool {
        let lower = sentence.lowercased()
        if lower.contains("above") || lower.contains("previous") { return false }
        if lower.contains("below") || lower.contains("following") { return true }
        return isLast && sentence.hasSuffix(":")
    }
}
